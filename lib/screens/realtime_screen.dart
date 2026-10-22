import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:latlong2/latlong.dart';
import '../models/merged_record.dart';
import '../services/database_service.dart';
import '../models/train_record.dart';
import '../services/merge_service.dart';
import 'package:lbjconsole/ui/web_map.dart';
import 'package:lbjconsole/ui/glass_card.dart';
import 'package:lbjconsole/ui/glass_dialog.dart';

class RealtimeScreen extends StatefulWidget {
  const RealtimeScreen({
    super.key,
  });

  @override
  RealtimeScreenState createState() => RealtimeScreenState();
}

class RealtimeScreenState extends State<RealtimeScreen> {

  final List<Object> _displayItems = [];
  bool _isLoading = true;
  final ScrollController _scrollController = ScrollController();
  bool _isAtTop = true;
  final GlobalKey _listViewportKey = GlobalKey();
  final Map<String, GlobalKey> _itemKeys = {};
  _RenderViewportAnchor? _pendingRenderViewportAnchor;
  MergeSettings _mergeSettings = MergeSettings();
  StreamSubscription? _recordDeleteSubscription;
  StreamSubscription? _settingsSubscription;

  final WebMapController _webMap = WebMapController();
  bool _mapReady = false;
  bool _railwayLayerVisible = true;
  bool _showMap = true;
  final Set<String> _selectedGroupKeys = {};
  final Map<String, LatLng?> _positionCache = {};

  List<Object> getDisplayItems() => _displayItems;

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

  // The selected groups drawn on the map: a black route line per
  // merged group and the train chip at its end, over the shared
  // basemap.
  void _pushSelectionData() {
    final lines = <List<LatLng>>[];
    final chips = <WebMapChip>[];
    for (final groupKey in _selectedGroupKeys.toList()) {
      try {
        if (groupKey.startsWith('single:')) {
          final uniqueId = groupKey.substring(7);
          final singleRecord = _displayItems
              .whereType<TrainRecord>()
              .firstWhere((record) => record.uniqueId == uniqueId);
          final position = _getCachedPosition(singleRecord);
          if (position != null) {
            chips.add(
              WebMapChip(
                id: singleRecord.uniqueId,
                position: position,
                label: _getTrainDisplayName(singleRecord),
              ),
            );
          }
        } else {
          final mergedRecord = _displayItems
              .whereType<MergedTrainRecord>()
              .firstWhere((item) => item.groupKey == groupKey);
          final routeEntries =
              _validPositionsForRecords(mergedRecord.records).toList();
          final routePoints = routeEntries
              .map((entry) => entry.value)
              .toList()
              .reversed
              .toList();
          if (routePoints.length >= 2) {
            lines.add(routePoints);
          }
          if (routePoints.isNotEmpty) {
            chips.add(
              WebMapChip(
                id: routeEntries.first.key.uniqueId,
                position: routePoints.last,
                label: _getTrainDisplayName(routeEntries.first.key),
              ),
            );
          }
        }
      } catch (e) {
        _selectedGroupKeys.remove(groupKey);
      }
    }
    _webMap.setData(lines: lines, chips: chips);
  }

