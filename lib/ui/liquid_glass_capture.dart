part of 'liquid_glass.dart';

class LiquidGlassFade extends SingleChildRenderObjectWidget {
  const LiquidGlassFade({super.key, required this.opacity, super.child});

  final Animation<double> opacity;

  static void push(
    PaintingContext context,
    Offset offset,
    int alpha,
    PaintingContextCallback painter,
  ) {
    context.pushLayer(
      _LiquidGlassFadeLayer()
        ..alpha = alpha
        ..offset = offset,
      painter,
      Offset.zero,
    );
  }

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderLiquidGlassFade(opacity);
  }

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderLiquidGlassFade).opacity = opacity;
  }
}

class _RenderLiquidGlassFade extends RenderProxyBox {
  _RenderLiquidGlassFade(this._opacity);

  final _layer = LayerHandle<_LiquidGlassFadeLayer>();

  Animation<double> _opacity;
  set opacity(Animation<double> value) {
    if (value == _opacity) {
      return;
    }
    if (attached) {
      _opacity.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _opacity = value;
    markNeedsPaint();
  }

  int get _alpha =>
      ui.Color.getAlphaFromOpacity(_opacity.value.clamp(0.0, 1.0));

  @override
  bool get alwaysNeedsCompositing => child != null;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _opacity.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _opacity.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    _layer.layer = null;
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final alpha = _alpha;
    if (child == null || alpha == 0) {
      _layer.layer = null;
      return;
    }
    final layer = _layer.layer ??= _LiquidGlassFadeLayer();
    layer
      ..alpha = alpha
      ..offset = offset;
    context.pushLayer(layer, super.paint, Offset.zero);
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (_alpha != 0) {
      super.visitChildrenForSemantics(visitor);
    }
  }
}

class _LiquidGlassFadeLayer extends OpacityLayer {}
