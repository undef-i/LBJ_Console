import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'orm_style.dart';

/// A train label chip on the web map.
class WebMapChip {
  final String id;
  final LatLng position;
  final String label;

  const WebMapChip({
    required this.id,
    required this.position,
    required this.label,
  });
}

/// A round marker on the web map: a train glyph, or the user's
/// location glyph when [location] is true.
class WebMapDot {
  final LatLng position;
  final bool location;

  const WebMapDot({required this.position, this.location = false});
}

/// A tap target: tapping within 28 screen px of [position] reports
/// [id] as a chip tap.
class WebMapHit {
  final String id;
  final LatLng position;

  const WebMapHit({required this.id, required this.position});
}

/// Drives one [WebMapView]. Calls made before the page reports
/// ready are queued and flushed in order once it does.
class WebMapController {
  WebViewController? _webView;
  bool _ready = false;
  final List<String> _pending = [];

  void _attach(WebViewController webView) => _webView = webView;

  void _markReady() {
    _ready = true;
    final queued = List<String>.of(_pending);
    _pending.clear();
    for (final js in queued) {
      _webView?.runJavaScript(js);
    }
  }

  void _run(String js) {
    if (_ready && _webView != null) {
      _webView!.runJavaScript(js);
    } else {
      _pending.add(js);
    }
  }

  void setData({
    List<List<LatLng>> lines = const [],
    List<WebMapChip> chips = const [],
    List<WebMapDot> dots = const [],
    List<WebMapHit> hits = const [],
  }) {
    final payload = <String, dynamic>{
      'lines': [
        for (final line in lines)
          [for (final point in line) [point.longitude, point.latitude]],
      ],
      'chips': [
        for (final chip in chips)
          {
            'id': chip.id,
            'lng': chip.position.longitude,
            'lat': chip.position.latitude,
            'label': chip.label,
          },
      ],
      'dots': [
        for (final dot in dots)
          {
            'lng': dot.position.longitude,
            'lat': dot.position.latitude,
            'kind': dot.location ? 'location' : 'train',
          },
      ],
      'hits': [
        for (final hit in hits)
          {
            'id': hit.id,
            'lng': hit.position.longitude,
            'lat': hit.position.latitude,
          },
      ],
    };
    _run('LbjSetData(${jsonEncode(payload)})');
  }

  void moveTo(LatLng center, double zoom, {double? bearing}) {
    final b = bearing == null ? 'null' : '$bearing';
    _run('LbjMoveTo(${center.longitude}, ${center.latitude}, $zoom, $b)');
  }

  void fitBounds(
    List<LatLng> points, {
    required double padding,
    required double maxZoom,
  }) {
    final pts = [
      for (final point in points) [point.longitude, point.latitude],
    ];
    _run('LbjFitBounds(${jsonEncode(pts)}, $padding, $maxZoom)');
  }

  void setOrm(bool visible) => _run('LbjSetOrm($visible)');

  void setTheme(bool dark) => _run('LbjSetTheme($dark)');
}

/// The map itself: a WebView running the bundled MapLibre GL JS
/// page (assets/map/map.html), which composes the basemap and the
/// OpenRailwayMap overlay exactly as rail.nedifinita.com does: the
/// railway style is preprocessed by the Dart port of rail's backend
/// rewrite (orm_style.dart, validated against rail's live
/// /api/map/orm-style-v2) and merged with the OpenFreeMap liberty
/// basemap by the page's port of rail's frontend combine. The style
/// document and the ORM sprite atlases are fetched in Dart and
/// handed to the page because openrailwaymap.app serves no CORS
/// headers for a WebView origin to fetch them directly.
///
/// A WebView is a platform view, invisible to the glass capture
/// replay, so the page exports its settled canvas and the bytes
/// are kept as an image layer directly beneath the WebView:
/// floating glass samples the map itself instead of the black the
/// platform view leaves in the layer tree. Exports flow for the
/// whole flight, not only at rest, and between exports the page
/// streams the camera on every move so the underlay is
/// transformed by the same pan and zoom: the glass keeps sampling
/// the map where it is now, in content and in position alike.
class WebMapView extends StatefulWidget {
  final WebMapController controller;
  final LatLng initialCenter;
  final double initialZoom;
  final double initialBearing;
  final double minZoom;
  final double maxZoom;
  final bool interactive;

  /// Whether this map carries the OpenRailwayMap overlay at all.
  final bool orm;

  /// The overlay's initial visibility.
  final bool ormVisible;
  final bool dark;
  final VoidCallback? onReady;
  final VoidCallback? onError;
  final void Function(LatLng center, double zoom, double bearing)?
      onCameraIdle;
  final void Function(String id)? onChipTap;
  final void Function(LatLng point)? onTap;

