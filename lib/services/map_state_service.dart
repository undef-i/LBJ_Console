import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:lbjconsole/models/map_state.dart';
import 'database_service.dart';

class MapStateService {
  static final MapStateService instance = MapStateService._internal();
  factory MapStateService() => instance;
  MapStateService._internal();

  static const String _tableName = 'record_map_states';
  
  final Map<String, MapState> _memoryCache = {};

  Future<void> _ensureTableExists() async {
    final db = await DatabaseService.instance.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableName (
        key TEXT PRIMARY KEY,
        state TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
  }

  String getSingleRecordMapKey(String recordId) {
    return "${recordId}_record_map";
  }

  String getMergedRecordMapKey(String groupKey) {
    return "${groupKey}_group_map";
  }

  Future<void> saveMapState(String key, MapState state) async {
    try {
      _memoryCache[key] = state;
      
      final db = await DatabaseService.instance.database;
      await _ensureTableExists();
      
      await db.insert(
        _tableName,
        {
          'key': key,
          'state': jsonEncode(state.toJson()),
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      print('保存地图状态失败: $e');
    }
  }

  Future<MapState?> getMapState(String key) async {
    if (_memoryCache.containsKey(key)) {
      return _memoryCache[key];
    }

    try {
      final db = await DatabaseService.instance.database;
      await _ensureTableExists();
      
      final result = await db.query(
        _tableName,
        where: 'key = ?',
        whereArgs: [key],
        limit: 1,
      );

      if (result.isNotEmpty) {
        final stateJson = jsonDecode(result.first['state'] as String);
        final state = MapState.fromJson(stateJson);
        _memoryCache[key] = state;
        return state;
      }
    } catch (e) {
      print('读取地图状态失败: $e');
    }
    
    return null;
  }

  Future<void> deleteMapState(String key) async {
    _memoryCache.remove(key);
    
    try {
      final db = await DatabaseService.instance.database;
      await db.delete(
        _tableName,
        where: 'key = ?',
        whereArgs: [key],
      );
    } catch (e) {
      print('删除地图状态失败: $e');
    }
  }

  Future<void> clearAllMapStates() async {
    _memoryCache.clear();
    
    try {
      final db = await DatabaseService.instance.database;
      await db.delete(_tableName);
    } catch (e) {
      print('清空地图状态失败: $e');
    }
  }

  void clearMemoryCache() {
    _memoryCache.clear();
  }
}