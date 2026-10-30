import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../util/app_log.dart';
import 'pocsag_demod.dart';

class DemodEvent {
  DemodEvent(this.kind, this.address, this.function, this.content, this.magsq);
  final String kind;
  final int address;
  final int function;
  final String content;
  final double magsq;
}

void _workerMain(SendPort mainPort) {
  final mic = MicDemod();
  final fft = AudioFft(4096);
  final iqFft = IqFft(4096);
  final rtl = RtlDemod();
  Socket? socket;
  StreamSubscription<Uint8List>? socketSub;
  var connected = false;
  var connecting = false;
  var generation = 0;
  var bytesIn = 0;

  final port = ReceivePort();
  mainPort.send(port.sendPort);

  void sendStatus() {
    mainPort.send(['rtlStatus', connected, rtl.magsqRaw, bytesIn]);
  }

  Timer.periodic(const Duration(seconds: 2), (_) => sendStatus());

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
      case 'micReset':
        mic.reset();
        break;
      case 'pcm':
        final data = (msg[1] as TransferableTypedData).materialize();
        final samples = data.asInt16List(0, data.lengthInBytes ~/ 2);
        fft.processSamples(samples);
        mic.processSamples(samples);
        for (final m in mic.messages) {
          mainPort.send(['msg', 'mic', m.address, m.function, m.content, 0.0]);
        }
        mic.messages.clear();
        break;
      case 'spectrum':
        (msg[1] as SendPort)
            .send(connected ? iqFft.spectrum500() : fft.spectrum500());
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
                    '数据头不正确：${header.take(4).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}'
                  ]);
                  teardownSocket();
                  connected = false;
                  connecting = false;
                  sendStatus();
                  return;
                }
                headerDone = true;
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
                mainPort.send(['rtlDiag', '数据头校验通过']);
                sendStatus();
                if (rest.isEmpty) return;
                data = Uint8List.fromList(rest);
              }
              bytesIn += data.length;
              iqFft.pushBytes(data);
              rtl.pushBytes(data);
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
              rtl.messages.clear();
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

class DemodWorker {
  DemodWorker._();
  static final DemodWorker instance = DemodWorker._();

  SendPort? _port;
  Future<void>? _starting;
  ReceivePort? _lifecycle;
  final _events = StreamController<DemodEvent>.broadcast();
  final _rtlStatus = StreamController<(bool, double, int)>.broadcast();
  final _diag = StreamController<String>.broadcast();

  Stream<DemodEvent> get events => _events.stream;
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
      }
    });
    _port = await completer.future;
  }

  Future<void> micReset() async {
    await ensureStarted();
    _port!.send(['micReset']);
  }

  Future<void> pushPcm(Uint8List bytes) async {
    await ensureStarted();
    _port!.send(['pcm', TransferableTypedData.fromList([bytes])]);
  }

  Future<Float32List> spectrum() async {
    await ensureStarted();
    final reply = ReceivePort();
    _port!.send(['spectrum', reply.sendPort]);
    try {
      return (await reply.first.timeout(const Duration(seconds: 2)))
          as Float32List;
    } finally {
      reply.close();
    }
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
