import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:lbjconsole/models/ffsk_alarm_event.dart';
import 'package:lbjconsole/models/klw_event.dart';
import 'package:lbjconsole/models/sync_event.dart';
import 'package:lbjconsole/models/train_record.dart';
import 'package:lbjconsole/services/database_service.dart';
import 'package:lbjconsole/services/demod_worker.dart';
import 'package:lbjconsole/services/ffsk_protocol.dart';
import 'package:lbjconsole/services/pocsag_demod.dart';
import 'package:lbjconsole/services/rtl_tcp_service.dart';
import 'package:lbjconsole/services/lbj_state.dart';

class BLEService {
  static final BLEService _instance = BLEService._internal();
  factory BLEService() => _instance;
  BLEService._internal() {
    _rtlTcpService = RtlTcpService();
  }

  late final RtlTcpService _rtlTcpService;
  RtlTcpService? get rtlTcpService => _rtlTcpService;

  static final Guid serviceUuid = Guid("0000ffe0-0000-1000-8000-00805f9b34fb");
  static final Guid charUuid = Guid("0000ffe1-0000-1000-8000-00805f9b34fb");
  static final Guid dataCharUuid = Guid("0000ffe2-0000-1000-8000-00805f9b34fb");
  static final Guid capCharUuid = Guid("0000ffe4-0000-1000-8000-00805f9b34fb");

  BluetoothDevice? _connectedDevice;
  StreamSubscription<List<int>>? _valueSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  StreamSubscription<List<ScanResult>>? _scanResultsSubscription;
  final Set<Function(List<BluetoothDevice>)> _scanListeners =
      <Function(List<BluetoothDevice>)>{};
  List<BluetoothDevice> _lastScanDevices = <BluetoothDevice>[];

  String get targetDeviceName => _targetDeviceName;

  final StreamController<String> _statusController =
      StreamController<String>.broadcast();
  final StreamController<TrainRecord> _dataController =
      StreamController<TrainRecord>.broadcast();
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();
  final StreamController<DateTime?> _lastReceivedTimeController =
      StreamController<DateTime?>.broadcast();
  final StreamController<LbjSyncEvent> _syncController =
      StreamController<LbjSyncEvent>.broadcast();
  final StreamController<TrainRecord> _tdcsController =
      StreamController<TrainRecord>.broadcast();
  final StreamController<KlwEvent> _klwController =
      StreamController<KlwEvent>.broadcast();
  final StreamController<FfskAlarmEvent> _alarmController =
      StreamController<FfskAlarmEvent>.broadcast();

  Stream<String> get statusStream => _statusController.stream;
  Stream<TrainRecord> get dataStream => _dataController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<DateTime?> get lastReceivedTimeStream =>
      _lastReceivedTimeController.stream;
  Stream<LbjSyncEvent> get syncEvents => _syncController.stream;
  Stream<TrainRecord> get tdcsRecords => _tdcsController.stream;
  Stream<KlwEvent> get klwEvents => _klwController.stream;
  Stream<FfskAlarmEvent> get alarmEvents => _alarmController.stream;

  var isV2Device = false;
  var deviceFeatures = 0;
  var firmwareVersion = 0;
  var batteryMv = 0;

  StreamSubscription<List<int>>? _v2DataSubscription;
  StreamSubscription<List<int>>? _v2StatusSubscription;
  final _v2Framing = PocsagFraming();

  set splitOnPreamble(bool value) => _v2Framing.splitOnPreamble = value;
  final _v2State = LbjState();
  final _ffskBuf = <int>[];
  var _v2HasPending = false;
  var _v2PendingRssi = 0;
  var _v2PendingTsUs = -1;
  var _v2Serial = 0;

