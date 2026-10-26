import 'dart:async';
import 'dart:io' show File, Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../data/arena_service.dart';
import '../data/card_library.dart';
import '../data/debug_log.dart';
import '../data/gallery_saver.dart';
import '../data/instagram_share.dart';
import '../data/reel_library.dart';
import '../data/review_prompt.dart';
import '../data/rewards_service.dart';
import '../data/settings_service.dart';
import '../data/share_origin.dart';
import '../data/verse_light.dart';
import '../data/whatsapp_share.dart';
import '../l10n/l10n.dart';
import '../render/verses_story.dart';
import '../state/creation_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_toast.dart';
import '../widgets/direct_share_button.dart';
import '../widgets/arrive.dart';
import '../widgets/glass_tile.dart';
import '../widgets/glow_button.dart';
import '../widgets/tanafus_button.dart';
import '../widgets/a11y.dart';
import '../widgets/ambient_motion.dart';
import '../widgets/illumination.dart';
import '../widgets/rate_sheet.dart';
import '../widgets/gallery_blocked_dialog.dart';
import '../widgets/hashtags_sheet.dart';
import '../widgets/how_to_sheet.dart';
import '../widgets/reel_thumb.dart';
import '../widgets/storage_sheet.dart';
import 'reciter_screen.dart';
import 'reel_player_screen.dart';
import 'reopen_reel.dart';

/// Every reel the user has exported, newest first. Tap to replay,
/// menu to share again or delete. Lives as a tab in the home shell,
/// refreshing itself whenever the library changes.
///
/// Two pages under one switch at the top: the reels themselves, and
/// "Your verses" — every verse those reels recite, lit on a picture of
/// the whole Quran, ready to share as a story.
class MyReelsScreen extends StatefulWidget {
  /// Set to have the tab open on its "Your verses" page — by the shell,
  /// for a share notification or the tenth reel's offer. Taken (set
  /// back to false) by the tab when it turns there.
  static final ValueNotifier<bool> versesWanted = ValueNotifier(false);

  const MyReelsScreen({super.key});

  @override
  State<MyReelsScreen> createState() => _MyReelsScreenState();
}

class _MyReelsScreenState extends State<MyReelsScreen> {
  List<SavedReel>? _reels;

