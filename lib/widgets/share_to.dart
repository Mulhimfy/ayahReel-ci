import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/platform_share.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import 'a11y.dart';
import 'direct_share_button.dart' show instagramMesh, whatsappMesh;
import 'instagram_choice.dart' show InstagramGlyph;
import 'popover.dart';

/// Each target's own colours, as its app wears them.
extension ShareTargetLook on ShareTarget {
  List<Color> get colours => switch (this) {
        ShareTarget.instagramReel || ShareTarget.instagramStory =>
          instagramMesh,
        ShareTarget.tiktok => const [
            Color(0xFF25F4EE),
            Color(0xFF111111),
            Color(0xFF111111),
            Color(0xFFFE2C55),
          ],
        ShareTarget.youtube => const [Color(0xFFFF2D2D), Color(0xFFCC0000)],
        ShareTarget.whatsapp => whatsappMesh,
      };

  String label(L10n l) => switch (this) {
        ShareTarget.instagramReel => l.shareToInstagramReel,
        ShareTarget.instagramStory => l.shareToInstagramStory,
        ShareTarget.tiktok => 'TikTok',
        ShareTarget.youtube => l.shareToYouTube,
        ShareTarget.whatsapp => 'WhatsApp',
      };
}

/// Opens the platforms a reel can go straight to, rising out of [anchor]
/// (the Share to button): one button per app, in the app's own colours,
/// arriving one after another. Answers with the one tapped, or null.
Future<ShareTarget?> showShareTo(BuildContext anchor,
    {required List<ShareTarget> targets}) {
  return showPopover<ShareTarget>(
    anchor,
    preferAbove: true,
    dim: true,
    builder: (context) => _ShareToPanel(targets: targets),
  );
}

class _ShareToPanel extends StatefulWidget {
  final List<ShareTarget> targets;
  const _ShareToPanel({required this.targets});

  @override
  State<_ShareToPanel> createState() => _ShareToPanelState();
}