  String _deviceStatus = "未连接";
  String? _lastKnownDeviceAddress;
  String _targetDeviceName = "LBJReceiver";
  DateTime? _lastReceivedTime;

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
      // ignore: empty_catches
    } catch (e) {}
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
      final connected = await FlutterBluePlus.systemDevices([serviceUuid]);
      final matchingDevices = connected.where(
        (d) => d.remoteId.str == _lastKnownDeviceAddress,
      );
      BluetoothDevice? target = matchingDevices.isNotEmpty
          ? matchingDevices.first
          : null;

      if (target == null) {
        startScan();
        _isConnecting = false;
      } else {
        await connect(target);
      }
    } catch (e) {
      startScan();
      _isConnecting = false;
    }
  }

  void _ensureScanListener() {
    if (_scanResultsSubscription != null) {
      return;
    }
    _scanResultsSubscription = FlutterBluePlus.scanResults.listen((results) {
      final allFoundDevices = results.map((r) => r.device).toList();
      _lastScanDevices = allFoundDevices;

      for (final listener in List<Function(List<BluetoothDevice>)>.of(
        _scanListeners,
      )) {
        listener(allFoundDevices);
      }

      if (isConnected ||
          _isConnecting ||
          _isManualDisconnect ||
          _isAutoConnectBlocked) {
        return;
      }

      for (var device in allFoundDevices) {
        if (_shouldAutoConnectTo(device)) {
          stopScan();
          connect(device);
          break;
        }
      }
    });
  }

  Future<void> startScan({
    String? targetName,
    Duration? timeout,
    Function(List<BluetoothDevice>)? onScanResults,
  }) async {
    _targetDeviceName = targetName ?? _targetDeviceName;
    _ensureScanListener();

    if (onScanResults != null) {
      _scanListeners.add(onScanResults);
      onScanResults(_lastScanDevices);
    }

    try {
      if (!FlutterBluePlus.isScanningNow) {
        _statusController.add("正在扫描...");
        await FlutterBluePlus.startScan(timeout: timeout);
      } else if (timeout != null) {
        await Future<void>.delayed(timeout);
      }
    } catch (e) {
      _statusController.add("扫描失败");
    } finally {
      if (onScanResults != null) {
        _scanListeners.remove(onScanResults);
      }
    }
  }

  bool _shouldAutoConnectTo(BluetoothDevice device) {
    final deviceName = device.platformName;
    final deviceAddress = device.remoteId.str;

    if (_targetDeviceName.isNotEmpty &&
        deviceName.toLowerCase() == _targetDeviceName.toLowerCase()) {
      return true;
    }
    if (_lastKnownDeviceAddress != null &&
        _lastKnownDeviceAddress == deviceAddress) {
      return true;
    }

    return false;
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
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
    _settleV2Pending();
    _v2State.reset();
    _ffskBuf.clear();
    isV2Device = false;
    _v2DataSubscription?.cancel();
    _v2StatusSubscription?.cancel();
    final wasConnected = isConnected;
    _updateConnectionState(false, "连接已断开");
    _connectionStateSubscription?.cancel();

    if (wasConnected && !_isManualDisconnect) {
      ensureConnection();
    }
    _isConnecting = false;
  }

  Future<void> _discoverServicesAndSetupNotifications(
    BluetoothDevice device,
  ) async {
    try {
      final services = await device.discoverServices();
      for (var service in services) {
        if (service.uuid == serviceUuid) {
          BluetoothCharacteristic? v1;
          BluetoothCharacteristic? v2;
          BluetoothCharacteristic? cap;
          for (var char in service.characteristics) {
            if (char.uuid == charUuid) v1 = char;
            if (char.uuid == dataCharUuid) v2 = char;
            if (char.uuid == capCharUuid) cap = char;
          }
          if (v2 != null) {
            await device.requestMtu(517);
            if (cap != null) {
              final capValue = await cap.read();
              if (capValue.length >= 2) {
                deviceFeatures = capValue[1];
              }
              await cap.setNotifyValue(true);
              _v2StatusSubscription = cap.lastValueStream.listen(_onV2Status);
            }
            await v2.setNotifyValue(true);
            _v2DataSubscription = v2.lastValueStream.listen(_onV2Data);
            isV2Device = true;
            _updateConnectionState(true, "已连接");
            _isConnecting = false;
            return;
          }
          if (v1 != null) {
            await device.requestMtu(517);
            await v1.setNotifyValue(true);
            _valueSubscription = v1.lastValueStream.listen(_onDataReceived);
            _updateConnectionState(true, "已连接");
            _isConnecting = false;
            return;
          }
        }
      }
      await device.disconnect();
    } catch (e) {
      await device.disconnect();
    }
  }

  void _onV2Status(List<int> value) {
    if (value.length < 4) return;
    final data = ByteData.sublistView(Uint8List.fromList(value));
    firmwareVersion = data.getUint16(0, Endian.little);
    batteryMv = data.getUint16(2, Endian.little);
  }

  void _onV2Data(List<int> value) {
    if (value.length < 10) return;
    final type = value[0];
    final data = ByteData.sublistView(Uint8List.fromList(value));
    final tsUs = data.getUint64(1, Endian.little);
    var rssi = value[9];
    if (rssi > 127) rssi -= 256;
    final payload = value.sublist(10);
    _lastReceivedTime = DateTime.now();
    _lastReceivedTimeController.add(_lastReceivedTime);
    if (type == 0x01) {
      _onV2Pocsag(payload, tsUs, rssi);
    } else if (type == 0x02) {
      _onV2Ffsk(payload, rssi);
    }
  }

  void _onV2Pocsag(List<int> payload, int tsUs, int rssi) {
    if (payload.isEmpty) {
      _v2Framing.dryUp();
      if (_v2Framing.streamEnded) {
        _v2Framing.streamEnded = false;
        _settleV2Pending();
      }
      return;
    }
    for (final byte in payload) {
      for (var i = 7; i >= 0; i--) {
        _v2Framing.feedBit(((byte >> i) & 1) == 1);
      }
    }
    for (final line in _v2Framing.batchLog) {
      DemodWorker.instance.logRaw('pocsag', line);
    }
    _v2Framing.batchLog.clear();
    while (true) {
      final msg = _v2Framing.takeMessage();
      if (msg == null) break;
      _handleV2Message(msg, tsUs, rssi);
    }
    if (_v2Framing.streamEnded) {
      _v2Framing.streamEnded = false;
      _settleV2Pending();
    }
  }

  void _handleV2Message(PocsagMessage msg, int tsUs, int rssi) {
    final addr = '${msg.address}';
    if (addr != lbjInfoAddr && addr != lbjInfo2Addr && addr != lbjSyncAddr) {
      return;
    }
    _v2State.updateFromRaw(addr, msg.function, msg.content);
    if (addr == lbjSyncAddr && _v2State.time.isNotEmpty) {
      final now = DateTime.now();
      final event = LbjSyncEvent(
        uniqueId: 'sync_${now.millisecondsSinceEpoch}',
        timestamp: now,
        receivedTimestamp: now,
        timeText: _v2State.time,
      );
      _syncController.add(event);
      DatabaseService.instance.insertSyncEvent(event);
    }
    if (addr == lbjInfoAddr || addr == lbjInfo2Addr) {
      _v2HasPending = true;
      _v2PendingRssi = rssi;
      if (tsUs > 0) _v2PendingTsUs = tsUs;
    }
  }

  void _settleV2Pending() {
    if (!_v2HasPending) return;
    _v2HasPending = false;
    final magsq = pow(10, _v2PendingRssi / 10).toDouble();
    final jsonData = _v2State.toTrainRecordJson(magsq);
    jsonData['source'] = 'bluetooth';
    if (_v2PendingTsUs > 0) {
      jsonData['timestamp'] = _v2PendingTsUs ~/ 1000;
    }
    _v2PendingTsUs = -1;
    final record = TrainRecord.fromJson(jsonData);
    _v2State.reset();
    _dataController.add(record);
    DatabaseService.instance.insertRecord(record);
  }

  void _onV2Ffsk(List<int> payload, int rssi) {
    if (payload.isEmpty) {
      _ffskBuf.clear();
      return;
    }
    _ffskBuf.addAll(payload);
    while (_ffskBuf.length >= 2) {
      final total = _ffskBuf[1] + 2;
      if (_ffskBuf.length < total) break;
      final frame = _ffskBuf.sublist(0, total);
      _ffskBuf.removeRange(0, total);
      DemodWorker.instance.logRaw(
        'ffsk',
        frame
            .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
            .join(' '),
      );
      final msg = parseFfskFrame(Uint8List.fromList(frame));
      if (msg == null) continue;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (msg is FfskKlw) {
        _klwController.add(
          KlwEvent.fromJson(
            klwEventJson(msg, 'ble_${now}_${_v2Serial++}', now),
          ),
        );
      } else if (msg is FfskTdcs) {
        _tdcsController.add(
          TrainRecord.fromJson(
            tdcsRecordJson(
              msg,
              'ble_${now}_${_v2Serial++}',
              now,
              rssi.toDouble(),
            ),
          ),
        );
      } else if (msg is FfskAlarm) {
        _alarmController.add(
          FfskAlarmEvent.fromJson(
            alarmEventJson(msg, 'ble_${now}_${_v2Serial++}', now),
          ),
        );
      }
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
      // ignore: empty_catches
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

        if (!recordData.containsKey('timestamp')) {
          recordData['timestamp'] = now.millisecondsSinceEpoch;
        }

        _lastReceivedTime = now;
        _lastReceivedTimeController.add(_lastReceivedTime);

        final trainRecord = TrainRecord.fromJson(recordData);
        _dataController.add(trainRecord);
        DatabaseService.instance.insertRecord(trainRecord);
      }
      // ignore: empty_catches
    } catch (e) {}
  }

  void _updateConnectionState(bool connected, String status) {
    if (connected) {
      _deviceStatus = "已连接";
    } else {
      _deviceStatus = status;
      _connectedDevice = null;
      _lastReceivedTime = null;
      _lastReceivedTimeController.add(null);
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
  BluetoothDevice? get connectedDevice => _connectedDevice;
  bool get isManualDisconnect => _isManualDisconnect;

  void dispose() {
    _heartbeatTimer?.cancel();
    disconnect();
    _statusController.close();
    _dataController.close();
    _connectionController.close();
    _lastReceivedTimeController.close();
    _syncController.close();
    _tdcsController.close();
    _klwController.close();
    _alarmController.close();
  }
}
