import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'elastic_press.dart';
import 'glass_styles.dart';
import 'liquid_glass.dart';
import 'motion.dart';
import 'shape.dart';

const double _actionGap = 8;
const double _actionInset = 16;
const double _actionHeight = 48;
const double _textInset = 30;
const double _alertWidth = 348;
const double _pressGrowth = 4;
const double _pressPull = 3;
const double _pressedFillShare = 0.4;
const double _pressedDarkDefaultShare = 0.5;
const double _alertCorner = 34;
const Color _destructiveColor = Color(0xFFFF4245);

// UIAlertController on iOS 27 grows in from 1.2 times its size and only
// fades out, both on one critically damped spring that settles in 0.404 s.
const _alertDuration = Duration(milliseconds: 404);
const double _alertEntryScale = 1.2;
final _alertSpring = SpringCurve(
  SpringDescription.withDurationAndBounce(
    duration: const Duration(milliseconds: 275),
  ),
  seconds: _alertDuration.inMicroseconds / Duration.microsecondsPerSecond,
);

Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return Navigator.of(context).push<T>(
    _AlertRoute<T>(
      barrierColor: Colors.black.withValues(
        alpha: Theme.of(context).brightness == Brightness.dark ? 0.48 : 0.2,
      ),
      barrierDismissible: barrierDismissible,
      barrierLabel: barrierDismissible
          ? MaterialLocalizations.of(context).modalBarrierDismissLabel
          : null,
      builder: builder,
    ),
  );
}

class _AlertRoute<T> extends PopupRoute<T> {
  _AlertRoute({
    required this.barrierColor,
    required this.barrierDismissible,
    required this.barrierLabel,
    required this.builder,
  });

  @override
  final Color barrierColor;

  @override
  final bool barrierDismissible;

  @override
  final String? barrierLabel;

  final WidgetBuilder builder;

  CurvedAnimation? _sprung;

  Animation<double> get _spring => _sprung ??= CurvedAnimation(
    parent: animation!,
    curve: _alertSpring,
    reverseCurve: _alertSpring.flipped,
  );

  @override
  Duration get transitionDuration => _alertDuration;

  @override
  Widget buildModalBarrier() {
    if (offstage) {
      return ModalBarrier(
        dismissible: barrierDismissible,
        semanticsLabel: barrierLabel,
        barrierSemanticsDismissible: semanticsDismissible,
      );
    }
    return AnimatedModalBarrier(
      color: _spring.drive(
        ColorTween(
          begin: barrierColor.withValues(alpha: 0),
          end: barrierColor,
        ),
      ),
      dismissible: barrierDismissible,
      semanticsLabel: barrierLabel,
      barrierSemanticsDismissible: semanticsDismissible,
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _AlertTransition(animation: _spring, child: child);
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      child: SafeArea(child: Builder(builder: builder)),
    );
  }

  @override
  void dispose() {
    _sprung?.dispose();
    super.dispose();
  }
}

class _AlertTransition extends StatefulWidget {
  const _AlertTransition({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  State<_AlertTransition> createState() => _AlertTransitionState();
}

class _AlertTransitionState extends State<_AlertTransition> {
  double? _heldScale;

  double get _scale =>
      _heldScale ??
      _alertEntryScale + (1 - _alertEntryScale) * widget.animation.value;

  @override
  void initState() {
    super.initState();
    widget.animation.addStatusListener(_handleStatus);
  }

  @override
  void didUpdateWidget(_AlertTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animation != oldWidget.animation) {
      oldWidget.animation.removeStatusListener(_handleStatus);
      widget.animation.addStatusListener(_handleStatus);
    }
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_handleStatus);
    super.dispose();
  }

  void _handleStatus(AnimationStatus status) {
    _heldScale = status == AnimationStatus.reverse ? _scale : null;
  }

  @override
  Widget build(BuildContext context) {
    return LiquidGlassFade(
      opacity: widget.animation,
      child: AnimatedBuilder(
        animation: widget.animation,
        builder: (_, child) => Transform.scale(scale: _scale, child: child),
        child: widget.child,
      ),
    );
  }
}

