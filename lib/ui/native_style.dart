import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'orm_style.dart';
import 'pmtiles_local.dart';

const _libertyStyleUrl = 'https://tiles.openfreemap.org/styles/liberty';

final _styleCache = <String, Future<String?>>{};

Future<String?> buildNativeMapStyle({required bool orm, required bool dark}) {
  final key = 'orm:$orm dark:$dark';
  return _styleCache[key] ??= _build(orm: orm, dark: dark);
}

Future<String?> _build({required bool orm, required bool dark}) async {
  final base = await _getJson(Uri.parse(_libertyStyleUrl));
  if (base == null) return null;
  if (!orm) return jsonEncode(base);
  final rawOrm = await _getJson(Uri.parse(ormStyleURL));
  if (rawOrm == null) return jsonEncode(base);
  final style = rawOrm;
  final sprite = style['sprite'];
  final spriteUpstreams = <String, String>{
    if (sprite is String)
      'orm': sprite
    else if (sprite is List)
      for (final entry in sprite)
        if (entry is Map && entry['id'] is String && entry['url'] is String)
          entry['id'] as String: entry['url'] as String,
  };
  final defaults = _stateDefaults(rawOrm, dark);
  final layers = style['layers'];
  if (layers is List) {
    final kept = <dynamic>[];
    for (final raw in layers) {
      if (raw is! Map<String, dynamic>) {
        kept.add(raw);
        continue;
      }
      final layer = raw;
      for (final key in const ['filter', 'paint', 'layout']) {
        final value = layer[key];
        if (value != null) layer[key] = _fold(value, defaults, const {});
      }
      if (layer['filter'] == false) continue;
      if (layer['filter'] == true) layer.remove('filter');
      kept.add(layer);
    }
    style['layers'] = kept;
  }
  final combined = _combineStyles(base, style, spriteUpstreams);
  combined.remove('state');
  await _mergePmtilesSources(combined);
  return jsonEncode(combined);
}

Future<void> _mergePmtilesSources(Map<String, dynamic> style) async {
  final sources = style['sources'];
  if (sources is! Map<String, dynamic>) return;
  final merged = <String>[
    for (final entry in sources.entries)
      if (entry.value is Map &&
          (entry.value as Map)['url'] == ormPMTilesURL)
        entry.key,
  ];
  if (merged.isEmpty) return;
  final base = await PmtilesTileServer.instance.baseUrl();
  for (final name in merged) {
    sources.remove(name);
  }
  sources['orm'] = {'type': 'vector', 'url': '$base/tiles.json'};
  final layers = style['layers'];
  if (layers is List) {
    for (final layer in layers) {
      if (layer is Map && merged.contains(layer['source'])) {
        layer['source'] = 'orm';
      }
    }
  }
}

Map<String, dynamic> _stateDefaults(Map<String, dynamic> ormStyle, bool dark) {
  final defaults = <String, dynamic>{};
  final state = ormStyle['state'];
  if (state is Map) {
    for (final entry in state.entries) {
      final value = entry.value;
      if (entry.key is String && value is Map && value.containsKey('default')) {
        defaults[entry.key as String] = value['default'];
      }
    }
  }
  defaults['theme'] = dark ? 'dark' : 'light';
  return defaults;
}

Future<Map<String, dynamic>?> _getJson(Uri uri) async {
  final client = HttpClient();
  try {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final request = await client
            .getUrl(uri)
            .timeout(const Duration(seconds: 15));
        request.headers.set(
          'User-Agent',
          'emu-log/1.0 (+https://rail.nedifinita.com/)',
        );
        request.headers.set('Referer', 'https://rail.nedifinita.com/');
        final response = await request
            .close()
            .timeout(const Duration(seconds: 15));
        if (response.statusCode == 200) {
          final bytes = await response
              .fold<List<int>>(<int>[], (acc, chunk) {
                acc.addAll(chunk);
                return acc;
              })
              .timeout(const Duration(seconds: 15));
          final decoded = jsonDecode(utf8.decode(bytes));
          return decoded is Map<String, dynamic> ? decoded : null;
        }
        if (!_retryable(response.statusCode) || attempt == 2) return null;
        await response.drain<void>();
      } catch (_) {
        if (attempt == 2) return null;
      }
    }
    return null;
  } finally {
    client.close();
  }
}

