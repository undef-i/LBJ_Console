import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:lbjconsole/services/ble_service.dart';

const String _notificationChannelId = 'lbj_console_channel';
const String _notificationChannelName = 'LBJ Console 后台服务';
const String _notificationChannelDescription = '保持蓝牙连接稳定';
const int _notificationId = 114514;

@pragma('vm:entry-point')
class BackgroundService {
  static final FlutterBackgroundService _service = FlutterBackgroundService();
  static bool _isInitialized = false;

  static Future<void> initialize() async {
    if (_isInitialized) return;

    final service = FlutterBackgroundService();

    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

    if (Platform.isAndroid) {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        _notificationChannelId,
        _notificationChannelName,
        description: _notificationChannelDescription,
        importance: Importance.low,
        enableLights: false,
        enableVibration: false,
        playSound: false,
      );

      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: _notificationChannelId,
        initialNotificationTitle: 'LBJ Console',
        initialNotificationContent: '蓝牙连接监控中',
        foregroundServiceNotificationId: _notificationId,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: _onStart,
        onBackground: _onIosBackground,
      ),
    );

    _isInitialized = true;
  }

  @pragma('vm:entry-point')
  static void _onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();

    if (service is AndroidServiceInstance) {
      service.on('setAsForeground').listen((event) {
        service.setAsForegroundService();
      });

      service.on('setAsBackground').listen((event) {
        service.setAsBackgroundService();
      });
    }

    service.on('stopService').listen((event) {
      service.stopSelf();
    });

    BLEService().initialize();

    if (service is AndroidServiceInstance) {
      await Future.delayed(const Duration(seconds: 1));
      if (await service.isForegroundService()) {
        final flutterLocalNotificationsPlugin =
            FlutterLocalNotificationsPlugin();

        try {
          const AndroidNotificationChannel channel = AndroidNotificationChannel(
            _notificationChannelId,
            _notificationChannelName,
            description: _notificationChannelDescription,
            importance: Importance.low,
            enableLights: false,
            enableVibration: false,
            playSound: false,
          );

          await flutterLocalNotificationsPlugin
              .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin>()
              ?.createNotificationChannel(channel);

          await flutterLocalNotificationsPlugin.show(
            _notificationId,
            'LBJ Console',
            '蓝牙连接监控中',
            const NotificationDetails(
              android: AndroidNotificationDetails(
                _notificationChannelId,
                _notificationChannelName,
                channelDescription: _notificationChannelDescription,
                icon: '@mipmap/ic_launcher',
                ongoing: true,
                autoCancel: false,
                importance: Importance.low,
                priority: Priority.low,
                enableLights: false,
                enableVibration: false,
                playSound: false,
                onlyAlertOnce: true,
                setAsGroupSummary: false,
                groupKey: 'lbj_console_group',
                visibility: NotificationVisibility.public,
                category: AndroidNotificationCategory.service,
              ),
            ),
          );
        } catch (e) {}
      }
    }

    Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (service is AndroidServiceInstance) {
        if (await service.isForegroundService()) {
          try {
            final bleService = BLEService();
            final isConnected = bleService.isConnected;
            final deviceStatus = bleService.deviceStatus;

            final flutterLocalNotificationsPlugin =
                FlutterLocalNotificationsPlugin();
            await flutterLocalNotificationsPlugin.show(
              _notificationId,
              'LBJ Console',
              isConnected ? '蓝牙已连接 - $deviceStatus' : '蓝牙未连接 - 自动重连中',
              const NotificationDetails(
                android: AndroidNotificationDetails(
                  _notificationChannelId,
                  _notificationChannelName,
                  channelDescription: _notificationChannelDescription,
                  icon: '@mipmap/ic_launcher',
                  ongoing: true,
                  autoCancel: false,
                  importance: Importance.low,
                  priority: Priority.low,
                  enableLights: false,
                  enableVibration: false,
                  playSound: false,
                  onlyAlertOnce: true,
                  setAsGroupSummary: false,
                  groupKey: 'lbj_console_group',
                  visibility: NotificationVisibility.public,
                  category: AndroidNotificationCategory.service,
                ),
              ),
            );
          } catch (e) {}
        }
      }
    });
  }

  @pragma('vm:entry-point')
  static Future<bool> _onIosBackground(ServiceInstance service) async {
    return true;
  }

  static Future<void> startService() async {
    await initialize();
    final service = FlutterBackgroundService();

    if (Platform.isAndroid) {
      final isRunning = await service.isRunning();
      if (!isRunning) {
        service.startService();
      }
    } else if (Platform.isIOS) {
      service.startService();
    }
  }

  static Future<void> stopService() async {
    final service = FlutterBackgroundService();
    service.invoke('stopService');
  }

  static Future<bool> isRunning() async {
    final service = FlutterBackgroundService();
    return await service.isRunning();
  }

  static void setForegroundMode(bool isForeground) {
    final service = FlutterBackgroundService();
    if (isForeground) {
      service.invoke('setAsForeground');
    } else {
      service.invoke('setAsBackground');
    }
  }
}
