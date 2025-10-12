import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
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
import 'package:lbjconsole/themes/app_theme.dart';

class _ConnectionStatusWidget extends StatefulWidget {
  final BLEService bleService;
  final DateTime? lastReceivedTime;

  const _ConnectionStatusWidget({
    required this.bleService,
    required this.lastReceivedTime,
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
    return Row(
      children: [
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.lastReceivedTime == null || !_isConnected) ...[
              Text(_deviceStatus,
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
            _LastReceivedTimeWidget(
              lastReceivedTime: widget.lastReceivedTime,
              isConnected: _isConnected,
            ),
          ],
        ),
        const SizedBox(width: 8),
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: _isConnected ? Colors.green : Colors.red,
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
  final NotificationService _notificationService = NotificationService();

  StreamSubscription? _connectionSubscription;
  StreamSubscription? _dataSubscription;
  StreamSubscription? _lastReceivedTimeSubscription;
  StreamSubscription? _settingsSubscription;
  DateTime? _lastReceivedTime;
  bool _isHistoryEditMode = false;
  final GlobalKey<HistoryScreenState> _historyScreenKey =
      GlobalKey<HistoryScreenState>();
  final GlobalKey<RealtimeScreenState> _realtimeScreenKey =
      GlobalKey<RealtimeScreenState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bleService = BLEService();
    _bleService.initialize();
    _initializeServices();
    _checkAndStartBackgroundService();
    _setupLastReceivedTimeListener();
    _setupSettingsListener();
    _loadMapType();
  }

  Future<void> _loadMapType() async {
    final settings = await DatabaseService.instance.getAllSettings() ?? {};
    if (mounted) {
      setState(() {
        _mapType = settings['mapType']?.toString() ?? 'webview';
      });
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
  }

  void _setupSettingsListener() {
    _settingsSubscription =
        DatabaseService.instance.onSettingsChanged((settings) {
      if (mounted && _currentIndex == 1) {
        _realtimeScreenKey.currentState?.loadRecords(scrollToTop: false);
      }
    });
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    _dataSubscription?.cancel();
    _lastReceivedTimeSubscription?.cancel();
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
  }

  void _showConnectionDialog() {
    _bleService.setAutoConnectBlocked(true);
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) =>
          _PixelPerfectBluetoothDialog(bleService: _bleService),
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
              lastReceivedTime: _lastReceivedTime,
            ),
            IconButton(
              icon: const Icon(Icons.bluetooth, color: Colors.white),
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
  const _PixelPerfectBluetoothDialog({required this.bleService});
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
  @override
  void initState() {
    super.initState();
    _connectionSubscription = widget.bleService.connectionStream.listen((_) {
      if (mounted) setState(() {});
    });
    if (!widget.bleService.isConnected) {
      _startScan();
    }
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
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
      title: const Text('蓝牙设备'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: isConnected
              ? _buildConnectedView(context, widget.bleService.connectedDevice)
              : _buildDisconnectedView(context),
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
