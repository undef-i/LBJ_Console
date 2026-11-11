import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class ResourceEntry {
  final String id;
  final String name;
  final String file;
  final String version;
  final String sha256;
  final int size;

  const ResourceEntry({
    required this.id,
    required this.name,
    required this.file,
    required this.version,
    required this.sha256,
    required this.size,
  });

  factory ResourceEntry.fromJson(Map<String, dynamic> json) {
    return ResourceEntry(
      id: json['id'] as String,
      name: json['name'] as String,
      file: json['file'] as String,
      version: json['version'] as String,
      sha256: json['sha256'] as String,
      size: (json['size'] as num).toInt(),
    );
  }
}

class ResourceService {
  static const baseUrl =
      'https://lbj-data.nedifinita.com';
  static const bundledVersions = {
    'loco_info': String.fromEnvironment(
      'BUNDLED_LOCO_VERSION',
      defaultValue: '20260910',
    ),
    'loco_type_info': String.fromEnvironment(
      'BUNDLED_LOCO_TYPE_VERSION',
      defaultValue: '20261110',
    ),
  };
  static const assetPaths = {
    'loco_info': 'assets/data/loco_info.csv',
    'loco_type_info': 'assets/data/loco_type_info.csv',
  };
  static const resourceNames = {
    'loco_info': '机车配属',
    'loco_type_info': '机车类型',
  };

  static Directory? _dir;
  static Map<String, dynamic> _state = {};
  static bool _ready = false;

  static Future<void> initialize() async {
    if (_ready) return;
    final docs = await getApplicationDocumentsDirectory();
    _dir = Directory('${docs.path}/resources');
    await _dir!.create(recursive: true);
    final file = File('${_dir!.path}/state.json');
    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, dynamic>) _state = decoded;
      } on FormatException {
        _state = {};
      }
    }
    _ready = true;
    for (final id in assetPaths.keys) {
      await _extractBundled(id);
      await _refreshCurrent(id);
    }
  }

  static Future<void> _extractBundled(String id) async {
    final target = File('${_dir!.path}/$id/${bundledVersions[id]}.csv');
    if (await target.exists()) return;
    try {
      final text = await rootBundle.loadString(assetPaths[id]!);
      if (text.isEmpty) return;
      await target.parent.create(recursive: true);
      await target.writeAsString(text);
    } on Exception {
      return;
    }
  }

  static Future<void> _refreshCurrent(String id) async {
    final dir = Directory('${_dir!.path}/$id');
    String? newest;
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.csv')) {
          final name = entity.path.split('/').last;
          final version = name.substring(0, name.length - 4);
          if (newest == null || version.compareTo(newest) > 0) {
            newest = version;
          }
        }
      }
    }
    _current[id] = newest;
  }

  static Future<void> _save() async {
    await File('${_dir!.path}/state.json').writeAsString(jsonEncode(_state));
  }

  static final Map<String, String?> _current = {};

  static String? currentVersion(String id) => _current[id];

  static String get trainTypeVersion =>
      _state['trainType'] as String? ?? '2014';

  static Future<void> setTrainTypeVersion(String version) async {
    _state['trainType'] = version;
    await _save();
  }

  static Future<String> loadText(String id) async {
    await initialize();
    final version = currentVersion(id);
    if (version != null) {
      final file = File('${_dir!.path}/$id/$version.csv');
      if (await file.exists()) return file.readAsString();
    }
    try {
      return await rootBundle.loadString(assetPaths[id]!);
    } on Exception {
      return '';
    }
  }

  static Future<List<ResourceEntry>?> fetchManifest() async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(Uri.parse('$baseUrl/manifest.json'));
      final response = await request.close();
      if (response.statusCode != 200) return null;
      final text = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) return null;
      final list = decoded['resources'];
      if (list is! List) return null;
      return list
          .whereType<Map<String, dynamic>>()
          .map(ResourceEntry.fromJson)
          .toList();
    } on Exception {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<void> download(ResourceEntry entry) async {
    await initialize();
    final dir = Directory('${_dir!.path}/${entry.id}');
    await dir.create(recursive: true);
    final tmp = File('${dir.path}/${entry.version}.csv.tmp');
    final target = File('${dir.path}/${entry.version}.csv');
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(Uri.parse('$baseUrl/${entry.file}'));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw const FileSystemException('下载失败');
      }
      final sink = tmp.openWrite();
      await response.listen((chunk) => sink.add(chunk)).asFuture();
      await sink.close();
      final bytes = await tmp.readAsBytes();
      if (bytes.length != entry.size ||
          sha256.convert(bytes).toString() != entry.sha256) {
        await tmp.delete();
        throw const FileSystemException('文件校验失败');
      }
      await tmp.rename(target.path);
      await _refreshCurrent(entry.id);
    } finally {
      client.close(force: true);
    }
  }

}
