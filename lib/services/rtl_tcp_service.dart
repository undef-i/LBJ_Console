import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:gbk_codec/gbk_codec.dart';
import 'package:lbjconsole/models/train_record.dart';
import 'package:lbjconsole/services/database_service.dart';
import 'package:lbjconsole/util/app_log.dart';

const String _lbjInfoAddr = "1234000";
const String _lbjInfo2Addr = "1234002";
const String _lbjSyncAddr = "1234008";
const int _functionDown = 1;
const int _functionUp = 3;

class _LbJState {
  String train = "<NUL>";
  int direction = -1;
  String speed = "NUL";
  String positionKm = " <NUL>";
  String time = "<NUL>";
  String lbjClass = "NA";
  String loco = "<NUL>";
  String route = "********";

  String posLonDeg = "";
  String posLonMin = "";
  String posLatDeg = "";
  String posLatMin = "";

  String _info2Hex = "";

  void reset() {
    train = "<NUL>";
    direction = -1;
    speed = "NUL";
    positionKm = " <NUL>";
    time = "<NUL>";
    lbjClass = "NA";
    loco = "<NUL>";
    route = "********";
    posLonDeg = "";
    posLonMin = "";
    posLatDeg = "";
    posLatMin = "";
    _info2Hex = "";
  }

  String _recodeBCD(String numericStr) {
    return numericStr
        .replaceAll('.', 'A')
        .replaceAll('U', 'B')
        .replaceAll(' ', 'C')
        .replaceAll('-', 'D')
        .replaceAll(')', 'E')
        .replaceAll('(', 'F');
  }

  int _hexToChar(String hex1, String hex2) {
    final String hex = "$hex1$hex2";
    return int.tryParse(hex, radix: 16) ?? 0;
  }

  String _gbkToUtf8(List<int> gbkBytes) {
    try {
      final validBytes = gbkBytes.where((b) => b != 0).toList();
      return gbk_bytes.decode(validBytes);
    } catch (e) {
      return "";
    }
  }

  void updateFromRaw(String addr, int func, String numeric) {
    if (func == _functionDown || func == _functionUp) {
      direction = func;
    }
    switch (addr) {
      case _lbjInfoAddr:
        final RegExp infoRegex = RegExp(r'^\s*(\S+)\s+(\S+)\s+(\S+)');
        final match = infoRegex.firstMatch(numeric);
        if (match != null) {
          train = match.group(1) ?? "<NUL>";
          speed = match.group(2) ?? "NUL";

          String pos = match.group(3)?.trim() ?? "";

          if (pos.isEmpty) {
            positionKm = " <NUL>";
          } else if (pos.length > 1) {
            positionKm =
                "${pos.substring(0, pos.length - 1)}.${pos.substring(pos.length - 1)}";
          } else {
            positionKm = "0.$pos";
          }
        }
        break;

      case _lbjInfo2Addr:
        String buffer = numeric;
        if (buffer.length < 50) return;
        _info2Hex = _recodeBCD(buffer);

        if (_info2Hex.length >= 4) {
          try {
            List<int> classBytes = [
              _hexToChar(_info2Hex[0], _info2Hex[1]),
              _hexToChar(_info2Hex[2], _info2Hex[3]),
            ];
            lbjClass = String.fromCharCodes(classBytes
                .where((b) => b > 0x1F && b < 0x7F && b != 0x22 && b != 0x2C));
          // ignore: empty_catches
          } catch (e) {}
        }
        if (buffer.length >= 12) loco = buffer.substring(4, 12);

        List<int> routeBytes = List<int>.filled(17, 0);

        if (_info2Hex.length >= 18) {
          try {
            routeBytes[0] = _hexToChar(_info2Hex[14], _info2Hex[15]);
            routeBytes[1] = _hexToChar(_info2Hex[16], _info2Hex[17]);
          // ignore: empty_catches
          } catch (e) {}
        }

        if (_info2Hex.length >= 22) {
          try {
            routeBytes[2] = _hexToChar(_info2Hex[18], _info2Hex[19]);
            routeBytes[3] = _hexToChar(_info2Hex[20], _info2Hex[21]);
          // ignore: empty_catches
          } catch (e) {}
        }

        if (_info2Hex.length >= 30) {
          try {
            routeBytes[4] = _hexToChar(_info2Hex[22], _info2Hex[23]);
            routeBytes[5] = _hexToChar(_info2Hex[24], _info2Hex[25]);
            routeBytes[6] = _hexToChar(_info2Hex[26], _info2Hex[27]);
            routeBytes[7] = _hexToChar(_info2Hex[28], _info2Hex[29]);
          // ignore: empty_catches
          } catch (e) {}
        }
        route = _gbkToUtf8(routeBytes);

        if (buffer.length >= 39) {
          posLonDeg = buffer.substring(30, 33);
          posLonMin = "${buffer.substring(33, 35)}.${buffer.substring(35, 39)}";
        }
        if (buffer.length >= 47) {
          posLatDeg = buffer.substring(39, 41);
          posLatMin = "${buffer.substring(41, 43)}.${buffer.substring(43, 47)}";
        }
        break;

      case _lbjSyncAddr:
        if (numeric.length >= 5) {
          time = "${numeric.substring(1, 3)}:${numeric.substring(3, 5)}";
        }
        break;
    }
  }

