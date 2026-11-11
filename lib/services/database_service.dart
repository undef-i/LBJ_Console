import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';

import 'package:lbjconsole/models/train_record.dart';
import 'package:lbjconsole/models/klw_event.dart';
import 'package:lbjconsole/models/ffsk_alarm_event.dart';
import 'package:lbjconsole/models/sync_event.dart';
import 'package:lbjconsole/util/app_log.dart';

enum InputSource { bluetooth, rtlTcp, audioInput, usb }

class DatabaseService {
  static final DatabaseService instance = DatabaseService._internal();
  factory DatabaseService() => instance;
  DatabaseService._internal();

  static const String _databaseName = 'train_database';
  static const _databaseVersion = 19;

  static const String trainRecordsTable = 'train_records';
  static const String appSettingsTable = 'app_settings';
  static const String klwEventsTable = 'klw_events';
  static const String alarmEventsTable = 'ffsk_alarm_events';
  static const String syncEventsTable = 'lbj_sync_events';

  Database? _database;

  Future<Database> get database async {
    try {
      if (_database != null) {
        final path = _database!.path;
        if (path == ':memory:' || await File(path).exists()) {
          return _database!;
        }
        try {
          await _database!.close();
        } catch (_) {}
        _database = null;
      }
      _database = await _initDatabase();
      return _database!;
    } catch (e) {
      rethrow;
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
        onDowngrade: (db, oldVersion, newVersion) async {
          throw StateError(
            'database downgrade $oldVersion -> $newVersion refused',
          );
        },
        onOpen: (db) async {
          await _ensureIndexes(db);
          try {
            await _ensureTdcsKlwSchema(db);
          } catch (e) {
            AppLog.warn('database', 'schema self-heal failed: $e');
          }
        },
      );

      return db;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    AppLog.info('database', 'upgrade $oldVersion -> $newVersion');

    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE $appSettingsTable ADD COLUMN hideTimeOnlyRecords INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 3) {
      await db.execute(
        'ALTER TABLE $appSettingsTable ADD COLUMN mapTimeFilter TEXT NOT NULL DEFAULT "unlimited"',
      );
    }
    if (oldVersion < 4) {
      try {
        await db.execute(
          'ALTER TABLE $appSettingsTable ADD COLUMN mapTimeFilter TEXT NOT NULL DEFAULT "unlimited"',
        );
        // ignore: empty_catches
      } catch (e) {}
    }
    if (oldVersion < 5) {
      await db.execute(
        'ALTER TABLE $appSettingsTable ADD COLUMN mapType TEXT NOT NULL DEFAULT "map"',
      );
    }
    if (oldVersion < 6) {
      await db.execute(
        'ALTER TABLE $appSettingsTable ADD COLUMN hideUngroupableRecords INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 7) {
      await db.execute(
        'ALTER TABLE $appSettingsTable ADD COLUMN mapSettingsTimestamp INTEGER',
      );
    }
    if (oldVersion < 8) {
      await db.execute(
        'ALTER TABLE $appSettingsTable ADD COLUMN rtlTcpEnabled INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE $appSettingsTable ADD COLUMN rtlTcpHost TEXT NOT NULL DEFAULT "127.0.0.1"',
      );
      await db.execute(
        'ALTER TABLE $appSettingsTable ADD COLUMN rtlTcpPort TEXT NOT NULL DEFAULT "14423"',
      );
    }
    if (oldVersion < 9) {
      await db.execute(
        'ALTER TABLE $appSettingsTable ADD COLUMN inputSource TEXT NOT NULL DEFAULT "bluetooth"',
      );

      try {
        final List<Map<String, dynamic>> results = await db.query(
          appSettingsTable,
          columns: ['rtlTcpEnabled'],
          where: 'id = 1',
        );
        if (results.isNotEmpty) {
          final int rtlTcpEnabled = results.first['rtlTcpEnabled'] as int? ?? 0;
          if (rtlTcpEnabled == 1) {
            await db.update(appSettingsTable, {
              'inputSource': 'rtlTcp',
            }, where: 'id = 1');
            AppLog.info('database', 'migrated input source to rtl-tcp');
          }
        }
      } catch (e) {
        AppLog.warn('database', 'migration v9 data update failed: $e');
      }
    }
    if (oldVersion < 10) {
      await _ensureIndexes(db);
    }
    if (oldVersion < 11) {
      await db.execute(
        'ALTER TABLE $appSettingsTable ADD COLUMN mapEngine TEXT NOT NULL DEFAULT "native"',
      );
    }
    if (oldVersion < 12) {
      if (!await _hasColumn(db, 'usbDeviceType')) {
        await db.execute(
          'ALTER TABLE $appSettingsTable ADD COLUMN usbDeviceType TEXT NOT NULL DEFAULT "rtl"',
        );
      }
      if (!await _hasColumn(db, 'usbStarted')) {
        await db.execute(
          'ALTER TABLE $appSettingsTable ADD COLUMN usbStarted INTEGER NOT NULL DEFAULT 1',
        );
      }
    }
    if (oldVersion < 13) {
      if (await _hasColumn(db, 'usbDeviceType')) {
        await db.execute(
          'ALTER TABLE $appSettingsTable DROP COLUMN usbDeviceType',
        );
      }
    }
    if (oldVersion < 14) {
      if (await _hasColumn(db, 'usbStarted')) {
        await db.execute(
          'ALTER TABLE $appSettingsTable DROP COLUMN usbStarted',
        );
      }
    }
    if (oldVersion < 15) {
      if (!await _hasColumn(db, 'debugMode')) {
        await db.execute(
          'ALTER TABLE $appSettingsTable ADD COLUMN debugMode INTEGER NOT NULL DEFAULT 0',
        );
      }
    }
    if (oldVersion < 16) {
      try {
        await _ensureTdcsKlwSchema(db);
      } catch (e) {
        AppLog.warn('database', 'migration v16 failed: $e');
      }
    }
    if (oldVersion < 17) {
      if (!await _hasColumn(db, 'rasterBaseSource')) {
        await db.execute(
          'ALTER TABLE $appSettingsTable ADD COLUMN rasterBaseSource TEXT NOT NULL DEFAULT "osm"',
        );
      }
      if (!await _hasColumn(db, 'rasterBaseUrl')) {
        await db.execute(
          'ALTER TABLE $appSettingsTable ADD COLUMN rasterBaseUrl TEXT NOT NULL DEFAULT ""',
        );
      }
      if (!await _hasColumn(db, 'rasterRailSource')) {
        await db.execute(
          'ALTER TABLE $appSettingsTable ADD COLUMN rasterRailSource TEXT NOT NULL DEFAULT "orm"',
        );
      }
      if (!await _hasColumn(db, 'rasterRailUrl')) {
        await db.execute(
          'ALTER TABLE $appSettingsTable ADD COLUMN rasterRailUrl TEXT NOT NULL DEFAULT ""',
        );
      }
      if (!await _hasColumn(db, 'rasterGcj')) {
        await db.execute(
          'ALTER TABLE $appSettingsTable ADD COLUMN rasterGcj INTEGER NOT NULL DEFAULT 0',
        );
      }
    }
    if (oldVersion < 18) {
      if (!await _hasColumn(db, 'rasterBaseGcj')) {
        await db.execute(
          'ALTER TABLE $appSettingsTable ADD COLUMN rasterBaseGcj INTEGER NOT NULL DEFAULT 0',
        );
      }
      if (!await _hasColumn(db, 'rasterRailGcj')) {
        await db.execute(
          'ALTER TABLE $appSettingsTable ADD COLUMN rasterRailGcj INTEGER NOT NULL DEFAULT 0',
        );
      }
      if (await _hasColumn(db, 'rasterGcj')) {
        await db.execute(
          'UPDATE $appSettingsTable SET rasterBaseGcj = rasterGcj',
        );
      }
    }
    if (oldVersion < 19) {
      const added = {
        'protoUsbLbj': 1,
        'protoUsbKlw': 0,
        'protoUsbTdcs': 0,
        'protoRtlLbj': 1,
        'protoRtlKlw': 0,
        'protoRtlTdcs': 0,
        'sampleRecordsEnabled': 0,
      };
      for (final entry in added.entries) {
        if (!await _hasColumn(db, entry.key)) {
          await db.execute(
            'ALTER TABLE $appSettingsTable ADD COLUMN ${entry.key} INTEGER NOT NULL DEFAULT ${entry.value}',
          );
        }
      }
    }
  }

