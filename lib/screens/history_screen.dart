import 'dart:math' as math;
import 'dart:isolate';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/merged_record.dart';
import '../services/database_service.dart';
import '../models/train_record.dart';
import '../services/merge_service.dart';
import '../models/map_state.dart';
import '../services/map_state_service.dart';

class HistoryScreen extends StatefulWidget {
  final Function(bool isEditing) onEditModeChanged;
  final Function() onSelectionChanged;

  const HistoryScreen({
    super.key,
    required this.onEditModeChanged,
    required this.onSelectionChanged,
  });

  @override
  HistoryScreenState createState() => HistoryScreenState();
}

class HistoryScreenState extends State<HistoryScreen> {
  static const double _smallMapMinZoom = 2.0;
  static const double _smallMapMaxZoom = 18.0;
  static const double _singlePointMapZoom = 17.0;

  final List<Object> _displayItems = [];
  bool _isLoading = true;
  bool _isEditMode = false;
  final Set<String> _selectedRecords = {};
  final Map<String, bool> _expandedStates = {};
  late final ScrollController _scrollController;
  bool _isAtTop = true;
  final GlobalKey _listViewportKey = GlobalKey();
  final Map<String, GlobalKey> _itemKeys = {};
  _RenderViewportAnchor? _pendingRenderViewportAnchor;
  MergeSettings _mergeSettings = MergeSettings();

  final Map<String, double> _mapOptimalZoom = {};
  final Map<String, bool> _mapCalculating = {};

  int getSelectedCount() => _selectedRecords.length;
  Set<String> getSelectedRecordIds() => _selectedRecords;
  List<Object> getDisplayItems() => _displayItems;
  void clearSelection() => setState(() => _selectedRecords.clear());

  void setEditMode(bool isEditing) {
    setState(() {
      _isEditMode = isEditing;
      widget.onEditModeChanged(isEditing);
      if (!isEditing) {
        _selectedRecords.clear();
      }
    });
  }

  Future<void> reloadRecords() async {
    await loadRecords(scrollToTop: false);
  }

  bool get _isViewingLatest {
    if (!_scrollController.hasClients) return true;
    return _scrollController.position.pixels <= 2.0;
  }

  String _displayItemKey(Object item) {
    if (item is MergedTrainRecord) {
      return 'group:${item.groupKey}';
    }
    return 'record:${(item as TrainRecord).uniqueId}';
  }

  Set<String> _displayItemRecordIds(Object item) {
    if (item is MergedTrainRecord) {
      return item.records.map((record) => record.uniqueId).toSet();
    }
    return {(item as TrainRecord).uniqueId};
  }

  List<Set<String>> _expandedRecordIdGroups() {
    final groups = <Set<String>>[];
    for (final item in _displayItems) {
      final key = _displayItemKey(item);
      if (_expandedStates[key] == true) {
        groups.add(_displayItemRecordIds(item));
      }
    }
    return groups;
  }

  void _restoreExpandedStates(List<Set<String>> expandedRecordIdGroups) {
    final nextStates = <String, bool>{};
    for (final item in _displayItems) {
      final recordIds = _displayItemRecordIds(item);
      final shouldExpand = expandedRecordIdGroups.any(
        (expandedIds) => expandedIds.intersection(recordIds).isNotEmpty,
      );
      if (shouldExpand) {
        nextStates[_displayItemKey(item)] = true;
      }
    }

    _expandedStates
      ..clear()
      ..addAll(nextStates);
  }

  GlobalKey _keyForDisplayItem(Object item) {
    final key = _displayItemKey(item);
    return _itemKeys.putIfAbsent(key, GlobalKey.new);
  }

  _RenderViewportAnchor? _currentRenderViewportAnchor() {
    final viewportContext = _listViewportKey.currentContext;
    if (viewportContext == null || !_scrollController.hasClients) {
      return null;
    }

    final viewportBox = viewportContext.findRenderObject() as RenderBox?;
    if (viewportBox == null || !viewportBox.hasSize) {
      return null;
    }
    final viewportTop = viewportBox.localToGlobal(Offset.zero).dy;

    _RenderViewportAnchor? firstVisible;
    for (final item in _displayItems) {
      final itemKey = _displayItemKey(item);
      final context = _itemKeys[itemKey]?.currentContext;
      if (context == null) continue;

      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;

      final dy = box.localToGlobal(Offset.zero).dy - viewportTop;
      final bottom = dy + box.size.height;
      if (bottom <= 0 || dy >= viewportBox.size.height) continue;

      final anchor = _RenderViewportAnchor(
        itemKey: itemKey,
        recordIds: _displayItemRecordIds(item),
        dy: dy,
      );

      if (dy <= 0 && bottom > 0) {
        return anchor;
      }
      firstVisible ??= anchor;
    }

    return firstVisible;
  }

  String? _fallbackItemKeyForAnchor(_RenderViewportAnchor anchor) {
    for (final item in _displayItems) {
      final recordIds = _displayItemRecordIds(item);
      if (recordIds.intersection(anchor.recordIds).isNotEmpty) {
        return _displayItemKey(item);
      }
    }
    return null;
  }

