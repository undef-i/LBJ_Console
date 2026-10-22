import 'package:flutter/material.dart';

import 'elastic_press.dart';
import 'shape.dart';

Color flCardColor(ColorScheme scheme) => scheme.brightness == Brightness.dark
    ? scheme.surfaceContainer
    : scheme.surfaceBright;

/// The surface one level above the card: field and tonal-button fills.
Color flBlockColor(ColorScheme scheme) => scheme.brightness == Brightness.dark
    ? scheme.surfaceContainerHigh
    : scheme.surfaceContainer;

TextStyle flListTitleStyle(ColorScheme scheme) => TextStyle(
      fontSize: 17,
      height: 22 / 17,
      color: scheme.onSurface,
    );

TextStyle flListSubtitleStyle(ColorScheme scheme) => TextStyle(
      fontSize: 15,
      height: 20 / 15,
      color: scheme.onSurfaceVariant,
    );

TextStyle flCaptionStyle(ColorScheme scheme) => TextStyle(
      fontSize: 13,
      height: 18 / 13,
      color: scheme.onSurfaceVariant,
    );

class FlSection extends StatelessWidget {
  const FlSection({super.key, this.title, this.footer, required this.rows});

  final String? title;
  final String? footer;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text(title!, style: flCaptionStyle(scheme)),
          ),
        ClipPath(
          clipper: ShapeBorderClipper(shape: AppShape.all(AppCorner.xl)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                Container(color: flCardColor(scheme), child: rows[i]),
                if (i < rows.length - 1)
                  Container(
                    color: flCardColor(scheme),
                    padding: const EdgeInsets.only(left: 16, right: 14),
                    child: Divider(
                      height: 1,
                      thickness: 1,
                      color: scheme.outlineVariant.withValues(alpha: 0.55),
                    ),
                  ),
              ],
            ],
          ),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(footer!, style: flCaptionStyle(scheme)),
          ),
      ],
    );
  }
}

class FlRow extends StatelessWidget {
  const FlRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.titleStyle,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DefaultTextStyle(
                  style: titleStyle ?? flListTitleStyle(scheme),
                  child: title,
                ),
                if (subtitle != null)
                  DefaultTextStyle(
                    style: flListSubtitleStyle(scheme),
                    child: subtitle!,
                  ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
    if (onTap == null) return content;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}

class FlTonalButton extends StatelessWidget {
  const FlTonalButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.height = 36,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = FilledButton.styleFrom(
      backgroundColor: scheme.onSurface.withValues(alpha: 0.08),
      foregroundColor: scheme.onSurface,
      elevation: 0,
      minimumSize: Size(0, height),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      shape: const StadiumBorder(),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
    );
    return ElasticPress(
      enabled: onPressed != null,
      child: icon == null
          ? FilledButton(
              onPressed: onPressed,
              style: style,
              child: Text(label),
            )
          : FilledButton.icon(
              onPressed: onPressed,
              style: style,
              icon: Icon(icon, size: 20),
              label: Text(label),
            ),
    );
  }
}
