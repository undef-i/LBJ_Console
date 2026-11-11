import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'native_map.dart';

enum MapEngine { raster, native }

class MapEngineStore extends ValueNotifier<MapEngine> {
  MapEngineStore._() : super(MapEngine.native);

  static final MapEngineStore instance = MapEngineStore._();

  void applySettings(Map<String, dynamic>? settings) {
    final name = settings?['mapEngine'] as String?;
    value = MapEngine.values.firstWhere(
      (e) => e.name == name,
      orElse: () => MapEngine.native,
    );
  }
}

LatLng wgs84ToGcj02(LatLng point) {
  final lat = point.latitude;
  final lng = point.longitude;
  if (lng < 72.004 || lng > 137.8347 || lat < 0.8293 || lat > 55.8271) {
    return point;
  }
  var dLat = _gcjDeltaLat(lng - 105.0, lat - 35.0);
  var dLng = _gcjDeltaLng(lng - 105.0, lat - 35.0);
  final radLat = lat / 180.0 * math.pi;
  var magic = math.sin(radLat);
  magic = 1 - 0.00669342162296594323 * magic * magic;
  final sqrtMagic = math.sqrt(magic);
  dLat =
      (dLat * 180.0) /
      ((6378245.0 * (1 - 0.00669342162296594323)) /
          (magic * sqrtMagic) *
          math.pi);
  dLng = (dLng * 180.0) / (6378245.0 / sqrtMagic * math.cos(radLat) * math.pi);
  return LatLng(lat + dLat, lng + dLng);
}

double _gcjDeltaLat(double x, double y) {
  var ret =
      -100.0 +
      2.0 * x +
      3.0 * y +
      0.2 * y * y +
      0.1 * x * y +
      0.2 * math.sqrt(x.abs());
  ret +=
      (20.0 * math.sin(6.0 * x * math.pi) +
          20.0 * math.sin(2.0 * x * math.pi)) *
      2.0 /
      3.0;
  ret +=
      (20.0 * math.sin(y * math.pi) + 40.0 * math.sin(y / 3.0 * math.pi)) *
      2.0 /
      3.0;
  ret +=
      (160.0 * math.sin(y / 12.0 * math.pi) +
          320.0 * math.sin(y * math.pi / 30.0)) *
      2.0 /
      3.0;
  return ret;
}

double _gcjDeltaLng(double x, double y) {
  var ret =
      300.0 +
      x +
      2.0 * y +
      0.1 * x * x +
      0.1 * x * y +
      0.1 * math.sqrt(x.abs());
  ret +=
      (20.0 * math.sin(6.0 * x * math.pi) +
          20.0 * math.sin(2.0 * x * math.pi)) *
      2.0 /
      3.0;
  ret +=
      (20.0 * math.sin(x * math.pi) + 40.0 * math.sin(x / 3.0 * math.pi)) *
      2.0 /
      3.0;
  ret +=
      (150.0 * math.sin(x / 12.0 * math.pi) +
          300.0 * math.sin(x / 30.0 * math.pi)) *
      2.0 /
      3.0;
  return ret;
}

LatLng gcj02ToWgs84(LatLng point) {
  final lat = point.latitude;
  final lng = point.longitude;
  if (lng < 72.004 || lng > 137.8347 || lat < 0.8293 || lat > 55.8271) {
    return point;
  }
  var guess = point;
  for (var i = 0; i < 3; i++) {
    final converted = wgs84ToGcj02(guess);
    guess = LatLng(
      guess.latitude + (lat - converted.latitude),
      guess.longitude + (lng - converted.longitude),
    );
  }
  return guess;
}

class RasterTileSource {
  final String template;
  final List<String> subdomains;
  final bool tms;
  final bool gcj;

  const RasterTileSource(
    this.template, {
    this.subdomains = const [],
    this.tms = false,
    this.gcj = false,
  });
}

