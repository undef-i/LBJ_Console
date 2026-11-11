import 'package:flutter/material.dart';

import '../services/database_service.dart';
import '../ui/app_map.dart';
import '../ui/fl_list.dart';
import '../ui/glass_select.dart';
import '../ui/glass_switch.dart';

class RasterMapScreen extends StatefulWidget {
  const RasterMapScreen({super.key});

  @override
  State<RasterMapScreen> createState() => _RasterMapScreenState();
}

class _RasterMapScreenState extends State<RasterMapScreen> {
  final _baseUrlController = TextEditingController();
  final _railUrlController = TextEditingController();
  String _baseSource = 'osm';
  String _railSource = 'orm';
  bool _baseGcj = false;
  bool _railGcj = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _railUrlController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await DatabaseService.instance.getAllSettings();
    if (!mounted) return;
    setState(() {
      _baseSource = settings?['rasterBaseSource'] as String? ?? 'osm';
      _railSource = settings?['rasterRailSource'] as String? ?? 'orm';
      _baseUrlController.text = settings?['rasterBaseUrl'] as String? ?? '';
      _railUrlController.text = settings?['rasterRailUrl'] as String? ?? '';
      _baseGcj = (settings?['rasterBaseGcj'] as int? ?? 0) == 1;
      _railGcj = (settings?['rasterRailGcj'] as int? ?? 0) == 1;
      _loaded = true;
    });
  }

  Future<void> _save() async {
    await DatabaseService.instance.updateSettings({
      'rasterBaseSource': _baseSource,
      'rasterBaseUrl': _baseUrlController.text.trim(),
      'rasterRailSource': _railSource,
      'rasterRailUrl': _railUrlController.text.trim(),
      'rasterBaseGcj': _baseGcj ? 1 : 0,
      'rasterRailGcj': _railGcj ? 1 : 0,
    });
    final settings = await DatabaseService.instance.getAllSettings();
    RasterMapStore.instance.applySettings(settings);
  }

  Widget _gcjRow(bool value, String subtitle, ValueChanged<bool> onChanged) {
    return FlRow(
      title: const Text('GCJ-02 校准'),
      subtitle: Text(subtitle),
      trailing: GlassSwitch(value: value, onChanged: onChanged),
      onTap: () => onChanged(!value),
    );
  }

  Widget _urlRow(TextEditingController controller, String example) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('地址', style: flListTitleStyle(scheme)),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.url,
                  textAlign: TextAlign.end,
                  cursorWidth: 2,
                  onTapOutside: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  decoration: const InputDecoration.collapsed(hintText: null),
                  style: TextStyle(
                    fontSize: 17,
                    height: 22 / 17,
                    color: scheme.onSurface,
                  ),
                  onChanged: (_) => _save(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text('示例：$example', style: flCaptionStyle(scheme)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('flutter_map 管理')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                FlSection(
                  title: '底图',
                  rows: [
                    FlRow(
                      title: const Text('底图瓦片'),
                      trailing: GlassSelect<String>(
                        value: _baseSource,
                        items: [
                          for (final entry in rasterBasePresets.entries)
                            DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value.$1),
                            ),
                          const DropdownMenuItem(
                            value: 'custom',
                            child: Text('自定义'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _baseSource = value);
                          _save();
                        },
                      ),
                    ),
                    if (_baseSource == 'custom')
                      _urlRow(
                        _baseUrlController,
                        'https://example.com/{z}/{x}/{y}.png',
                      ),
                    if (_baseSource == 'custom')
                      _gcjRow(_baseGcj, '底图为 GCJ-02 时校准', (value) {
                        setState(() => _baseGcj = value);
                        _save();
                      }),
                  ],
                ),
                FlSection(
                  title: '铁路叠加层',
                  rows: [
                    FlRow(
                      title: const Text('铁路瓦片'),
                      trailing: GlassSelect<String>(
                        value: _railSource,
                        items: [
                          for (final entry in rasterRailPresets.entries)
                            DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value.$1),
                            ),
                          const DropdownMenuItem(
                            value: 'custom',
                            child: Text('自定义'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _railSource = value);
                          _save();
                        },
                      ),
                    ),
                    if (_railSource == 'custom')
                      _urlRow(
                        _railUrlController,
                        'https://example.com/{z}/{x}/{y}.png',
                      ),
                    if (_railSource == 'custom')
                      _gcjRow(_railGcj, '叠加层为 GCJ-02 时开启', (value) {
                        setState(() => _railGcj = value);
                        _save();
                      }),
                  ],
                ),
              ],
            ),
    );
  }
}
