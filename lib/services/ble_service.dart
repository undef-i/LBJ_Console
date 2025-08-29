import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:lbjconsole/models/train_record.dart';
import 'package:lbjconsole/services/database_service.dart';

class BLEService {
  static final BLEService _instance = BLEService._internal();
  factory BLEService() => _instance;
  BLEService._internal();

  static const String TAG = "LBJ_BT_FLUTTER";
  static final Guid serviceUuid = Guid("0000ffe0-0000-1000-8000-00805f9b34fb");
  static final Guid charUuid = Guid("0000ffe1-0000-1000-8000-00805f9b34fb");

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _characteristic;
  StreamSubscription<List<int>>? _valueSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  StreamSubscription<List<ScanResult>>? _scanResultsSubscription;

  final StreamController<String> _statusController =
      StreamController<String>.broadcast();
  final StreamController<TrainRecord> _dataController =
      StreamController<TrainRecord>.broadcast();
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();

  Stream<String> get statusStream => _statusController.stream;
  Stream<TrainRecord> get dataStream => _dataController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;

  String _deviceStatus = "未连接";
  String? _lastKnownDeviceAddress;
  String _targetDeviceName = "LBJReceiver";

  bool _isConnecting = false;
  bool _isManualDisconnect = false;
  bool _isAutoConnectBlocked = false;

  Timer? _heartbeatTimer;
  final StringBuffer _dataBuffer = StringBuffer();

