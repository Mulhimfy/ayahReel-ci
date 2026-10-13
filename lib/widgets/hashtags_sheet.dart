import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/hashtag_sets.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import 'a11y.dart';

/// The last thing between a finished reel and a posted one.
///
/// A reel leaves this app into a caption box, and what goes in that box
/// decides whether anyone ever finds it. Writing a dozen tags by hand
/// on a phone, per post, is the step people quietly stop doing — so the
/// app carries the tags instead, cut for the app being posted to, one
/// tap to the clipboard.
///
/// A small square in the middle of the screen, not a sheet: this is a
/// clipboard, and a clipboard that rose up over half the preview read
/// as a new screen the user had not asked for. Everything it holds —
/// which app, which block, the block, Copy — fits in a card the size
/// of a hand.
/// The tags, offered the moment a reel is finished.
///
/// Called after every completed export — saved to the gallery or
/// handed to another app — because that is the one second in the whole
/// flow when they are wanted: the reel is in hand, the caption box is
/// the next thing the user will be looking at, and a set of tags
/// copied a minute later is a set of tags nobody goes back for.
///
/// A sheet rather than a snackbar, because the point of it is the tap
/// on Copy. It is dismissible and it is the first thing on screen
/// after the export, ahead of anything the *app* wants to ask (the
/// reminder, the rating, the feedback note) — those are about the app,
/// this is about what the user is doing next.
Future<void> offerHashtagsAfterExport(
  BuildContext context, {
  String? surahName,
}) =>
    showHashtagsSheet(context, surahName: surahName);

Future<void> showHashtagsSheet(BuildContext context, {String? surahName}) {
  HapticFeedback.selectionClick();
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => _HashtagsDialog(surahName: surahName),
  );
}

/// The button that opens them.
///
/// As small as a control can be and still be read: a hairline of gold
/// around a tag and a word, standing on its own directly above Share.
/// Gold because it is a way out of this screen and into the caption
/// box, and the app's ways out are gold — hairline gold, not filled,
/// so the one gold thing that stays loud on the preview is Share. It
/// breathes a little light, the way Share does, so the eye that lands
/// on Share finds it too.
class HashtagsButton extends StatefulWidget {
  /// English surah name of the reel in hand, which earns a block of
  /// tags about this reel rather than about reels in general.
  final String? surahName;

  const HashtagsButton({super.key, this.surahName});

  @override
  State<HashtagsButton> createState() => _HashtagsButtonState();
}

