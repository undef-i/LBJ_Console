import 'package:flutter/material.dart';

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
