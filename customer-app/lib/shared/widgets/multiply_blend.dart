import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Paints its child multiplied into whatever is already on the canvas, the
/// Flutter equivalent of CSS `mix-blend-mode: multiply`.
///
/// Cocktail and bottle photography is shot on white, so dropping it straight
/// onto a tinted card well leaves a visible white box. Multiplying makes the
/// white pixels transparent against the tint while the artwork keeps its
/// color. Cutout PNGs with real transparency would make this unnecessary —
/// until then every tinted image well on Home goes through this widget.
///
/// Each instance costs a `saveLayer`, so use it on image wells only, never
/// around a whole card or list.
class MultiplyBlend extends SingleChildRenderObjectWidget {
  const MultiplyBlend({super.key, required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderMultiplyBlend();
  }
}

class _RenderMultiplyBlend extends RenderProxyBox {
  @override
  bool get alwaysNeedsCompositing => child != null;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;

    context.canvas.saveLayer(
      offset & size,
      Paint()..blendMode = BlendMode.multiply,
    );
    super.paint(context, offset);
    context.canvas.restore();
  }
}
