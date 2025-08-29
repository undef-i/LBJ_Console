import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';

class LocoTypeUtil {
  static final LocoTypeUtil _instance = LocoTypeUtil._internal();
  factory LocoTypeUtil() => _instance;
  LocoTypeUtil._internal() {
    _syncInitialize();
  }

  final Map<String, String> _locoTypeMap = {};
  bool _isInitialized = false;

  void _syncInitialize() {
    try {
      rootBundle.loadString('assets/loco_type_info.csv').then((csvData) {
        final lines = const LineSplitter().convert(csvData);
        for (final line in lines) {
          final trimmedLine = line.trim();
          if (trimmedLine.isEmpty) continue;
          final parts = trimmedLine.split(',');
          if (parts.length >= 2) {
            final code = parts[0].trim();
            final type = parts[1].trim();
            _locoTypeMap[code] = type;
          }
        }
        _isInitialized = true;
      });
    } catch (e) {}
  }

  @deprecated
  Future<void> initialize() async {}

  String? getLocoTypeByCode(String code) {
    return _locoTypeMap[code];
  }

  String? getLocoTypeByLocoNumber(String locoNumber) {
    if (locoNumber.length < 3) return null;
    final prefix = locoNumber.substring(0, 3);
    return getLocoTypeByCode(prefix);
  }

  Map<String, String> getAllMappings() {
    return Map.from(_locoTypeMap);
  }

  bool get isInitialized => _isInitialized;

  int get mappingCount => _locoTypeMap.length;
}