  /// Which page is open: the reels, or the card of their verses.
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
    ReelLibrary.revision.addListener(_refresh);
    // Asked for before this tab was ever built: it opens there.
    if (MyReelsScreen.versesWanted.value) {
      MyReelsScreen.versesWanted.value = false;
      _page = 1;
    }
    MyReelsScreen.versesWanted.addListener(_onVersesWanted);
  }

  @override
  void dispose() {
    ReelLibrary.revision.removeListener(_refresh);
    MyReelsScreen.versesWanted.removeListener(_onVersesWanted);
    super.dispose();
  }

  void _onVersesWanted() {
    if (!MyReelsScreen.versesWanted.value || !mounted) return;
    MyReelsScreen.versesWanted.value = false;
    if (_page != 1) setState(() => _page = 1);
  }

  Future<void> _refresh() async {
    final reels = await ReelLibrary.load();
    if (mounted) setState(() => _reels = reels);
  }

  /// Caption localized at share time; the stored names stay English so
  /// the library is stable across language switches.
  String _caption(SavedReel r) => r.shareCaption(L10n.current);

  /// [origin] is the card that was tapped, measured before the file
  /// lookup — iOS refuses to open the sheet without a rect.
  Future<void> _share(SavedReel r, Rect origin) async {
    try {
      final file = await ReelLibrary.videoFile(r);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path)],
        text: _caption(r),
        sharePositionOrigin: origin,
      ));
      // The same offer the wizard makes, for the same reason: the
      // caption box is the next thing this user will be looking at.
      if (mounted) {
        await offerHashtagsAfterExport(context, surahName: r.surahName);
      }
    } catch (e, s) {
      rlogError('reel share', e, s);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        toast(L10n.of(context).shareFailed(e), tone: ToastTone.problem),
      );
    }
  }

  Future<void> _shareWhatsApp(SavedReel r, Rect origin) async {
    final file = await ReelLibrary.videoFile(r);
    final handed = await WhatsAppShare.shareVideo(file, text: _caption(r));
    if (handed) return;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        toast(
          L10n.of(context).whatsappUnavailable,
          tone: ToastTone.problem,
        ),
      );
    }
    await _share(r, origin);
  }

  /// Writes a reel the app already holds straight to the gallery.
  ///
  /// The wizard's Save was the only way a reel ever reached the
  /// gallery, so a save the phone refused — a permission not yet
  /// granted, an album write an OEM would not take — left the user
  /// with a finished reel in the app and no second chance at it short
  /// of building the whole thing again. This is that second chance,
  /// and it costs no render: the mp4 is already on disk.
  Future<void> _save(SavedReel r) async {
    final l = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final file = await ReelLibrary.videoFile(r);
    final result = await GallerySaver.save(
      file,
      name: 'AyahReel ${r.surahName} ${r.startAyah}-${r.endAyah}',
    );
    if (!mounted) return;
    switch (result.status) {
      case GallerySaveStatus.saved:
        await ReelLibrary.markInGallery(r);
        messenger.showSnackBar(toast(l.savedToDevice, tone: ToastTone.done));
        if (mounted) {
          await offerHashtagsAfterExport(context, surahName: r.surahName);
        }
        // A reel reaching the gallery counts here exactly as it does
        // in the wizard, and nothing else is on screen to compete for
        // the moment. Whether it asks at all, and with whose sheet, is
        // [ReviewPrompt.decide]'s call and not this screen's.
        // `mounted`, not `context.mounted`: this is the State's own
        // context, and the analyzer only accepts the State's flag for
        // it after an await.
        if (await ReviewPrompt.offerAfterExport() == ReviewAsk.banner &&
            mounted) {
          await showRateSheet(context);
        }
      case GallerySaveStatus.denied:
        rlogError('gallery save', result.error ?? 'access denied',
            StackTrace.current);
        await showGalleryBlockedDialog(context);
      case GallerySaveStatus.failed:
        rlogError('gallery save', result.error ?? 'unknown', StackTrace.current);
        messenger.showSnackBar(
          toast(
            result.outOfSpace
                  ? l.phoneStorageFull
                  : l.saveFailed(result.error ?? ''),
            tone: ToastTone.problem,
          ),
        );
    }
  }

  Future<void> _delete(SavedReel r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final l = L10n.of(ctx);
        return AlertDialog(
          backgroundColor: AppColors.surfaceRaised,
          title: Text(l.deleteReelTitle),
          content: Text(l.deleteReelBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l.delete,
                  style: const TextStyle(color: Color(0xFFE57373))),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await ReelLibrary.remove(r);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    final reels = _reels;
    final motion = AmbientScope.maybeOf(context);
    final body = SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 26, 10, 6),
            child: Row(
              children: [
                Expanded(
                  child: A11yHeader(
                    child: Text(l.navWorks, style: t.headlineMedium),
                  ),
                ),
                IconButton(
                  tooltip: l.manageStorage,
                  icon: const Icon(Icons.storage_rounded,
                      size: 20, color: AppColors.gold),
                  onPressed: () async {
                    await showStorageSheet(context);
                    _refresh(); // sizes may have changed
                  },
                ),
                // Clear of the arena's roundel, which stands in this
                // corner on every tab.
                const SizedBox(width: TanafusButton.size + 6),
              ],
            ),
          ),
          // The same rule that heads every section on Home, so the tab
          // reads as another page of the same book.
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 0, 22, 6),
            child: Row(
              children: [
                Expanded(child: OrnamentHairline(towardsEnd: true)),
                SizedBox(width: 8),
                SealGlyph(size: 7, color: Color(0x99D4A947)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 6, 22, 0),
            child: _PageSwitch(
              page: _page,
              reels: reels?.length ?? 0,
              onSelect: (p) {
                if (p == _page) return;
                HapticFeedback.selectionClick();
                setState(() => _page = p);
              },
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween(
                          begin: const Offset(0, 0.02), end: Offset.zero)
                      .animate(a),
                  child: child,
                ),
              ),
              child: reels == null
                ? const Center(
                    key: ValueKey('loading'),
                    child:
                        CircularProgressIndicator(color: AppColors.gold))
                : _page == 1
                    ? _VersesPage(key: const ValueKey('verses'), reels: reels)
                    : reels.isEmpty
                    ? _EmptyState(key: const ValueKey('empty'), textTheme: t)
                    : GridView.builder(
                        key: const ValueKey('grid'),
                        padding:
                            const EdgeInsets.fromLTRB(22, 12, 22, 128),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                          childAspectRatio: 9 / 16,
                        ),
                        itemCount: reels.length,
                        itemBuilder: (_, i) => _ReelCard(
                          // Identity, not position: the list is
                          // newest-first, so every export shifts each
                          // card down one and an unkeyed grid would
                          // hand each card's state to the reel that
                          // replaced it.
                          key: ValueKey(reels[i].id),
                          reel: reels[i],
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    ReelPlayerScreen(reel: reels[i]),
                              ),
                            );
                          },
                          onShare: (origin) => _share(reels[i], origin),
                          onSave: () => _save(reels[i]),
                          onEdit: reels[i].canEdit
                              ? () => ReelReopener.open(context, reels[i])
                              : null,
                          onShareWhatsApp: Platform.isAndroid &&
                                  SettingsService
                                      .state.value.whatsappDirectShare
                              ? (origin) =>
                                  _shareWhatsApp(reels[i], origin)
                              : null,
                          onDelete: () => _delete(reels[i]),
                        ),
                      ),
            ),
          ),
        ],
      ),
    );
    if (motion == null) return body;
    // The grid feeds the shell's sky exactly as Home's page does.
    return AmbientScrollSensor(motion: motion, child: body);
  }
}

