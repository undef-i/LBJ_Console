import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as latlong;
import 'package:lbjconsole/models/train_record.dart';
import 'package:lbjconsole/services/database_service.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

class MapWebViewScreen extends StatefulWidget {
  const MapWebViewScreen({super.key});

  @override
  State<MapWebViewScreen> createState() => MapWebViewScreenState();
}

class MapWebViewScreenState extends State<MapWebViewScreen>
    with WidgetsBindingObserver {
  MapLibreMapController? _controller;
  final Map<String, TrainRecord> _symbolRecordMap = {};

  Position? _currentPosition;
  List<TrainRecord> _trainRecords = [];
  bool _isRailwayLayerVisible = true;
  bool _isLoading = true;
  bool _isStyleLoaded = false;
  String _timeFilter = 'unlimited';
  Timer? _refreshTimer;
  Timer? _locationUpdateTimer;

  bool _isMapInitialized = false;
  bool _isLocationPermissionGranted = false;
  double _currentZoom = 14.0;
  double _currentRotation = 0.0;
  latlong.LatLng? _currentLocation;
  latlong.LatLng? _lastTrainLocation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startInitialization();
  }

  Future<void> _startInitialization() async {
    setState(() => _isLoading = true);
    try {
      await _loadSettings();
      await _loadTrainRecordsFromDatabase();
      _initializeLocation();
      _startAutoRefresh();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reloadSettingsIfNeeded();
    }
  }

  Duration? _getTimeFilterDuration(String filter) {
    switch (filter) {
      case '1hour':
        return const Duration(hours: 1);
      case '6hours':
        return const Duration(hours: 6);
      case '12hours':
        return const Duration(hours: 12);
      case '24hours':
        return const Duration(hours: 24);
      case '7days':
        return const Duration(days: 7);
      case '30days':
        return const Duration(days: 30);
      default:
        return null;
    }
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted) {
        _loadTrainRecordsFromDatabase();
        _reloadSettingsIfNeeded();
      }
    });
  }

  void _reloadSettingsIfNeeded() async {
    try {
      final settings = await DatabaseService.instance.getAllSettings();
      final newTimeFilter = settings?['mapTimeFilter'] as String? ?? 'unlimited';
      if (newTimeFilter != _timeFilter) {
        if (mounted) {
          setState(() => _timeFilter = newTimeFilter);
        }
        _loadTrainRecordsFromDatabase();
      }
    } catch (_) {}
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await DatabaseService.instance.getAllSettings();
      if (settings != null) {
        setState(() {
          _isRailwayLayerVisible =
              (settings['mapRailwayLayerVisible'] as int?) == 1;
          _currentZoom = (settings['mapZoomLevel'] as num?)?.toDouble() ?? 10.0;
          _currentRotation = (settings['mapRotation'] as num?)?.toDouble() ?? 0.0;
          _timeFilter = settings['mapTimeFilter'] as String? ?? 'unlimited';

          final lat = (settings['mapCenterLat'] as num?)?.toDouble();
          final lon = (settings['mapCenterLon'] as num?)?.toDouble();
          if (lat != null && lon != null && lat != 0.0 && lon != 0.0) {
            _currentLocation = latlong.LatLng(lat, lon);
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _saveSettings() async {
    try {
      final settings = {
        'mapRailwayLayerVisible': _isRailwayLayerVisible ? 1 : 0,
        'mapZoomLevel': _currentZoom,
        'mapRotation': _currentRotation,
        'mapTimeFilter': _timeFilter,
        'mapSettingsTimestamp': DateTime.now().millisecondsSinceEpoch,
      };

      if (_currentLocation != null) {
        settings['mapCenterLat'] = _currentLocation!.latitude;
        settings['mapCenterLon'] = _currentLocation!.longitude;
      }

      await DatabaseService.instance.updateSettings(settings);
    } catch (_) {}
  }

  Future<void> _initializeLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.best,
            timeLimit: Duration(seconds: 15),
          ),
        );
        setState(() {
          _currentPosition = position;
          _isLocationPermissionGranted = true;
        });
        _updateUserLocation();
        _startLocationUpdates();
      }
    } catch (_) {}
  }

  void _startLocationUpdates() {
    _locationUpdateTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isLocationPermissionGranted && mounted) {
        _updateCurrentLocation();
      }
    });
  }

  Future<void> _updateCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        forceAndroidLocationManager: true,
      );
      setState(() => _currentPosition = position);
      _updateUserLocation();
    } catch (_) {}
  }

  Future<void> _loadTrainRecordsFromDatabase() async {
    try {
      List<TrainRecord> records;
      if (_timeFilter == 'unlimited') {
        records = await DatabaseService.instance.getAllRecords();
      } else {
        final duration = _getTimeFilterDuration(_timeFilter);
        records = (duration != null && duration != Duration.zero)
            ? await DatabaseService.instance.getRecordsWithinReceivedTimeRange(
                duration,
              )
            : await DatabaseService.instance.getAllRecords();
      }

      setState(() {
        _trainRecords = records;
        final valid = [..._getValidRecords(), ..._getValidDmsRecords()];
        if (valid.isNotEmpty) {
          final pos = _extractPosition(valid.first);
          if (pos != null) _lastTrainLocation = pos;
        }
      });

      _updateTrainMarkers();
    } catch (_) {}
  }

  latlong.LatLng? _parseDmsCoordinate(String? positionInfo) {
    if (positionInfo == null || positionInfo.isEmpty || positionInfo == '<NUL>') {
      return null;
    }
    try {
      final parts = positionInfo.trim().split(' ');
      if (parts.length < 2) return null;
      final lat = _parseDmsString(parts[0]);
      final lng = _parseDmsString(parts[1]);
      if (lat == null || lng == null) return null;
      return latlong.LatLng(lat, lng);
    } catch (_) {
      return null;
    }
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
    } catch (_) {
      return null;
    }
  }

  List<TrainRecord> _getValidRecords() {
    return _trainRecords.where((record) {
      final coords = record.getCoordinates();
      return coords['lat'] != 0.0 && coords['lng'] != 0.0;
    }).toList();
  }

  List<TrainRecord> _getValidDmsRecords() {
    return _trainRecords.where((record) {
      return _parseDmsCoordinate(record.positionInfo) != null;
    }).toList();
  }

  latlong.LatLng? _extractPosition(TrainRecord record) {
    final dms = _parseDmsCoordinate(record.positionInfo);
    if (dms != null) return dms;
    final coords = record.getCoordinates();
    final lat = coords['lat'];
    final lng = coords['lng'];
    if (lat != null && lng != null && (lat != 0.0 || lng != 0.0)) {
      return latlong.LatLng(lat, lng);
    }
    return null;
  }

  Future<void> _updateTrainMarkers() async {
    final controller = _controller;
    if (!_isStyleLoaded || controller == null) return;

    await controller.clearSymbols();
    _symbolRecordMap.clear();

    final validRecords = [..._getValidRecords(), ..._getValidDmsRecords()];
    if (validRecords.isEmpty) return;

    for (final record in validRecords) {
      final pos = _extractPosition(record);
      if (pos == null) continue;

      final symbol = await controller.addSymbol(
        SymbolOptions(
          geometry: LatLng(pos.latitude, pos.longitude),
          textField: record.fullTrainNumber.isEmpty ? '未知列车' : record.fullTrainNumber,
          textSize: 11,
          textColor: '#FFFFFF',
          textHaloColor: '#000000',
          textHaloWidth: 1.0,
          textOffset: const Offset(0, 0.8),
        ),
      );

      _symbolRecordMap[symbol.id] = record;
    }
  }

  Future<void> _updateUserLocation() async {
    final controller = _controller;
    if (!_isStyleLoaded || controller == null || _currentPosition == null) return;

    await controller.clearCircles();
    await controller.addCircle(
      CircleOptions(
        geometry: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        circleColor: '#2196F3',
        circleRadius: 6,
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 2,
      ),
    );
  }

  Future<void> _toggleRailwayLayer() async {
    final controller = _controller;
    setState(() => _isRailwayLayerVisible = !_isRailwayLayerVisible);
    if (!_isStyleLoaded || controller == null) return;
    try {
      await controller.setLayerVisibility('railway', _isRailwayLayerVisible);
      await _saveSettings();
    } catch (_) {}
  }

  Future<void> _centerMap(latlong.LatLng location, {double? zoom, double? bearing}) async {
    final controller = _controller;
    if (controller == null) return;
    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(location.latitude, location.longitude),
          zoom: zoom ?? _currentZoom,
          bearing: bearing ?? _currentRotation,
        ),
      ),
    );
  }

  void _onSymbolTapped(Symbol symbol) {
    final record = _symbolRecordMap[symbol.id];
    if (record == null) return;
    _showTrainDetailsDialog(record);
  }

  void _showTrainDetailsDialog(TrainRecord record) {
    final pos = _extractPosition(record);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(record.fullTrainNumber.isEmpty ? '未知车次' : record.fullTrainNumber,
            style: const TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow('车次', record.fullTrainNumber),
              _buildDetailRow('速度', '${record.speed} km/h'),
              _buildDetailRow('位置', record.position),
              _buildDetailRow('路线', record.route),
              _buildDetailRow('机车', '${record.locoType}-${record.loco}'),
              if (pos != null) _buildDetailRow('坐标', '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭', style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              if (pos != null) {
                _centerMap(pos, zoom: 16);
              }
            },
            child: const Text('定位', style: TextStyle(color: Color(0xFF007ACC))),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text('$label:', style: const TextStyle(color: Colors.grey)),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '未知' : value,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _centerToUserLocation() async {
    if (_currentPosition != null) {
      await _centerMap(
        latlong.LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        zoom: 15,
      );
    } else {
      await _updateCurrentLocation();
    }
  }

  void _centerToLastTrain() {
    if (_lastTrainLocation != null) {
      _centerMap(_lastTrainLocation!, zoom: 15);
    }
  }

  void _refreshMap() {
    _loadTrainRecordsFromDatabase();
    if (_isLocationPermissionGranted) {
      _updateCurrentLocation();
    }
  }

  void _saveSettingsAndReload() async {
    await _saveSettings();
    _loadTrainRecordsFromDatabase();
  }

  String _getTimeFilterLabel() {
    switch (_timeFilter) {
      case '1hour':
        return '1小时';
      case '6hours':
        return '6小时';
      case '12hours':
        return '12小时';
      case '24hours':
        return '24小时';
      case '7days':
        return '7天';
      case '30days':
        return '30天';
      default:
        return '无限制';
    }
  }

  void _showTimeFilterDialog() {
    final items = {
      'unlimited': '无限制',
      '1hour': '最近1小时',
      '6hours': '最近6小时',
      '12hours': '最近12小时',
      '24hours': '最近24小时',
      '7days': '最近7天',
      '30days': '最近30天',
    };

    showDialog(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('时间筛选'),
        children: items.entries
            .map(
              (e) => SimpleDialogOption(
                onPressed: () {
                  setState(() => _timeFilter = e.key);
                  Navigator.of(context).pop();
                  _saveSettingsAndReload();
                },
                child: Text(e.value),
              ),
            )
            .toList(),
      ),
    );
  }

  String _mapStyleJson() {
    final layers = [
      {
        'id': 'osm',
        'type': 'raster',
        'source': 'osm',
        'minzoom': 0,
        'maxzoom': 19,
      },
      {
        'id': 'railway',
        'type': 'raster',
        'source': 'railway',
        'minzoom': 0,
        'maxzoom': 19,
      }
    ];

    return jsonEncode({
      'version': 8,
      'name': 'LBJ MapLibre',
      'sources': {
        'osm': {
          'type': 'raster',
          'tiles': [
            'https://a.tile.openstreetmap.org/{z}/{x}/{y}.png',
            'https://b.tile.openstreetmap.org/{z}/{x}/{y}.png',
            'https://c.tile.openstreetmap.org/{z}/{x}/{y}.png'
          ],
          'tileSize': 256,
          'attribution': '© OpenStreetMap contributors'
        },
        'railway': {
          'type': 'raster',
          'tiles': [
            'https://a.tiles.openrailwaymap.org/standard/{z}/{x}/{y}.png',
            'https://b.tiles.openrailwaymap.org/standard/{z}/{x}/{y}.png',
            'https://c.tiles.openrailwaymap.org/standard/{z}/{x}/{y}.png'
          ],
          'tileSize': 256,
          'attribution': '© OpenRailwayMap'
        }
      },
      'layers': layers,
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveSettings();
    _refreshTimer?.cancel();
    _locationUpdateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initialTarget = _currentLocation ??
        _lastTrainLocation ??
        const latlong.LatLng(39.9042, 116.4074);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Stack(
        children: [
          MapLibreMap(
            styleString: _mapStyleJson(),
            initialCameraPosition: CameraPosition(
              target: LatLng(initialTarget.latitude, initialTarget.longitude),
              zoom: _currentZoom,
              bearing: _currentRotation,
            ),
            trackCameraPosition: true,
            onMapCreated: (controller) {
              _controller = controller;
              controller.onSymbolTapped.add(_onSymbolTapped);
            },
            onStyleLoadedCallback: () async {
              _isStyleLoaded = true;
              if (!_isMapInitialized) {
                _isMapInitialized = true;
              }
              await _toggleRailwayVisibilityWithoutFlip();
              await _updateUserLocation();
              await _updateTrainMarkers();
            },
            onCameraIdle: () async {
              final camera = _controller?.cameraPosition;
              if (camera != null) {
                _currentLocation =
                    latlong.LatLng(camera.target.latitude, camera.target.longitude);
                _currentZoom = camera.zoom;
                _currentRotation = camera.bearing;
                await _saveSettings();
              }
            },
          ),
          if (_isLoading)
            Container(
              color: const Color(0xFF121212).withValues(alpha: 0.8),
              child: const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF007ACC)),
                ),
              ),
            ),
          Positioned(
            right: 16,
            bottom: 80,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton(
                  heroTag: 'time_filter',
                  mini: true,
                  backgroundColor: const Color(0xFF1E1E1E),
                  onPressed: _showTimeFilterDialog,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.filter_list, color: Colors.white, size: 18),
                      Text(
                        _getTimeFilterLabel(),
                        style: const TextStyle(color: Colors.white, fontSize: 8),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                FloatingActionButton(
                  heroTag: 'refresh',
                  mini: true,
                  backgroundColor: const Color(0xFF1E1E1E),
                  onPressed: _refreshMap,
                  child: const Icon(Icons.refresh, color: Colors.white),
                ),
                const SizedBox(height: 8),
                FloatingActionButton(
                  heroTag: 'layers',
                  mini: true,
                  backgroundColor: const Color(0xFF1E1E1E),
                  onPressed: _toggleRailwayLayer,
                  child: Icon(
                    _isRailwayLayerVisible ? Icons.layers : Icons.layers_outlined,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                FloatingActionButton(
                  heroTag: 'location',
                  mini: true,
                  backgroundColor: const Color(0xFF1E1E1E),
                  onPressed: _centerToUserLocation,
                  child: const Icon(Icons.my_location, color: Colors.white),
                ),
                const SizedBox(height: 8),
                FloatingActionButton(
                  heroTag: 'last_train',
                  mini: true,
                  backgroundColor: const Color(0xFF1E1E1E),
                  onPressed: _centerToLastTrain,
                  child: const Icon(Icons.train, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleRailwayVisibilityWithoutFlip() async {
    if (_controller == null || !_isStyleLoaded) return;
    try {
      await _controller!.setLayerVisibility('railway', _isRailwayLayerVisible);
    } catch (_) {}
  }
}