  void _adjustMapViewToSelectedGroups() {
    _pushSelectionData();
    if (_selectedGroupKeys.isEmpty) {
      if (mounted) {
        _webMap.moveTo(const LatLng(35.8617, 104.1954), 2.0);
      }
      return;
    }

    if (!mounted) return;

    final allSelectedPoints = <LatLng>[];

    for (final groupKey in _selectedGroupKeys.toList()) {
      try {
        if (groupKey.startsWith('single:')) {
          final uniqueId = groupKey.substring(7);
          final singleRecord = _displayItems
              .whereType<TrainRecord>()
              .firstWhere((record) => record.uniqueId == uniqueId);

          final position = _getCachedPosition(singleRecord);
          if (position != null) {
            allSelectedPoints.add(position);
          }
        } else {
          final mergedRecord = _displayItems
              .whereType<MergedTrainRecord>()
              .firstWhere((item) => item.groupKey == groupKey);

          final routePoints = _validPositionsForRecords(mergedRecord.records)
              .map((entry) => entry.value)
              .toList();

          allSelectedPoints.addAll(routePoints);
        }
      } catch (e) {
        _selectedGroupKeys.remove(groupKey);
      }
    }

    if (allSelectedPoints.isNotEmpty) {
      if (allSelectedPoints.length > 1) {
        var south = allSelectedPoints.first.latitude;
        var north = south;
        var west = allSelectedPoints.first.longitude;
        var east = west;
        for (final point in allSelectedPoints) {
          if (point.latitude < south) south = point.latitude;
          if (point.latitude > north) north = point.latitude;
          if (point.longitude < west) west = point.longitude;
          if (point.longitude > east) east = point.longitude;
        }
        _webMap.fitBounds(allSelectedPoints, padding: 50, maxZoom: 16);
      } else {
        _webMap.moveTo(allSelectedPoints.first, 14);
      }
    }
  }

  void _onGroupSelected(MergedTrainRecord mergedRecord) {
    setState(() {
      if (_selectedGroupKeys.contains(mergedRecord.groupKey)) {
        _selectedGroupKeys.remove(mergedRecord.groupKey);
      } else {
        _selectedGroupKeys.add(mergedRecord.groupKey);
      }
    });

    _adjustMapViewToSelectedGroups();
  }

  void _onSingleRecordSelected(TrainRecord record) {
    final groupKey = "single:${record.uniqueId}";

    setState(() {
      if (_selectedGroupKeys.contains(groupKey)) {
        _selectedGroupKeys.remove(groupKey);
      } else {
        _selectedGroupKeys.add(groupKey);
      }
    });

    _adjustMapViewToSelectedGroups();
  }

  Iterable<MapEntry<TrainRecord, LatLng>> _validPositionsForRecords(
      Iterable<TrainRecord> records) sync* {
    for (final record in records) {
      final position = _getCachedPosition(record);
      if (position != null) {
        yield MapEntry(record, position);
      }
    }
  }

  LatLng? _getCachedPosition(TrainRecord record) {
    final id = record.uniqueId;
    if (_positionCache.containsKey(id)) {
      return _positionCache[id];
    }
    final parsed = _parsePositionFromRecord(record);
    _positionCache[id] = parsed;
    return parsed;
  }

  LatLng? _parsePositionFromRecord(TrainRecord record) {
    if (record.positionInfo.isEmpty || record.positionInfo == '<NUL>') {
      return null;
    }

    try {
      final parts = record.positionInfo.trim().split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        final lat = _parseDmsCoordinate(parts[0]);
        final lng = _parseDmsCoordinate(parts[1]);
        if (_isValidMapCoordinate(lat, lng)) {
          return LatLng(lat!, lng!);
        }
      }
    } catch (e) {
      return null;
    }
    return null;
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

  String _getTrainDisplayName(TrainRecord record) {
    if (record.fullTrainNumber.isNotEmpty) {
      return record.fullTrainNumber.length > 8
          ? record.fullTrainNumber.substring(0, 8)
          : record.fullTrainNumber;
    }
    if (record.locoType.isNotEmpty && record.loco.isNotEmpty) {
      return "${record.locoType}-${record.loco.length > 5 ? record.loco.substring(record.loco.length - 5) : record.loco}";
    }
    return "列车";
  }

