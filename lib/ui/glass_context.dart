import 'package:flutter/widgets.dart';

extension LiquidGlassMotion on BuildContext {
  Duration motionDuration(Duration duration) =>
      MediaQuery.disableAnimationsOf(this) ? Duration.zero : duration;
}
