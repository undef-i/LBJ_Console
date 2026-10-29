import 'package:flutter/material.dart';

import 'liquid_glass.dart';

LiquidGlassStyle glassRegularStyle(ColorScheme colorScheme) {
  if (colorScheme.brightness == Brightness.dark) {
    return LiquidGlassStyle(
      tint: colorScheme.surfaceContainerHighest.withValues(alpha: 0.62),
      contrast: -0.4,
      saturation: 2.84,
      rim: 0.28,
      rimWidth: 1.2,
      rimTail: 0.17,
      rimFocus: 1,
      rimAdded: 0.38,
      hairlineSide: 0.75,
    );
  }
  return const LiquidGlassStyle(
    tint: Color(0x8AFDFDFD),
    contrast: 0.4,
    saturation: 2.08,
    rim: 0.28,
    rimWidth: 1.2,
    rimTail: 0.17,
    rimFocus: 1,
    rimAdded: 0.38,
    hairline: 0.25,
    hairlineSide: 0.75,
  );
}

List<BoxShadow> glassMenuShadowsOf(ColorScheme colorScheme,
    [double depth = 1]) {
  final strength = colorScheme.brightness == Brightness.dark ? 1.5 : 1.0;
  final alpha = strength * depth;
  return [
    BoxShadow(
      color: colorScheme.shadow.withValues(alpha: 0.09 * alpha),
      blurRadius: 16.5,
      offset: const Offset(0, 4),
    ),
    BoxShadow(
      color: colorScheme.shadow.withValues(alpha: 0.045 * alpha),
      blurRadius: 42,
      offset: const Offset(0, 8),
    ),
  ];
}

LiquidGlassStyle glassMenuStyle(ColorScheme colorScheme, {double blur = 12}) {
  if (colorScheme.brightness == Brightness.dark) {
    return LiquidGlassStyle(
      tint: colorScheme.surfaceContainerHighest.withValues(alpha: 0.63),
      contrast: -0.53,
      blur: blur,
      saturation: 1.75,
      brightness: 1.8,
      rim: 0,
    );
  }
  return LiquidGlassStyle(
    tint: colorScheme.surfaceBright.withValues(alpha: 0.55),
    blur: blur,
    saturation: 2,
    brightness: 1.1,
    rim: 0,
  );
}

