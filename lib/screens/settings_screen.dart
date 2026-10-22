import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';

import 'package:lbjconsole/models/merged_record.dart';
import 'package:lbjconsole/services/database_service.dart';
import 'package:lbjconsole/services/background_service.dart';
import 'package:lbjconsole/services/audio_input_service.dart';
import 'package:lbjconsole/services/rtl_tcp_service.dart';
import 'package:lbjconsole/themes/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:file_picker/file_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:lbjconsole/ui/app_map.dart';
import 'package:lbjconsole/ui/fl_list.dart';
import 'package:lbjconsole/ui/glass_dialog.dart';
import 'package:lbjconsole/ui/glass_styles.dart';
import 'package:lbjconsole/ui/glass_select.dart';
import 'package:lbjconsole/ui/glass_switch.dart';
import 'package:lbjconsole/ui/glass_clipper.dart';
import 'package:lbjconsole/ui/liquid_glass.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback? onSettingsChanged;
  final bool temporaryRecordsEnabled;
  final ValueChanged<bool>? onTemporaryRecordsChanged;

  const SettingsScreen({
    super.key,
    this.onSettingsChanged,
    this.temporaryRecordsEnabled = false,
    this.onTemporaryRecordsChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {


  late DatabaseService _databaseService;
  late TextEditingController _deviceNameController;
  late TextEditingController _rtlTcpHostController;
  late TextEditingController _rtlTcpPortController;

  bool _settingsLoaded = false;

  String _deviceName = '';
  bool _backgroundServiceEnabled = false;
  bool _notificationsEnabled = true;
  bool _mergeRecordsEnabled = false;
  bool _hideTimeOnlyRecords = false;
  bool _hideUngroupableRecords = false;
  GroupBy _groupBy = GroupBy.trainAndLoco;
  TimeWindow _timeWindow = TimeWindow.unlimited;

  InputSource _inputSource = InputSource.bluetooth;
  MapEngine _mapEngine = MapEngine.vector;

  String _rtlTcpHost = '127.0.0.1';
  String _rtlTcpPort = '14423';
  int _aboutIconTapCount = 0;
  Timer? _aboutIconTapTimer;
  late final Future<String> _appVersion;

  @override
  void initState() {
    super.initState();
    _appVersion = _getAppVersion();
    _databaseService = DatabaseService.instance;
    _deviceNameController = TextEditingController();
    _rtlTcpHostController = TextEditingController();
    _rtlTcpPortController = TextEditingController();
    _loadSettings();
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
        _hideTimeOnlyRecords = (settingsMap['hideTimeOnlyRecords'] ?? 0) == 1;
        _hideUngroupableRecords = settings.hideUngroupableRecords;
        _groupBy = settings.groupBy;
        _timeWindow = settings.timeWindow;

        _rtlTcpHost = settingsMap['rtlTcpHost']?.toString() ?? '127.0.0.1';
        _rtlTcpPort = settingsMap['rtlTcpPort']?.toString() ?? '14423';
        _rtlTcpHostController.text = _rtlTcpHost;
        _rtlTcpPortController.text = _rtlTcpPort;

        final sourceStr = settingsMap['inputSource'] as String? ?? 'bluetooth';
        _inputSource = InputSource.values.firstWhere(
          (e) => e.name == sourceStr,
          orElse: () => InputSource.bluetooth,
        );

        final engineStr = settingsMap['mapEngine'] as String? ?? 'vector';
        _mapEngine = MapEngine.values.firstWhere(
          (e) => e.name == engineStr,
          orElse: () => MapEngine.vector,
        );

        _settingsLoaded = true;
      });
    }
  }

  Future<void> _saveSettings() async {
    if (!_settingsLoaded) return;

    await _databaseService.updateSettings({
      'deviceName': _deviceName,
      'backgroundServiceEnabled': _backgroundServiceEnabled ? 1 : 0,
      'notificationEnabled': _notificationsEnabled ? 1 : 0,
      'mergeRecordsEnabled': _mergeRecordsEnabled ? 1 : 0,
      'hideTimeOnlyRecords': _hideTimeOnlyRecords ? 1 : 0,
      'hideUngroupableRecords': _hideUngroupableRecords ? 1 : 0,
      'groupBy': _groupBy.name,
      'timeWindow': _timeWindow.name,
      'inputSource': _inputSource.name,
      'mapEngine': _mapEngine.name,
      'rtlTcpHost': _rtlTcpHost,
      'rtlTcpPort': _rtlTcpPort,
    });
    widget.onSettingsChanged?.call();
  }

  Future<void> _switchInputSource(InputSource newSource) async {
    await AudioInputService().stopListening();
    await RtlTcpService().disconnect();
    setState(() {
      _inputSource = newSource;
    });

    switch (newSource) {
      case InputSource.audioInput:
        await AudioInputService().startListening();
        break;
      case InputSource.rtlTcp:
        RtlTcpService().connect(host: _rtlTcpHost, port: _rtlTcpPort);
        break;
      case InputSource.bluetooth:
        break;
    }

    _saveSettings();
  }

  @override
  void dispose() {
    _aboutIconTapTimer?.cancel();
    _deviceNameController.dispose();
    _rtlTcpHostController.dispose();
    _rtlTcpPortController.dispose();
    super.dispose();
  }

  Widget _formRow({
    required String title,
    required TextEditingController controller,
    String? hint,
    TextInputType? keyboardType,
    required ValueChanged<String> onChanged,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.fromLTRB(16, 10, 2, 10),
      child: Row(
        children: [
          Flexible(
            child: Text(title, style: flListTitleStyle(scheme)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: TextField(
                controller: controller,
                keyboardType: keyboardType,
                textAlign: TextAlign.end,
                cursorWidth: 2,
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                decoration: InputDecoration.collapsed(
                  hintText: hint,
                  hintStyle: TextStyle(
                    fontSize: 17,
                    height: 22 / 17,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                style: TextStyle(
                  fontSize: 17,
                  height: 22 / 17,
                  color: scheme.onSurface,
                ),
                onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggleRow(
    String title,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return FlRow(
      title: Text(title),
      trailing: GlassSwitch(value: value, onChanged: onChanged),
      onTap: () => onChanged(!value),
    );
  }

  Widget _buildInputSourceSettings() {
    final scheme = Theme.of(context).colorScheme;
    return FlSection(
      title: '信号源设置',
      rows: [
        FlRow(
          title: const Text('信号源'),
          trailing: GlassSelect<InputSource>(
            value: _inputSource,
            items: const [
              DropdownMenuItem(
                value: InputSource.bluetooth,
                child: Text('蓝牙设备'),
              ),
              DropdownMenuItem(
                value: InputSource.rtlTcp,
                child: Text('RTL-TCP'),
              ),
              DropdownMenuItem(
                value: InputSource.audioInput,
                child: Text('音频输入'),
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                _switchInputSource(value);
              }
            },
          ),
        ),
        if (_inputSource == InputSource.bluetooth)
          _formRow(
            title: '蓝牙设备名称',
            controller: _deviceNameController,
            hint: '输入设备名称',
            onChanged: (value) {
              setState(() {
                _deviceName = value;
              });
              _saveSettings();
            },
          ),
        if (_inputSource == InputSource.rtlTcp) ...[
          _formRow(
            title: '服务器地址',
            controller: _rtlTcpHostController,
            hint: '127.0.0.1',
            onChanged: (value) {
              setState(() {
                _rtlTcpHost = value;
              });
              _saveSettings();
            },
          ),
          _formRow(
            title: '服务器端口',
            controller: _rtlTcpPortController,
            hint: '14423',
            keyboardType: TextInputType.number,
            onChanged: (value) {
              setState(() {
                _rtlTcpPort = value;
              });
              _saveSettings();
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: FlTonalButton(
              label: '重新连接 RTL-TCP',
              icon: Icons.refresh,
              height: 44,
              onPressed: () {
                RtlTcpService().connect(host: _rtlTcpHost, port: _rtlTcpPort);
              },
            ),
          ),
        ],
        if (_inputSource == InputSource.audioInput)
          FlRow(
            leading: Icon(Icons.mic, color: scheme.onSurfaceVariant),
            title: const Text('音频解调已启用。请通过音频线 (Line-in) 或麦克风输入信号。'),
            titleStyle: TextStyle(
              fontSize: 13,
              height: 18 / 13,
              color: scheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
          16, MediaQuery.paddingOf(context).top + 80, 16, 118),
      children: [
        _buildInputSourceSettings(),
        _buildAppSettings(),
        _buildMergeSettings(),
        _buildDataManagement(),
        _buildAboutSection(),
      ],
    );
  }

  Widget _buildAppSettings() {
    return FlSection(
      title: '应用设置',
      rows: [
        _toggleRow('后台保活服务', _backgroundServiceEnabled, (value) async {
          setState(() {
            _backgroundServiceEnabled = value;
          });
          await _saveSettings();
          if (value) {
            await BackgroundService.startService();
          } else {
            await BackgroundService.stopService();
          }
        }),
        _toggleRow('通知服务', _notificationsEnabled, (value) {
          setState(() {
            _notificationsEnabled = value;
          });
          _saveSettings();
        }),
        _toggleRow('隐藏只有时间有效的记录', _hideTimeOnlyRecords, (value) {
          setState(() {
            _hideTimeOnlyRecords = value;
          });
          _saveSettings();
        }),
        FlRow(
          title: const Text('地图'),
          trailing: GlassSelect<MapEngine>(
            value: _mapEngine,
            items: const [
              DropdownMenuItem(value: MapEngine.vector, child: Text('矢量')),
              DropdownMenuItem(value: MapEngine.raster, child: Text('位图')),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _mapEngine = value;
                });
                MapEngineStore.instance.value = value;
                _saveSettings();
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMergeSettings() {
    return FlSection(
      title: '记录合并',
      rows: [
        _toggleRow('启用记录合并', _mergeRecordsEnabled, (value) {
          setState(() {
            _mergeRecordsEnabled = value;
          });
          _saveSettings();
        }),
        if (_mergeRecordsEnabled) ...[
          FlRow(
            title: const Text('分组方式'),
            trailing: GlassSelect<GroupBy>(
              value: _groupBy,
              items: const [
                DropdownMenuItem(
                    value: GroupBy.trainOnly, child: Text('仅车次号')),
                DropdownMenuItem(
                    value: GroupBy.locoOnly, child: Text('仅机车号')),
                DropdownMenuItem(
                    value: GroupBy.trainOrLoco, child: Text('车次号或机车号')),
                DropdownMenuItem(
                    value: GroupBy.trainAndLoco, child: Text('车次号与机车号')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _groupBy = value;
                  });
                  _saveSettings();
                }
              },
            ),
          ),
          FlRow(
            title: const Text('时间窗口'),
            trailing: GlassSelect<TimeWindow>(
              value: _timeWindow,
              items: const [
                DropdownMenuItem(
                    value: TimeWindow.oneHour, child: Text('1小时内')),
                DropdownMenuItem(
                    value: TimeWindow.twoHours, child: Text('2小时内')),
                DropdownMenuItem(
                    value: TimeWindow.sixHours, child: Text('6小时内')),
                DropdownMenuItem(
                    value: TimeWindow.twelveHours, child: Text('12小时内')),
                DropdownMenuItem(
                    value: TimeWindow.oneDay, child: Text('24小时内')),
                DropdownMenuItem(
                    value: TimeWindow.unlimited, child: Text('不限时间')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _timeWindow = value;
                  });
                  _saveSettings();
                }
              },
            ),
          ),
          _toggleRow('隐藏不可分组记录', _hideUngroupableRecords, (value) {
            setState(() {
              _hideUngroupableRecords = value;
            });
            _saveSettings();
          }),
        ],
      ],
    );
  }

  Widget _buildDataManagement() {
    final scheme = Theme.of(context).colorScheme;
    final destructive = scheme.brightness == Brightness.dark
        ? const Color(0xFFFF4245)
        : const Color(0xFFFF383C);
    Widget chevron() => Icon(
          Icons.arrow_forward_ios,
          size: 18,
          color: scheme.onSurfaceVariant,
        );
    return FlSection(
      title: '数据管理',
      rows: [
        FlRow(
          leading: Icon(Icons.share, color: scheme.primary),
          title: const Text('分享数据'),
          subtitle: const Text('将记录分享为 JSON 文件'),
          trailing: chevron(),
          onTap: _shareData,
        ),
        FlRow(
          leading: Icon(Icons.file_download, color: scheme.primary),
          title: const Text('导入数据'),
          subtitle: const Text('从 JSON 文件导入记录和设置'),
          trailing: chevron(),
          onTap: _importData,
        ),
        FlRow(
          leading: Icon(Icons.clear_all, color: destructive),
          title: Text('清空数据', style: TextStyle(color: destructive)),
          subtitle: const Text('删除所有记录和设置'),
          trailing: chevron(),
          onTap: _clearAllData,
        ),
      ],
    );
  }

  Future<String> _getAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return 'v${packageInfo.version}+${packageInfo.buildNumber}';
    } catch (e) {
      return '';
    }
  }

  void _handleAboutIconTap() {
    _aboutIconTapTimer?.cancel();
    _aboutIconTapTimer = Timer(const Duration(seconds: 2), () {
      _aboutIconTapCount = 0;
    });

    _aboutIconTapCount += 1;
    if (_aboutIconTapCount < 5) return;

    _aboutIconTapCount = 0;
    _aboutIconTapTimer?.cancel();
    _showTemporaryRecordsPanel();
  }

  void _showTemporaryRecordsPanel() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      enableDrag: true,
      isDismissible: true,
      builder: (context) {
        bool enabled = widget.temporaryRecordsEnabled;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Stack(
              children: [
                Positioned.fill(
                  child: LiquidGlass(
                    style: glassMenuStyle(Theme.of(context).colorScheme),
                    clipper: const SuperellipseClipper(
                      BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
                SafeArea(
                  child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.science,
                            color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 12),
                        const Text('临时测试', style: AppTheme.titleMedium),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('生成临时列车记录', style: AppTheme.bodyLarge),
                              SizedBox(height: 2),
                              Text('每 5 秒新增一条真实记录，包含随机移动坐标',
                                  style: AppTheme.caption),
                            ],
                          ),
                        ),
                        GlassSwitch(
                          value: enabled,
                          onChanged: (value) {
                            setSheetState(() {
                              enabled = value;
                            });
                            widget.onTemporaryRecordsChanged?.call(value);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('关闭'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _shareData() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      showGlassDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const GlassDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('正在准备分享数据...'),
            ],
          ),
        ),
      );

      try {
        final exportedPath = await _databaseService.exportDataAsJson();
        if (!mounted) return;
        Navigator.pop(context);

        if (exportedPath != null) {
          final file = File(exportedPath);

          await Share.shareXFiles(
            [XFile(file.path)],
            subject: 'LBJ Console Data',
            text: '',
          );
        } else {
          scaffoldMessenger.showSnackBar(
            const SnackBar(
              content: Text('分享失败：无法生成数据文件'),
            ),
          );
        }
      } catch (e) {
        if (!mounted) return;
        Navigator.pop(context);
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('分享错误：$e'),
          ),
        );
      }
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('分享错误：$e'),
        ),
      );
    }
  }

  Future<void> _importData() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    final result = await showGlassDialog<bool>(
      context: context,
      builder: (context) => GlassDialog(
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
    if (!mounted) return;

    showGlassDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const GlassDialog(
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
      if (!mounted) return;
      Navigator.pop(context);

      if (success) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('数据导入成功'),
          ),
        );

        await _loadSettings();
        setState(() {});
      } else {
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('数据导入失败'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
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

    final result = await showGlassDialog<bool>(
      context: context,
      builder: (context) => GlassDialog(
        title: const Text('清空数据'),
        content: const Text('此操作将删除所有记录和设置，无法撤销。是否继续？'),
        destructive: true,
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

    if (result != true) return;
    if (!mounted) return;

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
      await _databaseService.deleteAllRecords();
      await _databaseService.updateSettings({
        'deviceName': 'LBJReceiver',
        'backgroundServiceEnabled': 0,
        'notificationEnabled': 1,
        'mergeRecordsEnabled': 0,
        'groupBy': 'trainAndLoco',
        'timeWindow': 'unlimited',
        'inputSource': 'bluetooth',
      });

      if (!mounted) return;
      Navigator.pop(context);

      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('数据已清空'),
        ),
      );

      await _loadSettings();
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('清空错误：$e'),
        ),
      );
    }
  }

  Widget _buildAboutSection() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Row(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _handleAboutIconTap,
                child: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Icon(Icons.info, color: scheme.primary, size: 20),
                ),
              ),
              const SizedBox(width: 8),
              Text('关于', style: flCaptionStyle(scheme)),
            ],
          ),
        ),
        FlSection(
          rows: [
            FlRow(
              title: const Text('LBJ Console'),
              titleStyle: TextStyle(
                fontSize: 22,
                height: 28 / 22,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
              subtitle: FutureBuilder<String>(
                future: _appVersion,
                builder: (context, snapshot) {
                  return Text(snapshot.data ?? '');
                },
              ),
            ),
            FlRow(
              title: const Text('项目仓库'),
              subtitle: Text(
                'github.com/undef-i/LBJConsole',
                style: flCaptionStyle(scheme),
              ),
              trailing: Icon(
                Icons.arrow_forward_ios,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
              onTap: () async {
                final url =
                    Uri.parse('https://github.com/undef-i/LBJConsole');
                if (await canLaunchUrl(url)) {
                  await launchUrl(url);
                }
              },
            ),
          ],
        ),
      ],
    );
  }
}
