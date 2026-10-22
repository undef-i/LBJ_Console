import 'dart:math' as math;
import 'dart:ui' as ui show ImageFilter, lerpDouble;

import 'package:flutter/material.dart';

import 'elastic_press.dart';
import 'glass_styles.dart';
import 'liquid_glass.dart';
import 'motion.dart';
import 'shape.dart';

class GlassSelect<T> extends StatelessWidget {
  const GlassSelect({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;

  String _labelOf(DropdownMenuItem<T> item) {
    final child = item.child;
    return child is Text ? child.data ?? '' : '';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = items.firstWhere(
      (item) => item.value == value,
      orElse: () => items.first,
    );
    return ElasticPress(
      enabled: onChanged != null,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onChanged == null
              ? null
              : () async {
                  final box = context.findRenderObject()! as RenderBox;
                  final origin = box.localToGlobal(Offset.zero);
                  final picked = await Navigator.of(context).push<T>(
                    _SelectRoute<T>(
                      anchor: origin & box.size,
                      dismissLabel: MaterialLocalizations.of(
                        context,
                      ).modalBarrierDismissLabel,
                      value: value,
                      items: [
                        for (final item in items)
                          (value: item.value, label: _labelOf(item)),
                      ],
                    ),
                  );
                  if (picked != null) onChanged!(picked);
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _labelOf(selected),
                  style: TextStyle(
                    fontSize: 17,
                    height: 22 / 17,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.unfold_more,
                  size: 20,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const _cardInset = 8.0;
const _itemRadius = AppCorner.md;
const _cardRadius = _itemRadius + _cardInset;
const _screenMargin = 16.0;
const _anchorOverlap = 8.0;
const _menuMinWidth = 160.0;
const _menuMaxWidth = 280.0;
const _maxContentBlur = 8.0;
const _dismissScale = 0.8;

const _openDuration = Duration(milliseconds: 750);
const _shrinkDuration = Duration(milliseconds: 200);
const _openSeconds = 0.75;

final _growSpring = SpringCurve(
  SpringDescription.withDurationAndBounce(
    duration: const Duration(milliseconds: 500),
    bounce: 0.3,
  ),
  seconds: _openSeconds,
);

final _moveYSpring = SpringCurve(
  SpringDescription.withDurationAndBounce(
    duration: const Duration(milliseconds: 340),
    bounce: 0.12,
  ),
  seconds: _openSeconds,
);

final _moveXSpring = SpringCurve(
  SpringDescription.withDurationAndBounce(
    duration: const Duration(milliseconds: 520),
    bounce: 0.2,
  ),
  seconds: _openSeconds,
);

const _contentReveal = Interval(0.04, 0.45, curve: Curves.easeOutCubic);

class _SelectRoute<T> extends PopupRoute<T> {
  _SelectRoute({
    required this.anchor,
    required this.dismissLabel,
    required this.value,
    required this.items,
  });

  final Rect anchor;
  final String dismissLabel;
  final T value;
  final List<({T? value, String label})> items;

  Rect _finalRect = Rect.zero;
  double _closingFrom = 1;

  late final CurvedAnimation _grow = CurvedAnimation(
    parent: animation!,
    curve: _growSpring,
  );

  late final CurvedAnimation _moveX = CurvedAnimation(
    parent: animation!,
    curve: _moveXSpring,
  );

  late final CurvedAnimation _moveY = CurvedAnimation(
    parent: animation!,
    curve: _moveYSpring,
  );

  @override
  Color get barrierColor => Colors.transparent;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => dismissLabel;

  @override
  Duration get transitionDuration => _openDuration;

  @override
  Duration get reverseTransitionDuration => _shrinkDuration;

  @override
  void install() {
    super.install();
    animation!.addStatusListener(_handleStatusChanged);
  }

  void _handleStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.reverse) {
      _closingFrom = animation!.value;
    }
  }

  @override
  void dispose() {
    animation!.removeStatusListener(_handleStatusChanged);
    _grow.dispose();
    _moveX.dispose();
    _moveY.dispose();
    super.dispose();
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final media = MediaQuery.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final labelStyle = TextStyle(
      fontSize: 15,
      height: 20 / 15,
      color: colorScheme.onSurface,
    );
    var menuWidth = _menuMinWidth;
    for (final item in items) {
      final painter = TextPainter(
        text: TextSpan(text: item.label, style: labelStyle),
        textDirection: Directionality.of(context),
      )..layout();
      final checked = item.value == value;
      final rowWidth = (checked ? 20.0 : 24.0) +
          painter.width +
          (checked ? 8 + 16 : 0);
      menuWidth = math.max(menuWidth, rowWidth + 2 * _cardInset);
      painter.dispose();
    }
    menuWidth = menuWidth.clamp(_menuMinWidth, _menuMaxWidth);
    final menuHeight = items.length * 44.0 + 2 * _cardInset;
    final insets = media.padding + const EdgeInsets.all(_screenMargin);
    final maxX = media.size.width - insets.right - menuWidth;
    final maxY = media.size.height - insets.bottom - menuHeight;
    final left = (anchor.right - menuWidth)
        .clamp(insets.left, math.max(insets.left, maxX))
        .toDouble();
    final y0 = anchor.top - _anchorOverlap;
    final minY = math.max(
      media.padding.top,
      math.min(insets.top, y0),
    );
    final top = y0.clamp(minY, math.max(minY, maxY)).toDouble();
    _finalRect = Rect.fromLTWH(left, top, menuWidth, menuHeight);
    return SizedBox(
      width: menuWidth,
      height: menuHeight,
      child: Padding(
        padding: const EdgeInsets.all(_cardInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final item in items)
              Material(
                type: MaterialType.transparency,
                child: InkWell(
                  customBorder: AppShape.all(_itemRadius),
                  splashFactory: NoSplash.splashFactory,
                  highlightColor: Colors.transparent,
                  onTap: () => Navigator.of(context).pop(item.value),
                  child: Padding(
                    padding: item.value == value
                        ? const EdgeInsets.only(
                            left: 12,
                            top: 12,
                            bottom: 12,
                            right: 8,
                          )
                        : const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: labelStyle,
                          ),
                        ),
                        if (item.value == value) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.check,
                            size: 16,
                            color: colorScheme.onSurface,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        if (animation.status == AnimationStatus.reverse) {
          return _buildDismissal(context, animation, child!);
        }
        final grow = _grow.value;
        final width = anchor.width + (_finalRect.width - anchor.width) * grow;
        final height =
            anchor.height + (_finalRect.height - anchor.height) * grow;
        final centerX = anchor.center.dx +
            (_finalRect.center.dx - anchor.center.dx) * _moveX.value;
        final centerY = anchor.center.dy +
            (_finalRect.center.dy - anchor.center.dy) * _moveY.value;
        final rect = Rect.fromCenter(
          center: Offset(centerX, centerY),
          width: width,
          height: height,
        );
        final radius = math.max(
          0.0,
          ui.lerpDouble(anchor.shortestSide / 2, _cardRadius, grow) ??
              _cardRadius,
        );
        final clipper = ShapeBorderClipper(shape: AppShape.all(radius));
        final reveal = _contentReveal.transform(animation.value);
        final coverScale = math.max(
          rect.width / _finalRect.width,
          rect.height / _finalRect.height,
        );
        return Stack(
          children: [
            Positioned.fromRect(
              rect: rect,
              child: LiquidGlass(
                style: LiquidGlassStyle.lerp(
                  glassRegularStyle(colorScheme),
                  glassMenuStyle(colorScheme),
                  grow.clamp(0.0, 1.0),
                ),
                shadows: glassMenuShadowsOf(colorScheme),
                clipper: clipper,
                child: ClipPath(
                  clipper: clipper,
                  child: Center(
                    child: Opacity(
                      opacity: reveal,
                      child: ImageFiltered(
                        enabled: reveal < 1,
                        imageFilter: ui.ImageFilter.blur(
                          sigmaX: _maxContentBlur * (1 - reveal),
                          sigmaY: _maxContentBlur * (1 - reveal),
                        ),
                        child: Transform.scale(
                          scale: coverScale,
                          child: SizedBox(
                            width: _finalRect.width,
                            height: _finalRect.height,
                            child: child,
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

  Widget _buildDismissal(
    BuildContext context,
    Animation<double> animation,
    Widget child,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final from = _closingFrom;
    final dismissal =
        from <= 0 ? 1.0 : (1 - animation.value / from).clamp(0.0, 1.0);
    final shrink = Curves.easeOut.transform(dismissal);
    final scale = ui.lerpDouble(1, _dismissScale, shrink)!;
    final center = anchor.center;
    final transform = Matrix4.translationValues(center.dx, center.dy, 0)
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-center.dx, -center.dy, 0, 1);
    final clipper = ShapeBorderClipper(shape: AppShape.all(_cardRadius));
    return Transform(
      transform: transform,
      child: Opacity(
        opacity: 1 - shrink,
        child: Stack(
          children: [
            Positioned.fromRect(
              rect: _finalRect,
              child: LiquidGlass(
                style: glassMenuStyle(colorScheme),
                shadows: glassMenuShadowsOf(colorScheme),
                clipper: clipper,
                child: ClipPath(clipper: clipper, child: child),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