class _EmptyState extends StatelessWidget {
  final TextTheme textTheme;
  const _EmptyState({super.key, required this.textTheme});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 64),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // An empty seal rather than a greyed-out icon: nothing has
            // been made yet, so the page is showing its mark and
            // waiting.
            const SizedBox(
              width: 58,
              height: 58,
              child: CustomPaint(painter: _EmptySealPainter()),
            ),
            const SizedBox(height: 18),
            Text(l.noReelsYet, style: textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              l.noReelsBody,
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () {
                creationState.startNewReel();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ReciterScreen()),
                );
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.goldBright,
                side: BorderSide(
                    color: AppColors.gold.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.add_rounded, size: 20),
              label: Text(l.createFirstReel),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptySealPainter extends CustomPainter {
  const _EmptySealPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    canvas.drawPath(
      Khatam.seal(c, size.shortestSide * 0.46),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = AppColors.gold.withValues(alpha: 0.45),
    );
    canvas.drawPath(
      Khatam.star(c, size.shortestSide * 0.14),
      Paint()..color = AppColors.gold.withValues(alpha: 0.55),
    );
  }

  @override
  bool shouldRepaint(covariant _EmptySealPainter old) => false;
}

class _ReelCard extends StatelessWidget {
  final SavedReel reel;
  final VoidCallback onTap;

  /// Handed the card's bounds so iOS has somewhere to anchor the sheet.
  final ValueChanged<Rect> onShare;

  /// Writes this reel to the device gallery.
  final VoidCallback onSave;

  /// Reopens the reel in the wizard. Null for a reel made before the
  /// app kept recipes, which has nothing to reopen.
  final VoidCallback? onEdit;

  /// Non-null only when the WhatsApp quick-share setting is on.
  final ValueChanged<Rect>? onShareWhatsApp;
  final VoidCallback onDelete;

