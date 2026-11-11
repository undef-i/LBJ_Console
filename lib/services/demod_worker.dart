import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import '../models/ffsk_alarm_event.dart';
import '../models/klw_event.dart';
import '../models/train_record.dart';
import '../util/app_log.dart';
import 'ffsk_protocol.dart';
import 'ffsk_demod.dart';
import 'pocsag_demod.dart';
import 'resource_service.dart';

class DemodEvent {
  DemodEvent(this.kind, this.address, this.function, this.content, this.magsq);
  final String kind;
  final int address;
  final int function;
  final String content;
  final double magsq;
}

const _protoFreq = {'lbj': 821237500, 'klw': 866237500, 'tdcs': 457550000};

void _workerMain(SendPort mainPort) {
  final mic = MicDemod();
  final fft = AudioFft(4096);
  final iqFft = IqFft(4096);
  final rtl = RtlDemod();
  final micFfsk = FfskDecoder();
  final rtlFfsk = FfskDecoder();
  var enabledProtos = <String>['lbj'];
  var cycle = <String>['lbj'];
  var cycleIdx = 0;
  var dwellStartMs = 0;
  var syncStartMs = -1;
  var frameDoneMs = -1;
  var basePocCount = 0;
  var baseSyncCount = 0;
  var baseFrameCount = 0;
  var pocMsgCount = 0;
  var rtlFrameCount = 0;
  var lastLbjMsgMs = -1;
  var ffskSerial = 0;
  Socket? socket;
  StreamSubscription<Uint8List>? socketSub;
  var connected = false;
  var connecting = false;
  var lastPcmMs = 0;
  var generation = 0;
  var bytesIn = 0;

  final port = ReceivePort();
  mainPort.send(port.sendPort);

  void sendStatus() {
    mainPort.send(['rtlStatus', connected, rtl.magsqRaw, bytesIn]);
  }

  Timer.periodic(const Duration(seconds: 2), (_) => sendStatus());

  bool protoOn(String p) => enabledProtos.contains(p);

  int nowMs() => DateTime.now().millisecondsSinceEpoch;

  List<String> buildCycle(List<String> protos) {
    if (protos.length <= 1) return List.of(protos);
    if (!protos.contains('lbj')) return List.of(protos);
    final others = protos.where((p) => p != 'lbj').toList();
    final seq = <String>[];
    for (final o in others) {
      seq.add('lbj');
      seq.add(o);
    }
    if (others.length == 1) seq.add('lbj');
    return seq;
  }

  void sendFreq(int hz) {
    final s = socket;
    if (s == null) return;
    final cmds = ByteData(5);
    cmds.setUint8(0, 0x01);
    cmds.setUint32(1, hz, Endian.big);
    s.add(cmds.buffer.asUint8List());
  }

  void tuneAt(int idx) {
    if (cycle.isEmpty) return;
    cycleIdx = idx % cycle.length;
    sendFreq(_protoFreq[cycle[cycleIdx]]!);
    rtl.reset();
    rtlFfsk.reset();
    iqFft.reset();
    dwellStartMs = nowMs();
    syncStartMs = -1;
    frameDoneMs = -1;
    basePocCount = pocMsgCount;
    baseSyncCount = rtlFfsk.syncCount;
    baseFrameCount = rtlFrameCount;
  }

  double rssiFromMagsq(double magsqRaw) {
    if (magsqRaw <= 0) return -120.0;
    final rssi = 10 * math.log(magsqRaw) / math.ln10;
    return rssi.clamp(-120.0, 0.0).toDouble();
  }


  void emitFfsk(
    List<FfskMessage> messages,
    double rssi, {
    bool poll = false,
    bool gated = true,
  }) {
    for (final m in messages) {
      if (m is FfskKlw) {
        if (poll) {
          rtlFrameCount++;
          frameDoneMs = nowMs();
        }
        if (!gated || protoOn('klw')) {
          final now = nowMs();
          mainPort.send([
            'ffskKlw',
            klwEventJson(m, 'ffsk_${now}_${ffskSerial++}', now),
          ]);
        }
      } else if (m is FfskTdcs) {
        if (poll) {
          rtlFrameCount++;
          frameDoneMs = nowMs();
        }
        if (!gated || protoOn('tdcs')) {
          final now = nowMs();
          mainPort.send([
            'ffskTdcs',
            tdcsRecordJson(m, 'ffsk_${now}_${ffskSerial++}', now, rssi),
          ]);
        }
      } else if (m is FfskAlarm) {
        if (poll) {
          lastLbjMsgMs = nowMs();
        }
        if (!gated || protoOn('lbj')) {
          final now = nowMs();
          mainPort.send([
            'ffskAlarm',
            alarmEventJson(m, 'alarm_${now}_${ffskSerial++}', now),
          ]);
        }
      }
    }
  }

  Timer.periodic(const Duration(milliseconds: 50), (_) {
    if (!connected || cycle.length <= 1) return;
    final now = nowMs();
    final proto = cycle[cycleIdx];
    var syncActive = false;
    if (proto == 'lbj') {
      syncActive = rtl.framing.gotSC || pocMsgCount > basePocCount;
    } else {
      syncActive = rtlFfsk.syncCount > baseSyncCount;
    }
    if (syncActive && syncStartMs < 0) syncStartMs = now;
    if (proto == 'lbj' && lastLbjMsgMs > 0 && now - lastLbjMsgMs < 3000) {
      return;
    }
    if (frameDoneMs > 0) {
      if (now - frameDoneMs >= 200 && rtlFrameCount > baseFrameCount) {
        tuneAt(cycleIdx + 1);
      }
      return;
    }
    if (syncStartMs > 0) {
      if (now - syncStartMs >= 600) tuneAt(cycleIdx + 1);
      return;
    }
    if (now - dwellStartMs >= 250) tuneAt(cycleIdx + 1);
  });

  Future<void> teardownSocket() async {
    await socketSub?.cancel();
    socketSub = null;
    socket?.destroy();
    socket = null;
  }

  port.listen((dynamic raw) async {
    try {
      final msg = raw as List;
      switch (msg[0] as String) {
        case 'locoTypes':
          loadLocoModelNames(msg[1] as String);
          break;
        case 'micReset':
          mic.reset();
          break;
        case 'pcm':
          lastPcmMs = DateTime.now().millisecondsSinceEpoch;
          final data = (msg[1] as TransferableTypedData).materialize();
          final samples = data.asInt16List(0, data.lengthInBytes ~/ 2);
          fft.processSamples(samples);
          mic.processSamples(samples);
          for (final m in mic.messages) {
            mainPort.send([
              'msg',
              'mic',
              m.address,
              m.function,
              m.content,
              0.0,
            ]);
          }
          mic.messages.clear();
          for (final line in mic.framing.batchLog) {
            mainPort.send(['rawLog', 'pocsag', line]);
          }
          mic.framing.batchLog.clear();
          if (mic.framing.streamEnded) {
            mic.framing.streamEnded = false;
            mainPort.send(['pocsagEnd', 'mic']);
          }
          final audio = Float32List(samples.length);
          for (var i = 0; i < samples.length; i++) {
            audio[i] = samples[i] / 32768.0;
          }
          emitFfsk(micFfsk.feed(audio), 0.0, gated: false);
          for (final line in micFfsk.frameLog) {
            mainPort.send(['rawLog', 'ffsk', line]);
          }
          micFfsk.frameLog.clear();
          break;
        case 'spectrum':
          final band = connected && cycle.isNotEmpty
              ? cycle[cycleIdx]
              : 'audio';
          final values = connected
              ? iqFft.spectrum500()
              : DateTime.now().millisecondsSinceEpoch - lastPcmMs <= 1000
              ? fft.spectrum500()
              : Float32List(0);
          (msg[1] as SendPort).send([band, values]);
          break;
        case 'rtlConnect':
          if (connected || connecting) return;
          mainPort.send(['rtlDiag', '正在建立数据连接']);
          connecting = true;
          final gen = ++generation;
          final host = msg[1] as String;
          final portNum = int.tryParse(msg[2] as String) ?? 0;
          rtl.reset();
          iqFft.reset();
          try {
            final s = await Socket.connect(
              host,
              portNum,
              timeout: const Duration(seconds: 5),
            );
            if (gen != generation) {
              s.destroy();
              return;
            }
            socket = s;
            mainPort.send(['rtlDiag', '数据连接已建立']);
            var header = <int>[];
            var headerDone = false;
            socketSub = s.listen(
              (chunk) {
                try {
                  var data = chunk;
                  if (!headerDone) {
                    header.addAll(chunk);
                    if (header.length < 12) return;
                    if (header[0] != 0x52 ||
                        header[1] != 0x54 ||
                        header[2] != 0x4C ||
                        header[3] != 0x30) {
                      mainPort.send([
                        'rtlDiag',
                        '数据头不正确：${header.take(4).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}',
                      ]);
                      teardownSocket();
                      connected = false;
                      connecting = false;
                      sendStatus();
                      return;
                    }
                    headerDone = true;
                    cycle = buildCycle(enabledProtos);
                    final rest = header.sublist(12);
                    header = [];
                    final cmds = ByteData(15);
                    cmds.setUint8(0, 0x02);
                    cmds.setUint32(1, 240000, Endian.big);
                    cmds.setUint8(5, 0x03);
                    cmds.setUint32(6, 1, Endian.big);
                    cmds.setUint8(10, 0x08);
                    cmds.setUint32(11, 1, Endian.big);
                    s.add(cmds.buffer.asUint8List());
                    connected = true;
                    connecting = false;
                    tuneAt(0);
                    mainPort.send(['rtlDiag', '数据头校验通过']);
                    sendStatus();
                    if (rest.isEmpty) return;
                    data = Uint8List.fromList(rest);
                  }
                  bytesIn += data.length;
                  iqFft.pushBytes(data);
                  rtl.pushBytes(data);
                  if (rtl.messages.isNotEmpty) {
                    pocMsgCount += rtl.messages.length;
                    lastLbjMsgMs = nowMs();
                  }
                  if (protoOn('lbj')) {
                    for (final m in rtl.messages) {
                      mainPort.send([
                        'msg',
                        'rtl',
                        m.address,
                        m.function,
                        m.content,
                        rtl.magsqRaw,
                      ]);
                    }
                  }
                  rtl.messages.clear();
                  for (final line in rtl.framing.batchLog) {
                    mainPort.send(['rawLog', 'pocsag', line]);
                  }
                  rtl.framing.batchLog.clear();
                  if (rtl.framing.streamEnded) {
                    rtl.framing.streamEnded = false;
                    mainPort.send(['pocsagEnd', 'rtl']);
                  }
                  if (rtl.audioTap.isNotEmpty) {
                    final audio = Float32List.fromList(rtl.audioTap);
                    rtl.audioTap.clear();
                    emitFfsk(
                      rtlFfsk.feed(audio),
                      rssiFromMagsq(rtl.magsqRaw),
                      poll: true,
                    );
                    for (final line in rtlFfsk.frameLog) {
                      mainPort.send(['rawLog', 'ffsk', line]);
                    }
                    rtlFfsk.frameLog.clear();
                  }
                } catch (e) {
                  mainPort.send(['rtlDiag', '处理数据出错：$e']);
                  teardownSocket();
                  connected = false;
                  connecting = false;
                  sendStatus();
                }
              },
              onDone: () {
                if (!identical(socket, s)) return;
                connected = false;
                connecting = false;
                socket = null;
                socketSub = null;
                mainPort.send(['rtlDiag', '数据连接已断开']);
                sendStatus();
              },
              onError: (Object e) {
                if (!identical(socket, s)) return;
                connected = false;
                connecting = false;
                socket = null;
                socketSub = null;
                mainPort.send(['rtlDiag', '数据连接出错：$e']);
                sendStatus();
              },
            );
          } catch (e) {
            if (gen == generation) {
              connecting = false;
              connected = false;
              mainPort.send(['rtlDiag', '数据连接失败：$e']);
              sendStatus();
            }
          }
          break;
        case 'protoSet':
          final ids = (msg[1] as List)
              .map((e) => e.toString())
              .where((e) => _protoFreq.containsKey(e))
              .toList();
          enabledProtos = ids.isEmpty ? ['lbj'] : ids;
          cycle = buildCycle(enabledProtos);
          if (connected) tuneAt(0);
          break;
        case 'rtlDisconnect':
          generation++;
          connecting = false;
          await teardownSocket();
          if (connected) {
            connected = false;
            sendStatus();
          }
          break;
      }
    } catch (e) {
      mainPort.send(['rtlDiag', '数据处理出错：$e']);
    }
  });
}

