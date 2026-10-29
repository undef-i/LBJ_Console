import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'mvt_simplify.dart';
import 'orm_style.dart';

final _archiveUrl = ormPMTilesURL.substring('pmtiles://'.length);

class _Entry {
  _Entry(this.tileId, this.offset, this.length, this.runLength);

  final int tileId;
  final int offset;
  final int length;
  final int runLength;
}

List<int> _rotate(int n, int x, int y, int rx, int ry) {
  if (ry == 0) {
    if (rx != 0) return [n - 1 - y, n - 1 - x];
    return [y, x];
  }
  return [x, y];
}

int _zxyToTileId(int z, int x, int y) {
  var acc = ((1 << z) * (1 << z) - 1) ~/ 3;
  var a = z - 1;
  var tx = x;
  var ty = y;
  for (var s = 1 << a; s > 0; s >>= 1) {
    final rx = tx & s;
    final ry = ty & s;
    acc += ((3 * rx) ^ ry) * (1 << a);
    final rotated = _rotate(s, tx, ty, rx, ry);
    tx = rotated[0];
    ty = rotated[1];
    a--;
  }
  return acc;
}

class _Reader {
  _Reader(this.buf);

  final Uint8List buf;
  var pos = 0;

  int varint() {
    var val = 0;
    var shift = 0;
    while (true) {
      final b = buf[pos++];
      val |= (b & 0x7f) << shift;
      if (b < 0x80) return val;
      shift += 7;
    }
  }
}

List<_Entry> _deserializeIndex(Uint8List data) {
  final reader = _Reader(data);
  final numEntries = reader.varint();
  final entries = <_Entry>[];
  var lastId = 0;
  final tileIds = List<int>.filled(numEntries, 0);
  for (var i = 0; i < numEntries; i++) {
    lastId += reader.varint();
    tileIds[i] = lastId;
  }
  final runLengths = List<int>.filled(numEntries, 0);
  for (var i = 0; i < numEntries; i++) {
    runLengths[i] = reader.varint();
  }
  final lengths = List<int>.filled(numEntries, 0);
  for (var i = 0; i < numEntries; i++) {
    lengths[i] = reader.varint();
  }
  var prevOffset = 0;
  var prevLength = 0;
  for (var i = 0; i < numEntries; i++) {
    final v = reader.varint();
    final offset = (v == 0 && i > 0) ? prevOffset + prevLength : v - 1;
    entries.add(_Entry(tileIds[i], offset, lengths[i], runLengths[i]));
    prevOffset = offset;
    prevLength = lengths[i];
  }
  return entries;
}

_Entry? _findTile(List<_Entry> entries, int tileId) {
  var m = 0;
  var n = entries.length - 1;
  while (m <= n) {
    final k = (n + m) >> 1;
    final cmp = tileId - entries[k].tileId;
    if (cmp > 0) {
      m = k + 1;
    } else if (cmp < 0) {
      n = k - 1;
    } else {
      return entries[k];
    }
  }
  if (n >= 0) {
    if (entries[n].runLength == 0) return entries[n];
    if (tileId - entries[n].tileId < entries[n].runLength) return entries[n];
  }
  return null;
}

Uint8List _gunzip(Uint8List data, int compression) {
  if (compression == 2) return Uint8List.fromList(gzip.decode(data));
  return data;
}

class _EtagChanged implements Exception {}

class PmtilesArchive {
  static Map<int, Set<String>>? layerKeepSets;

  final _client = HttpClient();
  Future<void>? _loading;
  String? _etag;

  late int _rootOffset;
  late int _rootLength;
  late int _metadataOffset;
  late int _metadataLength;
  late int _leafOffset;
  late int _dataOffset;
  late int _internalCompression;
  late int _tileCompression;
  late int minZoom;
  late int maxZoom;
  late double _minLon;
  late double _minLat;
  late double _maxLon;
  late double _maxLat;
  late int _centerZoom;
  late double _centerLon;
  late double _centerLat;

