import 'dart:math' as math;
import 'dart:isolate';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:scrollview_observer/scrollview_observer.dart';
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
  final List<Object> _displayItems = [];
  bool _isLoading = true;
  bool _isEditMode = false;
  final Set<String> _selectedRecords = {};
  final Map<String, bool> _expandedStates = {};
  final ScrollController _scrollController = ScrollController();
  final ListObserverController _observerController =
      ListObserverController(controller: null)..cacheJumpIndexOffset = false;
  late final ChatScrollObserver _chatObserver;
  bool _isAtTop = true;
  MergeSettings _mergeSettings = MergeSettings();
  double _itemHeightCache = 0.0;

  final Map<String, double> _mapOptimalZoom = {};
  final Map<String, bool> _mapCalculating = {};

  LatLng? _currentUserLocation;
  bool _isLocationPermissionGranted = false;
  Timer? _locationTimer;

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

  @override
  void initState() {
    super.initState();
    _chatObserver = ChatScrollObserver(_observerController)
      ..toRebuildScrollViewCallback = () {
        setState(() {});
      };
    _scrollController.addListener(() {
      if (_scrollController.position.atEdge) {
        if (_scrollController.position.pixels == 0) {
          if (!_isAtTop) setState(() => _isAtTop = true);
        }
      } else {
        if (_isAtTop) setState(() => _isAtTop = false);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        loadRecords();
        _startLocationUpdates();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _observerController.controller?.dispose();
    _locationTimer?.cancel();
    super.dispose();
  }

  Future<void> loadRecords({bool scrollToTop = true}) async {
    try {
      final allRecords = await DatabaseService.instance.getAllRecords();
      final settingsMap = await DatabaseService.instance.getAllSettings() ?? {};
      _mergeSettings = MergeSettings.fromMap(settingsMap);

      List<TrainRecord> filteredRecords = allRecords;
      if ((settingsMap['hideTimeOnlyRecords'] ?? 0) == 1) {
        int hiddenCount = 0;
        int shownCount = 0;

        filteredRecords = allRecords.where((record) {
          bool isFieldMeaningful(String field) {
            if (field.isEmpty) return false;
            String cleaned = field.replaceAll('<NUL>', '').trim();
            if (cleaned.isEmpty) return false;
            if (cleaned.runes
                .every((r) => r == '*'.runes.first || r == ' '.runes.first))
              return false;
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

          if (!shouldShow) {
            hiddenCount++;
          } else {
            shownCount++;
          }

          return shouldShow;
        }).toList();
      }

      final items = MergeService.getMixedList(filteredRecords, _mergeSettings);

      if (mounted) {
        final hasDataChanged = _hasDataChanged(items);

        if (hasDataChanged) {
          setState(() {
            _displayItems.clear();
            _displayItems.addAll(items);
            _isLoading = false;
          });

          if (scrollToTop && _isAtTop && _scrollController.hasClients) {
            _scrollController.jumpTo(0.0);
          }
        } else {
          if (_isLoading) {
            setState(() => _isLoading = false);
          }
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> addNewRecord(TrainRecord newRecord) async {
    try {
      final settingsMap = await DatabaseService.instance.getAllSettings() ?? {};
      _mergeSettings = MergeSettings.fromMap(settingsMap);

      if ((settingsMap['hideTimeOnlyRecords'] ?? 0) == 1) {
        bool isFieldMeaningful(String field) {
          if (field.isEmpty) return false;
          String cleaned = field.replaceAll('<NUL>', '').trim();
          if (cleaned.isEmpty) return false;
          if (cleaned.runes
              .every((r) => r == '*'.runes.first || r == ' '.runes.first))
            return false;
          return true;
        }

        final hasTrainNumber = isFieldMeaningful(newRecord.fullTrainNumber) &&
            !newRecord.fullTrainNumber.contains("-----");

        final hasDirection =
            newRecord.direction == 1 || newRecord.direction == 3;

        final hasLocoInfo = isFieldMeaningful(newRecord.locoType) ||
            isFieldMeaningful(newRecord.loco);

        final hasRoute = isFieldMeaningful(newRecord.route);

        final hasPosition = isFieldMeaningful(newRecord.position);

        final hasSpeed =
            isFieldMeaningful(newRecord.speed) && newRecord.speed != "NUL";

        final hasPositionInfo = isFieldMeaningful(newRecord.positionInfo);

        final hasTrainType = isFieldMeaningful(newRecord.trainType) &&
            newRecord.trainType != "未知";

        final hasLbjClass =
            isFieldMeaningful(newRecord.lbjClass) && newRecord.lbjClass != "NA";

        final hasTrain = isFieldMeaningful(newRecord.train) &&
            !newRecord.train.contains("-----");

        if (!hasTrainNumber &&
            !hasDirection &&
            !hasLocoInfo &&
            !hasRoute &&
            !hasPosition &&
            !hasSpeed &&
            !hasPositionInfo &&
            !hasTrainType &&
            !hasLbjClass &&
            !hasTrain) {
          return;
        }
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

      final allRecords = await DatabaseService.instance.getAllRecords();
      final items = MergeService.getMixedList(allRecords, _mergeSettings);

      if (mounted) {
        if (!_isAtTop) {
          _chatObserver.standby();
        }

        final hasDataChanged = _hasDataChanged(items);
        if (hasDataChanged) {
          setState(() {
            _displayItems.clear();
            _displayItems.addAll(items);
          });
        }

        if (_isAtTop && _scrollController.hasClients) {
          _scrollController.jumpTo(0.0);
        }
      }
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
      }
    }

    return false;
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
    return ListViewObserver(
      controller: _observerController,
      child: ListView.builder(
        controller: _scrollController,
        physics: ChatObserverClampingScrollPhysics(observer: _chatObserver),
        shrinkWrap: _chatObserver.isShrinkWrap,
        padding: const EdgeInsets.all(16.0),
        itemCount: _displayItems.length,
        itemBuilder: (context, index) {
          final item = _displayItems[index];
          if (item is MergedTrainRecord) {
            return _buildMergedRecordCard(item);
          } else if (item is TrainRecord) {
            return _buildRecordCard(item, key: ValueKey(item.uniqueId));
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildMergedRecordCard(MergedTrainRecord mergedRecord) {
    final bool isSelected =
        mergedRecord.records.any((r) => _selectedRecords.contains(r.uniqueId));
    final isExpanded = _expandedStates[mergedRecord.groupKey] ?? false;
    return Card(
        color: isSelected && _isEditMode
            ? const Color(0xFF2E2E2E)
            : const Color(0xFF1E1E1E),
        elevation: 1,
        margin: const EdgeInsets.only(bottom: 8.0),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.0),
            side: BorderSide(
                color: isSelected && _isEditMode
                    ? Colors.blue
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
                if (isExpanded) {
                  final mapId =
                      mergedRecord.records.map((r) => r.uniqueId).join('_');
                  setState(() {
                    _expandedStates[mergedRecord.groupKey] = false;
                    _mapOptimalZoom.remove(mapId);
                    _mapCalculating.remove(mapId);
                  });
                } else {
                  setState(() {
                    _expandedStates[mergedRecord.groupKey] = true;
                  });
                }
              }
            },
            onLongPress: () {
              if (!_isEditMode) setEditMode(true);
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
                      if (isExpanded) _buildMergedExpandedContent(mergedRecord)
                    ]))));
  }

  Widget _buildMergedExpandedContent(MergedTrainRecord mergedRecord) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildExpandedMapForAll(mergedRecord.records, mergedRecord.groupKey),
        const Divider(color: Colors.white24, height: 24),
        ...mergedRecord.records.map((record) => _buildSubRecordItem(
            record, mergedRecord.latestRecord, _mergeSettings.groupBy)),
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
                  style:
                      const TextStyle(color: Color(0xFF81D4FA), fontSize: 12),
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
    final locoType = record.locoType.trim();
    final latestTrain = latest.train.trim();
    final latestLoco = latest.loco.trim();
    final latestLocoType = latest.locoType.trim();

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

  double _calculateOptimalZoom(List<LatLng> positions,
      {double containerWidth = 400, double containerHeight = 220}) {
    if (positions.length == 1) return 17.0;

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

    double latToY(double lat) {
      final latRad = lat * math.pi / 180.0;
      return math.log(math.tan(latRad) + 1.0 / math.cos(latRad));
    }

    double lngToX(double lng) {
      return lng * math.pi / 180.0;
    }

    final minX = lngToX(minLng);
    final maxX = lngToX(maxLng);
    final minY = latToY(minLat);
    final maxY = latToY(maxLat);

    const worldSize = 2.0 * math.pi;

    final widthWorld = (maxX - minX) / worldSize;
    final heightWorld = (maxY - minY) / worldSize;

    const paddingRatio = 0.8;

    final widthZoom =
        math.log((containerWidth * paddingRatio) / (widthWorld * 256.0)) /
            math.log(2.0);
    final heightZoom =
        math.log((containerHeight * paddingRatio) / (heightWorld * 256.0)) /
            math.log(2.0);

    final optimalZoom = math.min(widthZoom, heightZoom);

    return math.max(1.0, math.min(20.0, optimalZoom));
  }

  double _calculateDistance(LatLng pos1, LatLng pos2) {
    const earthRadius = 6371000;
    final lat1 = pos1.latitude * math.pi / 180;
    final lat2 = pos2.latitude * math.pi / 180;
    final deltaLat = (pos2.latitude - pos1.latitude) * math.pi / 180;
    final deltaLng = (pos2.longitude - pos1.longitude) * math.pi / 180;

    final a = math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(deltaLng / 2) *
            math.sin(deltaLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadius * c;
  }

  String _getLocationInfo(TrainRecord record) {
    List<String> parts = [];
    if (record.route.isNotEmpty && record.route != "<NUL>")
      parts.add(record.route);
    if (record.direction != 0) parts.add(record.direction == 1 ? "下" : "上");
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
    if (positions.isEmpty) return const SizedBox.shrink();

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
            _mapOptimalZoom[mapId] = optimalZoom;
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
                color: Colors.blue,
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
            currentUserLocation: _currentUserLocation,
          ))
    ]);
  }

  double _getDefaultZoom(List<LatLng> positions) {
    if (positions.length == 1) return 15.0;
    if (positions.length < 10) return 12.0;
    return 10.0;
  }

  Future<void> _requestLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      return;
    }

    setState(() {
      _isLocationPermissionGranted = true;
    });

    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        forceAndroidLocationManager: true,
      );

      setState(() {
        _currentUserLocation = LatLng(position.latitude, position.longitude);
      });
    } catch (e) {}
  }

  void _startLocationUpdates() {
    _requestLocationPermission();

    _locationTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isLocationPermissionGranted) {
        _getCurrentLocation();
      }
    });
  }

  Widget _buildRecordCard(TrainRecord record,
      {bool isSubCard = false, Key? key}) {
    final isSelected = _selectedRecords.contains(record.uniqueId);
    final isExpanded =
        !isSubCard && (_expandedStates[record.uniqueId] ?? false);

    final GlobalKey itemKey = GlobalKey();

    final Widget card = Card(
        key: key ?? itemKey,
        color: isSelected && _isEditMode
            ? const Color(0xFF2E2E2E)
            : const Color(0xFF1E1E1E),
        elevation: isSubCard ? 0 : 1,
        margin: EdgeInsets.only(bottom: isSubCard ? 4.0 : 8.0),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.0),
            side: BorderSide(
                color: isSelected && _isEditMode
                    ? Colors.blue
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
              }
            },
            onLongPress: () {
              if (!_isEditMode) setEditMode(true);
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_itemHeightCache <= 0 && itemKey.currentContext != null) {
        final RenderBox renderBox =
            itemKey.currentContext!.findRenderObject() as RenderBox;
        final double realHeight = renderBox.size.height;
        if (realHeight > 0) {
          setState(() {
            _itemHeightCache = realHeight;
          });
        }
      }
    });

    return card;
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
                    style: const TextStyle(fontSize: 14, color: Colors.white70))
            ]),
        const SizedBox(height: 2)
      ]
    ]);
  }

  Widget _buildLocoInfo(TrainRecord record) {
    final locoInfo = record.locoInfo;
    if (locoInfo == null || locoInfo.isEmpty) return const SizedBox.shrink();
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
    if (!isValidRoute && !isValidPosition && !isValidSpeed)
      return const SizedBox.shrink();
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

    if (!_mapOptimalZoom.containsKey(mapId) &&
        !(_mapCalculating[mapId] ?? false)) {
      _mapCalculating[mapId] = true;

      _calculateOptimalZoomAsync([position],
              containerWidth: 400, containerHeight: 220)
          .then((optimalZoom) {
        if (mounted) {
          setState(() {
            _mapOptimalZoom[mapId] = optimalZoom;
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
                color: Colors.blue,
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
          child: _DelayedMapWithMarker(
            key: ValueKey('map_${mapId}_$zoomLevel'),
            position: position,
            zoom: zoomLevel,
            recordId: record.uniqueId,
            currentUserLocation: _currentUserLocation,
          ))
    ]);
  }

  LatLng? _parsePosition(String? positionInfo) {
    if (positionInfo == null || positionInfo.isEmpty || positionInfo == '<NUL>')
      return null;
    try {
      final parts = positionInfo.trim().split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        final lat = _parseDmsCoordinate(parts[0]);
        final lng = _parseDmsCoordinate(parts[1]);
        if (lat != null &&
            lng != null &&
            (lat.abs() > 0.001 || lng.abs() > 0.001)) {
          return LatLng(lat, lng);
        }
      }
    } catch (e) {}
    return null;
  }

  double? _parseDmsCoordinate(String dmsStr) {
    try {
      final degreeIndex = dmsStr.indexOf('°');
      if (degreeIndex == -1) return null;
      final degrees = double.tryParse(dmsStr.substring(0, degreeIndex));
      if (degrees == null) return null;
      final minuteIndex = dmsStr.indexOf('′');
      if (minuteIndex == -1) return degrees;
      final minutes =
          double.tryParse(dmsStr.substring(degreeIndex + 1, minuteIndex));
      if (minutes == null) return degrees;
      return degrees + (minutes / 60.0);
    } catch (e) {
      return null;
    }
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
    if (positions.length == 1) return 17.0;

    final boundaryBox = await _calculateBoundaryBoxParallel(positions);

    double latToY(double lat) {
      final latRad = lat * math.pi / 180.0;
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

    const paddingRatio = 0.8;

    final widthZoom =
        math.log((containerWidth * paddingRatio) / (widthWorld * 256.0)) /
            math.log(2.0);
    final heightZoom =
        math.log((containerHeight * paddingRatio) / (heightWorld * 256.0)) /
            math.log(2.0);

    final optimalZoom = math.min(widthZoom, heightZoom);

    return math.max(5.0, math.min(18.0, optimalZoom));
  }
}

class _BoundaryBox {
  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;

  _BoundaryBox(this.minLat, this.maxLat, this.minLng, this.maxLng);
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
  final LatLng? currentUserLocation;

  const _DelayedMapWithMarker({
    Key? key,
    required this.position,
    required this.zoom,
    required this.recordId,
    this.currentUserLocation,
  }) : super(key: key);

  @override
  State<_DelayedMapWithMarker> createState() => _DelayedMapWithMarkerState();
}

class _DelayedMapWithMarkerState extends State<_DelayedMapWithMarker> {
  late final MapController _mapController;
  late final String _mapKey;
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
        savedState.zoom,
      );
      if (savedState.bearing != 0.0) {
        _mapController.rotate(savedState.bearing);
      }
    }
    setState(() {
      _isInitializing = false;
    });
  }

  void _onCameraMove() {
    if (_isInitializing) return;

    final camera = _mapController.camera;
    final state = MapState(
      zoom: camera.zoom,
      centerLat: camera.center.latitude,
      centerLng: camera.center.longitude,
      bearing: camera.rotation,
    );

    MapStateService.instance.saveMapState(_mapKey, state);
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>[
      Marker(
        point: widget.position,
        width: 24,
        height: 24,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.red,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white, width: 1.5),
          ),
          child: const Icon(Icons.train, color: Colors.white, size: 12),
        ),
      ),
    ];

    if (widget.currentUserLocation != null) {
      markers.add(
        Marker(
          point: widget.currentUserLocation!,
          width: 24,
          height: 24,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blue,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
            ),
            child: const Icon(
              Icons.my_location,
              color: Colors.white,
              size: 12,
            ),
          ),
        ),
      );
    }

    if (_isInitializing) {
      return FlutterMap(
        options: MapOptions(
          initialCenter: widget.position,
          initialZoom: widget.zoom,
          onPositionChanged: (position, hasGesture) => _onCameraMove(),
        ),
        mapController: _mapController,
        children: [
          TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'org.noxylva.lbjconsole'),
          MarkerLayer(markers: markers),
        ],
      );
    }

    return FlutterMap(
      options: MapOptions(
        onPositionChanged: (position, hasGesture) => _onCameraMove(),
      ),
      mapController: _mapController,
      children: [
        TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'org.noxylva.lbjconsole'),
        MarkerLayer(markers: markers),
      ],
    );
  }
}

