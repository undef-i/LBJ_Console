class LbjSyncEvent {
  final String uniqueId;
  final DateTime timestamp;
  final DateTime receivedTimestamp;
  final String timeText;

  LbjSyncEvent({
    required this.uniqueId,
    required this.timestamp,
    required this.receivedTimestamp,
    required this.timeText,
  });

  Map<String, dynamic> toJson() {
    return {
      'uniqueId': uniqueId,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'receivedTimestamp': receivedTimestamp.millisecondsSinceEpoch,
      'timeText': timeText,
    };
  }

  Map<String, dynamic> toDatabaseJson() => toJson();

  factory LbjSyncEvent.fromJson(Map<String, dynamic> json) {
    return LbjSyncEvent(
      uniqueId: json['uniqueId']?.toString() ?? json['id']?.toString() ?? '',
      timestamp:
          DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int? ?? 0),
      receivedTimestamp: DateTime.fromMillisecondsSinceEpoch(
          json['receivedTimestamp'] as int? ?? 0),
      timeText: json['timeText']?.toString() ?? '',
    );
  }

  factory LbjSyncEvent.fromDatabaseJson(Map<String, dynamic> json) =>
      LbjSyncEvent.fromJson(json);
}
