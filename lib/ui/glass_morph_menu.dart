import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart' show RenderProxyBox;

import 'glass_clipper.dart';
import 'glass_styles.dart';
import 'liquid_glass.dart';

/// A menu replicating lgw's GlassMenu morph (the iOS 26 pull-down
/// pattern, as on Mail's top-right button) on this app's single
/// glass surface: the trigger's glass morphs into the menu instead
/// of a separate popup being added.
///
/// The animation is lgw's own, ported from its GlassMorphController
/// and LiquidMorphPhysics: asymmetric underdamped springs (open
/// 120/16, close 200/21 with the -3.2 velocity hint, settled within
/// a 0.001/0.05 tolerance and snapped to the end), the size driven
/// by linearToEaseOut on open and by a pow(value, 1.4) contraction
/// on close, the centre travelling with the J-curve drift clamped
/// to 8px, rows scaling 0.7 → 1.0 as they fade through their
/// windows, and the trigger dissolving out over the first 20% of
/// the opening, then catching the returning droplet at the spring's
/// zero crossing: from that frame the overlay hands off to the real
/// trigger, which absorbs the remaining undershoot as a push and a
/// squash. lgw renders the same motion as two SDF-blended blobs;
/// the path ported here is its standard (non-premium) single-blob
/// collapse, which is what this app's capture-based glass can draw.
///
/// The final frame keeps the anchor's top-right corner pinned and
/// grows down and to the left, clamped inside the screen margins.
class GlassMorphMenu extends StatefulWidget {
  const GlassMorphMenu({
    super.key,
    required this.triggerBuilder,
    required this.menuBuilder,
    required this.menuWidth,
    this.onOpen,
    this.onClosed,
  });

  /// Builds the trigger; [toggle] opens or closes the menu.
  final Widget Function(BuildContext context, VoidCallback toggle)
      triggerBuilder;

  /// Builds the menu content at its final size; [close] dismisses
  /// the menu.
  final Widget Function(BuildContext context, VoidCallback close) menuBuilder;

  final double menuWidth;

  /// The menu has started opening.
  final VoidCallback? onOpen;

  /// The morph back into the trigger has fully settled.
  final VoidCallback? onClosed;

  @override
  State<GlassMorphMenu> createState() => _GlassMorphMenuState();
}

class _GlassMorphMenuState extends State<GlassMorphMenu>
    with SingleTickerProviderStateMixin {
  // lgw's iOS 26 spring profiles (LiquidMorphPhysics.openSpring /
  // closeSpring, MorphSpeed.normal).
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

  // lgw's handoff latch: the first zero crossing of the closing
  // spring hands the surface back to the real trigger.
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
    // The portal comes down when the spring settles, whatever its
    // status reports: the future's completion is the guarantee. A
    // re-open cancels this future, and its completion then finds
    // the menu open again and leaves the portal up.
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
            // lgw's trigger presence: dissolved over the first 20%
            // of the opening, hidden for the whole closing flight,
            // and back at full opacity from the handoff frame,
            // pushed and squashed by the spring's undershoot.
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
        // lgw's single-blob geometry: the surface's size follows
        // sizeT from the trigger's size to the menu's, squeezing
        // relative to the trigger's size in the undershoot, and its
        // centre follows sizeT directly on close, or sizeT plus the
        // J-curve drift (clamped to 8px) on open.
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
        // lgw's content windows: rows fade in over value
        // 0.25→0.70 on open and flush out over 1.0→0.85 on close,
        // scaling 0.7 → 1.0 across 0.25→1.0 in both directions.
        final contentOpacity = _isClosing
            ? ((c - 0.85) / 0.15).clamp(0.0, 1.0)
            : ((c - 0.25) / 0.45).clamp(0.0, 1.0);
        final itemScale = _lerp(
          0.7,
          1.0,
          Curves.easeOut.transform(((c - 0.25) / 0.75).clamp(0.0, 1.0)),
        );
        // From the handoff frame the overlay is gone: the real
        // trigger has caught the droplet. Before the first size
        // measurement lands, the final rect still falls back to
        // the anchor's height, and rendering those frames flashes
        // a wide flat bar of wrong geometry across the top of the
        // pane; the surface stays hidden for that one frame and
        // the still-visible trigger covers the wait.
        final overlayOpacity =
            (_isClosing && _hasHandedOff) || _menuSize == null ? 0.0 : 1.0;
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) {
                  // The trigger stays live through the barrier: a
                  // tap landing on its rect toggles in every phase.
                  // Mid-close that is the difference between a
                  // re-open and a swallowed tap, because the
                  // barrier's own close is a no-op once the menu
                  // is already closing, and the pane does not come
                  // down until the spring settles.
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
                  style: LiquidGlassStyle.lerp(
                    glassRegularStyle(colorScheme),
                    glassMenuStyle(colorScheme),
                    c,
                  ),
                  shadows: glassMenuShadowsOf(colorScheme),
                  clipper: clipper,
                  child: ClipPath(
                    clipper: clipper,
                    // The content keeps its natural height inside
                    // the morphing surface, laid into an
                    // OverflowBox the way lgw lays its list into the
                    // glass: the surface's clip reveals it as the
                    // surface grows. Laying it out at the surface's
                    // own height instead would make the measured
                    // height a fixed point of itself and pin the
                    // menu at the trigger's height.
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

/// lgw's LiquidMorphPhysics, ported for the values this menu's
/// single surface consumes (path/size progression and the
/// container's scale pulse). The SDF blend and anchor-blob scale
/// the full engine computes have no consumer here: they exist only
/// for the premium two-blob render path.
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

  // The J-curve back-out: (t-1)·t·((A+1)·t + A) + 1.
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

/// Reports its child's laid-out size whenever it changes, so the
/// morph can size the surface to the menu's natural height.
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