  const _ReelCard({
    super.key,
    required this.reel,
    required this.onTap,
    required this.onShare,
    required this.onSave,
    this.onEdit,
    this.onShareWhatsApp,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    final g = reel.gradientArgb;
    // The card is one button to a screen reader — the reel's name,
    // voice and date, then what a tap does — with the menu as its own
    // control after it, named rather than the stock "Show menu".
    // Under the same glass as the sceneries the reel was made from: it
    // leans to the finger and the light runs across it. The glass is
    // the touch's answer here, so the ink ripple is left out — a grey
    // ring spreading over a picture is the one thing glass would not
    // do.
    return Semantics(
      container: true,
      button: true,
      hint: l.a11yPlaysReel,
      child: GlassTile(
        radius: 20,
        child: ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(g[0]), Color(g[1])],
            ),
          ),
          child: InkWell(
            onTap: onTap,
            splashFactory: NoSplash.splashFactory,
            highlightColor: Colors.transparent,
            child: Stack(
              fit: StackFit.expand,
              children: [
                GlassDepth(child: ReelThumb(reel: reel)),
                const Center(
                  child: Icon(Icons.play_arrow_rounded,
                      size: 44, color: Colors.white70),
                ),
                // The options sit at the tile's trailing corner, which is
                // the left one in Arabic and Urdu.
                PositionedDirectional(
                  top: 2,
                  end: 2,
                  child: PopupMenuButton<String>(
                    tooltip: l.a11yReelOptions,
                    icon: const Icon(Icons.more_vert_rounded,
                        size: 20, color: Colors.white70),
                    color: AppColors.surfaceRaised,
                    onSelected: (v) => switch (v) {
                      'share' => onShare(shareOriginOf(context)),
                      'whatsapp' =>
                        onShareWhatsApp?.call(shareOriginOf(context)),
                      'save' => onSave(),
                      'edit' => onEdit?.call(),
                      _ => onDelete(),
                    },
                    itemBuilder: (_) => [
                      if (onEdit != null)
                        PopupMenuItem(
                          value: 'edit',
                          child: Text(l.editAgain),
                        ),
                      PopupMenuItem(
                        value: 'share',
                        child: Text(l.share),
                      ),
                      if (onShareWhatsApp != null)
                        PopupMenuItem(
                          value: 'whatsapp',
                          child: Text(l.sendToWhatsApp),
                        ),
                      PopupMenuItem(
                        value: 'save',
                        child: Text(l.saveToDevice),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(l.delete),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 20, 12, 10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.65),
                        ],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.reelTitle(reel.surahName, reel.startAyah,
                              reel.endAyah),
                          style: t.bodyMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${l.localizedReciterName(reel.reciterName)} · '
                          '${l.formatDate(reel.createdAt)}',
                          style: t.bodySmall
                              ?.copyWith(color: Colors.white70),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
      ),
    );
  }
}

/// The two pages of the tab, side by side in one pill: the reels, with
/// how many there are, and "Your verses". A gold lozenge slides under
/// whichever is open.
class _PageSwitch extends StatelessWidget {
  final int page;
  final int reels;
  final ValueChanged<int> onSelect;

  const _PageSwitch({
    required this.page,
    required this.reels,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    Widget half(int i, String label, Widget? lead) {
      final on = page == i;
      return Expanded(
        child: A11yTap(
          label: label,
          selected: on,
          onTap: () => onSelect(i),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onSelect(i),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (lead != null) ...[lead, const SizedBox(width: 7)],
                  // From the theme, so the face is the app's: an
                  // animated style replaces the one around it whole.
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 220),
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                          fontSize: 13.5,
                          height: 1.2,
                          fontWeight: on ? FontWeight.w700 : FontWeight.w600,
                          color: on
                              ? const Color(0xFF14100A)
                              : AppColors.textSecondary,
                        ),
                    child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      height: 42,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: AppColors.stroke),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth / 2;
          return Stack(
            children: [
              AnimatedPositionedDirectional(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                start: page * w,
                top: 0,
                bottom: 0,
                width: w,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFFFE7A6), AppColors.gold],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.gold.withValues(alpha: 0.35),
                        blurRadius: 14,
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  half(
                    0,
                    reels > 0 ? '${l.reelsTabReels} · $reels' : l.reelsTabReels,
                    null,
                  ),
                  half(
                    1,
                    l.reelsTabVerses,
                    SizedBox.square(
                      dimension: 13,
                      child: CustomPaint(painter: _SunGlyph(lit: page == 1)),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A sun of twelve rays, for the "Your verses" half of the switch.
class _SunGlyph extends CustomPainter {
  final bool lit;
  const _SunGlyph({required this.lit});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final ink = lit ? const Color(0xFF14100A) : AppColors.gold;
    final ray = Paint()
      ..color = ink
      ..strokeWidth = r * 0.16
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      final reach = i.isEven ? 1.0 : 0.78;
      final d = Offset(math.cos(a), math.sin(a)) * (r * reach);
      canvas.drawLine(c + d * 0.55, c + d, ray);
    }
    canvas.drawCircle(c, r * 0.32, Paint()..color = ink);
  }

  @override
  bool shouldRepaint(_SunGlyph old) => old.lit != lit;
}

/// "Your verses": the card, live, in a light frame — the whole Quran as
/// a sun and every verse the user has met in the app burning on it: the
/// reels', the cards' that quote one, the quiz's — with a "?" beside it,
/// a line saying what it is, the two things it can carry besides the
/// picture, and the two ways out. With nothing lit yet, the same sun
/// unlit, and the way to light it.
class _VersesPage extends StatefulWidget {
  final List<SavedReel> reels;
  const _VersesPage({super.key, required this.reels});

  @override
  State<_VersesPage> createState() => _VersesPageState();
}

class _VersesPageState extends State<_VersesPage> {
  /// The reels' light at once, from the list the tab already has; the
  /// cards' and the quiz's join it as soon as they are read.
  late VerseLight _light = VerseLight.of(widget.reels);

  /// Whether every source has been read, so an empty sun means nothing
  /// lit anywhere rather than nothing read yet.
  bool _gathered = false;
  int _gathering = 0;
  bool _storyBusy = false;
  bool _shareBusy = false;

  @override
  void initState() {
    super.initState();
    CardLibrary.revision.addListener(_gather);
    ArenaService.state.addListener(_gather);
    _gather();
    // Rounds filed before rounds kept their verses get them from their
    // seeds — once, and the state change gathers them in.
    unawaited(ArenaService.fillVerses());
  }

  @override
  void dispose() {
    CardLibrary.revision.removeListener(_gather);
    ArenaService.state.removeListener(_gather);
    super.dispose();
  }

  @override
  void didUpdateWidget(_VersesPage old) {
    super.didUpdateWidget(old);
    if (!identical(old.reels, widget.reels)) _gather();
  }

  /// Reads every source again; the last read to start is the one kept.
  Future<void> _gather() async {
    final run = ++_gathering;
    final light = await VerseLight.gather(reels: widget.reels);
    if (!mounted || run != _gathering) return;
    setState(() {
      _light = light;
      _gathered = true;
    });
  }

  /// The "?" beside the card: what the sun is, what lights it, what it
  /// can carry, and where it goes.
  void _howTo() {
    final l = L10n.of(context);
    const gold = AppColors.goldBright;
    showHowTo(
      context,
      title: l.sunHowToTitle,
      steps: [
        (
          const CustomPaint(
              size: Size(17, 17), painter: _SunGlyph(lit: false)),
          l.sunHowToRays,
        ),
        (
          const Icon(Icons.auto_awesome_rounded, size: 17, color: gold),
          l.sunHowToLight,
        ),
        (
          const Text('#',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800, color: gold)),
          l.sunHowToOnCard,
        ),
        (
          const Icon(Icons.ios_share_rounded, size: 17, color: gold),
          l.sunHowToShare,
        ),
      ],
    );
  }

  Future<File> _card(L10n l) {
    final s = SettingsService.state.value;
    return VersesStory.render(
      l: l,
      light: _light,
      name: s.versesCardName ? s.name.trim() : '',
      numbers: s.versesCardNumbers,
    );
  }

  Future<void> _toStory(BuildContext buttonContext) async {
    if (_storyBusy) return;
    final l = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final origin = shareOriginOf(buttonContext);
    HapticFeedback.selectionClick();
    setState(() => _storyBusy = true);
    try {
      final card = await _card(l);
      if (await InstagramShare.shareStory(card)) {
        unawaited(RewardsService.recordAppShared());
        return;
      }
      messenger.showSnackBar(
          toast(l.instagramUnavailable, tone: ToastTone.problem));
      await SharePlus.instance.share(ShareParams(
        files: [XFile(card.path, mimeType: 'image/png')],
        text: l.versesShareMessage,
        sharePositionOrigin: origin,
      ));
    } catch (e, s) {
      rlogError('verses story', e, s);
      messenger.showSnackBar(toast(l.shareFailed(e), tone: ToastTone.problem));
    } finally {
      if (mounted) setState(() => _storyBusy = false);
    }
  }

  Future<void> _share(BuildContext buttonContext) async {
    if (_shareBusy) return;
    final l = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final origin = shareOriginOf(buttonContext);
    HapticFeedback.selectionClick();
    setState(() => _shareBusy = true);
    try {
      final card = await _card(l);
      final result = await SharePlus.instance.share(ShareParams(
        files: [XFile(card.path, mimeType: 'image/png')],
        text: l.versesShareMessage,
        sharePositionOrigin: origin,
      ));
      if (result.status != ShareResultStatus.dismissed) {
        unawaited(RewardsService.recordAppShared());
      }
    } catch (e, s) {
      rlogError('verses share', e, s);
      messenger.showSnackBar(toast(l.shareFailed(e), tone: ToastTone.problem));
    } finally {
      if (mounted) setState(() => _shareBusy = false);
    }
  }

  void _make() {
    creationState.startNewReel();
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const ReciterScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final empty = _light.isEmpty;
    // Unlit and not yet read through: the sun alone, no word yet on how
    // to light it — the quiz or the cards may be about to.
    final waiting = empty && !_gathered;
    return ValueListenableBuilder<AppSettings>(
      valueListenable: SettingsService.state,
      builder: (context, s, _) {
        final name = s.name.trim();
        return LayoutBuilder(
          builder: (context, box) {
            // Under the card: its line, the switches, the buttons, and
            // room for the floating bar.
            const below = 112.0 + 156.0;
            final double cardH =
                (box.maxHeight - below - 16).clamp(200.0, 620.0).toDouble();
            final cardW = cardH * VersesStory.width / VersesStory.height;
            // Scrolls only on a screen too short to hold it all; the
            // floating bar's room is kept at the foot either way.
            return SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 112),
              child: Column(
              children: [
                const SizedBox(height: 12),
                // The card, and the "?" beside its top corner, clear of
                // it where the screen has the room.
                SizedBox(
                  width: box.maxWidth,
                  child: Stack(
                    alignment: Alignment.topCenter,
                    children: [
                      _VersesPreview(
                        width: cardW,
                        light: _light,
                        name: s.versesCardName ? name : '',
                        numbers: s.versesCardNumbers && !empty,
                      ),
                      PositionedDirectional(
                        top: 0,
                        end: math.max(2.0, (box.maxWidth - cardW) / 2 - 48),
                        child: HowToButton(
                            label: l.sunHowToTitle, onTap: _howTo),
                      ),
                    ],
                  ),
                ),
                if (!waiting) ...[
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 34),
                    child: Text(
                      empty ? l.versesEmpty : l.versesCaption,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (empty)
                    OutlinedButton.icon(
                      onPressed: _make,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.goldBright,
                        side: BorderSide(
                            color: AppColors.gold.withValues(alpha: 0.5)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.add_rounded, size: 20),
                      label: Text(l.createFirstReel),
                    )
                  else ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (name.isNotEmpty) ...[
                          _OnCard(
                            label: l.versesToggleName,
                            on: s.versesCardName,
                            onTap: () => SettingsService.update(SettingsService
                                .state.value
                                .copyWith(versesCardName: !s.versesCardName)),
                          ),
                          const SizedBox(width: 8),
                        ],
                        _OnCard(
                          label: l.versesToggleNumbers,
                          on: s.versesCardNumbers,
                          onTap: () => SettingsService.update(SettingsService
                              .state.value
                              .copyWith(versesCardNumbers: !s.versesCardNumbers)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      child: Row(
                        children: [
                          if (InstagramShare.supported) ...[
                            Expanded(
                              child: Builder(
                                builder: (bc) => DirectShareButton(
                                  label: l.sendToInstagramStory,
                                  icon: Icons.auto_awesome_rounded,
                                  colors: instagramMesh,
                                  height: 50,
                                  busy: _storyBusy,
                                  onPressed: () => _toStory(bc),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: Builder(
                              builder: (bc) => GlowButton(
                                label: l.share,
                                icon: Icons.ios_share_rounded,
                                height: 50,
                                busy: _shareBusy,
                                onPressed: () => _share(bc),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ],
              ),
            );
          },
        );
      },
    );
  }
}

/// The card on screen, live, in a light frame: rounded, lifted on a
/// soft shadow, light caught along its top edge.
class _VersesPreview extends StatelessWidget {
  final double width;
  final VerseLight light;
  final String name;
  final bool numbers;

  const _VersesPreview({
    required this.width,
    required this.light,
    required this.name,
    required this.numbers,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final height = width * VersesStory.height / VersesStory.width;
    final radius = BorderRadius.circular(width * 0.07);
    return Semantics(
      container: true,
      image: true,
      label: l.a11yVersesCard,
      excludeSemantics: true,
      // It arrives swinging up out of depth, and then sits under glass
      // like the reels beside it: it leans to the finger, the light
      // runs across it, and the slow light drifts over it at rest.
      child: Arrive(
        depth: 0.35,
        child: SizedBox(
        width: width,
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 30,
                offset: const Offset(0, 18),
              ),
              BoxShadow(
                color: AppColors.gold.withValues(alpha: 0.14),
                blurRadius: 40,
                spreadRadius: -6,
              ),
            ],
          ),
          child: GlassTile(
            radius: width * 0.07,
            child: ClipRRect(
            borderRadius: radius,
            child: Stack(
              fit: StackFit.expand,
              children: [
                GlassDepth(
                  child: MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.noScaling),
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: VersesCard(
                      l: l,
                      light: light,
                      name: name,
                      numbers: numbers,
                      live: true,
                    ),
                  ),
                  ),
                ),
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: radius,
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                          width: 0.8),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: const Alignment(0.4, 0.2),
                        colors: [
                          Colors.white.withValues(alpha: 0.07),
                          Colors.white.withValues(alpha: 0),
                        ],
                      ),
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
    );
  }
}

/// A word that is either on the card or not: a small pill with a check
/// that lights gold when it is.
class _OnCard extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;

  const _OnCard({required this.label, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    void tap() {
      HapticFeedback.selectionClick();
      onTap();
    }

    return A11yTap(
      label: label,
      toggled: on,
      button: false,
      onTap: tap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: tap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          height: 34,
          padding: const EdgeInsetsDirectional.fromSTEB(8, 0, 13, 0),
          decoration: BoxDecoration(
            color: on
                ? AppColors.gold.withValues(alpha: 0.12)
                : AppColors.surface.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: on ? AppColors.gold.withValues(alpha: 0.55) : AppColors.stroke,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: on ? AppColors.gold : Colors.transparent,
                  border: Border.all(
                    color: on
                        ? AppColors.goldBright
                        : AppColors.textSecondary.withValues(alpha: 0.5),
                    width: 1.3,
                  ),
                ),
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 200),
                  scale: on ? 1 : 0,
                  child: const Icon(Icons.check_rounded,
                      size: 12, color: Color(0xFF14100A)),
                ),
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: on ? AppColors.textPrimary : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
