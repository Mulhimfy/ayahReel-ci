import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/app_share.dart';
import '../data/debug_log.dart';
import '../data/instagram_share.dart';
import '../data/share_origin.dart';
import '../l10n/l10n.dart';
import '../render/invite_story.dart';
import '../theme/app_theme.dart';
import 'a11y.dart';
import 'app_toast.dart';
import 'direct_share_button.dart';
import 'glow_button.dart';
import 'mesh_glass.dart';
import 'night_sky.dart';
import 'ambient_pace.dart';

/// The reason to pass the app on, said once, before the share sheet
/// opens.
///
/// Handing someone this app is not a referral — it is the same deed
/// they will go on to do, credited again to whoever pointed the way.
/// That is worth a screen of its own; a share sheet that opens with no
/// explanation is just a favour being asked.
///
/// It closes only by its own buttons — sharing, or Not now and its one
/// question — never by a tap beside it or a swipe down (the owner's call,
/// 2026-10-26); Back asks the same question Not now does.
Future<void> showInviteSheet(BuildContext context) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => const _InviteSheet(),
  );
}

/// One gentle second thought before the sheet closes. Not a guilt trip:
/// a single question, and either answer ends it.
Future<void> _confirmLeave(BuildContext context) async {
  final navigator = Navigator.of(context);
  final leave = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final l = L10n.of(dialogContext);
      return AlertDialog(
        backgroundColor: AppColors.surfaceRaised,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        content: Text(
          l.loseRewardsConfirm,
          textAlign: TextAlign.center,
          style: Theme.of(dialogContext)
              .textTheme
              .bodyMedium
              ?.copyWith(height: 1.5),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          QuietButton(
            label: l.leave,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
          QuietButton(
            label: l.stay,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
        ],
      );
    },
  );
  if (leave ?? false) navigator.pop();
}

