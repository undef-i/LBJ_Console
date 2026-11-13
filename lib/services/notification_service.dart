import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:lbjconsole/models/train_record.dart';

class NotificationService {
  static const String channelId = 'lbj_messages';
  static const String channelName = 'LBJ Messages';
  static const String channelDescription = 'Receive LBJ messages';

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  int _notificationId = 1000;
  bool enabled = true;

  Future<void> initialize() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (details) {},
    );

    await _createNotificationChannel();
  }

  Future<void> _createNotificationChannel() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      channelId,
      channelName,
      description: channelDescription,
      importance: Importance.high,
      enableVibration: true,
      playSound: true,
    );

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  Future<void> showTrainNotification(TrainRecord record) async {
    if (!enabled) return;

    final text = buildCardText(record);

    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      ticker: 'ticker',
      styleInformation: BigTextStyleInformation(text.body),
    );

    final NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await _notificationsPlugin.show(
      _notificationId++,
      text.title,
      text.body,
      platformChannelSpecifics,
      payload: 'train_${record.trainNumber}',
    );
  }

  static ({String title, String body}) buildCardText(TrainRecord record) {
    final rawLoco = record.formattedLocoInfo;
    final locoText = rawLoco == '<NUL>' ? '' : rawLoco;
    final direction = record.directionChar;
    final train = record.trainNumber;
    final titleParts = <String>[
      if (train.isNotEmpty)
        train
      else if (locoText.isEmpty)
        '列车',
      if (direction.isNotEmpty) direction,
      if (locoText.isNotEmpty) locoText,
    ];

    final lines = <String>[];
    final positionLine = <String>[
      if (record.hasValidRoute) record.route.trim(),
      if (record.hasValidPosition) record.positionText,
      if (record.hasValidSpeed) record.speedText,
    ].join(' ');
    if (positionLine.isNotEmpty) lines.add(positionLine);

    final locoInfo = record.locoInfo;
    if (locoInfo != null && locoInfo.isNotEmpty) {
      lines.add(locoInfo);
    }

    final extraLine = record.extrasLine;
    if (extraLine.isNotEmpty) lines.add(extraLine);

    return (title: titleParts.join(' '), body: lines.join('\n'));
  }

}
