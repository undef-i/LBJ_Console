import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:lbjconsole/screens/main_screen.dart';
import 'package:lbjconsole/themes/app_theme.dart';
import 'package:lbjconsole/ui/liquid_glass.dart';
import 'package:lbjconsole/util/train_type_util.dart';
import 'package:lbjconsole/util/loco_info_util.dart';
import 'package:lbjconsole/services/background_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await _initializeNotifications();

  await BackgroundService.initialize();

  await Future.wait([
    TrainTypeUtil.initialize(),
    LocoInfoUtil.initialize(),
  ]);

  runApp(const LBJReceiverApp());
}

Future<void> _initializeNotifications() async {
  final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);
}

class LBJReceiverApp extends StatelessWidget {
  const LBJReceiverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LBJ Console',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      builder: (context, child) => LiquidGlassScope(
        enabled: true,
        quality: LiquidGlassQuality.standard,
        child: LiquidGlassHost(enabled: true, child: child!),
      ),
      home: const MainScreen(),
    );
  }
}