class _InviteSheet extends StatefulWidget {
  const _InviteSheet();

  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet>
    with AmbientTickerProviderStateMixin {
  /// The story card is drawn on the way out, and the button shows the
  /// wait rather than going dead for it.
  bool _storyBusy = false;

  /// The emblem's people going round, the ripples, and the light in the
  /// sheet's ground.
  late final AnimationController _clock = AnimationController(
    vsync: ambient,
    duration: const Duration(seconds: 9),
  )..repeat();

  /// The way in: the emblem opening out, then the words, the hadith
  /// turning up into view, and the buttons, one after another.
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
  )..forward();

  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still == _still) return;
    _still = still;
    if (still) {
      _clock.value = 0.2;
      _enter.value = 1;
    } else {
      _clock.repeat();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    _enter.dispose();
    super.dispose();
  }

  /// Straight into Instagram's story composer with the invite card as
  /// the story's background. The card is rendered first, while the
  /// sheet is still up; then the sheet closes and the hand-off runs
  /// exactly as the share button's does — nothing here may touch this
  /// context once the pop has happened.
  Future<void> _toStory(BuildContext buttonContext) async {
    final messenger = ScaffoldMessenger.of(buttonContext);
    final origin = shareOriginOf(buttonContext);
    final navigator = Navigator.of(buttonContext);
    HapticFeedback.selectionClick();
    setState(() => _storyBusy = true);
    final File card;
    try {
      card = await InviteStory.render();
    } catch (e, s) {
      rlogError('invite story', e, s);
      if (!mounted) return;
      setState(() => _storyBusy = false);
      messenger.showSnackBar(
        toast(L10n.current.shareFailed(e), tone: ToastTone.problem),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _storyBusy = false);
    // Only while this sheet is on top: after the render's wait a bare
    // pop could close whatever was opened over it instead.
    if (ModalRoute.of(context)?.isCurrent == true) navigator.pop();
    await shareAppStory(messenger, card, origin: origin);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    // Back is Not now: the same question, not a silent close.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave(context);
      },
      child: _sheet(context, t, l),
    );
  }

  Widget _sheet(BuildContext context, TextTheme t, L10n l) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1D2537), Color(0xFF131A28)],
          ),
          border: Border(
            top: BorderSide(
                color: AppColors.gold.withValues(alpha: 0.3), width: 0.9),
          ),
        ),
        // The ground is painted first and everything stands on it: the
        // sheet's own night, rose and gold light drifting in it, the
        // stars, and the glow off its corner.
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: MeshPainter(
                      palette: MeshPalette.invite,
                      clock: _clock,
                      radius: BorderRadius.zero,
                      opacity: 0,
                      glow: 0.2,
                    ),
                  ),
                ),
              ),
            ),
            const Positioned.fill(
              child: IgnorePointer(child: Starfield(count: 40, seed: 23)),
            ),
            const Positioned(
              top: -90,
              right: -70,
              child: IgnorePointer(child: GlowOrb(size: 240, alpha: 0.15)),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(26, 12, 26, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.stroke,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ExcludeSemantics(
                      child: _SpreadEmblem(clock: _clock, enter: _enter),
                    ),
                    const SizedBox(height: 8),
                    _Rise(
                      enter: _enter,
                      from: 0.22,
                      to: 0.62,
                      child: A11yHeader(
                        child: Text(
                          l.inviteHeadline,
                          textAlign: TextAlign.center,
                          style: t.headlineMedium
                              ?.copyWith(fontSize: 22, height: 1.3),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _Rise(
                      enter: _enter,
                      from: 0.3,
                      to: 0.7,
                      child: Text(
                        l.inviteBody,
                        textAlign: TextAlign.center,
                        style: t.bodyMedium?.copyWith(height: 1.55),
                      ),
                    ),
                    const SizedBox(height: 18),
                    // The hadith turns up into view like a page.
                    _Rise(
                      enter: _enter,
                      from: 0.38,
                      to: 0.82,
                      tilt: 1.15,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 13),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppColors.gold.withValues(alpha: 0.10),
                              const Color(0xFFD65CFF).withValues(alpha: 0.05),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: AppColors.gold.withValues(alpha: 0.24)),
                        ),
                        child: Column(
                          children: [
                            Text(
                              l.hadithGuidesToGood,
                              textAlign: TextAlign.center,
                              style: AppTheme.translation(
                                      size: 13.5, arabic: l.arabicScript)
                                  .copyWith(
                                      color: AppColors.textPrimary,
                                      height: 1.5),
                            ),
                            const SizedBox(height: 7),
                            Text(l.sahihMuslim,
                                style: t.bodySmall?.copyWith(
                                  color: AppColors.gold,
                                  fontSize: 11,
                                  letterSpacing: 0.6,
                                )),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    // Two doors side by side: the share sheet, in rose
                    // gold and dawn glass, and Instagram's story composer
                    // in Instagram's own colours — two warm lights that
                    // sit together, where the gold bar beside the brand's
                    // gradient used to look borrowed from two apps.
                    _Rise(
                      enter: _enter,
                      from: 0.48,
                      to: 0.9,
                      child: Row(
                        children: [
                          Expanded(
                            flex: 6,
                            // Builder so the origin rect measures the
                            // button itself rather than the whole sheet.
                            child: Builder(
                              builder: (buttonContext) => MeshButton(
                                label: l.shareAyahReel,
                                icon: Icons.ios_share_rounded,
                                palette: MeshPalette.invite,
                                height: 50,
                                onPressed: () async {
                                  // Both grabbed before the pop: the
                                  // sheet's context is gone by the time
                                  // the OS share sheet returns, and a
                                  // popped button has no render box left
                                  // to measure.
                                  final messenger =
                                      ScaffoldMessenger.of(buttonContext);
                                  final origin = shareOriginOf(buttonContext);
                                  Navigator.of(buttonContext).pop();
                                  await shareApp(messenger, origin: origin);
                                },
                              ),
                            ),
                          ),
                          if (InstagramShare.supported) ...[
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 5,
                              child: Builder(
                                builder: (buttonContext) => DirectShareButton(
                                  label: l.sendToInstagramStory,
                                  icon: Icons.motion_photos_on_rounded,
                                  colors: instagramMesh,
                                  height: 50,
                                  busy: _storyBusy,
                                  onPressed: () => _toStory(buttonContext),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    _Rise(
                      enter: _enter,
                      from: 0.55,
                      to: 1,
                      child: QuietButton(
                        label: l.notNow,
                        onPressed: () => _confirmLeave(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A part of the sheet arriving in its turn: rising a little into place
/// and fading in, and — given a [tilt] — turning up out of depth about
/// its middle, as a page lifted toward the reader.
class _Rise extends StatelessWidget {
  final Animation<double> enter;
  final double from;
  final double to;
  final double tilt;
  final Widget child;

  const _Rise({
    required this.enter,
    required this.from,
    required this.to,
    required this.child,
    this.tilt = 0,
  });

  @override
  Widget build(BuildContext context) {
    final span = Interval(from, to);
    return AnimatedBuilder(
      animation: enter,
      child: child,
      builder: (context, child) {
        final v = Curves.easeOutCubic.transform(span.transform(enter.value));
        if (v >= 1) return child!;
        return Opacity(
          opacity: v,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..translateByDouble(0, 22 * (1 - v), 0, 1)
              ..rotateX(tilt * (1 - v)),
            child: child,
          ),
        );
      },
    );
  }
}

/// What passing the app on does, drawn: the giving hand in an orb of
/// light, and around it, on three rings tilted in depth, the people it
/// reaches, each a point of light going round. A ripple goes out from
/// the hand twice a turn. The people passing in front of the hand are
/// larger and brighter than those behind it, and each ring's near half
/// is drawn over the orb and its far half under it, so the rings stand
/// in space around the hand rather than lying flat on the sheet.
class _SpreadEmblem extends StatelessWidget {
  final Animation<double> clock;
  final Animation<double> enter;

  const _SpreadEmblem({required this.clock, required this.enter});

  static const _open = Interval(0, 0.6);
  static const _fade = Interval(0, 0.3);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 230,
      height: 124,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter:
                    _OrbitPainter(clock: clock, enter: enter, front: false),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: enter,
            builder: (context, child) {
              final e = Curves.easeOutBack.transform(
                  _open.transform(enter.value));
              return Opacity(
                opacity: _fade.transform(enter.value),
                child: Transform.scale(scale: 0.4 + 0.6 * e, child: child),
              );
            },
            child: Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: const Alignment(-0.3, -0.4),
                  radius: 0.95,
                  colors: [
                    const Color(0xFFFFE3C8).withValues(alpha: 0.42),
                    AppColors.gold.withValues(alpha: 0.16),
                  ],
                ),
                border: Border.all(
                    color: AppColors.goldBright.withValues(alpha: 0.6)),
                boxShadow: const [
                  BoxShadow(color: Color(0x66FFB08A), blurRadius: 28),
                  BoxShadow(
                    color: Color(0x40D65CFF),
                    blurRadius: 40,
                    spreadRadius: -6,
                  ),
                ],
              ),
              child: const Icon(Icons.volunteer_activism_rounded,
                  size: 27, color: Colors.white),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter:
                      _OrbitPainter(clock: clock, enter: enter, front: true),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  final Animation<double> clock;
  final Animation<double> enter;

  /// The rings' near halves and the people on them, over the orb; or
  /// their far halves, the people behind and the ripples, under it.
  final bool front;

  _OrbitPainter({
    required this.clock,
    required this.enter,
    required this.front,
  }) : super(repaint: Listenable.merge([clock, enter]));

  static const _rings = [
    (rx: 100.0, ry: 22.0, tilt: -0.30, people: 3, laps: 1,
        colour: Color(0xFFFFB08A)),
    (rx: 80.0, ry: 30.0, tilt: 0.40, people: 2, laps: 2,
        colour: Color(0xFFE0A93A)),
    (rx: 108.0, ry: 13.0, tilt: 0.06, people: 4, laps: 1,
        colour: Color(0xFFD65CFF)),
  ];

  static const _open = Interval(0.1, 0.8);
  static const _show = Interval(0.1, 0.5);

  @override
  void paint(Canvas canvas, Size size) {
    final show = _show.transform(enter.value);
    if (show <= 0) return;
    final e = Curves.easeOutBack.transform(_open.transform(enter.value));
    final c = size.center(Offset.zero);
    final turn = clock.value * 2 * math.pi;

    if (!front) {
      for (final k in const [0.0, 0.5]) {
        final p = (clock.value * 2 + k) % 1;
        final r = 30 + 84 * p;
        canvas.drawOval(
          Rect.fromCenter(center: c, width: r * 2, height: r * 0.86),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color =
                AppColors.goldBright.withValues(alpha: 0.28 * (1 - p) * show),
        );
      }
    }

    for (var i = 0; i < _rings.length; i++) {
      final ring = _rings[i];
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(ring.tilt);
      final rx = ring.rx * e, ry = ring.ry * e;
      canvas.drawArc(
        Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2),
        front ? 0 : math.pi,
        math.pi,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9
          ..color = ring.colour.withValues(alpha: (front ? 0.42 : 0.16) * show),
      );
      final way = i.isEven ? 1.0 : -1.0;
      for (var j = 0; j < ring.people; j++) {
        final a = turn * ring.laps * way + j * 2 * math.pi / ring.people + i;
        final near = math.sin(a) > 0;
        if (near != front) continue;
        final depth = (math.sin(a) + 1) / 2;
        final at = Offset(rx * math.cos(a), ry * math.sin(a));
        final r = (2.0 + 2.2 * depth) * math.min(e, 1.2);
        canvas.drawCircle(
          at,
          r * 3,
          Paint()
            ..color = ring.colour
                .withValues(alpha: 0.16 * show * (0.4 + 0.6 * depth)),
        );
        canvas.drawCircle(
          at,
          r,
          Paint()
            ..color = Color.lerp(ring.colour, Colors.white, 0.4 + 0.3 * depth)!
                .withValues(alpha: show * (0.45 + 0.55 * depth)),
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter old) =>
      old.front != front || old.clock != clock || old.enter != enter;
}

/// The persistent invitation: bottom-right on every tab, floating above
/// the nav bar.
///
/// Deliberately NOT gold-filled. Gold in this app marks the one most
/// wanted action on a screen, and on Home that is the Create card — a
/// gold button down here would split the eye every time the app opens.
/// Glass with a gold edge reads as always-available, never as the ask.
class InviteFab extends StatelessWidget {
  const InviteFab({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Semantics(
      container: true,
      button: true,
      label: l.inviteSomeoneSemantics,
      child: Tooltip(
        message: l.inviteSomeone,
        excludeFromSemantics: true,
        child: ClipOval(
          // Grouped with the shell's other glass (HomeShell's
          // BackdropGroup): one copy of the screen for all of it.
          child: BackdropFilter.grouped(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Material(
              color: AppColors.surfaceRaised.withValues(alpha: 0.88),
              shape: CircleBorder(
                side: BorderSide(
                    color: AppColors.gold.withValues(alpha: 0.42), width: 1),
              ),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => showInviteSheet(context),
                child: const SizedBox(
                  width: 52,
                  height: 52,
                  child: Icon(Icons.volunteer_activism_rounded,
                      size: 23, color: AppColors.goldBright),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