  void _queueRenderViewportAnchorRestore(_RenderViewportAnchor? anchor) {
    if (anchor == null) return;
    _pendingRenderViewportAnchor = anchor;
  }

  bool _applyPendingRenderViewportAnchorCorrection() {
    final anchor = _pendingRenderViewportAnchor;
    _pendingRenderViewportAnchor = null;
    if (anchor == null || !mounted || !_scrollController.hasClients) {
      return false;
    }

    final viewportContext = _listViewportKey.currentContext;
    final viewportBox = viewportContext?.findRenderObject() as RenderBox?;
    if (viewportBox == null || !viewportBox.hasSize) return false;
    final viewportTop = viewportBox.localToGlobal(Offset.zero).dy;

    final itemKey = _itemKeys[anchor.itemKey]?.currentContext == null
        ? _fallbackItemKeyForAnchor(anchor)
        : anchor.itemKey;
    if (itemKey == null) return false;

    final itemContext = _itemKeys[itemKey]?.currentContext;
    final itemBox = itemContext?.findRenderObject() as RenderBox?;
    if (itemBox == null || !itemBox.hasSize) return false;

    final newDy = itemBox.localToGlobal(Offset.zero).dy - viewportTop;
    final delta = newDy - anchor.dy;
    if (delta.abs() <= 0.5) return false;

    final position = _scrollController.position;
    final targetPixels = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    final correction = targetPixels - position.pixels;
    if (correction.abs() <= 0.5) return false;

    position.correctBy(correction);
    return true;
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController(keepScrollOffset: false);
    _scrollController.addListener(() {
      if (_scrollController.position.atEdge) {
        if (_scrollController.position.pixels == 0) {
          if (!_isAtTop) {
            setState(() => _isAtTop = true);
          }
        } else if (_scrollController.position.pixels ==
            _scrollController.position.maxScrollExtent) {
          if (_isAtTop) {
            setState(() => _isAtTop = false);
          }
        }
      } else {
        if (_isAtTop) {
          setState(() => _isAtTop = false);
        }
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        loadRecords(scrollToTop: true);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> loadRecords({bool scrollToTop = true}) async {
    final renderAnchor =
        scrollToTop || _isViewingLatest ? null : _currentRenderViewportAnchor();

    try {
      final allRecords = await DatabaseService.instance.getAllRecords();
      final settingsMap = await DatabaseService.instance.getAllSettings() ?? {};
      _mergeSettings = MergeSettings.fromMap(settingsMap);

      List<TrainRecord> filteredRecords = allRecords;
      if ((settingsMap['hideTimeOnlyRecords'] ?? 0) == 1) {
        filteredRecords = allRecords.where((record) {
          bool isFieldMeaningful(String field) {
            if (field.isEmpty) {
              return false;
            }
            String cleaned = field.replaceAll('<NUL>', '').trim();
            if (cleaned.isEmpty) {
              return false;
            }
            if (cleaned.runes
                .every((r) => r == '*'.runes.first || r == ' '.runes.first)) {
              return false;
            }
            return true;
          }

          final hasTrainNumber = isFieldMeaningful(record.fullTrainNumber) &&
              !record.fullTrainNumber.contains("-----");

          final hasDirection = record.direction == 1 || record.direction == 3;

          final hasLocoInfo = isFieldMeaningful(record.locoType) ||
              isFieldMeaningful(record.loco);

          final hasRoute = isFieldMeaningful(record.route);

          final hasPosition = isFieldMeaningful(record.position);

          final hasSpeed =
              isFieldMeaningful(record.speed) && record.speed != "NUL";

          final hasPositionInfo = isFieldMeaningful(record.positionInfo);

          final hasTrainType =
              isFieldMeaningful(record.trainType) && record.trainType != "未知";

          final hasLbjClass =
              isFieldMeaningful(record.lbjClass) && record.lbjClass != "NA";

          final hasTrain = isFieldMeaningful(record.train) &&
              !record.train.contains("-----");

          final shouldShow = hasTrainNumber ||
              hasDirection ||
              hasLocoInfo ||
              hasRoute ||
              hasPosition ||
              hasSpeed ||
              hasPositionInfo ||
              hasTrainType ||
              hasLbjClass ||
              hasTrain;

          return shouldShow;
        }).toList();
      }

      final items = MergeService.getMixedList(filteredRecords, _mergeSettings);

      if (mounted) {
        final hasDataChanged = _hasDataChanged(items);

        if (hasDataChanged) {
          final expandedRecordIdGroups = _expandedRecordIdGroups();
          final shouldRevealAfterJump = _isLoading && scrollToTop;
          setState(() {
            _displayItems
              ..clear()
              ..addAll(items);
            _restoreExpandedStates(expandedRecordIdGroups);
            if (!shouldRevealAfterJump) {
              _isLoading = false;
            }
          });

          if (scrollToTop) {
            if (shouldRevealAfterJump) {
              setState(() {
                _isLoading = false;
                _isAtTop = true;
              });
            }
          } else {
            _queueRenderViewportAnchorRestore(renderAnchor);
          }
        } else {
          if (_isLoading) {
            setState(() => _isLoading = false);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> addNewRecord(TrainRecord newRecord) async {
    try {
      final isNewRecord = !_displayItems.any((item) {
        if (item is TrainRecord) {
          return item.uniqueId == newRecord.uniqueId;
        } else if (item is MergedTrainRecord) {
          return item.records.any((r) => r.uniqueId == newRecord.uniqueId);
        }
        return false;
      });
      if (!isNewRecord) return;

      if (mounted) {
        final renderAnchor =
            _isViewingLatest ? null : _currentRenderViewportAnchor();
        List<TrainRecord> allRecords = [];
        Set<String> selectedRecordIds = {};

        for (final item in _displayItems) {
          if (item is MergedTrainRecord) {
            allRecords.addAll(item.records);
            if (item.records
                .any((r) => _selectedRecords.contains(r.uniqueId))) {
              selectedRecordIds.addAll(item.records.map((r) => r.uniqueId));
            }
          } else if (item is TrainRecord) {
            allRecords.add(item);
            if (_selectedRecords.contains(item.uniqueId)) {
              selectedRecordIds.add(item.uniqueId);
            }
          }
        }

        allRecords.insert(0, newRecord);
        final mergedItems =
            MergeService.getMixedList(allRecords, _mergeSettings);
        final expandedRecordIdGroups = _expandedRecordIdGroups();

        setState(() {
          _displayItems
            ..clear()
            ..addAll(mergedItems);
          _restoreExpandedStates(expandedRecordIdGroups);

          _selectedRecords.clear();
          for (final item in _displayItems) {
            if (item is MergedTrainRecord) {
              if (item.records
                  .any((r) => selectedRecordIds.contains(r.uniqueId))) {
                _selectedRecords.addAll(item.records.map((r) => r.uniqueId));
              }
            } else if (item is TrainRecord &&
                selectedRecordIds.contains(item.uniqueId)) {
              _selectedRecords.add(item.uniqueId);
            }
          }
        });

        _queueRenderViewportAnchorRestore(renderAnchor);
      }
    // ignore: empty_catches
    } catch (e) {}
  }

  bool _hasDataChanged(List<Object> newItems) {
    if (_displayItems.length != newItems.length) return true;

    for (int i = 0; i < _displayItems.length; i++) {
      final oldItem = _displayItems[i];
      final newItem = newItems[i];

      if (oldItem.runtimeType != newItem.runtimeType) return true;

      if (oldItem is TrainRecord && newItem is TrainRecord) {
        if (oldItem.uniqueId != newItem.uniqueId) return true;
      } else if (oldItem is MergedTrainRecord && newItem is MergedTrainRecord) {
        if (oldItem.groupKey != newItem.groupKey) return true;
        if (oldItem.records.length != newItem.records.length) return true;
        final oldIds = oldItem.records.map((record) => record.uniqueId);
        final newIds = newItem.records.map((record) => record.uniqueId);
        if (!_sameOrderedIds(oldIds, newIds)) return true;
      }
    }
    return false;
  }

  bool _sameOrderedIds(Iterable<String> a, Iterable<String> b) {
    final aIterator = a.iterator;
    final bIterator = b.iterator;
    while (true) {
      final aHasNext = aIterator.moveNext();
      final bHasNext = bIterator.moveNext();
      if (aHasNext != bHasNext) return false;
      if (!aHasNext) return true;
      if (aIterator.current != bIterator.current) return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _displayItems.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_displayItems.isEmpty) {
      return const Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.history, size: 64, color: Colors.grey),
        SizedBox(height: 16),
        Text('暂无记录', style: TextStyle(color: Colors.white, fontSize: 18))
      ]));
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          ignoring: _isLoading,
          child: Opacity(
            opacity: _isLoading ? 0 : 1,
            child: _buildHistoryListView(),
          ),
        ),
        if (_isLoading) const Center(child: CircularProgressIndicator()),
      ],
    );
  }

  Widget _buildHistoryListView() {
    return _ViewportAnchorRestorer(
      onAfterLayout: _applyPendingRenderViewportAnchorCorrection,
      child: ListView.builder(
        key: _listViewportKey,
        controller: _scrollController,
        padding: const EdgeInsets.all(16.0),
        cacheExtent: 800,
        itemCount: _displayItems.length,
        itemBuilder: (context, index) {
          final item = _displayItems[index];
          if (item is MergedTrainRecord) {
            return RepaintBoundary(
              key: _keyForDisplayItem(item),
              child: _buildMergedRecordCard(item),
            );
          } else if (item is TrainRecord) {
            return RepaintBoundary(
              key: _keyForDisplayItem(item),
              child: _buildRecordCard(item, key: ValueKey(item.uniqueId)),
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildMergedRecordCard(MergedTrainRecord mergedRecord) {
    final bool isSelected =
        mergedRecord.records.any((r) => _selectedRecords.contains(r.uniqueId));
    final itemKey = _displayItemKey(mergedRecord);
    final isExpanded = _expandedStates[itemKey] ?? false;
    return Card(
        key: ValueKey(mergedRecord.groupKey),
        color: isSelected && _isEditMode
            ? const Color(0xFF2E2E2E)
            : const Color(0xFF1E1E1E),
        elevation: 1,
        margin: const EdgeInsets.only(bottom: 8.0),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.0),
            side: BorderSide(
                color: isSelected && _isEditMode
                    ? Colors.white
                    : Colors.transparent,
                width: 2.0)),
        child: InkWell(
            borderRadius: BorderRadius.circular(8.0),
            onTap: () {
              if (_isEditMode) {
                setState(() {
                  final allIdsInGroup =
                      mergedRecord.records.map((r) => r.uniqueId).toSet();
                  if (isSelected) {
                    _selectedRecords.removeAll(allIdsInGroup);
                  } else {
                    _selectedRecords.addAll(allIdsInGroup);
                  }
                  widget.onSelectionChanged();
                });
              } else {
                setState(() {
                  _expandedStates[itemKey] = !isExpanded;
                });
              }
            },
            onLongPress: () {
              if (!_isEditMode) {
                setEditMode(true);
              }
              setState(() {
                final allIdsInGroup =
                    mergedRecord.records.map((r) => r.uniqueId).toSet();
                _selectedRecords.addAll(allIdsInGroup);
                widget.onSelectionChanged();
              });
            },
            child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildRecordHeader(mergedRecord.latestRecord,
                          isMerged: true),
                      _buildPositionAndSpeed(mergedRecord.latestRecord),
                      _buildLocoInfo(mergedRecord.latestRecord),
                      if (isExpanded) _buildMergedExpandedContent(mergedRecord),
                    ]))));
  }

  Widget _buildMergedExpandedContent(MergedTrainRecord mergedRecord) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildExpandedMapForAll(mergedRecord.records, mergedRecord.groupKey),
        const SizedBox(height: 12),
        ...mergedRecord.records.map(
          (record) => _buildSubRecordItem(
            record,
            mergedRecord.latestRecord,
            _mergeSettings.groupBy,
          ),
        ),
      ],
    );
  }

  Widget _buildSubRecordItem(
      TrainRecord record, TrainRecord latest, GroupBy groupBy) {
    String differingInfo = _getDifferingInfo(record, latest, groupBy);
    String locationInfo = _getLocationInfo(record);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, top: 4.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                record.receivedTimestamp.toString().split('.')[0],
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              if (differingInfo.isNotEmpty)
                Text(
                  differingInfo,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  locationInfo,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                record.speed.isNotEmpty ? "${record.speed} km/h" : "",
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatLocoInfo(TrainRecord record) {
    final locoType = record.locoType.trim();
    final loco = record.loco.trim();

    if (locoType.isNotEmpty && loco.isNotEmpty) {
      final shortLoco =
          loco.length > 5 ? loco.substring(loco.length - 5) : loco;
      return "$locoType-$shortLoco";
    } else if (locoType.isNotEmpty) {
      return locoType;
    } else if (loco.isNotEmpty) {
      return loco;
    }
    return "";
  }

  String _getDifferingInfo(
      TrainRecord record, TrainRecord latest, GroupBy groupBy) {
    final train = record.train.trim();
    final loco = record.loco.trim();
    final latestTrain = latest.train.trim();
    final latestLoco = latest.loco.trim();

    switch (groupBy) {
      case GroupBy.trainOnly:
        if (loco != latestLoco && loco.isNotEmpty) {
          return _formatLocoInfo(record);
        }
        return "";
      case GroupBy.locoOnly:
        return train != latestTrain && train.isNotEmpty ? train : "";
      case GroupBy.trainOrLoco:
        final trainDiff = train.isNotEmpty && train != latestTrain ? train : "";
        final locoDiff = loco.isNotEmpty && loco != latestLoco
            ? _formatLocoInfo(record)
            : "";

        if (trainDiff.isNotEmpty && locoDiff.isNotEmpty) {
          return "$trainDiff $locoDiff";
        } else if (trainDiff.isNotEmpty) {
          return trainDiff;
        } else if (locoDiff.isNotEmpty) {
          return locoDiff;
        }
        return "";
      case GroupBy.trainAndLoco:
        if (train.isNotEmpty && train != latestTrain) {
          final locoInfo = _formatLocoInfo(record);
          if (locoInfo.isNotEmpty) {
            return "$train $locoInfo";
          }
          return train;
        }
        if (loco.isNotEmpty && loco != latestLoco) {
          return _formatLocoInfo(record);
        }
        return "";
    }
  }

  String _getLocationInfo(TrainRecord record) {
    List<String> parts = [];
    if (record.route.isNotEmpty && record.route != "<NUL>") {
      parts.add(record.route);
    }
    if (record.direction != 0) {
      parts.add(record.direction == 1 ? "下" : "上");
    }
    if (record.position.isNotEmpty && record.position != "<NUL>") {
      final position = record.position;
      final cleanPosition = position.endsWith('.')
          ? position.substring(0, position.length - 1)
          : position;
      parts.add("${cleanPosition}K");
    }
    return parts.join(' ');
  }

  Widget _buildExpandedMapForAll(List<TrainRecord> records, String groupKey) {
    final positions = records
        .map((record) => _parsePosition(record.positionInfo))
        .whereType<LatLng>()
        .toList();
    if (positions.isEmpty) {
      return const SizedBox.shrink();
    }

    final mapId = records.map((r) => r.uniqueId).join('_');
    final bounds = LatLngBounds.fromPoints(positions);

    if (!_mapOptimalZoom.containsKey(mapId) &&
        !(_mapCalculating[mapId] ?? false)) {
      _mapCalculating[mapId] = true;

      _calculateOptimalZoomAsync(positions,
              containerWidth: 400, containerHeight: 220)
          .then((optimalZoom) {
        if (mounted) {
          setState(() {
            _mapOptimalZoom[mapId] =
                optimalZoom.isFinite ? optimalZoom : _singlePointMapZoom;
            _mapCalculating[mapId] = false;
          });
        }
      }).catchError((_) {
        if (mounted) {
          setState(() {
            _mapOptimalZoom[mapId] = _singlePointMapZoom;
            _mapCalculating[mapId] = false;
          });
        }
      });
    }

    if (!_mapOptimalZoom.containsKey(mapId)) {
      return const Column(
        children: [
          SizedBox(height: 8),
          SizedBox(
            height: 228,
            child: Center(
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            ),
          ),
        ],
      );
    }

    final zoomLevel = _mapOptimalZoom[mapId]!;

    return Column(children: [
      const SizedBox(height: 8),
      Container(
          height: 220,
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8), color: Colors.grey[900]),
          child: _DelayedMultiMarkerMap(
            key: ValueKey('multi_map_${mapId}_$zoomLevel'),
            positions: positions,
            center: bounds.center,
            zoom: zoomLevel,
            groupKey: groupKey,
          ))
    ]);
  }

  Widget _buildRecordCard(TrainRecord record,
      {bool isSubCard = false, Key? key}) {
    final isSelected = _selectedRecords.contains(record.uniqueId);
    final itemKey = _displayItemKey(record);
    final isExpanded = _expandedStates[itemKey] ?? false;

    return Card(
        key: key,
        color: isSelected && _isEditMode
            ? const Color(0xFF2E2E2E)
            : const Color(0xFF1E1E1E),
        elevation: isSubCard ? 0 : 1,
        margin: EdgeInsets.only(bottom: isSubCard ? 4.0 : 8.0),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.0),
            side: BorderSide(
                color: isSelected && _isEditMode
                    ? Colors.white
                    : Colors.transparent,
                width: 2.0)),
        child: InkWell(
            borderRadius: BorderRadius.circular(8.0),
            onTap: () {
              if (_isEditMode) {
                setState(() {
                  if (isSelected) {
                    _selectedRecords.remove(record.uniqueId);
                  } else {
                    _selectedRecords.add(record.uniqueId);
                  }
                  widget.onSelectionChanged();
                });
              } else {
                setState(() {
                  _expandedStates[itemKey] = !isExpanded;
                });
              }
            },
            onLongPress: () {
              if (!_isEditMode) {
                setEditMode(true);
              }
              setState(() {
                _selectedRecords.add(record.uniqueId);
                widget.onSelectionChanged();
              });
            },
            child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildRecordHeader(record),
                      _buildPositionAndSpeed(record),
                      _buildLocoInfo(record),
                      if (isExpanded) _buildExpandedContent(record),
                    ]))));
  }

  Widget _buildRecordHeader(TrainRecord record, {bool isMerged = false}) {
    final trainType = record.trainType;
    String formattedLocoInfo = "";
    if (record.locoType.isNotEmpty && record.loco.isNotEmpty) {
      final shortLoco = record.loco.length > 5
          ? record.loco.substring(record.loco.length - 5)
          : record.loco;
      formattedLocoInfo = "${record.locoType}-$shortLoco";
    } else if (record.locoType.isNotEmpty) {
      formattedLocoInfo = record.locoType;
    } else if (record.loco.isNotEmpty) {
      formattedLocoInfo = record.loco;
    }

    if (record.fullTrainNumber.isEmpty && formattedLocoInfo.isEmpty) {
      return Text(
          (record.time == "<NUL>" || record.time.isEmpty)
              ? record.receivedTimestamp.toString().split(".")[0]
              : record.time.split("\n")[0],
          style: const TextStyle(fontSize: 11, color: Colors.grey),
          overflow: TextOverflow.ellipsis);
    }

    final hasTrainNumber = record.fullTrainNumber.isNotEmpty;
    final hasDirection = record.direction == 1 || record.direction == 3;
    final hasLocoInfo =
        formattedLocoInfo.isNotEmpty && formattedLocoInfo != "<NUL>";
    final shouldShowTrainRow = hasTrainNumber || hasDirection || hasLocoInfo;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Flexible(
            child: Text(
                (record.time == "<NUL>" || record.time.isEmpty)
                    ? record.receivedTimestamp.toString().split(".")[0]
                    : record.time.split("\n")[0],
                style: const TextStyle(fontSize: 11, color: Colors.grey),
                overflow: TextOverflow.ellipsis)),
        if (trainType.isNotEmpty)
          Flexible(
              child: Text(trainType,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                  overflow: TextOverflow.ellipsis))
      ]),
      if (shouldShowTrainRow) ...[
        const SizedBox(height: 2),
        Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                  child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                    if (hasTrainNumber)
                      Flexible(
                          child: Text(record.fullTrainNumber,
                              style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white),
                              overflow: TextOverflow.ellipsis)),
                    if (hasTrainNumber && hasDirection)
                      const SizedBox(width: 6),
                    if (hasDirection)
                      Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(2)),
                          child: Center(
                              child: Text(record.direction == 1 ? "下" : "上",
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black))))
                  ])),
              if (hasLocoInfo)
                Text(formattedLocoInfo,
                    style:
                        const TextStyle(fontSize: 14, color: Colors.white70)),
            ]),
        const SizedBox(height: 2)
      ]
    ]);
  }

  Widget _buildLocoInfo(TrainRecord record) {
    final locoInfo = record.locoInfo;
    if (locoInfo == null || locoInfo.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 4),
      Text(locoInfo,
          style: const TextStyle(fontSize: 14, color: Colors.white),
          maxLines: 1,
          overflow: TextOverflow.ellipsis)
    ]);
  }

  Widget _buildPositionAndSpeed(TrainRecord record) {
    final routeStr = record.route.trim();
    final position = record.position.trim();
    final speed = record.speed.trim();
    final isValidRoute = routeStr.isNotEmpty &&
        !routeStr.runes.every((r) => r == '*'.runes.first);
    final isValidPosition = position.isNotEmpty &&
        !position.runes
            .every((r) => r == '-'.runes.first || r == '.'.runes.first) &&
        position != "<NUL>";
    final isValidSpeed = speed.isNotEmpty &&
        !speed.runes
            .every((r) => r == '*'.runes.first || r == '-'.runes.first) &&
        speed != "NUL" &&
        speed != "<NUL>";
    if (!isValidRoute && !isValidPosition && !isValidSpeed) {
      return const SizedBox.shrink();
    }
    return Padding(
        padding: const EdgeInsets.only(top: 4.0),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          if (isValidRoute || isValidPosition)
            Expanded(
                child: Row(children: [
              if (isValidRoute)
                Flexible(
                    child: Text(routeStr,
                        style:
                            const TextStyle(fontSize: 16, color: Colors.white),
                        overflow: TextOverflow.ellipsis)),
              if (isValidRoute && isValidPosition) const SizedBox(width: 4),
              if (isValidPosition)
                Flexible(
                    child: Text(
                        "${position.trim().endsWith('.') ? position.trim().substring(0, position.trim().length - 1) : position.trim()}K",
                        style:
                            const TextStyle(fontSize: 16, color: Colors.white),
                        overflow: TextOverflow.ellipsis))
            ])),
          if (isValidSpeed)
            Text("${speed.replaceAll(' ', '')} km/h",
                style: const TextStyle(fontSize: 16, color: Colors.white),
                textAlign: TextAlign.right)
        ]));
  }

  Widget _buildExpandedContent(TrainRecord record) {
    final position = _parsePosition(record.positionInfo);
    final mapId = record.uniqueId;

    if (position == null) {
      return const SizedBox.shrink();
    }

    final zoomLevel = _mapOptimalZoom.putIfAbsent(
      mapId,
      () => _singlePointMapZoom,
    );

    return Column(children: [
      const SizedBox(height: 8),
      Container(
          height: 220,
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8), color: Colors.grey[900]),
          child: _DelayedMapWithMarker(
            key: ValueKey('map_${mapId}_$zoomLevel'),
            position: position,
            zoom: zoomLevel,
            recordId: record.uniqueId,
          ))
    ]);
  }

  LatLng? _parsePosition(String? positionInfo) {
    if (positionInfo == null ||
        positionInfo.isEmpty ||
        positionInfo == '<NUL>') {
      return null;
    }
    try {
      final parts = positionInfo.trim().split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        final lat = _parseDmsCoordinate(parts[0]);
        final lng = _parseDmsCoordinate(parts[1]);
        if (_isValidMapCoordinate(lat, lng)) {
          return LatLng(lat!, lng!);
        }
      }
    // ignore: empty_catches
    } catch (e) {}
    return null;
  }

  double? _parseDmsCoordinate(String dmsStr) {
    try {
      final degreeIndex = dmsStr.indexOf('°');
      if (degreeIndex == -1) {
        return null;
      }
      final degrees = double.tryParse(dmsStr.substring(0, degreeIndex));
      if (degrees == null) {
        return null;
      }
      final minuteIndex = dmsStr.indexOf('′');
      if (minuteIndex == -1) {
        return degrees;
      }
      final minutes =
          double.tryParse(dmsStr.substring(degreeIndex + 1, minuteIndex));
      if (minutes == null) {
        return degrees;
      }
      return degrees + (minutes / 60.0);
    } catch (e) {
      return null;
    }
  }

  bool _isValidMapCoordinate(double? lat, double? lng) {
    if (lat == null || lng == null || !lat.isFinite || !lng.isFinite) {
      return false;
    }
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      return false;
    }
    return lat.abs() > 0.001 || lng.abs() > 0.001;
  }

  Future<_BoundaryBox> _calculateBoundaryBoxParallel(
      List<LatLng> positions) async {
    if (positions.length < 100) {
      return _calculateBoundaryBoxIsolate(positions);
    }

    final chunkSize = (positions.length / 4).ceil();
    final chunks = <List<LatLng>>[];

    for (int i = 0; i < positions.length; i += chunkSize) {
      final end = math.min(i + chunkSize, positions.length);
      chunks.add(positions.sublist(i, end));
    }

    final results = await Future.wait(chunks.map(
        (chunk) => Isolate.run(() => _calculateBoundaryBoxIsolate(chunk))));

    double minLat = results[0].minLat;
    double maxLat = results[0].maxLat;
    double minLng = results[0].minLng;
    double maxLng = results[0].maxLng;

    for (final box in results.skip(1)) {
      minLat = math.min(minLat, box.minLat);
      maxLat = math.max(maxLat, box.maxLat);
      minLng = math.min(minLng, box.minLng);
      maxLng = math.max(maxLng, box.maxLng);
    }

    return _BoundaryBox(minLat, maxLat, minLng, maxLng);
  }

  Future<double> _calculateOptimalZoomAsync(List<LatLng> positions,
      {required double containerWidth, required double containerHeight}) async {
    if (positions.length == 1) return _singlePointMapZoom;

    final boundaryBox = await _calculateBoundaryBoxParallel(positions);
    if (!boundaryBox.isValid) return _singlePointMapZoom;

    double latToY(double lat) {
      final clampedLat = lat.clamp(-85.05112878, 85.05112878).toDouble();
      final latRad = clampedLat * math.pi / 180.0;
      return math.log(math.tan(latRad) + 1.0 / math.cos(latRad));
    }

    double lngToX(double lng) {
      return lng * math.pi / 180.0;
    }

    final minX = lngToX(boundaryBox.minLng);
    final maxX = lngToX(boundaryBox.maxLng);
    final minY = latToY(boundaryBox.minLat);
    final maxY = latToY(boundaryBox.maxLat);

    const worldSize = 2.0 * math.pi;

    final widthWorld = (maxX - minX) / worldSize;
    final heightWorld = (maxY - minY) / worldSize;
    if (widthWorld <= 0 || heightWorld <= 0) return _singlePointMapZoom;

    const paddingRatio = 0.8;

    final widthZoom =
        math.log((containerWidth * paddingRatio) / (widthWorld * 256.0)) /
            math.log(2.0);
    final heightZoom =
        math.log((containerHeight * paddingRatio) / (heightWorld * 256.0)) /
            math.log(2.0);

    final optimalZoom = math.min(widthZoom, heightZoom);
    if (!optimalZoom.isFinite) return _singlePointMapZoom;

    return optimalZoom.clamp(_smallMapMinZoom, _smallMapMaxZoom).toDouble();
  }
}

