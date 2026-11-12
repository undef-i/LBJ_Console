import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:io';

import 'package:lbjconsole/models/merged_record.dart';
import 'package:lbjconsole/screens/clear_data_screen.dart';
import 'package:lbjconsole/screens/klw_manage_screen.dart';
import 'package:lbjconsole/screens/raster_map_screen.dart';
import 'package:lbjconsole/screens/resource_screen.dart';
import 'package:lbjconsole/screens/licenses_screen.dart';
import 'package:lbjconsole/services/database_service.dart';
import 'package:lbjconsole/services/raw_log_service.dart';
import 'package:lbjconsole/services/demod_worker.dart';
import 'package:lbjconsole/screens/keep_alive_screen.dart';
import 'package:lbjconsole/services/audio_input_service.dart';
import 'package:lbjconsole/services/rtl_tcp_service.dart';
import 'package:lbjconsole/services/embedded_usb_service.dart';
import 'package:lbjconsole/themes/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:file_picker/file_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:lbjconsole/ui/app_map.dart';
import 'package:lbjconsole/ui/pmtiles_local.dart';
import 'package:lbjconsole/ui/fl_list.dart';
import 'package:lbjconsole/ui/glass_dialog.dart';
import 'package:lbjconsole/ui/glass_select.dart';
import 'package:lbjconsole/ui/glass_switch.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback? onSettingsChanged;
  final bool sampleRecordsEnabled;
  final ValueChanged<bool>? onSampleRecordsChanged;
  final int sampleIntervalSeconds;
  final ValueChanged<int>? onSampleIntervalChanged;
  final bool splitOnPreamble;
  final ValueChanged<bool>? onSplitOnPreambleChanged;

  const SettingsScreen({
    super.key,
    this.onSettingsChanged,
    this.sampleRecordsEnabled = false,
    this.onSampleRecordsChanged,
    this.sampleIntervalSeconds = 5,
    this.onSampleIntervalChanged,
    this.splitOnPreamble = false,
    this.onSplitOnPreambleChanged,
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
  bool _notificationsEnabled = true;
  bool _mergeRecordsEnabled = false;
  bool _hideTimeOnlyRecords = false;
  bool _hideUngroupableRecords = false;
  GroupBy _groupBy = GroupBy.trainAndLoco;
  TimeWindow _timeWindow = TimeWindow.unlimited;

  InputSource _inputSource = InputSource.bluetooth;
  MapEngine _mapEngine = MapEngine.native;

  String _rtlTcpHost = '127.0.0.1';
  String _rtlTcpPort = '14423';
  bool _debugMode = false;
  bool _protoLbj = true;
  bool _protoKlw = false;
  bool _protoTdcs = false;
  int _aboutTapCount = 0;
  Timer? _aboutTapTimer;
  bool _debugUnlocked = false;
  Future<String>? _exitFuture;
  Future<String>? _dbFuture;
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
        _notificationsEnabled = (settingsMap['notificationEnabled'] ?? 1) == 1;
        _mergeRecordsEnabled = settings.enabled;
        _hideTimeOnlyRecords = (settingsMap['hideTimeOnlyRecords'] ?? 0) == 1;
        _hideUngroupableRecords = settings.hideUngroupableRecords;
        _groupBy = settings.groupBy;
        _timeWindow = settings.timeWindow;

        _rtlTcpHost = settingsMap['rtlTcpHost']?.toString() ?? '127.0.0.1';
        _rtlTcpPort = settingsMap['rtlTcpPort']?.toString() ?? '14423';
        _debugMode = (settingsMap['debugMode'] ?? 0) == 1;
        _rtlTcpHostController.text = _rtlTcpHost;
        _rtlTcpPortController.text = _rtlTcpPort;

        final sourceStr = settingsMap['inputSource'] as String? ?? 'bluetooth';
        _inputSource = InputSource.values.firstWhere(
          (e) => e.name == sourceStr,
          orElse: () => InputSource.bluetooth,
        );
        _loadProtos(settingsMap);

        final engineStr = settingsMap['mapEngine'] as String? ?? 'vector';
        _mapEngine = MapEngine.values.firstWhere(
          (e) => e.name == engineStr,
          orElse: () => MapEngine.native,
        );

        _settingsLoaded = true;
      });
    }
  }

  String get _protoPrefix =>
      _inputSource == InputSource.usb ? 'protoUsb' : 'protoRtl';

  void _loadProtos(Map<String, dynamic> settingsMap) {
    _protoLbj = (settingsMap['${_protoPrefix}Lbj'] ?? 1) == 1;
    _protoKlw = (settingsMap['${_protoPrefix}Klw'] ?? 0) == 1;
    _protoTdcs = (settingsMap['${_protoPrefix}Tdcs'] ?? 0) == 1;
  }

  Future<void> _saveSettings() async {
    if (!_settingsLoaded) return;

    final values = <String, dynamic>{
      'deviceName': _deviceName,
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
    };
    if (_inputSource == InputSource.usb || _inputSource == InputSource.rtlTcp) {
      values['${_protoPrefix}Lbj'] = _protoLbj ? 1 : 0;
      values['${_protoPrefix}Klw'] = _protoKlw ? 1 : 0;
      values['${_protoPrefix}Tdcs'] = _protoTdcs ? 1 : 0;
    }
    await _databaseService.updateSettings(values);
    widget.onSettingsChanged?.call();
  }

  Future<void> _switchInputSource(InputSource newSource) async {
    await _saveSettings();
    await AudioInputService().stopListening();
    await EmbeddedUsbService.instance.deactivate();
    await RtlTcpService().disconnect();
    final settingsMap = await _databaseService.getAllSettings() ?? {};
    setState(() {
      _inputSource = newSource;
      _loadProtos(settingsMap);
    });

    switch (newSource) {
      case InputSource.audioInput:
        await AudioInputService().startListening();
        break;
      case InputSource.rtlTcp:
        RtlTcpService().connect(host: _rtlTcpHost, port: _rtlTcpPort);
        break;
      case InputSource.usb:
        await EmbeddedUsbService.instance.activate();
        break;
      case InputSource.bluetooth:
        break;
    }

    _saveSettings();
  }

  @override
  void dispose() {
    _aboutTapTimer?.cancel();
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
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          Text(title, style: flListTitleStyle(scheme)),
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

  Widget _toggleRow(String title, bool value, ValueChanged<bool> onChanged) {
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
                child: Text('rtl_tcp'),
              ),
              DropdownMenuItem(value: InputSource.usb, child: Text('USB 设备')),
              DropdownMenuItem(
                value: InputSource.audioInput,
                child: Text('音频设备'),
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
        ],
        if (_inputSource == InputSource.rtlTcp ||
            _inputSource == InputSource.usb) ...[
          _toggleRow('列车接近预警 (821.2375 MHz)', _protoLbj, (value) {
            if (!value && !_protoKlw && !_protoTdcs) return;
            setState(() {
              _protoLbj = value;
            });
            _saveSettings();
          }),
          _toggleRow('列尾与列车安全预警 (866.2375 MHz)', _protoKlw, (value) {
            if (!value && !_protoLbj && !_protoTdcs) return;
            setState(() {
              _protoKlw = value;
            });
            _saveSettings();
          }),
          _toggleRow('车次号校核 (457.550 MHz)', _protoTdcs, (value) {
            if (!value && !_protoLbj && !_protoKlw) return;
            setState(() {
              _protoTdcs = value;
            });
            _saveSettings();
          }),
        ],
        if (_inputSource == InputSource.usb)
          FlRow(
            leading: Icon(Icons.usb, color: scheme.onSurfaceVariant),
            title: const Text(
              '支持 ADALM-PLUTO、RTL2832U（R820T、R828D、E4000、FC0012、FC0013、FC2580）',
            ),
            titleStyle: TextStyle(
              fontSize: 13,
              height: 18 / 13,
              color: scheme.onSurfaceVariant,
            ),
          ),
        if (_inputSource == InputSource.rtlTcp)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: FlTonalButton(
              label: '重新连接',
              icon: Icons.refresh,
              height: 44,
              onPressed: () {
                RtlTcpService().connect(host: _rtlTcpHost, port: _rtlTcpPort);
              },
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.paddingOf(context).top + 80,
        16,
        118,
      ),
      children: [
        _buildInputSourceSettings(),
        _buildAppSettings(),
        _buildMergeSettings(),
        _buildDataManagement(),
        if (_debugUnlocked) _buildDebugSection(),
        _buildAboutSection(),
      ],
    );
  }

  Widget _buildAppSettings() {
    return FlSection(
      title: '应用设置',
      rows: [
        FlRow(
          title: const Text('后台运行管理'),
          trailing: Icon(
            Icons.arrow_forward_ios,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => const KeepAliveScreen(),
              ),
            );
          },
        ),
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
              DropdownMenuItem(
                value: MapEngine.raster,
                child: Text('flutter_map'),
              ),
              DropdownMenuItem(
                value: MapEngine.native,
                child: Text('MapLibre Native'),
              ),
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
        if (_mapEngine == MapEngine.raster)
          FlRow(
            title: const Text('flutter_map 管理'),
            trailing: Icon(
              Icons.arrow_forward_ios,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => const RasterMapScreen(),
                ),
              );
            },
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
                DropdownMenuItem(value: GroupBy.trainOnly, child: Text('仅车次号')),
                DropdownMenuItem(value: GroupBy.locoOnly, child: Text('仅机车号')),
                DropdownMenuItem(
                  value: GroupBy.trainOrLoco,
                  child: Text('车次号或机车号'),
                ),
                DropdownMenuItem(
                  value: GroupBy.trainAndLoco,
                  child: Text('车次号与机车号'),
                ),
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
                  value: TimeWindow.oneHour,
                  child: Text('1小时内'),
                ),
                DropdownMenuItem(
                  value: TimeWindow.twoHours,
                  child: Text('2小时内'),
                ),
                DropdownMenuItem(
                  value: TimeWindow.sixHours,
                  child: Text('6小时内'),
                ),
                DropdownMenuItem(
                  value: TimeWindow.twelveHours,
                  child: Text('12小时内'),
                ),
                DropdownMenuItem(
                  value: TimeWindow.oneDay,
                  child: Text('24小时内'),
                ),
                DropdownMenuItem(
                  value: TimeWindow.unlimited,
                  child: Text('不限时间'),
                ),
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
    Widget chevron() =>
        Icon(Icons.arrow_forward_ios, size: 18, color: scheme.onSurfaceVariant);
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
          leading: Icon(Icons.list, color: scheme.primary),
          title: const Text('KLW 数据管理'),
          subtitle: const Text('查看和删除 KLW 事件'),
          trailing: chevron(),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => const KlwManageScreen(),
              ),
            );
          },
        ),
        FlRow(
          leading: Icon(Icons.folder_open, color: scheme.primary),
          title: const Text('数据管理'),
          subtitle: const Text('数据表版本、更新与车次编排版本'),
          trailing: chevron(),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => const ResourceScreen(),
              ),
            );
          },
        ),
        FlRow(
          leading: Icon(Icons.clear_all, color: scheme.primary),
          title: const Text('清空数据'),
          trailing: chevron(),
          onTap: _openClearData,
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

  void _handleAboutTap() {
    _aboutTapTimer?.cancel();
    _aboutTapTimer = Timer(const Duration(seconds: 2), () {
      _aboutTapCount = 0;
    });

    _aboutTapCount += 1;
    if (_aboutTapCount < 5) return;

    _aboutTapCount = 0;
    _aboutTapTimer?.cancel();
    setState(() {
      _debugUnlocked = true;
      _exitFuture = _lastExitText();
      _dbFuture = _databaseService.diagnoseDatabase();
    });
  }

  static const _debugChannel = MethodChannel('lbj/debug');

  Future<String> _lastExitText() async {
    try {
      final info = await _debugChannel.invokeMapMethod<String, dynamic>(
        'lastExitInfo',
      );
      if (info == null) return '无记录';
      final reason = switch (info['reason'] as int? ?? 0) {
        2 => '被信号杀死',
        3 => '内存不足被杀',
        4 => '崩溃',
        5 => '原生崩溃',
        6 => '无响应 (ANR)',
        9 => '资源占用过高被杀',
        10 => '用户主动退出',
        11 => '被系统停止',
        _ => '其他 (代码 ${info['reason']})',
      };
      final ts = info['timestamp'] as int? ?? 0;
      final when = ts > 0
          ? DateTime.fromMillisecondsSinceEpoch(ts).toString().substring(0, 19)
          : '';
      final desc = (info['description'] as String? ?? '').trim();
      final trace = (info['trace'] as String? ?? '').trim();
      return [
        reason,
        when,
        if (desc.isNotEmpty) desc,
        if (trace.isNotEmpty)
          trace.length > 3000 ? trace.substring(0, 3000) : trace,
      ].join('\n');
    } catch (_) {
      return '读取失败';
    }
  }

  void _setDebugMode(bool value) {
    setState(() {
      _debugMode = value;
    });
    _databaseService.setSetting('debugMode', value ? 1 : 0);
  }

  void _setRawLog(bool value) {
    RawLogService.instance.enabled = value;
  }

  Future<void> _shareRawLog() async {
    final path = await RawLogService.instance.exportPath();
    await Share.shareXFiles([XFile(path)], subject: 'LBJ Console 原始日志');
  }

  Future<void> _shareIq() async {
    if (DemodWorker.instance.iqState.value.$1) {
      DemodWorker.instance.stopIqRecording();
      await Future.delayed(const Duration(milliseconds: 400));
    }
    final path = DemodWorker.instance.iqPath;
    if (path == null) return;
    final file = File(path);
    if (!await file.exists() || await file.length() == 0) return;
    await Share.shareXFiles([XFile(path)], subject: 'LBJ Console 原始 IQ');
  }

  Widget _buildDebugSection() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FlSection(
          title: '调试',
          rows: [
            FlRow(
              title: const Text('显示设备状态'),
              subtitle: const Text('连接弹窗显示状态'),
              trailing: GlassSwitch(
                value: _debugMode,
                onChanged: _setDebugMode,
              ),
              onTap: () => _setDebugMode(!_debugMode),
            ),
            FlRow(
              title: const Text('生成示例记录'),
              trailing: GlassSwitch(
                value: widget.sampleRecordsEnabled,
                onChanged: (value) =>
                    widget.onSampleRecordsChanged?.call(value),
              ),
              onTap: () => widget.onSampleRecordsChanged?.call(
                !widget.sampleRecordsEnabled,
              ),
            ),
            FlRow(
              title: const Text('生成间隔'),
              trailing: GlassSelect<int>(
                value: widget.sampleIntervalSeconds,
                items: const [
                  DropdownMenuItem(value: 1, child: Text('1 秒')),
                  DropdownMenuItem(value: 2, child: Text('2 秒')),
                  DropdownMenuItem(value: 5, child: Text('5 秒')),
                  DropdownMenuItem(value: 10, child: Text('10 秒')),
                  DropdownMenuItem(value: 30, child: Text('30 秒')),
                  DropdownMenuItem(value: 60, child: Text('60 秒')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    widget.onSampleIntervalChanged?.call(value);
                  }
                },
              ),
            ),
            FlRow(
              title: const Text('按前导码分组'),
              subtitle: const Text('开启后新前导码到达时结算上一组'),
              trailing: GlassSwitch(
                value: widget.splitOnPreamble,
                onChanged: (value) =>
                    widget.onSplitOnPreambleChanged?.call(value),
              ),
              onTap: () => widget.onSplitOnPreambleChanged?.call(
                !widget.splitOnPreamble,
              ),
            ),
            FlRow(
              title: const Text('记录原始日志'),
              subtitle: const Text('POCSAG 批次与 FFSK 原始帧'),
              trailing: GlassSwitch(
                value: RawLogService.instance.enabled,
                onChanged: (value) {
                  _setRawLog(value);
                  setState(() {});
                },
              ),
              onTap: () {
                _setRawLog(!RawLogService.instance.enabled);
                setState(() {});
              },
            ),
            FlRow(
              title: const Text('导出原始日志'),
              trailing: Icon(
                Icons.arrow_forward_ios,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
              onTap: _shareRawLog,
            ),
            ValueListenableBuilder<(bool, int)>(
              valueListenable: DemodWorker.instance.iqState,
              builder: (context, iq, _) {
                return FlRow(
                  title: const Text('记录原始 IQ'),
                  subtitle: iq.$1
                      ? Text(
                          '录制中 ${(iq.$2 / 1000000).toStringAsFixed(1)} MB',
                        )
                      : null,
                  trailing: GlassSwitch(
                    value: iq.$1,
                    onChanged: (value) {
                      if (value) {
                        DemodWorker.instance.startIqRecording();
                      } else {
                        DemodWorker.instance.stopIqRecording();
                      }
                    },
                  ),
                );
              },
            ),
            FlRow(
              title: const Text('导出原始 IQ'),
              trailing: Icon(
                Icons.arrow_forward_ios,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
              onTap: _shareIq,
            ),
            FlRow(
              title: const Text('瓦片请求日志'),
              trailing: Icon(
                Icons.arrow_forward_ios,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
              onTap: _showTileLog,
            ),
            FlRow(
              title: const Text('上次退出'),
              subtitle: FutureBuilder<String>(
                future: _exitFuture,
                builder: (context, snapshot) =>
                    Text(snapshot.data ?? '读取中'),
              ),
            ),
            FlRow(
              title: const Text('数据库状态'),
              subtitle: FutureBuilder<String>(
                future: _dbFuture,
                builder: (context, snapshot) =>
                    Text(snapshot.data ?? '读取中'),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: StreamBuilder<void>(
            stream: RawLogService.instance.changes,
            builder: (context, _) {
              final all = RawLogService.instance.lines;
              final tail = all.length > 8 ? all.sublist(all.length - 8) : all;
              return Text(
                tail.isEmpty ? '暂无日志' : tail.join('\n'),
                style: AppTheme.caption.copyWith(fontFamily: 'monospace'),
              );
            },
          ),
        ),
      ],
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
            const SnackBar(content: Text('分享失败：无法生成数据文件')),
          );
        }
      } catch (e) {
        if (!mounted) return;
        Navigator.pop(context);
        scaffoldMessenger.showSnackBar(SnackBar(content: Text('分享错误：$e')));
      }
    } catch (e) {
      scaffoldMessenger.showSnackBar(SnackBar(content: Text('分享错误：$e')));
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
        scaffoldMessenger.showSnackBar(const SnackBar(content: Text('数据导入成功')));

        await _loadSettings();
        setState(() {});
      } else {
        scaffoldMessenger.showSnackBar(const SnackBar(content: Text('数据导入失败')));
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      scaffoldMessenger.showSnackBar(SnackBar(content: Text('导入错误：$e')));
    }
  }

  Future<void> _openClearData() async {
    final cleared = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (context) => const ClearDataScreen()),
    );
    if (cleared != true || !mounted) return;
    await _loadSettings();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('数据已清空')));
  }

  void _showTileLog() {
    final lines = PmtilesTileServer.requestLog;
    showGlassDialog(
      context: context,
      builder: (context) => GlassDialog(
        title: const Text('瓦片请求日志'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              lines.isEmpty ? '暂无记录' : lines.join('\n'),
              style: const TextStyle(fontSize: 11, height: 1.5),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutSection() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _handleAboutTap,
            child: Text('关于', style: flCaptionStyle(scheme)),
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
                final url = Uri.parse('https://github.com/undef-i/LBJConsole');
                if (await canLaunchUrl(url)) {
                  await launchUrl(url);
                }
              },
            ),
            FlRow(
              title: const Text('开放源代码许可'),
              trailing: Icon(
                Icons.arrow_forward_ios,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => const LicensesScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}
