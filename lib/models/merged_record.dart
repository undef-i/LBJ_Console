import 'package:lbjconsole/models/train_record.dart';

class MergedTrainRecord {
  final String groupKey;
  final List<TrainRecord> records;
  final TrainRecord latestRecord;

  MergedTrainRecord({
    required this.groupKey,
    required this.records,
    required this.latestRecord,
  });

  int get recordCount => records.length;
}

class MergeSettings {
  final bool enabled;
  final GroupBy groupBy;
  final TimeWindow timeWindow;

  MergeSettings({
    this.enabled = true,
    this.groupBy = GroupBy.trainAndLoco,
    this.timeWindow = TimeWindow.unlimited,
  });

  factory MergeSettings.fromMap(Map<String, dynamic> map) {
    return MergeSettings(
      enabled: (map['mergeRecordsEnabled'] ?? 0) == 1,
      groupBy: GroupBy.values.firstWhere(
        (e) => e.name == map['groupBy'],
        orElse: () => GroupBy.trainAndLoco,
      ),
      timeWindow: TimeWindow.values.firstWhere(
        (e) => e.name == map['timeWindow'],
        orElse: () => TimeWindow.unlimited,
      ),
    );
  }
}

enum GroupBy {
  trainOnly,
  locoOnly,
  trainOrLoco,
  trainAndLoco,
}

enum TimeWindow {
  oneHour(Duration(hours: 1)),
  twoHours(Duration(hours: 2)),
  sixHours(Duration(hours: 6)),
  twelveHours(Duration(hours: 12)),
  oneDay(Duration(days: 1)),
  unlimited(null);

  final Duration? duration;
  const TimeWindow(this.duration);
}
