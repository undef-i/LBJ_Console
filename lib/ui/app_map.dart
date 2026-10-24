import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'native_map.dart';
import 'web_map.dart';

enum MapEngine { vector, raster, native }

class MapEngineStore extends ValueNotifier<MapEngine> {
  MapEngineStore._() : super(MapEngine.vector);

  static final MapEngineStore instance = MapEngineStore._();

  void applySettings(Map<String, dynamic>? settings) {
    final name = settings?['mapEngine'] as String?;
    value = MapEngine.values.firstWhere(
      (e) => e.name == name,
      orElse: () => MapEngine.vector,
    );
  }
}

class _RasterState {
  List<List<LatLng>> lines = const [];
  List<WebMapChip> chips = const [];
  List<WebMapDot> dots = const [];
  List<WebMapHit> hits = const [];
  bool ormVisible = true;
  final ValueNotifier<int> change = ValueNotifier(0);

  void bump() => change.value++;
}

class AppMapController {
  final WebMapController web = WebMapController();
  final NativeMapController native = NativeMapController();
  final NativeMapState nativeState = NativeMapState();
  final _RasterState raster = _RasterState();

  MapController? _rasterMap;
  bool _rasterReady = false;
  final List<void Function(MapController)> _rasterPending = [];

  void _attachRaster(MapController map) {
    _rasterMap = map;
    _rasterReady = false;
  }

  void _markRasterReady() {
    _rasterReady = true;
    final queued = List<void Function(MapController)>.of(_rasterPending);
    _rasterPending.clear();
    final map = _rasterMap;
    if (map == null) {
      return;
    }
    for (final op in queued) {
      op(map);
    }
  }

  void _detachRaster(MapController map) {
    if (identical(_rasterMap, map)) {
      _rasterMap = null;
      _rasterReady = false;
      _rasterPending.clear();
    }
  }

  void _rasterRun(void Function(MapController) op) {
    final map = _rasterMap;
    if (_rasterReady && map != null) {
      op(map);
    } else {
      _rasterPending.add(op);
    }
  }

  void setData({
    List<List<LatLng>> lines = const [],
    List<WebMapChip> chips = const [],
    List<WebMapDot> dots = const [],
    List<WebMapHit> hits = const [],
  }) {
    web.setData(lines: lines, chips: chips, dots: dots, hits: hits);
    native.setLines(lines);
    nativeState.lines = lines;
    nativeState.chips = chips;
    nativeState.dots = dots;
    nativeState.hits = hits;
    nativeState.bump();
    raster.lines = lines;
    raster.chips = chips;
    raster.dots = dots;
    raster.hits = hits;
    raster.bump();
  }

  void moveTo(LatLng center, double zoom, {double? bearing}) {
    web.moveTo(center, zoom, bearing: bearing);
    native.moveTo(center, zoom, bearing: bearing);
    _rasterRun((map) {
      map.move(center, zoom);
      if (bearing != null) {
        map.rotate(bearing);
      }
    });
  }

  void fitBounds(
    List<LatLng> points, {
    required double padding,
    required double maxZoom,
  }) {
    web.fitBounds(points, padding: padding, maxZoom: maxZoom);
    native.fitBounds(points, padding: padding, maxZoom: maxZoom);
    if (points.isEmpty) {
      return;
    }
    _rasterRun((map) {
      map.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: EdgeInsets.all(padding),
          maxZoom: maxZoom,
        ),
      );
    });
  }

  void setOrm(bool visible) {
    web.setOrm(visible);
    nativeState.ormVisible = visible;
    nativeState.bump();
    raster.ormVisible = visible;
    raster.bump();
  }

  void setTheme(bool dark) {
    web.setTheme(dark);
    nativeState.dark = dark;
    nativeState.bump();
  }
}

class AppMapView extends StatelessWidget {
  final AppMapController controller;
  final LatLng initialCenter;
  final double initialZoom;
  final double initialBearing;
  final double minZoom;
  final double maxZoom;
  final bool interactive;
  final bool hybridComposition;
  final bool orm;
  final bool ormVisible;
  final bool dark;
  final VoidCallback? onReady;
  final VoidCallback? onError;
  final void Function(LatLng center, double zoom, double bearing)?
      onCameraIdle;
  final void Function(String id)? onChipTap;
  final void Function(LatLng point)? onTap;

