import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'glass_fallback.dart';
import 'liquid_glass.dart';
import 'shape.dart';

const double _barHeight = 62;
const double _barPadding = 4;
const double _edgeMargin = 21;
const double _shadowRoom = 8;
const double _hitSlop = 8;
const double _maxItemExtent = 86;
const double _minLensWidth = 84;
const _fullWidthCount = 5;
const double _iconSize = 28;
const double _labelGap = 2;
const double _labelInset = 2;
const double _labelSize = 10;
const double _labelLeading = 14.5;
const double _minLabelSize = 9;
const double _pressGrowth = 1 / 8;
const double _maxPressGrowth = 16;
const double _lensGrowth = 8;
const double _lensMagnify = 0.16;
const double _liftSnap = 0.975;
const double _liftRelease = 0.04;
const double _jellySpeed = 3;
const double _jellyStretch = 0.2;
const double _jellyBrake = 25;
const double _jellySquash = 0.15;
const double _jellyAspect = 1.4;
const double _glowReach = 28;
const double _glowGrowth = 3;
const double _glowPeak = 0.06;
const double _glowWash = 0.7;
const double _overdrag = 0.35;
const double _pullLimit = 7 / 32;
const double _pullStretch = 0.5;
const _flingProjection = Duration(milliseconds: 100);
final _trackSpring = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 120),
);
final _pressSpring = SpringDescription.withDampingRatio(
  mass: 1,
  stiffness: 311,
  ratio: 0.593,
);
final _followSpring = SpringDescription.withDampingRatio(
  mass: 1,
  stiffness: 1024,
  ratio: 0.9,
);
final _liftSpring = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 250),
);
final _travelSpring = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 400),
  bounce: 0.15,
);
final _jellySpring = SpringDescription.withDampingRatio(
  mass: 1,
  stiffness: 100,
  ratio: 0.4,
);
double _rubberBand(double overshoot, double limit) {
  final pull = 1 - 1 / (overshoot.abs() * 0.55 / limit + 1);
  return limit * pull * overshoot.sign;
}

double _saturate(double value) => 1 - 2 / (math.exp(2 * value) + 1);

Rect _lensRect({
  required double position,
  required double stretch,
  required double pitch,
  required double width,
  required double height,
  required double lift,
}) {
  final growth = _lensGrowth * 2 * lift;
  final lensWidth = (width + growth) * (1 + stretch);
  final lensHeight = (height + growth) * (1 - stretch * _jellyAspect);
  return Rect.fromLTWH(
    (position + 0.5) * pitch - lensWidth / 2,
    (height - lensHeight) / 2,
    lensWidth,
    lensHeight,
  );
}

({double pitch, double lens, double inset}) _dockLayout(
  double span,
  int count,
) {
  if (count <= 1) {
    return (pitch: span - _barPadding * 2, lens: span, inset: _barPadding);
  }
  final pitch = (span - _barPadding * 2) / count;
  if (pitch + _barPadding * 2 >= _minLensWidth) {
    return (pitch: pitch, lens: pitch + _barPadding * 2, inset: _barPadding);
  }
  final lens = math.min(_minLensWidth, span);
  final closed = (span - lens) / (count - 1);
  return (pitch: closed, lens: lens, inset: (lens - closed) / 2);
}

class _Spring extends ChangeNotifier implements ValueListenable<double> {
  _Spring(TickerProvider vsync, this._value) {
    _ticker = vsync.createTicker(_tick);
  }

  late final Ticker _ticker;
  double _value;
  double _target = 0;
  SpringSimulation? _simulation;
  SpringDescription? _spring;
  double _now = 0;
  double _start = 0;

  @override
  double get value => _value;

  double get target => _simulation == null ? _value : _target;

  double get velocity => _simulation?.dx(_now - _start) ?? 0;

  double get acceleration {
    final spring = _spring;
    if (_simulation == null || spring == null) {
      return 0;
    }
    return (spring.stiffness * (_target - _value) - spring.damping * velocity) /
        spring.mass;
  }

  void springTo(double target, SpringDescription spring) {
    _simulation = SpringSimulation(spring, _value, target, velocity);
    _spring = spring;
    _target = target;
    if (_ticker.isActive) {
      _start = _now;
      return;
    }
    _now = _start = 0;
    _ticker.start();
  }

  void jumpTo(double value) {
    _simulation = null;
    _ticker.stop();
    _value = value;
    notifyListeners();
  }