class SpectrumFrame {
  SpectrumFrame(this.band, this.values);
  final String band;
  final Float32List values;
}

class DemodWorker {
  DemodWorker._();
  static final DemodWorker instance = DemodWorker._();

  static const protoFreqLabel = {
    'lbj': 'LBJ 821.2375 MHz',
    'klw': 'KLW 866.2375 MHz',
    'tdcs': 'TDCS 457.550 MHz',
  };

  List<String> _protocols = ['lbj'];
  List<String> get protocols => List.unmodifiable(_protocols);

  SendPort? _port;
  Future<void>? _starting;
  ReceivePort? _lifecycle;
  final _events = StreamController<DemodEvent>.broadcast();
  final _pocsagEnds = StreamController<String>.broadcast();
  final _rawLogs = StreamController<(String, String)>.broadcast();
  final _rtlStatus = StreamController<(bool, double, int)>.broadcast();
  final _diag = StreamController<String>.broadcast();
  final _klwEvents = StreamController<KlwEvent>.broadcast();
  final _tdcsRecords = StreamController<TrainRecord>.broadcast();
  final _alarmEvents = StreamController<FfskAlarmEvent>.broadcast();

  Stream<DemodEvent> get events => _events.stream;
  Stream<String> get pocsagEnds => _pocsagEnds.stream;
  Stream<(String, String)> get rawLogs => _rawLogs.stream;