  void initialize() {
    _loadSettings();
    FlutterBluePlus.adapterState.listen((state) {
      if (state == BluetoothAdapterState.on) {
        ensureConnection();
      } else {
        _updateConnectionState(false, "蓝牙已关闭");
        stopScan();
      }
    });
    _startHeartbeat();
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 7), (timer) {
      ensureConnection();
    });
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await DatabaseService.instance.getAllSettings();
      if (settings != null) {
        _targetDeviceName = settings['deviceName'] ?? 'LBJReceiver';
      }
    } catch (e) {
    }
  }

  void ensureConnection() {
    if (isConnected || _isConnecting) {
      return;
    }
    _tryReconnectDirectly();
  }

  Future<void> _tryReconnectDirectly() async {
    if (_lastKnownDeviceAddress == null) {
      startScan();
      return;
    }

    _isConnecting = true;
    _statusController.add("正在重连...");

    try {
      final connected = await FlutterBluePlus.connectedSystemDevices;
      final matchingDevices =
          connected.where((d) => d.remoteId.str == _lastKnownDeviceAddress);
      BluetoothDevice? target =
          matchingDevices.isNotEmpty ? matchingDevices.first : null;

      if (target != null) {
        await connect(target);
      } else {
        startScan();
        _isConnecting = false;
      }
    } catch (e) {
      startScan();
      _isConnecting = false;
    }
  }

  Future<void> startScan({
    String? targetName,
    Duration? timeout,
    Function(List<BluetoothDevice>)? onScanResults,
  }) async {
    if (FlutterBluePlus.isScanningNow) {
      return;
    }

    _targetDeviceName = targetName ?? _targetDeviceName;
    _statusController.add("正在扫描...");

    _scanResultsSubscription?.cancel();
    _scanResultsSubscription = FlutterBluePlus.scanResults.listen((results) {
      final allFoundDevices = results.map((r) => r.device).toList();

      final filteredDevices = allFoundDevices.where((device) {
        if (_targetDeviceName.isEmpty) return true;
        return device.platformName.toLowerCase() ==
            _targetDeviceName.toLowerCase();
      }).toList();

      onScanResults?.call(filteredDevices);

      if (isConnected ||
          _isConnecting ||
          _isManualDisconnect ||
          _isAutoConnectBlocked) return;

      for (var device in allFoundDevices) {
        if (_shouldAutoConnectTo(device)) {
          stopScan();
          connect(device);
          break;
        }
      }
    });

    try {
      await FlutterBluePlus.startScan(timeout: timeout);
    } catch (e) {
      _statusController.add("扫描失败");
    }
  }

  bool _shouldAutoConnectTo(BluetoothDevice device) {
    final deviceName = device.platformName;
    final deviceAddress = device.remoteId.str;

    if (_targetDeviceName.isNotEmpty &&
        deviceName.toLowerCase() == _targetDeviceName.toLowerCase())
      return true;
    if (_lastKnownDeviceAddress != null &&
        _lastKnownDeviceAddress == deviceAddress) return true;

    return false;
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    _scanResultsSubscription?.cancel();
  }

  Future<void> connect(BluetoothDevice device) async {
    if (isConnected) return;

    _isConnecting = true;
    _isManualDisconnect = false;
    _statusController.add("正在连接: ${device.platformName}");

    try {
      _connectionStateSubscription?.cancel();
      _connectionStateSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _onDisconnected();
        }
      });

      await device.connect(timeout: const Duration(seconds: 15));
      await _onConnected(device);
    } catch (e) {
      _onDisconnected();
    }
  }

  Future<void> _onConnected(BluetoothDevice device) async {
    _connectedDevice = device;
    _lastKnownDeviceAddress = device.remoteId.str;
    await _discoverServicesAndSetupNotifications(device);
  }

  void _onDisconnected() {
    final wasConnected = isConnected;
    _updateConnectionState(false, "连接已断开");
    _connectionStateSubscription?.cancel();

    if (wasConnected && !_isManualDisconnect) {
      ensureConnection();
    }
    _isConnecting = false;
  }

  Future<void> _discoverServicesAndSetupNotifications(
      BluetoothDevice device) async {
    try {
      final services = await device.discoverServices();
      for (var service in services) {
        if (service.uuid == serviceUuid) {
          for (var char in service.characteristics) {
            if (char.uuid == charUuid) {
              _characteristic = char;
              await device.requestMtu(512);
              await char.setNotifyValue(true);
              _valueSubscription = char.lastValueStream.listen(_onDataReceived);

              _updateConnectionState(true, "已连接");
              _isConnecting = false;
              return;
            }
          }
        }
      }
      await device.disconnect();
    } catch (e) {
      await device.disconnect();
    }
  }

  Future<void> connectManually(BluetoothDevice device) async {
    _isManualDisconnect = false;
    _isAutoConnectBlocked = false;
    stopScan();
    await connect(device);
  }

  Future<void> disconnect() async {
    _isManualDisconnect = true;
    stopScan();

    await _connectionStateSubscription?.cancel();
    await _valueSubscription?.cancel();

    if (_connectedDevice != null) {
      await _connectedDevice!.disconnect();
    }
    _onDisconnected();
  }

  void _onDataReceived(List<int> value) {
    if (value.isEmpty) return;
    try {
      final data = utf8.decode(value);
      _dataBuffer.write(data);
      _processDataBuffer();
    } catch (e) {}
  }

  void _processDataBuffer() {
    String bufferContent = _dataBuffer.toString();
    if (bufferContent.isEmpty) return;

    int firstBrace = bufferContent.indexOf('{');
    if (firstBrace == -1) {
      _dataBuffer.clear();
      return;
    }

    bufferContent = bufferContent.substring(firstBrace);
    int braceCount = 0;
    int lastValidJsonEnd = -1;

    for (int i = 0; i < bufferContent.length; i++) {
      if (bufferContent[i] == '{') {
        braceCount++;
      } else if (bufferContent[i] == '}') {
        braceCount--;
      }
      if (braceCount == 0 && i > 0) {
        lastValidJsonEnd = i;
        String jsonToParse = bufferContent.substring(0, lastValidJsonEnd + 1);
        _parseAndNotify(jsonToParse);
        bufferContent = bufferContent.substring(lastValidJsonEnd + 1);
        i = -1;
        firstBrace = bufferContent.indexOf('{');
        if (firstBrace != -1) {
          bufferContent = bufferContent.substring(firstBrace);
        } else {
          break;
        }
      }
    }
    _dataBuffer.clear();
    if (braceCount > 0) {
      _dataBuffer.write(bufferContent);
    }
  }

  void _parseAndNotify(String jsonData) {
    try {
      final decodedJson = jsonDecode(jsonData);
      if (decodedJson is Map<String, dynamic>) {
        final now = DateTime.now();
        final recordData = Map<String, dynamic>.from(decodedJson);
        recordData['uniqueId'] =
            '${now.millisecondsSinceEpoch}_${Random().nextInt(9999)}';
        recordData['receivedTimestamp'] = now.millisecondsSinceEpoch;

        final trainRecord = TrainRecord.fromJson(recordData);
        _dataController.add(trainRecord);
        DatabaseService.instance.insertRecord(trainRecord);
      }
    } catch (e) {
      print("$TAG: JSON Decode Error: $e, Data: $jsonData");
    }
  }

  void _updateConnectionState(bool connected, String status) {
    if (connected) {
      _deviceStatus = "已连接";
    } else {
      _deviceStatus = status;
      _connectedDevice = null;
      _characteristic = null;
    }
    _statusController.add(_deviceStatus);
    _connectionController.add(connected);
  }

  void onAppResume() {
    ensureConnection();
  }

  void setAutoConnectBlocked(bool blocked) {
    _isAutoConnectBlocked = blocked;
  }

  bool get isConnected => _connectedDevice != null;
  String get deviceStatus => _deviceStatus;
  String? get deviceAddress => _connectedDevice?.remoteId.str;
  bool get isScanning => FlutterBluePlus.isScanningNow;
  BluetoothDevice? get connectedDevice => _connectedDevice;
  bool get isManualDisconnect => _isManualDisconnect;

  void dispose() {
    _heartbeatTimer?.cancel();
    disconnect();
    _statusController.close();
    _dataController.close();
    _connectionController.close();
  }
}
