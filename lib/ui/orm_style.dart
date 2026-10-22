// A line-for-line port of rail.nedifinita.com's backend style
// preprocessing (emu-log handlers/map.go: rewriteORMStyle and its
// helpers), so the app's OpenRailwayMap overlay is built from
// exactly the style rail serves at /api/map/orm-style-v2. Two
// transport substitutions, both forced by the app having no
// same-origin backend on rail's host:
//
//   * Where rail's absoluteORMURL points asset URLs at
//     https://rail.nedifinita.com/api/map/orm-vector/…, this port
//     points them at the upstream https://openrailwaymap.app/…
//     itself.
//   * Sprite atlases are the exception: openrailwaymap.app sends
//     no CORS headers, so the rewritten sprite URLs use a custom
//     ormsprite:// scheme and the caller downloads the atlas bytes
//     itself (spriteUpstreams says from where) and hands them to
//     the page, which serves them through a protocol handler.
//
// Pure Dart (no Flutter imports) so the port can be run standalone
// and diffed against rail's live /api/map/orm-style-v2 output.

const ormProxyPrefix = '/api/map/orm-vector/';
// HTTPS avoids mixed-content blocking on the HTTPS map page.
const ormPMTilesURL = 'pmtiles://https://orm.nedifinita.com/orm.pmtiles';
const _ormUpstreamOrigin = 'https://openrailwaymap.app';

class OrmRewriteResult {
  OrmRewriteResult(this.style, this.spriteUpstreams);

  final Map<String, dynamic> style;

  /// Sprite id → upstream base URL (no extension) to download the
  /// atlas .json/.png (or @2x variants) from.
  final Map<String, String> spriteUpstreams;
}

String _rewriteORMURL(String value) {
  final parsed = Uri.tryParse(value);
  if (parsed == null) return value;
  var v = value;
  if (parsed.hasScheme) {
    if (parsed.host != 'openrailwaymap.app') return value;
    v = parsed.path;
    if (parsed.hasQuery) v += '?${parsed.query}';
  }
  if (!v.startsWith('/')) v = '/$v';
  return ormProxyPrefix + v.substring(1);
}

/// What rail's absoluteORMURL produces, against the upstream
/// origin instead of rail's host.
String _absoluteORMURL(String value) {
  if (value.startsWith(ormProxyPrefix)) {
    return '$_ormUpstreamOrigin/${value.substring(ormProxyPrefix.length)}';
  }
  return value;
}

void _rewriteORMURLs(dynamic node) {
  if (node is Map) {
    for (final key in node.keys.toList()) {
      final child = node[key];
      if (key == 'url') {
        if (child is String) {
          node[key] = _rewriteORMURL(child);
          continue;
        }
      }
      if (key == 'tiles') {
        if (child is List) {
          for (var i = 0; i < child.length; i++) {
            final tile = child[i];
            if (tile is String) child[i] = _rewriteORMURL(tile);
          }
          continue;
        }
      }
      _rewriteORMURLs(child);
    }
  } else if (node is List) {
    for (final child in node) {
      _rewriteORMURLs(child);
    }
  }
}

OrmRewriteResult rewriteORMStyle(Map<String, dynamic> style) {
  final spriteUpstreams = <String, String>{};
  final sources = style['sources'] as Map<String, dynamic>?;
  final layers = style['layers'] as List<dynamic>?;
  final zoomBySource = <String, (double, double)>{};
  if (layers != null) {
    for (final raw in layers) {
      final layer = raw as Map<String, dynamic>;
      final source = layer['source'] as String?;
      if (source == null || source.isEmpty) continue;
      var minZoom = 0.0;
      var maxZoom = 24.0;
      final minValue = layer['minzoom'];
      if (minValue is num) minZoom = minValue.toDouble();
      final maxValue = layer['maxzoom'];
      if (maxValue is num) maxZoom = maxValue.toDouble();
      final bounds = zoomBySource[source];
      if (bounds == null) {
        zoomBySource[source] = (minZoom, maxZoom);
      } else {
        zoomBySource[source] = (
          minZoom < bounds.$1 ? minZoom : bounds.$1,
          maxZoom > bounds.$2 ? maxZoom : bounds.$2,
        );
      }
    }
  }
  // Keep the railway style as an overlay and point all its vector
  // sources at the single PMTiles archive. Terrain and historical
  // layers are unrelated.
  final removed = <String>{};
  if (sources != null) {
    for (final name in sources.keys.toList()) {
      final source = sources[name] as Map<String, dynamic>;
      if (name == 'dem' || name == 'openhistoricalmap') {
        sources.remove(name);
        removed.add(name);
        continue;
      }
      if (source['type'] == 'vector') {
        source.remove('tiles');
        source['url'] = ormPMTilesURL;
        source.remove('minzoom');
        source.remove('maxzoom');
        continue;
      }
      final tileJSONURL = source['url'];
      if (tileJSONURL is String) {
        final proxyURL = _rewriteORMURL(tileJSONURL);
        if (proxyURL.startsWith(ormProxyPrefix)) {
          source.remove('url');
          final trimmed = proxyURL.endsWith('/')
              ? proxyURL.substring(0, proxyURL.length - 1)
              : proxyURL;
          final tileURL = '$trimmed/{z}/{x}/{y}';
          source['tiles'] = [_absoluteORMURL(tileURL)];
          final bounds = zoomBySource[name];
          if (bounds != null) {
            source['minzoom'] = bounds.$1;
            source['maxzoom'] = bounds.$2;
          }
        }
      }
      _rewriteORMURLs(source);
    }
  }
  if (layers != null && layers.isNotEmpty) {
    final kept = <dynamic>[];
    for (final raw in layers) {
      final layer = raw as Map<String, dynamic>;
      final source = layer['source'] as String?;
      if (!removed.contains(source)) {
        kept.add(raw);
      }
    }
    style['layers'] = kept;
  }
  final glyphs = style['glyphs'];
  if (glyphs is String) {
    style['glyphs'] = _rewriteORMURL(glyphs);
  }
  String spriteSchemeURL(String rawURL, String id) {
    final upstream = _absoluteORMURL(_rewriteORMURL(rawURL));
    spriteUpstreams[id] = upstream;
    // The path segment matters: with a bare ormsprite://<id> the
    // GL JS sprite loader appends '/.json' instead of '.json'.
    return 'ormsprite://$id/sprite';
  }

  final sprite = style['sprite'];
  if (sprite is String) {
    // The frontend names a lone railway sprite 'orm' when it
    // merges sprite sets; use the same id here.
    style['sprite'] = spriteSchemeURL(sprite, 'orm');
  } else if (sprite is List) {
    for (final entry in sprite) {
      if (entry is Map<String, dynamic>) {
        final value = entry['url'];
        final id = entry['id'];
        if (value is String && id is String) {
          entry['url'] = spriteSchemeURL(value, id);
        }
      }
    }
  }
  return OrmRewriteResult(style, spriteUpstreams);
}
