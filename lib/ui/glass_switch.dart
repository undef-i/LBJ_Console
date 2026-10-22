import 'package:flutter/material.dart';

import 'elastic_press.dart';

class GlassSwitch extends StatelessWidget {
  const GlassSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  static const trackWidth = 52.0;
  static const _trackHeight = 32.0;
  static const _thumbIcon = WidgetStatePropertyAll(Icon(null));

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      label: semanticLabel,
      child: ElasticPress(
        enabled: onChanged != null,
        child: SizedBox(
          width: trackWidth,
          height: _trackHeight,
          child: OverflowBox(
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: Switch(
              value: value,
              onChanged: onChanged,
              padding: EdgeInsets.zero,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              thumbIcon: _thumbIcon,
              overlayColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.pressed)
                    ? Colors.transparent
                    : null,
              ),
              trackOutlineColor: const WidgetStatePropertyAll(
                Colors.transparent,
              ),
              trackOutlineWidth: const WidgetStatePropertyAll(0),
              trackColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? colorScheme.primary
                    : colorScheme.onSurface.withValues(alpha: 0.18),
              ),
              thumbColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? colorScheme.onPrimary
                    : Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