  double _convertMagSqToRssi(double magsqRaw) {
    if (magsqRaw <= 0) return -120.0;
    double rssi = 10 * log(magsqRaw) / log(10);
    return (rssi - 30.0).clamp(-120.0, -20.0);
  }

  Map<String, dynamic> toTrainRecordJson(double magsqRaw) {
    final now = DateTime.now();
    final double finalRssi = _convertMagSqToRssi(magsqRaw);

    String gpsPosition = "";
    if (posLatDeg.isNotEmpty && posLatMin.isNotEmpty) {
      gpsPosition = "$posLatDeg°$posLatMin′";
    }
    if (posLonDeg.isNotEmpty && posLonMin.isNotEmpty) {
      gpsPosition += "${gpsPosition.isEmpty ? "" : " "}$posLonDeg°$posLonMin′";
    }

    String kmPosition = positionKm.replaceAll(' <NUL>', '');

    final jsonData = {
      'uniqueId': '${now.millisecondsSinceEpoch}_${Random().nextInt(9999)}',
      'receivedTimestamp': now.millisecondsSinceEpoch,
      'timestamp': now.millisecondsSinceEpoch,
      'rssi': finalRssi,
      'train': train.replaceAll('<NUL>', ''),
      'loco': loco.replaceAll('<NUL>', ''),
      'speed': speed.replaceAll('NUL', ''),
      'position': kmPosition,
      'positionInfo': gpsPosition,
      'route': route.replaceAll('********', ''),
      'lbjClass': lbjClass.replaceAll('NA', ''),
      'time': time.replaceAll('<NUL>', ''),
      'direction': (direction == 1 || direction == 3) ? direction : 0,
      'locoType': "",
    };
    return jsonData;
  }
}

class RtlTcpService {
  static final RtlTcpService _instance = RtlTcpService._internal();
  factory RtlTcpService() => _instance;
  RtlTcpService._internal();
  static const _methodChannel =
      MethodChannel('org.noxylva.lbjconsole/rtl_tcp_method');
  static const _eventChannel =
      EventChannel('org.noxylva.lbjconsole/rtl_tcp_event');
  final StreamController<String> _statusController =
      StreamController<String>.broadcast();
  final StreamController<TrainRecord> _dataController =
      StreamController<TrainRecord>.broadcast();
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();
  final StreamController<DateTime?> _lastReceivedTimeController =
      StreamController<DateTime?>.broadcast();

  Stream<String> get statusStream => _statusController.stream;
  Stream<TrainRecord> get dataStream => _dataController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<DateTime?> get lastReceivedTimeStream =>
      _lastReceivedTimeController.stream;
  String _deviceStatus = "未连接";
  bool _isConnected = false;
  DateTime? _lastReceivedTime;
  StreamSubscription? _eventChannelSubscription;
  final _LbJState _state = _LbJState();
  Timer? _reconnectTimer;
  String _lastHost = '127.0.0.1';
  String _lastPort = '14423';
  static const Duration _reconnectInterval = Duration(seconds: 2);
  bool _isEnabled = false;

