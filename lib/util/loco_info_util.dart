import 'dart:convert';
import 'package:flutter/services.dart';

class LocoInfoUtil {
  static final List<LocoInfo> _locoData = [];
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      final csvData = await rootBundle.loadString('assets/loco_info.csv');
      final lines = csvData.split('\n');

      for (final line in lines) {
        if (line.trim().isEmpty) continue;

        final fields = _parseCsvLine(line);
        if (fields.length >= 4) {
          try {
            final model = fields[0];
            final start = int.parse(fields[1]);
            final end = int.parse(fields[2]);
            final owner = fields[3];
            final alias = fields.length > 4 ? fields[4] : '';
            final manufacturer = fields.length > 5 ? fields[5] : '';

            _locoData.add(LocoInfo(
              model: model,
              start: start,
              end: end,
              owner: owner,
              alias: alias,
              manufacturer: manufacturer,
            ));
          } catch (e) {}
        }
      }
      _initialized = true;
    } catch (e) {
      _initialized = true;
    }
  }

  static List<String> _parseCsvLine(String line) {
    final fields = <String>[];
    final buffer = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final char = line[i];

      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == ',' && !inQuotes) {
        fields.add(buffer.toString().trim());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }

    fields.add(buffer.toString().trim());
    return fields;
  }

  static LocoInfo? findLocoInfo(String model, String number) {
    if (!_initialized || model.isEmpty || number.isEmpty) {
      return null;
    }

    try {
      final cleanNumber = number.trim().replaceAll('-', '').replaceAll(' ', '');
      final num = cleanNumber.length > 4
          ? int.parse(cleanNumber.substring(cleanNumber.length - 4))
          : int.parse(cleanNumber);

      for (final info in _locoData) {
        if (info.model == model && num >= info.start && num <= info.end) {
          return info;
        }
      }
    } catch (e) {
      return null;
    }

    return null;
  }

  static String? getLocoInfoDisplay(String model, String number) {
    if (_locoData.isEmpty) return null;

    final modelTrimmed = model.trim();
    final numberTrimmed = number.trim();

    if (modelTrimmed.isEmpty ||
        numberTrimmed.isEmpty ||
        numberTrimmed == "<NUL>") {
      return null;
    }

    final cleanNumber = numberTrimmed.replaceAll('-', '').replaceAll(' ', '');
    final numberSuffix = cleanNumber.length >= 4
        ? cleanNumber.substring(cleanNumber.length - 4)
        : cleanNumber.padLeft(4, '0');

    final numberInt = int.tryParse(numberSuffix);
    if (numberInt == null) {
      return null;
    }

    for (final info in _locoData) {
      if (info.model == modelTrimmed &&
          numberInt >= info.start &&
          numberInt <= info.end) {
        final buffer = StringBuffer();
        buffer.write(info.owner);

        if (info.alias.isNotEmpty) {
          buffer.write(' - ${info.alias}');
        }

        if (info.manufacturer.isNotEmpty) {
          buffer.write(' - ${info.manufacturer}');
        }

        return buffer.toString();
      }
    }
    return null;
  }
}

class LocoInfo {
  final String model;
  final int start;
  final int end;
  final String owner;
  final String alias;
  final String manufacturer;

  LocoInfo({
    required this.model,
    required this.start,
    required this.end,
    required this.owner,
    required this.alias,
    required this.manufacturer,
  });
}
