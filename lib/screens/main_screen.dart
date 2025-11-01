import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:lbjconsole/models/merged_record.dart';
import 'package:lbjconsole/models/train_record.dart';
import 'package:lbjconsole/screens/history_screen.dart';
import 'package:lbjconsole/screens/map_screen.dart';
import 'package:lbjconsole/screens/map_webview_screen.dart';
import 'package:lbjconsole/screens/realtime_screen.dart';
import 'package:lbjconsole/screens/settings_screen.dart';
import 'package:lbjconsole/services/ble_service.dart';
import 'package:lbjconsole/services/database_service.dart';
import 'package:lbjconsole/services/notification_service.dart';
import 'package:lbjconsole/services/background_service.dart';
import 'package:lbjconsole/services/rtl_tcp_service.dart';
import 'package:lbjconsole/themes/app_theme.dart';
import 'dart:convert';

class _ConnectionStatusWidget extends StatefulWidget {
  final BLEService bleService;
  final RtlTcpService rtlTcpService;
  final DateTime? lastReceivedTime;
  final DateTime? rtlTcpLastReceivedTime;
  final bool rtlTcpEnabled;
  final bool rtlTcpConnected;

  const _ConnectionStatusWidget({
    required this.bleService,
    required this.rtlTcpService,
    required this.lastReceivedTime,
    required this.rtlTcpLastReceivedTime,
    required this.rtlTcpEnabled,
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
  void dispose() {
    _connectionSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isRtlTcpMode = widget.rtlTcpEnabled;
    final rtlTcpConnected = widget.rtlTcpConnected;
    
    final isConnected = isRtlTcpMode ? rtlTcpConnected : _isConnected;
    final statusColor = isRtlTcpMode 
        ? (rtlTcpConnected ? Colors.green : Colors.red)
        : (_isConnected ? Colors.green : Colors.red);
    final statusText = isRtlTcpMode 
        ? (rtlTcpConnected ? '已连接' : '未连接')
        : _deviceStatus;
    
    final lastReceivedTime = isRtlTcpMode ? widget.rtlTcpLastReceivedTime : widget.lastReceivedTime;
    
    return Row(
      children: [
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (lastReceivedTime == null || !isConnected) ...[
              Text(statusText,
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
            _LastReceivedTimeWidget(
              lastReceivedTime: lastReceivedTime,
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
  int _currentIndex = 0;
  String _mapType = 'webview';

  late final BLEService _bleService;
  late final RtlTcpService _rtlTcpService;
  final NotificationService _notificationService = NotificationService();
  final DatabaseService _databaseService = DatabaseService.instance;

  StreamSubscription? _connectionSubscription;
  StreamSubscription? _rtlTcpConnectionSubscription;
  StreamSubscription? _dataSubscription;
  StreamSubscription? _rtlTcpDataSubscription;
  StreamSubscription? _lastReceivedTimeSubscription;
  StreamSubscription? _rtlTcpLastReceivedTimeSubscription;
  StreamSubscription? _settingsSubscription;
  DateTime? _lastReceivedTime;
  DateTime? _rtlTcpLastReceivedTime;
  bool _isHistoryEditMode = false;
  bool _rtlTcpEnabled = false;
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
    _loadRtlTcpSettings();
    _initializeServices();
    _checkAndStartBackgroundService();
    _setupConnectionListener();
    _setupLastReceivedTimeListener();
    _setupSettingsListener();
    _loadMapType();
  }

  Future<void> _loadMapType() async {
    final settings = await DatabaseService.instance.getAllSettings();
    if (mounted) {
      setState(() {
        _mapType = settings?['mapType']?.toString() ?? 'webview';
      });
    }
  }

  void _loadRtlTcpSettings() async {
    developer.log('rtl_tcp: load_settings');
    final settings = await _databaseService.getAllSettings();
    developer.log('rtl_tcp: settings_loaded: enabled=${(settings?['rtlTcpEnabled'] ?? 0) == 1}, host=${settings?['rtlTcpHost']?.toString() ?? '127.0.0.1'}, port=${settings?['rtlTcpPort']?.toString() ?? '14423'}');
    if (mounted) {
      setState(() {
        _rtlTcpEnabled = (settings?['rtlTcpEnabled'] ?? 0) == 1;
        _rtlTcpConnected = _rtlTcpService.isConnected;
      });
      
      if (_rtlTcpEnabled && !_rtlTcpConnected) {
        final host = settings?['rtlTcpHost']?.toString() ?? '127.0.0.1';
        final port = settings?['rtlTcpPort']?.toString() ?? '14423';
        developer.log('rtl_tcp: auto_connect');
        _connectToRtlTcp(host, port);
      } else {
        developer.log('rtl_tcp: skip_connect: enabled=$_rtlTcpEnabled, connected=$_rtlTcpConnected');
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
        if (_rtlTcpEnabled) {
          setState(() {
            _rtlTcpLastReceivedTime = time;
          });
        }
      }
    });
  }

  void _setupSettingsListener() {
    developer.log('rtl_tcp: setup_listener');
    _settingsSubscription =
        DatabaseService.instance.onSettingsChanged((settings) {
      developer.log('rtl_tcp: settings_changed: enabled=${(settings?['rtlTcpEnabled'] ?? 0) == 1}, host=${settings?['rtlTcpHost']?.toString() ?? '127.0.0.1'}, port=${settings?['rtlTcpPort']?.toString() ?? '14423'}');
      if (mounted) {
        final rtlTcpEnabled = (settings?['rtlTcpEnabled'] ?? 0) == 1;
        if (rtlTcpEnabled != _rtlTcpEnabled) {
          setState(() {
            _rtlTcpEnabled = rtlTcpEnabled;
          });
          
          if (rtlTcpEnabled) {
            final host = settings?['rtlTcpHost']?.toString() ?? '127.0.0.1';
            final port = settings?['rtlTcpPort']?.toString() ?? '14423';
            _connectToRtlTcp(host, port);
          } else {
          _rtlTcpConnectionSubscription?.cancel();
          _rtlTcpDataSubscription?.cancel();
          _rtlTcpLastReceivedTimeSubscription?.cancel();
          _rtlTcpService.disconnect();
          setState(() {
            _rtlTcpConnected = false;
            _rtlTcpLastReceivedTime = null;
          });
          }
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
        if (_rtlTcpEnabled) {
          setState(() {
            _rtlTcpConnected = connected;
          });
        }
      }
    });
  }

  Future<void> _connectToRtlTcp(String host, String port) async {
    developer.log('rtl_tcp: connect: $host:$port');
    try {
      await _rtlTcpService.connect(host: host, port: port);
      developer.log('rtl_tcp: connect_req_sent');
    } catch (e) {
      developer.log('rtl_tcp: connect_fail: $e');
    }
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    _rtlTcpConnectionSubscription?.cancel();
    _dataSubscription?.cancel();
    _rtlTcpDataSubscription?.cancel();
    _lastReceivedTimeSubscription?.cancel();
    _rtlTcpLastReceivedTimeSubscription?.cancel();
    _settingsSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _bleService.onAppResume();
      _loadMapType();
    }
  }

  Future<void> _initializeServices() async {
    await _notificationService.initialize();

    _dataSubscription = _bleService.dataStream.listen((record) {
      _notificationService.showTrainNotification(record);
      if (_historyScreenKey.currentState != null) {
        _historyScreenKey.currentState!.addNewRecord(record);
      }
      if (_realtimeScreenKey.currentState != null) {
        _realtimeScreenKey.currentState!.addNewRecord(record);
      }
    });

    _rtlTcpDataSubscription = _rtlTcpService.dataStream.listen((record) {
      developer.log('rtl_tcp: recv_data: train=${record.train}');
      developer.log('rtl_tcp: recv_json: ${jsonEncode(record.toJson())}');
      _notificationService.showTrainNotification(record);
      if (_historyScreenKey.currentState != null) {
        _historyScreenKey.currentState!.addNewRecord(record);
      }
      if (_realtimeScreenKey.currentState != null) {
        _realtimeScreenKey.currentState!.addNewRecord(record);
      }
    });
  }

  void _showConnectionDialog() {
    _bleService.setAutoConnectBlocked(true);
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) =>
          _PixelPerfectBluetoothDialog(bleService: _bleService, rtlTcpEnabled: _rtlTcpEnabled),
    ).then((_) {
      _bleService.setAutoConnectBlocked(false);
      if (!_bleService.isManualDisconnect) {
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
                rtlTcpEnabled: _rtlTcpEnabled,
                rtlTcpConnected: _rtlTcpConnected,
              ),
              IconButton(
                icon: Icon(
                  _rtlTcpEnabled ? Icons.wifi : Icons.bluetooth,
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
      _mapType == 'map' ? const MapScreen() : const MapWebViewScreen(),
      SettingsScreen(
        onSettingsChanged: () {
          _loadMapType();
          _loadRtlTcpSettings();
        },
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
          if (index == 1) {
            _realtimeScreenKey.currentState?.loadRecords(scrollToTop: false);
          }
          if (_currentIndex == 3 && index == 2) {
            _loadMapType();
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
  final bool rtlTcpEnabled;
  const _PixelPerfectBluetoothDialog({required this.bleService, required this.rtlTcpEnabled});
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
    
    if (widget.rtlTcpEnabled && widget.bleService.rtlTcpService != null) {
      _rtlTcpConnected = widget.bleService.rtlTcpService!.isConnected;
    }
    
    if (!widget.bleService.isConnected && !widget.rtlTcpEnabled) {
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
    if (mounted)
      setState(() {
        _devices.clear();
        _scanState = _ScanState.scanning;
      });
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

  void _setupLastReceivedTimeListener() {
    _lastReceivedTimeSubscription =
        widget.bleService.lastReceivedTimeStream.listen((timestamp) {
      if (mounted) {
        setState(() {
          _lastReceivedTime = timestamp;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = widget.bleService.isConnected;
    return AlertDialog(
      title: Text(widget.rtlTcpEnabled ? 'RTL-TCP 模式' : '蓝牙设备'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: widget.rtlTcpEnabled
              ? _buildRtlTcpView(context)
              : (isConnected
                  ? _buildConnectedView(context, widget.bleService.connectedDevice)
                  : _buildDisconnectedView(context)),
        ),
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
      if (_lastReceivedTime != null) ...[
        const SizedBox(height: 8),
        _LastReceivedTimeWidget(
          lastReceivedTime: _lastReceivedTime,
          isConnected: widget.bleService.isConnected,
        ),
      ],
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
      Text('$currentAddress',
          style: TextStyle(color: isConnected ? Colors.green : Colors.grey)),
      const SizedBox(height: 16),
      if (_lastReceivedTime != null && isConnected) ...[
        _LastReceivedTimeWidget(
          lastReceivedTime: _lastReceivedTime,
          isConnected: isConnected,
        ),
      ],
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