const rasterBasePresets = <String, (String, RasterTileSource)>{
  'osm': (
    'OpenStreetMap',
    RasterTileSource('https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
  ),
  'gaode': (
    '高德地图',
    RasterTileSource(
      'https://webrd0{s}.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}',
      subdomains: ['1', '2', '3', '4'],
      gcj: true,
    ),
  ),
  'gaodeSat': (
    '高德影像',
    RasterTileSource(
      'https://webst0{s}.is.autonavi.com/appmaptile?style=6&x={x}&y={y}&z={z}',
      subdomains: ['1', '2', '3', '4'],
      gcj: true,
    ),
  ),
  'tencent': (
    '腾讯地图',
    RasterTileSource(
      'https://rt{s}.map.gtimg.com/tile?z={z}&x={x}&y={y}&type=vector&styleid=1',
      subdomains: ['0', '1', '2', '3'],
      tms: true,
      gcj: true,
    ),
  ),
};

const rasterRailPresets = <String, (String, RasterTileSource)>{
  'orm': (
    'ORM',
    RasterTileSource(
      'https://{s}.tiles.openrailwaymap.org/standard/{z}/{x}/{y}.png',
      subdomains: ['a', 'b', 'c'],
    ),
  ),
  'ormMaxspeed': (
    'ORM 最大速度',
    RasterTileSource(
      'https://{s}.tiles.openrailwaymap.org/maxspeed/{z}/{x}/{y}.png',
      subdomains: ['a', 'b', 'c'],
    ),
  ),
  'ormSignals': (
    'ORM 信号',
    RasterTileSource(
      'https://{s}.tiles.openrailwaymap.org/signals/{z}/{x}/{y}.png',
      subdomains: ['a', 'b', 'c'],
    ),
  ),
};

class RasterMapConfig {
  final String baseSource;
  final String baseUrl;
  final bool baseGcj;
  final String railSource;
  final String railUrl;
  final bool railGcj;

  const RasterMapConfig({
    this.baseSource = 'osm',
    this.baseUrl = '',
    this.baseGcj = false,
    this.railSource = 'orm',
    this.railUrl = '',
    this.railGcj = false,
  });

  RasterTileSource get baseTile => baseSource == 'custom'
      ? RasterTileSource(baseUrl, gcj: baseGcj)
      : (rasterBasePresets[baseSource] ?? rasterBasePresets['osm']!).$2;

  RasterTileSource get railTile => railSource == 'custom'
      ? RasterTileSource(railUrl, gcj: railGcj)
      : (rasterRailPresets[railSource] ?? rasterRailPresets['orm']!).$2;

  bool get dataGcj => baseTile.gcj || railTile.gcj;
}

class RasterMapStore extends ValueNotifier<RasterMapConfig> {
  RasterMapStore._() : super(const RasterMapConfig());

  static final RasterMapStore instance = RasterMapStore._();

  void applySettings(Map<String, dynamic>? settings) {
    value = RasterMapConfig(
      baseSource: settings?['rasterBaseSource'] as String? ?? 'osm',
      baseUrl: settings?['rasterBaseUrl'] as String? ?? '',
      baseGcj: (settings?['rasterBaseGcj'] as int? ?? 0) == 1,
      railSource: settings?['rasterRailSource'] as String? ?? 'orm',
      railUrl: settings?['rasterRailUrl'] as String? ?? '',
      railGcj: (settings?['rasterRailGcj'] as int? ?? 0) == 1,
    );
  }
}

class RasterState {
  List<List<LatLng>> lines = const [];
  List<MapChip> chips = const [];
  List<MapDot> dots = const [];
  List<MapHit> hits = const [];
  bool ormVisible = true;
  final ValueNotifier<int> change = ValueNotifier(0);

  void bump() => change.value++;
}

class AppMapController {
  final NativeMapController native = NativeMapController();
  final NativeMapState nativeState = NativeMapState();
  final RasterState raster = RasterState();

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
    List<MapChip> chips = const [],
    List<MapDot> dots = const [],
    List<MapHit> hits = const [],
  }) {
    native.setLines(lines);
    nativeState.lines = lines;
    nativeState.chips = chips;
    nativeState.dots = dots;
    nativeState.hits = hits;
    nativeState.bump();
    _rawLines = lines;
    _rawChips = chips;
    _rawDots = dots;
    _rawHits = hits;
    _applyRaster();
  }

  List<List<LatLng>> _rawLines = const [];
  List<MapChip> _rawChips = const [];
  List<MapDot> _rawDots = const [];
  List<MapHit> _rawHits = const [];

  void _applyRaster() {
    final gcj = RasterMapStore.instance.value.dataGcj;
    raster.lines = gcj
        ? [
            for (final line in _rawLines)
              [for (final point in line) wgs84ToGcj02(point)],
          ]
        : _rawLines;
    raster.chips = gcj
        ? [
            for (final chip in _rawChips)
              MapChip(
                id: chip.id,
                position: wgs84ToGcj02(chip.position),
                label: chip.label,
              ),
          ]
        : _rawChips;
    raster.dots = gcj
        ? [
            for (final dot in _rawDots)
              MapDot(
                position: wgs84ToGcj02(dot.position),
                location: dot.location,
              ),
          ]
        : _rawDots;
    raster.hits = gcj
        ? [
            for (final hit in _rawHits)
              MapHit(id: hit.id, position: wgs84ToGcj02(hit.position)),
          ]
        : _rawHits;
    raster.bump();
  }

  void moveTo(LatLng center, double zoom, {double? bearing}) {
    native.moveTo(center, zoom, bearing: bearing);
    final rasterCenter = RasterMapStore.instance.value.dataGcj
        ? wgs84ToGcj02(center)
        : center;
    _rasterRun((map) {
      map.move(rasterCenter, zoom);
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
    native.fitBounds(points, padding: padding, maxZoom: maxZoom);
    if (points.isEmpty) {
      return;
    }
    final rasterPoints = RasterMapStore.instance.value.dataGcj
        ? [for (final point in points) wgs84ToGcj02(point)]
        : points;
    _rasterRun((map) {
      map.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(rasterPoints),
          padding: EdgeInsets.all(padding),
          maxZoom: maxZoom,
        ),
      );
    });
  }

  void setOrm(bool visible) {
    nativeState.ormVisible = visible;
    nativeState.bump();
    raster.ormVisible = visible;
    raster.bump();
  }

  void setTheme(bool dark) {
    nativeState.dark = dark;
    nativeState.bump();
  }
}

