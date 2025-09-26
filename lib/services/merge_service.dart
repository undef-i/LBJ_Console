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

    final now = DateTime.now();
    final validRecords = settings.timeWindow.duration == null
        ? allRecords
        : allRecords
            .where((r) =>
                now.difference(r.receivedTimestamp) <=
                settings.timeWindow.duration!)
            .toList();

    validRecords
        .sort((a, b) => b.receivedTimestamp.compareTo(a.receivedTimestamp));

    if (settings.groupBy == GroupBy.trainOrLoco) {
      return _groupByTrainOrLoco(validRecords);
    }

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
        mergedRecords.add(MergedTrainRecord(
          groupKey: key,
          records: group,
          latestRecord: group.first,
        ));
        for (final record in group) {
          mergedRecordIds.add(record.uniqueId);
        }
      }
    });

    final singleRecords = validRecords
        .where((r) => !mergedRecordIds.contains(r.uniqueId))
        .toList();

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

  static List<Object> _groupByTrainOrLoco(List<TrainRecord> records) {
    final List<MergedTrainRecord> mergedRecords = [];
    final Set<String> usedRecordIds = {};

    for (int i = 0; i < records.length; i++) {
      final record = records[i];
      if (usedRecordIds.contains(record.uniqueId)) continue;

      final group = <TrainRecord>[record];
      usedRecordIds.add(record.uniqueId);

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
          usedRecordIds.add(otherRecord.uniqueId);
        }
      }

      if (group.length >= 2) {
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
      }
    }

    final singleRecords =
        records.where((r) => !usedRecordIds.contains(r.uniqueId)).toList();

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