bool _retryable(int status) =>
    status == 408 ||
    status == 500 ||
    status == 502 ||
    status == 503 ||
    status == 504 ||
    (status >= 520 && status <= 524);

dynamic _deepCopy(dynamic value) {
  if (value is Map || value is List) {
    return jsonDecode(jsonEncode(value));
  }
  return value;
}

bool _deepEquals(dynamic a, dynamic b) {
  if (a is num && b is num) return a == b;
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) return false;
    }
    return true;
  }
  return a == b;
}

bool _isLiteral(dynamic value) =>
    value is! List || (value.isNotEmpty && value[0] == 'literal');

dynamic _literalValue(dynamic value) =>
    (value is List && value.isNotEmpty && value[0] == 'literal')
        ? value[1]
        : value;

dynamic _fold(
  dynamic node,
  Map<String, dynamic> state,
  Map<String, dynamic> vars,
) {
  if (node is Map) {
    return <String, dynamic>{
      for (final entry in node.entries)
        entry.key.toString(): _fold(entry.value, state, vars),
    };
  }
  if (node is List) {
    if (node.isEmpty) return node;
    final head = node[0];
    if (head is! String) {
      return [for (final child in node) _fold(child, state, vars)];
    }
    switch (head) {
      case 'literal':
        return node;
      case 'global-state':
        if (node.length == 2 && node[1] is String) {
          final value = _deepCopy(state[node[1]]);
          if (value is List || value is Map) return ['literal', value];
          return value;
        }
        return node;
      case 'var':
        if (node.length == 2 &&
            node[1] is String &&
            vars.containsKey(node[1])) {
          return _deepCopy(vars[node[1]]);
        }
        return node;
      case 'let':
        if (node.length >= 3 && node.length.isEven) {
          final inner = Map<String, dynamic>.of(vars);
          var valid = true;
          for (var i = 1; i < node.length - 1; i += 2) {
            final name = node[i];
            if (name is! String) {
              valid = false;
              break;
            }
            inner[name] = _fold(node[i + 1], state, inner);
          }
          if (valid) return _fold(node.last, state, inner);
        }
        return [for (final child in node) _fold(child, state, vars)];
    }
    final args = [
      for (var i = 1; i < node.length; i++) _fold(node[i], state, vars),
    ];
    switch (head) {
      case '==':
      case '!=':
        if (args.length == 2 &&
            _isLiteral(args[0]) &&
            _isLiteral(args[1]) &&
            (node[1] is List ||
                node[2] is List ||
                args[0] is! String ||
                args[1] is! String)) {
          final equal = _deepEquals(
            _literalValue(args[0]),
            _literalValue(args[1]),
          );
          return head == '==' ? equal : !equal;
        }
      case '>':
      case '<':
      case '>=':
      case '<=':
        if (args.length == 2 && args[0] is num && args[1] is num) {
          final a = args[0] as num;
          final b = args[1] as num;
          return switch (head) {
            '>' => a > b,
            '<' => a < b,
            '>=' => a >= b,
            _ => a <= b,
          };
        }
      case '+':
        if (args.isNotEmpty && args.every((a) => a is num)) {
          return args.fold<num>(0, (sum, a) => sum + (a as num));
        }
      case '*':
        if (args.isNotEmpty && args.every((a) => a is num)) {
          return args.fold<num>(1, (sum, a) => sum * (a as num));
        }
      case '-':
        if (args.length == 1 && args[0] is num) return -(args[0] as num);
        if (args.length == 2 && args[0] is num && args[1] is num) {
          return (args[0] as num) - (args[1] as num);
        }
      case '/':
        if (args.length == 2 && args[0] is num && args[1] is num) {
          return (args[0] as num) / (args[1] as num);
        }
      case '%':
        if (args.length == 2 && args[0] is num && args[1] is num) {
          return (args[0] as num) % (args[1] as num);
        }
      case 'all':
        if (args.any((a) => a == false)) return false;
        final rest = [for (final a in args) if (a != true) a];
        if (rest.isEmpty) return true;
        if (rest.length == 1) return rest[0];
        return ['all', ...rest];
      case 'any':
        if (args.any((a) => a == true)) return true;
        final rest = [for (final a in args) if (a != false) a];
        if (rest.isEmpty) return false;
        if (rest.length == 1) return rest[0];
        return ['any', ...rest];
      case '!':
        if (args.length == 1 && args[0] is bool) return !(args[0] as bool);
      case 'case':
        var i = 0;
        while (i + 1 < args.length) {
          final condition = args[i];
          if (condition is bool) {
            if (condition) return args[i + 1];
            i += 2;
            continue;
          }
          return ['case', ...args.sublist(i)];
        }
        return args.isEmpty ? null : args.last;
      case 'match':
        if (args.length >= 2 && _isLiteral(args[0])) {
          final input = _literalValue(args[0]);
          var i = 1;
          while (i + 1 < args.length) {
            final label = _literalValue(args[i]);
            final hit = label is List
                ? label.any((option) => _deepEquals(option, input))
                : _deepEquals(label, input);
            if (hit) return args[i + 1];
            i += 2;
          }
          return args.last;
        }
      case 'coalesce':
        for (var i = 0; i < args.length; i++) {
          final arg = args[i];
          if (_isLiteral(arg)) {
            if (_literalValue(arg) != null) return arg;
          } else {
            return ['coalesce', ...args.sublist(i)];
          }
        }
        return null;
      case 'in':
        if (args.length == 2 && _isLiteral(args[0]) && _isLiteral(args[1])) {
          final needle = _literalValue(args[0]);
          final haystack = _literalValue(args[1]);
          if (haystack is List) {
            return haystack.any((option) => _deepEquals(option, needle));
          }
          if (haystack is String && needle is String) {
            return haystack.contains(needle);
          }
        }
      case 'step':
        if (args.length >= 2 && args[0] is num) {
          final input = args[0] as num;
          dynamic result = args[1];
          for (var i = 2; i + 1 < args.length; i += 2) {
            final stop = args[i];
            if (stop is num && input >= stop) result = args[i + 1];
          }
          return result;
        }
      case 'to-string':
        if (args.length == 1 && _isLiteral(args[0])) {
          final value = _literalValue(args[0]);
          if (value == null) return '';
          if (value is bool) return value ? 'true' : 'false';
          return value.toString();
        }
      case 'to-number':
        if (args.length == 1 && _isLiteral(args[0])) {
          final value = _literalValue(args[0]);
          if (value is num) return value;
          if (value is String) return num.tryParse(value);
          if (value is bool) return value ? 1 : 0;
        }
      case 'concat':
        if (args.every((a) => _isLiteral(a) && _literalValue(a) is String)) {
          return args.map((a) => _literalValue(a) as String).join();
        }
      case 'upcase':
        if (args.length == 1 && _isLiteral(args[0])) {
          final value = _literalValue(args[0]);
          if (value is String) return value.toUpperCase();
        }
      case 'downcase':
        if (args.length == 1 && _isLiteral(args[0])) {
          final value = _literalValue(args[0]);
          if (value is String) return value.toLowerCase();
        }
      case 'length':
        if (args.length == 1 && _isLiteral(args[0])) {
          final value = _literalValue(args[0]);
          if (value is String) return value.length;
          if (value is List) return value.length;
        }
    }
    return [head, ...args];
  }
  return node;
}

