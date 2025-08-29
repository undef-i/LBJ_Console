import 'package:flutter/material.dart';
import 'package:lbjconsole/screens/main_screen.dart';
import 'package:lbjconsole/util/train_type_util.dart';
import 'package:lbjconsole/util/loco_info_util.dart';
import 'package:lbjconsole/util/loco_type_util.dart';
import 'package:lbjconsole/services/loco_type_service.dart';
import 'package:lbjconsole/services/database_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Future.wait([
    TrainTypeUtil.initialize(),
    LocoInfoUtil.initialize(),
    LocoTypeService().initialize(),
  ]);

  runApp(const LBJReceiverApp());
}

class LBJReceiverApp extends StatelessWidget {
  const LBJReceiverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LBJ Console',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      themeMode: ThemeMode.dark,
      home: const MainScreen(),
    );
  }
}
