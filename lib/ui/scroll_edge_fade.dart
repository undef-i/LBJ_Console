import 'package:flutter/material.dart';

/// The top scroll-edge fade, in the manner of iOS 26's
/// `.scrollEdgeEffectStyle(.soft)` and lgw's GlassScrollEdgeEffect
/// in its default soft style: a gradient of the page background
/// colour over the top edge, so content scrolling up under the
/// floating chrome melts into the background instead of running
/// under the title text. The zone covers the safe area plus the
/// 72pt header row plus a buffer, as lgw's sizing prescribes.
///
/// A child of a [Stack]; it never absorbs pointers.
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
              colors: [
                background,
                background.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
