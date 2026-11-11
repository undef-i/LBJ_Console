import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:latlong2/latlong.dart';
import '../models/merged_record.dart';
import '../services/database_service.dart';
import '../models/ffsk_alarm_event.dart';
import '../models/sync_event.dart';
import '../models/klw_event.dart';
import '../models/train_record.dart';
import '../services/merge_service.dart';
import '../models/map_state.dart';
import '../services/map_state_service.dart';
import 'package:lbjconsole/ui/native_map.dart';
import 'package:lbjconsole/ui/app_map.dart';
import 'package:lbjconsole/ui/glass_card.dart';
import 'package:lbjconsole/ui/record_card_builders.dart';
import 'package:lbjconsole/ui/shape.dart';

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

class HistoryScreenState extends State<HistoryScreen> with RecordCardBuilders {
  static const double _smallMapMinZoom = 2.0;
  static const double _smallMapMaxZoom = 18.0;
  static const double _singlePointMapZoom = 17.0;

  final List<Object> _displayItems = [];
  bool _isLoading = true;
  bool _isEditMode = false;
  final Set<String> _selectedRecords = {};
  final Set<String> _selectedEvents = {};
  final Map<String, bool> _expandedStates = {};
  final Map<String, (String, Brightness, GroupBy, Widget)> _subItemsCache = {};
  late final ScrollController _scrollController;
  bool _isAtTop = true;
  final GlobalKey _listViewportKey = GlobalKey();
  final Map<String, GlobalKey> _itemKeys = {};
  _RenderViewportAnchor? _pendingRenderViewportAnchor;
  int _pendingAnchorPasses = 0;
  final Map<String, GlobalKey> _subKeys = {};
  final Map<String, double> _itemHeights = {};

  MergeSettings _mergeSettings = MergeSettings();

  int getSelectedCount() => _selectedRecords.length + _selectedEvents.length;
  Set<String> getSelectedRecordIds() => _selectedRecords;
  Set<String> getSelectedEventIds() => _selectedEvents;
  List<Object> getDisplayItems() => _displayItems;
  void clearSelection() => setState(() {
    _selectedRecords.clear();
    _selectedEvents.clear();
  });

  void _toggleEventSelection(String id) {
    if (!_isEditMode) return;
    setState(() {
      if (_selectedEvents.contains(id)) {
        _selectedEvents.remove(id);
      } else {
        _selectedEvents.add(id);
      }
      widget.onSelectionChanged();
    });
  }

  void _selectEvent(String id) {
    if (!_isEditMode) {
      setEditMode(true);
    }
    setState(() {
      _selectedEvents.add(id);
      widget.onSelectionChanged();
    });
  }

