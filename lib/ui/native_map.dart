import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre/maplibre.dart' as ml;

import 'native_style.dart';
import 'web_map.dart';

class NativeMapState {
  List<List<LatLng>> lines = const [];
  List<WebMapChip> chips = const [];
  List<WebMapDot> dots = const [];
  List<WebMapHit> hits = const [];
  bool ormVisible = true;
  bool dark = false;
  final ValueNotifier<int> change = ValueNotifier(0);

  void bump() => change.value++;
}

class NativeMapController {
  ml.MapController? _map;
  ml.StyleController? _style;
  bool _ready = false;
  final List<void Function(ml.MapController)> _pending = [];
  String _linesData = '{"type":"FeatureCollection","features":[]}';

  void _attach(ml.MapController map) => _map = map;

  void _detach(ml.MapController map) {
    if (identical(_map, map)) {
      _map = null;
      _style = null;
      _ready = false;
      _pending.clear();
    }
  }

  void _onStyleReloading() => _style = null;

  Future<void> _onStyleLoaded(ml.StyleController style) async {
    _style = style;
    await style.addSource(
      ml.GeoJsonSource(id: 'lbj-lines', data: _linesData),
    );
    await style.addLayer(
      const ml.LineStyleLayer(
        id: 'lbj-lines',
        sourceId: 'lbj-lines',
        layout: {'line-cap': 'round', 'line-join': 'round'},
        paint: {'line-color': '#000000', 'line-width': 4},
      ),
    );
    if (!_ready) {
      _ready = true;
      final map = _map;
      if (map != null) {
        final queued = List<void Function(ml.MapController)>.of(_pending);
        _pending.clear();
        for (final op in queued) {
          op(map);
        }
      }
    }
  }

  void _run(void Function(ml.MapController) op) {
    final map = _map;
    if (_ready && map != null) {
      op(map);
    } else {
      _pending.add(op);
    }
  }

  void setLines(List<List<LatLng>> lines) {
    _linesData = jsonEncode({
      'type': 'FeatureCollection',
      'features': [
        for (final line in lines)
          {
            'type': 'Feature',
            'geometry': {
              'type': 'LineString',
              'coordinates': [
                for (final point in line) [point.longitude, point.latitude],
              ],
            },
            'properties': <String, dynamic>{},
          },
      ],
    });
    final style = _style;
    if (_ready && style != null) {
      style.updateGeoJsonSource(id: 'lbj-lines', data: _linesData);
    }
  }

  void moveTo(LatLng center, double zoom, {double? bearing}) {
    _run((map) {
      map.moveCamera(
        center: ml.Geographic(lon: center.longitude, lat: center.latitude),
        zoom: zoom,
        bearing: bearing,
      );
    });
  }

  void fitBounds(
    List<LatLng> points, {
    required double padding,
    required double maxZoom,
  }) {
    if (points.isEmpty) return;
    _run((map) async {
      await map.fitBounds(
        bounds: ml.LngLatBounds.fromPoints([
          for (final point in points)
            ml.Geographic(lon: point.longitude, lat: point.latitude),
        ]),
        padding: EdgeInsets.all(padding),
      );
      if (map.getCamera().zoom > maxZoom) {
        map.moveCamera(zoom: maxZoom);
      }
    });
  }
}

class NativeMapView extends StatefulWidget {
  final NativeMapController controller;
  final NativeMapState state;
  final LatLng initialCenter;
  final double initialZoom;
  final double initialBearing;
  final double minZoom;
  final double maxZoom;
  final bool interactive;
  final bool orm;
  final bool ormVisible;
  final bool dark;
  final VoidCallback? onReady;
  final VoidCallback? onError;
  final void Function(LatLng center, double zoom, double bearing)?
      onCameraIdle;
  final void Function(String id)? onChipTap;
  final void Function(LatLng point)? onTap;

