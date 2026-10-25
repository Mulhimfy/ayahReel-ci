import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/feedback_service.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import 'a11y.dart';
import 'app_toast.dart';
import 'glow_button.dart';
import 'night_sky.dart';

/// The text box. One field, one button, and the note is in an inbox.
///
/// Deliberately not a form: no name, no category picker, no rating out
/// of five, no required email. Every one of those is a question asked
/// before the user has said the thing they opened the sheet to say,
/// and each one is somewhere the sheet can be abandoned. What arrives
/// is a sentence and the context needed to act on it, which
/// [FeedbackService.payload] attaches without asking.
///
/// The optional email is the exception, and it earns its place: it is
/// the difference between reading a bug report and being able to
/// answer it. Left empty, everything still sends.
///
/// Opens from three places — the Settings row, which is permanent, the
/// prompt during the first few renders, and the Report button on a save
/// that went wrong. [source] changes the wording at the top and the tag
/// on the submission; a report also opens with its note written, so
/// one tap on Send is all it asks of someone whose reel just failed.
Future<void> showFeedbackSheet(
  BuildContext context, {
  FeedbackSource source = FeedbackSource.settings,
}) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    isScrollControlled: true,
    builder: (_) => _FeedbackSheet(source: source),
  );
}

class _FeedbackSheet extends StatefulWidget {
  final FeedbackSource source;
  const _FeedbackSheet({required this.source});

  @override
  State<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<_FeedbackSheet> {
  final _message = TextEditingController();
  final _contact = TextEditingController();

  /// True while the POST is in flight. The button shows it and the
  /// fields lock, so a second tap cannot send the note twice.
  bool _sending = false;

  /// Shown under the button after a failed send. Cleared the moment
  /// the user edits anything, because the old failure says nothing
  /// about the next attempt.
  bool _failed = false;

  bool get _report => widget.source == FeedbackSource.exportTrouble;

  @override
  void initState() {
    super.initState();
    if (_report) _message.text = L10n.current.feedbackExportDraft;
    // Rebuilds for the button's enabled state, which follows whether
    // there is anything to send.
    _message.addListener(_onEdit);
  }

  @override
  void dispose() {
    _message.removeListener(_onEdit);
    _message.dispose();
    _contact.dispose();
    super.dispose();
  }

  void _onEdit() {
    if (!mounted) return;
    setState(() => _failed = false);
  }

  bool get _hasNote => _message.text.trim().isNotEmpty;

  Future<void> _send() async {
    if (!_hasNote || _sending) return;
    HapticFeedback.selectionClick();
    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _failed = false;
    });
    final ok = await FeedbackService.send(
      message: _message.text,
      contact: _contact.text,
      source: widget.source,
    );
    if (!mounted) return;
    if (!ok) {
      // The note stays in the box. Losing something a user typed by
      // hand because the network blinked is the one failure this sheet
      // must never have.
      setState(() {
        _sending = false;
        _failed = true;
      });
      return;
    }
    // Captured before the pop: this sheet's context is gone by the
    // time the snack is asked for.
    final messenger = ScaffoldMessenger.of(context);
    // Only while this sheet is on top: after the send's wait a bare pop
    // could close whatever was opened over it instead.
    if (ModalRoute.of(context)?.isCurrent == true) Navigator.of(context).pop();
    messenger
      ..clearSnackBars()
      ..showSnackBar(toast(L10n.current.feedbackThanks, tone: ToastTone.done));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    final (title, body) = switch (widget.source) {
      FeedbackSource.settings ||
      FeedbackSource.rating =>
        (l.feedbackSheetTitle, l.feedbackSheetBody),
      FeedbackSource.afterRender => (
          l.feedbackAfterRenderTitle,
          l.feedbackAfterRenderBody
        ),
      FeedbackSource.exportTrouble => (
          l.feedbackExportTitle,
          l.feedbackExportBody
        ),
    };
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: Stack(
        children: [
          const Positioned.fill(
            child: ExcludeSemantics(
                child: IgnorePointer(child: Starfield(count: 40, seed: 23))),
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
                // The keyboard covers the button otherwise, and this
                // sheet is the one place in the app where the keyboard
                // is up the whole time it is open.
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
                      const SizedBox(height: 22),
                      const Icon(Icons.forum_rounded,
                          size: 30, color: AppColors.goldBright),
                      const SizedBox(height: 16),
                      A11yHeader(
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          style: t.headlineMedium
                              ?.copyWith(fontSize: 22, height: 1.3),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        body,
                        textAlign: TextAlign.center,
                        style: t.bodyMedium?.copyWith(height: 1.55),
                      ),
                      // On the sheet anyone opens from Settings, one quiet
                      // line on what makes a report fixable. The other two
                      // already know what they are asking about.
                      if (widget.source == FeedbackSource.settings) ...[
                        const SizedBox(height: 8),
                        Text(
                          l.feedbackDetailHint,
                          textAlign: TextAlign.center,
                          style: t.bodySmall?.copyWith(
                            fontSize: 12,
                            height: 1.45,
                            color: AppColors.textSecondary
                                .withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      FeedbackField(
                        controller: _message,
                        hint: l.feedbackHint,
                        enabled: !_sending,
                        // A report is already written: the keyboard
                        // would only cover the Send it is waiting on.
                        autofocus: !_report,
                        maxLines: 5,
                        maxLength: FeedbackService.maxMessageLength,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                      ),
                      const SizedBox(height: 12),
                      FeedbackField(
                        controller: _contact,
                        hint: l.feedbackContactHint,
                        enabled: !_sending,
                        maxLines: 1,
                        maxLength: 120,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _send(),
                      ),
                      if (_failed) ...[
                        const SizedBox(height: 12),
                        // Read out as it appears: the note is still in
                        // the box, and the reader has to be told so.
                        A11yLive(
                          child: Text(
                            l.feedbackFailed,
                            textAlign: TextAlign.center,
                            style: t.bodySmall?.copyWith(
                                color: const Color(0xFFE9A08A), height: 1.45),
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      GlowButton(
                        label: l.feedbackSend,
                        icon: Icons.send_rounded,
                        busy: _sending,
                        // Null until there is something to send: a
                        // "Send" that posts an empty note is a dead tap
                        // dressed as a working one.
                        onPressed: _hasNote ? _send : null,
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

/// The sheet's input styling, which is the name dialog's — same fill,
/// same gold focus ring — so a text box here does not read as a
/// different app's. The rating sheet's note box is one too.
class FeedbackField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool enabled;
  final bool autofocus;
  final int maxLines;
  final int maxLength;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;

  const FeedbackField({
    required this.controller,
    required this.hint,
    required this.enabled,
    required this.maxLines,
    required this.maxLength,
    required this.keyboardType,
    required this.textInputAction,
    this.autofocus = false,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return TextField(
      controller: controller,
      enabled: enabled,
      autofocus: autofocus,
      minLines: maxLines > 1 ? 3 : 1,
      maxLines: maxLines,
      maxLength: maxLength,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      textCapitalization: TextCapitalization.sentences,
      style: t.bodyMedium?.copyWith(color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: t.bodyMedium?.copyWith(color: AppColors.textSecondary),
        // The count is noise on a box nobody is going to fill; the cap
        // is there to stop a pasted logfile, not to set a target.
        counterText: '',
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.stroke),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.stroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.gold),
        ),
      ),
    );
  }
}