class _RenderViewportAnchor {
  final String itemKey;
  final Set<String> recordIds;
  final double dy;

  const _RenderViewportAnchor({
    required this.itemKey,
    required this.recordIds,
    required this.dy,
  });
}

class _ViewportAnchorRestorer extends SingleChildRenderObjectWidget {
  final bool Function() onAfterLayout;

  const _ViewportAnchorRestorer({
    required this.onAfterLayout,
    required super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _ViewportAnchorRestorerRenderObject(onAfterLayout);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _ViewportAnchorRestorerRenderObject renderObject,
  ) {
    renderObject.onAfterLayout = onAfterLayout;
  }
}

class _ViewportAnchorRestorerRenderObject extends RenderProxyBox {
  bool Function() onAfterLayout;

  _ViewportAnchorRestorerRenderObject(this.onAfterLayout);

  @override
  void performLayout() {
    child?.layout(constraints, parentUsesSize: true);
    size = child?.size ?? constraints.smallest;

    if (onAfterLayout()) {
      child?.layout(constraints, parentUsesSize: true);
      size = child?.size ?? constraints.smallest;
    }
  }
}

class _BoundaryBox {
  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;

  _BoundaryBox(this.minLat, this.maxLat, this.minLng, this.maxLng);

  bool get isValid {
    return minLat.isFinite &&
        maxLat.isFinite &&
        minLng.isFinite &&
        maxLng.isFinite &&
        minLat >= -90 &&
        maxLat <= 90 &&
        minLng >= -180 &&
        maxLng <= 180;
  }
}

_BoundaryBox _calculateBoundaryBoxIsolate(List<LatLng> positions) {
  double minLat = positions[0].latitude;
  double maxLat = positions[0].latitude;
  double minLng = positions[0].longitude;
  double maxLng = positions[0].longitude;

  for (final pos in positions) {
    minLat = math.min(minLat, pos.latitude);
    maxLat = math.max(maxLat, pos.latitude);
    minLng = math.min(minLng, pos.longitude);
    maxLng = math.max(maxLng, pos.longitude);
  }

  return _BoundaryBox(minLat, maxLat, minLng, maxLng);
}

class _DelayedMapWithMarker extends StatefulWidget {
  final LatLng position;
  final double zoom;
  final String recordId;

