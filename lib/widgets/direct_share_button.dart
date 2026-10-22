import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

/// Instagram's own sweep, the way its icon runs it: sun, then pink,
/// then violet. A shade under the brand values, so it sits in a dark
/// UI without glowing louder than the gold button beside it.
///
/// One definition, shared: the preview's "To Instagram" and the
/// invite sheet's "To Instagram story" are two doors to the same app,
/// and they must be the same colour or the hand stops trusting either.
const instagramMesh = [
  Color(0xFFF0943A),
  Color(0xFFDE2C5A),
  Color(0xFFB8218F),
  Color(0xFF6A3BB4),
];

/// WhatsApp's greens, from its bright bubble down to its teal.
const whatsappMesh = [
  Color(0xFF3FD27C),
  Color(0xFF22A85C),
  Color(0xFF0F7A63),
];

/// A straight-to-an-app button: skips the share sheet and hands
/// something to a named app.
///
/// Filled with that app's colours rather than this app's gold, so it
/// reads as a door to another place and not as one more Share.
/// Dimmed, not restyled, while there is nothing to hand over yet.
class DirectShareButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback? onPressed;

  /// Drawn in place of [icon] when the door has a mark the icon font
  /// does not carry — Instagram's camera.
  final Widget? leading;

  /// Overall height. The preview runs a short one under its Share; the
  /// invite sheet runs one the height of the gold button beside it.
  final double height;

  /// Shows a spinner in place of the label while the thing being
  /// handed over is still being made.
  final bool busy;

  const DirectShareButton({
    super.key,
    required this.label,
    required this.icon,
    required this.colors,
    required this.onPressed,
    this.height = 40,
    this.busy = false,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final on = onPressed != null && !busy;
    // A painted button, so it says what it is: named after the app it
    // hands over to, dimmed when there is nothing to hand over yet,
    // and still named while the spinner stands in for the words.
    return Semantics(
      container: true,
      button: true,
      enabled: on,
      label: busy ? L10n.of(context).a11yBusy(label) : null,
      // The InkWell below supplies the tap; a second one here would
      // split the button into two nodes.
      excludeSemantics: busy,
      child: AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: on || busy ? 1 : 0.45,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          borderRadius: BorderRadius.circular(13),
          boxShadow: [
            if (on)
              BoxShadow(
                color: colors[colors.length ~/ 2].withValues(alpha: 0.32),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(13),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: on ? onPressed : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: busy
                  ? const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      ),
                    )
                  // A new word (say, "copied" for a moment) slides in
                  // over the old one rather than blinking.
                  : AnimatedSwitcher(
                      duration: const Duration(milliseconds: 240),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, a) => FadeTransition(
                        opacity: a,
                        child: SlideTransition(
                          position: Tween(
                                  begin: const Offset(0, 0.35),
                                  end: Offset.zero)
                              .animate(a),
                          child: child,
                        ),
                      ),
                      child: Row(
                        key: ValueKey(label),
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          leading ??
                              Icon(icon, size: 15, color: Colors.white),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
      ),
    );
  }
}