  static const bool _logRaw = false;
  static const bool _logParsed = false;
  String _lastRawMessage = "";

  bool get isConnected => _isConnected;
  String get deviceStatus => _deviceStatus;
  String get currentAddress => '$_lastHost:$_lastPort';
  bool get isEnabled => _isEnabled;

  void _updateConnectionState(bool connected, String status) {
    if (_isConnected == connected && _deviceStatus == status) return;
    final wasConnected = _isConnected;
    _isConnected = connected;
    _deviceStatus = status;
    if (!connected) {
      _lastReceivedTime = null;
      if (wasConnected) _state.reset();
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

  void _listenToEventChannel() {
    if (_eventChannelSubscription != null) {
      _eventChannelSubscription?.cancel();
    }

    _eventChannelSubscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        try {
          final map = event as Map;

          if (map.containsKey('connected')) {
            final connected = map['connected'] as bool? ?? false;
            if (_isConnected != connected) {
              _updateConnectionState(connected, connected ? "已连接" : "已断开");
            }
          }

          if (map.containsKey('address')) {
            final addr = map['address'] as String;

            if (addr != _lbjInfoAddr &&
                addr != _lbjInfo2Addr &&
                addr != _lbjSyncAddr) {
              return;
            }

            final func = int.tryParse(map['func'] as String? ?? '-1') ?? -1;
            final numeric = map['numeric'] as String;
            final magsqRaw = (map['magsqRaw'] as num?)?.toDouble() ?? 0.0;

            final String currentRawMessage = "$addr|$func|$numeric";
            if (currentRawMessage == _lastRawMessage) {
              return;
            }
            _lastRawMessage = currentRawMessage;

            if (kDebugMode && _logRaw) {
              AppLog.info('rtl-tcp', 'raw $currentRawMessage');
            }

            if (!_isConnected) {
              _updateConnectionState(true, "已连接");
            }
            _lastReceivedTime = DateTime.now();
            _lastReceivedTimeController.add(_lastReceivedTime);

            _state.updateFromRaw(addr, func, numeric);

            if (addr == _lbjInfoAddr || addr == _lbjInfo2Addr) {
              final jsonData = _state.toTrainRecordJson(magsqRaw);
              final trainRecord = TrainRecord.fromJson(jsonData);

              if (kDebugMode && _logParsed) {
                AppLog.info('rtl-tcp', 'parsed ${jsonEncode(jsonData)}');
              }

              _dataController.add(trainRecord);
              DatabaseService.instance.insertRecord(trainRecord);
            }
          }
        } catch (e) {
          AppLog.error('rtl-tcp', 'state machine failed', e);
          _updateConnectionState(false, "数据解析错误");
        }
      },
      onError: (dynamic error) {
        _updateConnectionState(false, "数据通道错误");
        _eventChannelSubscription?.cancel();
        _eventChannelSubscription = null;
      },
      onDone: () {
        _updateConnectionState(false, "连接已断开");
        _eventChannelSubscription = null;
      },
    );
  }

  Future<void> _internalConnect() async {
    if (_eventChannelSubscription == null) {
      _listenToEventChannel();
    }

    try {
      await _methodChannel
          .invokeMethod('connect', {'host': _lastHost, 'port': _lastPort});
    } on PlatformException catch (e) {
      _updateConnectionState(false, "连接失败: ${e.message}");
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
    await _eventChannelSubscription?.cancel();
    _eventChannelSubscription = null;
    try {
      await _methodChannel.invokeMethod('disconnect');
    } catch (e) {
      AppLog.error('rtl-tcp', 'native disconnect failed', e);
    }
    _updateConnectionState(false, "已禁用");
  }

  void dispose() {
    disconnect();
    _statusController.close();
    _dataController.close();
    _connectionController.close();
    _lastReceivedTimeController.close();
  }
}
