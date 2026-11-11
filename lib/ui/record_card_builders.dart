import 'package:flutter/material.dart';
import '../models/ffsk_alarm_event.dart';
import '../models/klw_event.dart';
import '../models/sync_event.dart';
import '../services/ffsk_protocol.dart';
import '../models/train_record.dart';
import '../services/database_service.dart';
import 'package:lbjconsole/ui/glass_card.dart';
import 'package:lbjconsole/ui/glass_dialog.dart';

mixin RecordCardBuilders<T extends StatefulWidget> on State<T> {
  List<KlwEvent> klwEvents = [];

  Future<void> refreshKlwStates() async {
    final events = await DatabaseService.instance.getKlwEvents();
    if (!mounted) return;
    setState(() {
      klwEvents = events;
    });
  }

  Widget buildAlarmCard(FfskAlarmEvent event, {bool selected = false}) {
    final colorScheme = Theme.of(context).colorScheme;
    final timeText = event.receivedTimestamp.toString().split('.')[0];
    final isTrainAlarm = event.functionCode == 1 || event.functionCode == 2;
    final isTestAlarm = event.functionCode == 7 || event.functionCode == 8;
    final titleText = isTrainAlarm && event.trainNumber.isNotEmpty
        ? event.trainNumber
        : event.name;
    final secondLine = isTrainAlarm
        ? [
            event.name,
            if (event.positionText.isNotEmpty) event.positionText,
          ].join(' ')
        : isTestAlarm
        ? ''
        : [
            if (event.lineName.isNotEmpty) event.lineName,
            if (event.positionText.isNotEmpty) event.positionText,
          ].join(' ');
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 8.0),
      radius: 16,
      selected: selected,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    timeText,
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Flexible(
                  child: Text(
                    '防护报警',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    titleText,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (event.rawLocoNumber.isNotEmpty)
                  Flexible(
                    child: Text(
                      locoDigitsDisplay(event.rawLocoNumber),
                      style: TextStyle(
                        fontSize: 14,
                        color: colorScheme.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
            if (secondLine.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  secondLine,
                  style: TextStyle(fontSize: 16, color: colorScheme.onSurface),
                ),
              ),
            if (event.detail.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  event.detail,
                  style: TextStyle(fontSize: 14, color: colorScheme.onSurface),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget buildSyncCard(LbjSyncEvent event, {bool selected = false}) {
    final colorScheme = Theme.of(context).colorScheme;
    final timeText = event.receivedTimestamp.toString().split('.')[0];
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 8.0),
      radius: 16,
      selected: selected,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    timeText,
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Flexible(
                  child: Text(
                    '对时',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              event.timeText,
              style: TextStyle(fontSize: 20, color: colorScheme.onSurface),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildRecordHeader(TrainRecord record, {bool isMerged = false}) {
    final trainType = record.trainType;
    final formattedLocoInfo = record.formattedLocoInfo;

    if (record.trainNumber.isEmpty && formattedLocoInfo.isEmpty) {
      return Text(
        record.displayTime,
        style: TextStyle(
          fontSize: 11,
          color: Theme.of(context).colorScheme.onSurface,
        ),
        overflow: TextOverflow.ellipsis,
      );
    }

    final hasTrainNumber = record.trainNumber.isNotEmpty;
    final hasDirection = record.directionCode == 1 || record.directionCode == 3;
    final hasLocoInfo =
        formattedLocoInfo.isNotEmpty && formattedLocoInfo != "<NUL>";
    final shouldShowTrainRow = hasTrainNumber || hasDirection || hasLocoInfo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                record.displayTime,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (trainType.isNotEmpty)
              Flexible(
                child: Text(
                  trainType,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
        if (shouldShowTrainRow) ...[
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (hasTrainNumber)
                      Flexible(
                        child: Text(
                          record.trainNumber,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (hasTrainNumber && hasDirection)
                      const SizedBox(width: 6),
                    if (hasDirection)
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.onSurface,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Center(
                          child: Text(
                            record.directionChar,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.surface,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (hasLocoInfo)
                Text(
                  formattedLocoInfo,
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
        ],
      ],
    );
  }

  Widget buildPositionAndSpeed(TrainRecord record) {
    final routeStr = record.route.trim();
    final isValidRoute = record.hasValidRoute;
    final isValidPosition = record.hasValidPosition;
    final isValidSpeed = record.hasValidSpeed;
    if (!isValidRoute && !isValidPosition && !isValidSpeed) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (isValidRoute || isValidPosition)
            Expanded(
              child: Row(
                children: [
                  if (isValidRoute)
                    Flexible(
                      child: Text(
                        routeStr,
                        style: TextStyle(
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (isValidRoute && isValidPosition) const SizedBox(width: 4),
                  if (isValidPosition)
                    Flexible(
                      child: Text(
                        record.positionText,
                        style: TextStyle(
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
          if (isValidSpeed)
            Text(
              record.speedText,
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              textAlign: TextAlign.right,
            ),
        ],
      ),
    );
  }

  Widget buildLocoInfo(TrainRecord record) {
    final locoInfo = record.locoInfo;
    if (locoInfo == null || locoInfo.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Text(
          locoInfo,
          style: TextStyle(
            fontSize: 14,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget buildExtraInfo(TrainRecord? record, {TextStyle? style}) {
    if (record == null) {
      return const SizedBox.shrink();
    }
    final role = record.extrasRole;
    final stats = record.extrasStats;
    final place = record.extrasPlace;
    final driver = record.extrasDriver;
    if (role.isEmpty && stats.isEmpty && place.isEmpty && driver.isEmpty) {
      return const SizedBox.shrink();
    }
    final textStyle =
        style ??
        TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface);
    Widget line(String left, String right) => Row(
      children: [
        if (left.isNotEmpty) Text(left, style: textStyle),
        const Spacer(),
        if (right.isNotEmpty) Text(right, style: textStyle),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(top: 4.0),
      child: Column(
        children: [
          if (role.isNotEmpty || stats.isNotEmpty) line(role, stats),
          if (place.isNotEmpty || driver.isNotEmpty) ...[
            if (role.isNotEmpty || stats.isNotEmpty) const SizedBox(height: 2),
            line(place, driver),
          ],
        ],
      ),
    );
  }

  String klwValueText(KlwEvent event) => event.pressureKpa != null
      ? '${event.pressureKpa} kPa'
      : (event.parameter.isNotEmpty &&
            event.parameter != 'FF FF' &&
            event.parameter != 'FF A5')
      ? event.paramDisplay
      : '';

  Widget buildTailStateRow(List<KlwEvent> matched) {
    if (matched.isEmpty) {
      return const SizedBox.shrink();
    }
    final event = matched.first;
    final colorScheme = Theme.of(context).colorScheme;
    final time = event.timestamp.toString().substring(11, 19);
    final value = klwValueText(event);
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: GestureDetector(
        onTap: () => showKlwEvents(matched),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: colorScheme.onSurface.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colorScheme.onSurface.withValues(alpha: 0.08),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'KLW ${event.tailNumber}',
                    style: TextStyle(
                      fontSize: 14,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    time,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      value.isEmpty
                          ? event.commandName
                          : '${event.commandName} $value',
                      style: TextStyle(
                        fontSize: 14,
                        color: colorScheme.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    event.locoDisplay,
                    style: TextStyle(
                      fontSize: 14,
                      color: colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void showKlwEvents(List<KlwEvent> events) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    showGlassDialog(
      context: context,
      builder: (context) => GlassDialog(
        title: Text('KLW 历史记录', style: TextStyle(color: onSurface)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final event in events) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    event.timestamp.toString().substring(0, 19),
                    style: TextStyle(fontSize: 12, color: onSurface),
                  ),
                  Text(
                    'KLW ${event.tailNumber}',
                    style: TextStyle(fontSize: 12, color: onSurface),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 1.0, bottom: 6.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        klwValueText(event).isEmpty
                            ? event.commandName
                            : '${event.commandName} ${klwValueText(event)}',
                        style: TextStyle(fontSize: 13, color: onSurface),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      event.locoDisplay,
                      style: TextStyle(fontSize: 13, color: onSurface),
                      textAlign: TextAlign.right,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}