  List<_Entry>? _root;
  Map<String, dynamic>? _metadata;
  final _directories = <String, List<_Entry>>{};
  final _pendingDirectories = <String, Future<List<_Entry>>>{};
  final _tileCache = <int, Uint8List?>{};
  final _pendingTiles = <int, Future<Uint8List?>>{};
  var _tileCacheBytes = 0;

  static const _tileCacheMaxEntries = 1024;
  static const _tileCacheMaxBytes = 32 * 1024 * 1024;
  static const _simplifyThreshold = 1024 * 1024;
  static const _directoryCacheMaxEntries = 128;

  String? get etag => _etag;

  Future<void> ensureLoaded() {
    if (_root != null) return Future.value();
    return _loading ??= _load().whenComplete(() {
      if (_root == null) _loading = null;
    });
  }

  void _invalidate() {
    _root = null;
    _metadata = null;
    _etag = null;
    _directories.clear();
    _tileCache.clear();
    _tileCacheBytes = 0;
    _loading = null;
  }

  Future<void> _load() async {
    final first = await _range(0, 16384);
    final bytes = first.bytes;
    if (bytes.length < 127 ||
        bytes[0] != 0x50 ||
        bytes[1] != 0x4d ||
        bytes[2] != 0x54) {
      throw const FormatException('not a PMTiles archive');
    }
    final view = ByteData.sublistView(bytes);
    int u64(int offset) => view.getUint64(offset, Endian.little);
    double coord(int offset) => view.getInt32(offset, Endian.little) / 1e7;
    _rootOffset = u64(8);
    _rootLength = u64(16);
    _metadataOffset = u64(24);
    _metadataLength = u64(32);
    _leafOffset = u64(40);
    _dataOffset = u64(56);
    _internalCompression = bytes[97];
    _tileCompression = bytes[98];
    minZoom = bytes[100];
    maxZoom = bytes[101];
    _minLon = coord(102);
    _minLat = coord(106);
    _maxLon = coord(110);
    _maxLat = coord(114);
    _centerZoom = bytes[118];
    _centerLon = coord(119);
    _centerLat = coord(123);
    final rootRaw = Uint8List.sublistView(
      bytes,
      _rootOffset,
      _rootOffset + _rootLength,
    );
    _root = _deserializeIndex(_gunzip(rootRaw, _internalCompression));
    final metaRaw = (await _range(_metadataOffset, _metadataLength)).bytes;
    final decoded = jsonDecode(
      utf8.decode(_gunzip(metaRaw, _internalCompression)),
    );
    _metadata = decoded is Map<String, dynamic> ? decoded : null;
  }

  Future<({Uint8List bytes, String? etag})> _rangeOnce(
    int offset,
    int length,
  ) async {
    final request = await _client.getUrl(Uri.parse(_archiveUrl));
    request.headers.set(
      'User-Agent',
      'emu-log/1.0 (+https://rail.nedifinita.com/)',
    );
    request.headers.set('Referer', 'https://rail.nedifinita.com/');
    request.headers.set('Range', 'bytes=$offset-${offset + length - 1}');
    final response = await request.close();
    if (response.statusCode != 206) {
      await response.drain<void>();
      throw HttpException('range request failed: ${response.statusCode}');
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    return (bytes: builder.takeBytes(), etag: response.headers.value('etag'));
  }

  Future<({Uint8List bytes, String? etag})> _range(
    int offset,
    int length,
  ) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final result = await _rangeOnce(offset, length);
        final etag = result.etag;
        if (etag != null) {
          if (_etag != null && _etag != etag) throw _EtagChanged();
          _etag = etag;
        }
        return result;
      } on _EtagChanged {
        rethrow;
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? const HttpException('range request failed');
  }