  @override
  void initState() {
    super.initState();
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
        loadRecords(scrollToTop: false).then((_) {
          if (mounted) setState(() => _isAtTop = true);
        });
      }
    });
    _setupRecordDeleteListener();
    _setupSettingsListener();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _recordDeleteSubscription?.cancel();
    _settingsSubscription?.cancel();
    super.dispose();
  }

  void _setupRecordDeleteListener() {
    _recordDeleteSubscription =
        DatabaseService.instance.onRecordDeleted((deletedIds) {
      if (mounted) {
        loadRecords(scrollToTop: false);
      }
    });
  }

  void _setupSettingsListener() {
    _settingsSubscription =
        DatabaseService.instance.onSettingsChanged((settings) {
      if (mounted) {
        loadRecords(scrollToTop: false);
      }
    });
  }

  Future<void> loadRecords({bool scrollToTop = true}) async {
    final renderAnchor =
        scrollToTop || _isViewingLatest ? null : _currentRenderViewportAnchor();

    try {
      if (mounted) {
        setState(() => _isLoading = true);
      }

      final allRecords = await DatabaseService.instance.getAllRecords();
      final settingsMap = await DatabaseService.instance.getAllSettings() ?? {};
      _mergeSettings = MergeSettings.fromMap(settingsMap);
      // The railway overlay follows the same persisted switch as
      // the position map; its FAB writes the setting, the settings
      // listener reloads records, and this keeps the monitor map
      // in step.
      final railwayVisible =
          (settingsMap['mapRailwayLayerVisible'] as int?) != 0;
      if (railwayVisible != _railwayLayerVisible) {
        _railwayLayerVisible = railwayVisible;
        _webMap.setOrm(railwayVisible);
      }

      List<TrainRecord> filteredRecords = allRecords;

      filteredRecords = allRecords.where((record) {
        final position = _getCachedPosition(record);
        return position != null;
      }).toList();

      if ((settingsMap['hideTimeOnlyRecords'] ?? 0) == 1) {
        filteredRecords = filteredRecords.where((record) {
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
          final selectedSingleRecords = <String>[];
          final selectedMergedGroups = <String>[];

          for (final key in _selectedGroupKeys) {
            if (key.startsWith('single:')) {
              selectedSingleRecords.add(key);
            } else {
              selectedMergedGroups.add(key);
            }
          }

          final inheritedSelections = <String, String>{};

          for (final oldSingleKey in selectedSingleRecords) {
            final uniqueId = oldSingleKey.substring(7);

            for (final newItem in items) {
              if (newItem is MergedTrainRecord) {
                final containsOldRecord = newItem.records
                    .any((record) => record.uniqueId == uniqueId);
                if (containsOldRecord) {
                  inheritedSelections[oldSingleKey] = newItem.groupKey;
                  break;
                }
              }
            }
          }

          setState(() {
            _displayItems.clear();
            _displayItems.addAll(items);
            _isLoading = false;

            for (final entry in inheritedSelections.entries) {
              final oldSingleKey = entry.key;
              final newMergedKey = entry.value;

              _selectedGroupKeys.remove(oldSingleKey);
              if (!_selectedGroupKeys.contains(newMergedKey)) {
                _selectedGroupKeys.add(newMergedKey);
              }
            }
          });

          if (!scrollToTop) {
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
    _pushSelectionData();
  }

  Future<void> addNewRecord(TrainRecord newRecord) async {
    try {
      final position = _parsePositionFromRecord(newRecord);
      if (position == null) {
        return;
      }

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
            if (_selectedGroupKeys.contains(item.groupKey)) {
              selectedRecordIds.addAll(item.records.map((r) => r.uniqueId));
            }
          } else if (item is TrainRecord) {
            allRecords.add(item);
            if (_selectedGroupKeys.contains("single:${item.uniqueId}")) {
              selectedRecordIds.add(item.uniqueId);
            }
          }
        }

        allRecords.insert(0, newRecord);

        final mergedItems =
            MergeService.getMixedList(allRecords, _mergeSettings);

        setState(() {
          _displayItems.clear();
          _displayItems.addAll(mergedItems);

          _selectedGroupKeys.clear();
          for (final item in _displayItems) {
            if (item is MergedTrainRecord) {
              if (item.records
                  .any((r) => selectedRecordIds.contains(r.uniqueId))) {
                _selectedGroupKeys.add(item.groupKey);
              }
            } else if (item is TrainRecord) {
              if (selectedRecordIds.contains(item.uniqueId)) {
                _selectedGroupKeys.add("single:${item.uniqueId}");
              }
            }
          }
        });

        if (_selectedGroupKeys.isNotEmpty && mounted) {
          _adjustMapViewToSelectedGroups();
        }

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
      return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.history, size: 64, color: Colors.grey),
        SizedBox(height: 16),
        Text('暂无记录', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 18))
      ]));
    }

    return Column(
      children: [
        if (_showMap)
          Expanded(
            flex: 1,
            child: Stack(
              children: [
                WebMapView(
                  controller: _webMap,
                  initialCenter: const LatLng(35.8617, 104.1954),
                  initialZoom: 2,
                  minZoom: 2,
                  maxZoom: 18,
                  interactive: true,
                  hybridComposition: true,
                  orm: true,
                  ormVisible: _railwayLayerVisible,
                  dark: Theme.of(context).brightness == Brightness.dark,
                  onReady: () {
                    if (mounted) setState(() => _mapReady = true);
                    _pushSelectionData();
                  },
                ),
                if (!_mapReady)
                  const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
        if (!_showMap)
          Padding(
            padding: EdgeInsets.fromLTRB(
                16.0, MediaQuery.paddingOf(context).top + 80, 16.0, 16.0),
            child: ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _showMap = true;
                });
              },
              icon: const Icon(Icons.map, size: 16),
              label: const Text('显示地图'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
          ),
        const SizedBox(height: 8),
        Expanded(
          flex: _showMap ? 1 : 2,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _ViewportAnchorRestorer(
                onAfterLayout: _applyPendingRenderViewportAnchorCorrection,
                child: ListView.builder(
                  key: _listViewportKey,
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 118.0),
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
                        child: _buildRecordCard(
                          item,
                          key: ValueKey(item.uniqueId),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMergedRecordCard(MergedTrainRecord mergedRecord) {
    final isSelected = _selectedGroupKeys.contains(mergedRecord.groupKey);
    return GestureDetector(
      onTap: () => _onGroupSelected(mergedRecord),
      child: GlassCard(
          key: ValueKey(mergedRecord.groupKey),
          margin: const EdgeInsets.only(bottom: 8.0),
          radius: 16,
          selected: isSelected,
          child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildRecordHeader(mergedRecord.latestRecord,
                        isMerged: true),
                    _buildPositionAndSpeedWithRouteLogic(mergedRecord),
                    _buildLocoInfo(mergedRecord.latestRecord),
                  ]))),
    );
  }

  Widget _buildRecordCard(TrainRecord record,
      {bool isSubCard = false, Key? key}) {
    final isSelected = _selectedGroupKeys.contains("single:${record.uniqueId}");

    return GestureDetector(
      onTap: () => _onSingleRecordSelected(record),
      child: GlassCard(
          key: key,
          margin: EdgeInsets.only(bottom: isSubCard ? 4.0 : 8.0),
          radius: 16,
          selected: isSelected,
          child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildRecordHeader(record),
                    _buildPositionAndSpeed(record),
                    _buildLocoInfo(record),
                  ]))),
    );
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
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
                              overflow: TextOverflow.ellipsis)),
                    if (hasTrainNumber && hasDirection)
                      const SizedBox(width: 6),
                    if (hasDirection)
                      Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                              color:
                                  Theme.of(context).colorScheme.onSurface,
                              borderRadius: BorderRadius.circular(2)),
                          child: Center(
                              child: Text(record.direction == 1 ? "下" : "上",
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surface))))
                  ])),
              if (hasLocoInfo)
                Text(formattedLocoInfo,
                    style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant))
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
          style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface),
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
                            TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurface),
                        overflow: TextOverflow.ellipsis)),
              if (isValidRoute && isValidPosition) const SizedBox(width: 4),
              if (isValidPosition)
                Flexible(
                    child: Text(
                        "${position.trim().endsWith('.') ? position.trim().substring(0, position.trim().length - 1) : position.trim()}K",
                        style:
                            TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurface),
                        overflow: TextOverflow.ellipsis))
            ])),
          if (isValidSpeed)
            Text("${speed.replaceAll(' ', '')} km/h",
                style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurface),
                textAlign: TextAlign.right)
        ]));
  }

  Widget _buildPositionAndSpeedWithRouteLogic(MergedTrainRecord mergedRecord) {
    if (mergedRecord.records.isEmpty) {
      return const SizedBox.shrink();
    }

    final latestRecord = mergedRecord.latestRecord;

    String getValidRoute(TrainRecord record) {
      final routeStr = record.route.trim();
      if (routeStr.isNotEmpty &&
          !routeStr.runes.every((r) => r == '*'.runes.first) &&
          routeStr != "<NUL>") {
        return routeStr;
      }
      return "";
    }

    final latestRoute = getValidRoute(latestRecord);

    String displayRoute = latestRoute;
    bool isDisplayingLatestNormal = true;

    if (latestRoute.isEmpty || latestRoute.contains('*')) {
      for (final record in mergedRecord.records) {
        final route = getValidRoute(record);
        if (route.isNotEmpty && !route.contains('*')) {
          displayRoute = route;
          isDisplayingLatestNormal = (record == latestRecord);
          break;
        }
      }
    }

    final bool needsSpecialDisplay = !isDisplayingLatestNormal ||
        (latestRoute.contains('*') && displayRoute != latestRoute);

    final position = latestRecord.position.trim();
    final speed = latestRecord.speed.trim();

    final isValidPosition = position.isNotEmpty &&
        !position.runes
            .every((r) => r == '-'.runes.first || r == '.'.runes.first) &&
        position != "<NUL>";
    final isValidSpeed = speed.isNotEmpty &&
        !speed.runes
            .every((r) => r == '*'.runes.first || r == '-'.runes.first) &&
        speed != "NUL" &&
        speed != "<NUL>";

    if (latestRoute.isEmpty && !isValidPosition && !isValidSpeed) {
      return const SizedBox.shrink();
    }

    return Padding(
        padding: const EdgeInsets.only(top: 4.0),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          if (latestRoute.isNotEmpty || isValidPosition)
            Expanded(
                child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (displayRoute.isNotEmpty) ...[
                  if (needsSpecialDisplay) ...[
                    Flexible(
                        child: Text(displayRoute,
                            style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurface),
                            overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () {
                        showGlassDialog(
                          context: context,
                          builder: (context) => GlassDialog(
                            title: Text("路线信息",
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (!isDisplayingLatestNormal) ...[
                                  Text("显示路线: $displayRoute",
                                      style:
                                          TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                                  const SizedBox(height: 8),
                                ],
                                Text(
                                    "最新路线: ${latestRoute.isNotEmpty ? latestRoute : '无效路线'}",
                                    style: TextStyle(
                                      color: latestRoute.isNotEmpty
                                          ? Theme.of(context).colorScheme.onSurfaceVariant
                                          : Colors.red,
                                    )),
                              ],
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('关闭'),
                              ),
                            ],
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange, width: 1),
                        ),
                        child: const Icon(
                          Icons.question_mark,
                          size: 16,
                          color: Colors.orange,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ] else
                    Flexible(
                        child: Text(displayRoute,
                            style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurface),
                            overflow: TextOverflow.ellipsis)),
                ],
                if (latestRoute.isNotEmpty && isValidPosition)
                  const SizedBox(width: 4),
                if (isValidPosition)
                  Flexible(
                      child: Text(
                          "${position.trim().endsWith('.') ? position.trim().substring(0, position.trim().length - 1) : position.trim()}K",
                          style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurface),
                          overflow: TextOverflow.ellipsis))
              ],
            )),
          if (isValidSpeed)
            Text("${speed.replaceAll(' ', '')} km/h",
                style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurface),
                textAlign: TextAlign.right)
        ]));
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
