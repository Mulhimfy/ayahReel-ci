import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import '../data/debug_log.dart';
import '../data/reel_library.dart';
import '../data/share_origin.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import '../widgets/a11y.dart';
import '../widgets/app_toast.dart';
import '../widgets/hashtags_sheet.dart';
import '../widgets/night_sky.dart';
import '../widgets/reel_thumb.dart';
import 'reopen_reel.dart';

/// Every reel is exported 1080x1920, so the stage keeps that shape.
const double _reelAspect = 9 / 16;

/// The reel is deliberately NOT given the whole screen. Blown up edge
/// to edge, a 9:16 clip reads as a video that escaped its frame: it
/// touches the app bar, it touches both sides, and the app around it
/// disappears. Held to a phone-shaped card with room on every side it
/// reads as an object on a page — the same object the user is about
/// to hand to someone else.
const double _stageWidthFraction = 0.74;
const double _stageMaxWidth = 320;

/// Height kept clear under the card for the transport — the reciter
/// line, the scrub bar, the three buttons, the hashtags pill.
/// Deliberately a little generous: the card gives way to the controls
/// rather than the other way round, and the stage sits in an
/// [Expanded] which absorbs whatever is left over.
const double _transportReserve = 232;

/// The narrowest the transport can be cut before its own row of
/// buttons stops fitting. It follows the card's width down to here and
/// no further — sideways, the card gets narrow enough to strangle it.
const double _transportMinWidth = 220;

/// Plays one saved reel. Tap the card — or the play button — to pause
/// and resume, drag the bar to move through it, share from the row
/// underneath.
class ReelPlayerScreen extends StatefulWidget {
  final SavedReel reel;
  const ReelPlayerScreen({super.key, required this.reel});

  @override
  State<ReelPlayerScreen> createState() => _ReelPlayerScreenState();
}

