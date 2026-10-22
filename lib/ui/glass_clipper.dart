import 'package:flutter/widgets.dart';

import 'shape.dart';

class SuperellipseClipper extends CustomClipper<Path> {
  const SuperellipseClipper(this.borderRadius);

  final BorderRadius borderRadius;

  @override
  Path getClip(Size size) =>
      AppShape.of(borderRadius).getOuterPath(Offset.zero & size);

  @override
  bool shouldReclip(SuperellipseClipper oldClipper) =>
      oldClipper.borderRadius != borderRadius;
}
