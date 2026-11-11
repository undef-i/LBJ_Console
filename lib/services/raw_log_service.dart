import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'demod_worker.dart';

class RawLogService {
  RawLogService._();
  static final instance = RawLogService._();

  var enabled = false;
  final lines = <String>[];
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
    });
  }

  Future<String> exportPath() async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/raw_log.txt');
    await file.writeAsString(lines.join('\n'));
    return file.path;
  }
}
