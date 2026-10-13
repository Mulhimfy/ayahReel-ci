import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Reports how tall its child laid out to.
///
/// The one thing a verse card cannot be asked for any other way. Both
/// screens that draw a reel need it for the same reason: in full frame
/// the watermark hangs off the *card's* bottom edge rather than the
/// frame's, so where the mark goes depends on a height only layout
/// knows — and the exporter positions its own overlay from the height
/// the rasterized PNG came back at. Three places, one number, or the
/// mark sits somewhere different in the file than on the screen.
class MeasureHeight extends SingleChildRenderObjectWidget {
  final ValueChanged<double> onChange;

  const MeasureHeight({
    super.key,
    required this.onChange,
    required Widget super.child,
  });

  @override
  RenderMeasureHeight createRenderObject(BuildContext context) =>
      RenderMeasureHeight(onChange);

  @override
  void updateRenderObject(
      BuildContext context, RenderMeasureHeight renderObject) {
    renderObject.onChange = onChange;
  }
}

class RenderMeasureHeight extends RenderProxyBox {
  RenderMeasureHeight(this.onChange);

  ValueChanged<double> onChange;
  double _reported = -1;

  @override
  void performLayout() {
    super.performLayout();
    // Only on a real change: the card relays out on every frame of a
    // verse switch, and the listener just parks the value in a field.
    if (size.height != _reported) {
      _reported = size.height;
      onChange(size.height);
    }
  }
}

/// Reports the size its child laid out to, the way [MeasureHeight]
/// reports a height — for a caller that needs both sides of it, and
/// for the same reason: what it measures is built during layout, where
/// a [GlobalKey] would be reparented on a schedule the element tree
/// does not control.
class MeasureSize extends SingleChildRenderObjectWidget {
  final ValueChanged<Size> onChange;

  const MeasureSize({
    super.key,
    required this.onChange,
    required Widget super.child,
  });

  @override
  RenderMeasureSize createRenderObject(BuildContext context) =>
      RenderMeasureSize(onChange);

  @override
  void updateRenderObject(BuildContext context, RenderMeasureSize renderObject) {
    renderObject.onChange = onChange;
  }
}

class RenderMeasureSize extends RenderProxyBox {
  RenderMeasureSize(this.onChange);

  ValueChanged<Size> onChange;
  Size? _reported;

  @override
  void performLayout() {
    super.performLayout();
    if (size != _reported) {
      _reported = size;
      onChange(size);
    }
  }
}
