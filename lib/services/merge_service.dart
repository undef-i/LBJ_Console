import 'package:lbjconsole/models/train_record.dart';
import 'package:lbjconsole/models/merged_record.dart';

class MergeService {
  static String? _generateGroupKey(TrainRecord record, GroupBy groupBy) {
    final train = record.train.trim();
    final loco = record.loco.trim();
    final hasTrain =
        train.isNotEmpty && train != "<NUL>" && !train.contains("-----");
    final hasLoco = loco.isNotEmpty && loco != "<NUL>";

    switch (groupBy) {
      case GroupBy.trainOnly:
        return hasTrain ? train : null;
      case GroupBy.locoOnly:
        return hasLoco ? loco : null;
      case GroupBy.trainOrLoco:
        if (hasTrain && hasLoco) {
          return "train:$train|loco:$loco";
        } else if (hasTrain) {
          return "train:$train";
        } else if (hasLoco) {
          return "loco:$loco";
        }
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

    allRecords
        .sort((a, b) => b.receivedTimestamp.compareTo(a.receivedTimestamp));

    if (settings.groupBy == GroupBy.trainOrLoco) {
      return _groupByTrainOrLocoWithTimeWindow(allRecords, settings.timeWindow);
    }

    final groupedRecords = <String, List<TrainRecord>>{};
    for (final record in allRecords) {
      final key = _generateGroupKey(record, settings.groupBy);
      if (key != null) {
        groupedRecords.putIfAbsent(key, () => []).add(record);
      }
    }

    final List<MergedTrainRecord> mergedRecords = [];
    final Set<String> mergedRecordIds = {};
    final List<TrainRecord> discardedRecords = [];

    groupedRecords.forEach((key, group) {
      final processedGroup = _applyTimeWindow(group, settings.timeWindow);

      if (processedGroup.length >= 2) {
        mergedRecords.add(MergedTrainRecord(
          groupKey: key,
          records: processedGroup,
          latestRecord: processedGroup.first,
        ));
        for (final record in processedGroup) {
          mergedRecordIds.add(record.uniqueId);
        }
      }

      for (final record in group) {
        if (!processedGroup.contains(record)) {
          discardedRecords.add(record);
        }
      }
    });

    final reusedRecords = _reuseDiscardedRecords(
        discardedRecords, mergedRecordIds, settings.groupBy);

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

  static List<TrainRecord> _applyTimeWindow(
      List<TrainRecord> group, TimeWindow timeWindow) {
    if (timeWindow.duration == null) {
      return group;
    }

    group.sort((a, b) => a.receivedTimestamp.compareTo(b.receivedTimestamp));

    while (group.length > 1) {
      final timeSpan = group.last.receivedTimestamp
          .difference(group.first.receivedTimestamp);

      if (timeSpan <= timeWindow.duration!) {
        break;
      }

      group.removeAt(0);
    }

    group.sort((a, b) => b.receivedTimestamp.compareTo(a.receivedTimestamp));
    return group;
  }

  static List<TrainRecord> _reuseDiscardedRecords(
      List<TrainRecord> discardedRecords,
      Set<String> mergedRecordIds,
      GroupBy groupBy) {
    final reusedRecords = <TrainRecord>[];

    for (final record in discardedRecords) {
      if (mergedRecordIds.contains(record.uniqueId)) continue;

      final key = _generateGroupKey(record, groupBy);
      if (key != null) {
        reusedRecords.add(record);
      }
    }

    return reusedRecords;
  }

  static List<Object> _groupByTrainOrLocoWithTimeWindow(
      List<TrainRecord> records, TimeWindow timeWindow) {
    final List<MergedTrainRecord> mergedRecords = [];
    final List<TrainRecord> singleRecords = [];
    final Set<String> usedRecordIds = {};

    for (int i = 0; i < records.length; i++) {
      final record = records[i];
      if (usedRecordIds.contains(record.uniqueId)) continue;

      final group = <TrainRecord>[record];

      for (int j = i + 1; j < records.length; j++) {
        final otherRecord = records[j];
        if (usedRecordIds.contains(otherRecord.uniqueId)) continue;

        final recordTrain = record.train.trim();
        final otherTrain = otherRecord.train.trim();
        final recordLoco = record.loco.trim();
        final otherLoco = otherRecord.loco.trim();

        final trainMatch = recordTrain.isNotEmpty &&
            recordTrain != "<NUL>" &&
            !recordTrain.contains("-----") &&
            otherTrain.isNotEmpty &&
            otherTrain != "<NUL>" &&
            !otherTrain.contains("-----") &&
            recordTrain == otherTrain;

        final locoMatch = recordLoco.isNotEmpty &&
            recordLoco != "<NUL>" &&
            otherLoco.isNotEmpty &&
            otherLoco != "<NUL>" &&
            recordLoco == otherLoco;

        final bothTrainEmpty = (recordTrain.isEmpty ||
                recordTrain == "<NUL>" ||
                recordTrain.contains("----")) &&
            (otherTrain.isEmpty ||
                otherTrain == "<NUL>" ||
                otherTrain.contains("----"));

        if (trainMatch || locoMatch || (bothTrainEmpty && locoMatch)) {
          group.add(otherRecord);
        }
      }

      final processedGroup = _applyTimeWindow(group, timeWindow);

      if (processedGroup.length >= 2) {
        for (final record in processedGroup) {
          usedRecordIds.add(record.uniqueId);
        }

        final firstRecord = processedGroup.first;
        final train = firstRecord.train.trim();
        final loco = firstRecord.loco.trim();
        String uniqueGroupKey;

        if (train.isNotEmpty &&
            train != "<NUL>" &&
            !train.contains("-----") &&
            loco.isNotEmpty &&
            loco != "<NUL>") {
          uniqueGroupKey = "train_or_loco:${train}_$loco";
        } else if (train.isNotEmpty &&
            train != "<NUL>" &&
            !train.contains("-----") &&
            loco.isEmpty) {
          uniqueGroupKey = "train_or_loco:train:$train";
        } else if (loco.isNotEmpty && loco != "<NUL>") {
          uniqueGroupKey = "train_or_loco:loco:$loco";
        } else {
          uniqueGroupKey = "train_or_loco:group_${mergedRecords.length}";
        }

        mergedRecords.add(MergedTrainRecord(
          groupKey: uniqueGroupKey,
          records: processedGroup,
          latestRecord: processedGroup.first,
        ));
      } else {
        // 处理被丢弃的记录
        for (final record in group) {
          if (!processedGroup.contains(record)) {
            singleRecords.add(record);
            usedRecordIds.add(record.uniqueId);
          }
        }

        if (processedGroup.isNotEmpty) {
          singleRecords.add(processedGroup.first);
          usedRecordIds.add(processedGroup.first.uniqueId);
        }
      }
    }

    final List<Object> result = [...mergedRecords, ...singleRecords];
    result.sort((a, b) {
      final aTime = a is MergedTrainRecord
          ? a.latestRecord.receivedTimestamp
          : (a as TrainRecord).receivedTimestamp;
      final bTime = b is MergedTrainRecord
          ? b.latestRecord.receivedTimestamp
          : (b as TrainRecord).receivedTimestamp;
      return bTime.compareTo(aTime);
    });

    return result;
  }

  static List<Object> _groupByTrainOrLoco(List<TrainRecord> records) {
    final List<MergedTrainRecord> mergedRecords = [];
    final List<TrainRecord> singleRecords = [];
    final Set<String> usedRecordIds = {};

    for (int i = 0; i < records.length; i++) {
      final record = records[i];
      if (usedRecordIds.contains(record.uniqueId)) continue;

      final group = <TrainRecord>[record];

      for (int j = i + 1; j < records.length; j++) {
        final otherRecord = records[j];
        if (usedRecordIds.contains(otherRecord.uniqueId)) continue;

        final recordTrain = record.train.trim();
        final otherTrain = otherRecord.train.trim();
        final recordLoco = record.loco.trim();
        final otherLoco = otherRecord.loco.trim();

        final trainMatch = recordTrain.isNotEmpty &&
            recordTrain != "<NUL>" &&
            !recordTrain.contains("-----") &&
            otherTrain.isNotEmpty &&
            otherTrain != "<NUL>" &&
            !otherTrain.contains("-----") &&
            recordTrain == otherTrain;

        final locoMatch = recordLoco.isNotEmpty &&
            recordLoco != "<NUL>" &&
            otherLoco.isNotEmpty &&
            otherLoco != "<NUL>" &&
            recordLoco == otherLoco;

        final bothTrainEmpty = (recordTrain.isEmpty ||
                recordTrain == "<NUL>" ||
                recordTrain.contains("----")) &&
            (otherTrain.isEmpty ||
                otherTrain == "<NUL>" ||
                otherTrain.contains("----"));

        if (trainMatch || locoMatch || (bothTrainEmpty && locoMatch)) {
          group.add(otherRecord);
        }
      }

      if (group.length >= 2) {
        for (final record in group) {
          usedRecordIds.add(record.uniqueId);
        }

        final firstRecord = group.first;
        final train = firstRecord.train.trim();
        final loco = firstRecord.loco.trim();
        String uniqueGroupKey;

        if (train.isNotEmpty &&
            train != "<NUL>" &&
            !train.contains("-----") &&
            loco.isNotEmpty &&
            loco != "<NUL>") {
          uniqueGroupKey = "train_or_loco:${train}_$loco";
        } else if (train.isNotEmpty &&
            train != "<NUL>" &&
            !train.contains("-----")) {
          uniqueGroupKey = "train_or_loco:train:$train";
        } else if (loco.isNotEmpty && loco != "<NUL>") {
          uniqueGroupKey = "train_or_loco:loco:$loco";
        } else {
          uniqueGroupKey = "train_or_loco:group_${mergedRecords.length}";
        }

        mergedRecords.add(MergedTrainRecord(
          groupKey: uniqueGroupKey,
          records: group,
          latestRecord: group.first,
        ));
      } else {
        singleRecords.add(record);
        usedRecordIds.add(record.uniqueId);
      }
    }

    final List<Object> result = [...mergedRecords, ...singleRecords];
    result.sort((a, b) {
      final aTime = a is MergedTrainRecord
          ? a.latestRecord.receivedTimestamp
          : (a as TrainRecord).receivedTimestamp;
      final bTime = b is MergedTrainRecord
          ? b.latestRecord.receivedTimestamp
          : (b as TrainRecord).receivedTimestamp;
      return bTime.compareTo(aTime);
    });

    return result;
  }
}
