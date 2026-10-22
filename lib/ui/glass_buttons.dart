import 'package:flutter/material.dart';

import 'glass_fallback.dart';
import 'glass_styles.dart';
import 'liquid_glass.dart';
import 'shape.dart';

class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.translucent = false,
  });

  final IconData icon;
  final VoidCallback onPressed;

  /// Over a platform view the capture glass renders solid; a plain
  /// translucent disc composites over the map instead.
  final bool translucent;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (translucent) {
      return FallbackGlass(
        shape: AppShape.full,
        shadows: glassMenuShadowsOf(colorScheme),
        child: SizedBox(
          width: 40,
          height: 40,
          child: IconButton(
            onPressed: onPressed,
            icon: Icon(icon, color: colorScheme.onSurface, size: 20),
            padding: EdgeInsets.zero,
          ),
        ),
      );
    }
    // The regular tinted pane, not the clear lens: over map tiles a
    // transparent lens disc is invisible and the glyph washes out.
    return LiquidGlass(
      style: glassRegularStyle(colorScheme),
      shadows: glassMenuShadowsOf(colorScheme),
      child: SizedBox(
        width: 40,
        height: 40,
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon, color: colorScheme.onSurface, size: 20),
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }
}