  const _DelayedMapWithMarker({
    super.key,
    required this.position,
    required this.zoom,
    required this.recordId,
  });

  @override
  State<_DelayedMapWithMarker> createState() => _DelayedMapWithMarkerState();
}

class _DelayedMapWithMarkerState extends State<_DelayedMapWithMarker> {
  late final MapController _mapController;
  late final String _mapKey;
  Timer? _mapStateSaveTimer;
  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _mapKey = MapStateService.instance.getSingleRecordMapKey(widget.recordId);
    _initializeMapState();
  }

  Future<void> _initializeMapState() async {
    final savedState = await MapStateService.instance.getMapState(_mapKey);
    if (savedState != null && mounted) {
      _mapController.move(
        LatLng(savedState.centerLat, savedState.centerLng),
        savedState.zoom
            .clamp(
              HistoryScreenState._smallMapMinZoom,
              HistoryScreenState._smallMapMaxZoom,
            )
            .toDouble(),
      );
      if (savedState.bearing != 0.0) {
        _mapController.rotate(savedState.bearing);
      }
    }
    if (mounted) {
      setState(() {
        _isInitializing = false;
      });
    }
  }

  void _onCameraMove() {
    if (_isInitializing) {
      return;
    }

    final camera = _mapController.camera;
    final state = MapState(
      zoom: camera.zoom,
      centerLat: camera.center.latitude,
      centerLng: camera.center.longitude,
      bearing: camera.rotation,
    );

    _mapStateSaveTimer?.cancel();
    _mapStateSaveTimer = Timer(const Duration(milliseconds: 600), () {
      MapStateService.instance.saveMapState(_mapKey, state);
    });
  }