class AppMapView extends StatefulWidget {
  final AppMapController controller;
  final LatLng initialCenter;
  final double initialZoom;
  final double initialBearing;
  final double minZoom;
  final double maxZoom;
  final bool interactive;
  final bool orm;
  final bool ormVisible;
  final bool dark;
  final bool attribution;
  final VoidCallback? onReady;
  final VoidCallback? onError;
  final void Function(LatLng center, double zoom, double bearing)? onCameraIdle;
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
    this.orm = false,
    this.ormVisible = true,
    this.dark = false,
    this.attribution = false,
    this.onReady,
    this.onError,
    this.onCameraIdle,
    this.onChipTap,
    this.onTap,
  });

  @override
  State<AppMapView> createState() => _AppMapViewState();
}

class _AppMapViewState extends State<AppMapView> {
  MapEngine _engine = MapEngineStore.instance.value;
  bool _swapScheduled = false;

  @override
  void initState() {
    super.initState();
    MapEngineStore.instance.addListener(_onEngineChanged);
  }

  @override
  void dispose() {
    MapEngineStore.instance.removeListener(_onEngineChanged);
    super.dispose();
  }

  void _onEngineChanged() {
    if (_swapScheduled) return;
    _swapScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _swapScheduled = false;
      if (!mounted) return;
      setState(() => _engine = MapEngineStore.instance.value);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_engine == MapEngine.native) {
      return NativeMapView(
        controller: widget.controller.native,
        state: widget.controller.nativeState,
        initialCenter: widget.initialCenter,
        initialZoom: widget.initialZoom,
        initialBearing: widget.initialBearing,
        minZoom: widget.minZoom,
        maxZoom: widget.maxZoom,
        interactive: widget.interactive,
        orm: widget.orm,
        ormVisible: widget.ormVisible,
        dark: widget.dark,
        attribution: widget.attribution,
        onReady: widget.onReady,
        onError: widget.onError,
        onCameraIdle: widget.onCameraIdle,
        onChipTap: widget.onChipTap,
        onTap: widget.onTap,
      );
    }
    return RasterMapView(
      controller: widget.controller,
      initialCenter: widget.initialCenter,
      initialZoom: widget.initialZoom,
      initialBearing: widget.initialBearing,
      minZoom: widget.minZoom,
      maxZoom: widget.maxZoom,
      interactive: widget.interactive,
      orm: widget.orm,
      ormVisible: widget.ormVisible,
      attribution: widget.attribution,
      onReady: widget.onReady,
      onCameraIdle: widget.onCameraIdle,
      onChipTap: widget.onChipTap,
      onTap: widget.onTap,
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
  final bool attribution;
  final VoidCallback? onReady;
  final void Function(LatLng center, double zoom, double bearing)? onCameraIdle;
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
    this.attribution = false,
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
  bool _dataGcj = RasterMapStore.instance.value.dataGcj;

  @override
  void initState() {
    super.initState();
    widget.controller.raster.ormVisible = widget.ormVisible;
    widget.controller._attachRaster(_map);
    RasterMapStore.instance.addListener(_onRasterConfigChanged);
  }

  @override
  void dispose() {
    RasterMapStore.instance.removeListener(_onRasterConfigChanged);
    _idleTimer?.cancel();
    widget.controller._detachRaster(_map);
    _map.dispose();
    super.dispose();
  }

  void _onRasterConfigChanged() {
    widget.controller._applyRaster();
    final gcj = RasterMapStore.instance.value.dataGcj;
    if (gcj == _dataGcj) {
      return;
    }
    _dataGcj = gcj;
    try {
      final camera = _map.camera;
      final center = gcj
          ? wgs84ToGcj02(camera.center)
          : gcj02ToWgs84(camera.center);
      _map.move(center, camera.zoom);
    } catch (_) {}
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
    widget.onTap?.call(
      RasterMapStore.instance.value.dataGcj ? gcj02ToWgs84(point) : point,
    );
  }

  void _handlePositionChanged(MapCamera camera, bool hasGesture) {
    final callback = widget.onCameraIdle;
    if (callback == null) {
      return;
    }
    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(milliseconds: 350), () {
      callback(
        RasterMapStore.instance.value.dataGcj
            ? gcj02ToWgs84(camera.center)
            : camera.center,
        camera.zoom,
        camera.rotation,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.raster;
    return ValueListenableBuilder<RasterMapConfig>(
      valueListenable: RasterMapStore.instance,
      builder: (context, config, _) {
        return ValueListenableBuilder<int>(
          valueListenable: state.change,
          builder: (context, _, _) {
            return FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: config.dataGcj
                    ? wgs84ToGcj02(widget.initialCenter)
                    : widget.initialCenter,
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
                if (config.baseTile.template.isNotEmpty)
                  TileLayer(
                    urlTemplate: config.baseTile.template,
                    subdomains: config.baseTile.subdomains,
                    tms: config.baseTile.tms,
                    userAgentPackageName: 'org.noxylva.lbjconsole.flutter',
                  ),
                if (widget.orm &&
                    state.ormVisible &&
                    config.railTile.template.isNotEmpty)
                  TileLayer(
                    urlTemplate: config.railTile.template,
                    subdomains: config.railTile.subdomains,
                    tms: config.railTile.tms,
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
                if (widget.attribution)
                  const RichAttributionWidget(
                    alignment: AttributionAlignment.bottomRight,
                    attributions: [
                      TextSourceAttribution('OpenStreetMap contributors'),
                    ],
                  ),
              ],
            );
          },
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
        color: Colors.black,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
      ),
    );
  }
}
