import 'dart:convert';
import 'package:flutter/services.dart';

class TrainTypeUtil {
  static final List<_TrainTypePattern> _patterns = [];
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      final csvData =
          await rootBundle.loadString('assets/train_number_info.csv');
      final lines = csvData.split('\n');

      for (final line in lines) {
        if (line.trim().isEmpty) continue;

        final firstQuoteEnd = line.indexOf('"', 1);
        if (firstQuoteEnd > 0 && firstQuoteEnd < line.length - 1) {
          final regex = line.substring(1, firstQuoteEnd);
          final remainingPart = line.substring(firstQuoteEnd + 1).trim();

          if (remainingPart.startsWith(',"') && remainingPart.endsWith('"')) {
            final type = remainingPart.substring(2, remainingPart.length - 1);
            try {
              _patterns.add(_TrainTypePattern(RegExp(regex), type));
            } catch (e) {}
          }
        }
      }
      _initialized = true;
    } catch (e) {
      _initialized = true;
    }
  }

  static String? getTrainType(String lbjClass, String train) {
    if (!_initialized) {
      return null;
    }

    final lbjClassTrimmed = lbjClass.trim();
    final trainTrimmed = train.trim();

    if (trainTrimmed.isEmpty || trainTrimmed == "<NUL>") {
      return null;
    }

    final actualTrain =
        lbjClassTrimmed == "NA" ? trainTrimmed : lbjClassTrimmed + trainTrimmed;

    for (final pattern in _patterns) {
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
