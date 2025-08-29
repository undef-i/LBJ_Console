import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:lbjconsole/models/merged_record.dart';
import 'package:lbjconsole/models/train_record.dart';
import 'package:lbjconsole/screens/history_screen.dart';
import 'package:lbjconsole/screens/map_screen.dart';
import 'package:lbjconsole/screens/settings_screen.dart';
import 'package:lbjconsole/services/ble_service.dart';
import 'package:lbjconsole/services/database_service.dart';
import 'package:lbjconsole/services/notification_service.dart';
import 'package:lbjconsole/themes/app_theme.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;

  late final BLEService _bleService;
  final NotificationService _notificationService = NotificationService();

  StreamSubscription? _connectionSubscription;
  StreamSubscription? _dataSubscription;

  bool _isHistoryEditMode = false;
  final GlobalKey<HistoryScreenState> _historyScreenKey =
      GlobalKey<HistoryScreenState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bleService = BLEService();
    _bleService.initialize();
    _initializeServices();
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    _dataSubscription?.cancel();
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

    _connectionSubscription = _bleService.connectionStream.listen((_) {
      if (mounted) setState(() {});
    });

    _dataSubscription = _bleService.dataStream.listen((record) {
      _notificationService.showTrainNotification(record);
      if (_historyScreenKey.currentState != null) {
        _historyScreenKey.currentState!.loadRecords(scrollToTop: true);
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
        ['列车记录', '位置地图', '设置'][_currentIndex],
        style: const TextStyle(
            color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
      ),
      centerTitle: false,
      actions: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: _bleService.isConnected ? Colors.green : Colors.red,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(_bleService.deviceStatus,
                style: const TextStyle(color: Colors.white70)),
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
      const MapScreen(),
      const SettingsScreen(),
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
        indicatorColor: AppTheme.accentBlue.withOpacity(0.2),
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          if (_currentIndex == 2 && index == 0) {
            _historyScreenKey.currentState?.loadRecords();
          }
          setState(() {
            if (_isHistoryEditMode) _isHistoryEditMode = false;
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.directions_railway), label: '列车记录'),
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
