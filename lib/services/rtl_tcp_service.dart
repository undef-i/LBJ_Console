import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:lbjconsole/models/sync_event.dart';
import 'package:lbjconsole/models/train_record.dart';
import 'package:lbjconsole/services/database_service.dart';
import 'package:lbjconsole/services/demod_worker.dart';
import 'package:lbjconsole/util/app_log.dart';
import 'package:lbjconsole/services/lbj_state.dart';



class RtlTcpService {
  static final RtlTcpService _instance = RtlTcpService._internal();
  factory RtlTcpService() => _instance;
  RtlTcpService._internal();
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

  Stream<String> get statusStream => _statusController.stream;
  Stream<TrainRecord> get dataStream => _dataController.stream;
  Stream<LbjSyncEvent> get syncEvents => _syncController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<DateTime?> get lastReceivedTimeStream =>
      _lastReceivedTimeController.stream;
  String _deviceStatus = "未连接";
  bool _isConnected = false;
  DateTime? _lastReceivedTime;
  StreamSubscription? _workerSubscription;
  StreamSubscription? _workerStatusSubscription;
  final LbjState _state = LbjState();
  Timer? _reconnectTimer;
  DateTime? lastStatusAt;
  int lastBytesIn = 0;
  String _lastHost = '127.0.0.1';
  String _lastPort = '14423';
  static const Duration _reconnectInterval = Duration(seconds: 2);
  bool _isEnabled = false;

  static const bool _logRaw = false;
  static const bool _logParsed = false;
  StreamSubscription? _endSubscription;
  bool _hasPending = false;
  double _pendingMagsq = 0;

  bool get isConnected => _isConnected;
  String get deviceStatus => _deviceStatus;

  void _updateConnectionState(bool connected, String status) {
    if (_isConnected == connected && _deviceStatus == status) return;
    final wasConnected = _isConnected;
    _isConnected = connected;
    _deviceStatus = status;
    if (!connected) {
      _lastReceivedTime = null;
      if (wasConnected) {
        _settlePending();
        _state.reset();
      }
      if (_isEnabled) _startAutoReconnect();
    } else {
      _cancelAutoReconnect();
    }
    _statusController.add(_deviceStatus);
    _connectionController.add(_isConnected);
    _lastReceivedTimeController.add(_lastReceivedTime);
  }

  void _startAutoReconnect() {
    if (!_isEnabled || _reconnectTimer != null) return;
    AppLog.info('rtl-tcp', 'auto reconnect started');
    _reconnectTimer = Timer.periodic(_reconnectInterval, (timer) {
      if (_isConnected || !_isEnabled) {
        _cancelAutoReconnect();
        return;
      }
      AppLog.info('rtl-tcp', 'reconnecting');
      _internalConnect();
    });
  }

  void _cancelAutoReconnect() {
    if (_reconnectTimer != null) {
      AppLog.info('rtl-tcp', 'auto reconnect stopped');
      _reconnectTimer!.cancel();
      _reconnectTimer = null;
    }
  }

  void _handleMessage(String addr, int func, String numeric, double magsqRaw) {
    if (addr != lbjInfoAddr && addr != lbjInfo2Addr && addr != lbjSyncAddr) {
      return;
    }

    final String currentRawMessage = "$addr|$func|$numeric";

    if (kDebugMode && _logRaw) {
      AppLog.info('rtl-tcp', 'raw $currentRawMessage');
    }

    if (!_isConnected) {
      _updateConnectionState(true, "已连接");
    }
    _lastReceivedTime = DateTime.now();
    _lastReceivedTimeController.add(_lastReceivedTime);

    _state.updateFromRaw(addr, func, numeric);

    if (addr == lbjSyncAddr && _state.time.isNotEmpty) {
      final now = DateTime.now();
      final event = LbjSyncEvent(
        uniqueId: 'sync_${now.millisecondsSinceEpoch}',
        timestamp: now,
        receivedTimestamp: now,
        timeText: _state.time,
      );
      _syncController.add(event);
      DatabaseService.instance.insertSyncEvent(event);
    }

    if (addr == lbjInfoAddr || addr == lbjInfo2Addr) {
      _hasPending = true;
      _pendingMagsq = magsqRaw;
    }
  }

  void _settlePending() {
    if (!_hasPending) return;
    _hasPending = false;
    final jsonData = _state.toTrainRecordJson(_pendingMagsq);
    final trainRecord = TrainRecord.fromJson(jsonData);
    _state.reset();

    if (kDebugMode && _logParsed) {
      AppLog.info('rtl-tcp', 'parsed ${jsonEncode(jsonData)}');
    }

    _dataController.add(trainRecord);
    DatabaseService.instance.insertRecord(trainRecord);
  }

  void _listenToWorker() {
    _endSubscription ??= DemodWorker.instance.pocsagEnds.listen((kind) {
      if (kind == 'rtl') _settlePending();
    });
    _workerSubscription ??= DemodWorker.instance.events.listen((event) {
      if (event.kind != 'rtl') return;
      try {
        _handleMessage(
          '${event.address}',
          event.function,
          event.content,
          event.magsq,
        );
      } catch (e) {
        AppLog.error('rtl-tcp', 'state machine failed', e);
        _updateConnectionState(false, "数据解析错误");
      }
    });
    _workerStatusSubscription ??=
        DemodWorker.instance.rtlStatus.listen((status) {
      lastStatusAt = DateTime.now();
      lastBytesIn = status.$3;
      final connected = status.$1;
      if (_isConnected != connected) {
        _updateConnectionState(connected, connected ? "已连接" : "已断开");
      }
    });
  }

  Future<void> _internalConnect() async {
    try {
      _listenToWorker();
      await DemodWorker.instance.rtlConnect(_lastHost, _lastPort);
    } catch (e) {
      DemodWorker.instance.reportDiag('数据连接启动失败：$e');
    }
  }

  Future<void> connect({String? host, String? port}) async {
    final settings = await DatabaseService.instance.getAllSettings();
    final dbHost = host ?? settings?['rtl_tcp_host'] ?? '127.0.0.1';
    final dbPort = port ?? settings?['rtl_tcp_port'] ?? '14423';
    _isEnabled = true;
    _lastHost = dbHost;
    _lastPort = dbPort;
    if (_isConnected) return;
    _updateConnectionState(false, "正在连接...");
    _internalConnect();
  }

  Future<void> disconnect() async {
    _isEnabled = false;
    _cancelAutoReconnect();
    try {
      await DemodWorker.instance.rtlDisconnect();
    } catch (e) {
      AppLog.error('rtl-tcp', 'disconnect failed', e);
    }
    _updateConnectionState(false, "已禁用");
  }

  void dispose() {
    _endSubscription?.cancel();
    disconnect();
    _statusController.close();
    _dataController.close();
    _connectionController.close();
    _lastReceivedTimeController.close();
  }
}
