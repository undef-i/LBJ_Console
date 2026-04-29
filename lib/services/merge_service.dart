import 'package:lbjconsole/models/train_record.dart';
import 'package:lbjconsole/models/merged_record.dart';

class MergeService {
  static bool isNeverGroupableRecord(TrainRecord record, GroupBy groupBy) {
    final train = record.train.trim();
    final loco = record.loco.trim();

    final hasValidTrain =
        train.isNotEmpty && train != "<NUL>" && !train.contains("-----");
    final hasValidLoco = loco.isNotEmpty && loco != "<NUL>";

    switch (groupBy) {
      case GroupBy.trainOnly:
        return !hasValidTrain;

      case GroupBy.locoOnly:
        return !hasValidLoco;

      case GroupBy.trainAndLoco:
        return !hasValidTrain || !hasValidLoco;

      case GroupBy.trainOrLoco:
        return !hasValidTrain && !hasValidLoco;
    }
  }

  static List<TrainRecord> filterUngroupableRecords(
      List<TrainRecord> records, GroupBy groupBy, bool hideUngroupable) {
    if (!hideUngroupable) return records;
    return records
        .where((record) => !isNeverGroupableRecord(record, groupBy))
        .toList();
  }

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

  static bool _hasValidTrain(String train) {
    return train.isNotEmpty && train != "<NUL>" && !train.contains("-----");
  }

  static bool _hasValidLoco(String loco) {
    return loco.isNotEmpty && loco != "<NUL>";
  }

  static List<Object> getMixedList(
      List<TrainRecord> allRecords, MergeSettings settings) {
    if (!settings.enabled) {
      allRecords
          .sort((a, b) => b.receivedTimestamp.compareTo(a.receivedTimestamp));
      return allRecords;
    }

    final filteredRecords = filterUngroupableRecords(
        allRecords, settings.groupBy, settings.hideUngroupableRecords);

    filteredRecords
        .sort((a, b) => b.receivedTimestamp.compareTo(a.receivedTimestamp));

    if (settings.groupBy == GroupBy.trainOrLoco) {
      return _groupByTrainOrLocoWithTimeWindow(
          filteredRecords, settings.timeWindow);
    }

    final groupedRecords = <String, List<TrainRecord>>{};
    for (final record in filteredRecords) {
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

    _reuseDiscardedRecords(discardedRecords, mergedRecordIds, settings.groupBy);

    final singleRecords = filteredRecords
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

  static List<TrainRecord> _applyTimeWindow(
      List<TrainRecord> group, TimeWindow timeWindow) {
    if (timeWindow.duration == null) {
      return group;
    }

    final sortedGroup = List<TrainRecord>.from(group)
      ..sort((a, b) => a.receivedTimestamp.compareTo(b.receivedTimestamp));
    var start = 0;

    while (sortedGroup.length - start > 1) {
      final timeSpan = sortedGroup.last.receivedTimestamp
          .difference(sortedGroup[start].receivedTimestamp);
      if (timeSpan <= timeWindow.duration!) {
        break;
      }
      start++;
    }

    return sortedGroup.sublist(start).reversed.toList();
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
    final trainIndex = <String, List<TrainRecord>>{};
    final locoIndex = <String, List<TrainRecord>>{};

    for (final record in records) {
      final train = record.train.trim();
      final loco = record.loco.trim();
      if (_hasValidTrain(train)) {
        trainIndex.putIfAbsent(train, () => []).add(record);
      }
      if (_hasValidLoco(loco)) {
        locoIndex.putIfAbsent(loco, () => []).add(record);
      }
    }

    for (int i = 0; i < records.length; i++) {
      final record = records[i];
      if (usedRecordIds.contains(record.uniqueId)) continue;

      final recordTrain = record.train.trim();
      final recordLoco = record.loco.trim();
      final candidates = <TrainRecord>{};
      if (_hasValidTrain(recordTrain)) {
        candidates.addAll(trainIndex[recordTrain] ?? const <TrainRecord>[]);
      }
      if (_hasValidLoco(recordLoco)) {
        candidates.addAll(locoIndex[recordLoco] ?? const <TrainRecord>[]);
      }

      final group = <TrainRecord>[record];
      for (final otherRecord in candidates) {
        if (otherRecord.uniqueId == record.uniqueId) continue;
        if (usedRecordIds.contains(otherRecord.uniqueId)) continue;

        final otherTrain = otherRecord.train.trim();
        final otherLoco = otherRecord.loco.trim();

        final trainMatch =
            _hasValidTrain(recordTrain) && recordTrain == otherTrain;
        final locoMatch = _hasValidLoco(recordLoco) && recordLoco == otherLoco;

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

      group.sort((a, b) => b.receivedTimestamp.compareTo(a.receivedTimestamp));
      final processedGroup = _applyTimeWindow(group, timeWindow);

      if (processedGroup.length >= 2) {
        for (final record in processedGroup) {
          usedRecordIds.add(record.uniqueId);
        }

        final firstRecord = processedGroup.first;
        final train = firstRecord.train.trim();
        final loco = firstRecord.loco.trim();
        String uniqueGroupKey;

        if (_hasValidTrain(train) && _hasValidLoco(loco)) {
          uniqueGroupKey = "train_or_loco:${train}_$loco";
        } else if (_hasValidTrain(train) && loco.isEmpty) {
          uniqueGroupKey = "train_or_loco:train:$train";
        } else if (_hasValidLoco(loco)) {
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
}