  const WebMapView({
    super.key,
    required this.controller,
    required this.initialCenter,
    required this.initialZoom,
    this.initialBearing = 0,
    this.minZoom = 2,
    this.maxZoom = 18,
    this.interactive = true,
    this.orm = false,
    this.ormVisible = true,
    this.dark = false,
    this.onReady,
    this.onError,
    this.onCameraIdle,
    this.onChipTap,
    this.onTap,
  });

  @override
  State<WebMapView> createState() => _WebMapViewState();
}

/// The preprocessed railway style plus its sprite atlases.
class _OrmData {
  _OrmData(this.style, this.sprites);

  final Map<String, dynamic> style;

  /// Sprite id → {'json': base64, 'png': base64}, one density set
  /// (the page's protocol handler answers every density suffix
  /// with it).
  final Map<String, Map<String, String>> sprites;
}

class _WebMapViewState extends State<WebMapView> {
  late final WebViewController _webView;
  Uint8List? _snapshotBytes;
  // The camera the current snapshot was exported at, and the
  // latest camera the page has streamed; the underlay's transform
  // is the pan/zoom from the first to the second.
  double _snapLng = 0;
  double _snapLat = 0;
  double _snapZoom = 0;
  double _curLng = 0;
  double _curLat = 0;
  double _curZoom = 0;

  static Future<_OrmData?>? _ormDataFuture;

  // Fetched once per app run and shared by every map that carries
  // the overlay.
  static Future<_OrmData?> _ormData() {
    return _ormDataFuture ??= () async {
      final raw = await _ormGet(
        Uri.parse('https://openrailwaymap.app/style.json'),
      );
      if (raw == null) return null;
      final Map<String, dynamic> styleJson;
      try {
        styleJson = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
      } catch (_) {
        return null;
      }
      final result = rewriteORMStyle(styleJson);
      final style = result.style;
      final sprites = <String, Map<String, String>>{};
      final failedIds = <String>[];
      for (final entry in result.spriteUpstreams.entries) {
        final files = await _ormSpriteFiles(entry.value);
        if (files == null) {
          failedIds.add(entry.key);
        } else {
          sprites[entry.key] = files;
        }
      }
      if (failedIds.isNotEmpty) {
        // An atlas that could not be downloaded leaves the style
        // rather than pointing the page at bytes it does not have.
        final sprite = style['sprite'];
        if (sprite is String) {
          style.remove('sprite');
        } else if (sprite is List) {
          sprite.removeWhere(
            (entry) => entry is Map && failedIds.contains(entry['id']),
          );
          if (sprite.isEmpty) style.remove('sprite');
        }
      }
      return _OrmData(style, sprites);
    }();
  }

  static Future<Map<String, String>?> _ormSpriteFiles(
    String upstreamBase,
  ) async {
    for (final suffix in ['@2x', '']) {
      final json = await _ormGet(Uri.parse('$upstreamBase$suffix.json'));
      if (json == null) continue;
      final png = await _ormGet(Uri.parse('$upstreamBase$suffix.png'));
      if (png == null) continue;
      return {'json': base64Encode(json), 'png': base64Encode(png)};
    }
    return null;
  }

  // Mirrors rail's ormGet: the same client headers, three
  // attempts, retries only on the statuses rail retries.
  static Future<List<int>?> _ormGet(Uri uri) async {
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
            return await response
                .fold<List<int>>(<int>[], (acc, chunk) {
                  acc.addAll(chunk);
                  return acc;
                })
                .timeout(const Duration(seconds: 15));
          }
          if (!_retryableOrmStatus(response.statusCode) || attempt == 2) {
            return null;
          }
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

  static bool _retryableOrmStatus(int status) =>
      status == 408 ||
      status == 500 ||
      status == 502 ||
      status == 503 ||
      status == 504 ||
      (status >= 520 && status <= 524);