class _HashtagsButtonState extends State<HashtagsButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  bool _still = false;

  /// Reduce motion holds the glow steady at half strength instead of
  /// breathing.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still == _still) return;
    _still = still;
    if (still) {
      _pulse.value = 0.5; // setting the value stops the controller
    } else {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Its own boundary, for the same reason Share has one: the glow
    // repaints every frame, and nothing under it should.
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          final eased = Curves.easeInOut.transform(_pulse.value);
          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AppColors.gold.withValues(alpha: 0.16 + 0.26 * eased),
                  blurRadius: 16,
                  spreadRadius: 0.5,
                ),
              ],
            ),
            child: child,
          );
        },
        child: _pill(context),
      ),
    );
  }

  /// The pill itself, built once per rebuild rather than once per
  /// frame of the glow.
  Widget _pill(BuildContext context) {
    final l = L10n.of(context);
    return Semantics(
      container: true,
      button: true,
      hint: l.a11yOpensHashtags,
      child: Container(
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.55)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () =>
              showHashtagsSheet(context, surahName: widget.surahName),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 12, 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.tag_rounded,
                    size: 12, color: AppColors.goldBright),
                const SizedBox(width: 4),
                Text(
                  l.hashtags,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                        color: AppColors.goldBright,
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

/// The card's width, and near enough its height: a square.
const double _cardSize = 300;

/// How tall the block of tags stands. A longer block scrolls inside
/// it rather than growing the card.
const double _blockHeight = 150;

class _HashtagsDialog extends StatefulWidget {
  final String? surahName;
  const _HashtagsDialog({this.surahName});

  @override
  State<_HashtagsDialog> createState() => _HashtagsDialogState();
}

class _HashtagsDialogState extends State<_HashtagsDialog> {
  TagPlatform _platform = TagPlatform.instagram;
  int _set = 0;

  /// The block whose Copy is currently reading "Copied", and the timer
  /// that puts it back. Keyed by name rather than index so a switch
  /// mid-timer cannot light up the wrong block.
  String? _copied;
  Timer? _reset;

  List<HashtagSet> get _sets =>
      hashtagSets(_platform, surahName: widget.surahName);

  void _pickPlatform(TagPlatform p) {
    if (p == _platform) return;
    HapticFeedback.selectionClick();
    setState(() {
      _platform = p;
      // Back to the first block: the apps hold different blocks, and
      // landing on the third of them says nothing about the app just
      // opened.
      _set = 0;
      _copied = null;
    });
  }

  void _pickSet(int i) {
    if (i == _set) return;
    HapticFeedback.selectionClick();
    setState(() => _set = i);
  }

  void _copy(HashtagSet set) {
    Clipboard.setData(ClipboardData(text: set.text));
    HapticFeedback.selectionClick();
    _reset?.cancel();
    setState(() => _copied = set.key);
    // The button says so itself rather than a snackbar saying it: a
    // bar sliding up under a card the user is still reading covers
    // nothing useful and outlives the card.
    _reset = Timer(const Duration(milliseconds: 1900), () {
      if (mounted) setState(() => _copied = null);
    });
  }

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    final sets = _sets;
    final set = sets[_set.clamp(0, sets.length - 1)];
    // Inter has no Arabic glyphs, and the Arabic block is on offer with
    // the app in English too — read in the UI face it would be a block
    // of empty boxes.
    final tags = set.rtl
        ? GoogleFonts.ibmPlexSansArabic(
            fontSize: 12.5, height: 1.7, color: AppColors.textPrimary)
        : t.bodySmall?.copyWith(
            fontSize: 12.5, height: 1.7, color: AppColors.textPrimary);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        width: _cardSize,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1D2537), Color(0xFF131A28)],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Which app: four equal slots, so the row is the same
            // width whichever is lit.
            Row(
              children: [
                for (final p in TagPlatform.values)
                  Expanded(
                    child: _PlatformTab(
                      label: switch (p) {
                        TagPlatform.instagram => l.platformInstagram,
                        TagPlatform.tiktok => l.platformTikTok,
                        TagPlatform.youtube => l.platformYouTube,
                        TagPlatform.more => l.platformMore,
                      },
                      selected: _platform == p,
                      onTap: () => _pickPlatform(p),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            // Which block: a line of names, scrolling sideways where
            // the curated tab has more than the line holds.
            SizedBox(
              height: 22,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                itemCount: sets.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (_, i) => _SetTab(
                  label: l.hashtagSetLabel(sets[i].key,
                      surahName: widget.surahName ?? ''),
                  selected: i == _set,
                  onTap: () => _pickSet(i),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: _blockHeight,
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.stroke),
              ),
              child: Directionality(
                textDirection:
                    set.rtl ? TextDirection.rtl : TextDirection.ltr,
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: Text(set.text, style: tags),
                ),
              ),
            ),
            const SizedBox(height: 10),
            _CopyBar(copied: _copied == set.key, onTap: () => _copy(set)),
          ],
        ),
      ),
    );
  }
}

/// One of the four app slots. The lit one is a gold hairline, the
/// rest are bare words.
class _PlatformTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PlatformTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return A11yTap(
      selected: selected,
      child: GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 26,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? AppColors.gold.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: selected ? AppColors.gold : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 10.5,
                color:
                    selected ? AppColors.goldBright : AppColors.textSecondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
        ),
      ),
      ),
    );
  }
}

/// One block's name on the line under the apps. Lit by colour alone.
class _SetTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SetTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return A11yTap(
      selected: selected,
      child: GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 160),
          style: Theme.of(context).textTheme.bodySmall!.copyWith(
                fontSize: 11.5,
                color:
                    selected ? AppColors.goldBright : AppColors.textSecondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
          child: Text(label),
        ),
      ),
      ),
    );
  }
}

/// The card's one gold thing. Everything else here is a way of
/// choosing what this button copies.
class _CopyBar extends StatelessWidget {
  final bool copied;
  final VoidCallback onTap;

  const _CopyBar({required this.copied, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final fg = copied ? AppColors.goldBright : const Color(0xFF14100A);
    // Live as well as a button: the word turning to "Copied" is the
    // only confirmation there is, and a reader has to hear it turn.
    return Semantics(
      container: true,
      button: true,
      liveRegion: true,
      hint: l.a11yCopiesTags,
      child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 36,
      decoration: BoxDecoration(
        color: copied ? AppColors.gold.withValues(alpha: 0.14) : null,
        gradient: copied
            ? null
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.goldBright, AppColors.gold],
              ),
        borderRadius: BorderRadius.circular(12),
        border: copied
            ? Border.all(color: AppColors.gold.withValues(alpha: 0.5))
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 170),
              child: Row(
                key: ValueKey(copied),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    copied ? Icons.check_rounded : Icons.copy_rounded,
                    size: 15,
                    color: fg,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    copied ? l.copied : l.copy,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontSize: 13,
                          color: fg,
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
