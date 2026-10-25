import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/feedback_service.dart';
import '../data/review_prompt.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import 'a11y.dart';
import 'app_toast.dart';
import 'feedback_sheet.dart';
import 'glow_button.dart';
import 'night_sky.dart';

/// The route to the store that no quota can close, and the ear for
/// everyone the app has not won over yet.
///
/// The OS rating sheet is the only thing allowed to interrupt a user
/// to ask for a rating, and both stores ration it — three times a year
/// on iOS, an undisclosed and changeable allowance on Play — with no
/// way for the app to learn whether any given call showed anything at
/// all. So a user who wants to leave a rating, or who declined the
/// system sheet once and changed their mind, has no way back in. This
/// is that way back: it opens from the Settings row, and on Android
/// after a run of reels (see [ReviewPrompt]).
///
/// Five stars say thank you, and that the store's own stars are the
/// ones that count, then open the store. Fewer open a box for what
/// would make it five — optional, straight to our inbox — with the
/// store's button right under it all the same. The store is never kept
/// from anyone: a sheet that sent only the happy to the store would be
/// review gating — manipulating reviews to Apple (5.6.3), an opinion
/// question before the rating to Google — so this one sends everyone,
/// and asks the rest what to fix.
Future<void> showRateSheet(BuildContext context) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    isScrollControlled: true,
    builder: (_) => const _RateSheet(),
  );
}

/// How long the thanks after five stars stays up before the store
/// opens: long enough to read that the store asks for the stars again.
@visibleForTesting
const rateStoreDelay = Duration(milliseconds: 1600);

class _RateSheet extends StatefulWidget {
  const _RateSheet();

  @override
  State<_RateSheet> createState() => _RateSheetState();
}

class _RateSheetState extends State<_RateSheet> {
  /// The stars tapped; 0 before any.
  int _stars = 0;

  final _note = TextEditingController();

  /// While the note is on its way: the button shows it and nothing
  /// sends it twice.
  bool _sending = false;

  /// Under the button after a failed send, until the next edit.
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _note.addListener(_onEdit);
  }

  @override
  void dispose() {
    _note.removeListener(_onEdit);
    _note.dispose();
    super.dispose();
  }

  void _onEdit() {
    if (mounted) setState(() => _failed = false);
  }

  Future<void> _pick(int n) async {
    HapticFeedback.selectionClick();
    setState(() => _stars = n);
    unawaited(ReviewPrompt.answered());
    if (n < 5) return;
    // Five: to the store, where the stars count — after the thanks has
    // been read, so nobody takes our stars for the rating itself.
    await Future<void>.delayed(rateStoreDelay);
    if (mounted && _stars == 5) await _openStore();
  }

  Future<void> _openStore() async {
    // Captured before the pop: the sheet's context is gone by the time
    // the browser hand-off returns, and the snack has to outlive it.
    final messenger = ScaffoldMessenger.of(context);
    if (ModalRoute.of(context)?.isCurrent == true) Navigator.of(context).pop();
    if (await ReviewPrompt.openListing()) return;
    if (!messenger.mounted) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(toast(
        L10n.current.storeOpenFailed,
        tone: ToastTone.problem,
      ));
  }

  Future<void> _send() async {
    final text = _note.text.trim();
    if (text.isEmpty || _sending) return;
    HapticFeedback.selectionClick();
    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _failed = false;
    });
    final ok = await FeedbackService.send(
      message: '${'★' * _stars}${'☆' * (5 - _stars)} ($_stars/5)\n\n$text',
      source: FeedbackSource.rating,
    );
    if (!mounted) return;
    if (!ok) {
      // The note stays in the box; a retry is one tap.
      setState(() {
        _sending = false;
        _failed = true;
      });
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    if (ModalRoute.of(context)?.isCurrent == true) Navigator.of(context).pop();
    messenger
      ..clearSnackBars()
      ..showSnackBar(toast(L10n.current.feedbackThanks, tone: ToastTone.done));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    final low = _stars > 0 && _stars < 5;
    final line = _stars == 5
        ? l.rateFiveThanks(appStore: Platform.isIOS)
        : low
            ? l.rateWhatWouldHelp
            : l.rateHowMany;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: Stack(
        children: [
          const Positioned.fill(
            child: ExcludeSemantics(
                child: IgnorePointer(child: Starfield(count: 40, seed: 11))),
          ),
          const Positioned(
            top: -90,
            right: -70,
            child: GlowOrb(size: 240, alpha: 0.15),
          ),
          Container(
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
            child: SafeArea(
              top: false,
              child: Padding(
                // The keyboard would cover the note's button otherwise.
                padding: EdgeInsets.only(
                    bottom: MediaQuery.viewInsetsOf(context).bottom),
                child: SingleChildScrollView(
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
                      const SizedBox(height: 18),
                      _Stars(
                        value: _stars,
                        onPick: _sending ? null : _pick,
                      ),
                      const SizedBox(height: 14),
                      A11yHeader(
                        child: Text(
                          l.rateSheetTitle,
                          textAlign: TextAlign.center,
                          style: t.headlineMedium
                              ?.copyWith(fontSize: 22, height: 1.3),
                        ),
                      ),
                      const SizedBox(height: 10),
                      A11yLive(
                        child: Text(
                          line,
                          textAlign: TextAlign.center,
                          style: t.bodyMedium?.copyWith(height: 1.55),
                        ),
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child: !low
                            ? const SizedBox(width: double.infinity)
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(height: 16),
                                  FeedbackField(
                                    controller: _note,
                                    hint: l.feedbackHint,
                                    enabled: !_sending,
                                    maxLines: 4,
                                    maxLength:
                                        FeedbackService.maxMessageLength,
                                    keyboardType: TextInputType.multiline,
                                    textInputAction: TextInputAction.newline,
                                  ),
                                  if (_failed) ...[
                                    const SizedBox(height: 10),
                                    A11yLive(
                                      child: Text(
                                        l.feedbackFailed,
                                        textAlign: TextAlign.center,
                                        style: t.bodySmall?.copyWith(
                                            color: const Color(0xFFE9A08A),
                                            height: 1.45),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 14),
                                  GlowButton(
                                    label: l.feedbackSend,
                                    icon: Icons.send_rounded,
                                    busy: _sending,
                                    onPressed: _note.text.trim().isEmpty
                                        ? null
                                        : _send,
                                  ),
                                  const SizedBox(height: 4),
                                  // The store, for every rating.
                                  QuietButton(
                                    label: Platform.isIOS
                                        ? l.openAppStore
                                        : l.openPlayStore,
                                    onPressed: _sending ? null : _openStore,
                                  ),
                                ],
                              ),
                      ),
                      const SizedBox(height: 6),
                      QuietButton(
                        label: l.notNow,
                        onPressed: _sending
                            ? null
                            : () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Five stars to tap, lit up to [value].
class _Stars extends StatelessWidget {
  final int value;
  final ValueChanged<int>? onPick;

  const _Stars({required this.value, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var n = 1; n <= 5; n++)
          A11yTap(
            label: l.rateStars(n),
            selected: value == n,
            onTap: onPick == null ? null : () => onPick!(n),
            child: GestureDetector(
              key: ValueKey('rate-star-$n'),
              behavior: HitTestBehavior.opaque,
              onTap: onPick == null ? null : () => onPick!(n),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: AnimatedScale(
                  scale: n <= value ? 1.12 : 1,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutBack,
                  child: Icon(
                    Icons.star_rounded,
                    size: 38,
                    color: n <= value
                        ? AppColors.goldBright
                        : AppColors.stroke.withValues(alpha: 0.9),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