RenderPhysicalShape? _surfaceIn(RenderObject node) {
  if (node is RenderPhysicalShape) {
    return node;
  }
  RenderPhysicalShape? surface;
  node.visitChildren((child) => surface ??= _surfaceIn(child));
  return surface;
}

Rect _surfaceRectIn(RenderBox box) {
  final surface = _surfaceIn(box);
  if (surface == null) {
    return Offset.zero & box.size;
  }
  return MatrixUtils.transformRect(
    surface.getTransformTo(box),
    Offset.zero & surface.size,
  );
}

/// An [AlertDialog] takes only a color, so the pane goes where its
/// [Material] lays out its [PhysicalShape].
class _AlertGlass extends SingleChildRenderObjectWidget {
  const _AlertGlass({
    required this.style,
    required this.rim,
    required this.shadows,
    super.child,
  });

  final LiquidGlassStyle style;
  final LiquidGlassRim rim;
  final List<BoxShadow> shadows;

  @override
  _RenderAlertGlass createRenderObject(BuildContext context) {
    return _RenderAlertGlass(style, rim, shadows);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderAlertGlass renderObject,
  ) {
    renderObject
      ..style = style
      ..rim = rim
      ..shadows = shadows;
  }
}

class _RenderAlertGlass extends RenderProxyBox {
  _RenderAlertGlass(this._style, this._rim, this._shadows);

  late final _pane = LiquidGlassPane(markNeedsPaint);

  LiquidGlassStyle _style;
  set style(LiquidGlassStyle value) {
    if (value == _style) {
      return;
    }
    _style = value;
    markNeedsPaint();
  }

  LiquidGlassRim _rim;
  set rim(LiquidGlassRim value) {
    if (value == _rim) {
      return;
    }
    _rim = value;
    markNeedsPaint();
  }

  List<BoxShadow> _shadows;
  set shadows(List<BoxShadow> value) {
    if (listEquals(value, _shadows)) {
      return;
    }
    _shadows = value;
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void dispose() {
    _pane.dispose();
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_surfaceIn(this) == null) {
      _pane.clear();
    } else {
      final rect = _surfaceRectIn(this).shift(offset);
      _pane.paint(
        context,
        rect,
        shape: LiquidGlassCorners.circular(_alertCorner),
        style: _style,
        shadows: _shadows,
        rim: _rim,
      );
      _rim.paintLine(context.canvas, rect, _alertCorner);
    }
    super.paint(context, offset);
  }
}

LiquidGlassStyle _alertStyle(ColorScheme colorScheme) =>
    glassMenuStyle(colorScheme, blur: 16);

LiquidGlassRim _alertRim(ColorScheme colorScheme) =>
    colorScheme.brightness == Brightness.dark
    ? const LiquidGlassRim(side: 0.75, corner: 0.1, flat: 0.03, shine: 0.22)
    : const LiquidGlassRim(side: 0.35, corner: 0.22, flat: 0.12, shine: 0.16);

List<BoxShadow> _alertShadows(ColorScheme colorScheme) {
  final strength = colorScheme.brightness == Brightness.dark ? 1.5 : 1.0;
  return [
    BoxShadow(
      color: colorScheme.shadow.withValues(alpha: 0.09 * strength),
      blurRadius: 16.5,
      offset: const Offset(0, 4),
    ),
    BoxShadow(
      color: colorScheme.shadow.withValues(alpha: 0.045 * strength),
      blurRadius: 42,
      offset: const Offset(0, 8),
    ),
  ];
}

class GlassDialog extends StatelessWidget {
  const GlassDialog({
    super.key,
    this.title,
    this.content,
    this.actions = const <Widget>[],
    this.destructive = false,
  });

  final Widget? title;
  final Widget? content;
  final List<Widget> actions;