class _ReelPlayerScreenState extends State<ReelPlayerScreen>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  File? _file;

  /// The file would not open. The card keeps its poster and says so,
  /// rather than sitting on a spinner that never ends.
  bool _failed = false;

  /// Whether playback was running when the app went away, so coming
  /// back restores what the user left rather than starting the reel
  /// on its own. A reel paused by hand stays paused.
  bool _playingWhenHidden = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load() async {
    VideoPlayerController? c;
    try {
      final file = await ReelLibrary.videoFile(widget.reel);
      c = VideoPlayerController.file(file);
      // Bounded: a decoder the platform never hands out (every slot
      // taken by a preview still winding down) left this awaiting
      // forever, and the card on a spinner that never ended.
      await c.initialize().timeout(const Duration(seconds: 20));
      // Bail before starting it. Calling play() and then disposing races
      // the platform player: the dispose can land while the play is
      // still in flight, and the reel goes on sounding from a screen
      // that is gone. Nothing has been started here yet, so leaving is
      // just a dispose.
      if (!mounted) {
        await c.dispose();
        return;
      }
      c.setLooping(true);
      setState(() {
        _file = file;
        _controller = c;
      });
      await c.play();
    } catch (e, s) {
      rlogError('player load', e, s);
      // A controller that failed to open still holds whatever the
      // platform gave it; only the one seated in [_controller] is
      // disposed with the screen.
      if (c != null && c != _controller) c.dispose();
      if (mounted) setState(() => _failed = true);
    }
  }

  /// Backgrounding does not stop ExoPlayer on its own, so a reel left
  /// playing keeps sounding behind whatever the user switched to — and
  /// is still going when they come back, which reads as the app
  /// starting playback by itself.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // Hiding comes as inactive and then paused: the second finds the
      // reel already paused by the first, and must not forget that it
      // was playing.
      if (c.value.isPlaying) {
        _playingWhenHidden = true;
        c.pause();
      }
    } else if (state == AppLifecycleState.resumed && _playingWhenHidden) {
      _playingWhenHidden = false;
      c.play();
    }
  }

  /// [origin] is the tapped icon, measured by the caller — iOS refuses
  /// to open the sheet without a rect. See [shareOriginOf].
  Future<void> _share(Rect origin) async {
    final file = _file;
    if (file == null) return;
    final wasPlaying = _controller?.value.isPlaying ?? false;
    _controller?.pause();
    final l = L10n.current;
    try {
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path)],
        text: widget.reel.shareCaption(l),
        sharePositionOrigin: origin,
      ));
      // The same offer the wizard makes after an export: the caption
      // box is the next thing this user will be looking at.
      if (mounted) {
        await offerHashtagsAfterExport(context,
            surahName: widget.reel.surahName);
      }
    } catch (e, s) {
      rlogError('player share', e, s);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          toast(l.shareFailed(e), tone: ToastTone.problem),
        );
      }
    }
    // Resume either way: a failed share should leave the reel playing,
    // not paused on a screen the user is still looking at. Unless the
    // user had paused it themselves.
    if (wasPlaying && mounted) _controller?.play();
  }

  /// The controller, once it can actually be driven. Nothing in the
  /// transport calls setState: the controller is itself the notifier
  /// the screen listens to, so a pause, a seek, and every position
  /// tick all arrive by the same route.
  VideoPlayerController? get _ready {
    final c = _controller;
    return c != null && c.value.isInitialized ? c : null;
  }

  void _togglePlay() {
    final c = _ready;
    if (c == null) return;
    HapticFeedback.selectionClick();
    c.value.isPlaying ? c.pause() : c.play();
  }

  void _replay() {
    final c = _ready;
    if (c == null) return;
    HapticFeedback.selectionClick();
    c.seekTo(Duration.zero);
    c.play();
  }

  void _seek(Duration to) => _ready?.seekTo(to);

  /// Back into the wizard with everything this reel was made of. The
  /// player rests while the wizard is up and resumes on the way back,
  /// which is also when the library may have a newer reel in it.
  Future<void> _edit() async {
    final wasPlaying = _controller?.value.isPlaying ?? false;
    _controller?.pause();
    await ReelReopener.open(context, widget.reel);
    // The wait can end with the wizard still up ("Add sceneries" swaps
    // one of its screens for another), and the reel would sound under
    // it: only a player back on top plays again.
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    if (wasPlaying) _controller?.play();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final r = widget.reel;
    final l = L10n.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(color: AppColors.textSecondary),
        title: Text(
          l.reelTitle(r.surahName, r.startAyah, r.endAyah),
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      body: Stack(
        children: [
          // The same whisper of night sky the home tab opens with, so
          // the player belongs to the app and not just to the video.
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 280,
            child: ExcludeSemantics(
                child: IgnorePointer(child: Starfield(count: 34))),
          ),
          SafeArea(
            top: false,
            child: c == null
                ? _content(null)
                : ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: c,
                    builder: (_, v, __) => _content(v),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _content(VideoPlayerValue? v) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    final r = widget.reel;
    final live = v != null && v.isInitialized;
    final playing = v?.isPlaying ?? false;
    return LayoutBuilder(
      builder: (_, body) {
        // One card size, decided once, for the whole screen: the
        // transport underneath is cut to the same width, so the clocks,
        // the bar and the buttons line up with the reel's own edges
        // instead of running out past them.
        //
        // Width leads — that is what holds the reel to a card. Height
        // only takes over on a screen too short to stand one up.
        var w = math.min(body.maxWidth * _stageWidthFraction, _stageMaxWidth);
        var h = w / _reelAspect;
        // Clamped at zero: turned sideways there can be less height
        // here than the transport alone wants, and a negative card is
        // an assertion rather than a small one.
        final room = math.max(0.0, body.maxHeight - _transportReserve);
        if (h > room) {
          h = room;
          w = h * _reelAspect;
        }
        return Column(
          children: [
            Expanded(
              child: Center(
                // Its own layer: the card carries a 78px glow and a
                // 40px shadow, and every position tick below redraws
                // the scrubber. Without the boundary each tick
                // re-rastered both blurs along with it.
                child: RepaintBoundary(
                  child: _Stage(
                    reel: r,
                    width: w,
                    height: h,
                    controller: _controller,
                    playing: playing,
                    failed: _failed,
                    onTap: _togglePlay,
                  ),
                ),
              ),
            ),
            SizedBox(
              width: math.max(
                  w, math.min(_transportMinWidth, body.maxWidth)),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  Text(
                    '${l.localizedReciterName(r.reciterName)} · '
                    '${l.formatDate(r.createdAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        t.bodySmall?.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  _Scrubber(
                    position: v?.position ?? Duration.zero,
                    duration: v?.duration ?? Duration.zero,
                    enabled: live,
                    onSeek: _seek,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _CircleButton(
                        icon: Icons.replay_rounded,
                        tooltip: l.replay,
                        onTap: live ? _replay : null,
                      ),
                      _PlayButton(
                        playing: playing,
                        tooltip: playing ? l.pause : l.play,
                        onTap: live ? _togglePlay : null,
                      ),
                      Builder(
                        builder: (buttonContext) => _CircleButton(
                          icon: Icons.ios_share_rounded,
                          tooltip: l.share,
                          onTap: _file == null
                              ? null
                              : () => _share(shareOriginOf(buttonContext)),
                        ),
                      ),
                      // Only for reels that kept their recipe: an
                      // older reel plays and shares, and that is all
                      // it can do.
                      if (r.canEdit)
                        _CircleButton(
                          icon: Icons.tune_rounded,
                          tooltip: l.editAgain,
                          onTap: _edit,
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // A reel opened from the library is a reel about to
                  // be posted again. The caption it needs is here, on
                  // the same screen as the share button, rather than
                  // typed out from memory in the other app.
                  HashtagsButton(surahName: r.surahName),
                  const SizedBox(height: 18),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The reel itself: a phone-shaped card lit from behind by its own
/// background gradient, so the color of the reel spills onto the page
/// around it.
class _Stage extends StatelessWidget {
  final SavedReel reel;
  final double width;
  final double height;
  final VideoPlayerController? controller;
  final bool playing;
  final bool failed;
  final VoidCallback onTap;

  const _Stage({
    required this.reel,
    required this.width,
    required this.height,
    required this.controller,
    required this.playing,
    required this.failed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final g = reel.gradientArgb;
    final top = Color(g.isNotEmpty ? g[0] : 0xFF1D2537);
    final bottom = Color(g.length > 1 ? g[1] : 0xFF131A28);
    // The brighter end of the reel's own gradient. Spilling the darker
    // end onto a near-black page reads as a second shadow, not as
    // light — and half the sceneries are darkest at the bottom.
    final spill = top.computeLuminance() >= bottom.computeLuminance()
        ? top
        : bottom;
    final radius = BorderRadius.circular(28);
    final c = controller;
    final live = c != null && c.value.isInitialized;
    // The card is one control: what it is, what state it is in, and
    // that a double tap pauses or resumes it. Before the file opens
    // it says it is loading; if the file never opens, it says so.
    final spoken = failed
        ? l.reelUnavailable
        : !live
            ? l.a11yLoadingReel
            : l.reelTitle(reel.surahName, reel.startAyah, reel.endAyah);
    return A11yTap(
      label: spoken,
      hint: live ? (playing ? l.pause : l.play) : null,
      enabled: live,
      onTap: live ? onTap : null,
      child: SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          // Light spill: an unfilled box behind the card, so only its
          // blur shows — the reel's own colors bleeding into the page,
          // plus a plain black shadow to seat it.
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  boxShadow: [
                    BoxShadow(
                      color: spill.withValues(alpha: 0.42),
                      blurRadius: 78,
                      spreadRadius: 2,
                    ),
                    // One shadow to seat it, blurred wide: a tighter
                    // one stacks with the glow into a visible dark lip
                    // along the bottom edge.
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 40,
                      offset: const Offset(0, 18),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: ClipRRect(
              borderRadius: radius,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: live ? onTap : null,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Under everything: the gradient, then the poster
                    // frame. The card is never a black rectangle —
                    // not while the file opens, not if it never does.
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [top, bottom],
                        ),
                      ),
                    ),
                    ReelThumb(reel: reel),
                    if (live)
                      FittedBox(
                        fit: BoxFit.cover,
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox(
                          width: c.value.size.width,
                          height: c.value.size.height,
                          child: VideoPlayer(c),
                        ),
                      ),
                    // Paused: a glass disc over a light scrim, gone
                    // again the moment playback resumes.
                    IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: live && playing ? 0 : 1,
                        duration: const Duration(milliseconds: 170),
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.26),
                          alignment: Alignment.center,
                          child: failed
                              ? Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 22),
                                  child: Text(
                                    l.reelUnavailable,
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(color: Colors.white),
                                  ),
                                )
                              : live
                                  ? const _PlayGlyph()
                                  : const SizedBox(
                                      width: 30,
                                      height: 30,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.4,
                                        color: AppColors.goldBright,
                                      ),
                                    ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Drawn last and outside the clip, so the hairline stays a
          // whole line instead of being shaved in half by its own edge.
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(
                    color: AppColors.gold.withValues(alpha: 0.30),
                    width: 0.9,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

class _PlayGlyph extends StatelessWidget {
  const _PlayGlyph();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.45)),
      ),
      child:
          const Icon(Icons.play_arrow_rounded, size: 34, color: Colors.white),
    );
  }
}

/// Elapsed · bar · total. Drag it, or tap anywhere along it, to move.
class _Scrubber extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final bool enabled;
  final ValueChanged<Duration> onSeek;

  const _Scrubber({
    required this.position,
    required this.duration,
    required this.enabled,
    required this.onSeek,
  });

  @override
  State<_Scrubber> createState() => _ScrubberState();
}

class _ScrubberState extends State<_Scrubber> {
  /// Where the finger is, while it is down. The bar follows the touch
  /// rather than the player during a drag: a seek lands a frame or two
  /// later, and a bar waiting for it would crawl behind the thumb the
  /// whole way across.
  double? _drag;

  double get _fraction {
    final total = widget.duration.inMilliseconds;
    if (total <= 0) return 0;
    return (_drag ?? widget.position.inMilliseconds / total).clamp(0.0, 1.0);
  }

  void _scrub(double dx, double width) {
    if (!widget.enabled || width <= 0) return;
    final f = (dx / width).clamp(0.0, 1.0);
    setState(() => _drag = f);
    widget.onSeek(widget.duration * f);
  }

  void _release() {
    if (_drag != null) setState(() => _drag = null);
  }

  static String _clock(Duration d) {
    final s = d.inSeconds < 0 ? 0 : d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  /// The reader's stand-in for the drag: five seconds a step.
  void _step(int seconds) {
    if (!widget.enabled) return;
    final ms = (widget.position.inMilliseconds + seconds * 1000)
        .clamp(0, widget.duration.inMilliseconds);
    widget.onSeek(Duration(milliseconds: ms));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    final f = _fraction;
    final shown = _drag == null ? widget.position : widget.duration * _drag!;
    final style = t.bodySmall?.copyWith(color: AppColors.textSecondary);
    // Media time runs left to right in both languages, and so does the
    // bar that measures it. To a reader the whole row is one slider:
    // where the reel is out of how long it runs, moved five seconds at
    // a time.
    return A11yAdjustable(
      label: l.a11yPlaybackPosition,
      value: '${_clock(shown)} / ${_clock(widget.duration)}',
      onIncrease: widget.enabled ? () => _step(5) : null,
      onDecrease: widget.enabled ? () => _step(-5) : null,
      child: Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        children: [
          SizedBox(
            width: 38,
            child: Text(_clock(shown), softWrap: false, style: style),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (_, box) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _scrub(d.localPosition.dx, box.maxWidth),
                onTapUp: (_) => _release(),
                onTapCancel: _release,
                onHorizontalDragUpdate: (d) =>
                    _scrub(d.localPosition.dx, box.maxWidth),
                onHorizontalDragEnd: (_) => _release(),
                onHorizontalDragCancel: _release,
                child: SizedBox(
                  height: 30,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: f,
                          child: Container(
                            height: 4,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  AppColors.gold,
                                  AppColors.goldBright,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment(f * 2 - 1, 0),
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.goldBright,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.gold.withValues(alpha: 0.55),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 38,
            child: Text(
              _clock(widget.duration),
              textAlign: TextAlign.right,
              softWrap: false,
              style: style,
            ),
          ),
        ],
      ),
      ),
    );
  }
}

/// The one gold thing on the screen. The app spends its accent on a
/// single action per screen, and here that action is playback.
class _PlayButton extends StatelessWidget {
  final bool playing;
  final String tooltip;
  final VoidCallback? onTap;

  const _PlayButton({
    required this.playing,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final on = onTap != null;
    // The tooltip's words are the button's name to a reader; the
    // tooltip itself is left for a long press by eye.
    return Semantics(
      container: true,
      button: true,
      enabled: on,
      label: tooltip,
      child: Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: Container(
        width: 66,
        height: 66,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: on
                ? const [AppColors.goldBright, AppColors.gold]
                : const [AppColors.surfaceRaised, AppColors.surface],
          ),
          boxShadow: on
              ? [
                  BoxShadow(
                    color: AppColors.gold.withValues(alpha: 0.32),
                    blurRadius: 22,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              transitionBuilder: (child, anim) => ScaleTransition(
                scale: anim,
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                key: ValueKey(playing),
                size: 32,
                color: on ? const Color(0xFF14100A) : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }
}

/// Quiet round buttons flanking the gold one.
class _CircleButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  const _CircleButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final on = onTap != null;
    return Semantics(
      container: true,
      button: true,
      enabled: on,
      label: tooltip,
      child: Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.surface,
          border: Border.all(color: AppColors.stroke),
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Icon(
              icon,
              size: 21,
              color: on
                  ? AppColors.textPrimary
                  : AppColors.textSecondary.withValues(alpha: 0.4),
            ),
          ),
        ),
      ),
      ),
    );
  }
}
