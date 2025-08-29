import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';

import 'package:lbjconsole/models/merged_record.dart';
import 'package:lbjconsole/services/database_service.dart';
import 'package:lbjconsole/services/ble_service.dart';
import 'package:lbjconsole/themes/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late DatabaseService _databaseService;
  late TextEditingController _deviceNameController;

  String _deviceName = '';
  bool _backgroundServiceEnabled = false;
  bool _notificationsEnabled = true;
  int _recordCount = 0;
  bool _mergeRecordsEnabled = false;
  GroupBy _groupBy = GroupBy.trainAndLoco;
  TimeWindow _timeWindow = TimeWindow.unlimited;

  @override
  void initState() {
    super.initState();
    _databaseService = DatabaseService.instance;
    _deviceNameController = TextEditingController();
    _loadSettings();
    _loadRecordCount();
  }

  @override
  void dispose() {
    _deviceNameController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final settingsMap = await _databaseService.getAllSettings() ?? {};
    final settings = MergeSettings.fromMap(settingsMap);
    if (mounted) {
      setState(() {
        _deviceName = settingsMap['deviceName'] ?? 'LBJReceiver';
        _deviceNameController.text = _deviceName;
        _backgroundServiceEnabled =
            (settingsMap['backgroundServiceEnabled'] ?? 0) == 1;
        _notificationsEnabled = (settingsMap['notificationEnabled'] ?? 1) == 1;
        _mergeRecordsEnabled = settings.enabled;
        _groupBy = settings.groupBy;
        _timeWindow = settings.timeWindow;
      });
    }
  }

  Future<void> _loadRecordCount() async {
    final count = await _databaseService.getRecordCount();
    if (mounted) {
      setState(() {
        _recordCount = count;
      });
    }
  }

  Future<void> _saveSettings() async {
    await _databaseService.updateSettings({
      'deviceName': _deviceName,
      'backgroundServiceEnabled': _backgroundServiceEnabled ? 1 : 0,
      'notificationEnabled': _notificationsEnabled ? 1 : 0,
      'mergeRecordsEnabled': _mergeRecordsEnabled ? 1 : 0,
      'groupBy': _groupBy.name,
      'timeWindow': _timeWindow.name,
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBluetoothSettings(),
          const SizedBox(height: 20),
          _buildAppSettings(),
          const SizedBox(height: 20),
          _buildMergeSettings(),
          const SizedBox(height: 20),
          _buildDataManagement(),
          const SizedBox(height: 20),
          _buildAboutSection(),
        ],
      ),
    );
  }

  Widget _buildBluetoothSettings() {
    return Card(
      color: AppTheme.tertiaryBlack,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bluetooth,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Text('蓝牙设备', style: AppTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _deviceNameController,
              decoration: InputDecoration(
                labelText: '设备名称 (用于自动连接)',
                hintText: '输入设备名称',
                labelStyle: const TextStyle(color: Colors.white70),
                hintStyle: const TextStyle(color: Colors.white54),
                border: OutlineInputBorder(
                  borderSide: const BorderSide(color: Colors.white54),
                  borderRadius: BorderRadius.circular(12.0),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Colors.white54),
                  borderRadius: BorderRadius.circular(12.0),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide:
                      BorderSide(color: Theme.of(context).colorScheme.primary),
                  borderRadius: BorderRadius.circular(12.0),
                ),
              ),
              style: const TextStyle(color: Colors.white),
              onChanged: (value) {
                setState(() {
                  _deviceName = value;
                });
                _saveSettings();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppSettings() {
    return Card(
      color: AppTheme.tertiaryBlack,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.settings,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Text('应用设置', style: AppTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('后台保活服务', style: AppTheme.bodyLarge),
                    Text('保持应用在后台运行', style: AppTheme.caption),
                  ],
                ),
                Switch(
                  value: _backgroundServiceEnabled,
                  onChanged: (value) {
                    setState(() {
                      _backgroundServiceEnabled = value;
                    });
                    _saveSettings();
                  },
                  activeColor: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('LBJ消息通知', style: AppTheme.bodyLarge),
                    Text('接收LBJ消息通知', style: AppTheme.caption),
                  ],
                ),
                Switch(
                  value: _notificationsEnabled,
                  onChanged: (value) {
                    setState(() {
                      _notificationsEnabled = value;
                    });
                    _saveSettings();
                  },
                  activeColor: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMergeSettings() {
    return Card(
      color: AppTheme.tertiaryBlack,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.merge_type,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Text('记录合并', style: AppTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('启用记录合并', style: AppTheme.bodyLarge),
                    Text('合并相同内容的LBJ记录', style: AppTheme.caption),
                  ],
                ),
                Switch(
                  value: _mergeRecordsEnabled,
                  onChanged: (value) {
                    setState(() {
                      _mergeRecordsEnabled = value;
                    });
                    _saveSettings();
                  },
                  activeColor: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
            Visibility(
              visible: _mergeRecordsEnabled,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  Text('分组方式', style: AppTheme.bodyLarge),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<GroupBy>(
                    value: _groupBy,
                    items: [
                      DropdownMenuItem(
                          value: GroupBy.trainOnly,
                          child: Text('仅车次号', style: AppTheme.bodyMedium)),
                      DropdownMenuItem(
                          value: GroupBy.locoOnly,
                          child: Text('仅机车号', style: AppTheme.bodyMedium)),
                      DropdownMenuItem(
                          value: GroupBy.trainOrLoco,
                          child: Text('车次号或机车号', style: AppTheme.bodyMedium)),
                      DropdownMenuItem(
                          value: GroupBy.trainAndLoco,
                          child: Text('车次号与机车号', style: AppTheme.bodyMedium)),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _groupBy = value;
                        });
                        _saveSettings();
                      }
                    },
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppTheme.secondaryBlack,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.0),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    dropdownColor: AppTheme.secondaryBlack,
                    style: AppTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  Text('时间窗口', style: AppTheme.bodyLarge),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<TimeWindow>(
                    value: _timeWindow,
                    items: [
                      DropdownMenuItem(
                          value: TimeWindow.oneHour,
                          child: Text('1小时内', style: AppTheme.bodyMedium)),
                      DropdownMenuItem(
                          value: TimeWindow.twoHours,
                          child: Text('2小时内', style: AppTheme.bodyMedium)),
                      DropdownMenuItem(
                          value: TimeWindow.sixHours,
                          child: Text('6小时内', style: AppTheme.bodyMedium)),
                      DropdownMenuItem(
                          value: TimeWindow.twelveHours,
                          child: Text('12小时内', style: AppTheme.bodyMedium)),
                      DropdownMenuItem(
                          value: TimeWindow.oneDay,
                          child: Text('24小时内', style: AppTheme.bodyMedium)),
                      DropdownMenuItem(
                          value: TimeWindow.unlimited,
                          child: Text('不限时间', style: AppTheme.bodyMedium)),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _timeWindow = value;
                        });
                        _saveSettings();
                      }
                    },
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppTheme.secondaryBlack,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.0),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    dropdownColor: AppTheme.secondaryBlack,
                    style: AppTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataManagement() {
    return Card(
      color: AppTheme.tertiaryBlack,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.share, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Text('数据导出', style: AppTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 16),
            _buildActionButton(
              icon: Icons.download,
              title: '导出数据',
              subtitle: '将记录导出为JSON文件',
              onTap: _exportData,
            ),
            const SizedBox(height: 12),
            _buildActionButton(
              icon: Icons.file_download,
              title: '导入数据',
              subtitle: '从JSON文件导入记录和设置',
              onTap: _importData,
            ),
            const SizedBox(height: 12),
            _buildActionButton(
              icon: Icons.clear_all,
              title: '清空数据',
              subtitle: '删除所有记录和设置',
              onTap: _clearAllData,
              isDestructive: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12.0),
      child: Container(
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          color: isDestructive
              ? Colors.red.withOpacity(0.1)
              : AppTheme.secondaryBlack,
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(
            color: isDestructive
                ? Colors.red.withOpacity(0.3)
                : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isDestructive
                  ? Colors.red
                  : Theme.of(context).colorScheme.primary,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTheme.bodyLarge.copyWith(
                      color: isDestructive ? Colors.red : Colors.white,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: AppTheme.caption,
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Colors.white54,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  Future<String> _getAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return 'v${packageInfo.version}';
    } catch (e) {
      return '';
    }
  }

  Future<String?> _selectDirectory() async {
    try {
      // 使用文件选择器选择目录
      final directory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择导出位置',
        lockParentWindow: true,
      );
      return directory;
    } catch (e) {
      // 如果文件选择器失败，使用默认的文档目录
      try {
        final documentsDir = await getApplicationDocumentsDirectory();
        final exportDir = Directory(path.join(documentsDir.path, 'LBJ_Exports'));
        if (!await exportDir.exists()) {
          await exportDir.create(recursive: true);
        }
        return exportDir.path;
      } catch (e) {
        return null;
      }
    }
  }

  Future<void> _exportData() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      // 让用户选择保存位置
      final fileName =
          'LBJ_Console_${DateTime.now().year}${DateTime.now().month.toString().padLeft(2, '0')}${DateTime.now().day.toString().padLeft(2, '0')}.json';
      
      String? selectedDirectory = await _selectDirectory();
      if (selectedDirectory == null) return;

      final filePath = path.join(selectedDirectory, fileName);

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('正在导出数据...'),
            ],
          ),
        ),
      );

      try {
        final exportedPath = await _databaseService.exportDataAsJson(customPath: filePath);
        Navigator.pop(context);

        if (exportedPath != null) {
          final file = File(exportedPath);
          final fileName = file.path.split(Platform.pathSeparator).last;
          
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text('数据已导出到：$fileName'),
              action: SnackBarAction(
                label: '查看',
                onPressed: () async {
                  // 打开文件所在目录
                  try {
                    final directory = file.parent;
                    await Process.run('explorer', [directory.path]);
                  } catch (e) {
                    // 如果无法打开目录，显示路径
                    scaffoldMessenger.showSnackBar(
                      SnackBar(
                        content: Text('文件路径：${file.path}'),
                      ),
                    );
                  }
                },
              ),
            ),
          );
        } else {
          scaffoldMessenger.showSnackBar(
            const SnackBar(
              content: Text('导出失败'),
            ),
          );
        }
      } catch (e) {
        Navigator.pop(context);
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('导出错误：$e'),
          ),
        );
      }
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('选择目录错误：$e'),
        ),
      );
    }
  }

  Future<void> _importData() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入数据'),
        content: const Text('导入将替换所有现有数据，是否继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('继续'),
          ),
        ],
      ),
    );

    if (result != true) return;

    final resultFile = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (resultFile == null) return;
    final selectedFile = resultFile.files.single.path;
    if (selectedFile == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('正在导入数据...'),
          ],
        ),
      ),
    );

    try {
      final success = await _databaseService.importDataFromJson(selectedFile);
      Navigator.pop(context);

      if (success) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('数据导入成功'),
          ),
        );

        await _loadSettings();
        await _loadRecordCount();
        setState(() {});
      } else {
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('数据导入失败'),
          ),
        );
      }
    } catch (e) {
      Navigator.pop(context);
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('导入错误：$e'),
        ),
      );
    }
  }

  Future<void> _clearAllData() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空数据'),
        content: const Text('此操作将删除所有记录和设置，无法撤销。是否继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('确认清空'),
          ),
        ],
      ),
    );

    if (result != true) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
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
      await _databaseService.deleteAllRecords();
      await _databaseService.updateSettings({
        'deviceName': 'LBJReceiver',
        'backgroundServiceEnabled': 0,
        'notificationEnabled': 1,
        'mergeRecordsEnabled': 0,
        'groupBy': 'trainAndLoco',
        'timeWindow': 'unlimited',
      });

      Navigator.pop(context);

      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('数据已清空'),
        ),
      );

      await _loadSettings();
      await _loadRecordCount();
      setState(() {});
    } catch (e) {
      Navigator.pop(context);
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('清空错误：$e'),
        ),
      );
    }
  }

  Widget _buildAboutSection() {
    return Card(
      color: AppTheme.tertiaryBlack,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Text('关于', style: AppTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 16),
            Text('LBJ Console', style: AppTheme.titleMedium),
            const SizedBox(height: 8),
            FutureBuilder<String>(
              future: _getAppVersion(),
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  return Text(snapshot.data!, style: AppTheme.bodyMedium);
                } else {
                  return const Text('v0.1.3-flutter', style: AppTheme.bodyMedium);
                }
              },
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () async {
                final url = Uri.parse('https://github.com/undef-i/LBJConsole');
                if (await canLaunchUrl(url)) {
                  await launchUrl(url);
                }
              },
              child: Text(
                'https://github.com/undef-i/LBJConsole',
                style: AppTheme.caption,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
