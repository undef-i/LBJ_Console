import 'package:flutter/services.dart';
import 'package:lbjconsole/services/resource_service.dart';

class TrainTypeUtil {
  static final Map<String, List<_TrainTypePattern>> _patternsByVersion = {};
  static bool _initialized = false;
  static String activeVersion = '2014';

  static Future<void> initialize() async {
    if (_initialized) return;
    _patternsByVersion['2014'] =
        await _load('assets/train_number_info.csv');
    _patternsByVersion['2026-1'] =
        await _load('assets/train_number_info_2026_batch1.csv');
    _patternsByVersion['2026'] =
        await _load('assets/train_number_info_2026.csv');
    activeVersion = ResourceService.trainTypeVersion;
    _initialized = true;
  }

  static Future<List<_TrainTypePattern>> _load(String asset) async {
    final patterns = <_TrainTypePattern>[];
    try {
      final csvData = await rootBundle.loadString(asset);
      for (final line in csvData.split('\n')) {
        if (line.trim().isEmpty) continue;

        final firstQuoteEnd = line.indexOf('"', 1);
        if (firstQuoteEnd > 0 && firstQuoteEnd < line.length - 1) {
          final regex = line.substring(1, firstQuoteEnd);
          final remainingPart = line.substring(firstQuoteEnd + 1).trim();

          if (remainingPart.startsWith(',"') && remainingPart.endsWith('"')) {
            final type = remainingPart.substring(2, remainingPart.length - 1);
            try {
              patterns.add(_TrainTypePattern(RegExp(regex), type));
            // ignore: empty_catches
            } catch (e) {}
          }
        }
      }
    } catch (e) {
      patterns.clear();
    }
    return patterns;
  }

  static Future<void> setVersion(String version) async {
    activeVersion = version;
    await ResourceService.setTrainTypeVersion(version);
  }

  static String? getTrainType(String trainNumber, {DateTime? at}) {
    if (!_initialized) {
      return null;
    }

    final actualTrain = trainNumber.trim();

    if (actualTrain.isEmpty || actualTrain == "<NUL>") {
      return null;
    }

    var version = activeVersion;
    if (version == 'auto') {
      final t = at ?? DateTime.now();
      version = t.isBefore(DateTime(2026, 11, 25)) ? '2014' : '2026-1';
    }

    for (final pattern in _patternsByVersion[version] ??
        const <_TrainTypePattern>[]) {
      if (pattern.regex.hasMatch(actualTrain)) {
        return pattern.type;
      }
    }

    return null;
  }
}

class _TrainTypePattern {
  final RegExp regex;
  final String type;

  _TrainTypePattern(this.regex, this.type);
}
