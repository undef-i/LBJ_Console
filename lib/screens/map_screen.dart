import 'dart:async';
import 'dart:math' show sin, cos, sqrt, atan2;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lbjconsole/services/database_service.dart';
import 'package:lbjconsole/models/train_record.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  final List<TrainRecord> _trainRecords = [];
  final List<Marker> _trainMarkers = [];
  bool _isLoading = true;
  bool _railwayLayerVisible = true;
  LatLng? _currentLocation;
  LatLng? _lastTrainLocation;
  LatLng? _userLocation;
  double _currentZoom = 14.0;
  double _currentRotation = 0.0;

  bool _isMapInitialized = false;
  bool _isLocationPermissionGranted = false;
  Timer? _locationTimer;
  Timer? _settingsSaveTimer;

  String _selectedTimeFilter = 'unlimited';
  final Map<String, Duration> _timeFilterOptions = {
    'unlimited': Duration.zero,
    '1hour': const Duration(hours: 1),
    '6hours': const Duration(hours: 6),
    '12hours': const Duration(hours: 12),
    '24hours': const Duration(hours: 24),
    '7days': const Duration(days: 7),
    '30days': const Duration(days: 30),
  };

  @override
  void initState() {
    super.initState();
    _initializeMap();

    _checkDatabaseSettings();

    _loadSettings().then((_) {
      _loadTrainRecords().then((_) {
        _startLocationUpdates();
        if (!_isMapInitialized &&
            (_currentLocation != null ||
                _lastTrainLocation != null ||
                _userLocation != null)) {
          _initializeMapPosition();
        }
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadSettings();
  }

  Future<void> _checkDatabaseSettings() async {
    try {
      final settings = await DatabaseService.instance.getAllSettings();

      if (settings != null) {
        final lat = settings['mapCenterLat'];
        final lon = settings['mapCenterLon'];

        if (lat != null && lon != null) {
          if (lat == 39.9042 && lon == 116.4074) {
          } else if (lat == 0.0 && lon == 0.0) {
          } else {
            const beijingLat = 39.9042;
            const beijingLon = 116.4074;
            final distance =
                _calculateDistance(lat, lon, beijingLat, beijingLon);

            if (distance < 50) {}
          }
        }
      }
    // ignore: empty_catches
    } catch (e) {}
  }

  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371;
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) *
            cos(_degreesToRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * pi / 180;
  }

  @override
  void dispose() {
    _settingsSaveTimer?.cancel();
    _saveSettings();
    _locationTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeMap() async {}

  Future<void> _requestLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!mounted) return;
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请开启定位服务')),
      );
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (!mounted) return;
    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('定位权限被拒绝，请在设置中开启')),
      );
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
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      final newLocation = LatLng(position.latitude, position.longitude);
      setState(() {
        _userLocation = newLocation;
      });

      if (!_isMapInitialized) {
        _initializeMapPosition();
      }
    // ignore: empty_catches
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

  Future<void> _forceUpdateLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
        ),
      );

      final newLocation = LatLng(position.latitude, position.longitude);

      setState(() {
        _userLocation = newLocation;
      });

      _mapController.move(newLocation, 15.0);
    // ignore: empty_catches
    } catch (e) {}
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await DatabaseService.instance.getAllSettings();
      if (settings != null) {
        setState(() {
          _railwayLayerVisible =
              (settings['mapRailwayLayerVisible'] as int?) == 1;
          _currentZoom = (settings['mapZoomLevel'] as num?)?.toDouble() ?? 10.0;
          _currentRotation =
              (settings['mapRotation'] as num?)?.toDouble() ?? 0.0;
          _selectedTimeFilter =
              settings['mapTimeFilter'] as String? ?? 'unlimited';

          final lat = (settings['mapCenterLat'] as num?)?.toDouble();
          final lon = (settings['mapCenterLon'] as num?)?.toDouble();

          if (lat != null && lon != null && lat != 0.0 && lon != 0.0) {
            _currentLocation = LatLng(lat, lon);
          }
        });
        if (!_isMapInitialized) {
          _initializeMapPosition();
        }
      }
    // ignore: empty_catches
    } catch (e) {}
  }

  Future<void> _saveSettings() async {
    try {
      final center = _mapController.camera.center;

      final isDefaultLocation =
          center.latitude == 39.9042 && center.longitude == 116.4074;

      final settings = {
        'mapRailwayLayerVisible': _railwayLayerVisible ? 1 : 0,
        'mapZoomLevel': _currentZoom,
        'mapRotation': _currentRotation,
        'mapTimeFilter': _selectedTimeFilter,
      };

      if (!isDefaultLocation) {
        settings['mapCenterLat'] = center.latitude;
        settings['mapCenterLon'] = center.longitude;
      }

      settings['mapSettingsTimestamp'] = DateTime.now().millisecondsSinceEpoch;

      await DatabaseService.instance.updateSettings(settings);
    // ignore: empty_catches
    } catch (e) {}
  }

  void _scheduleSettingsSave() {
    _settingsSaveTimer?.cancel();
    _settingsSaveTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) {
        _saveSettings();
      }
    });
  }

  Future<void> _loadTrainRecords() async {
    setState(() => _isLoading = true);
    try {
      final records = await _getFilteredRecords();
      final trainMarkers = _buildTrainMarkers(records);
      setState(() {
        _trainRecords.clear();
        _trainRecords.addAll(records);
        _trainMarkers
          ..clear()
          ..addAll(trainMarkers);
        _isLoading = false;

        if (_trainRecords.isNotEmpty) {
          final lastRecord = _trainRecords.first;
          final coords = lastRecord.getCoordinates();
          final dmsCoords = _parseDmsCoordinate(lastRecord.positionInfo);

          if (dmsCoords != null) {
            _lastTrainLocation = dmsCoords;
          } else if (coords['lat'] != 0.0 && coords['lng'] != 0.0) {
            _lastTrainLocation = LatLng(coords['lat']!, coords['lng']!);
          }
        }

        if (!_isMapInitialized) {
          _initializeMapPosition();
        }
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<List<TrainRecord>> _getFilteredRecords() async {
    if (_selectedTimeFilter == 'unlimited') {
      return await DatabaseService.instance.getAllRecords();
    } else {
      final duration = _timeFilterOptions[_selectedTimeFilter];
      if (duration != null && duration != Duration.zero) {
        return await DatabaseService.instance
            .getRecordsWithinReceivedTimeRange(duration);
      }
      return await DatabaseService.instance.getAllRecords();
    }
  }

  void _initializeMapPosition() {
    if (_isMapInitialized) return;

    LatLng? targetLocation;

    if (_currentLocation != null) {
      targetLocation = _currentLocation;
    } else if (_lastTrainLocation != null) {
      targetLocation = _lastTrainLocation;
    } else if (_userLocation != null) {
      targetLocation = _userLocation;
    } else {
      targetLocation = const LatLng(39.9042, 116.4074);
    }

    _centerMap(targetLocation!, zoom: _currentZoom, rotation: _currentRotation);
    _isMapInitialized = true;
  }

  void _centerMap(LatLng location, {double? zoom, double? rotation}) {
    _mapController.move(location, zoom ?? _currentZoom);
    _mapController.rotate(rotation ?? _currentRotation);
  }

  LatLng? _parseDmsCoordinate(String? positionInfo) {
    if (positionInfo == null ||
        positionInfo.isEmpty ||
        positionInfo == '<NUL>') {
      return null;
    }

    try {
      final parts = positionInfo.trim().split(' ');
      if (parts.length >= 2) {
        final latStr = parts[0];
        final lngStr = parts[1];

        final lat = _parseDmsString(latStr);
        final lng = _parseDmsString(lngStr);

        if (lat != null &&
            lng != null &&
            (lat.abs() > 0.001 || lng.abs() > 0.001)) {
          return LatLng(lat, lng);
        }
      }
    // ignore: empty_catches
    } catch (e) {}

    return null;
  }

  double? _parseDmsString(String dmsStr) {
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

  LatLng? _positionForRecord(TrainRecord record) {
    final dmsPosition = _parseDmsCoordinate(record.positionInfo);
    if (dmsPosition != null) {
      return dmsPosition;
    }

    final coords = record.getCoordinates();
    if (coords['lat'] != 0.0 && coords['lng'] != 0.0) {
      return LatLng(coords['lat']!, coords['lng']!);
    }

    return null;
  }

  List<Marker> _buildTrainMarkers(List<TrainRecord> records) {
    final markers = <Marker>[];
    final seenRecordIds = <String>{};

    for (final record in records) {
      if (!seenRecordIds.add(record.uniqueId)) continue;

      final position = _positionForRecord(record);

      if (position != null) {
        final trainDisplay =
            record.fullTrainNumber.isEmpty ? "未知列车" : record.fullTrainNumber;

        markers.add(
          Marker(
            point: position,
            width: 80,
            height: 16,
            child: GestureDetector(
              onTap: () => _showTrainDetailsDialog(record, position),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      trainDisplay,
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
          ),
        );
      }
    }

    return markers;
  }

  void _showTimeFilterDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return RadioGroup<String>(
          groupValue: _selectedTimeFilter,
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _selectedTimeFilter = value;
            });
            _loadTrainRecords();
            Navigator.pop(context);
          },
          child: SimpleDialog(
            title: const Text('时间筛选'),
            children: _timeFilterOptions.keys.map((key) {
              return RadioListTile<String>(
                value: key,
                title: Text(_getTimeFilterLabel(key)),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  String _getTimeFilterLabel(String key) {
    switch (key) {
      case 'unlimited':
        return '全部时间';
      case '1hour':
        return '最近1小时';
      case '6hours':
        return '最近6小时';
      case '12hours':
        return '最近12小时';
      case '24hours':
        return '最近24小时';
      case '7days':
        return '最近7天';
      case '30days':
        return '最近30天';
      default:
        return '未知';
    }
  }

  void _showTrainDetailsDialog(TrainRecord record, LatLng position) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 4,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        record.fullTrainNumber.isEmpty
                            ? "未知列车"
                            : record.fullTrainNumber,
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _buildMaterial3DetailRow(
                            context, "时间", _getDisplayTime(record)),
                        _buildMaterial3DetailRow(
                            context, "日期", _getDisplayDate(record)),
                        _buildMaterial3DetailRow(
                            context, "类型", record.trainType),
                        _buildMaterial3DetailRow(context, "速度",
                            "${record.speed.replaceAll(' ', '')} km/h"),
                        _buildMaterial3DetailRow(
                            context,
                            "位置",
                            record.position.trim().endsWith('.')
                                ? '${record.position.trim().substring(0, record.position.trim().length - 1)}K'
                                : '${record.position.trim()}K'),
                        _buildMaterial3DetailRow(
                            context,
                            "路线",
                            record.route.trim().endsWith('.')
                                ? record.route.trim().substring(
                                    0, record.route.trim().length - 1)
                                : record.route.trim()),
                        _buildMaterial3DetailRow(
                            context, "机车", "${record.locoType}-${record.loco}"),
                        _buildMaterial3DetailRow(context, "坐标",
                            "${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}"),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('关闭'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _centerMap(position,
                              zoom: 17.0, rotation: _currentRotation);
                        },
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.my_location, size: 16),
                            SizedBox(width: 8),
                            Text('居中查看'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _getDisplayTime(TrainRecord record) {
    if (record.time == "<NUL>" || record.time.isEmpty) {
      final receivedTime = record.receivedTimestamp;
      return '${receivedTime.hour.toString().padLeft(2, '0')}:${receivedTime.minute.toString().padLeft(2, '0')}:${receivedTime.second.toString().padLeft(2, '0')}';
    } else {
      return record.time.split("\n")[0];
    }
  }

  String _getDisplayDate(TrainRecord record) {
    if (record.time == "<NUL>" || record.time.isEmpty) {
      final receivedTime = record.receivedTimestamp;
      return '${receivedTime.year}-${receivedTime.month.toString().padLeft(2, '0')}-${receivedTime.day.toString().padLeft(2, '0')}';
    } else {
      final now = DateTime.now();
      return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    }
  }

  Widget _buildMaterial3DetailRow(
      BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? "未知" : value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final markers = List<Marker>.of(_trainMarkers, growable: true);

    if (_userLocation != null) {
      markers.add(
        Marker(
          point: _userLocation!,
          width: 24,
          height: 24,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black,
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

    final bool isDefaultLocation = _currentLocation == null &&
        _lastTrainLocation == null &&
        _userLocation == null;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      floatingActionButtonLocation: FloatingActionButtonLocation.endTop,
      floatingActionButton: SafeArea(
        minimum: const EdgeInsets.only(top: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FloatingActionButton.small(
              heroTag: 'timeFilter',
              backgroundColor: const Color(0xFF1E1E1E),
              foregroundColor: Colors.white,
              onPressed: _showTimeFilterDialog,
              child: const Icon(Icons.filter_list),
            ),
            const SizedBox(height: 8),
            FloatingActionButton.small(
              heroTag: 'railwayLayer',
              backgroundColor: const Color(0xFF1E1E1E),
              foregroundColor: Colors.white,
              onPressed: () {
                setState(() {
                  _railwayLayerVisible = !_railwayLayerVisible;
                });
                _settingsSaveTimer?.cancel();
                _saveSettings();
              },
              child: Icon(
                _railwayLayerVisible
                    ? Icons.layers
                    : Icons.layers_outlined,
              ),
            ),
            const SizedBox(height: 8),
            FloatingActionButton.small(
              heroTag: 'myLocation',
              backgroundColor: const Color(0xFF1E1E1E),
              foregroundColor: Colors.white,
              onPressed: () {
                _forceUpdateLocation();
              },
              child: const Icon(Icons.my_location),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          if (isDefaultLocation)
            const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Color(0xFF007ACC)),
                  ),
                  SizedBox(height: 16),
                  Text(
                    '正在加载地图位置...',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
            )
          else
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentLocation ??
                    _lastTrainLocation ??
                    _userLocation ??
                    const LatLng(39.9042, 116.4074),
                initialZoom: _currentZoom,
                initialRotation: _currentRotation,
                minZoom: 2.0,
                maxZoom: 18.0,
                onPositionChanged: (MapCamera camera, bool hasGesture) {
                  _currentLocation = camera.center;
                  _currentZoom = camera.zoom;
                  _currentRotation = camera.rotation;

                  _scheduleSettingsSave();
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'org.noxylva.lbjconsole',
                ),
                if (_railwayLayerVisible)
                  TileLayer(
                    urlTemplate:
                        'https://{s}.tiles.openrailwaymap.org/standard/{z}/{x}/{y}.png',
                    subdomains: const ['a', 'b', 'c'],
                    userAgentPackageName: 'org.noxylva.lbjconsole.flutter',
                  ),
                MarkerLayer(
                  markers: markers,
                ),
              ],
            ),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF007ACC)),
              ),
            ),
        ],
      ),
    );
  }
}
