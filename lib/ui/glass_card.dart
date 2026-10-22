import 'package:flutter/material.dart';

import 'shape.dart';

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    this.margin,
    this.radius = 16,
    this.selected = false,
    required this.child,
  });

  final EdgeInsetsGeometry? margin;
  final double radius;
  final bool selected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final shape = AppShape.all(radius);
    final clipper = ShapeBorderClipper(shape: shape);
    Widget content = Stack(
      children: [
        Container(
          decoration: ShapeDecoration(
            color: colorScheme.brightness == Brightness.dark
                ? colorScheme.surfaceContainer
                : colorScheme.surfaceBright,
            shape: shape,
          ),
          child: ClipPath(clipper: clipper, child: child),
        ),
        if (selected)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  shape: shape.copyWith(
                    side: BorderSide(color: colorScheme.primary, width: 2),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
    if (margin != null) {
      content = Padding(padding: margin!, child: content);
    }
    return content;
  }
}
