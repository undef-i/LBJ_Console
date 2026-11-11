import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'demod_worker.dart';

class RawLogService {
  RawLogService._();
  static final instance = RawLogService._();

  var _enabled = false;
  bool get enabled => _enabled;
  set enabled(bool value) {
    _enabled = value;
    _changes.add(null);
  }

  final lines = <String>[];
  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;
  StreamSubscription<(String, String)>? _subscription;

  void attach() {
    if (_subscription != null) return;
    _subscription = DemodWorker.instance.rawLogs.listen((event) {
      if (!enabled) return;
      final now = DateTime.now();
      String two(int v) => v.toString().padLeft(2, '0');
      final stamp =
          '${two(now.hour)}:${two(now.minute)}:${two(now.second)}.${now.millisecond.toString().padLeft(3, '0')}';
      lines.add('[$stamp] [${event.$1}] ${event.$2}');
      _changes.add(null);
    });
  }

  Future<String> exportPath() async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/raw_log.txt');
    await file.writeAsString(lines.join('\n'));
    return file.path;
  }
}