  @override
  void initState() {
    super.initState();
    _snapLng = _curLng = widget.initialCenter.longitude;
    _snapLat = _curLat = widget.initialCenter.latitude;
    _snapZoom = _curZoom = widget.initialZoom;
    _webView = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFCCCCCC))
      ..addJavaScriptChannel('LbjBridge', onMessageReceived: _onBridgeMessage)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _initPage(),
          onWebResourceError: (error) {
            if (error.isForMainFrame == true) widget.onError?.call();
          },
        ),
      )
      ..loadFlutterAsset('assets/map/map.html');
    widget.controller._attach(_webView);
  }

  Future<void> _initPage() async {
    _OrmData? ormData;
    if (widget.orm) {
      ormData = await _ormData();
    }
    if (!mounted) return;
    final init = <String, dynamic>{
      'center': [widget.initialCenter.longitude, widget.initialCenter.latitude],
      'zoom': widget.initialZoom,
      'bearing': widget.initialBearing,
      'minZoom': widget.minZoom,
      'maxZoom': widget.maxZoom,
      'interactive': widget.interactive,
      'orm': widget.ormVisible,
      'dark': widget.dark,
      'ormStyle': ormData?.style,
      'ormSprites': ormData?.sprites ?? const {},
    };
    await _webView.runJavaScript('LbjInit(${jsonEncode(init)})');
  }

  void _onBridgeMessage(JavaScriptMessage message) {
    final decoded = jsonDecode(message.message);
    if (decoded is! Map<String, dynamic>) return;
    switch (decoded['t']) {
      case 'ready':
        widget.controller._markReady();
        widget.onReady?.call();
      case 'error':
        widget.onError?.call();
      case 'camera':
        _curLng = (decoded['lng'] as num).toDouble();
        _curLat = (decoded['lat'] as num).toDouble();
        _curZoom = (decoded['zoom'] as num).toDouble();
        widget.onCameraIdle?.call(
          LatLng(_curLat, _curLng),
          _curZoom,
          (decoded['bearing'] as num).toDouble(),
        );
      case 'move':
        if (!mounted) return;
        setState(() {
          _curLng = (decoded['lng'] as num).toDouble();
          _curLat = (decoded['lat'] as num).toDouble();
          _curZoom = (decoded['zoom'] as num).toDouble();
        });
      case 'snapshot':
        final data = decoded['data'] as String?;
        if (data == null) return;
        final comma = data.indexOf(',');
        if (comma < 0) return;
        try {
          final bytes = base64Decode(data.substring(comma + 1));
          if (mounted && bytes.isNotEmpty) {
            setState(() {
              _snapshotBytes = bytes;
              _snapLng = (decoded['lng'] as num).toDouble();
              _snapLat = (decoded['lat'] as num).toDouble();
              _snapZoom = (decoded['zoom'] as num).toDouble();
            });
          }
        } catch (_) {}
      case 'chipTap':
        widget.onChipTap?.call(decoded['id'] as String);
      case 'tap':
        widget.onTap?.call(
          LatLng(
            (decoded['lat'] as num).toDouble(),
            (decoded['lng'] as num).toDouble(),
          ),
        );
    }
  }

  // Web Mercator world pixels at [zoom], the plane both the
  // snapshot's camera and the live camera are projected onto.
  static Offset _worldPx(double lng, double lat, double zoom) {
    final world = 512.0 * math.pow(2.0, zoom).toDouble();
    final x = (lng + 180.0) / 360.0 * world;
    final phi = lat * math.pi / 180.0;
    final y =
        (1.0 - math.log(math.tan(phi) + 1.0 / math.cos(phi)) / math.pi) /
        2.0 *
        world;
    return Offset(x, y);
  }

  // The affine that carries the snapshot's frame onto the live
  // camera's: a point of the snapshot lands where the same world
  // point sits on screen now. Both centers are projected at the
  // snapshot's zoom, so the translation is k times their world
  // offset plus the recentering of the scale itself.
  Matrix4 _underlayMatrix(Size viewport) {
    final k = math.pow(2.0, _curZoom - _snapZoom).toDouble();
    final snapCenter = _worldPx(_snapLng, _snapLat, _snapZoom);
    final curCenter = _worldPx(_curLng, _curLat, _snapZoom);
    final tx = k * (snapCenter.dx - curCenter.dx) + (1 - k) * viewport.width / 2;
    final ty =
        k * (snapCenter.dy - curCenter.dy) + (1 - k) * viewport.height / 2;
    return Matrix4.identity()
      ..translateByDouble(tx, ty, 0, 1)
      ..scaleByDouble(k, k, 1, 1);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        return Stack(
          children: [
            if (_snapshotBytes != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: Transform(
                    transform: _underlayMatrix(viewport),
                    child: Image.memory(
                      _snapshotBytes!,
                      fit: BoxFit.fill,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
              ),
            Positioned.fill(
              child: WebViewWidget.fromPlatformCreationParams(
                params: Platform.isAndroid
                    ? AndroidWebViewWidgetCreationParams(
                        controller: _webView.platform,
                        displayWithHybridComposition: false,
                        gestureRecognizers: widget.interactive
                            ? {
                                Factory<OneSequenceGestureRecognizer>(
                                  () => EagerGestureRecognizer(),
                                ),
                              }
                            : const {},
                      )
                    : PlatformWebViewWidgetCreationParams(
                        controller: _webView.platform,
                        gestureRecognizers: widget.interactive
                            ? {
                                Factory<OneSequenceGestureRecognizer>(
                                  () => EagerGestureRecognizer(),
                                ),
                              }
                            : const {},
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}
