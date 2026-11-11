import 'package:flutter/material.dart';
import 'package:lbjconsole/services/database_service.dart';
import 'package:lbjconsole/ui/fl_list.dart';
import 'package:lbjconsole/ui/glass_dialog.dart';
import 'package:lbjconsole/ui/glass_select.dart';
import 'package:lbjconsole/ui/glass_switch.dart';

class ClearDataScreen extends StatefulWidget {
  const ClearDataScreen({super.key});

  @override
  State<ClearDataScreen> createState() => _ClearDataScreenState();
}

class _ClearDataScreenState extends State<ClearDataScreen> {
  static const _options = <(String, Duration?, String)>[
    ('全部清空', null, '删除全部数据'),
    ('保留最近 24 小时', Duration(hours: 24), '删除 24 小时以前的数据'),
    ('保留最近 7 天', Duration(days: 7), '删除 7 天以前的数据'),
    ('保留最近 30 天', Duration(days: 30), '删除 30 天以前的数据'),
  ];

  int _selected = 0;
  bool _resetSettings = false;
  bool _working = false;

  Future<void> _execute() async {
    final retention = _options[_selected].$2;
    final scope = _options[_selected].$3;
    final confirmed = await showGlassDialog<bool>(
      context: context,
      builder: (context) => GlassDialog(
        title: const Text('清空数据'),
        content: Text('$scope${_resetSettings ? '，并将设置重置为默认' : ''}，无法撤销。是否继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认清空'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _working = true);
    showGlassDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const GlassDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('正在清空数据...'),
          ],
        ),
      ),
    );

    try {
      final database = DatabaseService.instance;
      if (retention == null) {
        await database.deleteAllRecords();
      } else {
        await database.deleteRecordsOlderThan(
          DateTime.now().subtract(retention),
        );
      }
      if (_resetSettings) {
        await database.updateSettings({
          'deviceName': 'LBJReceiver',
          'backgroundServiceEnabled': 0,
          'notificationEnabled': 1,
          'mergeRecordsEnabled': 0,
          'groupBy': 'trainAndLoco',
          'timeWindow': 'unlimited',
          'inputSource': 'bluetooth',
        });
      }
      if (!mounted) return;
      Navigator.pop(context);
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      setState(() => _working = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('清空错误：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('清空数据')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('保留时间'),
            trailing: GlassSelect<int>(
              value: _selected,
              items: [
                for (var i = 0; i < _options.length; i++)
                  DropdownMenuItem(value: i, child: Text(_options[i].$1)),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selected = value);
                }
              },
            ),
          ),
          const Divider(height: 1),
          FlRow(
            title: const Text('重置设置'),
            subtitle: const Text('将设置恢复为默认值'),
            trailing: GlassSwitch(
              value: _resetSettings,
              onChanged: (value) => setState(() => _resetSettings = value),
            ),
            onTap: () => setState(() => _resetSettings = !_resetSettings),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
            child: FilledButton(
              onPressed: _working ? null : _execute,
              child: const Text('清空'),
            ),
          ),
        ],
      ),
    );
  }
}