  void setEditMode(bool isEditing) {
    setState(() {
      _isEditMode = isEditing;
      widget.onEditModeChanged(isEditing);
      if (!isEditing) {
        _selectedRecords.clear();
        _selectedEvents.clear();
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
    if (item is FfskAlarmEvent) {
      return 'alarm:${item.uniqueId}';
    }
    if (item is LbjSyncEvent) {
      return 'sync:${item.uniqueId}';
    }
    return 'record:${(item as TrainRecord).uniqueId}';
  }

  List<FfskAlarmEvent> _alarmEvents = [];
  List<LbjSyncEvent> _syncEvents = [];

  DateTime _itemTime(Object item) {
    if (item is MergedTrainRecord) return item.latestRecord.timestamp;
    if (item is TrainRecord) return item.timestamp;
    if (item is FfskAlarmEvent) return item.receivedTimestamp;
    if (item is LbjSyncEvent) return item.receivedTimestamp;
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  List<Object> _withAlarms(List<Object> items) {
    if (_alarmEvents.isEmpty && _syncEvents.isEmpty) return items;
    final combined = List<Object>.from(items);
    for (final event in [..._alarmEvents, ..._syncEvents]) {
      final time = _itemTime(event);
      var index = combined.length;
      for (var i = 0; i < combined.length; i++) {
        if (_itemTime(combined[i]).isBefore(time)) {
          index = i;
          break;
        }
      }
      combined.insert(index, event);
    }
    return combined;
  }

  Future<void> refreshAlarmEvents() async {
    await loadRecords(scrollToTop: false);
  }

  Future<void> refreshSyncEvents() async {
    await loadRecords(scrollToTop: false);
  }

  Set<String> _displayItemRecordIds(Object item) {
    if (item is MergedTrainRecord) {
      return item.records.map((record) => record.uniqueId).toSet();
    }
    if (item is FfskAlarmEvent) {
      return {};
    }
    if (item is LbjSyncEvent) {
      return {};
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

  GlobalKey _subKeyFor(String subId) {
    return _subKeys.putIfAbsent(subId, GlobalKey.new);
  }

  RenderBox? _liveBox(GlobalKey? key) {
    final context = key?.currentContext;
    if (context == null) return null;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box;
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
    final viewportHeight = viewportBox.size.height;

    for (var index = 0; index < _displayItems.length; index++) {
      final item = _displayItems[index];
      final itemKey = _displayItemKey(item);
      final box = _liveBox(_itemKeys[itemKey]);
      if (box == null) continue;

      final dy = box.localToGlobal(Offset.zero).dy - viewportTop;
      final bottom = dy + box.size.height;
      if (bottom <= 0 || dy >= viewportHeight) continue;

      if (item is MergedTrainRecord && (_expandedStates[itemKey] ?? false)) {
        final subIds = <String>[
          'map:${item.groupKey}',
          for (final record in item.records) 'sub:${record.uniqueId}',
        ];
        for (final subId in subIds) {
          final subBox = _liveBox(_subKeys[subId]);
          if (subBox == null) continue;
          final subDy = subBox.localToGlobal(Offset.zero).dy - viewportTop;
          final subBottom = subDy + subBox.size.height;
          if (subBottom <= 0 || subDy >= viewportHeight) continue;
          return _RenderViewportAnchor(
            itemKey: itemKey,
            recordIds: _displayItemRecordIds(item),
            dy: subDy,
            subId: subId,
            index: index,
          );
        }
      }

      return _RenderViewportAnchor(
        itemKey: itemKey,
        recordIds: _displayItemRecordIds(item),
        dy: dy,
        index: index,
      );
    }

    return null;
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
    _pendingAnchorPasses = 0;
  }

  void _sweepItemHeights() {
    for (final item in _displayItems) {
      final itemKey = _displayItemKey(item);
      final box = _liveBox(_itemKeys[itemKey]);
      if (box != null) _itemHeights[itemKey] = box.size.height;
    }
  }

  double _estimatedItemHeight(String itemKey) {
    final known = _itemHeights[itemKey];
    if (known != null) return known;
    if (_itemHeights.isEmpty) return 120;
    var sum = 0.0;
    for (final height in _itemHeights.values) {
      sum += height;
    }
    return sum / _itemHeights.length;
  }

  bool _correctScrollBy(double delta) {
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

  bool _applyPendingRenderViewportAnchorCorrection() {
    _sweepItemHeights();
    final anchor = _pendingRenderViewportAnchor;
    if (anchor == null || !mounted || !_scrollController.hasClients) {
      return false;
    }

    final viewportContext = _listViewportKey.currentContext;
    final viewportBox = viewportContext?.findRenderObject() as RenderBox?;
    if (viewportBox == null || !viewportBox.hasSize) return false;
    final viewportTop = viewportBox.localToGlobal(Offset.zero).dy;

    var itemKey = anchor.itemKey;
    var subId = anchor.subId;
    final itemSurvives = _displayItems.any(
      (item) => _displayItemKey(item) == itemKey,
    );
    if (!itemSurvives) {
      final fallback = _fallbackItemKeyForAnchor(anchor);
      if (fallback != null) {
        itemKey = fallback;
        subId = null;
      } else if (_displayItems.isNotEmpty) {
        final clamped = anchor.index.clamp(0, _displayItems.length - 1);
        itemKey = _displayItemKey(_displayItems[clamped]);
        subId = null;
      } else {
        _pendingRenderViewportAnchor = null;
        return false;
      }
    }

    RenderBox? targetBox;
    if (subId != null) targetBox = _liveBox(_subKeys[subId]);
    targetBox ??= _liveBox(_itemKeys[itemKey]);

    if (targetBox != null) {
      final newDy = targetBox.localToGlobal(Offset.zero).dy - viewportTop;
      final delta = newDy - anchor.dy;
      _pendingRenderViewportAnchor = null;
      _pendingAnchorPasses = 0;
      if (delta.abs() <= 0.5) return false;
      return _correctScrollBy(delta);
    }

    _pendingAnchorPasses++;
    if (_pendingAnchorPasses > 15) {
      _pendingRenderViewportAnchor = null;
      _pendingAnchorPasses = 0;
      return false;
    }
    final seek = _seekCorrection(itemKey, anchor.dy, viewportTop);
    if (seek == null || seek.abs() <= 0.5) return false;
    return _correctScrollBy(seek);
  }

  double? _seekCorrection(
    String targetItemKey,
    double targetDy,
    double viewportTop,
  ) {
    int? targetIndex;
    for (var i = 0; i < _displayItems.length; i++) {
      if (_displayItemKey(_displayItems[i]) == targetItemKey) {
        targetIndex = i;
        break;
      }
    }
    if (targetIndex == null) return null;

    int? refIndex;
    var refDy = 0.0;
    for (var i = 0; i < _displayItems.length; i++) {
      final box = _liveBox(_itemKeys[_displayItemKey(_displayItems[i])]);
      if (box == null) continue;
      if (refIndex == null ||
          (i - targetIndex).abs() < (refIndex - targetIndex).abs()) {
        refIndex = i;
        refDy = box.localToGlobal(Offset.zero).dy - viewportTop;
      }
    }
    if (refIndex == null) return null;

    var estimatedDy = refDy;
    if (targetIndex > refIndex) {
      for (var i = refIndex; i < targetIndex; i++) {
        estimatedDy += _estimatedItemHeight(_displayItemKey(_displayItems[i]));
      }
    } else if (targetIndex < refIndex) {
      for (var i = targetIndex; i < refIndex; i++) {
        estimatedDy -= _estimatedItemHeight(_displayItemKey(_displayItems[i]));
      }
    }
    return estimatedDy - targetDy;
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

  void _setExpanded(String itemKey, bool value) {
    setState(() {
      _expandedStates[itemKey] = value;
    });
  }

  Future<void> loadRecords({bool scrollToTop = true}) async {
    final renderAnchor = scrollToTop || _isViewingLatest
        ? null
        : _currentRenderViewportAnchor();

    try {
      final allRecords = await DatabaseService.instance.getAllRecords();
      final settingsMap = await DatabaseService.instance.getAllSettings() ?? {};
      _mergeSettings = MergeSettings.fromMap(settingsMap);

      List<TrainRecord> filteredRecords = allRecords;
      if ((settingsMap['hideTimeOnlyRecords'] ?? 0) == 1) {
        filteredRecords = filteredRecords
            .where(MergeService.recordPassesFieldFilter)
            .toList();
      }
      klwEvents = await DatabaseService.instance.getKlwEvents();
      _alarmEvents = await DatabaseService.instance.getAlarmEvents();
      _syncEvents = await DatabaseService.instance.getSyncEvents();
      final items = _withAlarms(
        MergeService.getMixedList(filteredRecords, _mergeSettings),
      );

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
            _pruneSubItemsCache();
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
              _pendingRenderViewportAnchor = null;
              _pendingAnchorPasses = 0;
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
        final renderAnchor = _isViewingLatest
            ? null
            : _currentRenderViewportAnchor();
        List<TrainRecord> allRecords = [];
        Set<String> selectedRecordIds = {};

        for (final item in _displayItems) {
          if (item is MergedTrainRecord) {
            allRecords.addAll(item.records);
            if (item.records.any(
              (r) => _selectedRecords.contains(r.uniqueId),
            )) {
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
        final mergedItems = _withAlarms(
          MergeService.getMixedList(allRecords, _mergeSettings),
        );
        final expandedRecordIdGroups = _expandedRecordIdGroups();

        setState(() {
          _displayItems
            ..clear()
            ..addAll(mergedItems);
          _restoreExpandedStates(expandedRecordIdGroups);
          _pruneSubItemsCache();

          _selectedRecords.clear();
          for (final item in _displayItems) {
            if (item is MergedTrainRecord) {
              if (item.records.any(
                (r) => selectedRecordIds.contains(r.uniqueId),
              )) {
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
      } else if (oldItem is FfskAlarmEvent && newItem is FfskAlarmEvent) {
        if (oldItem.uniqueId != newItem.uniqueId) return true;
      } else if (oldItem is LbjSyncEvent && newItem is LbjSyncEvent) {
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.history, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              '暂无记录',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 18,
              ),
            ),
          ],
        ),
      );
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
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification &&
            notification.dragDetails != null) {
          _pendingRenderViewportAnchor = null;
          _pendingAnchorPasses = 0;
        }
        return false;
      },
      child: _ViewportAnchorRestorer(
        onAfterLayout: _applyPendingRenderViewportAnchorCorrection,
        child: ListView.builder(
          scrollCacheExtent: const ScrollCacheExtent.pixels(800),
          key: _listViewportKey,
          controller: _scrollController,
          padding: EdgeInsets.fromLTRB(
            16.0,
            MediaQuery.paddingOf(context).top + 80,
            16.0,
            118.0,
          ),
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
            } else if (item is FfskAlarmEvent) {
              return RepaintBoundary(
                key: _keyForDisplayItem(item),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _toggleEventSelection(item.uniqueId),
                  onLongPress: () => _selectEvent(item.uniqueId),
                  child: buildAlarmCard(
                    item,
                    selected:
                        _isEditMode && _selectedEvents.contains(item.uniqueId),
                  ),
                ),
              );
            } else if (item is LbjSyncEvent) {
              return RepaintBoundary(
                key: _keyForDisplayItem(item),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _toggleEventSelection(item.uniqueId),
                  onLongPress: () => _selectEvent(item.uniqueId),
                  child: buildSyncCard(
                    item,
                    selected:
                        _isEditMode && _selectedEvents.contains(item.uniqueId),
                  ),
                ),
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  Widget _buildMergedRecordCard(MergedTrainRecord mergedRecord) {
    final bool isSelected = mergedRecord.records.any(
      (r) => _selectedRecords.contains(r.uniqueId),
    );
    final itemKey = _displayItemKey(mergedRecord);
    final isExpanded = _expandedStates[itemKey] ?? false;
    return GlassCard(
      key: ValueKey(mergedRecord.groupKey),
      margin: const EdgeInsets.only(bottom: 8.0),
      radius: 16,
      selected: isSelected && _isEditMode,
      child: InkWell(
        customBorder: AppShape.all(16),
        onTap: () {
          if (_isEditMode) {
            setState(() {
              final allIdsInGroup = mergedRecord.records
                  .map((r) => r.uniqueId)
                  .toSet();
              if (isSelected) {
                _selectedRecords.removeAll(allIdsInGroup);
              } else {
                _selectedRecords.addAll(allIdsInGroup);
              }
              widget.onSelectionChanged();
            });
          } else {
            _setExpanded(itemKey, !isExpanded);
          }
        },
        onLongPress: () {
          if (!_isEditMode) {
            setEditMode(true);
          }
          setState(() {
            final allIdsInGroup = mergedRecord.records
                .map((r) => r.uniqueId)
                .toSet();
            _selectedRecords.addAll(allIdsInGroup);
            widget.onSelectionChanged();
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              buildRecordHeader(mergedRecord.latestRecord, isMerged: true),
              buildPositionAndSpeed(
                mergedRecord.latestRecord.copyWith(
                  route: mergedRecord.displayRoute,
                ),
              ),
              buildExtraInfo(mergedRecord.extrasRecord),
              buildLocoInfo(mergedRecord.latestRecord),
              buildTailStateRow(
                KlwState.eventsForRecords(klwEvents, mergedRecord.records),
              ),
              if (isExpanded) _buildMergedExpandedContent(mergedRecord),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMergedExpandedContent(MergedTrainRecord mergedRecord) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RepaintBoundary(
          key: _subKeyFor('map:${mergedRecord.groupKey}'),
          child: _buildExpandedMapForAll(
            mergedRecord.records,
            mergedRecord.groupKey,
          ),
        ),
        const SizedBox(height: 12),
        _mergedSubItems(mergedRecord),
      ],
    );
  }

  Widget _mergedSubItems(MergedTrainRecord mergedRecord) {
    final fingerprint = mergedRecord.records.map((r) => r.uniqueId).join('_');
    final brightness = Theme.of(context).brightness;
    final groupBy = _mergeSettings.groupBy;
    final hit = _subItemsCache[mergedRecord.groupKey];
    if (hit != null &&
        hit.$1 == fingerprint &&
        hit.$2 == brightness &&
        hit.$3 == groupBy) {
      return hit.$4;
    }
    final built = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...mergedRecord.records.map(
          (record) => RepaintBoundary(
            key: _subKeyFor('sub:${record.uniqueId}'),
            child: _buildSubRecordItem(
              record,
              mergedRecord.latestRecord,
              groupBy,
            ),
          ),
        ),
      ],
    );
    _subItemsCache[mergedRecord.groupKey] = (
      fingerprint,
      brightness,
      groupBy,
      built,
    );
    return built;
  }

  void _pruneSubItemsCache() {
    final live = <String>{
      for (final item in _displayItems)
        if (item is MergedTrainRecord) item.groupKey,
    };
    _subItemsCache.removeWhere((key, _) => !live.contains(key));
  }

  Widget _buildSubRecordItem(
    TrainRecord record,
    TrainRecord latest,
    GroupBy groupBy,
  ) {
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
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 12,
                ),
              ),
              if (differingInfo.isNotEmpty)
                Text(
                  differingInfo,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 14,
                  ),
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
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                record.speedKmh.isNotEmpty ? "${record.speedKmh} km/h" : "",
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          buildExtraInfo(record),
        ],
      ),
    );
  }

  String _getDifferingInfo(
    TrainRecord record,
    TrainRecord latest,
    GroupBy groupBy,
  ) {
    final train = record.trainNumber.trim();
    final hasLoco =
        record.rawLocoNumber.isNotEmpty || record.parsedLocoNumber.isNotEmpty;
    final latestTrain = latest.trainNumber.trim();
    final locoDiffers =
        hasLoco && KlwState.recordKey(record) != KlwState.recordKey(latest);

    switch (groupBy) {
      case GroupBy.trainOnly:
        if (locoDiffers) {
          return record.formattedLocoInfo;
        }
        return "";
      case GroupBy.locoOnly:
        return train != latestTrain && train.isNotEmpty ? train : "";
      case GroupBy.trainOrLoco:
        final trainDiff = train.isNotEmpty && train != latestTrain ? train : "";
        final locoDiff = locoDiffers ? record.formattedLocoInfo : "";

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
          final locoInfo = record.formattedLocoInfo;
          if (locoInfo.isNotEmpty) {
            return "$train $locoInfo";
          }
          return train;
        }
        if (locoDiffers) {
          return record.formattedLocoInfo;
        }
        return "";
    }
  }

  String _getLocationInfo(TrainRecord record) {
    List<String> parts = [];
    if (record.route.isNotEmpty && record.route != "<NUL>") {
      parts.add(record.route);
    }
    if (record.directionChar.isNotEmpty) {
      parts.add(record.directionChar);
    }
    if (record.kilometerMark.isNotEmpty && record.kilometerMark != "<NUL>") {
      parts.add(record.positionText);
    }
    return parts.join(' ');
  }

  Widget _buildExpandedMapForAll(List<TrainRecord> records, String groupKey) {
    final positions = records
        .map(
          (record) => record.hasGps
              ? LatLng(record.latitude!, record.longitude!)
              : null,
        )
        .whereType<LatLng>()
        .toList();
    if (positions.isEmpty) {
      return const SizedBox.shrink();
    }

    final mapId = records.map((r) => r.uniqueId).join('_');

    return Column(
      children: [
        const SizedBox(height: 8),
        Container(
          height: 220,
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.grey[900],
          ),
          child: _DelayedMultiMarkerMap(
            key: ValueKey('multi_map_$mapId'),
            positions: positions,
            groupKey: groupKey,
          ),
        ),
      ],
    );
  }

  Widget _buildRecordCard(
    TrainRecord record, {
    bool isSubCard = false,
    Key? key,
  }) {
    final isSelected = _selectedRecords.contains(record.uniqueId);
    final itemKey = _displayItemKey(record);
    final isExpanded = _expandedStates[itemKey] ?? false;

    return GlassCard(
      key: key,
      margin: EdgeInsets.only(bottom: isSubCard ? 4.0 : 8.0),
      radius: 16,
      selected: isSelected && _isEditMode,
      child: InkWell(
        customBorder: AppShape.all(16),
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
            _setExpanded(itemKey, !isExpanded);
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
              buildRecordHeader(record),
              buildPositionAndSpeed(record),
              buildExtraInfo(record),
              buildLocoInfo(record),
              buildTailStateRow(KlwState.eventsForRecords(klwEvents, [record])),
              if (isExpanded) _buildExpandedContent(record),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedContent(TrainRecord record) {
    final position = record.hasGps
        ? LatLng(record.latitude!, record.longitude!)
        : null;
    final mapId = record.uniqueId;

    return Column(
      children: [
        if (position != null) ...[
          const SizedBox(height: 8),
          Container(
            height: 220,
            margin: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.grey[900],
            ),
            child: _DelayedMapWithMarker(
              key: ValueKey('map_$mapId'),
              position: position,
              zoom: _singlePointMapZoom,
              recordId: record.uniqueId,
            ),
          ),
        ],
      ],
    );
  }
}

class _RenderViewportAnchor {
  final String itemKey;
  final Set<String> recordIds;
  final double dy;

  final String? subId;

  final int index;

  const _RenderViewportAnchor({
    required this.itemKey,
    required this.recordIds,
    required this.dy,
    this.subId,
    this.index = 0,
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
  final AppMapController _map = AppMapController();
  late final String _mapKey;
  Timer? _mapStateSaveTimer;
  ({LatLng center, double zoom, double bearing})? _initialCamera;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _mapKey = MapStateService.instance.getSingleRecordMapKey(widget.recordId);
    _initialize();
  }

  void _onCameraIdle(LatLng center, double zoom, double bearing) {
    final state = MapState(
      zoom: zoom,
      centerLat: center.latitude,
      centerLng: center.longitude,
      bearing: bearing,
    );
    _mapStateSaveTimer?.cancel();
    _mapStateSaveTimer = Timer(const Duration(milliseconds: 600), () {
      MapStateService.instance.saveMapState(_mapKey, state);
    });
  }

  Future<void> _initialize() async {
    final savedState = await MapStateService.instance.getMapState(_mapKey);
    if (!mounted) return;
    if (savedState != null) {
      _initialCamera = (
        center: LatLng(savedState.centerLat, savedState.centerLng),
        zoom: savedState.zoom
            .clamp(
              HistoryScreenState._smallMapMinZoom,
              HistoryScreenState._smallMapMaxZoom,
            )
            .toDouble(),
        bearing: savedState.bearing,
      );
    } else {
      _initialCamera = (
        center: widget.position,
        zoom: widget.zoom,
        bearing: 0.0,
      );
    }
    setState(() {
      _ready = true;
    });
  }

  @override
  void dispose() {
    _mapStateSaveTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _initialCamera == null) {
      return const SizedBox.expand();
    }
    return AppMapView(
      controller: _map,
      initialCenter: _initialCamera!.center,
      initialZoom: _initialCamera!.zoom,
      initialBearing: _initialCamera!.bearing,
      minZoom: HistoryScreenState._smallMapMinZoom,
      maxZoom: HistoryScreenState._smallMapMaxZoom,
      interactive: true,
      orm: true,
      attribution: true,
      dark: Theme.of(context).brightness == Brightness.dark,
      onReady: () {
        _map.setData(dots: [MapDot(position: widget.position)]);
      },
      onCameraIdle: _onCameraIdle,
    );
  }
}

class _DelayedMultiMarkerMap extends StatefulWidget {
  final List<LatLng> positions;
  final String groupKey;

  const _DelayedMultiMarkerMap({
    super.key,
    required this.positions,
    required this.groupKey,
  });

  @override
  State<_DelayedMultiMarkerMap> createState() => _DelayedMultiMarkerMapState();
}

class _DelayedMultiMarkerMapState extends State<_DelayedMultiMarkerMap> {
  final AppMapController _map = AppMapController();

  @override
  Widget build(BuildContext context) {
    return AppMapView(
      controller: _map,
      initialCenter: widget.positions.first,
      initialZoom: HistoryScreenState._singlePointMapZoom,
      minZoom: HistoryScreenState._smallMapMinZoom,
      maxZoom: HistoryScreenState._smallMapMaxZoom,
      interactive: true,
      orm: true,
      attribution: true,
      dark: Theme.of(context).brightness == Brightness.dark,
      onReady: () {
        _map.setData(
          lines: [widget.positions],
          dots: [MapDot(position: widget.positions.first)],
        );
        _map.fitBounds(widget.positions, padding: 24, maxZoom: 17);
      },
    );
  }
}
