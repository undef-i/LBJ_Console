import 'package:flutter/material.dart';

import 'shape.dart';

/// Geometry-only glass for what floats over a platform view (the
/// map). The capture glass cannot see a platform view: its backdrop
/// replay paints the page background and nothing of the map, so a
/// shader pane over the map can only ever come out solid. This
/// surface keeps the glass geometry, a translucent gradient tint
/// with a lit top edge and a hairline rim, and composites it with
/// plain alpha over the map, so the map genuinely shows through;
/// there is no refraction because there is no backdrop to refract.
class FallbackGlass extends StatelessWidget {
  const FallbackGlass({
    super.key,
    required this.shape,
    this.shadows = const [],
    required this.child,
  });

  final OutlinedBorder shape;
  final List<BoxShadow> shadows;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dark = colorScheme.brightness == Brightness.dark;
    final base = colorScheme.surfaceContainerHigh;
    final alpha = dark ? 0.74 : 0.8;
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        shadows: shadows,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(base, Colors.white, dark ? 0.10 : 0.30)!
                .withValues(alpha: alpha),
            base.withValues(alpha: alpha),
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  shape: shape.copyWith(
                    side: BorderSide(
                      color: colorScheme.onSurface.withValues(
                        alpha: dark ? 0.16 : 0.12,
                      ),
                      width: 1,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: ClipPath(
                clipper: ShapeBorderClipper(shape: shape),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: dark ? 0.07 : 0.22),
                        Colors.white.withValues(alpha: 0),
                      ],
                      stops: const [0, 0.45],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
