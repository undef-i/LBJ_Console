import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import '../models/train_record.dart';
import 'package:lbjconsole/services/database_service.dart';
import 'package:latlong2/latlong.dart';

class MapWebViewScreen extends StatefulWidget {
  const MapWebViewScreen({super.key});

  @override
  State<MapWebViewScreen> createState() => MapWebViewScreenState();
}

class MapWebViewScreenState extends State<MapWebViewScreen>
    with WidgetsBindingObserver {
  late final WebViewController _controller;
  Position? _currentPosition;
  List<TrainRecord> _trainRecords = [];
  bool _isRailwayLayerVisible = true;
  bool _isLoading = true;
  String _timeFilter = 'unlimited';
  Timer? _refreshTimer;
  Timer? _locationUpdateTimer;

  bool _isMapInitialized = false;
  bool _isLocationPermissionGranted = false;
  double _currentZoom = 14.0;
  double _currentRotation = 0.0;
  LatLng? _currentLocation;
  LatLng? _lastTrainLocation;
  bool _isDataLoaded = false;
  final Completer<void> _webViewReadyCompleter = Completer<void>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeWebView();
    _startInitialization();
  }

  Future<void> _startInitialization() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await _loadSettings();
      await _loadTrainRecordsFromDatabase();

      await _webViewReadyCompleter.future;

      _initializeMapCamera();

      _initializeLocation();
      _startAutoRefresh();
    } catch (e, s) {
      print('[Flutter] Init Map WebView Screen Failed: $e\n$s');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reloadSettingsIfNeeded();
    }
  }

  Future<void> _initializeWebView() async {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF121212))
      ..addJavaScriptChannel(
        'showTrainDetails',
        onMessageReceived: (JavaScriptMessage message) {
          try {
            final trainData = jsonDecode(message.message);
            _showTrainDetailsDialog(trainData);
          } catch (e) {}
        },
      )
      ..addJavaScriptChannel(
        'onMapStateChanged',
        onMessageReceived: (JavaScriptMessage message) {
          try {
            final mapState = jsonDecode(message.message);
            _onMapStateChanged(mapState);
          } catch (e) {}
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {},
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });

            if (!_webViewReadyCompleter.isCompleted) {
              _webViewReadyCompleter.complete();
            }
          },
          onWebResourceError: (WebResourceError error) {
            setState(() {
              _isLoading = false;
            });
          },
        ),
      )
      ..loadFlutterAsset('assets/mapbox_map.html')
          .then((_) {})
          .catchError((error) {});

    await Future.delayed(const Duration(milliseconds: 500));
  }

  Future<void> _initializeLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('请开启定位服务')),
          );
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        Position position = await Geolocator.getCurrentPosition(
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
      } else if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('定位权限被永久拒绝，请在设置中开启')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('定位权限被拒绝，请在设置中开启')),
          );
        }
      }
    } catch (e) {}
  }

  void _startLocationUpdates() {
    _locationUpdateTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isLocationPermissionGranted && mounted) {
        _updateCurrentLocation();
      } else {}
    });
  }

  Future<void> _updateCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        forceAndroidLocationManager: true,
      );

      setState(() {
        _currentPosition = position;
      });

      _updateUserLocation();
    } catch (e) {
      if (e.toString().contains('PERMISSION_DENIED') ||
          e.toString().contains('permission')) {
        _checkAndRequestPermissions();
      }
    }
  }

  Future<void> _checkAndRequestPermissions() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        setState(() {
          _isLocationPermissionGranted = true;
        });
      } else {
        setState(() {
          _isLocationPermissionGranted = false;
        });
      }
    } catch (e) {}
  }

  Future<void> _loadTrainRecordsFromDatabase() async {
    try {
      final isConnected = await DatabaseService.instance.isDatabaseConnected();
      if (!isConnected) {}

      List<TrainRecord> records;

      if (_timeFilter == 'unlimited') {
        records = await DatabaseService.instance.getAllRecords();
      } else {
        final duration = _getTimeFilterDuration(_timeFilter);
        if (duration != null && duration != Duration.zero) {
          records = await DatabaseService.instance
              .getRecordsWithinReceivedTimeRange(duration);
        } else {
          records = await DatabaseService.instance.getAllRecords();
        }
      }

      if (records.isNotEmpty) {
        for (int i = 0; i < math.min(3, records.length); i++) {
          final record = records[i];
          final coords = record.getCoordinates();
        }
      }

      setState(() {
        _trainRecords = records;
        _isLoading = false;

        if (_trainRecords.isNotEmpty) {
          final validRecords = [
            ..._getValidRecords(),
            ..._getValidDmsRecords()
          ];
          if (validRecords.isNotEmpty) {
            final lastRecord = validRecords.first;
            LatLng? position;

            final dmsPosition = _parseDmsCoordinate(lastRecord.positionInfo);
            if (dmsPosition != null) {
              position = dmsPosition;
            } else {
              final coords = lastRecord.getCoordinates();
              if (coords['lat'] != 0.0 && coords['lng'] != 0.0) {
                position = LatLng(coords['lat']!, coords['lng']!);
              }
            }

            if (position != null) {
              _lastTrainLocation = position;
            } else {}
          } else {}
        } else {}
      });

      Future.delayed(const Duration(milliseconds: 3000), () {
        if (mounted) {
          _updateTrainMarkers();
        }
      });

      Future.delayed(const Duration(milliseconds: 5000), () {
        if (mounted) {
          _updateTrainMarkers();
        }
      });
    } catch (e, stackTrace) {
      setState(() {
        _isLoading = false;
      });
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
      if (settings != null) {
        final newTimeFilter =
            settings['mapTimeFilter'] as String? ?? 'unlimited';
        if (newTimeFilter != _timeFilter) {
          if (mounted) {
            setState(() {
              _timeFilter = newTimeFilter;
            });
          }
          _loadTrainRecordsFromDatabase();
        }
      }
    } catch (e) {}
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reloadSettingsIfNeeded();
  }

  void _loadTrainRecords() async {
    setState(() => _isLoading = true);
    try {
      await _loadTrainRecordsFromDatabase();
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _initializeMapCamera() {
    if (_isMapInitialized) return;

    LatLng targetLocation;
    double targetZoom = _currentZoom;
    double targetRotation = _currentRotation;

    if (_currentLocation != null) {
      targetLocation = _currentLocation!;
    } else if (_lastTrainLocation != null) {
      targetLocation = _lastTrainLocation!;
      targetZoom = 14.0;
      targetRotation = 0.0;
    } else {
      targetLocation = const LatLng(39.9042, 116.4074);
      targetZoom = 10.0;
    }

    _centerMap(targetLocation, zoom: targetZoom, rotation: targetRotation);
    _isMapInitialized = true;

    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _updateUserLocation();
        _updateTrainMarkers();
        _controller.runJavaScript('''
          if (window.MapInterface) {
            window.MapInterface.setRailwayVisible($_isRailwayLayerVisible);
          }
        ''');
      }
    });
  }

  void _centerMap(LatLng location, {double? zoom, double? rotation}) {
    final targetZoom = zoom ?? _currentZoom;
    final targetRotation = rotation ?? _currentRotation;

    _controller.runJavaScript('''
      (function() {
        if (window.MapInterface) {
          try {
            window.MapInterface.setCenter(${location.latitude}, ${location.longitude}, $targetZoom, $targetRotation);
          } catch (error) {
          }
        }
      })();
    ''').then((result) {}).catchError((error) {});
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await DatabaseService.instance.getAllSettings();
      if (settings != null) {
        setState(() {
          _isRailwayLayerVisible =
              (settings['mapRailwayLayerVisible'] as int?) == 1;
          _currentZoom = (settings['mapZoomLevel'] as num?)?.toDouble() ?? 10.0;
          _currentRotation =
              (settings['mapRotation'] as num?)?.toDouble() ?? 0.0;
          _timeFilter = settings['mapTimeFilter'] as String? ?? 'unlimited';

          final lat = (settings['mapCenterLat'] as num?)?.toDouble();
          final lon = (settings['mapCenterLon'] as num?)?.toDouble();

          if (lat != null && lon != null && lat != 0.0 && lon != 0.0) {
            _currentLocation = LatLng(lat, lon);
          }
        });
      }
    } catch (e) {}
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
    } catch (e) {}
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

  void _updateTrainMarkers() {
    if (_trainRecords.isEmpty) {
      return;
    }

    if (!_isMapInitialized) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && _trainRecords.isNotEmpty) {
          _updateTrainMarkers();
        }
      });
      return;
    }

    final validRecords = [..._getValidRecords(), ..._getValidDmsRecords()];

    final trainData = validRecords
        .map((record) {
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
            return {
              'lat': position.latitude,
              'lng': position.longitude,
              'fullTrainNumber': record.fullTrainNumber,
              'time': record.time,
              'speed': record.speed,
              'position': record.position,
              'route': record.route,
              'locoType': record.locoType,
              'loco': record.loco,
              'timestamp': record.timestamp,
            };
          }
          return null;
        })
        .where((data) => data != null)
        .toList();

    trainData.sort((a, b) {
      final aTimestamp = a?['timestamp'];
      final bTimestamp = b?['timestamp'];

      if (aTimestamp == null || bTimestamp == null) return 0;

      if (aTimestamp is DateTime && bTimestamp is DateTime) {
        return bTimestamp.compareTo(aTimestamp);
      }

      if (aTimestamp is int && bTimestamp is int) {
        return bTimestamp.compareTo(aTimestamp);
      }

      if (aTimestamp is String && bTimestamp is String) {
        return bTimestamp.compareTo(aTimestamp);
      }

      return 0;
    });

    final jsonTrainData = trainData
        .map((train) {
          if (train == null) return null;

          final trainCopy = Map<String, dynamic>.from(train);

          if (trainCopy['timestamp'] is DateTime) {
            trainCopy['timestamp'] =
                (trainCopy['timestamp'] as DateTime).millisecondsSinceEpoch;
          }

          return trainCopy;
        })
        .where((train) => train != null)
        .toList();

    if (trainData.isEmpty) {
      return;
    }

    if (trainData.isNotEmpty) {
      final latestTrain = trainData.first;
      if (latestTrain != null) {
        _lastTrainLocation = LatLng((latestTrain['lat'] as num).toDouble(),
            (latestTrain['lng'] as num).toDouble());
      }
    }

    _controller.runJavaScript('''
      (function() {
        try {
          if (window.MapInterface && window.MapInterface.updateTrainMarkers) {
            window.MapInterface.updateTrainMarkers(${jsonEncode(jsonTrainData)});

            if (!window.trainMarkersUpdated && ${trainData.length} > 0) {
              window.trainMarkersUpdated = true;
              setTimeout(function() {
                if (window.MapInterface && window.MapInterface.fitBounds) {
                  window.MapInterface.fitBounds();
                }
              }, 1000);
            }
          } else {
            console.error('MapInterface 未定义或updateTrainMarkers方法不存在');
          }
        } catch (error) {
          console.error('更新列车标记失败:', error);
        }
      })();
    ''').then((result) {}).catchError((error) {});
  }

  void _updateUserLocation() {
    if (_currentPosition != null) {
      _controller.runJavaScript('''
        (function() {
          try {
            if (window.MapInterface && window.MapInterface.setUserLocation) {
              window.MapInterface.setUserLocation(${_currentPosition!.latitude}, ${_currentPosition!.longitude});

              if (!window.userLocationUpdated) {
                window.userLocationUpdated = true;
              }
            } else {
              console.error('MapInterface 未定义或setUserLocation方法不存在');
            }
          } catch (error) {
            console.error('更新用户位置失败:', error);
          }
        })();
      ''').then((_) {}).catchError((error) {});
    } else {}
  }

  void _toggleRailwayLayer() {
    setState(() {
      _isRailwayLayerVisible = !_isRailwayLayerVisible;
    });

    _controller.runJavaScript('''
      (function() {
        if (window.MapInterface) {
          try {
            window.MapInterface.setRailwayVisible($_isRailwayLayerVisible);
            console.log('铁路图层切换成功: $_isRailwayLayerVisible');
          } catch (error) {
            console.error('切换铁路图层失败:', error);
          }
        } else {
          console.error('MapInterface 未定义');
        }
      })();
    ''').then((result) {}).catchError((error) {});
  }

  void _showTrainDetailsDialog(Map<String, dynamic> train) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: Text(
            train['trainNumber'] ?? '未知车次',
            style: const TextStyle(color: Colors.white),
          ),
          content: SingleChildScrollView(
            child: ListBody(
              children: [
                _buildDetailRow('车次', train['trainNumber'] ?? '未知'),
                _buildDetailRow('类型', train['trainType'] ?? '未知'),
                _buildDetailRow('速度', '${train['speed'] ?? 0} km/h'),
                _buildDetailRow('方向', '${train['direction'] ?? 0}°'),
                _buildDetailRow(
                    '经度', train['longitude']?.toStringAsFixed(6) ?? '未知'),
                _buildDetailRow(
                    '纬度', train['latitude']?.toStringAsFixed(6) ?? '未知'),
                _buildDetailRow('时间', _getDisplayTime(train['timestamp'])),
                _buildDetailRow('日期', _getDisplayDate(train['timestamp'])),
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
                _controller.runJavaScript('''
                  if (window.MapInterface) {
                    window.MapInterface.setCenter(${train['latitude']}, ${train['longitude']}, 16);
                  }
                ''');
              },
              child:
                  const Text('定位', style: TextStyle(color: Color(0xFF007ACC))),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getDisplayTime(int? timestamp) {
    if (timestamp == null) return '未知';
    final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
  }

  String _getDisplayDate(int? timestamp) {
    if (timestamp == null) return '未知';
    final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
  }

  void _showTimeFilterDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return SimpleDialog(
          title: const Text('时间筛选'),
          children: [
            SimpleDialogOption(
              onPressed: () {
                setState(() {
                  _timeFilter = 'unlimited';
                });
                Navigator.of(context).pop();
                _saveSettingsAndReload();
              },
              child: const Text('无限制'),
            ),
            SimpleDialogOption(
              onPressed: () {
                setState(() {
                  _timeFilter = '1hour';
                });
                Navigator.of(context).pop();
                _saveSettingsAndReload();
              },
              child: const Text('最近1小时'),
            ),
            SimpleDialogOption(
              onPressed: () {
                setState(() {
                  _timeFilter = '6hours';
                });
                Navigator.of(context).pop();
                _saveSettingsAndReload();
              },
              child: const Text('最近6小时'),
            ),
            SimpleDialogOption(
              onPressed: () {
                setState(() {
                  _timeFilter = '12hours';
                });
                Navigator.of(context).pop();
                _saveSettingsAndReload();
              },
              child: const Text('最近12小时'),
            ),
            SimpleDialogOption(
              onPressed: () {
                setState(() {
                  _timeFilter = '24hours';
                });
                Navigator.of(context).pop();
                _saveSettingsAndReload();
              },
              child: const Text('最近24小时'),
            ),
            SimpleDialogOption(
              onPressed: () {
                setState(() {
                  _timeFilter = '7days';
                });
                Navigator.of(context).pop();
                _saveSettingsAndReload();
              },
              child: const Text('最近7天'),
            ),
            SimpleDialogOption(
              onPressed: () {
                setState(() {
                  _timeFilter = '30days';
                });
                Navigator.of(context).pop();
                _saveSettingsAndReload();
              },
              child: const Text('最近30天'),
            ),
          ],
        );
      },
    );
  }

  void _saveSettingsAndReload() async {
    try {
      await _saveSettings();
      _loadTrainRecordsFromDatabase();
    } catch (e) {}
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

  void _onMapStateChanged(Map<String, dynamic> mapState) {
    try {
      final lat = (mapState['lat'] as num).toDouble();
      final lng = (mapState['lng'] as num).toDouble();
      final zoom = (mapState['zoom'] as num).toDouble();
      final bearing = (mapState['bearing'] as num).toDouble();

      setState(() {
        _currentLocation = LatLng(lat, lng);
        _currentZoom = zoom;
        _currentRotation = bearing;
      });

      Future.microtask(() {
        if (mounted) {
          _saveSettings();
        }
      });
    } catch (e) {}
  }

  void _centerToUserLocation() async {
    if (_currentPosition != null) {
      final userLocation =
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
      _centerMap(userLocation, zoom: 15.0);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('正在获取当前位置...')),
        );
      }

      try {
        await _forceUpdateLocation();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('获取位置失败: $e')),
          );
        }
      }
    }
  }

  void _centerToLastTrain() {
    if (_trainRecords.isNotEmpty && _lastTrainLocation != null) {
      _centerMap(_lastTrainLocation!, zoom: 15.0);
    }
  }

  Future<void> _forceUpdateLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('请开启定位服务')),
          );
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('定位权限被永久拒绝，请在设置中开启')),
          );
        }
        return;
      }

      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('定位权限不足')),
          );
        }
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        forceAndroidLocationManager: true,
        timeLimit: const Duration(seconds: 20),
      );

      final newLocation = LatLng(position.latitude, position.longitude);
      setState(() {
        _currentPosition = position;
        _isLocationPermissionGranted = true;
      });

      _centerMap(newLocation, zoom: 16.0);

      _updateUserLocation();
    } catch (e) {}
  }

  void _refreshMap() {
    _loadTrainRecordsFromDatabase();

    if (_isLocationPermissionGranted) {
      _forceUpdateLocation();
    } else {
      _updateUserLocation();
    }

    _controller.runJavaScript('''
      if (window.MapInterface) {
        window.MapInterface.getTrainMarkersCount();
      }
    ''');
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
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
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
                  heroTag: "time_filter",
                  mini: true,
                  backgroundColor: const Color(0xFF1E1E1E),
                  onPressed: () {
                    _reloadSettingsIfNeeded();
                    _showTimeFilterDialog();
                  },
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.filter_list,
                          color: Colors.white, size: 18),
                      Text(
                        _getTimeFilterLabel(),
                        style:
                            const TextStyle(color: Colors.white, fontSize: 8),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                FloatingActionButton(
                  heroTag: "refresh",
                  mini: true,
                  backgroundColor: const Color(0xFF1E1E1E),
                  onPressed: _refreshMap,
                  child: const Icon(Icons.refresh, color: Colors.white),
                ),
                const SizedBox(height: 8),
                FloatingActionButton(
                  heroTag: "layers",
                  mini: true,
                  backgroundColor: const Color(0xFF1E1E1E),
                  onPressed: _toggleRailwayLayer,
                  child: Icon(
                    _isRailwayLayerVisible
                        ? Icons.layers
                        : Icons.layers_outlined,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                FloatingActionButton(
                  heroTag: "location",
                  mini: true,
                  backgroundColor: const Color(0xFF1E1E1E),
                  onPressed: _centerToUserLocation,
                  child: const Icon(Icons.my_location, color: Colors.white),
                ),
                const SizedBox(height: 8),
                FloatingActionButton(
                  heroTag: "last_train",
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
}
