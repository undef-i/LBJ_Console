import 'package:flutter/material.dart';
import 'package:lbjconsole/services/demod_worker.dart';
import 'package:lbjconsole/services/resource_service.dart';
import 'package:lbjconsole/ui/fl_list.dart';
import 'package:lbjconsole/util/loco_info_util.dart';
import 'package:lbjconsole/util/train_type_util.dart';

class ResourceScreen extends StatefulWidget {
  const ResourceScreen({super.key});

  @override
  State<ResourceScreen> createState() => _ResourceScreenState();
}

class _ResourceScreenState extends State<ResourceScreen> {
  static const _ids = ['loco_info', 'loco_type_info'];
  bool _loaded = false;
  String? _updating;

  @override
  void initState() {
    super.initState();
    ResourceService.initialize().then((_) {
      if (!mounted) return;
      setState(() => _loaded = true);
    });
  }

  Future<void> _reload(String id) async {
    if (id == 'loco_info') await LocoInfoUtil.reload();
    if (id == 'loco_type_info') await DemodWorker.instance.refreshLocoTypes();
  }

  void _show(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _update(String id) async {
    setState(() => _updating = id);
    final manifest = await ResourceService.fetchManifest();
    ResourceEntry? entry;
    if (manifest != null) {
      for (final e in manifest) {
        if (e.id == id) entry = e;
      }
    }
    if (entry == null) {
      if (!mounted) return;
      setState(() => _updating = null);
      _show('更新失败');
      return;
    }
    final current = ResourceService.currentVersion(id);
    if (current != null && entry.version.compareTo(current) <= 0) {
      if (!mounted) return;
      setState(() => _updating = null);
      _show('已是最新版本');
      return;
    }
    try {
      await ResourceService.download(entry);
      await _reload(id);
    } on Exception {
      if (!mounted) return;
      setState(() => _updating = null);
      _show('更新失败');
      return;
    }
    if (!mounted) return;
    setState(() => _updating = null);
    _show('已更新到 ${entry.version} 版');
  }

  Widget _trainRow(String version, String title, String subtitle) {
    final scheme = Theme.of(context).colorScheme;
    final active = TrainTypeUtil.activeVersion == version;
    return FlRow(
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: active
          ? Icon(Icons.check, color: scheme.onSurface)
          : const SizedBox(width: 24),
      onTap: () async {
        if (active) return;
        await TrainTypeUtil.setVersion(version);
        if (!mounted) return;
        setState(() {});
      },
    );
  }

  Widget _resourceRow(String id) {
    final version = ResourceService.currentVersion(id);
    final busy = _updating == id;
    return FlRow(
      title: Text(ResourceService.resourceNames[id]!),
      subtitle: Text(version == null ? '暂无数据' : '版本 $version'),
      trailing: FlTonalButton(
        label: '更新',
        busy: busy,
        onPressed: () => _update(id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('数据管理')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                FlSection(
                  title: '车次编排',
                  rows: [
                    _trainRow('auto', '自动', '按记录的接收时间选择'),
                    _trainRow('2014', '2014 版', '2026 年 11 月 25 日前'),
                    _trainRow(
                      '2026-1',
                      '2026 版（第一批）',
                      '2026 年 11 月 25 日至 12 月下旬',
                    ),
                    _trainRow('2026', '2026 版', '2026 年 12 月下旬起'),
                  ],
                ),
                FlSection(
                  title: '数据资源',
                  rows: [for (final id in _ids) _resourceRow(id)],
                ),
              ],
            ),
    );
  }
}