  @override
  void dispose() {
    _mapStateSaveTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return FlutterMap(
        options: MapOptions(
          initialCenter: widget.position,
          initialZoom: widget.zoom,
          minZoom: HistoryScreenState._smallMapMinZoom,
          maxZoom: HistoryScreenState._smallMapMaxZoom,
          onPositionChanged: (position, hasGesture) => _onCameraMove(),
        ),
        mapController: _mapController,
        children: [
          TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'org.noxylva.lbjconsole'),
          MarkerLayer(markers: [_buildTrainMarker(widget.position)]),
        ],
      );
    }

    return FlutterMap(
      options: MapOptions(
        minZoom: HistoryScreenState._smallMapMinZoom,
        maxZoom: HistoryScreenState._smallMapMaxZoom,
        onPositionChanged: (position, hasGesture) => _onCameraMove(),
      ),
      mapController: _mapController,
      children: [
        TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'org.noxylva.lbjconsole'),
        MarkerLayer(markers: [_buildTrainMarker(widget.position)]),
      ],
    );
  }

  Marker _buildTrainMarker(LatLng position) {
    return Marker(
      point: position,
      width: 24,
      height: 24,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        child: const Icon(Icons.train, color: Colors.white, size: 12),
      ),
    );
  }
}

class _DelayedMultiMarkerMap extends StatefulWidget {
  final List<LatLng> positions;
  final LatLng center;
  final double zoom;
  final String groupKey;

