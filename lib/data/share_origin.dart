import 'package:flutter/widgets.dart';

/// Where iOS anchors the share sheet.
///
/// iOS refuses to open the sheet without this. share_plus throws
///
///     PlatformException(error, sharePositionOrigin: argument must be
///     set, {{0, 0}, {0, 0}} must be non-zero and within coordinate
///     space of source view: {{0, 0}, {414, 896}})
///
/// on every share where the rect is missing — iPhone included, not just
/// iPad, where it additionally decides where the popover points. So the
/// contract is two-sided: the rect must be non-empty AND must lie
/// inside the Flutter view. Both are enforced here so no call site can
/// get it wrong. Android ignores the value entirely.
///
/// [context] should belong to the widget that was tapped; the result is
/// that widget's bounds in global (screen) coordinates. Capture it
/// *before* popping any route the button lives on, and before any long
/// await — an unmounted or relaid-out element has no box to measure.
Rect shareOriginOf(BuildContext context) {
  final view = View.of(context);
  final bounds = Offset.zero & (view.physicalSize / view.devicePixelRatio);
  final box = context.findRenderObject() as RenderBox?;
  if (box != null && box.attached && box.hasSize && !box.size.isEmpty) {
    // A button scrolled half off-screen, or one measured mid-transition,
    // can sit partly outside the view; iOS rejects that outright.
    final clipped = (box.localToGlobal(Offset.zero) & box.size)
        .intersect(bounds);
    if (clipped.width > 0 && clipped.height > 0) return clipped;
  }
  // Deliberately never empty — an empty rect is the exception above.
  // The centre of the screen is somewhere iOS will always accept.
  return Rect.fromCenter(center: bounds.center, width: 1, height: 1);
}
