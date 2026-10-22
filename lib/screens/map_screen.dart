import 'dart:async';
import 'dart:math' show sin, cos, sqrt, atan2;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lbjconsole/services/database_service.dart';
import 'package:lbjconsole/models/train_record.dart';
import 'package:lbjconsole/ui/web_map.dart';
import 'package:lbjconsole/ui/glass_morph_menu.dart';
import 'package:lbjconsole/models/merged_record.dart';
import 'package:lbjconsole/services/merge_service.dart';
import 'package:lbjconsole/ui/glass_styles.dart';
import 'package:lbjconsole/ui/glass_buttons.dart';
import 'package:lbjconsole/ui/glass_clipper.dart';
import 'package:lbjconsole/ui/liquid_glass.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  WebMapController _webMap = WebMapController();
  int _mapGeneration = 0;
  bool _mapReady = false;
  bool _styleFailed = false;
  bool _ormDark = false;
  final List<TrainRecord> _trainRecords = [];
  bool _isLoading = true;
  bool _railwayLayerVisible = true;
  LatLng? _currentLocation;
  LatLng? _lastTrainLocation;
  LatLng? _userLocation;
  double _currentZoom = 14.0;
  double _currentRotation = 0.0;

  bool _positionReady = false;
  bool _isLocationPermissionGranted = false;
  Timer? _locationTimer;
  Timer? _settingsSaveTimer;

  String _selectedTimeFilter = 'unlimited';
  MergeSettings _mergeSettings = MergeSettings();
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (_ormDark != dark) {
      _ormDark = dark;
      _webMap.setTheme(dark);
    }
  }

  @override
  void initState() {
    super.initState();
    _initializeMap();

    _checkDatabaseSettings();

    _loadSettings().then((_) {
      _loadTrainRecords().then((_) {
        _startLocationUpdates();
        if (mounted) {
          setState(() => _positionReady = true);
        }
      });
    });
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
      _pushMapData();
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

      _pushMapData();
      _webMap.moveTo(newLocation, 15.0);
    // ignore: empty_catches
    } catch (e) {}
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await DatabaseService.instance.getAllSettings();
      if (settings != null) {
        _mergeSettings = MergeSettings.fromMap(settings);
        setState(() {
          _railwayLayerVisible =
              (settings['mapRailwayLayerVisible'] as int?) != 0;
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
      }
    // ignore: empty_catches
    } catch (e) {}
  }

  Future<void> _saveSettings() async {
    try {
      final center = _currentLocation ?? const LatLng(39.9042, 116.4074);

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
    if (_trainRecords.isEmpty) {
      setState(() => _isLoading = true);
    }
    try {
      final records = await _getFilteredRecords();
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

      });
      _pushMapData();
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

  void _centerMap(LatLng location, {double? zoom, double? rotation}) {
    _currentLocation = location;
    if (zoom != null) _currentZoom = zoom;
    if (rotation != null) _currentRotation = rotation;
    _webMap.moveTo(
      location,
      zoom ?? _currentZoom,
      bearing: rotation ?? _currentRotation,
    );
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

  String _chipLabel(TrainRecord record) =>
      record.fullTrainNumber.isEmpty ? '未知列车' : record.fullTrainNumber;

  // The map's data, grouped the way the monitoring map groups: a
  // merged group's records draw as one black route line through
  // their positions with the train chip at its end; a single record
  // keeps its own chip. Every positioned record is also a tap
  // target (nearest within 28 screen px, resolved in the page).
  void _pushMapData() {
    final lines = <List<LatLng>>[];
    final chips = <WebMapChip>[];
    final dots = <WebMapDot>[];
    final hits = <WebMapHit>[];
    final mixed = MergeService.getMixedList(_trainRecords, _mergeSettings);
    for (final item in mixed) {
      if (item is TrainRecord) {
        final position = _positionForRecord(item);
        if (position == null) continue;
        chips.add(
          WebMapChip(id: item.uniqueId, position: position, label: _chipLabel(item)),
        );
      } else if (item is MergedTrainRecord) {
        final entries = <MapEntry<TrainRecord, LatLng>>[];
        for (final record in item.records) {
          final position = _positionForRecord(record);
          if (position != null) entries.add(MapEntry(record, position));
        }
        if (entries.length >= 2) {
          lines.add(
            entries.map((entry) => entry.value).toList().reversed.toList(),
          );
        }
        if (entries.isNotEmpty) {
          chips.add(
            WebMapChip(
              id: entries.first.key.uniqueId,
              position: entries.first.value,
              label: _chipLabel(entries.first.key),
            ),
          );
        }
      }
    }
    for (final record in _trainRecords) {
      final position = _positionForRecord(record);
      if (position != null) {
        hits.add(WebMapHit(id: record.uniqueId, position: position));
      }
    }
    final location = _userLocation;
    if (location != null) {
      dots.add(WebMapDot(position: location, location: true));
    }
    _webMap.setData(lines: lines, chips: chips, dots: dots, hits: hits);
  }

  void _onChipTap(String id) {
    for (final record in _trainRecords) {
      if (record.uniqueId != id) continue;
      final position = _positionForRecord(record);
      if (position != null && mounted) {
        _showTrainDetailsDialog(record, position);
      }
      return;
    }
  }

  void _onCameraIdle(LatLng center, double zoom, double bearing) {
    _currentLocation = center;
    _currentZoom = zoom;
    _currentRotation = bearing;
    _scheduleSettingsSave();
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
        return Stack(
          children: [
            Positioned.fill(
              child: LiquidGlass(
                style: glassMenuStyle(Theme.of(context).colorScheme),
                clipper: const SuperellipseClipper(
                  BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: const SizedBox.expand(),
              ),
            ),
            Container(
              width: double.infinity,
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
                        .onSurface
                        .withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
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
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context),
                        style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.08),
                          foregroundColor:
                              Theme.of(context).colorScheme.onSurface,
                        ),
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
          ),
          ],
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
    final bool isDefaultLocation = !_positionReady;

    return Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.endTop,
      floatingActionButton: Padding(
        padding: EdgeInsets.only(
            top: MediaQuery.paddingOf(context).top + 72),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GlassMorphMenu(
              menuWidth: 200,
              triggerBuilder: (context, toggle) => GlassIconButton(
                icon: Icons.filter_list,
                onPressed: toggle,
              ),
              menuBuilder: (context, close) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final key in _timeFilterOptions.keys)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          setState(() {
                            _selectedTimeFilter = key;
                          });
                          _loadTrainRecords();
                          close();
                        },
                        child: SizedBox(
                          height: 44,
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                Expanded(
                                    child: Text(_getTimeFilterLabel(key))),
                                if (_selectedTimeFilter == key)
                                  Icon(Icons.check,
                                      size: 24,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            GlassIconButton(
              icon: _railwayLayerVisible
                  ? Icons.layers
                  : Icons.layers_outlined,
              onPressed: () {
                setState(() {
                  _railwayLayerVisible = !_railwayLayerVisible;
                });
                _webMap.setOrm(_railwayLayerVisible);
                _settingsSaveTimer?.cancel();
                _saveSettings();
              },
            ),
            const SizedBox(height: 8),
            GlassIconButton(
              icon: Icons.my_location,
              onPressed: () {
                _forceUpdateLocation();
              },
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          if (isDefaultLocation)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.onSurface),
                  ),
                  SizedBox(height: 16),
                  Text(
                    '正在加载地图位置...',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 16),
                  ),
                ],
              ),
            )
          else if (_styleFailed)
            Center(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _styleFailed = false;
                    _mapReady = false;
                    _mapGeneration++;
                    _webMap = WebMapController();
                  });
                },
                child: Text(
                  '地图样式加载失败，点按重试',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 16),
                ),
              ),
            )
          else ...[
            WebMapView(
              key: ValueKey(_mapGeneration),
              controller: _webMap,
              initialCenter: _currentLocation ??
                  _lastTrainLocation ??
                  _userLocation ??
                  const LatLng(39.9042, 116.4074),
              initialZoom: _currentZoom,
              initialBearing: _currentRotation,
              minZoom: 2,
              maxZoom: 18,
              interactive: true,
              hybridComposition: true,
              orm: true,
              ormVisible: _railwayLayerVisible,
              dark: Theme.of(context).brightness == Brightness.dark,
              onReady: () {
                if (mounted) setState(() => _mapReady = true);
              },
              onError: () {
                if (mounted) setState(() => _styleFailed = true);
              },
              onCameraIdle: _onCameraIdle,
              onChipTap: _onChipTap,
            ),
            if (!_mapReady)
              Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).colorScheme.onSurface),
                ),
              ),
          ],
          if (_isLoading)
            Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.onSurface),
              ),
            ),
        ],
      ),
    );
  }
}
