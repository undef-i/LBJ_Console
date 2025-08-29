import 'package:lbjconsole/models/train_record.dart';
import 'package:lbjconsole/models/merged_record.dart';

class MergeService {
  static String? _generateGroupKey(TrainRecord record, GroupBy groupBy) {
    final train = record.train.trim();
    final loco = record.loco.trim();
    final hasTrain = train.isNotEmpty && train != "<NUL>";
    final hasLoco = loco.isNotEmpty && loco != "<NUL>";

    switch (groupBy) {
      case GroupBy.trainOnly:
        return hasTrain ? train : null;
      case GroupBy.locoOnly:
        return hasLoco ? loco : null;
      case GroupBy.trainOrLoco:
        if (hasTrain) return train;
        if (hasLoco) return loco;
        return null;
      case GroupBy.trainAndLoco:
        return (hasTrain && hasLoco) ? "${train}_$loco" : null;
    }
  }

  static List<Object> getMixedList(
      List<TrainRecord> allRecords, MergeSettings settings) {
    if (!settings.enabled) {
      allRecords
          .sort((a, b) => b.receivedTimestamp.compareTo(a.receivedTimestamp));
      return allRecords;
    }

    final now = DateTime.now();
    final validRecords = settings.timeWindow.duration == null
        ? allRecords
        : allRecords
            .where((r) =>
                now.difference(r.receivedTimestamp) <=
                settings.timeWindow.duration!)
            .toList();

    final groupedRecords = <String, List<TrainRecord>>{};
    for (final record in validRecords) {
      final key = _generateGroupKey(record, settings.groupBy);
      if (key != null) {
        groupedRecords.putIfAbsent(key, () => []).add(record);
      }
    }

    final List<MergedTrainRecord> mergedRecords = [];
    final Set<String> mergedRecordIds = {};

    groupedRecords.forEach((key, group) {
      if (group.length >= 2) {
        group
            .sort((a, b) => b.receivedTimestamp.compareTo(a.receivedTimestamp));
        final latestRecord = group.first;
        mergedRecords.add(MergedTrainRecord(
          groupKey: key,
          records: group,
          latestRecord: latestRecord,
        ));
        for (final record in group) {
          mergedRecordIds.add(record.uniqueId);
        }
      }
    });

    final singleRecords =
        allRecords.where((r) => !mergedRecordIds.contains(r.uniqueId)).toList();

    final List<Object> mixedList = [...mergedRecords, ...singleRecords];
    mixedList.sort((a, b) {
      final aTime = a is MergedTrainRecord
          ? a.latestRecord.receivedTimestamp
          : (a as TrainRecord).receivedTimestamp;
      final bTime = b is MergedTrainRecord
          ? b.latestRecord.receivedTimestamp
          : (b as TrainRecord).receivedTimestamp;
      return bTime.compareTo(aTime);
    });

    return mixedList;
  }
}
