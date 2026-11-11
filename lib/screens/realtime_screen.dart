import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:latlong2/latlong.dart';
import '../models/merged_record.dart';
import '../services/database_service.dart';
import '../models/klw_event.dart';
import '../models/train_record.dart';
import '../services/merge_service.dart';
import 'package:lbjconsole/ui/native_map.dart';
import 'package:lbjconsole/ui/app_map.dart';
import 'package:lbjconsole/ui/record_card_builders.dart';
import 'package:lbjconsole/ui/glass_card.dart';

class RealtimeScreen extends StatefulWidget {
  const RealtimeScreen({
    super.key,
  });

  @override
  RealtimeScreenState createState() => RealtimeScreenState();
}

class RealtimeScreenState extends State<RealtimeScreen>
    with RecordCardBuilders {

  final List<Object> _displayItems = [];
  List<TrainRecord> _poolRecords = [];
  bool _isLoading = true;
  final ScrollController _scrollController = ScrollController();
  bool _isAtTop = true;
  final GlobalKey _listViewportKey = GlobalKey();
  final Map<String, GlobalKey> _itemKeys = {};
  _RenderViewportAnchor? _pendingRenderViewportAnchor;
  MergeSettings _mergeSettings = MergeSettings();
  StreamSubscription? _recordDeleteSubscription;
  StreamSubscription? _settingsSubscription;
  StreamSubscription? _dataInsertSubscription;

  final AppMapController _webMap = AppMapController();
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

  void _pushSelectionData() {
    final lines = <List<LatLng>>[];
    final chips = <MapChip>[];
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
              MapChip(
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
              MapChip(
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
    final parsed = record.hasGps
        ? LatLng(record.latitude!, record.longitude!)
        : null;
    _positionCache[id] = parsed;
    return parsed;
  }

  bool _itemHasPosition(Object item) {
    if (item is MergedTrainRecord) {
      return item.records.any((r) => _getCachedPosition(r) != null);
    }
    if (item is TrainRecord) {
      return _getCachedPosition(item) != null;
    }
    return false;
  }

  List<Object> _gateItems(List<Object> items) =>
      items.where(_itemHasPosition).toList();

  String _getTrainDisplayName(TrainRecord record) {
    if (record.trainNumber.isNotEmpty) {
      return record.trainNumber.length > 8
          ? record.trainNumber.substring(0, 8)
          : record.trainNumber;
    }
    if (record.formattedLocoInfo.isNotEmpty) {
      return record.formattedLocoInfo;
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
    _dataInsertSubscription =
        DatabaseService.instance.onDataInserted(() {
      if (mounted) {
        loadRecords(scrollToTop: false);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _recordDeleteSubscription?.cancel();
    _settingsSubscription?.cancel();
    _dataInsertSubscription?.cancel();
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
      final railwayVisible =
          (settingsMap['mapRailwayLayerVisible'] as int?) != 0;
      if (railwayVisible != _railwayLayerVisible) {
        _railwayLayerVisible = railwayVisible;
        _webMap.setOrm(railwayVisible);
      }

      List<TrainRecord> filteredRecords = allRecords;

      if ((settingsMap['hideTimeOnlyRecords'] ?? 0) == 1) {
        filteredRecords = filteredRecords
            .where(MergeService.recordPassesFieldFilter)
            .toList();
      }
      klwEvents = await DatabaseService.instance.getKlwEvents();
      _poolRecords = filteredRecords;
      final items = _gateItems(
          MergeService.getMixedList(filteredRecords, _mergeSettings));

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
      final isNewRecord =
          !_poolRecords.any((r) => r.uniqueId == newRecord.uniqueId);
      if (!isNewRecord) return;

      if (mounted) {
        final renderAnchor =
            _isViewingLatest ? null : _currentRenderViewportAnchor();
        List<TrainRecord> allRecords = List.of(_poolRecords);
        Set<String> selectedRecordIds = {};

        for (final item in _displayItems) {
          if (item is MergedTrainRecord) {
            if (_selectedGroupKeys.contains(item.groupKey)) {
              selectedRecordIds.addAll(item.records.map((r) => r.uniqueId));
            }
          } else if (item is TrainRecord) {
            if (_selectedGroupKeys.contains("single:${item.uniqueId}")) {
              selectedRecordIds.add(item.uniqueId);
            }
          }
        }

        allRecords.insert(0, newRecord);
        _poolRecords = allRecords;

        final mergedItems = _gateItems(
            MergeService.getMixedList(allRecords, _mergeSettings));

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
        const Icon(Icons.history, size: 64, color: Colors.grey),
        const SizedBox(height: 16),
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
                AppMapView(
                  controller: _webMap,
                  initialCenter: const LatLng(35.8617, 104.1954),
                  initialZoom: 2,
                  minZoom: 2,
                  maxZoom: 18,
                  interactive: true,
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
                  scrollCacheExtent: const ScrollCacheExtent.pixels(800), key: _listViewportKey,
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 118.0),
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
                    buildRecordHeader(mergedRecord.latestRecord,
                        isMerged: true),
                    buildPositionAndSpeed(mergedRecord.latestRecord
                        .copyWith(route: mergedRecord.displayRoute)),
                    buildExtraInfo(mergedRecord.extrasRecord),
                    buildLocoInfo(mergedRecord.latestRecord),
                    buildTailStateRow(KlwState.eventsForRecords(
                        klwEvents, mergedRecord.records)),
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
                    buildRecordHeader(record),
                    buildPositionAndSpeed(record),
                    buildExtraInfo(record),
                    buildLocoInfo(record),
                    buildTailStateRow(
                        KlwState.eventsForRecords(klwEvents, [record])),
                  ]))),
    );
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