  const NativeMapView({
    super.key,
    required this.controller,
    required this.state,
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
  State<NativeMapView> createState() => _NativeMapViewState();
}

class _NativeMapViewState extends State<NativeMapView> {
  late final Future<String?> _initialStyle;
  ml.MapController? _plugin;
  bool _readyFired = false;
  bool _errorFired = false;
  late bool _appliedOrmVisible;
  late bool _appliedDark;
  Future<void> _swapChain = Future.value();

  @override
  void initState() {
    super.initState();
    final state = widget.state;
    state.ormVisible = widget.ormVisible;
    state.dark = widget.dark;
    _appliedOrmVisible = widget.ormVisible;
    _appliedDark = widget.dark;
    _initialStyle = buildNativeMapStyle(
      orm: widget.orm && widget.ormVisible,
      dark: widget.dark,
    );
    state.change.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    widget.state.change.removeListener(_onStateChanged);
    final plugin = _plugin;
    if (plugin != null) widget.controller._detach(plugin);
    super.dispose();
  }

  void _onStateChanged() {
    if (!widget.orm) return;
    final state = widget.state;
    if (state.ormVisible == _appliedOrmVisible &&
        state.dark == _appliedDark) {
      return;
    }
    final orm = state.ormVisible;
    final dark = state.dark;
    _swapChain = _swapChain.then((_) async {
      final json = await buildNativeMapStyle(orm: orm, dark: dark);
      if (!mounted || json == null) return;
      _appliedOrmVisible = orm;
      _appliedDark = dark;
      widget.controller._onStyleReloading();
      _plugin?.setStyle(json);
    });
  }

  void _onEvent(ml.MapEvent event) {
    switch (event) {
      case ml.MapEventClick(:final point, :final screenPoint):
        _handleTap(point, screenPoint);
      case ml.MapEventCameraIdle():
        _handleCameraIdle();
      default:
        break;
    }
  }

  void _handleTap(ml.Geographic point, Offset screenPoint) {
    final hits = widget.state.hits;
    final plugin = _plugin;
    if (hits.isNotEmpty && widget.onChipTap != null && plugin != null) {
      final offsets = plugin.toScreenLocations([
        for (final hit in hits)
          ml.Geographic(lon: hit.position.longitude, lat: hit.position.latitude),
      ]);
      String? bestId;
      var bestDistance = 28.0;
      for (var i = 0; i < hits.length; i++) {
        final distance = (offsets[i] - screenPoint).distance;
        if (distance <= bestDistance) {
          bestDistance = distance;
          bestId = hits[i].id;
        }
      }
      if (bestId != null) {
        widget.onChipTap!.call(bestId);
        return;
      }
    }
    widget.onTap?.call(LatLng(point.lat, point.lon));
  }

  void _handleCameraIdle() {
    final callback = widget.onCameraIdle;
    final plugin = _plugin;
    if (callback == null || plugin == null) return;
    final camera = plugin.getCamera();
    callback(
      LatLng(camera.center.lat, camera.center.lon),
      camera.zoom,
      camera.bearing,
    );
  }

  List<ml.Marker> _markers() {
    final state = widget.state;
    return [
      for (final dot in state.dots)
        ml.Marker(
          point: ml.Geographic(
            lon: dot.position.longitude,
            lat: dot.position.latitude,
          ),
          size: const Size(26, 26),
          child: IgnorePointer(
            child: dot.location ? const _LocationDot() : const _TrainDot(),
          ),
        ),
      for (final chip in state.chips)
        ml.Marker(
          point: ml.Geographic(
            lon: chip.position.longitude,
            lat: chip.position.latitude,
          ),
          size: Size(30 + chip.label.length * 9.0, 26),
          child: GestureDetector(
            onTap: () => widget.onChipTap?.call(chip.id),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Text(
                  chip.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _initialStyle,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const ColoredBox(color: Color(0xFFCCCCCC));
        }
        final style = snapshot.data;
        if (style == null) {
          if (!_errorFired) {
            _errorFired = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              widget.onError?.call();
            });
          }
          return const ColoredBox(color: Color(0xFFCCCCCC));
        }
        return ml.MapLibreMap(
          options: ml.MapOptions(
            initStyle: style,
            initCenter: ml.Geographic(
              lon: widget.initialCenter.longitude,
              lat: widget.initialCenter.latitude,
            ),
            initZoom: widget.initialZoom,
            initBearing: widget.initialBearing,
            minZoom: widget.minZoom,
            maxZoom: widget.maxZoom,
            minPitch: 0,
            maxPitch: 0,
            gestures: widget.interactive
                ? const ml.MapGestures.all(pitch: false)
                : const ml.MapGestures.none(),
          ),
          gestureRecognizers: widget.interactive
              ? {
                  Factory<OneSequenceGestureRecognizer>(
                    () => EagerGestureRecognizer(),
                  ),
                }
              : null,
          onMapCreated: (controller) {
            _plugin = controller;
            widget.controller._attach(controller);
          },
          onStyleLoaded: (style) async {
            await widget.controller._onStyleLoaded(style);
            if (!_readyFired) {
              _readyFired = true;
              widget.onReady?.call();
            }
          },
          onEvent: _onEvent,
          children: [
            ValueListenableBuilder<int>(
              valueListenable: widget.state.change,
              builder: (context, _, _) {
                return ml.WidgetLayer(
                  allowInteraction: true,
                  markers: _markers(),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _TrainDot extends StatelessWidget {
  const _TrainDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.black,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.train, color: Colors.white, size: 15),
    );
  }
}

class _LocationDot extends StatelessWidget {
  const _LocationDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E88E5),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 4),
        ],
      ),
    );
  }
}
