import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:lbjconsole/models/sync_event.dart';
import 'package:lbjconsole/models/train_record.dart';
import 'package:lbjconsole/services/database_service.dart';
import 'package:lbjconsole/services/demod_worker.dart';
import 'package:lbjconsole/util/app_log.dart';
import 'package:lbjconsole/services/lbj_state.dart';



class AudioInputService {
  static final AudioInputService _instance = AudioInputService._internal();
  factory AudioInputService() => _instance;
  AudioInputService._internal();

  static const _methodChannel =
      MethodChannel('org.noxylva.lbjconsole/audio_input');
  static const _eventChannel =
      EventChannel('org.noxylva.lbjconsole/audio_input_event');

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

  bool _isListening = false;
  DateTime? _lastReceivedTime;
  StreamSubscription? _eventChannelSubscription;
  StreamSubscription? _workerSubscription;
  final LbjState _state = LbjState();
  StreamSubscription? _endSubscription;
  bool _hasPending = false;

  bool get isListening => _isListening;
  DateTime? get lastReceivedTime => _lastReceivedTime;

  void _updateListeningState(bool listening, String status) {
    if (_isListening == listening) return;
    _isListening = listening;
    if (!listening) {
      _lastReceivedTime = null;
      _settlePending();
      _state.reset();
    }
    _statusController.add(status);
    _connectionController.add(listening);
    _lastReceivedTimeController.add(_lastReceivedTime);
  }

  void _handleMessage(String addr, int func, String numeric) {
    if (addr != lbjInfoAddr && addr != lbjInfo2Addr && addr != lbjSyncAddr) {
      return;
    }

    final String currentRawMessage = "$addr|$func|$numeric";

    if (kDebugMode) {
      AppLog.info('audio', 'raw $currentRawMessage');
    }

    if (!_isListening) {
      _updateListeningState(true, "监听中");
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
    }
  }

  void _settlePending() {
    if (!_hasPending) return;
    _hasPending = false;
    final jsonData = _state.toTrainRecordJson();
    final trainRecord = TrainRecord.fromJson(jsonData);
    _state.reset();

    _dataController.add(trainRecord);
    DatabaseService.instance.insertRecord(trainRecord);
  }

  void ensureWorkerListener() => _listenToWorker();

  void _listenToWorker() {
    _endSubscription ??= DemodWorker.instance.pocsagEnds.listen((kind) {
      if (kind == 'mic') _settlePending();
    });
    _workerSubscription ??= DemodWorker.instance.events.listen((event) {
      if (event.kind != 'mic') return;
      try {
        _handleMessage('${event.address}', event.function, event.content);
      } catch (e) {
        AppLog.error('audio', 'state machine failed', e);
      }
    });
  }

  void _listenToEventChannel() {
    if (_eventChannelSubscription != null) {
      _eventChannelSubscription?.cancel();
    }

    _eventChannelSubscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is Uint8List) {
          DemodWorker.instance.pushPcm(event);
          return;
        }
        if (event is Map && event.containsKey('listening')) {
          final listening = event['listening'] as bool? ?? false;
          if (_isListening != listening) {
            _updateListeningState(listening, listening ? "监听中" : "已停止");
          }
        }
      },
      onError: (dynamic error) {
        _updateListeningState(false, "数据通道错误");
        _eventChannelSubscription?.cancel();
      },
    );
  }

  Future<SpectrumFrame> getSpectrum() => DemodWorker.instance.spectrum();

  List<String> get activeProtocols => DemodWorker.instance.protocols;

  Future<bool> startListening() async {
    if (_isListening) return true;

    var status = await Permission.microphone.status;
    if (!status.isGranted) {
      status = await Permission.microphone.request();
      if (!status.isGranted) {
        AppLog.warn('audio', 'microphone permission denied');
        return false;
      }
    }

    try {
      _listenToEventChannel();
      _listenToWorker();
      await DemodWorker.instance.micReset();
      await _methodChannel.invokeMethod('start');
      _isListening = true;
      _statusController.add("监听中");
      _connectionController.add(true);
      AppLog.info('audio', 'started');
      return true;
    } on PlatformException catch (e) {
      AppLog.error('audio', 'start failed', e.message);
      return false;
    }
  }

  Future<void> stopListening() async {
    if (!_isListening) return;

    try {
      await _methodChannel.invokeMethod('stop');
      await DemodWorker.instance.micReset();
      _isListening = false;
      _lastReceivedTime = null;
      _settlePending();
      _state.reset();
      _statusController.add("已停止");
      _connectionController.add(false);
      _lastReceivedTimeController.add(null);
      AppLog.info('audio', 'stopped');
    } catch (e) {
      AppLog.error('audio', 'stop failed', e);
    }
  }

  void dispose() {
    _endSubscription?.cancel();
    _eventChannelSubscription?.cancel();
    _workerSubscription?.cancel();
    _statusController.close();
    _dataController.close();
    _connectionController.close();
    _lastReceivedTimeController.close();
  }
}
