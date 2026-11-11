import 'package:flutter/material.dart';
import 'package:lbjconsole/models/klw_event.dart';
import 'package:lbjconsole/services/database_service.dart';
import 'package:lbjconsole/ui/glass_dialog.dart';

class KlwManageScreen extends StatefulWidget {
  const KlwManageScreen({super.key});

  @override
  State<KlwManageScreen> createState() => _KlwManageScreenState();
}

class _KlwManageScreenState extends State<KlwManageScreen> {
  Map<String, List<KlwEvent>> _groups = {};
  bool _loading = true;
  bool _selecting = false;
  final Set<String> _expanded = {};
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final events = await DatabaseService.instance.getKlwEvents();
    if (!mounted) return;
    setState(() {
      _groups = KlwState.groupByLoco(events);
      _loading = false;
    });
  }

  void _exitSelecting() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  void _toggleEvent(KlwEvent event) {
    setState(() {
      if (!_selected.remove(event.uniqueId)) {
        _selected.add(event.uniqueId);
      }
    });
  }

  void _toggleGroup(List<KlwEvent> events) {
    final allSelected =
        events.every((event) => _selected.contains(event.uniqueId));
    setState(() {
      for (final event in events) {
        if (allSelected) {
          _selected.remove(event.uniqueId);
        } else {
          _selected.add(event.uniqueId);
        }
      }
    });
  }

  void _toggleExpanded(String key) {
    setState(() {
      if (!_expanded.remove(key)) {
        _expanded.add(key);
      }
    });
  }

  Future<void> _deleteSelected() async {
    final count = _selected.length;
    final confirmed = await showGlassDialog<bool>(
      context: context,
      builder: (context) => GlassDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除选中的 $count 条 KLW 事件吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await DatabaseService.instance.deleteKlwEvents(_selected.toList());
    if (!mounted) return;
    setState(() {
      _selecting = false;
      _selected.clear();
      _loading = true;
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        leading: _selecting
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _exitSelecting,
              )
            : null,
        title: Text(_selecting ? '已选择 ${_selected.length} 条' : 'KLW 数据管理'),
        titleTextStyle: theme.textTheme.titleLarge?.copyWith(
          color: dark ? Colors.white : null,
        ),
        iconTheme: IconThemeData(color: dark ? Colors.white : null),
        actions: [
          if (_selecting)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _selected.isEmpty ? null : _deleteSelected,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _groups.isEmpty
              ? const Center(child: Text('暂无 KLW 事件'))
              : ListView(
                  children: [
                    for (final entry in _groups.entries)
                      _buildGroup(entry.key, entry.value),
                  ],
                ),
    );
  }

  Widget _buildGroup(String key, List<KlwEvent> events) {
    final colorScheme = Theme.of(context).colorScheme;
    final expanded = _expanded.contains(key);
    final selectedCount =
        events.where((event) => _selected.contains(event.uniqueId)).length;
    final loco = events.first.locoDisplay;
    return Column(
      children: [
        ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          minVerticalPadding: 4,
          selected: _selecting && selectedCount == events.length,
          selectedTileColor: colorScheme.primary.withValues(alpha: 0.14),
          tileColor: _selecting && selectedCount > 0
              ? colorScheme.primary.withValues(alpha: 0.07)
              : null,
          title: Text(
            loco.isEmpty ? '机车号未知' : loco,
            style: const TextStyle(fontSize: 14),
          ),
          subtitle: Text(
            _selecting && selectedCount > 0
                ? '已选 $selectedCount 条，共 ${events.length} 条'
                : '共 ${events.length} 条',
            style: const TextStyle(fontSize: 12),
          ),
          trailing: IconButton(
            icon: Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              color: colorScheme.onSurfaceVariant,
            ),
            onPressed: () => _toggleExpanded(key),
          ),
          onTap: () {
            if (_selecting) {
              _toggleGroup(events);
            } else {
              _toggleExpanded(key);
            }
          },
          onLongPress: _selecting
              ? null
              : () => setState(() {
                    _selecting = true;
                    for (final event in events) {
                      _selected.add(event.uniqueId);
                    }
                  }),
        ),
        if (expanded)
          for (final event in events) _buildEventRow(event),
        const Divider(height: 1),
      ],
    );
  }

  Widget _buildEventRow(KlwEvent event) {
    final colorScheme = Theme.of(context).colorScheme;
    final checked = _selected.contains(event.uniqueId);
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      minVerticalPadding: 2,
      contentPadding: const EdgeInsets.only(left: 32, right: 16),
      selected: _selecting && checked,
      selectedTileColor: colorScheme.primary.withValues(alpha: 0.14),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(event.timestamp.toString().substring(0, 19),
              style: const TextStyle(fontSize: 12)),
          Text('KLW ${event.tailNumber}',
              style: TextStyle(fontSize: 12, color: colorScheme.onSurface)),
        ],
      ),
      subtitle: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(event.commandName,
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis),
          ),
          Text(
            event.pressureKpa != null
                ? '${event.pressureKpa} kPa'
                : event.paramDisplay,
            style: const TextStyle(fontSize: 13),
            textAlign: TextAlign.right,
          ),
        ],
      ),
      onTap: _selecting ? () => _toggleEvent(event) : null,
      onLongPress: _selecting
          ? null
          : () => setState(() {
                _selecting = true;
                _selected.add(event.uniqueId);
              }),
    );
  }
}