  const _DelayedMultiMarkerMap({
    super.key,
    required this.positions,
    required this.center,
    required this.zoom,
    required this.groupKey,
  });

  @override
  State<_DelayedMultiMarkerMap> createState() => _DelayedMultiMarkerMapState();
}

class _DelayedMultiMarkerMapState extends State<_DelayedMultiMarkerMap> {
  late final MapController _mapController;
  late final String _mapKey;
  Timer? _mapStateSaveTimer;
  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _mapKey = MapStateService.instance.getMergedRecordMapKey(widget.groupKey);
    _initializeMapState();
  }

  Future<void> _initializeMapState() async {
    final savedState = await MapStateService.instance.getMapState(_mapKey);
    if (savedState != null && mounted) {
      _mapController.move(
        LatLng(savedState.centerLat, savedState.centerLng),
        savedState.zoom
            .clamp(
              HistoryScreenState._smallMapMinZoom,
              HistoryScreenState._smallMapMaxZoom,
            )
            .toDouble(),
      );
      if (savedState.bearing != 0.0) {
        _mapController.rotate(savedState.bearing);
      }
    } else if (mounted) {
      _mapController.move(widget.center, widget.zoom);
    }
    if (mounted) {
      setState(() {
        _isInitializing = false;
      });
    }
  }

  void _onCameraMove() {
    if (_isInitializing) {
      return;
    }

    final camera = _mapController.camera;
    final state = MapState(
      zoom: camera.zoom,
      centerLat: camera.center.latitude,
      centerLng: camera.center.longitude,
      bearing: camera.rotation,
    );

    _mapStateSaveTimer?.cancel();
    _mapStateSaveTimer = Timer(const Duration(milliseconds: 600), () {
      MapStateService.instance.saveMapState(_mapKey, state);
    });
  }

  @override
  void dispose() {
    _mapStateSaveTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      options: MapOptions(
        onPositionChanged: (position, hasGesture) => _onCameraMove(),
        minZoom: HistoryScreenState._smallMapMinZoom,
        maxZoom: HistoryScreenState._smallMapMaxZoom,
      ),
      mapController: _mapController,
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'org.noxylva.lbjconsole',
        ),
        PolylineLayer(
          polylines: [
            Polyline(
              points: widget.positions,
              strokeWidth: 4,
              color: Colors.black,
            ),
          ],
        ),
      ],
    );
  }
}