  /// The last action destroys data: red on the plain fill, as in UIKit.
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final glass = LiquidGlassScope.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final fill = glass ? colorScheme.onSurface.withValues(alpha: 0.13) : null;
    final dialog = AlertDialog(
      backgroundColor: glass ? Colors.transparent : null,
      elevation: 0,
      shape: AppShape.all(_alertCorner),
      titleTextStyle: TextStyle(
        fontSize: 17,
        height: 22 / 17,
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
      ),
      contentTextStyle: TextStyle(
        fontSize: 15,
        height: 20 / 15,
        color: colorScheme.onSurfaceVariant.withValues(
          alpha: colorScheme.brightness == Brightness.dark ? 1 : 0.85,
        ),
      ),
      title: title,
      content: content == null
          ? null
          : Container(
              constraints: const BoxConstraints(
                maxWidth: _alertWidth - _textInset * 2,
              ),
              width: double.infinity,
              child: SingleChildScrollView(child: content),
            ),
      actions: actions.isEmpty
          ? null
          : [
              AlertActions(
                actions: actions,
                fill: fill,
                destructive: destructive,
              ),
            ],
      actionsPadding: const EdgeInsets.fromLTRB(
        _actionInset,
        0,
        _actionInset,
        _actionInset,
      ),
      titlePadding: const EdgeInsets.fromLTRB(_textInset, 21, _textInset, 0),
      contentPadding: EdgeInsets.fromLTRB(
        _textInset,
        title == null ? 20 : 6,
        _textInset,
        20,
      ),
    );
    return ElasticPress(
      pullPastEdges: true,
      maxGrowth: _pressGrowth,
      maxPull: _pressPull,
      panelOf: _surfaceRectIn,
      child: glass
          ? _AlertGlass(
              style: _alertStyle(colorScheme),
              rim: _alertRim(colorScheme),
              shadows: _alertShadows(colorScheme),
              child: dialog,
            )
          : dialog,
    );
  }
}

/// Text buttons laid out and filled as [GlassDialog] sets its own: the last
/// one is the default action and is filled, and the first one, the cancel
/// action by convention, ends a stack.
class AlertActions extends StatelessWidget {
  const AlertActions({
    super.key,
    required this.actions,
    this.fill,
    this.destructive = false,
  });

  final List<Widget> actions;
  final Color? fill;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return _AlertActions(
      children: [
        for (final (index, action) in actions.indexed)
          _AlertAction(
            isDefault: !destructive && index == actions.length - 1,
            destructive: destructive && index == actions.length - 1,
            fill: fill,
            child: action,
          ),
      ],
    );
  }
}

class _AlertAction extends StatelessWidget {
  const _AlertAction({
    required this.isDefault,
    required this.destructive,
    required this.fill,
    required this.child,
  });

  final bool isDefault;
  final bool destructive;
  final Color? fill;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fill = this.fill ?? colorScheme.surfaceContainerHigh;
    final foreground = isDefault
        ? colorScheme.onPrimary
        : destructive
        ? (colorScheme.brightness == Brightness.dark
              ? _destructiveColor
              : const Color(0xFFFF383C))
        : colorScheme.onSurface;
    final background = isDefault ? colorScheme.primary : fill;
    final pressedShare = switch ((isDefault, colorScheme.brightness)) {
      (true, Brightness.dark) => _pressedDarkDefaultShare,
      (false, Brightness.dark) => 1.0,
      _ => _pressedFillShare,
    };
    return TextButtonTheme(
      data: TextButtonThemeData(
        style:
            TextButton.styleFrom(
              foregroundColor: foreground,
              disabledForegroundColor: colorScheme.onSurface.withValues(
                alpha: 0.38,
              ),
              textStyle: TextStyle(
                fontSize: 17,
                height: 22 / 17,
                fontWeight: isDefault ? FontWeight.w600 : FontWeight.w500,
              ),
              minimumSize: const Size(0, _actionHeight),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: AppShape.full,
              visualDensity: VisualDensity.standard,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              splashFactory: NoSplash.splashFactory,
            ).copyWith(
              backgroundColor: WidgetStateProperty<Color?>.fromMap({
                WidgetState.disabled: fill,
                WidgetState.pressed: background.withValues(
                  alpha: background.a * pressedShare,
                ),
                WidgetState.any: background,
              }),
              overlayColor: WidgetStateProperty<Color?>.fromMap({
                WidgetState.focused: foreground.withValues(alpha: 0.1),
                WidgetState.pressed: Colors.transparent,
                WidgetState.hovered: foreground.withValues(alpha: 0.08),
              }),
            ),
      ),
      child: child,
    );
  }
}