  void logRaw(String kind, String line) {
    _rawLogs.add((kind, line));
  }
  Stream<KlwEvent> get klwEvents => _klwEvents.stream;
  Stream<TrainRecord> get tdcsRecords => _tdcsRecords.stream;
  Stream<FfskAlarmEvent> get alarmEvents => _alarmEvents.stream;
  Stream<(bool, double, int)> get rtlStatus => _rtlStatus.stream;
  Stream<String> get diagStream => _diag.stream;

  void reportDiag(String message) {
    _diag.add(message);
  }

  Future<void> ensureStarted() {
    if (_port != null) return Future.value();
    return _starting ??= _start().whenComplete(() {
      if (_port == null) _starting = null;
    });
  }

  void _ensureLifecycle() {
    if (_lifecycle != null) return;
    final lifecycle = ReceivePort();
    _lifecycle = lifecycle;
    lifecycle.listen((dynamic msg) {
      if (msg is List) {
        AppLog.error('demod', 'worker error: ${msg.first}');
        _diag.add('数据处理出错：${msg.first}');
      }
      _port = null;
      _starting = null;
    });
  }

  Future<void> _start() async {
    _ensureLifecycle();
    final receive = ReceivePort();
    try {
      await Isolate.spawn(
        _workerMain,
        receive.sendPort,
        onError: _lifecycle!.sendPort,
        onExit: _lifecycle!.sendPort,
      );
    } catch (e) {
      _diag.add('数据处理启动失败：$e');
      rethrow;
    }
    final completer = Completer<SendPort>();
    receive.listen((dynamic msg) {
      if (msg is SendPort) {
        _diag.add('数据处理已启动');
        if (!completer.isCompleted) completer.complete(msg);
        return;
      }
      final list = msg as List;
      switch (list[0] as String) {
        case 'msg':
          _events.add(
            DemodEvent(
              list[1] as String,
              list[2] as int,
              list[3] as int,
              list[4] as String,
              (list[5] as num).toDouble(),
            ),
          );
          break;
        case 'rawLog':
          _rawLogs.add((list[1] as String, list[2] as String));
          break;
        case 'pocsagEnd':
          _pocsagEnds.add(list[1] as String);
          break;
        case 'rtlStatus':
          _rtlStatus.add((
            list[1] as bool,
            (list[2] as num).toDouble(),
            (list[3] as num).toInt(),
          ));
          break;
        case 'rtlDiag':
          AppLog.error('rtl-tcp', list[1] as String);
          _diag.add(list[1] as String);
          break;
        case 'ffskKlw':
          _klwEvents.add(
            KlwEvent.fromDatabaseJson(list[1] as Map<String, dynamic>),
          );
          break;
        case 'ffskTdcs':
          _tdcsRecords.add(
            TrainRecord.fromJson(list[1] as Map<String, dynamic>),
          );
          break;
        case 'ffskAlarm':
          _alarmEvents.add(
            FfskAlarmEvent.fromJson(list[1] as Map<String, dynamic>),
          );
          break;
      }
    });
    _port = await completer.future;
    refreshLocoTypes();
  }