Map<String, dynamic> _sansSerifTextLayer(Map<String, dynamic> layer) {
  final layout = layer['layout'];
  if (layer['type'] != 'symbol' || layout is! Map) return layer;
  final families = layout['text-font'];
  if (families == null) return layer;
  final source = families is List ? families.join(' ') : families.toString();
  final font = RegExp('bold', caseSensitive: false).hasMatch(source)
      ? 'Noto Sans Bold'
      : RegExp('italic', caseSensitive: false).hasMatch(source)
          ? 'Noto Sans Italic'
          : 'Noto Sans Regular';
  return {
    ...layer,
    'layout': {...layout, 'text-font': [font]},
  };
}

dynamic _prefixSpriteExpression(dynamic value, String spriteId) {
  if (value is String) {
    return value.isNotEmpty && !value.contains(':')
        ? '$spriteId:$value'
        : value;
  }
  if (value is! List || value.isEmpty) return value;
  final operator = value[0];
  final args = value.sublist(1);
  if (operator == 'literal' && args.isNotEmpty && args[0] is String) {
    return ['literal', _prefixSpriteExpression(args[0], spriteId)];
  }
  if (operator == 'image') {
    return ['image', _prefixSpriteExpression(args[0], spriteId)];
  }
  if (operator == 'concat') {
    if (args.isNotEmpty &&
        args[0] is String &&
        (args[0] as String).startsWith('$spriteId:')) {
      return value;
    }
    return ['concat', '$spriteId:', ...args];
  }
  if (operator == 'case') {
    final rewritten = <dynamic>[operator];
    for (var i = 0; i < args.length - 1; i += 2) {
      rewritten.add(args[i]);
      rewritten.add(_prefixSpriteExpression(args[i + 1], spriteId));
    }
    if (args.length.isOdd) {
      rewritten.add(_prefixSpriteExpression(args.last, spriteId));
    }
    return rewritten;
  }
  if (operator == 'match') {
    final rewritten = <dynamic>[operator, args[0]];
    for (var i = 1; i < args.length - 1; i += 2) {
      rewritten.add(args[i]);
      rewritten.add(_prefixSpriteExpression(args[i + 1], spriteId));
    }
    if (args.length.isEven) {
      rewritten.add(_prefixSpriteExpression(args.last, spriteId));
    }
    return rewritten;
  }
  if (operator == 'step') {
    final rewritten = <dynamic>[
      operator,
      args[0],
      _prefixSpriteExpression(args[1], spriteId),
    ];
    for (var i = 2; i < args.length; i += 2) {
      rewritten.add(args[i]);
      rewritten.add(_prefixSpriteExpression(args[i + 1], spriteId));
    }
    return rewritten;
  }
  if (operator == 'interpolate' ||
      operator == 'interpolate-hcl' ||
      operator == 'interpolate-lab' ||
      operator == 'interpolate-rgb') {
    final rewritten = <dynamic>[operator, args[0], args[1]];
    for (var i = 2; i < args.length; i += 2) {
      rewritten.add(args[i]);
      rewritten.add(_prefixSpriteExpression(args[i + 1], spriteId));
    }
    return rewritten;
  }
  if (operator == 'coalesce') {
    return [
      operator,
      for (final arg in args) _prefixSpriteExpression(arg, spriteId),
    ];
  }
  if (operator == 'let') {
    return [
      ...value.sublist(0, value.length - 1),
      _prefixSpriteExpression(value.last, spriteId),
    ];
  }
  return ['concat', '$spriteId:', value];
}

