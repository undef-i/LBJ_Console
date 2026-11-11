import 'package:flutter/material.dart';

class ScrollEdgeFade extends StatelessWidget {
  const ScrollEdgeFade({super.key});

  @override
  Widget build(BuildContext context) {
    final background = Theme.of(context).scaffoldBackgroundColor;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: MediaQuery.paddingOf(context).top + 100,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [background, background.withValues(alpha: 0)],
            ),
          ),
        ),
      ),
    );
  }
}
