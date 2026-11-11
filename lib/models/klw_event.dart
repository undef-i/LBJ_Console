import 'package:lbjconsole/models/train_record.dart';
import 'package:lbjconsole/services/ffsk_protocol.dart';

const klwCommandNames = <int, String>{
  0x24: '排风',
  0x25: '排风应答',
  0x91: '查询风压',
  0x92: '查询风压应答',
  0x83: '消号',
  0x84: '消号应答',
  0xB5: '输号',
  0xB6: '输号应答',
  0x5B: '列尾输号请求',
  0x30: '风压报警',
  0x31: '风压报警应答',
  0xB0: '电池欠压报警',
  0xB1: '电池欠压应答',
  0x93: '自动查询风压',
  0x94: '自动查询风压应答',
  0xA1: '时钟校准',
  0xA2: '时钟校准应答',
  0xA3: '风压校准',
  0xA4: '风压校准应答',
};

class KlwEvent {
  final String uniqueId;
  final DateTime timestamp;
  final DateTime receivedTimestamp;
  final String rawLocoNumber;
  final String tailNumber;
  final int commandCode;
  final String parameter;
  final int? pressureKpa;

  KlwEvent({
    required this.uniqueId,
    required this.timestamp,
    required this.receivedTimestamp,
    required this.rawLocoNumber,
    required this.tailNumber,
    required this.commandCode,
    this.parameter = '',
    this.pressureKpa,
  });

  String get commandName =>
      klwCommandNames[commandCode] ??
      '命令 ${commandCode.toRadixString(16).toUpperCase().padLeft(2, '0')}';

  String get locoDisplay => locoDigitsDisplay(rawLocoNumber);

  String get paramDisplay {
    final digits = parameter.trim();
    if (digits.length == 12 && int.tryParse(digits) != null) {
      final month = int.parse(digits.substring(2, 4));
      final day = int.parse(digits.substring(4, 6));
      final hour = int.parse(digits.substring(6, 8));
      final minute = int.parse(digits.substring(8, 10));
      final second = int.parse(digits.substring(10, 12));
      if (month >= 1 &&
          month <= 12 &&
          day >= 1 &&
          day <= 31 &&
          hour <= 23 &&
          minute <= 59 &&
          second <= 59) {
        return '20${digits.substring(0, 2)}-${digits.substring(2, 4)}-${digits.substring(4, 6)} ${digits.substring(6, 8)}:${digits.substring(8, 10)}:${digits.substring(10, 12)}';
      }
    }
    return parameter;
  }

  Map<String, dynamic> toJson() {
    return {
      'uniqueId': uniqueId,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'receivedTimestamp': receivedTimestamp.millisecondsSinceEpoch,
      'rawLocoNumber': rawLocoNumber,
      'tailNumber': tailNumber,
      'commandCode': commandCode,
      'parameter': parameter,
      'pressureKpa': pressureKpa,
    };
  }

  Map<String, dynamic> toDatabaseJson() => toJson();

  factory KlwEvent.fromJson(Map<String, dynamic> json) {
    return KlwEvent(
      uniqueId: json['uniqueId']?.toString() ?? json['id']?.toString() ?? '',
      timestamp:
          DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int? ?? 0),
      receivedTimestamp: DateTime.fromMillisecondsSinceEpoch(
          json['receivedTimestamp'] as int? ?? 0),
      rawLocoNumber:
          json['rawLocoNumber']?.toString() ?? json['loco']?.toString() ?? '',
      tailNumber:
          json['tailNumber']?.toString() ?? json['tail']?.toString() ?? '',
      commandCode: json['commandCode'] as int? ?? json['command'] as int? ?? 0,
      parameter:
          json['parameter']?.toString() ?? json['param']?.toString() ?? '',
      pressureKpa: json['pressureKpa'] as int? ?? json['pressure'] as int?,
    );
  }

  factory KlwEvent.fromDatabaseJson(Map<String, dynamic> json) =>
      KlwEvent.fromJson(json);
}

class KlwState {
  static String locoKey(String loco) =>
      loco.replaceAll(' ', '').replaceAll('-', '').toUpperCase();

  static String recordKey(TrainRecord record) {
    final raw = record.rawLocoNumber.trim();
    if (raw.isNotEmpty) return raw;
    final parsed = record.parsedLocoNumber.trim();
    if (parsed.length == 8 && int.tryParse(parsed) != null) {
      return parsed;
    }
    final dash = parsed.lastIndexOf('-');
    if (dash > 0) {
      final serial = parsed.substring(dash + 1);
      final code = locoModelCode(parsed.substring(0, dash));
      if (code != null &&
          (serial.length == 4 || serial.length == 5) &&
          int.tryParse(serial) != null) {
        final tail = serial.length == 5 ? serial : '0$serial';
        return '${code.toString().padLeft(3, '0')}$tail';
      }
    }
    return locoKey(parsed);
  }

  static List<KlwEvent> eventsForRecords(
      List<KlwEvent> events, Iterable<TrainRecord> records) {
    final keys = {for (final record in records) recordKey(record)};
    final matched =
        events.where((event) => keys.contains(event.rawLocoNumber)).toList();
    matched.sort(
        (a, b) => b.receivedTimestamp.compareTo(a.receivedTimestamp));
    return matched;
  }

  static Map<String, List<KlwEvent>> groupByLoco(List<KlwEvent> events) {
    final groups = <String, List<KlwEvent>>{};
    for (final event in events) {
      groups.putIfAbsent(locoKey(event.rawLocoNumber), () => []).add(event);
    }
    for (final group in groups.values) {
      group.sort(
          (a, b) => b.receivedTimestamp.compareTo(a.receivedTimestamp));
    }
    return groups;
  }
}
