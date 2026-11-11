import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:lbjconsole/services/ble_service.dart';
import 'package:lbjconsole/services/keep_alive.dart';

const String _notificationChannelId = 'lbj_console_channel';
const String _notificationChannelName = 'LBJ Console 后台服务';
const String _notificationChannelDescription = '保持蓝牙连接稳定';
const int _notificationId = 114514;

@pragma('vm:entry-point')
class BackgroundService {
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
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);
    }

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: _notificationChannelId,
        initialNotificationTitle: 'LBJ Console',
        initialNotificationContent: '蓝牙连接中',
        foregroundServiceNotificationId: _notificationId,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
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

      service.on('updateStatus').listen((event) {
        final text = event?['text'] as String? ?? '蓝牙连接中';
        service.setForegroundNotificationInfo(
          title: 'LBJ Console',
          content: text,
        );
      });

      service.invoke('ready');
    }

    service.on('stopService').listen((event) {
      service.stopSelf();
    });
  }

  @pragma('vm:entry-point')
  static Future<bool> _onIosBackground(ServiceInstance service) async {
    return true;
  }

  static bool _readyBound = false;

  static Future<void> startService() async {
    await initialize();
    final service = FlutterBackgroundService();

    if (!_readyBound) {
      _readyBound = true;
      service.on('ready').listen((_) => pushBleStatus());
    }

    if (Platform.isAndroid) {
      final isRunning = await service.isRunning();
      if (isRunning) {
        await pushBleStatus();
      } else {
        service.startService();
      }
      await KeepAliveNative.acquireWakeLock();
    } else if (Platform.isIOS) {
      service.startService();
    }
  }

  static Future<void> pushBleStatus() async {
    if (!await isRunning()) return;
    final bleService = BLEService();
    final text = bleService.isConnected
        ? '蓝牙已连接 - ${bleService.deviceStatus}'
        : '蓝牙连接中';
    FlutterBackgroundService().invoke('updateStatus', {'text': text});
  }

  static Future<void> stopService() async {
    await KeepAliveNative.releaseWakeLock();
    final service = FlutterBackgroundService();
    service.invoke('stopService');
  }

  static Future<bool> isRunning() async {
    final service = FlutterBackgroundService();
    return await service.isRunning();
  }
}