Map<String, dynamic> _combineStyles(
  Map<String, dynamic> baseStyle,
  Map<String, dynamic> railwayStyle,
  Map<String, String> spriteUpstreams,
) {
  final sources = <String, dynamic>{
    ...(baseStyle['sources'] as Map<String, dynamic>? ?? const {}),
  };
  final railwaySources =
      railwayStyle['sources'] as Map<String, dynamic>? ?? const {};
  for (final entry in railwaySources.entries) {
    final source = Map<String, dynamic>.from(entry.value as Map);
    if (source['type'] == 'geojson' &&
        source['data'] == null &&
        source['url'] == null) {
      source['data'] = {'type': 'FeatureCollection', 'features': <dynamic>[]};
    }
    sources['orm-${entry.key}'] = source;
  }
  final baseSprite = baseStyle['sprite'];
  final baseSpriteIsSingle = baseSprite is String;
  final baseSprites = <Map<String, dynamic>>[
    if (baseSpriteIsSingle)
      {'id': 'ofm', 'url': baseSprite}
    else if (baseSprite is List)
      for (final entry in baseSprite)
        if (entry is Map) Map<String, dynamic>.from(entry),
  ];
  final railwaySprite = railwayStyle['sprite'];
  final railwaySprites = <Map<String, dynamic>>[
    if (railwaySprite is String)
      {'id': 'orm', 'url': spriteUpstreams['orm']}
    else if (railwaySprite is List)
      for (final entry in railwaySprite)
        if (entry is Map && entry['id'] is String)
          {'id': entry['id'], 'url': spriteUpstreams[entry['id']]},
  ];
  final spriteIds = <String>{};
  for (final sprite in [...baseSprites, ...railwaySprites]) {
    final id = sprite['id'];
    if (id is String && !spriteIds.add(id)) {
      throw StateError('duplicate map sprite id: $id');
    }
  }
  Map<String, dynamic> rewriteBaseSprites(Map<String, dynamic> layer) {
    if (!baseSpriteIsSingle) return layer;
    final layout = <String, dynamic>{
      ...(layer['layout'] as Map<String, dynamic>? ?? const {}),
    };
    final paint = <String, dynamic>{
      ...(layer['paint'] as Map<String, dynamic>? ?? const {}),
    };
    if (layout['icon-image'] != null) {
      layout['icon-image'] = _prefixSpriteExpression(layout['icon-image'], 'ofm');
    }
    for (final property in const [
      'fill-pattern',
      'line-pattern',
      'background-pattern',
      'fill-extrusion-pattern',
    ]) {
      if (paint[property] != null) {
        paint[property] = _prefixSpriteExpression(paint[property], 'ofm');
      }
    }
    return {...layer, 'layout': layout, 'paint': paint};
  }

  final baseLayers = <Map<String, dynamic>>[
    for (final raw in baseStyle['layers'] as List? ?? const [])
      if (raw is Map)
        _sansSerifTextLayer(
          rewriteBaseSprites(Map<String, dynamic>.from(raw)),
        ),
  ];
  final railwayLayers = <Map<String, dynamic>>[
    for (final raw in railwayStyle['layers'] as List? ?? const [])
      if (raw is Map)
        _sansSerifTextLayer({
          ...Map<String, dynamic>.from(raw),
          'id': 'orm-${raw['id']}',
          if (raw['source'] != null) 'source': 'orm-${raw['source']}',
          if (raw['ref'] != null) 'ref': 'orm-${raw['ref']}',
        }),
  ];
  final layers = [
    for (final layer in baseLayers)
      if (layer['type'] != 'symbol') layer,
    for (final layer in railwayLayers)
      if (layer['type'] != 'symbol') layer,
    for (final layer in railwayLayers)
      if (layer['type'] == 'symbol') layer,
    for (final layer in baseLayers)
      if (layer['type'] == 'symbol') layer,
  ];
  return {
    ...baseStyle,
    'sprite': [...baseSprites, ...railwaySprites],
    'glyphs': baseStyle['glyphs'] ?? railwayStyle['glyphs'],
    'sources': sources,
    'layers': layers,
  };
}
