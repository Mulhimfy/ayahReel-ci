import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A small panel that opens out of the control that asked for it and
/// stays tied to it: under it (or over it, near the foot of the
/// screen), lined up with its end edge, growing out of that corner.
///
/// For a choice that belongs to one control — a menu of what goes on a
/// card, a palette — where a sheet from the bottom of the screen would
/// carry the question away from the thing it is about. A tap outside
/// closes it. With [dim] off, nothing behind it is darkened, so what
/// the panel changes can be watched changing while it is open.
Future<T?> showPopover<T>(
  BuildContext anchor, {
  required WidgetBuilder builder,
  bool dim = false,
  bool preferAbove = false,
}) {
  final navigator = Navigator.of(anchor);
  final overlay = navigator.overlay?.context.findRenderObject();
  final box = anchor.findRenderObject();
  Rect? at;
  if (overlay is RenderBox && box is RenderBox && box.hasSize) {
    at = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
  }
  HapticFeedback.selectionClick();
  return navigator.push(_PopoverRoute<T>(
    anchor: at,
    builder: builder,
    dim: dim,
    preferAbove: preferAbove,
    direction: Directionality.of(anchor),
    barrierLabel: MaterialLocalizations.of(anchor).modalBarrierDismissLabel,
  ));
}

class _PopoverRoute<T> extends PopupRoute<T> {
  _PopoverRoute({
    required this.anchor,
    required this.builder,
    required this.dim,
    required this.preferAbove,
    required this.direction,
    required this.barrierLabel,
  });

  final Rect? anchor;
  final WidgetBuilder builder;
  final bool dim;
  final bool preferAbove;
  final TextDirection direction;

  @override
  final String? barrierLabel;

  @override
  Color? get barrierColor =>
      dim ? Colors.black.withValues(alpha: 0.3) : Colors.transparent;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 160);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final placement = _Placement(
      anchor: anchor,
      preferAbove: preferAbove,
      direction: direction,
      padding: MediaQuery.paddingOf(context),
    );
    final grow = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    );
    return CustomSingleChildLayout(
      delegate: placement,
      child: AnimatedBuilder(
        animation: grow,
        builder: (context, child) {
          final t = reduce ? animation.value : grow.value;
          final above = placement.opensAbove;
          // Out of the corner nearest the control, with a lean that
          // settles flat — a card turned up off the table.
          final origin = direction == TextDirection.rtl
              ? (above ? Alignment.bottomLeft : Alignment.topLeft)
              : (above ? Alignment.bottomRight : Alignment.topRight);
          final lean = reduce ? 0.0 : (1 - t.clamp(0.0, 1.0)) * 0.42;
          final m = Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateX(above ? lean : -lean)
            ..scaleByDouble(0.88 + 0.12 * t, 0.88 + 0.12 * t, 1, 1);
          return Opacity(
            opacity: animation.value.clamp(0.0, 1.0),
            child: Transform(alignment: origin, transform: m, child: child),
          );
        },
        child: Material(
          type: MaterialType.transparency,
          child: Semantics(
            scopesRoute: true,
            explicitChildNodes: true,
            child: builder(context),
          ),
        ),
      ),
    );
  }
}

class _Placement extends SingleChildLayoutDelegate {
  final Rect? anchor;
  final bool preferAbove;
  final TextDirection direction;
  final EdgeInsets padding;

  _Placement({
    required this.anchor,
    required this.preferAbove,
    required this.direction,
    required this.padding,
  });

  static const _margin = 12.0;
  static const _gap = 8.0;

  /// Settled during layout; read by the transition for its origin.
  bool opensAbove = false;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.biggest).deflate(EdgeInsets.fromLTRB(
          _margin, padding.top + _margin, _margin, padding.bottom + _margin));

  @override
  Offset getPositionForChild(Size size, Size child) {
    final a = anchor;
    if (a == null) {
      opensAbove = false;
      return Offset((size.width - child.width) / 2,
          (size.height - child.height) / 2);
    }
    final double maxX = math.max(_margin, size.width - child.width - _margin);
    final double x = (direction == TextDirection.rtl
            ? a.left
            : a.right - child.width)
        .clamp(_margin, maxX)
        .toDouble();
    final below = a.bottom + _gap;
    final above = a.top - _gap - child.height;
    final fitsBelow = below + child.height <= size.height - padding.bottom;
    final fitsAbove = above >= padding.top + _margin;
    opensAbove = preferAbove ? fitsAbove || !fitsBelow : !fitsBelow && fitsAbove;
    final double y = opensAbove ? above : below;
    final double maxY =
        math.max(padding.top, size.height - child.height - _margin);
    return Offset(x, y.clamp(padding.top, maxY).toDouble());
  }

  @override
  bool shouldRelayout(_Placement old) =>
      old.anchor != anchor ||
      old.preferAbove != preferAbove ||
      old.direction != direction ||
      old.padding != padding;
}
