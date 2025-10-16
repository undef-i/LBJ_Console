import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../models/merged_record.dart';
import '../services/database_service.dart';
import '../models/train_record.dart';
import '../services/merge_service.dart';

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
  MergeSettings _mergeSettings = MergeSettings();
  StreamSubscription? _recordDeleteSubscription;
  StreamSubscription? _settingsSubscription;

  final MapController _mapController = MapController();
  List<LatLng> _selectedGroupRoute = [];
  List<Marker> _mapMarkers = [];
  bool _showMap = true;
  Set<String> _selectedGroupKeys = {};
  LatLng? _userLocation;
  bool _isLocationPermissionGranted = false;
  Timer? _locationTimer;
  StreamSubscription<Position>? _positionStreamSubscription;

  List<Object> getDisplayItems() => _displayItems;

  Future<void> reloadRecords() async {
    await loadRecords(scrollToTop: false);
  }

  void _updateAllRecordMarkers() {
    setState(() {
      final allRecordsWithPosition = <TrainRecord>[];
      for (final item in _displayItems) {
        if (item is MergedTrainRecord) {
          allRecordsWithPosition.addAll(item.records);
        } else if (item is TrainRecord) {
          allRecordsWithPosition.add(item);
        }
      }

      _mapMarkers = allRecordsWithPosition
          .map((record) {
            final position = _parsePositionFromRecord(record);
            if (position != null) {
              final isInSelectedGroup = _selectedGroupKeys.isNotEmpty &&
                  (_displayItems.any((item) {
                        if (item is MergedTrainRecord &&
                            _selectedGroupKeys.contains(item.groupKey)) {
                          return item.records
                              .any((r) => r.uniqueId == record.uniqueId);
                        }
                        return false;
                      }) ||
                      _selectedGroupKeys.contains("single:${record.uniqueId}"));

              return Marker(
                point: position,
                width: 10,
                height: 10,
                child: Container(
                  decoration: BoxDecoration(
                    color: isInSelectedGroup ? Colors.black : Colors.grey,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: isInSelectedGroup
                            ? Colors.white
                            : Colors.grey[300]!,
                        width: 1.5),
                  ),
                ),
              );
            }
            return null;
          })
          .where((marker) => marker != null)
          .cast<Marker>()
          .toList();

      if (_userLocation != null) {
        _mapMarkers.add(
          Marker(
            point: _userLocation!,
            width: 24,
            height: 24,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white, width: 1),
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
    });
  }

  List<PolylineLayer> _buildSelectedGroupPolylines() {
    final polylineLayers = <PolylineLayer>[];

    for (final groupKey in _selectedGroupKeys.toList()) {
      try {
        if (groupKey.startsWith('single:')) {
          final uniqueId = groupKey.substring(7);
          final singleRecord = _displayItems
              .whereType<TrainRecord>()
              .firstWhere((record) => record.uniqueId == uniqueId);

          final position = _parsePositionFromRecord(singleRecord);
          if (position != null) {
            polylineLayers.add(
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: [position],
                    strokeWidth: 4.0,
                    color: Colors.black,
                  ),
                ],
              ),
            );
          }
        } else {
          final mergedRecord = _displayItems
              .whereType<MergedTrainRecord>()
              .firstWhere((item) => item.groupKey == groupKey);

          final routePoints = mergedRecord.records
              .map((record) => _parsePositionFromRecord(record))
              .where((latLng) => latLng != null)
              .cast<LatLng>()
              .toList()
              .reversed
              .toList();

          if (routePoints.isNotEmpty) {
            polylineLayers.add(
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: routePoints,
                    strokeWidth: 4.0,
                    color: Colors.black,
                  ),
                ],
              ),
            );
          }
        }
      } catch (e) {
        _selectedGroupKeys.remove(groupKey);
      }
    }

    return polylineLayers;
  }

  List<MarkerLayer> _buildSelectedGroupEndMarkers() {
    final markerLayers = <MarkerLayer>[];

    for (final groupKey in _selectedGroupKeys.toList()) {
      try {
        if (groupKey.startsWith('single:')) {
          final uniqueId = groupKey.substring(7);
          final singleRecord = _displayItems
              .whereType<TrainRecord>()
              .firstWhere((record) => record.uniqueId == uniqueId);

          final position = _parsePositionFromRecord(singleRecord);
          if (position != null) {
            markerLayers.add(
              MarkerLayer(
                markers: [
                  Marker(
                    point: position,
                    width: 80,
                    height: 16,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            _getTrainDisplayName(singleRecord),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }
        } else {
          final mergedRecord = _displayItems
              .whereType<MergedTrainRecord>()
              .firstWhere((item) => item.groupKey == groupKey);

          final routePoints = mergedRecord.records
              .map((record) => _parsePositionFromRecord(record))
              .where((latLng) => latLng != null)
              .cast<LatLng>()
              .toList()
              .reversed
              .toList();

          if (routePoints.isNotEmpty) {
            markerLayers.add(
              MarkerLayer(
                markers: [
                  Marker(
                    point: routePoints.last,
                    width: 80,
                    height: 16,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            _getTrainDisplayName(mergedRecord.latestRecord),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }
        }
      } catch (e) {
        _selectedGroupKeys.remove(groupKey);
      }
    }

    return markerLayers;
  }

  void _adjustMapViewToSelectedGroups() {
    if (_selectedGroupKeys.isEmpty) {
      if (mounted) {
        if (mounted) {
          _mapController.move(const LatLng(35.8617, 104.1954), 2.0);
        }
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

          final position = _parsePositionFromRecord(singleRecord);
          if (position != null) {
            allSelectedPoints.add(position);
          }
        } else {
          final mergedRecord = _displayItems
              .whereType<MergedTrainRecord>()
              .firstWhere((item) => item.groupKey == groupKey);

          final routePoints = mergedRecord.records
              .map((record) => _parsePositionFromRecord(record))
              .where((latLng) => latLng != null)
              .cast<LatLng>()
              .toList();

          allSelectedPoints.addAll(routePoints);
        }
      } catch (e) {
        _selectedGroupKeys.remove(groupKey);
      }
    }

    if (allSelectedPoints.isNotEmpty) {
      if (mounted) {
        if (allSelectedPoints.length > 1) {
          final bounds = LatLngBounds.fromPoints(allSelectedPoints);
          _mapController.fitCamera(
            CameraFit.bounds(
              bounds: bounds,
              padding: const EdgeInsets.all(50),
              maxZoom: 16,
            ),
          );
        } else if (allSelectedPoints.length == 1) {
          _mapController.move(allSelectedPoints.first, 14);
        }
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

      _selectedGroupRoute = [];
    });

    _updateAllRecordMarkers();

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

      _selectedGroupRoute = [];
    });

    _updateAllRecordMarkers();

    _adjustMapViewToSelectedGroups();
  }

  LatLng? _parsePositionFromRecord(TrainRecord record) {
    if (record.positionInfo == null ||
        record.positionInfo.isEmpty ||
        record.positionInfo == '<NUL>') {
      return null;
    }

    try {
      final parts = record.positionInfo.trim().split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        final lat = _parseDmsCoordinate(parts[0]);
        final lng = _parseDmsCoordinate(parts[1]);
        if (lat != null &&
            lng != null &&
            (lat.abs() > 0.001 || lng.abs() > 0.001)) {
          return LatLng(lat, lng);
        }
      }
    } catch (e) {
      return null;
    }
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

  void _showRecordDetails(TrainRecord record) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(
          _getTrainDisplayName(record),
          style: const TextStyle(color: Colors.white),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow("时间", record.time),
              _buildDetailRow("位置", record.position),
              _buildDetailRow("路线", record.route),
              _buildDetailRow("速度", record.speed),
              _buildDetailRow("坐标", () {
                final position = _parsePositionFromRecord(record);
                return position != null
                    ? "${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}"
                    : "无数据";
              }()),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              "$label: ",
              style: const TextStyle(
                color: Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty || value == "<NUL>" ? "无数据" : value,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.position.atEdge) {
        if (_scrollController.position.pixels ==
            _scrollController.position.maxScrollExtent) {
          if (!_isAtTop) {
            setState(() => _isAtTop = true);
          }
        } else if (_scrollController.position.pixels == 0) {
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
          if (_displayItems.isNotEmpty) {
            _scheduleInitialScroll();
          }
        });
      }
    });
    _setupRecordDeleteListener();
    _setupSettingsListener();
    _startLocationUpdates();
  }

  void _scheduleInitialScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients && _displayItems.isNotEmpty) {
        try {
          final maxScrollExtent = _scrollController.position.maxScrollExtent;
          _scrollController.jumpTo(maxScrollExtent);

          if (!_isAtTop) {
            setState(() => _isAtTop = true);
          }
        } catch (e) {}
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _recordDeleteSubscription?.cancel();
    _settingsSubscription?.cancel();
    _locationTimer?.cancel();
    _positionStreamSubscription?.cancel();
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
    _startRealtimeLocationUpdates();
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        forceAndroidLocationManager: true,
      );

      final newLocation = LatLng(position.latitude, position.longitude);
      setState(() {
        _userLocation = newLocation;
      });

      _updateAllRecordMarkers();
    } catch (e) {}
  }

  void _startLocationUpdates() {
    _requestLocationPermission();
  }

  void _startRealtimeLocationUpdates() {
    _positionStreamSubscription?.cancel();

    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 1,
        timeLimit: Duration(seconds: 30),
      ),
    ).listen(
      (Position position) {
        final newLocation = LatLng(position.latitude, position.longitude);
        setState(() {
          _userLocation = newLocation;
        });
        _updateAllRecordMarkers();
      },
      onError: (error) {},
    );
  }

  Future<void> loadRecords({bool scrollToTop = true}) async {
    try {
      if (mounted) {
        setState(() => _isLoading = true);
      }

      final allRecords = await DatabaseService.instance.getAllRecords();
      final settingsMap = await DatabaseService.instance.getAllSettings() ?? {};
      _mergeSettings = MergeSettings.fromMap(settingsMap);

      List<TrainRecord> filteredRecords = allRecords;

      filteredRecords = allRecords.where((record) {
        final position = _parsePositionFromRecord(record);
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

          _updateAllRecordMarkers();

          if (scrollToTop &&
              _isAtTop &&
              _scrollController.hasClients &&
              _displayItems.isNotEmpty) {
            try {
              final maxScrollExtent =
                  _scrollController.position.maxScrollExtent;
              _scrollController.jumpTo(maxScrollExtent);
            } catch (e) {}
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
      final position = _parsePositionFromRecord(newRecord);
      if (position == null) {
        return;
      }

      final settingsMap = await DatabaseService.instance.getAllSettings() ?? {};
      _mergeSettings = MergeSettings.fromMap(settingsMap);

      if ((settingsMap['hideTimeOnlyRecords'] ?? 0) == 1) {}

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

        _updateAllRecordMarkers();

        if (_selectedGroupKeys.isNotEmpty && mounted) {
          _adjustMapViewToSelectedGroups();
        }

        if (_isAtTop && _scrollController.hasClients) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _scrollController.hasClients) {
              final newMaxScrollExtent =
                  _scrollController.position.maxScrollExtent;

              _scrollController.jumpTo(newMaxScrollExtent);
            }
          });
        } else {}
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

    return Column(
      children: [
        if (_showMap)
          Expanded(
            flex: 1,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: const LatLng(35.8617, 104.1954),
                initialZoom: 2.0,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'org.noxylva.lbjconsole',
                ),
                MarkerLayer(markers: _mapMarkers),
                if (_selectedGroupKeys.isNotEmpty)
                  ..._buildSelectedGroupPolylines(),
                if (_selectedGroupKeys.isNotEmpty)
                  ..._buildSelectedGroupEndMarkers(),
              ],
            ),
          ),
        if (!_showMap)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _showMap = true;
                });
              },
              icon: const Icon(Icons.map, size: 16),
              label: const Text('显示地图'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[800],
                foregroundColor: Colors.white,
              ),
            ),
          ),
        const SizedBox(height: 8),
        Expanded(
          flex: _showMap ? 1 : 2,
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16.0),
            itemCount: _displayItems.length,
            reverse: true,
            itemBuilder: (context, index) {
              final item = _displayItems[_displayItems.length - 1 - index];
              if (item is MergedTrainRecord) {
                return _buildMergedRecordCard(item);
              } else if (item is TrainRecord) {
                return _buildRecordCard(item, key: ValueKey(item.uniqueId));
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMergedRecordCard(MergedTrainRecord mergedRecord) {
    final isSelected = _selectedGroupKeys.contains(mergedRecord.groupKey);
    return GestureDetector(
      onTap: () => _onGroupSelected(mergedRecord),
      child: Card(
          key: ValueKey(mergedRecord.groupKey),
          color: const Color(0xFF1E1E1E),
          elevation: 1,
          margin: const EdgeInsets.only(bottom: 8.0),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8.0),
              side: BorderSide(
                  color: isSelected ? Colors.blue : Colors.transparent,
                  width: 2.0)),
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

  Widget _buildRecordCard(TrainRecord record,
      {bool isSubCard = false, Key? key}) {
    final isSelected = _selectedGroupKeys.contains("single:${record.uniqueId}");

    return GestureDetector(
      onTap: () => _onSingleRecordSelected(record),
      child: Card(
          key: key,
          color: const Color(0xFF1E1E1E),
          elevation: isSubCard ? 0 : 1,
          margin: EdgeInsets.only(bottom: isSubCard ? 4.0 : 8.0),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8.0),
              side: BorderSide(
                  color: isSelected ? Colors.blue : Colors.transparent,
                  width: 2.0)),
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

  Widget _buildPositionAndSpeedWithRouteLogic(MergedTrainRecord mergedRecord) {
    if (mergedRecord.records.isEmpty) {
      return const SizedBox.shrink();
    }

    final latestRecord = mergedRecord.latestRecord;

    TrainRecord? previousRecord;
    if (mergedRecord.records.length > 1) {
      final sortedRecords = List<TrainRecord>.from(mergedRecord.records)
        ..sort((a, b) => b.receivedTimestamp.compareTo(a.receivedTimestamp));

      if (sortedRecords.length > 1) {
        previousRecord = sortedRecords[1];
      }
    }

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
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.white,
                              decoration: TextDecoration.lineThrough,
                              decorationColor: Colors.grey,
                            ),
                            overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            backgroundColor: const Color(0xFF1E1E1E),
                            title: const Text("路线信息",
                                style: TextStyle(color: Colors.white)),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (!isDisplayingLatestNormal) ...[
                                  Text("显示路线: $displayRoute",
                                      style:
                                          const TextStyle(color: Colors.white)),
                                  const SizedBox(height: 8),
                                ],
                                Text(
                                    "最新路线: ${latestRoute.isNotEmpty ? latestRoute : '无效路线'}",
                                    style: TextStyle(
                                      color: latestRoute.isNotEmpty
                                          ? Colors.grey
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
                          color: Colors.orange.withOpacity(0.2),
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
                            style: const TextStyle(
                                fontSize: 16, color: Colors.white),
                            overflow: TextOverflow.ellipsis)),
                ],
                if (latestRoute.isNotEmpty && isValidPosition)
                  const SizedBox(width: 4),
                if (isValidPosition)
                  Flexible(
                      child: Text(
                          "${position.trim().endsWith('.') ? position.trim().substring(0, position.trim().length - 1) : position.trim()}K",
                          style: const TextStyle(
                              fontSize: 16, color: Colors.white),
                          overflow: TextOverflow.ellipsis))
              ],
            )),
          if (isValidSpeed)
            Text("${speed.replaceAll(' ', '')} km/h",
                style: const TextStyle(fontSize: 16, color: Colors.white),
                textAlign: TextAlign.right)
        ]));
  }
}