class _ShareToPanelState extends State<_ShareToPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 260 + 70 * widget.targets.length),
  )..forward();

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final n = widget.targets.length;
    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: 238,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 26,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
              child: Text(
                l.shareToCaptionNote,
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.3,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            for (var i = 0; i < n; i++) ...[
              if (i > 0) const SizedBox(height: 6),
              AnimatedBuilder(
                animation: _in,
                builder: (context, child) {
                  // Each a beat after the one above it: the nearest the
                  // button first, as if they rise out of it.
                  final from = (n - 1 - i) * 70 / _in.duration!.inMilliseconds;
                  final v = Curves.easeOutBack.transform(
                      ((_in.value - from) / (1 - from).clamp(0.01, 1.0))
                          .clamp(0.0, 1.0));
                  return Opacity(
                    opacity: v.clamp(0.0, 1.0),
                    child: Transform.translate(
                      offset: Offset(0, 14 * (1 - v)),
                      child: Transform.scale(
                          scale: 0.92 + 0.08 * v, child: child),
                    ),
                  );
                },
                child: _TargetButton(
                  target: widget.targets[i],
                  label: widget.targets[i].label(l),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Navigator.of(context).pop(widget.targets[i]);
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One app, in its colours: its mark and its name.
class _TargetButton extends StatelessWidget {
  final ShareTarget target;
  final String label;
  final VoidCallback onTap;

  const _TargetButton({
    required this.target,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colours = target.colours;
    return A11yTap(
      label: label,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: colours,
            ),
            boxShadow: [
              BoxShadow(
                color: colours.last.withValues(alpha: 0.30),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              SizedBox(width: 22, height: 22, child: _mark(target)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    shadows: [Shadow(color: Color(0x55000000), blurRadius: 6)],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _mark(ShareTarget t) => switch (t) {
        ShareTarget.instagramReel ||
        ShareTarget.instagramStory =>
          const InstagramGlyph(),
        ShareTarget.tiktok => const CustomPaint(painter: _TikTokPainter()),
        ShareTarget.youtube => const CustomPaint(painter: _YouTubePainter()),
        ShareTarget.whatsapp =>
          const Icon(Icons.send_rounded, size: 19, color: Colors.white),
      };
}

/// TikTok's note, drawn: the stem and its hook, cyan behind and pink in
/// front, white over both.
class _TikTokPainter extends CustomPainter {
  const _TikTokPainter();

  Path _note(Size s) {
    final w = s.width, h = s.height;
    return Path()
      ..moveTo(w * 0.52, h * 0.10)
      ..lineTo(w * 0.52, h * 0.66)
      ..addOval(Rect.fromCircle(
          center: Offset(w * 0.38, h * 0.68), radius: w * 0.16))
      ..moveTo(w * 0.52, h * 0.12)
      ..quadraticBezierTo(w * 0.60, h * 0.32, w * 0.82, h * 0.34);
  }

  @override
  void paint(Canvas canvas, Size size) {
    Paint stroke(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.13
      ..strokeCap = StrokeCap.round;
    canvas.save();
    canvas.translate(-1.2, -1.2);
    canvas.drawPath(_note(size), stroke(const Color(0xFF25F4EE)));
    canvas.restore();
    canvas.save();
    canvas.translate(1.2, 1.2);
    canvas.drawPath(_note(size), stroke(const Color(0xFFFE2C55)));
    canvas.restore();
    canvas.drawPath(_note(size), stroke(Colors.white));
  }

  @override
  bool shouldRepaint(covariant _TikTokPainter old) => false;
}

/// YouTube's mark: a white rounded screen with the play in it.
class _YouTubePainter extends CustomPainter {
  const _YouTubePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromCenter(
        center: size.center(Offset.zero),
        width: size.width,
        height: size.height * 0.72);
    canvas.drawRRect(
        RRect.fromRectAndRadius(r, Radius.circular(size.height * 0.2)),
        Paint()..color = Colors.white);
    final c = r.center;
    final k = size.width * 0.17;
    canvas.drawPath(
      Path()
        ..moveTo(c.dx - k * 0.8, c.dy - k)
        ..lineTo(c.dx + k * 1.1, c.dy)
        ..lineTo(c.dx - k * 0.8, c.dy + k)
        ..close(),
      Paint()..color = const Color(0xFFE60000),
    );
  }

  @override
  bool shouldRepaint(covariant _YouTubePainter old) => false;
}

/// The reel screen's "Share to": beside the share sheet's button, a pill
/// carrying a dot of each app's colour, which opens [showShareTo].
class ShareToButton extends StatelessWidget {
  final List<ShareTarget> targets;
  final ValueChanged<ShareTarget>? onPick;
  final double height;

  const ShareToButton({
    super.key,
    required this.targets,
    required this.onPick,
    this.height = 46,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final enabled = onPick != null && targets.isNotEmpty;
    // One dot per app, not per way into it: Instagram's two are one dot.
    final dots = <List<Color>>[];
    for (final t in targets) {
      if (t == ShareTarget.instagramStory &&
          targets.contains(ShareTarget.instagramReel)) {
        continue;
      }
      dots.add(t.colours);
    }
    return A11yTap(
      label: l.shareTo,
      enabled: enabled,
      onTap: enabled ? () => _open(context) : null,
      child: Builder(
        builder: (anchor) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? () => _open(anchor) : null,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: enabled ? 1 : 0.45,
            child: Container(
              height: height,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(height / 2),
                color: AppColors.surfaceRaised,
                border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      l.shareTo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 12.0 + 9 * math.max(0, dots.length - 1),
                    height: 14,
                    child: Stack(
                      children: [
                        for (var i = 0; i < dots.length; i++)
                          Positioned(
                            left: 9.0 * i,
                            top: 1,
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(colors: dots[i]),
                                border: Border.all(
                                    color: AppColors.surfaceRaised, width: 1.4),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.expand_less_rounded,
                      size: 18, color: AppColors.textSecondary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext anchor) async {
    final picked = await showShareTo(anchor, targets: targets);
    if (picked != null) onPick?.call(picked);
  }
}
