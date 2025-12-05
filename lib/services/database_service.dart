import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:lbjconsole/models/train_record.dart';

enum InputSource {
  bluetooth,
  rtlTcp,
  audioInput
}

class DatabaseService {
  static final DatabaseService instance = DatabaseService._internal();
  factory DatabaseService() => instance;
  DatabaseService._internal();

  static const String _databaseName = 'train_database';
  static const _databaseVersion = 9;

  static const String trainRecordsTable = 'train_records';
  static const String appSettingsTable = 'app_settings';

  Database? _database;

  Future<Database> get database async {
    try {
      if (_database != null) {
        return _database!;
      }
      _database = await _initDatabase();
      return _database!;
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> isDatabaseConnected() async {
    try {
      if (_database == null) {
        return false;
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<Database> _initDatabase() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final path = join(directory.path, _databaseName);

      final db = await openDatabase(
        path,
        version: _databaseVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );

      return db;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    developer.log('Database upgrading from $oldVersion to $newVersion', name: 'Database');

    if (oldVersion < 2) {
      await db.execute(
          'ALTER TABLE $appSettingsTable ADD COLUMN hideTimeOnlyRecords INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 3) {
      await db.execute(
          'ALTER TABLE $appSettingsTable ADD COLUMN mapTimeFilter TEXT NOT NULL DEFAULT "unlimited"');
    }
    if (oldVersion < 4) {
      try {
        await db.execute(
            'ALTER TABLE $appSettingsTable ADD COLUMN mapTimeFilter TEXT NOT NULL DEFAULT "unlimited"');
      } catch (e) {}
    }
    if (oldVersion < 5) {
      await db.execute(
          'ALTER TABLE $appSettingsTable ADD COLUMN mapType TEXT NOT NULL DEFAULT "webview"');
    }
    if (oldVersion < 6) {
      await db.execute(
          'ALTER TABLE $appSettingsTable ADD COLUMN hideUngroupableRecords INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 7) {
      await db.execute(
          'ALTER TABLE $appSettingsTable ADD COLUMN mapSettingsTimestamp INTEGER');
    }
    if (oldVersion < 8) {
      await db.execute(
          'ALTER TABLE $appSettingsTable ADD COLUMN rtlTcpEnabled INTEGER NOT NULL DEFAULT 0');
      await db.execute(
          'ALTER TABLE $appSettingsTable ADD COLUMN rtlTcpHost TEXT NOT NULL DEFAULT "127.0.0.1"');
      await db.execute(
          'ALTER TABLE $appSettingsTable ADD COLUMN rtlTcpPort TEXT NOT NULL DEFAULT "14423"');
    }
    if (oldVersion < 9) {
      await db.execute(
          'ALTER TABLE $appSettingsTable ADD COLUMN inputSource TEXT NOT NULL DEFAULT "bluetooth"');
      
      try {
        final List<Map<String, dynamic>> results = await db.query(appSettingsTable, columns: ['rtlTcpEnabled'], where: 'id = 1');
        if (results.isNotEmpty) {
          final int rtlTcpEnabled = results.first['rtlTcpEnabled'] as int? ?? 0;
          if (rtlTcpEnabled == 1) {
            await db.update(
              appSettingsTable, 
              {'inputSource': 'rtlTcp'},
              where: 'id = 1'
            );
            developer.log('Migrated V8 settings: inputSource set to rtlTcp', name: 'Database');
          }
        }
      } catch (e) {
        developer.log('Migration V8->V9 data update failed: $e', name: 'Database');
      }
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $trainRecordsTable (
        uniqueId TEXT PRIMARY KEY,
        timestamp INTEGER NOT NULL,
        receivedTimestamp INTEGER NOT NULL,
        train TEXT NOT NULL,
        direction INTEGER NOT NULL,
        speed TEXT NOT NULL,
        position TEXT NOT NULL,
        time TEXT NOT NULL,
        loco TEXT NOT NULL,
        locoType TEXT NOT NULL,
        lbjClass TEXT NOT NULL,
        route TEXT NOT NULL,
        positionInfo TEXT NOT NULL,
        rssi REAL NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $appSettingsTable (
        id INTEGER PRIMARY KEY,
        deviceName TEXT NOT NULL DEFAULT 'LBJReceiver',
        currentTab INTEGER NOT NULL DEFAULT 0,
        historyEditMode INTEGER NOT NULL DEFAULT 0,
        historySelectedRecords TEXT NOT NULL DEFAULT '',
        historyExpandedStates TEXT NOT NULL DEFAULT '',
        historyScrollPosition INTEGER NOT NULL DEFAULT 0,
        historyScrollOffset INTEGER NOT NULL DEFAULT 0,
        settingsScrollPosition INTEGER NOT NULL DEFAULT 0,
        mapCenterLat REAL,
        mapCenterLon REAL,
        mapZoomLevel REAL NOT NULL DEFAULT 10.0,
        mapRailwayLayerVisible INTEGER NOT NULL DEFAULT 1,
        mapRotation REAL NOT NULL DEFAULT 0.0,
        mapType TEXT NOT NULL DEFAULT 'webview',
        specifiedDeviceAddress TEXT,
        searchOrderList TEXT NOT NULL DEFAULT '',
        autoConnectEnabled INTEGER NOT NULL DEFAULT 1,
        backgroundServiceEnabled INTEGER NOT NULL DEFAULT 0,
        notificationEnabled INTEGER NOT NULL DEFAULT 0,
        mergeRecordsEnabled INTEGER NOT NULL DEFAULT 0,
        hideTimeOnlyRecords INTEGER NOT NULL DEFAULT 0,
        groupBy TEXT NOT NULL DEFAULT 'trainAndLoco',
        timeWindow TEXT NOT NULL DEFAULT 'unlimited',
        mapTimeFilter TEXT NOT NULL DEFAULT 'unlimited',
        hideUngroupableRecords INTEGER NOT NULL DEFAULT 0,
        mapSettingsTimestamp INTEGER,
        rtlTcpEnabled INTEGER NOT NULL DEFAULT 0,
        rtlTcpHost TEXT NOT NULL DEFAULT '127.0.0.1',
        rtlTcpPort TEXT NOT NULL DEFAULT '14423',
        inputSource TEXT NOT NULL DEFAULT 'bluetooth'
      )
    ''');

    await db.insert(appSettingsTable, {
      'id': 1,
      'deviceName': 'LBJReceiver',
      'currentTab': 0,
      'historyEditMode': 0,
      'historySelectedRecords': '',
      'historyExpandedStates': '',
      'historyScrollPosition': 0,
      'historyScrollOffset': 0,
      'settingsScrollPosition': 0,
      'mapZoomLevel': 10.0,
      'mapRailwayLayerVisible': 1,
      'mapRotation': 0.0,
      'mapType': 'webview',
      'searchOrderList': '',
      'autoConnectEnabled': 1,
      'backgroundServiceEnabled': 0,
      'notificationEnabled': 0,
      'mergeRecordsEnabled': 0,
      'hideTimeOnlyRecords': 0,
      'groupBy': 'trainAndLoco',
      'timeWindow': 'unlimited',
      'mapTimeFilter': 'unlimited',
      'hideUngroupableRecords': 0,
      'mapSettingsTimestamp': null,
      'rtlTcpEnabled': 0,
      'rtlTcpHost': '127.0.0.1',
      'rtlTcpPort': '14423',
      'inputSource': 'bluetooth',
    });
  }

  Future<int> insertRecord(TrainRecord record) async {
    final db = await database;
    return await db.insert(
      trainRecordsTable,
      record.toDatabaseJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<TrainRecord>> getAllRecords() async {
    try {
      final db = await database;
      final result = await db.query(
        trainRecordsTable,
        orderBy: 'timestamp DESC',
      );
      final records =
          result.map((json) => TrainRecord.fromDatabaseJson(json)).toList();
      return records;
    } catch (e) {
      rethrow;
    }
  }

  Future<List<TrainRecord>> getRecordsWithinTimeRange(Duration duration) async {
    final db = await database;
    final cutoffTime = DateTime.now().subtract(duration).millisecondsSinceEpoch;
    final result = await db.query(
      trainRecordsTable,
      where: 'timestamp >= ?',
      whereArgs: [cutoffTime],
      orderBy: 'timestamp DESC',
    );
    return result.map((json) => TrainRecord.fromDatabaseJson(json)).toList();
  }

  Future<List<TrainRecord>> getRecordsWithinReceivedTimeRange(
      Duration duration) async {
    try {
      final db = await database;
      final cutoffTime =
          DateTime.now().subtract(duration).millisecondsSinceEpoch;

      final result = await db.query(
        trainRecordsTable,
        where: 'receivedTimestamp >= ?',
        whereArgs: [cutoffTime],
        orderBy: 'receivedTimestamp DESC',
      );
      final records =
          result.map((json) => TrainRecord.fromDatabaseJson(json)).toList();
      return records;
    } catch (e) {
      rethrow;
    }
  }

  Future<int> deleteRecord(String uniqueId) async {
    final db = await database;
    final result = await db.delete(
      trainRecordsTable,
      where: 'uniqueId = ?',
      whereArgs: [uniqueId],
    );

    if (result > 0) {
      _notifyRecordDeleted([uniqueId]);
    }

    return result;
  }

  Future<int> deleteAllRecords() async {
    final db = await database;
    final result = await db.delete(trainRecordsTable);

    if (result > 0) {
      _notifyRecordDeleted([]);
    }

    return result;
  }

  Future<int> getRecordCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM $trainRecordsTable');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<TrainRecord?> getLatestRecord() async {
    final db = await database;
    final result = await db.query(
      trainRecordsTable,
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    if (result.isNotEmpty) {
      return TrainRecord.fromDatabaseJson(result.first);
    }
    return null;
  }

  Future<Map<String, dynamic>?> getAllSettings() async {
    final db = await database;
    try {
      final result = await db.query(
        appSettingsTable,
        where: 'id = 1',
      );
      if (result.isEmpty) return null;
      return result.first;
    } catch (e) {
      return null;
    }
  }

  Future<int> updateSettings(Map<String, dynamic> settings) async {
    final db = await database;
    final result = await db.update(
      appSettingsTable,
      settings,
      where: 'id = 1',
    );
    if (result > 0) {
      _notifySettingsChanged(settings);
    }
    return result;
  }

  Future<int> setSetting(String key, dynamic value) async {
    final db = await database;
    final result = await db.update(
      appSettingsTable,
      {key: value},
      where: 'id = 1',
    );
    if (result > 0) {
      final currentSettings = await getAllSettings();
      if (currentSettings != null) {
        _notifySettingsChanged(currentSettings);
      }
    }
    return result;
  }

  Future<List<String>> getSearchOrderList() async {
    final settings = await getAllSettings();
    if (settings != null && settings['searchOrderList'] != null) {
      final listString = settings['searchOrderList'] as String;
      if (listString.isNotEmpty) {
        return listString.split(',');
      }
    }
    return [];
  }

  Future<int> updateSearchOrderList(List<String> orderList) async {
    return await setSetting('searchOrderList', orderList.join(','));
  }

  Future<Map<String, dynamic>> getDatabaseInfo() async {
    final db = await database;
    final count = await getRecordCount();
    final settings = await getAllSettings();
    return {
      'databaseVersion': _databaseVersion,
      'trainRecordCount': count,
      'appSettings': settings,
      'path': db.path,
    };
  }

  Future<String?> backupDatabase() async {
    try {
      final db = await database;
      final directory = await getApplicationDocumentsDirectory();
      final originalPath = db.path;
      final backupDirectory = Directory(join(directory.path, 'backups'));
      if (!await backupDirectory.exists()) {
        await backupDirectory.create(recursive: true);
      }
      final backupPath = join(backupDirectory.path,
          'train_database_backup_${DateTime.now().millisecondsSinceEpoch}.db');
      await File(originalPath).copy(backupPath);
      return backupPath;
    } catch (e) {
      return null;
    }
  }

  Future<void> deleteRecords(List<String> uniqueIds) async {
    final db = await database;
    for (String id in uniqueIds) {
      await db.delete(
        'train_records',
        where: 'uniqueId = ?',
        whereArgs: [id],
      );
    }
    _notifyRecordDeleted(uniqueIds);
  }

  final List<Function(List<String>)> _recordDeleteListeners = [];

  final List<Function(Map<String, dynamic>)> _settingsListeners = [];

  StreamSubscription<void> onRecordDeleted(Function(List<String>) listener) {
    _recordDeleteListeners.add(listener);
    return Stream.value(null).listen((_) {})
      ..onData((_) {})
      ..onDone(() {
        _recordDeleteListeners.remove(listener);
      });
  }

  void _notifyRecordDeleted(List<String> deletedIds) {
    for (final listener in _recordDeleteListeners) {
      listener(deletedIds);
    }
  }

  StreamSubscription<void> onSettingsChanged(
      Function(Map<String, dynamic>) listener) {
    _settingsListeners.add(listener);
    return _SettingsListenerSubscription(() {
      _settingsListeners.remove(listener);
    });
  }

  void _notifySettingsChanged(Map<String, dynamic> settings) {
    print('[Database] Notifying ${_settingsListeners.length} settings listeners');
    for (final listener in _settingsListeners) {
      listener(settings);
    }
  }

  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  Future<String?> exportDataAsJson({String? customPath}) async {
    try {
      final records = await getAllRecords();

      final exportData = {
        'records': records.map((r) => r.toDatabaseJson()).toList(),
      };

      final jsonString = jsonEncode(exportData);

      String filePath;
      if (customPath != null) {
        filePath = customPath;
      } else {
        final tempDir = Directory.systemTemp;
        final fileName =
            'LBJ_Console_${DateTime.now().year}${DateTime.now().month.toString().padLeft(2, '0')}${DateTime.now().day.toString().padLeft(2, '0')}.json';
        filePath = join(tempDir.path, fileName);
      }

      await File(filePath).writeAsString(jsonString);
      return filePath;
    } catch (e) {
      return null;
    }
  }

  Future<bool> importDataFromJson(String filePath) async {
    try {
      final jsonString = await File(filePath).readAsString();
      final importData = jsonDecode(jsonString);

      final db = await database;

      await db.transaction((txn) async {
        await txn.delete(trainRecordsTable);

        if (importData['records'] != null) {
          final records =
              List<Map<String, dynamic>>.from(importData['records']);
          for (final record in records) {
            await txn.insert(trainRecordsTable, record);
          }
        }
      });

      final currentSettings = await getAllSettings();
      if (currentSettings != null) {
        _notifySettingsChanged(currentSettings);
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteExportFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }
}

class _SettingsListenerSubscription implements StreamSubscription<void> {
  final void Function() _onCancel;
  bool _isCanceled = false;

  _SettingsListenerSubscription(this._onCancel);

  @override
  Future<void> cancel() async {
    if (!_isCanceled) {
      _isCanceled = true;
      _onCancel();
    }
  }

  @override
  void onData(void Function(void data)? handleData) {}

  @override
  void onDone(void Function()? handleDone) {}

  @override
  void onError(Function? handleError) {}

  @override
  void pause([Future<void>? resumeSignal]) {}

  @override
  void resume() {}

  @override
  bool get isPaused => false;

  @override
  Future<E> asFuture<E>([E? futureValue]) => Future.value(futureValue);
}