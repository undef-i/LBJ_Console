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


  String get latestRoute => _validRoute(latestRecord);

  String get displayRoute {
    final latest = latestRoute;
    if (latest.isEmpty || latest.contains('*')) {
      for (final record in records) {
        final route = _validRoute(record);
        if (route.isNotEmpty && !route.contains('*')) {
          return route;
        }
      }
    }
    return latest;
  }

  bool get routeIsFallback =>
      displayRoute.isNotEmpty && displayRoute != latestRoute;

  String _firstValue(String Function(TrainRecord) pick) {
    for (final record in records) {
      final value = pick(record).trim();
      if (value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }

  TrainRecord get extrasRecord {
    return latestRecord.copyWith(
      trainRole: _firstValue((r) => r.trainRole),
      stationNumber: _firstValue((r) => r.stationNumber),
      segmentNumber: _firstValue((r) => r.segmentNumber),
      actualSegmentNumber: _firstValue((r) => r.actualSegmentNumber),
      driverNumber: _firstValue((r) => r.driverNumber),
      weightTonnes: _firstValue((r) => r.weightTonnes),
      lengthMeters: _firstValue((r) => r.lengthMeters),
      carCount: _firstValue((r) => r.carCount),
    );
  }
}

String _validRoute(TrainRecord record) {
  final route = record.route.trim();
  if (route.isNotEmpty &&
      !route.runes.every((r) => r == '*'.runes.first) &&
      route != '<NUL>') {
    return route;
  }
  return '';
}

class MergeSettings {
  final bool enabled;
  final GroupBy groupBy;
  final TimeWindow timeWindow;
  final bool hideUngroupableRecords;
  MergeSettings({
    this.enabled = true,
    this.groupBy = GroupBy.trainAndLoco,
    this.timeWindow = TimeWindow.unlimited,
    this.hideUngroupableRecords = false,
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
      hideUngroupableRecords: (map['hideUngroupableRecords'] ?? 0) == 1,
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