  Future<List<_Entry>> _directory(int offset, int length) {
    if (offset == _rootOffset && length == _rootLength) {
      return Future.value(_root!);
    }
    final key = '$offset|$length';
    final cached = _directories.remove(key);
    if (cached != null) {
      _directories[key] = cached;
      return Future.value(cached);
    }
    final pending = _pendingDirectories[key];
    if (pending != null) return pending;
    final future = _fetchDirectory(key, offset, length);
    _pendingDirectories[key] = future;
    return future.whenComplete(() {
      _pendingDirectories.remove(key);
    });
  }

  Future<List<_Entry>> _fetchDirectory(
    String key,
    int offset,
    int length,
  ) async {
    final raw = (await _range(offset, length)).bytes;
    final directory = _deserializeIndex(_gunzip(raw, _internalCompression));
    if (directory.isEmpty) {
      throw const FormatException('empty directory');
    }
    _directories[key] = directory;
    while (_directories.length > _directoryCacheMaxEntries) {
      _directories.remove(_directories.keys.first);
    }
    return directory;
  }

  Future<Uint8List?> tile(int z, int x, int y) {
    final tileId = _zxyToTileId(z, x, y);
    if (_tileCache.containsKey(tileId)) {
      final value = _tileCache.remove(tileId);
      _tileCache[tileId] = value;
      return Future.value(value);
    }
    final pending = _pendingTiles[tileId];
    if (pending != null) return pending;
    final future = _fetchTile(z, x, y, tileId);
    _pendingTiles[tileId] = future;
    return future.whenComplete(() {
      _pendingTiles.remove(tileId);
    });
  }

  Future<Uint8List?> _fetchTile(int z, int x, int y, int tileId) async {
    Uint8List? result;
    try {
      result = await _tileAttempt(z, x, y);
    } on _EtagChanged {
      _invalidate();
      result = await _tileAttempt(z, x, y);
    }
    if (result != null) {
      final keep = layerKeepSets?[z];
      if (keep != null) {
        result = stripVectorTileLayers(result, keep);
      }
      if (result.length > _simplifyThreshold) {
        final raw = result;
        result = await Isolate.run(() => simplifyVectorTile(raw));
      }
    }
    _storeTile(tileId, result);
    return result;
  }

  void _storeTile(int tileId, Uint8List? bytes) {
    if (_tileCache.containsKey(tileId)) {
      _tileCacheBytes -= _tileCache[tileId]?.length ?? 0;
      _tileCache.remove(tileId);
    }
    _tileCache[tileId] = bytes;
    _tileCacheBytes += bytes?.length ?? 0;
    while (_tileCache.length > _tileCacheMaxEntries ||
        _tileCacheBytes > _tileCacheMaxBytes) {
      final oldest = _tileCache.keys.first;
      if (oldest == tileId) break;
      _tileCacheBytes -= _tileCache[oldest]?.length ?? 0;
      _tileCache.remove(oldest);
    }
  }

  Future<Uint8List?> _tileAttempt(int z, int x, int y) async {
    await ensureLoaded();
    if (z < minZoom || z > maxZoom) return null;
    final tileId = _zxyToTileId(z, x, y);
    var offset = _rootOffset;
    var length = _rootLength;
    for (var depth = 0; depth <= 3; depth++) {
      final directory = await _directory(offset, length);
      final entry = _findTile(directory, tileId);
      if (entry == null) return null;
      if (entry.runLength > 0) {
        final raw = (await _range(
          _dataOffset + entry.offset,
          entry.length,
        )).bytes;
        return _gunzip(raw, _tileCompression);
      }
      offset = _leafOffset + entry.offset;
      length = entry.length;
    }
    throw StateError('maximum directory depth exceeded');
  }

