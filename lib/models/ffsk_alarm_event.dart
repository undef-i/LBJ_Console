import 'package:lbjconsole/services/ffsk_protocol.dart';

class FfskAlarmEvent {
  final String uniqueId;
  final DateTime timestamp;
  final DateTime receivedTimestamp;
  final int functionCode;
  final String trainNumber;
  final String rawLocoNumber;
  final double? kilometer;
  final String detail;
  final String lineName;

  FfskAlarmEvent({
    required this.uniqueId,
    required this.timestamp,
    required this.receivedTimestamp,
    required this.functionCode,
    this.trainNumber = '',
    this.rawLocoNumber = '',
    this.kilometer,
    this.detail = '',
    this.lineName = '',
  });

  String get name => ffskAlarmNames[functionCode] ?? '防护报警';

  String get positionText {
    if (kilometer == null) return '';
    return '${kilometer!.toStringAsFixed(3)}K';
  }

  Map<String, dynamic> toJson() {
    return {
      'uniqueId': uniqueId,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'receivedTimestamp': receivedTimestamp.millisecondsSinceEpoch,
      'functionCode': functionCode,
      'trainNumber': trainNumber,
      'rawLocoNumber': rawLocoNumber,
      'kilometer': kilometer,
      'detail': detail,
      'lineName': lineName,
    };
  }

  Map<String, dynamic> toDatabaseJson() => toJson();

  factory FfskAlarmEvent.fromJson(Map<String, dynamic> json) {
    return FfskAlarmEvent(
      uniqueId: json['uniqueId']?.toString() ?? json['id']?.toString() ?? '',
      timestamp:
          DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int? ?? 0),
      receivedTimestamp: DateTime.fromMillisecondsSinceEpoch(
          json['receivedTimestamp'] as int? ?? 0),
      functionCode:
          json['functionCode'] as int? ?? json['function'] as int? ?? 0,
      trainNumber:
          json['trainNumber']?.toString() ?? json['train']?.toString() ?? '',
      rawLocoNumber:
          json['rawLocoNumber']?.toString() ?? json['loco']?.toString() ?? '',
      kilometer: (json['kilometer'] as num?)?.toDouble(),
      detail: json['detail']?.toString() ?? '',
      lineName: json['lineName']?.toString() ?? '',
    );
  }

  factory FfskAlarmEvent.fromDatabaseJson(Map<String, dynamic> json) =>
      FfskAlarmEvent.fromJson(json);
}
