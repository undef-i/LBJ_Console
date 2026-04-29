import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:lbjconsole/models/train_record.dart';
import 'package:lbjconsole/screens/history_screen.dart';
import 'package:lbjconsole/screens/map_screen.dart';
import 'package:lbjconsole/screens/realtime_screen.dart';
import 'package:lbjconsole/screens/settings_screen.dart';
import 'package:lbjconsole/services/ble_service.dart';
import 'package:lbjconsole/services/database_service.dart';
import 'package:lbjconsole/services/notification_service.dart';
import 'package:lbjconsole/services/background_service.dart';
import 'package:lbjconsole/services/rtl_tcp_service.dart';
import 'package:lbjconsole/services/audio_input_service.dart';
import 'package:lbjconsole/themes/app_theme.dart';
import 'package:lbjconsole/widgets/audio_waterfall_widget.dart';

class _ConnectionStatusWidget extends StatefulWidget {
  final BLEService bleService;
  final RtlTcpService rtlTcpService;
  final DateTime? lastReceivedTime;
  final DateTime? rtlTcpLastReceivedTime;
  final DateTime? audioLastReceivedTime;
  final InputSource inputSource;
  final bool rtlTcpConnected;

  const _ConnectionStatusWidget({
    required this.bleService,
    required this.rtlTcpService,
    required this.lastReceivedTime,
    required this.rtlTcpLastReceivedTime,
    required this.audioLastReceivedTime,
    required this.inputSource,
    required this.rtlTcpConnected,
  });

  @override
  State<_ConnectionStatusWidget> createState() =>
      _ConnectionStatusWidgetState();
}

class _ConnectionStatusWidgetState extends State<_ConnectionStatusWidget> {
  StreamSubscription? _connectionSubscription;
  String _deviceStatus = "未连接";
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _connectionSubscription =
        widget.bleService.connectionStream.listen((connected) {
      if (mounted) {
        setState(() {
          _isConnected = connected;
          _deviceStatus = connected ? "已连接" : "未连接";
        });
      }
    });
    _isConnected = widget.bleService.isConnected;
    _deviceStatus = widget.bleService.deviceStatus;
  }

  @override
  void didUpdateWidget(covariant _ConnectionStatusWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.inputSource != widget.inputSource ||
        oldWidget.rtlTcpConnected != widget.rtlTcpConnected) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isConnected;
    Color statusColor;
    String statusText;
    DateTime? displayTime;

    switch (widget.inputSource) {
      case InputSource.rtlTcp:
        isConnected = widget.rtlTcpConnected;
        statusColor = isConnected ? Colors.green : Colors.red;
        statusText = isConnected ? '已连接' : '未连接';
        displayTime = widget.rtlTcpLastReceivedTime;
        break;
      case InputSource.audioInput:
        isConnected = AudioInputService().isListening;
        statusColor = isConnected ? Colors.green : Colors.red;
        statusText = isConnected ? '监听中' : '已停止';
        displayTime = widget.audioLastReceivedTime;
        break;
      case InputSource.bluetooth:
        isConnected = _isConnected;
        statusColor = isConnected ? Colors.green : Colors.red;
        statusText = _deviceStatus;
        displayTime = widget.lastReceivedTime;
        break;
    }
    
    return Row(
      children: [
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (displayTime == null || !isConnected) ...[
              Text(statusText,
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
            _LastReceivedTimeWidget(
              lastReceivedTime: displayTime,
              isConnected: isConnected,
            ),
          ],
        ),
        const SizedBox(width: 8),
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: statusColor,
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }
}

class _LastReceivedTimeWidget extends StatefulWidget {
  final DateTime? lastReceivedTime;
  final bool isConnected;

  const _LastReceivedTimeWidget({
    required this.lastReceivedTime,
    required this.isConnected,
  });

  @override
  State<_LastReceivedTimeWidget> createState() =>
      _LastReceivedTimeWidgetState();
}

