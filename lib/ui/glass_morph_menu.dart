import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart' show RenderProxyBox;

import 'glass_clipper.dart';
import 'glass_styles.dart';
import 'liquid_glass.dart';

class GlassMorphMenu extends StatefulWidget {
  const GlassMorphMenu({
    super.key,
    required this.triggerBuilder,
    required this.menuBuilder,
    required this.menuWidth,
    this.onOpen,
    this.onClosed,
  });

  final Widget Function(BuildContext context, VoidCallback toggle)
      triggerBuilder;

  final Widget Function(BuildContext context, VoidCallback close) menuBuilder;

  final double menuWidth;

  final VoidCallback? onOpen;

  final VoidCallback? onClosed;

  @override
  State<GlassMorphMenu> createState() => _GlassMorphMenuState();
}

class _GlassMorphMenuState extends State<GlassMorphMenu>
    with SingleTickerProviderStateMixin {
  static const _openSpring = SpringDescription(
    mass: 1,
    stiffness: 120,
    damping: 16,
  );
  static const _closeSpring = SpringDescription(
    mass: 1,
    stiffness: 200,
    damping: 21,
  );
  static const _closeVelocityHint = -3.2;
  static const _settleTolerance = Tolerance(distance: 0.001, velocity: 0.05);

  final OverlayPortalController _portal = OverlayPortalController();
  final GlobalKey _triggerKey = GlobalKey();
  late final AnimationController _anim =
      AnimationController.unbounded(vsync: this);

  Rect _anchor = Rect.zero;
  Size? _menuSize;
  bool _open = false;
  bool _shown = false;
  bool _isClosing = false;
  bool _hasHandedOff = false;

  @override
  void initState() {
    super.initState();
    _anim.addListener(_onTick);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _onTick() {
    if (_isClosing && _anim.value <= 0 && !_hasHandedOff) {
      setState(() => _hasHandedOff = true);
    }
  }

  void _toggle() {
    if (_open) {
      _close();
    } else {
      _openMenu();
    }
  }

  void _openMenu() {
    final box =
        _triggerKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    _anchor = box.localToGlobal(Offset.zero) & box.size;
    _open = true;
    _isClosing = false;
    _hasHandedOff = false;
    if (!_shown) {
      _shown = true;
      _portal.show();
    }
    widget.onOpen?.call();
    _anim.animateWith(
      SpringSimulation(_openSpring, _anim.value, 1, 0,
          tolerance: _settleTolerance, snapToEnd: true),
    );
  }

  void _close() {
    if (!_open) return;
    _open = false;
    _isClosing = true;
    _anim
        .animateWith(
          SpringSimulation(_closeSpring, _anim.value, 0, _closeVelocityHint,
              tolerance: _settleTolerance, snapToEnd: true),
        )
        .whenComplete(() {
      if (!_open && _shown) {
        _shown = false;
        _isClosing = false;
        _hasHandedOff = false;
        _portal.hide();
        widget.onClosed?.call();
      }
    });
  }

  Rect _finalRect(MediaQueryData media) {
    final height = _menuSize?.height ?? _anchor.height;
    var top = _anchor.top;
    final maxTop = media.size.height - media.padding.bottom - 8 - height;
    if (top > maxTop) top = maxTop;
    var left = _anchor.right - widget.menuWidth;
    left = left.clamp(
      media.padding.left + 8,
      media.size.width - media.padding.right - widget.menuWidth - 8,
    );
    return Rect.fromLTWH(left, top, widget.menuWidth, height);
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: _buildOverlay,
      child: KeyedSubtree(
        key: _triggerKey,
        child: AnimatedBuilder(
          animation: _anim,
          builder: (context, child) {
            final v = _anim.value;
            final c = v.clamp(0.0, 1.0);
            final double opacity;
            if (!_shown || (_isClosing && _hasHandedOff)) {
              opacity = 1;
            } else if (!_isClosing) {
              opacity = 1 - (c / 0.20).clamp(0.0, 1.0);
            } else {
              opacity = 0;
            }
            var transform = Matrix4.identity();
            if (_isClosing && _hasHandedOff && _menuSize != null) {
              final media = MediaQuery.of(context);
              final finalRect = _finalRect(media);
              final dx = (finalRect.center.dx - _anchor.center.dx) * v;
              final dy = (finalRect.center.dy - _anchor.center.dy) * v;
              final impactScale = (1.0 + v * 0.35).clamp(0.88, 1.0);
              transform = Matrix4.translationValues(
                  _anchor.center.dx, _anchor.center.dy, 0)
                ..multiply(Matrix4.translationValues(dx, dy, 0))
                ..scaleByDouble(impactScale, impactScale, 1, 1)
                ..translateByDouble(-_anchor.center.dx, -_anchor.center.dy, 0, 1);
            }
            return Transform(
              transform: transform,
              child: Opacity(opacity: opacity, child: child),
            );
          },
          child: widget.triggerBuilder(context, _toggle),
        ),
      ),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    final media = MediaQuery.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        final v = _anim.value;
        final c = v.clamp(0.0, 1.0);
        final finalRect = _finalRect(media);
        final finalDx = finalRect.center.dx - _anchor.center.dx;
        final finalDy = finalRect.center.dy - _anchor.center.dy;
        final state = _MorphPhysics.compute(
          rawValue: v,
          finalDx: finalDx,
          finalDy: finalDy,
          isClosing: _isClosing,
          adaptiveDamping: finalDy.abs() > 100.0,
        );
        final double currentWidth;
        final double currentHeight;
        if (state.sizeT < 0) {
          currentWidth =
              (_anchor.width * (1 + state.sizeT * 0.25)).clamp(1.0, double.infinity);
          currentHeight =
              (_anchor.height * (1 + state.sizeT * 0.25)).clamp(1.0, double.infinity);
        } else {
          currentWidth =
              _lerp(_anchor.width, finalRect.width, state.sizeT);
          currentHeight =
              _lerp(_anchor.height, finalRect.height, state.sizeT);
        }
        final double effectiveDx;
        final double effectiveDy;
        if (_isClosing) {
          effectiveDx = finalDx * state.sizeT;
          effectiveDy = finalDy * state.sizeT;
        } else {
          effectiveDx = finalDx * state.sizeT +
              (finalDx * (state.pathT - state.sizeT)).clamp(-8.0, 8.0);
          effectiveDy = finalDy * state.sizeT +
              (finalDy * (state.pathT - state.sizeT)).clamp(-8.0, 8.0);
        }
        final rect = Rect.fromCenter(
          center: _anchor.center + Offset(effectiveDx, effectiveDy),
          width: currentWidth,
          height: currentHeight,
        );
        final radiusT = Curves.easeInExpo.transform(state.sizeT.clamp(0.0, 1.0));
        final radius = _isClosing
            ? _lerp(_anchor.height / 2, 32, radiusT)
            : _lerp(
                math.min(currentWidth, currentHeight) / 2, 32, radiusT);
        final clipper = SuperellipseClipper(BorderRadius.circular(radius));
        final contentOpacity = _isClosing
            ? ((c - 0.85) / 0.15).clamp(0.0, 1.0)
            : ((c - 0.25) / 0.45).clamp(0.0, 1.0);
        final itemScale = _lerp(
          0.7,
          1.0,
          Curves.easeOut.transform(((c - 0.25) / 0.75).clamp(0.0, 1.0)),
        );
        final overlayOpacity =
            (_isClosing && _hasHandedOff) || _menuSize == null ? 0.0 : 1.0;
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) {
                  if (_anchor.contains(details.globalPosition)) {
                    _toggle();
                  } else {
                    _close();
                  }
                },
              ),
            ),
            Positioned.fromRect(
              rect: rect,
              child: Opacity(
                opacity: overlayOpacity,
                child: LiquidGlass(
                  style: _isClosing
                      ? LiquidGlassStyle.lerp(
                          glassRegularStyle(colorScheme),
                          glassMenuStyle(colorScheme),
                          c,
                        )
                      : glassMenuStyle(colorScheme),
                  shadows: glassMenuShadowsOf(colorScheme),
                  clipper: clipper,
                  child: ClipPath(
                    clipper: clipper,
                    child: OverflowBox(
                      alignment: Alignment.topRight,
                      minWidth: widget.menuWidth,
                      maxWidth: widget.menuWidth,
                      minHeight: 0,
                      maxHeight: double.infinity,
                      child: IgnorePointer(
                        ignoring: c < 0.8,
                        child: Opacity(
                          opacity: contentOpacity,
                          child: Transform.scale(
                            scale: state.containerScale * itemScale,
                            alignment: Alignment.topRight,
                            child: _MeasureSize(
                              onChange: (size) {
                                if (_menuSize != size) {
                                  setState(() => _menuSize = size);
                                }
                              },
                              child: SizedBox(
                                width: widget.menuWidth,
                                child: widget.menuBuilder(context, _close),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

class _MorphPhysics {
  static const double _backOutAmplitude = 2.5;
  static const double _minBackOutAmplitude = 0.7;
  static const double _adaptiveThresholdDy = 100.0;

  static _MorphState compute({
    required double rawValue,
    required double finalDx,
    required double finalDy,
    required bool isClosing,
    required bool adaptiveDamping,
  }) {
    final clampedValue = rawValue.clamp(0.0, 1.0);
    final closeUndershoot = rawValue < 0.0 ? rawValue : 0.0;
    final amplitude = adaptiveDamping
        ? _adaptiveAmplitude(finalDy)
        : _backOutAmplitude;
    final double pathT;
    if (isClosing) {
      pathT = clampedValue + closeUndershoot;
    } else {
      pathT = _backOut(amplitude, clampedValue) + closeUndershoot;
    }
    final double rawSizeT;
    if (isClosing) {
      rawSizeT = math.pow(clampedValue, 1.4).toDouble();
    } else {
      rawSizeT = Curves.linearToEaseOut.transform(clampedValue);
    }
    final sizeT = rawSizeT + closeUndershoot;
    final containerScale = rawValue > 1.0
        ? 1.0 + (rawValue - 1.0) * 0.10
        : rawValue < 0.0
            ? 1.0 + rawValue * 0.55
            : 1.0;
    return _MorphState(
      pathT: pathT,
      sizeT: sizeT,
      containerScale: containerScale,
    );
  }

  static double _adaptiveAmplitude(double finalDy) {
    final absDy = finalDy.abs();
    if (absDy <= _adaptiveThresholdDy) return _backOutAmplitude;
    return (_backOutAmplitude * _adaptiveThresholdDy / absDy)
        .clamp(_minBackOutAmplitude, _backOutAmplitude);
  }

  static double _backOut(double amplitude, double t) {
    final u = t - 1.0;
    return u * u * ((amplitude + 1.0) * u + amplitude) + 1.0;
  }
}

class _MorphState {
  const _MorphState({
    required this.pathT,
    required this.sizeT,
    required this.containerScale,
  });

  final double pathT;
  final double sizeT;
  final double containerScale;
}

class _MeasureSize extends SingleChildRenderObjectWidget {
  const _MeasureSize({required this.onChange, required super.child});

  final ValueChanged<Size> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasureSize(onChange);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMeasureSize renderObject,
  ) {
    renderObject.onChange = onChange;
  }
}

class _RenderMeasureSize extends RenderProxyBox {
  _RenderMeasureSize(this.onChange);

  ValueChanged<Size> onChange;

  Size? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final size = child?.size;
    if (size != null && size != _reported) {
      _reported = size;
      WidgetsBinding.instance.addPostFrameCallback((_) => onChange(size));
    }
  }
}