  void _tick(Duration elapsed) {
    _now = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final simulation = _simulation!;
    final time = _now - _start;
    if (simulation.isDone(time)) {
      _value = _target;
      _simulation = null;
      _ticker.stop();
    } else {
      _value = simulation.x(time);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}

List<BoxShadow> dockGlassShadows(ColorScheme colorScheme) => [
  BoxShadow(
    color: colorScheme.shadow.withValues(alpha: 0.013),
    blurRadius: 3.8,
    offset: const Offset(0, 6.5),
  ),
];

LiquidGlassStyle _pillStyle(ColorScheme colorScheme) =>
    colorScheme.brightness == Brightness.dark
    ? LiquidGlassStyle(
        tint: colorScheme.surfaceContainerHighest.withValues(alpha: 0.48),
        contrast: -0.4,
        blur: 0,
        haze: 0.72,
        hazeBlur: 15.6,
        saturation: 1.925,
        rim: 0.35,
      )
    : const LiquidGlassStyle(
        tint: Color(0x93F4F4F4),
        contrast: 0.4,
        blur: 0,
        haze: 0.72,
        hazeBlur: 15.6,
        saturation: 2.1,
        hairline: 0.35,
      );

LiquidGlassStyle _lensStyle(ColorScheme colorScheme) {
  final dark = colorScheme.brightness == Brightness.dark;
  return LiquidGlassStyle(
    tint: Colors.transparent,
    blur: 0,
    refraction: -4.3,
    bevel: 5.5,
    saturation: 1,
    brightness: dark ? 1.33 : 1,
    rim: dark ? 0.3 : 0.6,
    rimWidth: 1.1,
    endShade: 0.045,
    dispersion: 6.5,
    rimBlur: 1.5,
    hairline: 0.42,
  );
}

LiquidGlassStyle _lensContentStyle(ColorScheme colorScheme) {
  final dark = colorScheme.brightness == Brightness.dark;
  return LiquidGlassStyle(
    tint: Colors.transparent,
    blur: 0,
    refraction: 14,
    bevel: 11.2,
    saturation: 1,
    brightness: dark ? 1.33 : 1,
    rim: 0,
    dispersion: 3.6,
    rimBlur: 2.5,
  );
}

class _DockSurface extends StatelessWidget {
  const _DockSurface({
    required this.glass,
    required this.translucent,
    required this.style,
    required this.shadows,
    required this.glow,
    required this.child,
  });

  final bool glass;
  final bool translucent;
  final LiquidGlassStyle style;
  final List<BoxShadow> shadows;
  final ValueListenable<LiquidGlassGlow> glow;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (glass) {
      return ValueListenableBuilder(
        valueListenable: glow,
        builder: (_, glow, child) => LiquidGlass(
          style: style,
          shadows: shadows,
          glow: glow,
          child: child,
        ),
        child: child,
      );
    }
    if (translucent) {
      return FallbackGlass(
        shape: AppShape.full,
        shadows: shadows,
        child: child,
      );
    }
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: AppShape.full,
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        shadows: shadows,
      ),
      child: child,
    );
  }
}

({double width, double height}) _measureLabel(
  BuildContext context,
  String label,
  TextStyle? style,
) {
  final painter = TextPainter(
    text: TextSpan(text: label, style: style),
    textScaler: MediaQuery.textScalerOf(context),
    textDirection: Directionality.of(context),
    maxLines: 1,
  )..layout();
  final size = (width: painter.width, height: painter.height);
  painter.dispose();
  return size;
}

