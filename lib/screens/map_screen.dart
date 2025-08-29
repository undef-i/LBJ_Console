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
  bool _isLoading = true;
  bool _railwayLayerVisible = true;
  LatLng? _currentLocation;
  LatLng? _lastTrainLocation;
  LatLng? _userLocation;
  double _currentZoom = 12.0;
  double _currentRotation = 0.0;

  bool _isMapInitialized = false;
  bool _isFollowingLocation = false;
  bool _isLocationPermissionGranted = false;

  static const LatLng _defaultPosition = LatLng(39.9042, 116.4074);

  @override
  void initState() {
    super.initState();
    _initializeMap();
    _loadTrainRecords();
    _loadSettings();
    _requestLocationPermission();
  }

  @override
  void dispose() {
    _saveSettings();
    super.dispose();
  }

  Future<void> _initializeMap() async {}

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
      );

      setState(() {
        _userLocation = LatLng(position.latitude, position.longitude);
      });

      if (!_isMapInitialized && _userLocation != null) {
        _mapController.move(_userLocation!, _currentZoom);
      }
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

          final lat = (settings['mapCenterLat'] as num?)?.toDouble();
          final lon = (settings['mapCenterLon'] as num?)?.toDouble();

          if (lat != null && lon != null) {
            _currentLocation = LatLng(lat, lon);
          }
        });
      }
    } catch (e) {}
  }

  Future<void> _saveSettings() async {
    try {
      final center = _mapController.camera.center;
      await DatabaseService.instance.updateSettings({
        'mapRailwayLayerVisible': _railwayLayerVisible ? 1 : 0,
        'mapZoomLevel': _currentZoom,
        'mapCenterLat': center.latitude,
        'mapCenterLon': center.longitude,
        'mapRotation': _currentRotation,
      });
    } catch (e) {}
  }

  Future<void> _loadTrainRecords() async {
    setState(() => _isLoading = true);
    try {
      final records = await DatabaseService.instance.getAllRecords();
      setState(() {
        _trainRecords.clear();
        _trainRecords.addAll(records);
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

        _initializeMapPosition();
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _initializeMapPosition() {
    if (_isMapInitialized) return;

    LatLng? targetLocation;

    if (_currentLocation != null) {
      targetLocation = _currentLocation;
    } else if (_userLocation != null) {
      targetLocation = _userLocation;
    } else if (_lastTrainLocation != null) {
      targetLocation = _lastTrainLocation;
    } else {
      targetLocation = _defaultPosition;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _centerMap(targetLocation!, zoom: _currentZoom);
      _isMapInitialized = true;
    });
  }

  void _centerMap(LatLng location, {double? zoom}) {
    _mapController.move(location, zoom ?? _currentZoom);
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
    } catch (e) {
      print('解析DMS坐标失败: $e');
    }

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

  List<Marker> _buildTrainMarkers() {
    final markers = <Marker>[];
    final validRecords = [..._getValidRecords(), ..._getValidDmsRecords()];

    for (final record in validRecords) {
      LatLng? position;

      final dmsPosition = _parseDmsCoordinate(record.positionInfo);
      if (dmsPosition != null) {
        position = dmsPosition;
      } else {
        final coords = record.getCoordinates();
        if (coords['lat'] != 0.0 && coords['lng'] != 0.0) {
          position = LatLng(coords['lat']!, coords['lng']!);
        }
      }

      if (position != null) {
        final trainDisplay =
            record.fullTrainNumber.isEmpty ? "未知列车" : record.fullTrainNumber;

        markers.add(
          Marker(
            point: position,
            width: 80,
            height: 60,
            child: GestureDetector(
              onTap: () => position != null
                  ? _showTrainDetailsDialog(record, position)
                  : null,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(
                      Icons.train,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Text(
                      trainDisplay,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
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

  void _centerToMyLocation() {
    _centerMap(_lastTrainLocation ?? _defaultPosition, zoom: 15.0);
  }

  void _centerToLastTrain() {
    if (_trainRecords.isNotEmpty) {
      final lastRecord = _trainRecords.first;
      final coords = lastRecord.getCoordinates();
      final dmsCoords = _parseDmsCoordinate(lastRecord.positionInfo);

      LatLng? targetPosition;
      if (dmsCoords != null) {
        targetPosition = dmsCoords;
      } else if (coords['lat'] != 0.0 && coords['lng'] != 0.0) {
        targetPosition = LatLng(coords['lat']!, coords['lng']!);
      }

      if (targetPosition != null) {
        _centerMap(targetPosition, zoom: 15.0);
      }
    }
  }

  void _showTrainDetailsDialog(TrainRecord record, LatLng position) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
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
                        .surfaceVariant
                        .withOpacity(0.3),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _buildMaterial3DetailRow(
                            context, "时间", record.formattedTime),
                        _buildMaterial3DetailRow(
                            context, "日期", record.formattedDate),
                        _buildMaterial3DetailRow(
                            context, "类型", record.trainType),
                        _buildMaterial3DetailRow(
                            context, "速度", "${record.speed} km/h"),
                        _buildMaterial3DetailRow(
                            context, "位置", record.position),
                        _buildMaterial3DetailRow(context, "路线", record.route),
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
                          _centerMap(position, zoom: 17.0);
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

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? "未知" : value,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMaterial3DetailRow(
      BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
    final markers = _buildTrainMarkers();

    if (_userLocation != null) {
      markers.add(
        Marker(
          point: _userLocation!,
          width: 40,
          height: 40,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blue,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Icon(
              Icons.my_location,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _lastTrainLocation ?? _defaultPosition,
              initialZoom: _currentZoom,
              initialRotation: _currentRotation,
              minZoom: 4.0,
              maxZoom: 18.0,
              onPositionChanged: (MapCamera camera, bool hasGesture) {
                if (hasGesture) {
                  setState(() {
                    _currentLocation = camera.center;
                    _currentZoom = camera.zoom;
                    _currentRotation = camera.rotation;
                  });
                  _saveSettings();
                }
              },
              onTap: (_, point) {
                for (final record in _trainRecords) {
                  final coords = record.getCoordinates();
                  final dmsCoords = _parseDmsCoordinate(record.positionInfo);
                  LatLng? recordPosition;

                  if (dmsCoords != null) {
                    recordPosition = dmsCoords;
                  } else if (coords['lat'] != 0.0 && coords['lng'] != 0.0) {
                    recordPosition = LatLng(coords['lat']!, coords['lng']!);
                  }

                  if (recordPosition != null) {
                    final distance = const Distance()
                        .as(LengthUnit.Meter, recordPosition, point);
                    if (distance < 50) {
                      _showTrainDetailsDialog(record, recordPosition);
                      break;
                    }
                  }
                }
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
                  userAgentPackageName: 'org.noxylva.lbjconsole',
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
          Positioned(
            right: 16,
            top: 40,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'railwayLayer',
                  backgroundColor: const Color(0xFF1E1E1E),
                  onPressed: () {
                    setState(() {
                      _railwayLayerVisible = !_railwayLayerVisible;
                    });
                    _saveSettings();
                  },
                  child: Icon(
                    _railwayLayerVisible ? Icons.layers : Icons.layers_outlined,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'myLocation',
                  backgroundColor: const Color(0xFF1E1E1E),
                  onPressed: () {
                    _getCurrentLocation();
                    if (_userLocation != null) {
                      _centerMap(_userLocation!, zoom: 15.0);
                    }
                  },
                  child: const Icon(Icons.my_location, color: Colors.white),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