class _LastReceivedTimeWidgetState extends State<_LastReceivedTimeWidget> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void didUpdateWidget(_LastReceivedTimeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lastReceivedTime != widget.lastReceivedTime ||
        oldWidget.isConnected != widget.isConnected) {
      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    if (widget.lastReceivedTime != null && widget.isConnected) {
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() {});
        }
      });
    }
  }

  String _formatTime() {
    if (widget.lastReceivedTime == null) return '';

    final now = DateTime.now();
    final difference = now.difference(widget.lastReceivedTime!);

    if (difference.inDays > 0) {
      return '${difference.inDays}天前';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}小时前';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}分钟前';
    } else {
      return '${difference.inSeconds}秒前';
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lastReceivedTime == null || !widget.isConnected) {
      return const SizedBox.shrink();
    }

    return Text(
      _formatTime(),
      style: const TextStyle(color: Colors.white70, fontSize: 12),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  // TEMP: 临时测试数据。发布前把开关改成 false 或删除本段相关代码。
  static const double _temporaryMinLat = 18.0;
  static const double _temporaryMaxLat = 53.0;
  static const double _temporaryMinLng = 73.0;
  static const double _temporaryMaxLng = 135.0;
  static const double _temporaryStartRadiusDegrees = 0.1;
  static const double _temporaryMaxStepDegrees = 0.02;
  static const String _temporaryTrainNumber = '7001';
  static const List<List<double>> _temporaryChinaAnchors = [
    [39.9042, 116.4074],
    [31.2304, 121.4737],
    [23.1291, 113.2644],
    [30.5728, 104.0668],
    [34.3416, 108.9398],
    [45.8038, 126.5349],
    [43.8256, 87.6168],
    [25.0389, 102.7183],
    [36.0611, 103.8343],
    [28.2282, 112.9388],
  ];

  int _currentIndex = 0;

  late final BLEService _bleService;
  late final RtlTcpService _rtlTcpService;
  final NotificationService _notificationService = NotificationService();
  final DatabaseService _databaseService = DatabaseService.instance;
  final math.Random _temporaryRandom = math.Random();

  StreamSubscription? _connectionSubscription;
  StreamSubscription? _rtlTcpConnectionSubscription;
  StreamSubscription? _audioConnectionSubscription;
  StreamSubscription? _dataSubscription;
  StreamSubscription? _rtlTcpDataSubscription;
  StreamSubscription? _audioDataSubscription;
  StreamSubscription? _lastReceivedTimeSubscription;
  StreamSubscription? _rtlTcpLastReceivedTimeSubscription;
  StreamSubscription? _audioLastReceivedTimeSubscription;
  StreamSubscription? _settingsSubscription;
  Timer? _temporaryRecordTimer;
  DateTime? _lastReceivedTime;
  DateTime? _rtlTcpLastReceivedTime;
  DateTime? _audioLastReceivedTime;
  double? _temporaryLat;
  double? _temporaryLng;
  int _temporaryRecordSerial = 0;
  bool _temporaryRecordsEnabled = false;
  bool _isHistoryEditMode = false;
  
  InputSource _inputSource = InputSource.bluetooth;
  
  bool _rtlTcpConnected = false;
  bool _isConnected = false;
  final GlobalKey<HistoryScreenState> _historyScreenKey =
      GlobalKey<HistoryScreenState>();
  final GlobalKey<RealtimeScreenState> _realtimeScreenKey =
      GlobalKey<RealtimeScreenState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bleService = BLEService();
    _rtlTcpService = RtlTcpService();
    _bleService.initialize();
    _loadInputSettings();
    _initializeServices();
    _checkAndStartBackgroundService();
    _setupConnectionListener();
    _setupLastReceivedTimeListener();
    _setupSettingsListener();
  }

  void _loadInputSettings() async {
    final settings = await _databaseService.getAllSettings();
    final sourceStr = settings?['inputSource'] as String? ?? 'bluetooth';
    
    if (mounted) {
      final newSource = InputSource.values.firstWhere(
        (e) => e.name == sourceStr,
        orElse: () => InputSource.bluetooth,
      );
      
      setState(() {
        _inputSource = newSource;
        _rtlTcpConnected = _rtlTcpService.isConnected;
      });
      
      if (_inputSource == InputSource.rtlTcp && !_rtlTcpConnected) {
        final host = settings?['rtlTcpHost']?.toString() ?? '127.0.0.1';
        final port = settings?['rtlTcpPort']?.toString() ?? '14423';
        _connectToRtlTcp(host, port);
      } else if (_inputSource == InputSource.audioInput) {
        await AudioInputService().startListening();
        setState(() {}); 
      }
    }
  }

  Future<void> _checkAndStartBackgroundService() async {
    final settings = await DatabaseService.instance.getAllSettings() ?? {};
    final backgroundServiceEnabled =
        (settings['backgroundServiceEnabled'] ?? 0) == 1;

    if (backgroundServiceEnabled) {
      await BackgroundService.startService();
    }
  }

  void _setupLastReceivedTimeListener() {
    _lastReceivedTimeSubscription =
        _bleService.lastReceivedTimeStream.listen((time) {
      if (mounted) {
        setState(() {
          _lastReceivedTime = time;
        });
      }
    });
    
    _rtlTcpLastReceivedTimeSubscription =
        _rtlTcpService.lastReceivedTimeStream.listen((time) {
      if (mounted) {
        setState(() {
          _rtlTcpLastReceivedTime = time;
        });
      }
    });
    
    _audioLastReceivedTimeSubscription =
        AudioInputService().lastReceivedTimeStream.listen((time) {
      if (mounted) {
        setState(() {
          _audioLastReceivedTime = time;
        });
      }
    });
  }

  void _setupSettingsListener() {
    _settingsSubscription =
        DatabaseService.instance.onSettingsChanged((settings) {
      if (mounted) {
        final sourceStr = settings['inputSource'] as String? ?? 'bluetooth';
        final newInputSource = InputSource.values.firstWhere(
          (e) => e.name == sourceStr,
          orElse: () => InputSource.bluetooth,
        );
        
        setState(() {
          _inputSource = newInputSource;
        });
        
        switch (newInputSource) {
          case InputSource.rtlTcp:
            setState(() {
              _rtlTcpConnected = _rtlTcpService.isConnected;
            });
            break;
          case InputSource.audioInput:
            setState(() {});
            break;
          case InputSource.bluetooth:
            _rtlTcpService.disconnect();
            setState(() {
              _rtlTcpConnected = false;
              _rtlTcpLastReceivedTime = null;
            });
            break;
        }
        
        if (_currentIndex == 1) {
          _realtimeScreenKey.currentState?.loadRecords(scrollToTop: false);
        }
      }
    });
  }

  void _setupConnectionListener() {
    _connectionSubscription = _bleService.connectionStream.listen((connected) {
      if (mounted) {
        setState(() {
          _isConnected = connected;
        });
      }
    });
    
    _rtlTcpConnectionSubscription = _rtlTcpService.connectionStream.listen((connected) {
      if (mounted) {
        setState(() {
          _rtlTcpConnected = connected;
        });
      }
    });
    
    _audioConnectionSubscription = AudioInputService().connectionStream.listen((listening) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  Future<void> _connectToRtlTcp(String host, String port) async {
    try {
      await _rtlTcpService.connect(host: host, port: port);
    } catch (e) {
      developer.log('rtl_tcp: connect_fail: $e');
    }
  }

  void _startTemporaryRecords() {
    if (!_temporaryRecordsEnabled) return;

    final startIndex = _temporaryRandom.nextInt(_temporaryChinaAnchors.length);
    final start = _temporaryChinaAnchors[startIndex];
    _temporaryLat ??= (start[0] + _temporaryStartOffset())
        .clamp(_temporaryMinLat, _temporaryMaxLat)
        .toDouble();
    _temporaryLng ??= (start[1] + _temporaryStartOffset())
        .clamp(_temporaryMinLng, _temporaryMaxLng)
        .toDouble();

    _temporaryRecordTimer?.cancel();
    _temporaryRecordTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _insertTemporaryRecord(),
    );
  }

  void _setTemporaryRecordsEnabled(bool enabled) {
    if (_temporaryRecordsEnabled == enabled) return;

    setState(() {
      _temporaryRecordsEnabled = enabled;
    });

    if (enabled) {
      _startTemporaryRecords();
    } else {
      _temporaryRecordTimer?.cancel();
      _temporaryRecordTimer = null;
    }
  }

  Future<void> _insertTemporaryRecord() async {
    final now = DateTime.now();
    final latStep = (_temporaryRandom.nextDouble() - 0.5) *
        _temporaryMaxStepDegrees;
    final lngStep = (_temporaryRandom.nextDouble() - 0.5) *
        _temporaryMaxStepDegrees;

    _temporaryLat = ((_temporaryLat ?? 35.0) + latStep)
        .clamp(_temporaryMinLat, _temporaryMaxLat)
        .toDouble();
    _temporaryLng = ((_temporaryLng ?? 105.0) + lngStep)
        .clamp(_temporaryMinLng, _temporaryMaxLng)
        .toDouble();
    _temporaryRecordSerial += 1;

    final serialText = _temporaryRecordSerial.toString().padLeft(4, '0');
    final record = TrainRecord(
      uniqueId: 'temporary_${now.millisecondsSinceEpoch}_$serialText',
      timestamp: now,
      receivedTimestamp: now,
      train: _temporaryTrainNumber,
      direction: _temporaryRecordSerial.isEven ? 0 : 1,
      speed: '${60 + _temporaryRandom.nextInt(80)}',
      position: '${(_temporaryRecordSerial % 300) + 1}.0',
      time: _temporaryClockText(now),
      loco: 'TEMP$serialText',
      locoType: 'HXD',
      lbjClass: 'G',
      route: '临时测试',
      positionInfo: _temporaryDmsPosition(_temporaryLat!, _temporaryLng!),
      rssi: -65 + _temporaryRandom.nextDouble() * 12,
    );

    await _databaseService.insertRecord(record);
    if (!mounted) return;
    _processRecord(record);
  }

  String _temporaryDmsPosition(double lat, double lng) {
    return '${_temporaryDmsCoordinate(lat)} ${_temporaryDmsCoordinate(lng)}';
  }

  double _temporaryStartOffset() {
    return (_temporaryRandom.nextDouble() - 0.5) *
        _temporaryStartRadiusDegrees;
  }

  String _temporaryClockText(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _temporaryDmsCoordinate(double value) {
    final degrees = value.truncate();
    final minutes = (value - degrees) * 60.0;
    return '$degrees°${minutes.toStringAsFixed(4)}′';
  }

  @override
  void dispose() {
    _temporaryRecordTimer?.cancel();
    _connectionSubscription?.cancel();
    _rtlTcpConnectionSubscription?.cancel();
    _audioConnectionSubscription?.cancel();
    _dataSubscription?.cancel();
    _rtlTcpDataSubscription?.cancel();
    _audioDataSubscription?.cancel();
    _lastReceivedTimeSubscription?.cancel();
    _rtlTcpLastReceivedTimeSubscription?.cancel();
    _audioLastReceivedTimeSubscription?.cancel();
    _settingsSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _bleService.onAppResume();
    }
  }

  Future<void> _initializeServices() async {
    await _notificationService.initialize();

    _dataSubscription = _bleService.dataStream.listen((record) {
      if (_inputSource == InputSource.bluetooth) {
        _processRecord(record);
      }
    });

    _rtlTcpDataSubscription = _rtlTcpService.dataStream.listen((record) {
      if (_inputSource == InputSource.rtlTcp) {
        _processRecord(record);
      }
    });
    
    _audioDataSubscription = AudioInputService().dataStream.listen((record) {
      if (_inputSource == InputSource.audioInput) {
        _processRecord(record);
      }
    });
  }

  void _processRecord(TrainRecord record) {
    _notificationService.showTrainNotification(record);
    _historyScreenKey.currentState?.addNewRecord(record);
    _realtimeScreenKey.currentState?.addNewRecord(record);
  }

  void _showConnectionDialog() {
    _bleService.setAutoConnectBlocked(true);
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) =>
          _PixelPerfectBluetoothDialog(
              bleService: _bleService, 
              inputSource: _inputSource
          ),
    ).then((_) {
      _bleService.setAutoConnectBlocked(false);
      if (_inputSource == InputSource.bluetooth && !_bleService.isManualDisconnect) {
        _bleService.ensureConnection();
      }
    });
  }

  AppBar _buildAppBar(BuildContext context) {
    final historyState = _historyScreenKey.currentState;
    final selectedCount = historyState?.getSelectedCount() ?? 0;

    if (_currentIndex == 0 && _isHistoryEditMode) {
      return AppBar(
        backgroundColor: Theme.of(context).primaryColor,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: _handleHistoryCancelSelection,
        ),
        title: Text(
          '已选择 $selectedCount 项',
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.white),
            onPressed: selectedCount > 0 ? _handleHistoryDeleteSelected : null,
          ),
        ],
      );
    }

    final IconData statusIcon = switch (_inputSource) {
      InputSource.rtlTcp => Icons.wifi,
      InputSource.audioInput => Icons.mic,
      InputSource.bluetooth => Icons.bluetooth,
    };

    return AppBar(
      backgroundColor: AppTheme.primaryBlack,
      elevation: 0,
      title: Text(
        ['列车记录', '数据监控', '位置地图', '设置'][_currentIndex],
        style: const TextStyle(
            color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
      ),
      centerTitle: false,
      actions: [
          Row(
            children: [
              _ConnectionStatusWidget(
                bleService: _bleService,
                rtlTcpService: _rtlTcpService,
                lastReceivedTime: _lastReceivedTime,
                rtlTcpLastReceivedTime: _rtlTcpLastReceivedTime,
                audioLastReceivedTime: _audioLastReceivedTime,
                inputSource: _inputSource,
                rtlTcpConnected: _rtlTcpConnected,
              ),
              IconButton(
                icon: Icon(
                  statusIcon,
                  color: Colors.white,
                ),
                onPressed: _showConnectionDialog,
              ),
            ],
          ),
        ],
    );
  }

  void _handleHistoryEditModeChanged(bool isEditing) {
    setState(() {
      _isHistoryEditMode = isEditing;
      if (!isEditing) {
        _historyScreenKey.currentState?.clearSelection();
      }
    });
  }

  void _handleSelectionChanged() {
    if (_isHistoryEditMode &&
        (_historyScreenKey.currentState?.getSelectedCount() ?? 0) == 0) {
      _handleHistoryCancelSelection();
    } else {
      setState(() {});
    }
  }

  void _handleHistoryCancelSelection() {
    _historyScreenKey.currentState?.setEditMode(false);
  }

  Future<void> _handleHistoryDeleteSelected() async {
    final historyState = _historyScreenKey.currentState;
    if (historyState == null || historyState.getSelectedCount() == 0) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除选中的 ${historyState.getSelectedCount()} 条记录吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final idsToDelete = historyState.getSelectedRecordIds().toList();
      await DatabaseService.instance.deleteRecords(idsToDelete);

      historyState.setEditMode(false);

      historyState.loadRecords(scrollToTop: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: AppTheme.primaryBlack,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ));

    final pages = [
      HistoryScreen(
        key: _historyScreenKey,
        onEditModeChanged: _handleHistoryEditModeChanged,
        onSelectionChanged: _handleSelectionChanged,
      ),
      RealtimeScreen(
        key: _realtimeScreenKey,
      ),
      const MapScreen(),
      SettingsScreen(
        temporaryRecordsEnabled: _temporaryRecordsEnabled,
        onTemporaryRecordsChanged: _setTemporaryRecordsEnabled,
      ),
    ];

    return Scaffold(
      backgroundColor: AppTheme.primaryBlack,
      appBar: _buildAppBar(context),
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: AppTheme.secondaryBlack,
        indicatorColor: AppTheme.accentBlue.withValues(alpha: 0.2),
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          if (index == 0) {
            _historyScreenKey.currentState?.reloadRecords();
          }
          setState(() {
            if (_isHistoryEditMode) _isHistoryEditMode = false;
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.directions_railway), label: '列车记录'),
          NavigationDestination(icon: Icon(Icons.speed), label: '数据监控'),
          NavigationDestination(icon: Icon(Icons.location_on), label: '位置地图'),
          NavigationDestination(icon: Icon(Icons.settings), label: '设置'),
        ],
      ),
    );
  }
}

