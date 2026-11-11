import 'package:lbjconsole/models/klw_event.dart';
import 'package:lbjconsole/models/train_record.dart';
import 'package:lbjconsole/models/merged_record.dart';

class MergeService {
  static bool isNeverGroupableRecord(TrainRecord record, GroupBy groupBy) {
    final hasValidTrain = _hasValidTrain(record.trainNumber.trim());
    final hasValidLoco = _hasValidLocoRecord(record);

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
    final train = _trainKey(record);
    final loco = KlwState.recordKey(record);
    final hasTrain = _hasValidTrain(record.trainNumber.trim());
    final hasLoco = _hasValidLocoRecord(record);

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


  static String _trainKey(TrainRecord record) {
    return record.trainNumber.trim();
  }

  static bool _hasValidTrain(String train) {
    return train.isNotEmpty && train != "<NUL>" && !train.contains("-----");
  }

  static bool _hasValidLocoRecord(TrainRecord record) {
    final raw = record.rawLocoNumber.trim();
    final parsed = record.parsedLocoNumber.trim();
    return (raw.isNotEmpty && raw != "<NUL>") ||
        (parsed.isNotEmpty && parsed != "<NUL>");
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
      final train = _trainKey(record);
      final loco = KlwState.recordKey(record);
      if (_hasValidTrain(record.trainNumber.trim())) {
        trainIndex.putIfAbsent(train, () => []).add(record);
      }
      if (_hasValidLocoRecord(record)) {
        locoIndex.putIfAbsent(loco, () => []).add(record);
      }
    }

    for (int i = 0; i < records.length; i++) {
      final record = records[i];
      if (usedRecordIds.contains(record.uniqueId)) continue;

      final recordTrain = _trainKey(record);
      final recordLoco = KlwState.recordKey(record);
      final candidates = <TrainRecord>{};
      if (_hasValidTrain(record.trainNumber.trim())) {
        candidates.addAll(trainIndex[recordTrain] ?? const <TrainRecord>[]);
      }
      if (_hasValidLocoRecord(record)) {
        candidates.addAll(locoIndex[recordLoco] ?? const <TrainRecord>[]);
      }

      final group = <TrainRecord>[record];
      for (final otherRecord in candidates) {
        if (otherRecord.uniqueId == record.uniqueId) continue;
        if (usedRecordIds.contains(otherRecord.uniqueId)) continue;

        final otherTrain = _trainKey(otherRecord);
        final otherLoco = KlwState.recordKey(otherRecord);

        final trainMatch = _hasValidTrain(record.trainNumber.trim()) &&
            recordTrain == otherTrain;
        final locoMatch =
            _hasValidLocoRecord(record) && recordLoco == otherLoco;

        final rawTrain = record.trainNumber.trim();
        final otherRawTrain = otherRecord.trainNumber.trim();
        final bothTrainEmpty = (rawTrain.isEmpty ||
                rawTrain == "<NUL>" ||
                rawTrain.contains("----")) &&
            (otherRawTrain.isEmpty ||
                otherRawTrain == "<NUL>" ||
                otherRawTrain.contains("----"));

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
        final train = _trainKey(firstRecord);
        final loco = KlwState.recordKey(firstRecord);
        String uniqueGroupKey;

        if (_hasValidTrain(firstRecord.trainNumber.trim()) &&
            _hasValidLocoRecord(firstRecord)) {
          uniqueGroupKey = "train_or_loco:${train}_$loco:${firstRecord.uniqueId}";
        } else if (_hasValidTrain(firstRecord.trainNumber.trim()) &&
            !_hasValidLocoRecord(firstRecord)) {
          uniqueGroupKey = "train_or_loco:train:$train:${firstRecord.uniqueId}";
        } else if (_hasValidLocoRecord(firstRecord)) {
          uniqueGroupKey = "train_or_loco:loco:$loco:${firstRecord.uniqueId}";
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

  static bool recordPassesFieldFilter(TrainRecord record) {
          bool isFieldMeaningful(String field) {
            if (field.isEmpty) {
              return false;
            }
            String cleaned = field.replaceAll('<NUL>', '').trim();
            if (cleaned.isEmpty) {
              return false;
            }
            if (cleaned.runes
                .every((r) => r == '*'.runes.first || r == ' '.runes.first)) {
              return false;
            }
            return true;
          }

          final hasTrainNumber = isFieldMeaningful(record.trainNumber) &&
              !record.trainNumber.contains("-----");

          final hasDirection =
              record.directionCode == 1 || record.directionCode == 3;

          final hasLocoInfo = isFieldMeaningful(record.rawLocoNumber) ||
              isFieldMeaningful(record.parsedLocoNumber);

          final hasRoute = isFieldMeaningful(record.route);

          final hasPosition = isFieldMeaningful(record.kilometerMark);

          final hasSpeed =
              isFieldMeaningful(record.speedKmh) && record.speedKmh != "NUL";

          final hasPositionInfo = record.hasGps;

          final hasTrainType =
              isFieldMeaningful(record.trainType) && record.trainType != "未知";

          final hasTrainClass =
              RegExp(r'^[A-Za-z]').hasMatch(record.trainNumber.trim());

          final shouldShow = hasTrainNumber ||
              hasDirection ||
              hasLocoInfo ||
              hasRoute ||
              hasPosition ||
              hasSpeed ||
              hasPositionInfo ||
              hasTrainType ||
              hasTrainClass;

          return shouldShow;

  }
}
