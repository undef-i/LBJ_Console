import 'dart:async';
import 'dart:math' show sin, cos, sqrt, atan2, pi;
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
  Timer? _locationTimer;

  String _selectedTimeFilter = 'unlimited';
  final Map<String, Duration> _timeFilterOptions = {
    'unlimited': Duration.zero,
    '1hour': Duration(hours: 1),
    '6hours': Duration(hours: 6),
    '12hours': Duration(hours: 12),
    '24hours': Duration(hours: 24),
    '7days': Duration(days: 7),
    '30days': Duration(days: 30),
  };

  @override
  void initState() {
    super.initState();
    print('=== 地图页面初始化 ===');
    _initializeMap();

    _checkDatabaseSettings();

    //
    _loadSettings().then((_) {
      print('设置加载完成，开始加载列车记录');
      _loadTrainRecords().then((_) {
        print('列车记录加载完成，开始位置更新');
        _startLocationUpdates();
      });
    });
  }

  Future<void> _checkDatabaseSettings() async {
    try {
      print('=== 检查数据库设置 ===');
      final dbInfo = await DatabaseService.instance.getDatabaseInfo();
      print('数据库信息: $dbInfo');

      final settings = await DatabaseService.instance.getAllSettings();
      print('数据库设置详情: $settings');

      if (settings != null) {
        final lat = settings['mapCenterLat'];
        final lon = settings['mapCenterLon'];
        print('数据库中的位置坐标: lat=$lat, lon=$lon');

        if (lat != null && lon != null) {
          if (lat == 39.9042 && lon == 116.4074) {
            print('警告：数据库中保存的是北京默认坐标');
          } else if (lat == 0.0 && lon == 0.0) {
            print('警告：数据库中保存的是零坐标');
          } else {
            print('数据库中保存的是有效坐标');
            final beijingLat = 39.9042;
            final beijingLon = 116.4074;
            final distance =
                _calculateDistance(lat, lon, beijingLat, beijingLon);
            print('与北京市中心的距离: ${distance.toStringAsFixed(2)} 公里');

            if (distance < 50) {
              print('注意：保存的位置在北京附近（距离 < 50公里）');
            }
          }
        }
      }
    } catch (e) {
      print('检查数据库设置失败: $e');
    }
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
    _saveSettings();
    _locationTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeMap() async {}

  Future<void> _requestLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
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
      print('=== 获取当前位置 ===');
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        forceAndroidLocationManager: true,
      );

      final newLocation = LatLng(position.latitude, position.longitude);
      print('获取到位置: $newLocation');
      setState(() {
        _userLocation = newLocation;
      });

      if (!_isMapInitialized) {
        print('获取位置后尝试初始化地图');
        _initializeMapPosition();
      }
    } catch (e) {
      print('获取位置失败: $e');
    }
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
        desiredAccuracy: LocationAccuracy.best,
        forceAndroidLocationManager: true,
      );

      final newLocation = LatLng(position.latitude, position.longitude);

      setState(() {
        _userLocation = newLocation;
      });

      _mapController.move(newLocation, 15.0);
    } catch (e) {
      print('强制更新位置失败: $e');
    }
  }

  Future<void> _loadSettings() async {
    try {
      print('=== 开始加载设置 ===');
      final settings = await DatabaseService.instance.getAllSettings();
      print('设置数据: $settings');
      if (settings != null) {
        print(
            '设置中的位置: lat=${settings['mapCenterLat']}, lon=${settings['mapCenterLon']}');
        print('设置中的缩放: ${settings['mapZoomLevel']}');
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
            print('使用保存的位置: $_currentLocation');
          } else {
            print('保存的位置无效或为零，不使用');
          }
        });
        print('设置加载完成，当前位置: $_currentLocation');
        if (!_isMapInitialized) {
          print('设置加载后尝试初始化地图');
          _initializeMapPosition();
        }
      } else {
        print('没有保存的设置数据');
      }
    } catch (e) {
      print('加载设置失败: $e');
    }
  }

  Future<void> _saveSettings() async {
    try {
      print('=== 保存设置到数据库 ===');
      print('当前旋转角度: $_currentRotation');
      print('当前缩放级别: $_currentZoom');
      print('当前位置: $_currentLocation');

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

      print('保存的设置数据: $settings');
      await DatabaseService.instance.updateSettings(settings);
      print('=== 设置保存成功 ===');
    } catch (e) {
      print('保存设置失败: $e');
    }
  }

  Future<void> _loadTrainRecords() async {
    setState(() => _isLoading = true);
    try {
      print('=== 开始加载列车记录 ===');
      final records = await _getFilteredRecords();
      print('加载到 ${records.length} 条记录');
      setState(() {
        _trainRecords.clear();
        _trainRecords.addAll(records);
        _isLoading = false;

        if (_trainRecords.isNotEmpty) {
          final lastRecord = _trainRecords.first;
          print(
              '最新记录: ${lastRecord.fullTrainNumber}, 位置: ${lastRecord.position}');
          final coords = lastRecord.getCoordinates();
          final dmsCoords = _parseDmsCoordinate(lastRecord.positionInfo);

          if (dmsCoords != null) {
            _lastTrainLocation = dmsCoords;
            print('使用DMS坐标: $dmsCoords');
          } else if (coords['lat'] != 0.0 && coords['lng'] != 0.0) {
            _lastTrainLocation = LatLng(coords['lat']!, coords['lng']!);
            print('使用解析坐标: $_lastTrainLocation');
          } else {
            print('记录中没有有效坐标');
          }
        } else {
          print('没有列车记录');
        }

        print('列车位置: $_lastTrainLocation');
        if (!_isMapInitialized) {
          print('列车记录加载后尝试初始化地图');
          _initializeMapPosition();
        }
      });
    } catch (e) {
      setState(() => _isLoading = false);
      print('加载列车记录失败: $e');
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

    print('=== 初始化地图位置 ===');
    print('当前位置: $_currentLocation');
    print('列车位置: $_lastTrainLocation');
    print('用户位置: $_userLocation');
    print('地图已初始化: $_isMapInitialized');

    if (_currentLocation != null) {
      targetLocation = _currentLocation;
      print('使用保存的坐标: $targetLocation');
    } else if (_lastTrainLocation != null) {
      targetLocation = _lastTrainLocation;
      print('使用列车位置: $targetLocation');
    } else if (_userLocation != null) {
      targetLocation = _userLocation;
      print('使用用户位置: $targetLocation');
    } else {
      targetLocation = const LatLng(39.9042, 116.4074);
      print('没有可用位置，使用北京默认位置: $targetLocation');
    }

    print('最终选择位置: $targetLocation');
    print('当前旋转角度: $_currentRotation');
    _centerMap(targetLocation!, zoom: _currentZoom, rotation: _currentRotation);
    _isMapInitialized = true;
    print('地图初始化完成，旋转角度: $_currentRotation');
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
            height: 16,
            child: GestureDetector(
              onTap: () => position != null
                  ? _showTrainDetailsDialog(record, position)
                  : null,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      trainDisplay,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
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
    if (_userLocation != null) {
      _centerMap(_userLocation!, zoom: 15.0, rotation: _currentRotation);
    }
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
        _centerMap(targetPosition, zoom: 15.0, rotation: _currentRotation);
      }
    }
  }

  void _showTimeFilterDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('时间筛选'),
          content: SizedBox(
            width: double.minPositive,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _timeFilterOptions.keys.map((key) {
                return RadioListTile<String>(
                  title: Text(_getTimeFilterLabel(key)),
                  value: key,
                  groupValue: _selectedTimeFilter,
                  onChanged: (String? value) {
                    if (value != null) {
                      setState(() {
                        _selectedTimeFilter = value;
                      });
                      _loadTrainRecords();
                      Navigator.pop(context);
                    }
                  },
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
          ],
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

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentLocation ??
                  _lastTrainLocation ??
                  _userLocation ??
                  const LatLng(39.9042, 116.4074),
              initialZoom: _currentZoom,
              initialRotation: _currentRotation,
              minZoom: 4.0,
              maxZoom: 18.0,
              onPositionChanged: (MapCamera camera, bool hasGesture) {
                setState(() {
                  _currentLocation = camera.center;
                  _currentZoom = camera.zoom;
                  _currentRotation = camera.rotation;
                });

                _saveSettings();
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
                  heroTag: 'timeFilter',
                  backgroundColor: const Color(0xFF1E1E1E),
                  onPressed: _showTimeFilterDialog,
                  child: const Icon(Icons.filter_list, color: Colors.white),
                ),
                const SizedBox(height: 8),
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
                    _forceUpdateLocation();
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