enum _ScanState { initial, scanning, finished }

class _PixelPerfectBluetoothDialog extends StatefulWidget {
  final BLEService bleService;
  final InputSource inputSource;
  const _PixelPerfectBluetoothDialog({required this.bleService, required this.inputSource});
  @override
  State<_PixelPerfectBluetoothDialog> createState() =>
      _PixelPerfectBluetoothDialogState();
}

class _PixelPerfectBluetoothDialogState
    extends State<_PixelPerfectBluetoothDialog> {
  List<BluetoothDevice> _devices = [];
  _ScanState _scanState = _ScanState.initial;
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _lastReceivedTimeSubscription;
  DateTime? _lastReceivedTime;
  StreamSubscription? _rtlTcpConnectionSubscription;
  bool _rtlTcpConnected = false;
  
  @override
  void initState() {
    super.initState();
    _connectionSubscription = widget.bleService.connectionStream.listen((_) {
      if (mounted) setState(() {});
    });
    
    _rtlTcpConnectionSubscription = widget.bleService.rtlTcpService?.connectionStream.listen((connected) {
      if (mounted) {
        setState(() {
          _rtlTcpConnected = connected;
        });
      }
    });
    
    if (widget.inputSource == InputSource.rtlTcp && widget.bleService.rtlTcpService != null) {
      _rtlTcpConnected = widget.bleService.rtlTcpService!.isConnected;
    }
    
    if (!widget.bleService.isConnected && widget.inputSource == InputSource.bluetooth) {
      _startScan();
    }
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    _rtlTcpConnectionSubscription?.cancel();
    _lastReceivedTimeSubscription?.cancel();
    super.dispose();
  }

  Future<void> _startScan() async {
    if (_scanState == _ScanState.scanning) return;
    if (mounted) {
      setState(() {
        _devices.clear();
        _scanState = _ScanState.scanning;
      });
    }
    await widget.bleService.startScan(
      timeout: const Duration(seconds: 8),
      onScanResults: (devices) {
        if (mounted) setState(() => _devices = devices);
      },
    );
    if (mounted) setState(() => _scanState = _ScanState.finished);
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    Navigator.pop(context);
    await widget.bleService.connectManually(device);
  }

  Future<void> _disconnect() async {
    Navigator.pop(context);
    await widget.bleService.disconnect();
  }

  @override
  Widget build(BuildContext context) {
    final (String title, Widget content) = switch (widget.inputSource) {
      InputSource.rtlTcp => ('RTL-TCP 服务器', _buildRtlTcpView(context)),
      InputSource.audioInput => ('音频输入', _buildAudioInputView(context)),
      InputSource.bluetooth => (
        '蓝牙设备',
        widget.bleService.isConnected
            ? _buildConnectedView(context, widget.bleService.connectedDevice)
            : _buildDisconnectedView(context)
      ),
    };

    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(child: content),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _buildConnectedView(BuildContext context, BluetoothDevice? device) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.bluetooth_connected, size: 48, color: Colors.green),
      const SizedBox(height: 16),
      Text('设备已连接',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      Text(device?.platformName ?? '未知设备', textAlign: TextAlign.center),
      Text(device?.remoteId.str ?? '',
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center),
      const SizedBox(height: 16),
      ElevatedButton.icon(
          onPressed: _disconnect,
          icon: const Icon(Icons.bluetooth_disabled),
          label: const Text('断开连接'),
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red, foregroundColor: Colors.white))
    ]);
  }

  Widget _buildDisconnectedView(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      ElevatedButton.icon(
          onPressed: _scanState == _ScanState.scanning ? null : _startScan,
          icon: _scanState == _ScanState.scanning
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.search),
          label: Text(_scanState == _ScanState.scanning ? '扫描中...' : '扫描设备'),
          style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 40))),
      const SizedBox(height: 16),
      if (_scanState == _ScanState.finished && _devices.isNotEmpty)
        _buildDeviceListView()
    ]);
  }

  Widget _buildRtlTcpView(BuildContext context) {
    final isConnected = _rtlTcpConnected;
    final currentAddress = widget.bleService.rtlTcpService?.currentAddress ?? '未配置';
    
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.wifi, size: 48, color: isConnected ? Colors.green : Colors.red),
      const SizedBox(height: 16),
      Text(isConnected ? '已连接' : '未连接',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Text(currentAddress,
          style: TextStyle(color: isConnected ? Colors.green : Colors.grey)),
    ]);
  }

  Widget _buildAudioInputView(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const SizedBox(height: 8),
      const AudioWaterfallWidget(),
    ]);
  }

  Widget _buildDeviceListView() {
    return SizedBox(
      height: 200,
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _devices.length,
        itemBuilder: (context, index) {
          final device = _devices[index];
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              leading: const Icon(Icons.bluetooth),
              title: Text(device.platformName.isNotEmpty
                  ? device.platformName
                  : '未知设备'),
              subtitle: Text(device.remoteId.str),
              onTap: () => _connectToDevice(device),
            ),
          );
        },
      ),
    );
  }
}