/// Two actions side by side when both labels fit half the width; any other
/// count, or labels too long, stacked in order with the first one at the
/// bottom.
class _AlertActions extends MultiChildRenderObjectWidget {
  const _AlertActions({required super.children});

  @override
  _RenderAlertActions createRenderObject(BuildContext context) {
    return _RenderAlertActions(textDirection: Directionality.of(context));
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderAlertActions renderObject,
  ) {
    renderObject.textDirection = Directionality.of(context);
  }
}

class _AlertActionsParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderAlertActions extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _AlertActionsParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _AlertActionsParentData> {
  _RenderAlertActions({required TextDirection textDirection})
    : _textDirection = textDirection;

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) {
      return;
    }
    _textDirection = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _AlertActionsParentData) {
      child.parentData = _AlertActionsParentData();
    }
  }

  bool _sideBySide(List<RenderBox> children, double width) =>
      children.length == 2 &&
      children.every(
        (child) =>
            child.getMaxIntrinsicWidth(double.infinity) <=
            (width - _actionGap) / 2,
      );

  double _childWidth(bool sideBySide, double width) =>
      sideBySide ? (width - _actionGap) / 2 : width;

  double _widest(double Function(RenderBox child) widthOf) =>
      getChildrenAsList().map(widthOf).fold(0, math.max);

  double _heightFor(
    double width,
    double Function(RenderBox child, double width) heightOf,
  ) {
    final children = getChildrenAsList();
    if (children.isEmpty) {
      return 0;
    }
    final sideBySide = _sideBySide(children, width);
    final heights = children.map(
      (child) => heightOf(child, _childWidth(sideBySide, width)),
    );
    return sideBySide
        ? heights.reduce(math.max)
        : heights.reduce((a, b) => a + b) + _actionGap * (children.length - 1);
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      _widest((child) => child.getMinIntrinsicWidth(height));

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _widest((child) => child.getMaxIntrinsicWidth(height));

  @override
  double computeMinIntrinsicHeight(double width) =>
      _heightFor(width, (child, width) => child.getMinIntrinsicHeight(width));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _heightFor(width, (child, width) => child.getMaxIntrinsicHeight(width));

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _layout(constraints, ChildLayoutHelper.dryLayoutChild);

  @override
  void performLayout() {
    size = _layout(constraints, ChildLayoutHelper.layoutChild, place: true);
  }

  Size _layout(
    BoxConstraints constraints,
    ChildLayouter layoutChild, {
    bool place = false,
  }) {
    final children = getChildrenAsList();
    final width = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : _widest((child) => child.getMaxIntrinsicWidth(double.infinity));
    final sideBySide = _sideBySide(children, width);
    final childConstraints = BoxConstraints.tightFor(
      width: _childWidth(sideBySide, width),
    );
    final sizes = [
      for (final child in children) layoutChild(child, childConstraints),
    ];
    final height = sizes.isEmpty
        ? 0.0
        : sideBySide
        ? math.max(sizes.first.height, sizes.last.height)
        : sizes.fold(0.0, (sum, size) => sum + size.height) +
              _actionGap * (sizes.length - 1);
    if (place) {
      final rtl = _textDirection == TextDirection.rtl;
      var y = 0.0;
      for (var step = 1; step <= children.length; step++) {
        final index = step % children.length;
        final size = sizes[index];
        final parentData =
            children[index].parentData! as _AlertActionsParentData;
        if (sideBySide) {
          final atLeft = (index == 0) != rtl;
          parentData.offset = Offset(
            atLeft ? 0 : width - size.width,
            (height - size.height) / 2,
          );
        } else {
          parentData.offset = Offset(0, y);
          y += size.height + _actionGap;
        }
      }
    }
    return constraints.constrain(Size(width, height));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }
}
