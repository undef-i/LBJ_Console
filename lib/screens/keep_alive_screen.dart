import 'package:flutter/material.dart';
import 'package:lbjconsole/services/background_service.dart';
import 'package:lbjconsole/services/database_service.dart';
import 'package:lbjconsole/services/keep_alive.dart';
import 'package:lbjconsole/ui/fl_list.dart';
import 'package:lbjconsole/ui/glass_switch.dart';

class KeepAliveScreen extends StatefulWidget {
  const KeepAliveScreen({super.key});

  @override
  State<KeepAliveScreen> createState() => _KeepAliveScreenState();
}

class _KeepAliveScreenState extends State<KeepAliveScreen>
    with WidgetsBindingObserver {
  bool _loaded = false;
  bool _serviceEnabled = false;
  bool _batteryExempt = false;
  bool _watchdogEnabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load();
    }
  }

  Future<void> _load() async {
    final settings = await DatabaseService.instance.getAllSettings();
    final results = await Future.wait([
      KeepAliveNative.isIgnoringBatteryOptimizations(),
      KeepAliveNative.isWatchdogEnabled(),
    ]);
    if (!mounted) return;
    setState(() {
      _serviceEnabled = (settings?['backgroundServiceEnabled'] ?? 0) == 1;
      _batteryExempt = results[0];
      _watchdogEnabled = results[1];
      _loaded = true;
    });
  }

  Future<void> _setServiceEnabled(bool value) async {
    setState(() => _serviceEnabled = value);
    await DatabaseService.instance.setSetting(
      'backgroundServiceEnabled',
      value ? 1 : 0,
    );
    if (value) {
      await BackgroundService.startService();
    } else {
      await BackgroundService.stopService();
    }
  }

  Future<void> _setWatchdogEnabled(bool value) async {
    setState(() => _watchdogEnabled = value);
    await KeepAliveNative.setWatchdogEnabled(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('后台运行管理')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
              children: [
                FlSection(
                  rows: [
                    FlRow(
                      title: const Text('后台服务'),
                      trailing: GlassSwitch(
                        value: _serviceEnabled,
                        onChanged: _setServiceEnabled,
                      ),
                    ),
                    FlRow(
                      title: const Text('电池优化'),
                      trailing: _batteryExempt
                          ? const Text('已豁免')
                          : const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('未豁免'),
                                SizedBox(width: 4),
                                Icon(Icons.chevron_right, size: 20),
                              ],
                            ),
                      onTap: _batteryExempt
                          ? null
                          : () =>
                                KeepAliveNative.requestIgnoreBatteryOptimizations(),
                    ),
                    FlRow(
                      title: const Text('守护进程'),
                      trailing: GlassSwitch(
                        value: _watchdogEnabled,
                        onChanged: _setWatchdogEnabled,
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