  Future<void> refreshLocoTypes() async {
    final text = await ResourceService.loadText('loco_type_info');
    loadLocoModelNames(text);
    _port?.send(['locoTypes', text]);
  }

  Future<void> micReset() async {
    await ensureStarted();
    _port!.send(['micReset']);
  }

  Future<void> pushPcm(Uint8List bytes) async {
    await ensureStarted();
    _port!.send([
      'pcm',
      TransferableTypedData.fromList([bytes]),
    ]);
  }

  Future<SpectrumFrame> spectrum() async {
    await ensureStarted();
    final reply = ReceivePort();
    _port!.send(['spectrum', reply.sendPort]);
    try {
      final result =
          await reply.first.timeout(const Duration(seconds: 2)) as List;
      return SpectrumFrame(result[0] as String, result[1] as Float32List);
    } finally {
      reply.close();
    }
  }

  static List<String> protocolsFromSettings(Map<String, dynamic> settings) {
    final source = settings['inputSource'] as String? ?? '';
    final prefix = switch (source) {
      'usb' => 'protoUsb',
      'rtlTcp' => 'protoRtl',
      _ => '',
    };
    if (prefix.isEmpty) return ['lbj'];
    final ids = <String>[];
    if (((settings['${prefix}Lbj'] as num?) ?? 1) == 1) ids.add('lbj');
    if (((settings['${prefix}Klw'] as num?) ?? 0) == 1) ids.add('klw');
    if (((settings['${prefix}Tdcs'] as num?) ?? 0) == 1) ids.add('tdcs');
    return ids.isEmpty ? ['lbj'] : ids;
  }

  Future<void> setProtocols(List<String> ids) async {
    _protocols = ids;
    await ensureStarted();
    _port!.send(['protoSet', ids]);
  }

  Future<void> rtlConnect(String host, String port) async {
    await ensureStarted();
    _port!.send(['rtlConnect', host, port]);
  }

  Future<void> rtlDisconnect() async {
    await ensureStarted();
    _port!.send(['rtlDisconnect']);
  }
}
