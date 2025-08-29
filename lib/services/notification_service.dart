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
  bool _notificationsEnabled = true;

  final StreamController<bool> _settingsController =
      StreamController<bool>.broadcast();
  Stream<bool> get settingsStream => _settingsController.stream;

  Future<void> initialize() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    final InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (details) {},
    );

    await _createNotificationChannel();

    _notificationsEnabled = await isNotificationEnabled();
    _settingsController.add(_notificationsEnabled);
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
    if (!_notificationsEnabled) return;

    if (!_isValidValue(record.train) ||
        !_isValidValue(record.route) ||
        !_isValidValue(record.directionText)) {
      return;
    }

    final String title = '列车信息更新';
    final String body = _buildNotificationContent(record);

    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      ticker: 'ticker',
      styleInformation: BigTextStyleInformation(body),
    );

    final NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await _notificationsPlugin.show(
      _notificationId++,
      title,
      body,
      platformChannelSpecifics,
      payload: 'train_${record.train}',
    );
  }

  String _buildNotificationContent(TrainRecord record) {
    final buffer = StringBuffer();

    buffer.writeln('车次: ${record.fullTrainNumber}');
    buffer.writeln('线路: ${record.route}');
    buffer.writeln('方向: ${record.directionText}');

    if (_isValidValue(record.speed)) {
      buffer.writeln('速度: ${record.speed} km/h');
    }

    if (_isValidValue(record.positionInfo)) {
      buffer.writeln('位置: ${record.positionInfo}');
    }

    buffer.writeln('时间: ${record.formattedTime}');

    return buffer.toString().trim();
  }

  bool _isValidValue(String? value) {
    if (value == null || value.isEmpty) return false;
    final trimmed = value.trim();
    return trimmed.isNotEmpty &&
        trimmed != 'NUL' &&
        trimmed != 'NA' &&
        trimmed != '*';
  }

  Future<void> enableNotifications(bool enable) async {
    _notificationsEnabled = enable;
    _settingsController.add(_notificationsEnabled);
  }

  Future<bool> isNotificationEnabled() async {
    return _notificationsEnabled;
  }

  Future<void> cancelAllNotifications() async {
    await _notificationsPlugin.cancelAll();
  }

  void dispose() {
    _settingsController.close();
  }
}