class _DelayedMultiMarkerMap extends StatefulWidget {
  final List<LatLng> positions;
  final LatLng center;
  final double zoom;
  final String groupKey;
  final LatLng? currentUserLocation;

  const _DelayedMultiMarkerMap({
    Key? key,
    required this.positions,
    required this.center,
    required this.zoom,
    required this.groupKey,
    this.currentUserLocation,
  }) : super(key: key);

  @override
  State<_DelayedMultiMarkerMap> createState() => _DelayedMultiMarkerMapState();
}

class _DelayedMultiMarkerMapState extends State<_DelayedMultiMarkerMap> {
  late final MapController _mapController;
  late final String _mapKey;
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
        savedState.zoom,
      );
      if (savedState.bearing != 0.0) {
        _mapController.rotate(savedState.bearing);
      }
    } else if (mounted) {
      _mapController.move(widget.center, widget.zoom);
    }
    setState(() {
      _isInitializing = false;
    });
  }

  void _onCameraMove() {
    if (_isInitializing) return;

    final camera = _mapController.camera;
    final state = MapState(
      zoom: camera.zoom,
      centerLat: camera.center.latitude,
      centerLng: camera.center.longitude,
      bearing: camera.rotation,
    );

    MapStateService.instance.saveMapState(_mapKey, state);
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>[
      ...widget.positions.map((pos) => Marker(
          point: pos,
          width: 24,
          height: 24,
          child: Container(
              decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.8),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5)),
              child: const Icon(Icons.train, color: Colors.white, size: 12)))),
    ];

    if (widget.currentUserLocation != null) {
      markers.add(
        Marker(
          point: widget.currentUserLocation!,
          width: 24,
          height: 24,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blue,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
            ),
            child: const Icon(
              Icons.my_location,
              color: Colors.white,
              size: 12,
            ),
          ),
        ),
      );
    }

    return FlutterMap(
      options: MapOptions(
        onPositionChanged: (position, hasGesture) => _onCameraMove(),
        minZoom: 5,
        maxZoom: 18,
      ),
      mapController: _mapController,
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'org.noxylva.lbjconsole',
        ),
        MarkerLayer(markers: markers),
      ],
    );
  }
}