  Map<String, dynamic> tileJson(String base) {
    final metadata = _metadata ?? const <String, dynamic>{};
    final tileJson = <String, dynamic>{
      'tilejson': '3.0.0',
      'scheme': 'xyz',
      'tiles': ['$base/tiles/{z}/{x}/{y}.mvt'],
      'vector_layers': metadata['vector_layers'],
      'attribution': metadata['attribution'],
      'description': metadata['description'],
      'name': metadata['name'],
      'version': metadata['version'],
      'bounds': [_minLon, _minLat, _maxLon, _maxLat],
      'center': [_centerLon, _centerLat, _centerZoom],
      'minzoom': minZoom,
      'maxzoom': maxZoom,
    };
    tileJson.removeWhere((_, value) => value == null);
    return tileJson;
  }
}

class PmtilesTileServer {
  PmtilesTileServer._();

  static final instance = PmtilesTileServer._();

  final archive = PmtilesArchive();
  HttpServer? _server;
  Future<String>? _starting;

  Future<String> baseUrl() {
    final server = _server;
    if (server != null) {
      return Future.value('http://127.0.0.1:${server.port}');
    }
    return _starting ??= _start();
  }

  Future<String> _start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen(_handle);
    return 'http://127.0.0.1:${server.port}';
  }

  static final _tilePath = RegExp(r'^/tiles/(\d+)/(\d+)/(\d+)(\.(mvt|pbf))?$');

  static final List<String> requestLog = [];

  static void _logRequest(String path, int status, int elapsedMs) {
    final now = DateTime.now().toIso8601String();
    requestLog.add(
      '${now.substring(11, 23)} $path $status ${elapsedMs}ms',
    );
    if (requestLog.length > 200) requestLog.removeAt(0);
  }

  bool _applyCacheHeaders(HttpRequest request, HttpResponse response) {
    final etag = archive.etag;
    if (etag == null) return false;
    response.headers.set('ETag', etag);
    response.headers.set(
      'Cache-Control',
      'public, max-age=31536000, immutable',
    );
    var ifNoneMatch = request.headers.value('if-none-match');
    if (ifNoneMatch != null && ifNoneMatch.startsWith('W/')) {
      ifNoneMatch = ifNoneMatch.substring(2);
    }
    return ifNoneMatch == etag;
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    final stopwatch = Stopwatch()..start();
    try {
      if (request.uri.path == '/tiles.json') {
        await archive.ensureLoaded();
        if (_applyCacheHeaders(request, response)) {
          response.statusCode = HttpStatus.notModified;
          await response.close();
          _logRequest('/tiles.json', 304, stopwatch.elapsedMilliseconds);
          return;
        }
        final base = 'http://127.0.0.1:${_server!.port}';
        response.headers.contentType = ContentType.json;
        response.write(jsonEncode(archive.tileJson(base)));
        await response.close();
        _logRequest('/tiles.json', 200, stopwatch.elapsedMilliseconds);
        return;
      }
      final match = _tilePath.firstMatch(request.uri.path);
      if (match == null) {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }
      final z = int.parse(match.group(1)!);
      final x = int.parse(match.group(2)!);
      final y = int.parse(match.group(3)!);
      await archive.ensureLoaded();
      if (z < archive.minZoom || z > archive.maxZoom) {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }
      if (_applyCacheHeaders(request, response)) {
        response.statusCode = HttpStatus.notModified;
        await response.close();
        _logRequest(request.uri.path, 304, stopwatch.elapsedMilliseconds);
        return;
      }
      final tile = await archive.tile(z, x, y);
      if (tile == null) {
        response.statusCode = HttpStatus.noContent;
        await response.close();
        _logRequest(request.uri.path, 204, stopwatch.elapsedMilliseconds);
        return;
      }
      response.headers.contentType = ContentType(
        'application',
        'x-protobuf',
      );
      response.add(tile);
      await response.close();
      _logRequest(request.uri.path, 200, stopwatch.elapsedMilliseconds);
    } catch (_) {
      _logRequest(request.uri.path, 502, stopwatch.elapsedMilliseconds);
      try {
        response.statusCode = HttpStatus.badGateway;
        await response.close();
      } catch (_) {}
    }
  }
}
