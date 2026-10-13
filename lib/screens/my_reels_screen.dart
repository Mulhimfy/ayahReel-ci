import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../data/debug_log.dart';
import '../data/gallery_saver.dart';
import '../data/reel_library.dart';
import '../data/review_prompt.dart';
import '../data/settings_service.dart';
import '../data/share_origin.dart';
import '../data/whatsapp_share.dart';
import '../l10n/l10n.dart';
import '../state/creation_state.dart';
import '../theme/app_theme.dart';
import '../widgets/tanafus_button.dart';
import '../widgets/a11y.dart';
import '../widgets/ambient_motion.dart';
import '../widgets/illumination.dart';
import '../widgets/rate_sheet.dart';
import '../widgets/gallery_blocked_dialog.dart';
import '../widgets/hashtags_sheet.dart';
import '../widgets/reel_thumb.dart';
import '../widgets/storage_sheet.dart';
import 'reciter_screen.dart';
import 'reel_player_screen.dart';
import 'reopen_reel.dart';

/// Every reel the user has exported, newest first. Tap to replay,
/// menu to share again or delete. Lives as a tab in the home shell,
/// refreshing itself whenever the library changes.
class MyReelsScreen extends StatefulWidget {
  const MyReelsScreen({super.key});

  @override
  State<MyReelsScreen> createState() => _MyReelsScreenState();
}

class _MyReelsScreenState extends State<MyReelsScreen> {
  List<SavedReel>? _reels;

  @override
  void initState() {
    super.initState();
    _refresh();
    ReelLibrary.revision.addListener(_refresh);
  }

  @override
  void dispose() {
    ReelLibrary.revision.removeListener(_refresh);
    super.dispose();
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
        SnackBar(content: Text(L10n.of(context).shareFailed(e))),
      );
    }
  }

  Future<void> _shareWhatsApp(SavedReel r, Rect origin) async {
    final file = await ReelLibrary.videoFile(r);
    final handed = await WhatsAppShare.shareVideo(file, text: _caption(r));
    if (handed) return;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.of(context).whatsappUnavailable)),
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
        messenger.showSnackBar(SnackBar(content: Text(l.savedToDevice)));
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
          SnackBar(
              content: Text(result.outOfSpace
                  ? l.phoneStorageFull
                  : l.saveFailed(result.error ?? ''))),
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
                    child: Text(l.navMyReels, style: t.headlineMedium),
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
          Expanded(
            child: reels == null
                ? const Center(
                    child:
                        CircularProgressIndicator(color: AppColors.gold))
                : reels.isEmpty
                    ? _EmptyState(textTheme: t)
                    : GridView.builder(
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
  const _EmptyState({required this.textTheme});

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
    return Semantics(
      container: true,
      button: true,
      hint: l.a11yPlaysReel,
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
            child: Stack(
              fit: StackFit.expand,
              children: [
                ReelThumb(reel: reel),
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
    );
  }
}