  Future<void> _ensureTdcsKlwSchema(Database db) async {
    try {
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final names = tables.map((row) => row['name'] as String).toSet();
      if (names.contains('cir_alarm_events') &&
          !names.contains(alarmEventsTable)) {
        await db.execute(
          'ALTER TABLE cir_alarm_events RENAME TO $alarmEventsTable',
        );
      }
    } catch (e) {
      AppLog.warn('database', 'rename alarm events table failed: $e');
    }
    try {
      await _createKlwEventsTable(db, klwEventsTable);
    } catch (e) {
      AppLog.warn('database', 'create klw events table failed: $e');
    }
    try {
      await _createAlarmEventsTable(db, alarmEventsTable);
    } catch (e) {
      AppLog.warn('database', 'create alarm events table failed: $e');
    }
    try {
      await _createSyncEventsTable(db, syncEventsTable);
    } catch (e) {
      AppLog.warn('database', 'create sync events table failed: $e');
    }
    try {
      await _migrateStorageTables(db);
    } catch (e) {
      AppLog.warn('database', 'storage migration failed: $e');
    }
  }

  Future<void> _migrateStorageTables(Database db) async {
    if (await _hasColumnIn(db, trainRecordsTable, 'lbjClass')) {
      final rows = await db.query(trainRecordsTable);
      const temp = '${trainRecordsTable}_new';
      await db.execute('DROP TABLE IF EXISTS $temp');
      await _createTrainRecordsTable(db, temp);
      final batch = db.batch();
      for (final row in rows) {
        batch.insert(
          temp,
          TrainRecord.fromDatabaseJson(row).toDatabaseJson(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
      await db.execute('DROP TABLE $trainRecordsTable');
      await db.execute('ALTER TABLE $temp RENAME TO $trainRecordsTable');
      await _ensureIndexes(db);
    }
    if (await _hasColumnIn(db, klwEventsTable, 'loco')) {
      final rows = await db.query(klwEventsTable);
      const temp = '${klwEventsTable}_new';
      await db.execute('DROP TABLE IF EXISTS $temp');
      await _createKlwEventsTable(db, temp);
      final batch = db.batch();
      for (final row in rows) {
        batch.insert(
          temp,
          KlwEvent.fromDatabaseJson(row).toDatabaseJson(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
      await db.execute('DROP TABLE $klwEventsTable');
      await db.execute('ALTER TABLE $temp RENAME TO $klwEventsTable');
      await _createKlwEventsTable(db, klwEventsTable);
    }
    if (await _hasColumnIn(db, alarmEventsTable, 'loco')) {
      final rows = await db.query(alarmEventsTable);
      const temp = '${alarmEventsTable}_new';
      await db.execute('DROP TABLE IF EXISTS $temp');
      await _createAlarmEventsTable(db, temp);
      final batch = db.batch();
      for (final row in rows) {
        batch.insert(
          temp,
          FfskAlarmEvent.fromDatabaseJson(row).toDatabaseJson(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
      await db.execute('DROP TABLE $alarmEventsTable');
      await db.execute('ALTER TABLE $temp RENAME TO $alarmEventsTable');
      await _createAlarmEventsTable(db, alarmEventsTable);
    }
    if (await _hasColumnIn(db, syncEventsTable, 'id')) {
      final rows = await db.query(syncEventsTable);
      const temp = '${syncEventsTable}_new';
      await db.execute('DROP TABLE IF EXISTS $temp');
      await _createSyncEventsTable(db, temp);
      final batch = db.batch();
      for (final row in rows) {
        batch.insert(
          temp,
          LbjSyncEvent.fromDatabaseJson(row).toDatabaseJson(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
      await db.execute('DROP TABLE $syncEventsTable');
      await db.execute('ALTER TABLE $temp RENAME TO $syncEventsTable');
      await _createSyncEventsTable(db, syncEventsTable);
    }
  }

  Future<void> _createTrainRecordsTable(Database db, String table) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $table (
        uniqueId TEXT PRIMARY KEY,
        timestamp INTEGER NOT NULL,
        receivedTimestamp INTEGER NOT NULL,
        trainNumber TEXT NOT NULL DEFAULT '',
        directionCode INTEGER NOT NULL DEFAULT 0,
        speedKmh TEXT NOT NULL DEFAULT '',
        kilometerMark TEXT NOT NULL DEFAULT '',
        rawLocoNumber TEXT NOT NULL DEFAULT '',
        parsedLocoNumber TEXT NOT NULL DEFAULT '',
        route TEXT NOT NULL DEFAULT '',
        latitude REAL,
        longitude REAL,
        rssi REAL NOT NULL DEFAULT 0,
        source TEXT NOT NULL DEFAULT 'lbj',
        weightTonnes TEXT NOT NULL DEFAULT '',
        lengthMeters TEXT NOT NULL DEFAULT '',
        carCount TEXT NOT NULL DEFAULT '',
        stationNumber TEXT NOT NULL DEFAULT '',
        segmentNumber TEXT NOT NULL DEFAULT '',
        actualSegmentNumber TEXT NOT NULL DEFAULT '',
        driverNumber TEXT NOT NULL DEFAULT '',
        signalState TEXT NOT NULL DEFAULT '',
        signalType TEXT NOT NULL DEFAULT '',
        trainRole TEXT NOT NULL DEFAULT ''
      )
    ''');
  }

  Future<void> _createSyncEventsTable(Database db, String table) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $table (
        uniqueId TEXT PRIMARY KEY,
        timestamp INTEGER NOT NULL,
        receivedTimestamp INTEGER NOT NULL,
        timeText TEXT NOT NULL DEFAULT ''
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_${table}_received_timestamp ON $table(receivedTimestamp DESC)',
    );
  }

  Future<bool> _hasColumn(Database db, String column) async {
    return _hasColumnIn(db, appSettingsTable, column);
  }

  Future<bool> _hasColumnIn(Database db, String table, String column) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.any((row) => row['name'] == column);
  }

  Future<void> _createKlwEventsTable(Database db, String table) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $table (
        uniqueId TEXT PRIMARY KEY,
        timestamp INTEGER NOT NULL,
        receivedTimestamp INTEGER NOT NULL,
        rawLocoNumber TEXT NOT NULL DEFAULT '',
        tailNumber TEXT NOT NULL DEFAULT '',
        commandCode INTEGER NOT NULL DEFAULT 0,
        parameter TEXT NOT NULL DEFAULT '',
        pressureKpa INTEGER
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_${table}_received_timestamp ON $table(receivedTimestamp DESC)',
    );
  }

  Future<void> _createAlarmEventsTable(Database db, String table) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $table (
        uniqueId TEXT PRIMARY KEY,
        timestamp INTEGER NOT NULL,
        receivedTimestamp INTEGER NOT NULL,
        functionCode INTEGER NOT NULL DEFAULT 0,
        trainNumber TEXT NOT NULL DEFAULT '',
        rawLocoNumber TEXT NOT NULL DEFAULT '',
        kilometer REAL,
        detail TEXT NOT NULL DEFAULT '',
        lineName TEXT NOT NULL DEFAULT ''
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_${table}_received_timestamp ON $table(receivedTimestamp DESC)',
    );
  }

  Future<void> _ensureIndexes(Database db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_train_records_timestamp ON $trainRecordsTable(timestamp DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_train_records_received_timestamp ON $trainRecordsTable(receivedTimestamp DESC)',
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createTrainRecordsTable(db, trainRecordsTable);

    await _ensureTdcsKlwSchema(db);

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
        mapType TEXT NOT NULL DEFAULT 'map',
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
        inputSource TEXT NOT NULL DEFAULT 'bluetooth',
        mapEngine TEXT NOT NULL DEFAULT 'native',
        rasterBaseSource TEXT NOT NULL DEFAULT 'osm',
        rasterBaseUrl TEXT NOT NULL DEFAULT '',
        rasterBaseGcj INTEGER NOT NULL DEFAULT 0,
        rasterRailSource TEXT NOT NULL DEFAULT 'orm',
        rasterRailUrl TEXT NOT NULL DEFAULT '',
        rasterRailGcj INTEGER NOT NULL DEFAULT 0,
        debugMode INTEGER NOT NULL DEFAULT 0,
        protoUsbLbj INTEGER NOT NULL DEFAULT 1,
        protoUsbKlw INTEGER NOT NULL DEFAULT 0,
        protoUsbTdcs INTEGER NOT NULL DEFAULT 0,
        protoRtlLbj INTEGER NOT NULL DEFAULT 1,
        protoRtlKlw INTEGER NOT NULL DEFAULT 0,
        protoRtlTdcs INTEGER NOT NULL DEFAULT 0,
        sampleRecordsEnabled INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await _ensureIndexes(db);

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
      'mapType': 'map',
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
    final result = await db.insert(
      trainRecordsTable,
      record.toDatabaseJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _notifyDataInserted();
    return result;
  }

  Future<int> insertKlwEvent(KlwEvent event) async {
    try {
      final db = await database;
      final result = await db.insert(
        klwEventsTable,
        event.toDatabaseJson(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      _notifyDataInserted();
      return result;
    } catch (e) {
      AppLog.warn('database', 'insert klw event failed: $e');
      return 0;
    }
  }

  Future<List<KlwEvent>> getKlwEvents() async {
    try {
      final db = await database;
      final result = await db.query(
        klwEventsTable,
        orderBy: 'receivedTimestamp DESC',
      );
      return result.map((json) => KlwEvent.fromDatabaseJson(json)).toList();
    } catch (e) {
      AppLog.warn('database', 'read klw events failed: $e');
      return [];
    }
  }

  Future<int> insertAlarmEvent(FfskAlarmEvent event) async {
    try {
      final db = await database;
      final result = await db.insert(
        alarmEventsTable,
        event.toDatabaseJson(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      _notifyDataInserted();
      return result;
    } catch (e) {
      AppLog.warn('database', 'insert alarm event failed: $e');
      return 0;
    }
  }

  Future<List<FfskAlarmEvent>> getAlarmEvents() async {
    try {
      final db = await database;
      final result = await db.query(
        alarmEventsTable,
        orderBy: 'receivedTimestamp DESC',
      );
      return result
          .map((json) => FfskAlarmEvent.fromDatabaseJson(json))
          .toList();
    } catch (e) {
      AppLog.warn('database', 'read alarm events failed: $e');
      return [];
    }
  }

  Future<int> insertSyncEvent(LbjSyncEvent event) async {
    try {
      final db = await database;
      final result = await db.insert(
        syncEventsTable,
        event.toDatabaseJson(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      _notifyDataInserted();
      return result;
    } catch (e) {
      AppLog.warn('database', 'insert sync event failed: $e');
      return 0;
    }
  }

  Future<List<LbjSyncEvent>> getSyncEvents() async {
    try {
      final db = await database;
      final result = await db.query(
        syncEventsTable,
        orderBy: 'receivedTimestamp DESC',
      );
      return result.map((json) => LbjSyncEvent.fromDatabaseJson(json)).toList();
    } catch (e) {
      AppLog.warn('database', 'read sync events failed: $e');
      return [];
    }
  }

  Future<List<TrainRecord>> getAllRecords() async {
    try {
      final db = await database;
      final result = await db.query(
        trainRecordsTable,
        orderBy: 'timestamp DESC',
      );
      final records = result
          .map((json) => TrainRecord.fromDatabaseJson(json))
          .toList();
      return records;
    } catch (e) {
      rethrow;
    }
  }

  Future<List<TrainRecord>> getRecordsWithinReceivedTimeRange(
    Duration duration,
  ) async {
    try {
      final db = await database;
      final cutoffTime = DateTime.now()
          .subtract(duration)
          .millisecondsSinceEpoch;

      final result = await db.query(
        trainRecordsTable,
        where: 'receivedTimestamp >= ?',
        whereArgs: [cutoffTime],
        orderBy: 'receivedTimestamp DESC',
      );
      final records = result
          .map((json) => TrainRecord.fromDatabaseJson(json))
          .toList();
      return records;
    } catch (e) {
      rethrow;
    }
  }

  Future<int> _deleteEventsByIds(String table, List<String> ids) async {
    if (ids.isEmpty) {
      return 0;
    }
    final db = await database;
    var deleted = 0;
    try {
      await db.transaction((txn) async {
        const chunkSize = 999;
        for (var start = 0; start < ids.length; start += chunkSize) {
          final end = (start + chunkSize > ids.length)
              ? ids.length
              : start + chunkSize;
          final chunk = ids.sublist(start, end);
          final placeholders = List.filled(chunk.length, '?').join(',');
          deleted += await txn.delete(
            table,
            where: 'uniqueId IN ($placeholders)',
            whereArgs: chunk,
          );
        }
      });
    } catch (e) {
      AppLog.warn('database', 'delete events from $table failed: $e');
      return 0;
    }
    if (deleted > 0) {
      _notifyRecordDeleted(const []);
    }
    return deleted;
  }

  Future<int> deleteAlarmEvents(List<String> ids) =>
      _deleteEventsByIds(alarmEventsTable, ids);

  Future<int> deleteSyncEvents(List<String> ids) =>
      _deleteEventsByIds(syncEventsTable, ids);

  Future<int> deleteKlwEvents(List<String> ids) async {
    if (ids.isEmpty) {
      return 0;
    }
    final db = await database;
    var deleted = 0;
    try {
      await db.transaction((txn) async {
        const chunkSize = 999;
        for (var start = 0; start < ids.length; start += chunkSize) {
          final end = (start + chunkSize > ids.length)
              ? ids.length
              : start + chunkSize;
          final chunk = ids.sublist(start, end);
          final placeholders = List.filled(chunk.length, '?').join(',');
          deleted += await txn.delete(
            klwEventsTable,
            where: 'uniqueId IN ($placeholders)',
            whereArgs: chunk,
          );
        }
      });
    } catch (e) {
      AppLog.warn('database', 'delete klw events failed: $e');
      return 0;
    }
    if (deleted > 0) {
      _notifyRecordDeleted(const []);
    }
    return deleted;
  }

  Future<int> deleteRecordsOlderThan(DateTime cutoff) async {
    final db = await database;
    final cutoffMs = cutoff.millisecondsSinceEpoch;
    var deleted = 0;
    await db.transaction((txn) async {
      deleted += await txn.delete(
        trainRecordsTable,
        where: 'receivedTimestamp < ?',
        whereArgs: [cutoffMs],
      );
      try {
        deleted += await txn.delete(
          klwEventsTable,
          where: 'receivedTimestamp < ?',
          whereArgs: [cutoffMs],
        );
      } catch (e) {
        AppLog.warn('database', 'clear old klw events failed: $e');
      }
      try {
        deleted += await txn.delete(
          alarmEventsTable,
          where: 'receivedTimestamp < ?',
          whereArgs: [cutoffMs],
        );
      } catch (e) {
        AppLog.warn('database', 'clear old alarm events failed: $e');
      }
      try {
        deleted += await txn.delete(
          syncEventsTable,
          where: 'receivedTimestamp < ?',
          whereArgs: [cutoffMs],
        );
      } catch (e) {
        AppLog.warn('database', 'clear old sync events failed: $e');
      }
    });
    if (deleted > 0) {
      _notifyRecordDeleted(const []);
    }
    return deleted;
  }

  Future<int> deleteAllRecords() async {
    final db = await database;
    final result = await db.delete(trainRecordsTable);
    var klwResult = 0;
    try {
      klwResult = await db.delete(klwEventsTable);
    } catch (e) {
      AppLog.warn('database', 'clear klw events failed: $e');
    }
    try {
      await db.delete(alarmEventsTable);
    } catch (e) {
      AppLog.warn('database', 'clear alarm events failed: $e');
    }
    try {
      await db.delete(syncEventsTable);
    } catch (e) {
      AppLog.warn('database', 'clear sync events failed: $e');
    }

    if (result > 0 || klwResult > 0) {
      _notifyRecordDeleted([]);
    }

    return result;
  }

  Future<int> getRecordCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM $trainRecordsTable');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<Map<String, dynamic>?> getAllSettings() async {
    final db = await database;
    try {
      final result = await db.query(appSettingsTable, where: 'id = 1');
      if (result.isEmpty) return null;
      return result.first;
    } catch (e) {
      return null;
    }
  }

  Future<int> updateSettings(Map<String, dynamic> settings) async {
    final db = await database;
    final result = await db.update(appSettingsTable, settings, where: 'id = 1');
    if (result > 0) {
      final currentSettings = await getAllSettings();
      if (currentSettings != null) {
        _notifySettingsChanged(currentSettings);
      }
    }
    return result;
  }

  Future<int> setSetting(String key, dynamic value) async {
    final db = await database;
    final result = await db.update(appSettingsTable, {
      key: value,
    }, where: 'id = 1');
    if (result > 0) {
      final currentSettings = await getAllSettings();
      if (currentSettings != null) {
        _notifySettingsChanged(currentSettings);
      }
    }
    return result;
  }

  Future<String> diagnoseDatabase() async {
    final parts = <String>[];
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File(join(directory.path, _databaseName));
      if (!await file.exists()) {
        parts.add('数据库文件不存在');
      } else {
        final size = await file.length();
        parts.add('文件 ${(size / 1024).toStringAsFixed(0)} KB\n${file.path}');
      }
    } catch (e) {
      parts.add('文件读取失败：$e');
    }
    try {
      final db = await database;
      final version = await db.getVersion();
      final count = await getRecordCount();
      parts.add('打开成功，版本 $version，记录 $count 条');
    } catch (e) {
      parts.add('打开失败：$e');
    }
    return parts.join('\n');
  }

  Future<void> deleteRecords(List<String> uniqueIds) async {
    if (uniqueIds.isEmpty) {
      return;
    }

    final db = await database;
    await db.transaction((txn) async {
      const chunkSize = 999;
      for (var start = 0; start < uniqueIds.length; start += chunkSize) {
        final end = (start + chunkSize > uniqueIds.length)
            ? uniqueIds.length
            : start + chunkSize;
        final chunk = uniqueIds.sublist(start, end);
        final placeholders = List.filled(chunk.length, '?').join(',');
        await txn.delete(
          trainRecordsTable,
          where: 'uniqueId IN ($placeholders)',
          whereArgs: chunk,
        );
      }
    });
    _notifyRecordDeleted(uniqueIds);
  }

  final List<Function(List<String>)> _recordDeleteListeners = [];

  final List<Function()> _dataInsertListeners = [];

  final List<Function(Map<String, dynamic>)> _settingsListeners = [];

  StreamSubscription<void> onDataInserted(Function() listener) {
    _dataInsertListeners.add(listener);
    return _ListenerSubscription(() {
      _dataInsertListeners.remove(listener);
    });
  }

  void _notifyDataInserted() {
    for (final listener in List.of(_dataInsertListeners)) {
      listener();
    }
  }

  StreamSubscription<void> onRecordDeleted(Function(List<String>) listener) {
    _recordDeleteListeners.add(listener);
    return _ListenerSubscription(() {
      _recordDeleteListeners.remove(listener);
    });
  }

  void _notifyRecordDeleted(List<String> deletedIds) {
    for (final listener in List.of(_recordDeleteListeners)) {
      listener(deletedIds);
    }
  }

  StreamSubscription<void> onSettingsChanged(
    Function(Map<String, dynamic>) listener,
  ) {
    _settingsListeners.add(listener);
    return _ListenerSubscription(() {
      _settingsListeners.remove(listener);
    });
  }

  void _notifySettingsChanged(Map<String, dynamic> settings) {
    for (final listener in List.of(_settingsListeners)) {
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
      final klwEvents = await getKlwEvents();
      final alarmEvents = await getAlarmEvents();
      final syncEvents = await getSyncEvents();

      final exportData = {
        'records': records.map((r) => r.toDatabaseJson()).toList(),
        'klwEvents': klwEvents.map((e) => e.toDatabaseJson()).toList(),
        'alarmEvents': alarmEvents.map((e) => e.toDatabaseJson()).toList(),
        'syncEvents': syncEvents.map((e) => e.toDatabaseJson()).toList(),
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
          final records = List<Map<String, dynamic>>.from(
            importData['records'],
          );
          for (final record in records) {
            await txn.insert(
              trainRecordsTable,
              TrainRecord.fromJson(record).toDatabaseJson(),
            );
          }
        }

        if (importData['klwEvents'] != null) {
          await txn.delete(klwEventsTable);
          final klwEvents = List<Map<String, dynamic>>.from(
            importData['klwEvents'],
          );
          for (final event in klwEvents) {
            await txn.insert(
              klwEventsTable,
              KlwEvent.fromJson(event).toDatabaseJson(),
            );
          }
        }

        if (importData['alarmEvents'] != null) {
          await txn.delete(alarmEventsTable);
          final alarmEvents = List<Map<String, dynamic>>.from(
            importData['alarmEvents'],
          );
          for (final event in alarmEvents) {
            await txn.insert(
              alarmEventsTable,
              FfskAlarmEvent.fromJson(event).toDatabaseJson(),
            );
          }
        }

        if (importData['syncEvents'] != null) {
          await txn.delete(syncEventsTable);
          final syncEvents = List<Map<String, dynamic>>.from(
            importData['syncEvents'],
          );
          for (final event in syncEvents) {
            await txn.insert(
              syncEventsTable,
              LbjSyncEvent.fromJson(event).toDatabaseJson(),
            );
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
}

class _ListenerSubscription implements StreamSubscription<void> {
  final void Function() _onCancel;
  bool _isCanceled = false;

  _ListenerSubscription(this._onCancel);

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
