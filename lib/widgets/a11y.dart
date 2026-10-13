import 'package:flutter/material.dart';

/// Screen-reader support for the app's hand-drawn controls.
///
/// Most of the app's buttons are not Material buttons: they are a
/// [GestureDetector] around a painted tablet, a pill or a tile, which
/// is exactly the shape a screen reader cannot see through. Every one
/// of those goes through [A11yTap], which tells VoiceOver and TalkBack
/// what the thing is (a button, a tab, a switch), what it says, what
/// state it is in, and what a double tap will do.
///
/// Two ways to use it:
///
///  * Without [label]: whatever text sits inside the control is read
///    as its name, and the [GestureDetector] inside keeps its own tap
///    action. Use this when the visible words already say it all.
///  * With [label]: the whole subtree is hidden from the reader and
///    replaced by [label]; [onTap] and [onLongPress] must then be
///    passed here too, because the ones inside are hidden with it.
///    Use this for icon-only controls, or when the visible text is
///    not the whole story (a tile that is also "needs download").
class A11yTap extends StatelessWidget {
  final Widget child;

  /// What the control is called. Null reads the child's own text.
  final String? label;

  /// What a double tap does, in a sentence the reader appends.
  final String? hint;

  /// The control's current value, read after the label.
  final String? value;

  /// The role. A button by default; a tab or a switch is still a
  /// button to the reader, with [selected] or [toggled] carried too.
  final bool button;

  /// Marks a chosen tab, chip or tile. Null when the control has no
  /// such state, so the reader does not say "not selected" on it.
  final bool? selected;

  /// Marks a switch. Null for anything that is not one.
  final bool? toggled;

  /// Marks a disclosure that is open or shut.
  final bool? expanded;

  final bool enabled;

  /// Only read when [label] is given; otherwise the [GestureDetector]
  /// inside supplies its own.
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const A11yTap({
    super.key,
    required this.child,
    this.label,
    this.hint,
    this.value,
    this.button = true,
    this.selected,
    this.toggled,
    this.expanded,
    this.enabled = true,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final override = label != null;
    return Semantics(
      container: true,
      button: button,
      enabled: enabled,
      selected: selected,
      toggled: toggled,
      expanded: expanded,
      label: label,
      hint: hint,
      value: value,
      // With a label of our own the child's actions are hidden with
      // its text, so the taps are re-supplied here. Without one the
      // detector inside merges its own tap in, and giving a second
      // would split the control into two nodes.
      onTap: override && enabled ? onTap : null,
      onLongPress: override && enabled ? onLongPress : null,
      excludeSemantics: override,
      child: child,
    );
  }
}

/// A value the user can nudge up and down with the screen reader's
/// adjust gesture: the stand-in for every drag on the app's timelines
/// and scrubbers, none of which a reader can perform.
class A11yAdjustable extends StatelessWidget {
  final Widget child;
  final String label;
  final String? hint;

  /// The current value, read aloud.
  final String value;

  /// Null makes the control read as busy and refuse the gesture.
  final VoidCallback? onIncrease;
  final VoidCallback? onDecrease;

  /// Whether to announce as a slider rather than a plain adjustable.
  final bool slider;

  const A11yAdjustable({
    super.key,
    required this.child,
    required this.label,
    required this.value,
    required this.onIncrease,
    required this.onDecrease,
    this.hint,
    this.slider = true,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      slider: slider,
      enabled: onIncrease != null || onDecrease != null,
      label: label,
      value: value,
      hint: hint,
      onIncrease: onIncrease,
      onDecrease: onDecrease,
      excludeSemantics: true,
      child: child,
    );
  }
}

/// A heading: lets a reader jump between the sections of a screen.
class A11yHeader extends StatelessWidget {
  final Widget child;
  const A11yHeader({super.key, required this.child});

  @override
  Widget build(BuildContext context) =>
      Semantics(container: true, header: true, child: child);
}

/// Something that appears or changes on its own and should be read
/// out when it does: a banner, a warning, a state that just changed.
///
/// A live region rather than an announcement: Android has retired
/// spoken announcements (they cut TalkBack off mid-sentence), and a
/// region the reader watches is what both platforms now ask for.
class A11yLive extends StatelessWidget {
  final Widget child;
  const A11yLive({super.key, required this.child});

  @override
  Widget build(BuildContext context) =>
      Semantics(container: true, liveRegion: true, child: child);
}