class GlassDockItem {
  const GlassDockItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class GlassDock extends StatelessWidget {
  const GlassDock({
    super.key,
    required this.currentIndex,
    required this.onSelected,
    required this.items,
    this.backdropFallback = false,
  });

  final int currentIndex;
  final ValueChanged<int> onSelected;
  final List<GlassDockItem> items;

  /// Over a platform view (the map) the capture-based glass has no
  /// backdrop to refract and renders solid; the bar then falls back
  /// to a plain translucent surface, which composites normally.
  final bool backdropFallback;

  static double heightOf(BuildContext context) {
    return _barHeight +
        MediaQuery.textScalerOf(context).scale(_labelSize) -
        _labelSize;
  }

  static double _bottomMarginOf(BuildContext context) =>
      math.max(_edgeMargin, MediaQuery.paddingOf(context).bottom);

  static double insetOf(BuildContext context) =>
      heightOf(context) + _bottomMarginOf(context);

  @override
  Widget build(BuildContext context) {
    final height = heightOf(context);
    final dock = Padding(
      padding: EdgeInsets.fromLTRB(
        _edgeMargin,
        _shadowRoom,
        _edgeMargin,
        _bottomMarginOf(context),
      ),
      child: _HitSlop(
        child: SizedBox(
          height: height,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: _HitSlop(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: items.length >= _fullWidthCount
                          ? double.infinity
                          : items.length * _maxItemExtent + _barPadding * 4,
                    ),
                    child: _FloatingBar(
                      items: items,
                      selectedIndex: currentIndex,
                      onSelected: onSelected,
                      backdropFallback: backdropFallback,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return SizedBox(
      width: double.infinity,
      height: _shadowRoom + height + _bottomMarginOf(context),
      child: RepaintBoundary(child: dock),
    );
  }
}

class _HitSlop extends SingleChildRenderObjectWidget {
  const _HitSlop({super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderHitSlop();
}

class _RenderHitSlop extends RenderProxyBox {
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (size.contains(position)) {
      return super.hitTest(result, position: position);
    }
    if (size.isEmpty ||
        !(Offset.zero & size).inflate(_hitSlop).contains(position)) {
      return false;
    }
    if (!hitTestChildren(result, position: _onSpine(position))) {
      return false;
    }
    result.add(BoxHitTestEntry(this, position));
    return true;
  }

  Offset _onSpine(Offset position) {
    final radius = size.shortestSide / 2;
    return Offset(
      position.dx.clamp(radius, size.width - radius),
      size.height / 2,
    );
  }
}

class _PressTransform extends SingleChildRenderObjectWidget {
  const _PressTransform({required this.lift, required this.pull, super.child});

  final double lift;
  final Offset pull;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderPressTransform(lift: lift, pull: pull);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPressTransform renderObject,
  ) {
    renderObject
      ..lift = lift
      ..pull = pull;
  }
}

class _RenderPressTransform extends RenderProxyBox {
  _RenderPressTransform({required double lift, required Offset pull})
    : _lift = lift,
      _pull = pull;

  double _lift;
  Offset _pull;

  set lift(double value) {
    if (value == _lift) {
      return;
    }
    _lift = value;
    markNeedsPaint();
  }

  set pull(Offset value) {
    if (value == _pull) {
      return;
    }
    _pull = value;
    markNeedsPaint();
  }

  Matrix4 get _transform {
    final panel = Offset.zero & size;
    final swell =
        1 +
            _lift * math.min(_pressGrowth * 2, _maxPressGrowth / panel.longestSide);
    final scaleX = swell * (1 + _pull.dx.abs() / panel.width * _pullStretch);
    final scaleY = swell * (1 + _pull.dy.abs() / panel.height * _pullStretch);
    final center = panel.center;
    return Matrix4.diagonal3Values(scaleX, scaleY, 1)..setTranslationRaw(
      center.dx * (1 - scaleX) + _pull.dx,
      center.dy * (1 - scaleY) + _pull.dy,
      0,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null || size.isEmpty || (_lift == 0 && _pull == Offset.zero)) {
      layer = null;
      super.paint(context, offset);
      return;
    }
    layer = context.pushTransform(
      needsCompositing,
      offset,
      _transform,
      super.paint,
      oldLayer: layer is TransformLayer ? layer as TransformLayer? : null,
    );
  }
}

class _FloatingBar extends StatefulWidget {
  const _FloatingBar({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    required this.backdropFallback,
  });

  final List<GlassDockItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool backdropFallback;

  @override
  State<_FloatingBar> createState() => _FloatingBarState();
}

class _FloatingBarState extends State<_FloatingBar>
    with TickerProviderStateMixin {
  late final _Spring _lens = _Spring(this, _selectedIndex.toDouble());
  late final _Spring _lift = _Spring(this, 0);
  late final _Spring _swell = _Spring(this, 0);
  late final _Spring _stretch = _Spring(this, 0);
  late final _Spring _jelly = _Spring(this, 0);
  late final _Spring _glow = _Spring(this, 0);
  late final _Spring _glowSpread = _Spring(this, 0);
  final ValueNotifier<LiquidGlassGlow> _touchGlow = ValueNotifier(
    LiquidGlassGlow.none,
  );
  Offset _glowAt = Offset.zero;
  late final Listenable _barMotion = Listenable.merge([_swell, _stretch]);
  late final Listenable _motion = Listenable.merge([_lens, _lift, _jelly]);
  bool _lifted = false;
  int? _pointer;
  int? _pressedIndex;
  double _pressX = 0;
  bool _dragging = false;
  bool _dropping = false;
  VelocityTracker? _tracker;

  int get _lastIndex => math.max(0, widget.items.length - 1);

  int get _selectedIndex => widget.selectedIndex.clamp(0, _lastIndex);

  ({double pitch, double lens, double inset}) get _layout => _dockLayout(
    context.size!.width - _barPadding * 2,
    widget.items.length,
  );

  @override
  void initState() {
    super.initState();
    _lens
      ..addListener(_wobble)
      ..addListener(_dropLift);
    _lift
      ..addListener(_dropLift)
      ..addListener(_noteLift);
    _glow.addListener(_shine);
    _glowSpread.addListener(_shine);
  }

  @override
  void didUpdateWidget(covariant _FloatingBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final rest = _selectedIndex.toDouble();
    if (_pressedIndex == null && _lens.target != rest) {
      _lens.springTo(rest, _travelSpring);
    }
  }

  @override
  void dispose() {
    _lens.dispose();
    _lift.dispose();
    _swell.dispose();
    _stretch.dispose();
    _jelly.dispose();
    _glow.dispose();
    _glowSpread.dispose();
    _touchGlow.dispose();
    super.dispose();
  }

  void _wobble() {
    final velocity = _lens.velocity;
    final braking = math.max(0.0, -_lens.acceleration * velocity.sign);
    final target =
        _jellyStretch * _saturate(velocity.abs() / _jellySpeed) -
        _jellySquash * _saturate(braking / _jellyBrake);
    if (target != _jelly.target) {
      _jelly.springTo(target, _jellySpring);
    }
  }

  void _shine() {
    final glow = _glow.value;
    _touchGlow.value = LiquidGlassGlow(
      center: _glowAt,
      reach: _glowReach * (1 + _glowGrowth * _glowSpread.value),
      strength: _glowPeak * glow * glow,
      wash: _glowWash,
    );
  }

  void _noteLift() {
    final lifted = _lift.value > 0;
    if (lifted != _lifted) {
      setState(() => _lifted = lifted);
    }
  }

  void _dropLift() {
    if (!_dropping || _pointer != null || _lift.value < _liftSnap) {
      return;
    }
    if ((_lens.target - _lens.value).abs() > _liftRelease) {
      return;
    }
    _dropping = false;
    _lift.springTo(0, _liftSpring);
  }

  double _positionAt(Offset localPosition) {
    final width = context.size!.width;
    final dx = Directionality.of(context) == TextDirection.ltr
        ? localPosition.dx
        : width - localPosition.dx;
    final layout = _layout;
    final position = (dx - _barPadding - layout.inset) / layout.pitch - 0.5;
    if (position < 0) {
      return _rubberBand(position, _overdrag);
    }
    if (position > _lastIndex) {
      return _lastIndex + _rubberBand(position - _lastIndex, _overdrag);
    }
    return position;
  }

  int _indexAt(double position) => position.round().clamp(0, _lastIndex);

  void _handlePointerDown(PointerDownEvent event) {
    if (_pointer != null || event.buttons & kPrimaryButton == 0) {
      return;
    }
    _pointer = event.pointer;
    _tracker = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.localPosition);
    _swell.springTo(1, _pressSpring);
    _glowAt = event.localPosition;
    _glowSpread.jumpTo(0);
    _glow.springTo(1, _glowInSpring);
    _press(event.localPosition);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer == _pointer) {
      _tracker?.addPosition(event.timeStamp, event.localPosition);
      _glowAt = event.localPosition;
      _shine();
      _slide(event.localPosition);
    }
  }

  void _handlePointerEnd(PointerEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    _pointer = null;
    final tracker = _tracker;
    _tracker = null;
    if (event is PointerUpEvent && tracker != null) {
      _fling(tracker.getVelocity().pixelsPerSecond.dx);
    }
    _release(commit: event is PointerUpEvent);
    _glow.springTo(0, _glowOutSpring);
    _glowSpread.springTo(1, _glowOutSpring);
    _stretch.springTo(0, _pressSpring);
    if (_swell.target != 0) {
      _swell.springTo(0, _pressSpring);
    }
  }

  void _press(Offset localPosition) {
    if (widget.items.isEmpty) {
      return;
    }
    final index = _indexAt(_positionAt(localPosition));
    _pressedIndex = index;
    _pressX = localPosition.dx;
    _dragging = false;
    _dropping = false;
    _lift.springTo(1, _liftSpring);
    _lens.springTo(index.toDouble(), _travelSpring);
  }

  void _slide(Offset localPosition) {
    if (_pressedIndex == null) {
      return;
    }
    if (!_dragging) {
      if ((localPosition.dx - _pressX).abs() < kTouchSlop) {
        return;
      }
      _dragging = true;
    }
    final size = context.size!;
    final overshoot =
        localPosition.dx - localPosition.dx.clamp(0.0, size.width);
    _stretch.springTo(
      _rubberBand(overshoot, size.shortestSide * _pullLimit),
      _trackSpring,
    );
    final position = _positionAt(localPosition);
    _lens.springTo(position, _followSpring);
    final index = _indexAt(position);
    if (index != _pressedIndex) {
      HapticFeedback.selectionClick();
      _pressedIndex = index;
    }
  }

  void _fling(double velocityX) {
    final pressed = _pressedIndex;
    if (!_dragging || pressed == null) {
      return;
    }
    final extent = _layout.pitch;
    final direction = Directionality.of(context) == TextDirection.ltr
        ? 1
        : -1;
    final lead =
        velocityX /
        extent *
        direction *
        _flingProjection.inMicroseconds /
        Duration.microsecondsPerSecond;
    final index = (_lens.target + lead)
        .round()
        .clamp(pressed - 1, pressed + 1)
        .clamp(0, _lastIndex);
    if (index != pressed) {
      HapticFeedback.selectionClick();
      _pressedIndex = index;
    }
  }

  void _release({required bool commit}) {
    final index = _pressedIndex;
    if (index == null) {
      return;
    }
    _pressedIndex = null;
    _dragging = false;
    _dropping = true;
    _lens.springTo((commit ? index : _selectedIndex).toDouble(), _travelSpring);
    _dropLift();
    if (commit && index != widget.selectedIndex) {
      widget.onSelected(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const labelStyle = TextStyle(
      fontSize: _labelSize,
      height: _labelLeading / _labelSize,
      fontWeight: FontWeight.w500,
    );
    final labels = [
      for (final item in widget.items)
        _measureLabel(context, item.label, labelStyle),
    ];
    final widest = labels.fold(
      0.0,
      (width, label) => math.max(width, label.width),
    );
    final lineHeight = labels.fold(
      0.0,
      (height, label) => math.max(height, label.height),
    );
    final glass =
        LiquidGlassScope.of(context) && !widget.backdropFallback;
    final ultra =
        LiquidGlassScope.qualityOf(context) == LiquidGlassQuality.ultra;
    final bar = _DockSurface(
      glass: glass,
      translucent: widget.backdropFallback,
      style: _pillStyle(colorScheme),
      shadows: ultra ? dockGlassShadows(colorScheme) : const [],
      glow: _touchGlow,
      child: Material(
        color: glass || widget.backdropFallback
            ? Colors.transparent
            : colorScheme.surfaceContainerHigh,
        shape: AppShape.full,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _handlePointerDown,
          onPointerMove: _handlePointerMove,
          onPointerUp: _handlePointerEnd,
          onPointerCancel: _handlePointerEnd,
          child: Padding(
            padding: const EdgeInsets.all(_barPadding),
            child: RepaintBoundary(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final layout = _dockLayout(
                    constraints.maxWidth,
                    widget.items.length,
                  );
                  final room = layout.pitch - _labelInset * 2;
                  final labelScale = widest <= room
                      ? 1.0
                      : math.max(room / widest, _minLabelSize / _labelSize);
                  Rect lensRect() => _lensRect(
                    position: _lens.value,
                    stretch: _jelly.value,
                    pitch: layout.pitch,
                    width: layout.lens,
                    height: constraints.maxHeight,
                    lift: _lift.value,
                  ).shift(Offset(layout.inset, 0));
                  Widget items(_LensPart part) => Padding(
                    padding: EdgeInsets.symmetric(horizontal: layout.inset),
                    child: Row(
                      children: [
                        for (final (index, item) in widget.items.indexed)
                          Expanded(
                            child: _FloatingBarItem(
                              item: item,
                              selected: index == _selectedIndex,
                              index: index,
                              part: part,
                              lens: _lens,
                              lensWidth: layout.lens,
                              jelly: _jelly,
                              lift: _lift,
                              labelStyle: labelStyle.copyWith(
                                fontSize: _labelSize * labelScale,
                              ),
                              labelHeight: lineHeight,
                              labelOverflows:
                                  labels[index].width * labelScale > room,
                              onActivate: () => widget.onSelected(index),
                            ),
                          ),
                      ],
                    ),
                  );
                  final lensed =
                      glass && _lifted && widget.items.isNotEmpty;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      if (widget.items.isNotEmpty)
                        AnimatedBuilder(
                          animation: _motion,
                          builder: (_, _) => _Lens(
                            rect: lensRect(),
                            lift: _lift.value,
                            glass: glass,
                            translucent: widget.backdropFallback,
                          ),
                        ),
                      if (glass && widget.items.isNotEmpty)
                        AnimatedBuilder(
                          animation: _motion,
                          builder: (_, _) =>
                              _GlassLens(rect: lensRect(), lift: _lift.value),
                        ),
                      items(lensed ? _LensPart.outside : _LensPart.both),
                      if (lensed)
                        AnimatedBuilder(
                          animation: _motion,
                          builder: (_, child) => _LensContent(
                            rect: lensRect(),
                            lift: _lift.value,
                            warp: ultra,
                            child: child!,
                          ),
                          child: items(_LensPart.inside),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    return AnimatedBuilder(
      animation: _barMotion,
      builder: (_, child) => _PressTransform(
        lift: _swell.value,
        pull: Offset(_stretch.value, 0),
        child: child,
      ),
      child: bar,
    );
  }
}

final _glowInSpring = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 100),
);
final _glowOutSpring = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 500),
);

class _Lens extends StatelessWidget {
  const _Lens({
    required this.rect,
    required this.lift,
    required this.glass,
    this.translucent = false,
  });

  final Rect rect;
  final double lift;
  final bool glass;
  final bool translucent;

  @override
  Widget build(BuildContext context) {
    // In glass mode there is no platter: the glass lens itself is the
    // resting indicator, as in component-library tab bars.
    if (glass) {
      return const SizedBox.shrink();
    }
    final colorScheme = Theme.of(context).colorScheme;
    final lifted = lift.clamp(0.0, 1.0);
    return PositionedDirectional(
      start: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: translucent
          ? const FallbackGlass(
              shape: AppShape.full,
              child: SizedBox.expand(),
            )
          : DecoratedBox(
              decoration: ShapeDecoration(
                color: Color.alphaBlend(
                  colorScheme.onSurface.withValues(alpha: 0.08 * lifted),
                  colorScheme.surfaceContainerHighest,
                ),
                shape: AppShape.full,
              ),
            ),
    );
  }
}

class _GlassLens extends StatelessWidget {
  const _GlassLens({required this.rect, required this.lift});

  final Rect rect;
  final double lift;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dark = colorScheme.brightness == Brightness.dark;
    final t = lift.clamp(0.0, 1.0);
    final lens = _lensStyle(colorScheme);
    final style = LiquidGlassStyle(
      tint: Color.lerp(
        colorScheme.onSurface.withValues(alpha: dark ? 0.14 : 0.09),
        lens.tint,
        t,
      )!,
      blur: 0,
      refraction: lens.refraction * t,
      bevel: lens.bevel * t,
      saturation: 1,
      brightness: 1 + (lens.brightness - 1) * t,
      rim: lens.rim * t,
      rimWidth: lens.rimWidth * t,
      endShade: lens.endShade,
      dispersion: lens.dispersion * t,
      rimBlur: lens.rimBlur * t,
      hairline: lens.hairline * t,
    );
    return Positioned.directional(
      textDirection: Directionality.of(context),
      start: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: IgnorePointer(
        child: LiquidGlass(
          style: style,
          shadows: _lensShadows(colorScheme, lift),
        ),
      ),
    );
  }
}

List<BoxShadow> _lensShadows(ColorScheme colorScheme, double lift) {
  final strength = colorScheme.brightness == Brightness.dark ? 3.0 : 1.0;
  return [
    BoxShadow(
      color: colorScheme.shadow.withValues(
        alpha: 0.055 * strength * lift.clamp(0.0, 1.0),
      ),
      blurRadius: 5,
      offset: const Offset(0, 8),
    ),
  ];
}

class _LensContent extends StatelessWidget {
  const _LensContent({
    required this.rect,
    required this.lift,
    required this.warp,
    required this.child,
  });

  final Rect rect;
  final double lift;
  final bool warp;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final textDirection = Directionality.of(context);
    final clipper = _LensClip(rect, textDirection);
    if (!warp) {
      return Positioned.fill(
        child: IgnorePointer(
          child: ExcludeSemantics(
            child: ClipPath(clipper: clipper, child: child),
          ),
        ),
      );
    }
    return Positioned.fill(
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: ClipPath(
            clipper: clipper,
            clipBehavior: Clip.antiAliasWithSaveLayer,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(child: child),
                Positioned.directional(
                  textDirection: textDirection,
                  start: rect.left,
                  top: rect.top,
                  width: rect.width,
                  height: rect.height,
                  child: LiquidGlass(
                    style: _lensContentStyle(
                      Theme.of(context).colorScheme,
                    ).scale(lift),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LensClip extends CustomClipper<Path> {
  const _LensClip(this.rect, this.textDirection);

  final Rect rect;
  final TextDirection textDirection;

  @override
  Path getClip(Size size) => AppShape.full.getOuterPath(
    textDirection == TextDirection.ltr
        ? rect
        : Rect.fromLTRB(
            size.width - rect.right,
            rect.top,
            size.width - rect.left,
            rect.bottom,
          ),
  );

  @override
  bool shouldReclip(_LensClip oldClipper) =>
      rect != oldClipper.rect || textDirection != oldClipper.textDirection;
}

enum _LensPart { both, outside, inside }

class _FloatingBarItem extends StatefulWidget {
  const _FloatingBarItem({
    required this.item,
    required this.selected,
    required this.index,
    required this.part,
    required this.lens,
    required this.lensWidth,
    required this.jelly,
    required this.lift,
    required this.labelStyle,
    required this.labelHeight,
    required this.labelOverflows,
    required this.onActivate,
  });

  final GlassDockItem item;
  final bool selected;
  final int index;
  final _LensPart part;
  final _Spring lens;
  final double lensWidth;
  final ValueListenable<double> jelly;
  final ValueListenable<double> lift;
  final TextStyle? labelStyle;
  final double labelHeight;
  final bool labelOverflows;
  final VoidCallback onActivate;

  @override
  State<_FloatingBarItem> createState() => _FloatingBarItemState();
}

class _FloatingBarItemState extends State<_FloatingBarItem> {
  late final Map<Type, Action<Intent>> _actions = {
    ActivateIntent: CallbackAction<ActivateIntent>(
      onInvoke: (_) {
        widget.onActivate();
        return null;
      },
    ),
  };
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = colorScheme.onSurfaceVariant;
    final tint = colorScheme.onSurface;
    final content = _LensTint(
      part: widget.part,
      lens: widget.lens,
      lensWidth: widget.lensWidth,
      jelly: widget.jelly,
      lift: widget.lift,
      index: widget.index,
      color: tint,
      textDirection: Directionality.of(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _labelInset),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(widget.item.icon, size: _iconSize, color: color),
            const SizedBox(height: _labelGap),
            SizedBox(
              height: widget.labelHeight,
              child: Center(
                child: Text(
                  widget.item.label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: widget.labelStyle?.copyWith(color: color),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (widget.part == _LensPart.inside) {
      return content;
    }
    return FocusableActionDetector(
      actions: _actions,
      mouseCursor: SystemMouseCursors.click,
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      child: Semantics(
        container: true,
        button: true,
        selected: widget.selected,
        label: widget.item.label,
        excludeSemantics: true,
        onTap: widget.onActivate,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: _focused
                ? colorScheme.onSurface.withValues(alpha: 0.1)
                : Colors.transparent,
            shape: AppShape.full.copyWith(
              side: _focused
                  ? BorderSide(
                      color: colorScheme.onSurface.withValues(alpha: 0.35),
                    )
                  : BorderSide.none,
            ),
          ),
          child: widget.labelOverflows
              ? Tooltip(message: widget.item.label, child: content)
              : content,
        ),
      ),
    );
  }
}

class _LensTint extends SingleChildRenderObjectWidget {
  const _LensTint({
    required this.part,
    required this.lens,
    required this.lensWidth,
    required this.jelly,
    required this.lift,
    required this.index,
    required this.color,
    required this.textDirection,
    super.child,
  });

  final _LensPart part;
  final _Spring lens;
  final double lensWidth;
  final ValueListenable<double> jelly;
  final ValueListenable<double> lift;
  final int index;
  final Color color;
  final TextDirection textDirection;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderLensTint(
      part: part,
      lens: lens,
      lensWidth: lensWidth,
      jelly: jelly,
      lift: lift,
      index: index,
      color: color,
      textDirection: textDirection,
    );
  }

  @override
  void updateRenderObject(BuildContext context, _RenderLensTint renderObject) {
    renderObject
      ..part = part
      ..lens = lens
      ..lensWidth = lensWidth
      ..jelly = jelly
      ..lift = lift
      ..index = index
      ..color = color
      ..textDirection = textDirection;
  }
}

class _RenderLensTint extends RenderProxyBox {
  _RenderLensTint({
    required _LensPart part,
    required _Spring lens,
    required double lensWidth,
    required ValueListenable<double> jelly,
    required ValueListenable<double> lift,
    required int index,
    required Color color,
    required TextDirection textDirection,
  }) : _part = part,
       _lens = lens,
       _lensWidth = lensWidth,
       _jelly = jelly,
       _lift = lift,
       _index = index,
       _color = color,
       _textDirection = textDirection;

  final _outside = LayerHandle<ClipPathLayer>();
  final _inside = LayerHandle<ClipPathLayer>();
  final _tint = LayerHandle<ColorFilterLayer>();
  final _outsideMotion = LayerHandle<TransformLayer>();
  final _insideMotion = LayerHandle<TransformLayer>();

  _LensPart _part;
  set part(_LensPart value) {
    if (value == _part) {
      return;
    }
    _part = value;
    markNeedsPaint();
  }

  _Spring _lens;
  set lens(_Spring value) {
    if (value == _lens) {
      return;
    }
    if (attached) {
      _lens.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _lens = value;
    markNeedsPaint();
  }

  double _lensWidth;
  set lensWidth(double value) {
    if (value == _lensWidth) {
      return;
    }
    _lensWidth = value;
    markNeedsPaint();
  }

  ValueListenable<double> _jelly;
  set jelly(ValueListenable<double> value) {
    if (value == _jelly) {
      return;
    }
    if (attached) {
      _jelly.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _jelly = value;
    markNeedsPaint();
  }

  ValueListenable<double> _lift;
  set lift(ValueListenable<double> value) {
    if (value == _lift) {
      return;
    }
    if (attached) {
      _lift.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _lift = value;
    markNeedsPaint();
  }

  int _index;
  set index(int value) {
    if (value == _index) {
      return;
    }
    _index = value;
    markNeedsPaint();
  }

  Color _color;
  set color(Color value) {
    if (value == _color) {
      return;
    }
    _color = value;
    markNeedsPaint();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) {
      return;
    }
    _textDirection = value;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _lens.addListener(markNeedsPaint);
    _jelly.addListener(markNeedsPaint);
    _lift.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _lens.removeListener(markNeedsPaint);
    _jelly.removeListener(markNeedsPaint);
    _lift.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    _outside.layer = null;
    _inside.layer = null;
    _tint.layer = null;
    _outsideMotion.layer = null;
    _insideMotion.layer = null;
    super.dispose();
  }

  Rect get _lensBounds {
    final rect = _lensRect(
      position: _lens.value - _index,
      stretch: _jelly.value,
      pitch: size.width,
      width: _lensWidth,
      height: size.height,
      lift: _lift.value,
    );
    return _textDirection == TextDirection.ltr
        ? rect
        : Rect.fromLTRB(
            size.width - rect.right,
            rect.top,
            size.width - rect.left,
            rect.bottom,
          );
  }

  Matrix4? _motion(double scale) {
    if (scale == 1) {
      return null;
    }
    final center = size.center(Offset.zero);
    return Matrix4.diagonal3Values(scale, scale, 1)..setTranslationRaw(
      center.dx * (1 - scale),
      center.dy * (1 - scale),
      0,
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final motion = _motion(1);
    if (motion != null) {
      transform.multiply(motion);
    }
  }

  void _paintMoved(
    PaintingContext context,
    Offset offset,
    Matrix4? motion,
    LayerHandle<TransformLayer> handle,
  ) {
    if (motion == null) {
      handle.layer = null;
      super.paint(context, offset);
      return;
    }
    handle.layer = context.pushTransform(
      needsCompositing,
      offset,
      motion,
      super.paint,
      oldLayer: handle.layer,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) {
      return;
    }
    final rest = _motion(1);
    final magnified = _motion(1 + _lensMagnify * _lift.value);
    final bounds = Offset.zero & size;
    Rect moved(Matrix4? motion) =>
        motion == null ? bounds : MatrixUtils.transformRect(motion, bounds);
    final lensBounds = _lensBounds;
    final reached = Rect.fromLTRB(
      lensBounds.left + _barPadding,
      lensBounds.top,
      lensBounds.right - _barPadding,
      lensBounds.bottom,
    );
    final outside = _part != _LensPart.inside;
    final inside = _part != _LensPart.outside;
    if (!reached.overlaps(moved(rest)) && !reached.overlaps(moved(magnified))) {
      _outside.layer = null;
      _inside.layer = null;
      _tint.layer = null;
      _insideMotion.layer = null;
      if (outside) {
        _paintMoved(context, offset, rest, _outsideMotion);
      } else {
        _outsideMotion.layer = null;
      }
      return;
    }
    final reach = moved(rest).expandToInclude(bounds).inflate(_labelInset);
    final lens = AppShape.full.getOuterPath(lensBounds);
    if (outside) {
      _outside.layer = context.pushClipPath(
        needsCompositing,
        offset,
        reach,
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(reach)
          ..addPath(lens, Offset.zero),
        (context, offset) => _paintMoved(context, offset, rest, _outsideMotion),
        oldLayer: _outside.layer,
      );
    } else {
      _outside.layer = null;
      _outsideMotion.layer = null;
    }
    if (inside) {
      _inside.layer = context.pushClipPath(
        needsCompositing,
        offset,
        lensBounds,
        lens,
        (context, offset) =>
            _paintTinted(context, offset, lensBounds, magnified),
        oldLayer: _inside.layer,
      );
    } else {
      _inside.layer = null;
      _tint.layer = null;
      _insideMotion.layer = null;
    }
  }

  void _paintTinted(
    PaintingContext context,
    Offset offset,
    Rect lensBounds,
    Matrix4? motion,
  ) {
    final filter = ColorFilter.mode(_color, BlendMode.srcIn);
    if (needsCompositing) {
      _tint.layer = context.pushColorFilter(
        offset,
        filter,
        (context, offset) =>
            _paintMoved(context, offset, motion, _insideMotion),
        oldLayer: _tint.layer,
      );
      return;
    }
    _tint.layer = null;
    final canvas = context.canvas
      ..saveLayer(lensBounds.shift(offset), Paint()..colorFilter = filter);
    _paintMoved(context, offset, motion, _insideMotion);
    canvas.restore();
  }
}