  const AppMapView({
    super.key,
    required this.controller,
    required this.initialCenter,
    required this.initialZoom,
    this.initialBearing = 0,
    this.minZoom = 2,
    this.maxZoom = 18,
    this.interactive = true,
    this.hybridComposition = false,
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
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MapEngine>(
      valueListenable: MapEngineStore.instance,
      builder: (context, engine, _) {
        if (engine == MapEngine.native) {
          return NativeMapView(
            controller: controller.native,
            state: controller.nativeState,
            initialCenter: initialCenter,
            initialZoom: initialZoom,
            initialBearing: initialBearing,
            minZoom: minZoom,
            maxZoom: maxZoom,
            interactive: interactive,
            orm: orm,
            ormVisible: ormVisible,
            dark: dark,
            onReady: onReady,
            onError: onError,
            onCameraIdle: onCameraIdle,
            onChipTap: onChipTap,
            onTap: onTap,
          );
        }
        if (engine == MapEngine.raster) {
          return RasterMapView(
            controller: controller,
            initialCenter: initialCenter,
            initialZoom: initialZoom,
            initialBearing: initialBearing,
            minZoom: minZoom,
            maxZoom: maxZoom,
            interactive: interactive,
            orm: orm,
            ormVisible: ormVisible,
            onReady: onReady,
            onCameraIdle: onCameraIdle,
            onChipTap: onChipTap,
            onTap: onTap,
          );
        }
        return WebMapView(
          controller: controller.web,
          initialCenter: initialCenter,
          initialZoom: initialZoom,
          initialBearing: initialBearing,
          minZoom: minZoom,
          maxZoom: maxZoom,
          interactive: interactive,
          hybridComposition: hybridComposition,
          orm: orm,
          ormVisible: ormVisible,
          dark: dark,
          onReady: onReady,
          onError: onError,
          onCameraIdle: onCameraIdle,
          onChipTap: onChipTap,
          onTap: onTap,
        );
      },
    );
  }
}

class RasterMapView extends StatefulWidget {
  final AppMapController controller;
  final LatLng initialCenter;
  final double initialZoom;
  final double initialBearing;
  final double minZoom;
  final double maxZoom;
  final bool interactive;
  final bool orm;
  final bool ormVisible;
  final VoidCallback? onReady;
  final void Function(LatLng center, double zoom, double bearing)?
      onCameraIdle;
  final void Function(String id)? onChipTap;
  final void Function(LatLng point)? onTap;

  const RasterMapView({
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
    this.onReady,
    this.onCameraIdle,
    this.onChipTap,
    this.onTap,
  });

  @override
  State<RasterMapView> createState() => _RasterMapViewState();
}

class _RasterMapViewState extends State<RasterMapView> {
  late final MapController _map = MapController();
  Timer? _idleTimer;

  @override
  void initState() {
    super.initState();
    widget.controller.raster.ormVisible = widget.ormVisible;
    widget.controller._attachRaster(_map);
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    widget.controller._detachRaster(_map);
    _map.dispose();
    super.dispose();
  }

  void _handleReady() {
    widget.controller._markRasterReady();
    widget.onReady?.call();
  }

  void _handleTap(TapPosition tapPosition, LatLng point) {
    final hits = widget.controller.raster.hits;
    if (hits.isNotEmpty && widget.onChipTap != null) {
      try {
        final camera = _map.camera;
        final tapPoint = camera.latLngToScreenOffset(point);
        String? bestId;
        var bestDistance = 28.0;
        for (final hit in hits) {
          final hitPoint = camera.latLngToScreenOffset(hit.position);
          final distance = (hitPoint - tapPoint).distance;
          if (distance <= bestDistance) {
            bestDistance = distance;
            bestId = hit.id;
          }
        }
        if (bestId != null) {
          widget.onChipTap!.call(bestId);
          return;
        }
      } catch (_) {}
    }
    widget.onTap?.call(point);
  }

  void _handlePositionChanged(MapCamera camera, bool hasGesture) {
    final callback = widget.onCameraIdle;
    if (callback == null) {
      return;
    }
    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(milliseconds: 350), () {
      callback(camera.center, camera.zoom, camera.rotation);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.raster;
    return ValueListenableBuilder<int>(
      valueListenable: state.change,
      builder: (context, _, _) {
        return FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: widget.initialCenter,
            initialZoom: widget.initialZoom,
            initialRotation: widget.initialBearing,
            minZoom: widget.minZoom,
            maxZoom: widget.maxZoom,
            interactionOptions: InteractionOptions(
              flags: widget.interactive
                  ? InteractiveFlag.all
                  : InteractiveFlag.none,
            ),
            onMapReady: _handleReady,
            onTap: _handleTap,
            onPositionChanged: _handlePositionChanged,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'org.noxylva.lbjconsole.flutter',
            ),
            if (widget.orm && state.ormVisible)
              TileLayer(
                urlTemplate:
                    'https://{s}.tiles.openrailwaymap.org/standard/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
                userAgentPackageName: 'org.noxylva.lbjconsole.flutter',
              ),
            PolylineLayer(
              polylines: [
                for (final line in state.lines)
                  Polyline(
                    points: line,
                    strokeWidth: 4,
                    color: Colors.black,
                  ),
              ],
            ),
            MarkerLayer(
              markers: [
                for (final dot in state.dots)
                  Marker(
                    point: dot.position,
                    width: 26,
                    height: 26,
                    child: dot.location
                        ? const _LocationDot()
                        : const _TrainDot(),
                  ),
                for (final chip in state.chips)
                  Marker(
                    point: chip.position,
                    width: 30 + chip.label.length * 9,
                    height: 26,
                    child: GestureDetector(
                      onTap: () => widget.onChipTap?.call(chip.id),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
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
              ],
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
