import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/reminder_service.dart';
import '../data/settings_service.dart';
import '../data/verse_translation.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import '../widgets/a11y.dart';
import '../widgets/ambient_motion.dart';
import '../widgets/arena_fx.dart';
import '../widgets/cinematic_hero.dart';
import '../widgets/glow_button.dart';
import '../widgets/illumination.dart';
import '../widgets/living_sky.dart';
import '../widgets/night_sky.dart';
import '../widgets/reminder_time_picker.dart';
import '../widgets/shimmer_text.dart';
import '../widgets/ambient_pace.dart';

/// First run, eight screens, one argument.
///
/// The order is the whole point: the dream before the problem, the
/// problem before the app, and the app only ever as the means. A user
/// who is shown the tool first has nothing to want it for.
///
///   1. the language     which one of these is yours
///   2. the dream        a verse of yours, travelling
///   3. the problem      the feed was never going to carry it
///   4. the answer       be the reason there's Quran on someone's phone
///   5. the reward       every share is sadaqah jariyah
///   6. the craft        beautiful, easy, and under a minute
///   7. the habit        pick the time we meet you
///   8. bismillah        go and make the first one
///
/// The language comes before the dream for the one reason that beats
/// the order above: every page after it is an argument, and an
/// argument in a language you do not read is not one.
///
/// Every surface here — the sky, the ornament, the gold, the glowing
/// button — is the same widget the Home screen uses. What is promised
/// on these pages is literally what opens behind them.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;
  const OnboardingScreen({super.key, required this.onDone});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _pageCount = 8;
  static const _langPage = 0; // zero-based
  static const _timePage = 7;

  final _controller = PageController();
  int _index = 0;

  /// The same signal Home's sky runs on. Onboarding is the first thing
  /// the user touches, so the night has to answer their swipes here
  /// exactly the way it will answer their scrolls in a minute's time —
  /// otherwise the app they were shown is not the app they arrive in.
  final _motion = AmbientMotion();

  /// Chosen on page 6. Nothing is armed and no OS permission is asked
  /// here — the ask is saved for the moment the user has just made
  /// something they're proud of.
  TimeOfDay _time = const TimeOfDay(hour: 20, minute: 0);
  bool _wantsReminder = true;

  /// The OS is asked at most once here, however many times the user
  /// swipes back and forth across the time page.
  bool _asked = false;

  /// Set the moment the flow starts closing. Begin and Skip are both
  /// still on screen while the settings write runs, and a second tap
  /// on either used to run the whole finish again.
  bool _finishing = false;

  @override
  void dispose() {
    _controller.dispose();
    _motion.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (_finishing) return;
    // A page still turning has already taken its tap. [_index] moves at
    // the halfway mark, so a quick second tap would act for the page
    // that is only arriving: from the page before the reminder's, it
    // asked for notifications without the user ever seeing that page.
    final page = _controller.hasClients ? _controller.page : null;
    if (page != null && (page - page.roundToDouble()).abs() > 0.01) return;
    if (page != null && page.round() != _index) return;
    HapticFeedback.selectionClick();
    // Leaving the time page is the moment to ask: the user has just
    // named an hour, so the system dialog reads as the last step of
    // their own decision rather than an interruption.
    if (_index == _timePage && _wantsReminder && !_asked) {
      setState(() => _asked = true);
      await _armChosenReminder();
      if (!mounted) return;
    }
    if (_index == _pageCount - 1) {
      await _finish(keepReminder: _wantsReminder);
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  /// Persist the choice, then ask the OS and arm it.
  ///
  /// A refusal is not treated as a failure worth stopping for: the
  /// choice stays saved, and Settings shows a banner that leads back to
  /// the system screen. Trapping someone on an onboarding page over a
  /// permission would cost more than the reminder is worth.
  Future<void> _armChosenReminder() async {
    final s = SettingsService.state.value;
    await SettingsService.update(s.copyWith(
      personalReminderOn: true,
      personalHour: _time.hour,
      personalMinute: _time.minute,
    ));
    await ReminderService.requestAndArm();
  }

  Future<void> _finish({required bool keepReminder}) async {
    if (_finishing) return;
    _finishing = true;
    final s = SettingsService.state.value;
    await SettingsService.update(s.copyWith(
      onboardingDone: true,
      personalReminderOn: keepReminder,
      personalHour: _time.hour,
      personalMinute: _time.minute,
    ));
    // They can arm it on the way forward and change their mind on the
    // way back, so the last word wins over what is already scheduled.
    if (!keepReminder) await ReminderService.cancelPersonalReminder();
    if (!mounted) return;
    widget.onDone();
  }

  /// Writes the language through to settings on the tap rather than
  /// holding it until the end.
  ///
  /// The MaterialApp above this screen listens to the same value, so
  /// the tap re-reads every page of this flow and mirrors it to RTL on
  /// the spot. That is the whole confirmation: there is nothing else
  /// on the page to press, and the user sees the answer in the words
  /// they are already looking at.
  Future<void> _pickLanguage(AppLang lang) async {
    final s = SettingsService.state.value;
    if (s.lang == lang) return;
    HapticFeedback.selectionClick();
    // The translation follows the language chosen here, because it is
    // the only signal there is at this point and it is nearly always
    // right. Settings can part them again afterwards.
    await SettingsService.update(s.copyWith(
      lang: lang,
      translation: VerseTranslation.forAppLang(lang.code),
    ));
  }

  Future<void> _pickTime() async {
    HapticFeedback.selectionClick();
    final picked = await pickReminderTime(
      context,
      initial: _time,
      helpText: L10n.of(context).myDailyMoment,
    );
    if (picked == null) return;
    setState(() {
      _time = picked;
      _wantsReminder = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    final last = _index == _pageCount - 1;

    return Scaffold(
      body: Stack(
        children: [
          // One sky behind all eight pages. The pages move across it
          // and it answers, slowly and from further away — so the
          // argument is being made somewhere, rather than on a slide.
          Positioned.fill(
            child: ExcludeSemantics(
              child: IgnorePointer(child: LivingSky(motion: _motion)),
            ),
          ),
          // And behind the last of them, the world arrives.
          //
          // The scenery Home will open on fades up across the final
          // pages, so by the time the user presses Begin they are
          // already standing in the screen they are about to be handed.
          // The app they were argued into is, to the pixel, the app
          // they land in.
          Positioned.fill(
            child: ExcludeSemantics(
              child: IgnorePointer(child: _Arrival(_controller)),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                SizedBox(
                  height: 44,
                  // Absent on the first page as well as the last: a
                  // Skip sitting beside the language question reads as
                  // an answer to it, and it is the one page here that
                  // has to be answered. Continuing past it costs one
                  // tap and leaves English chosen.
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 220),
                      opacity: last || _index == _langPage ? 0 : 1,
                      child: IgnorePointer(
                        ignoring: last || _index == _langPage,
                        child: TextButton(
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            // Skipping is not a preference: the user
                            // never chose a time, so nothing is stored
                            // as if they had.
                            _finish(keepReminder: false);
                          },
                          child: Text(l.skip,
                              style: t.bodyMedium
                                  ?.copyWith(color: AppColors.textSecondary)),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: AmbientScrollSensor(
                    motion: _motion,
                    child: PageView(
                    controller: _controller,
                    onPageChanged: (i) {
                      HapticFeedback.selectionClick();
                      setState(() => _index = i);
                    },
                    children: [
                      _parallax(
                        0,
                        // Watches the setting itself rather than
                        // waiting for the rebuild to come back down
                        // from the MaterialApp: the tick has to move
                        // under the finger even in a harness that
                        // isn't listening for the locale.
                        ValueListenableBuilder<AppSettings>(
                          valueListenable: SettingsService.state,
                          builder: (context, s, _) => _LanguagePage(
                            lang: s.lang,
                            onPick: _pickLanguage,
                          ),
                        ),
                      ),
                      _parallax(1, const _DreamPage()),
                      _parallax(2, const _ProblemPage()),
                      _parallax(3, const _AnswerPage()),
                      _parallax(4, const _RewardPage()),
                      _parallax(5, const _CraftPage()),
                      _parallax(6, const _ArenaPage()),
                      _parallax(
                        7,
                        _HabitPage(
                          time: _time,
                          enabled: _wantsReminder,
                          onPick: _pickTime,
                        ),
                      ),
                    ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 8, 28, 20),
                  child: Column(
                    children: [
                      _Dots(count: _pageCount, index: _index),
                      const SizedBox(height: 18),
                      // The way out of the reminder, just above the button
                      // that accepts it.
                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        child: _index == _timePage && _wantsReminder
                            ? Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: QuietButton(
                                  label: l.noReminderThanks,
                                  onPressed: () {
                                    HapticFeedback.selectionClick();
                                    setState(() => _wantsReminder = false);
                                  },
                                ),
                              )
                            : const SizedBox(width: double.infinity),
                      ),
                      GlowButton(
                        // Deliberately not "Create my first reel": this
                        // opens Home, and Home's Create card repeats
                        // page 3's promise word for word under the same
                        // ornament. A CTA that named the wizard would
                        // break the arrival on its first step.
                        label: _index == _timePage
                            ? (_wantsReminder && !_asked
                                // Names the system dialog that is
                                // about to appear, so it never
                                // arrives unannounced.
                                ? l.allowNotifications
                                : l.begin)
                            : l.continueLabel,
                        icon: last ? Icons.auto_awesome_rounded : null,
                        breathe: last,
                        onPressed: _next,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Content drifts and fades against the fixed sky as the page turns —
  /// a half-step slower than the swipe, which is what makes the sky
  /// read as further away.
  Widget _parallax(int page, Widget child) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, c) {
        final current = _controller.hasClients &&
                _controller.position.hasContentDimensions
            ? (_controller.page ?? _controller.initialPage.toDouble())
            : _index.toDouble();
        final d = (current - page).clamp(-1.0, 1.0);
        // A raw translation does not mirror the way the rest of the
        // tree does, so the drift is turned by hand — otherwise, once
        // page 1 flips the app to Arabic, the content would lag the
        // swipe from the wrong side.
        final sign =
            Directionality.of(context) == TextDirection.rtl ? 1.0 : -1.0;
        final away = d.abs();
        return Opacity(
          opacity: (1 - away).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(sign * d * 46, 0),
            // The outgoing page also falls back into the sky rather
            // than only sliding off it, which is what makes the swipe
            // read as depth instead of as a filmstrip.
            child: Transform.scale(scale: 1 - away * 0.06, child: c),
          ),
        );
      },
      child: child,
    );
  }
}

// ---------------------------------------------------------------------
// Page scaffold
// ---------------------------------------------------------------------

/// Every page is the same three beats — emblem, headline, one
/// paragraph — so the eye lands in the same place seven times and the
/// only thing that changes is the argument.
class _PageBody extends StatelessWidget {
  final Widget emblem;
  final String? label;
  final Widget headline;
  final Widget body;

  const _PageBody({
    required this.emblem,
    required this.headline,
    required this.body,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    // Scrolls rather than overflows on short screens, but stays
    // optically centred on tall ones.
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
        child: ConstrainedBox(
          // Clamped: the page sliver measures at zero extent on one
          // layout pass, and a bare subtraction makes that a negative
          // minimum, which is not a valid constraint.
          constraints: BoxConstraints(
            minHeight: (box.maxHeight - 24).clamp(0.0, double.infinity),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              emblem,
              const SizedBox(height: 34),
              if (label != null) ...[
                // Set in capitals for the eye; read in sentence case,
                // since some readers spell an all-caps word out.
                Semantics(
                  container: true,
                  label: _spoken(label!),
                  excludeSemantics: true,
                  child: Text(
                    label!,
                    style: t.bodySmall?.copyWith(
                      color: AppColors.gold,
                      fontSize: 11,
                      letterSpacing: 1.6,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              headline,
              const SizedBox(height: 14),
              body,
            ],
          ),
        ),
      ),
    );
  }
}

/// An all-caps page label in sentence case: 'WHAT THIS IS FOR' -> 'What
/// this is for'. Arabic has no case and comes back untouched.
String _spoken(String label) {
  if (label != label.toUpperCase()) return label;
  final lower = label.toLowerCase();
  return lower.substring(0, 1).toUpperCase() + lower.substring(1);
}

TextStyle _headlineStyle(BuildContext context, {double size = 26}) =>
    Theme.of(context).textTheme.headlineMedium!.copyWith(
          fontSize: size,
          height: 1.28,
          // Negative tracking breaks joined Arabic script.
          letterSpacing: L10n.of(context).arabicScript ? 0 : -0.4,
        );

Widget _body(BuildContext context, String text) => Text(
      text,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontSize: 15,
            height: 1.6,
          ),
    );

Widget _headline(BuildContext context, String text, {double size = 26}) =>
    A11yHeader(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: _headlineStyle(context, size: size),
      ),
    );

// ---------------------------------------------------------------------
// 1 · Language
// ---------------------------------------------------------------------

/// The one page here that is a setting rather than an argument.
///
/// Every card says its own name in its own script, whatever the app is
/// currently set to: a card that renamed itself in the language you
/// cannot read would be unreadable exactly when it matters. The choice
/// takes effect under the finger — the headline above it is already in
/// the new language before the finger lifts — so nothing on this page
/// needs a Save.
///
/// Choosing here also sets the verse translation to match, which is
/// right almost every time and is the only signal available this
/// early. Settings can part the two afterwards.
class _LanguagePage extends StatefulWidget {
  final AppLang lang;
  final ValueChanged<AppLang> onPick;

  const _LanguagePage({required this.lang, required this.onPick});

  @override
  State<_LanguagePage> createState() => _LanguagePageState();
}

class _LanguagePageState extends State<_LanguagePage> {
  /// Arabic and English stand on the page; the rest wait behind More,
  /// unless one of them is already the language in use.
  static const _first = [AppLang.ar, AppLang.en];
  late bool _more = !_first.contains(widget.lang);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    final lang = widget.lang;
    final shown = [
      ..._first,
      if (_more) ...AppLang.values.where((o) => !_first.contains(o)),
    ];
    return _PageBody(
      emblem: _ScriptEmblem(arabic: lang.arabicScript),
      label: l.obLangLabel,
      headline: _headline(context, l.obLangHeadline),
      body: Column(
        children: [
          _body(context, l.obLangBody),
          const SizedBox(height: 22),
          // Each card carries one word and no translation of it:
          // 'English' is the word an English reader is looking for, in
          // the alphabet they are looking for it in, and 'العربية' is
          // the same for an Arabic one. Naming any of them in another
          // language would put the label out of reach of exactly the
          // reader it is for.
          for (final option in shown) ...[
            _LanguageChoice(
              endonym: option.nativeName,
              direction: option.direction,
              arabicScript: option.arabicScript,
              selected: option == lang,
              onTap: () => widget.onPick(option),
            ),
            const SizedBox(height: 10),
          ],
          if (!_more)
            // In gold, so the other languages read as there to be had
            // and not as small print.
            TextButton.icon(
              onPressed: () => setState(() => _more = true),
              icon: const Icon(Icons.expand_more_rounded,
                  size: 20, color: AppColors.goldBright),
              label: Text(
                l.moreLanguages,
                style: t.bodyMedium?.copyWith(
                  color: AppColors.goldBright,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            l.obLangHint,
            textAlign: TextAlign.center,
            style: t.bodySmall?.copyWith(
              color: AppColors.textSecondary,
              fontSize: 11.5,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

/// One of the languages, as a full-width card.
///
/// [endonym] is pinned to its own [direction] rather than inheriting
/// the app's, so the Arabic card sits right-aligned even while the app
/// is still in English, and the English card stays left-aligned after
/// the switch. Each card therefore looks, before it is chosen, exactly
/// like the app it is about to produce.
class _LanguageChoice extends StatelessWidget {
  final String endonym;
  final TextDirection direction;

  /// Whether the name needs the Arabic-capable face. Inter has no
  /// glyphs for اردو, so a card set in it would be four empty boxes.
  final bool arabicScript;
  final bool selected;
  final VoidCallback onTap;

  const _LanguageChoice({
    required this.endonym,
    required this.direction,
    required this.arabicScript,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      hint: L10n.of(context).a11ySetsLanguage,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.gold.withValues(alpha: 0.12)
                  : AppColors.surface.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected
                    ? AppColors.gold.withValues(alpha: 0.7)
                    : AppColors.stroke,
                width: selected ? 1.3 : 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Directionality(
                    textDirection: direction,
                    child: Text(
                      endonym,
                      textAlign: TextAlign.start,
                      // The face comes from the language named, not
                      // from the app: Inter has no Arabic glyphs, so
                      // 'اردو' set in the English theme's face would
                      // be four empty boxes on the one card that has
                      // to be legible to an Urdu reader.
                      style: AppTheme.translation(
                        size: 19,
                        arabic: arabicScript,
                        color: selected
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ).copyWith(fontStyle: FontStyle.normal),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    key: ValueKey(selected),
                    size: 22,
                    color: selected ? AppColors.goldBright : AppColors.stroke,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The two alphabets side by side, the chosen one lit. It fills the same
/// 168 box every other emblem does, so the headline under it does not
/// jump as the pages turn.
class _ScriptEmblem extends StatelessWidget {
  final bool arabic;
  const _ScriptEmblem({required this.arabic});

  @override
  Widget build(BuildContext context) {
    // Two letters as ornament, not two words to read out.
    return ExcludeSemantics(
      child: SizedBox(
      width: 168,
      height: 168,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const GlowOrb(size: 168, alpha: 0.16),
          // Pinned left-to-right: these are two glyphs standing next to
          // each other, not a sentence, and they should not trade places
          // when the app mirrors mid-page.
          Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Glyph(glyph: 'A', lit: !arabic),
                const SizedBox(width: 12),
                _Glyph(glyph: 'ع', lit: arabic),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}

class _Glyph extends StatelessWidget {
  final String glyph;
  final bool lit;
  const _Glyph({required this.glyph, required this.lit});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      width: 58,
      height: 58,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.gold.withValues(alpha: lit ? 0.16 : 0.04),
        border: Border.all(
          color: AppColors.gold.withValues(alpha: lit ? 0.55 : 0.18),
          width: 1,
        ),
      ),
      child: Text(
        glyph,
        style: t.headlineMedium?.copyWith(
          fontSize: 24,
          color: lit ? AppColors.goldBright : AppColors.textSecondary,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// 2 · The dream
// ---------------------------------------------------------------------

class _DreamPage extends StatelessWidget {
  const _DreamPage();

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return _PageBody(
      emblem: const _RippleEmblem(),
      label: l.obDreamLabel,
      headline: _headline(context, l.obDreamHeadline),
      body: _body(context, l.obDreamBody),
    );
  }
}

/// A verse leaving one hand and spreading outward — rings that swell,
/// fade, and are replaced from the centre, endlessly.
class _RippleEmblem extends StatefulWidget {
  const _RippleEmblem();

  @override
  State<_RippleEmblem> createState() => _RippleEmblemState();
}

class _RippleEmblemState extends State<_RippleEmblem>
    with AmbientTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: ambient,
    duration: const Duration(milliseconds: 4200),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return SizedBox(
      width: 168,
      height: 168,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const GlowOrb(size: 168, alpha: 0.16),
          if (!still)
            Positioned.fill(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (context, _) =>
                      CustomPaint(painter: _RipplePainter(_c.value)),
                ),
              ),
            ),
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.gold.withValues(alpha: 0.16),
              border: Border.all(
                  color: AppColors.gold.withValues(alpha: 0.55), width: 1),
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                size: 26, color: AppColors.goldBright),
          ),
        ],
      ),
    );
  }
}

class _RipplePainter extends CustomPainter {
  final double phase;
  const _RipplePainter(this.phase);

  static const _rings = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final maxR = size.width / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    for (var i = 0; i < _rings; i++) {
      // Evenly spaced along one cycle, so a ring leaves the centre
      // exactly as the one ahead of it reaches the edge.
      final t = (phase + i / _rings) % 1.0;
      paint.color = AppColors.gold.withValues(alpha: 0.5 * (1 - t));
      canvas.drawCircle(centre, 30 + t * (maxR - 30), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RipplePainter old) => old.phase != phase;
}

// ---------------------------------------------------------------------
// 3 · The problem
// ---------------------------------------------------------------------

class _ProblemPage extends StatelessWidget {
  const _ProblemPage();

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return _PageBody(
      emblem: const _DimFeedEmblem(),
      label: l.obProblemLabel,
      headline: _headline(context, l.obProblemHeadline),
      body: _body(context, l.obProblemBody),
    );
  }
}

/// Three grey cards in a dead stack: a feed with nothing in it worth
/// stopping for. Deliberately the only page with no gold on it.
class _DimFeedEmblem extends StatelessWidget {
  const _DimFeedEmblem();

  @override
  Widget build(BuildContext context) {
    Widget card(double scale, double dy, double alpha) => Transform.translate(
          offset: Offset(0, dy),
          child: Transform.scale(
            scale: scale,
            child: Container(
              width: 116,
              height: 148,
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: alpha),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: AppColors.stroke.withValues(alpha: alpha)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final w in [0.85, 0.6, 0.72, 0.4]) ...[
                      FractionallySizedBox(
                        widthFactor: w,
                        child: Container(
                          height: 6,
                          decoration: BoxDecoration(
                            color: AppColors.stroke.withValues(alpha: alpha),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      const SizedBox(height: 9),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );

    return SizedBox(
      height: 168,
      child: Stack(
        alignment: Alignment.center,
        children: [
          card(0.80, -14, 0.35),
          card(0.90, -7, 0.6),
          card(1.0, 0, 1),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// 4 · The answer
// ---------------------------------------------------------------------

class _AnswerPage extends StatelessWidget {
  const _AnswerPage();

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return _PageBody(
      // The Create card's own letterhead, at the Create card's own
      // size, so the promise and the button that keeps it wear exactly
      // the same crown.
      emblem: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6),
        child: BismillahOrnament(),
      ),
      label: l.obAnswerLabel,
      headline: ShimmerText(
        text: l.beTheReason,
        style: _headlineStyle(context, size: 25),
        perWord: const Duration(milliseconds: 250),
      ),
      body: _body(context, l.obAnswerBody),
    );
  }
}

// ---------------------------------------------------------------------
// 5 · The reward
// ---------------------------------------------------------------------

class _RewardPage extends StatelessWidget {
  const _RewardPage();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    return _PageBody(
      emblem: const _RingEmblem(icon: Icons.all_inclusive_rounded),
      label: l.obRewardLabel,
      headline: ShimmerText(
        text: l.renderingShimmer,
        style: _headlineStyle(context, size: 21),
        perWord: const Duration(milliseconds: 215),
      ),
      body: Column(
        children: [
          _body(context, l.obRewardBody),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: AppColors.gold.withValues(alpha: 0.22)),
            ),
            child: Column(
              children: [
                Text(
                  l.hadithGuidesToGood,
                  textAlign: TextAlign.center,
                  style: AppTheme.translation(size: 14, arabic: l.arabicScript)
                      .copyWith(color: AppColors.textPrimary, height: 1.55),
                ),
                const SizedBox(height: 8),
                Text(l.sahihMuslim,
                    style: t.bodySmall?.copyWith(
                      color: AppColors.gold,
                      fontSize: 11.5,
                      letterSpacing: 0.6,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A single icon inside a thin gold ring, lit from behind.
class _RingEmblem extends StatelessWidget {
  final IconData icon;
  const _RingEmblem({required this.icon});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 132,
      height: 132,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const GlowOrb(size: 132, alpha: 0.16),
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.gold.withValues(alpha: 0.10),
              border: Border.all(
                  color: AppColors.gold.withValues(alpha: 0.45), width: 1),
            ),
            child: Icon(icon, size: 38, color: AppColors.goldBright),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// 6 · The craft
// ---------------------------------------------------------------------

class _CraftPage extends StatelessWidget {
  const _CraftPage();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    final steps = [
      (Icons.record_voice_over_rounded, l.stepReciter),
      (Icons.menu_book_rounded, l.stepVerses),
      (Icons.landscape_rounded, l.stepScenery),
      (Icons.ios_share_rounded, l.stepShare),
    ];
    return _PageBody(
      // The four taps, laid out as the four taps. Nothing here is a
      // stock illustration — this is the wizard the button opens.
      emblem: SizedBox(
        height: 168,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // The four share the width equally rather than sizing to
            // their labels, so a long word or a large text scale can
            // never push the row past the screen.
            Row(
              children: [
                for (var i = 0; i < steps.length; i++) ...[
                  if (i > 0)
                    Container(
                      width: 14,
                      height: 0.8,
                      color: AppColors.gold.withValues(alpha: 0.35),
                    ),
                  Expanded(
                    child: Column(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.gold.withValues(alpha: 0.10),
                            border: Border.all(
                                color: AppColors.gold.withValues(alpha: 0.38)),
                          ),
                          child: Icon(steps[i].$1,
                              size: 20, color: AppColors.goldBright),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          steps[i].$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: t.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
      label: l.obCraftLabel,
      headline: _headline(context, l.obCraftHeadline),
      body: _body(context, l.obCraftBody),
    );
  }
}

// ---------------------------------------------------------------------
// 7 · The arena
// ---------------------------------------------------------------------

/// Tanafus, said in the same three beats as the argument before it:
/// the crown turning in its glow, the dare in the word-glow, and what
/// a round is in one paragraph.
class _ArenaPage extends StatelessWidget {
  const _ArenaPage();

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return _PageBody(
      emblem: const _CrownEmblem(),
      label: l.obArenaLabel,
      headline: ShimmerText(
        text: l.obArenaHeadline,
        style: _headlineStyle(context, size: 23),
        perWord: const Duration(milliseconds: 230),
      ),
      body: _body(context, l.obArenaBody),
    );
  }
}

/// The arena's crown in a gold ring, its light running round the
/// thread as it does on the roundel.
class _CrownEmblem extends StatefulWidget {
  const _CrownEmblem();

  @override
  State<_CrownEmblem> createState() => _CrownEmblemState();
}

class _CrownEmblemState extends State<_CrownEmblem>
    with AmbientTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: ambient,
    duration: const Duration(milliseconds: 5200),
  )..repeat();

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return SizedBox(
      width: 132,
      height: 132,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const GlowOrb(size: 132, alpha: 0.16),
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.gold.withValues(alpha: 0.10),
              border: Border.all(
                  color: AppColors.gold.withValues(alpha: 0.45), width: 1),
            ),
            alignment: Alignment.center,
            child: AnimatedBuilder(
              animation: _turn,
              builder: (context, _) =>
                  TanafusMark(size: 54, phase: still ? 0 : _turn.value),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// 8 · The habit
// ---------------------------------------------------------------------

class _HabitPage extends StatelessWidget {
  final TimeOfDay time;
  final bool enabled;
  final VoidCallback onPick;

  const _HabitPage({
    required this.time,
    required this.enabled,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    final formatted = MaterialLocalizations.of(context).formatTimeOfDay(time);

    return _PageBody(
      // The dial reads as decoration to some people, so the same tap is
      // spelled out underneath it in words.
      emblem: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TimeDial(time: time, enabled: enabled, onTap: onPick),
          const SizedBox(height: 2),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 230),
            child: GlowButton(
              label: enabled ? l.setYourTime : l.setATime,
              icon: Icons.schedule_rounded,
              height: 46,
              onPressed: onPick,
            ),
          ),
        ],
      ),
      label: l.obHabitLabel,
      headline: _headline(context, l.obHabitHeadline),
      body: Column(
        children: [
          _body(
            context,
            enabled
                ? l.obHabitBodyEnabled(formatted)
                : l.obHabitBodyDeclined,
          ),
          const SizedBox(height: 18),
          // Says exactly what the next tap does. A system permission
          // dialog that arrives unannounced gets refused on reflex.
          if (enabled)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_outline_rounded,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    l.phoneWillAskNext,
                    textAlign: TextAlign.center,
                    style: t.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 11.5,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// The chosen time, set like a jewel — big enough to be the subject of
/// the page, and the only tappable thing on it.
class _TimeDial extends StatelessWidget {
  final TimeOfDay time;
  final bool enabled;
  final VoidCallback onTap;

  const _TimeDial({
    required this.time,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final formatted = MaterialLocalizations.of(context).formatTimeOfDay(time);
    // Unlike the other emblems this one is type, not geometry: it is
    // left free to grow with the user's text scale rather than pinned
    // to the 168 the rest of them share.
    return Stack(
      alignment: Alignment.center,
      children: [
        if (enabled) const GlowOrb(size: 210, alpha: 0.14),
        Semantics(
          container: true,
          button: true,
          hint: L10n.of(context).a11yChangesReminderTime,
          child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(26),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              padding:
                  const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: enabled
                      ? AppColors.gold.withValues(alpha: 0.5)
                      : AppColors.stroke,
                  width: enabled ? 1.2 : 1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    enabled
                        ? Icons.notifications_active_rounded
                        : Icons.notifications_off_outlined,
                    size: 20,
                    color: enabled
                        ? AppColors.goldBright
                        : AppColors.textSecondary,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    formatted,
                    style: t.headlineMedium?.copyWith(
                      fontSize: 40,
                      letterSpacing: -1.5,
                      color: enabled
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    enabled
                        ? L10n.of(context).everyDay
                        : L10n.of(context).tapToSet,
                    style: t.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 11.5,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
          ),
          ),
        ),
      ],
    );
  }
}

/// The scenery coming up under the closing pages.
class _Arrival extends StatelessWidget {
  final PageController controller;
  const _Arrival(this.controller);

  /// Nothing until page five, then up to nearly full by the last one —
  /// slow enough that no single swipe is the one that reveals it.
  static double _weight(double page) =>
      ((page - 4.6) / 2.4).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final decodeWidth =
        (media.size.width * media.devicePixelRatio * 1.1).round();
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final page = controller.hasClients &&
                controller.position.hasContentDimensions
            ? (controller.page ?? controller.initialPage.toDouble())
            : 0.0;
        final w = Curves.easeOut.transform(_weight(page));
        if (w <= 0.001) return const SizedBox.shrink();
        return Opacity(opacity: w * 0.9, child: child);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            CinematicHero.sceneForHour(DateTime.now().hour),
            fit: BoxFit.cover,
            cacheWidth: decodeWidth > 0 ? decodeWidth : null,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
          // Held further down than Home holds it: these pages are
          // still an argument, and the words have to win.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.bg.withValues(alpha: 0.80),
                  AppColors.bg.withValues(alpha: 0.48),
                  AppColors.bg.withValues(alpha: 0.88),
                ],
                stops: const [0.0, 0.44, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  final int count;
  final int index;
  const _Dots({required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
    // "Page 3 of 8", and said again as the page turns: the swipe is
    // silent, and the dots are the only thing on screen that says
    // where in the argument the reader is.
    return Semantics(
      container: true,
      liveRegion: true,
      label: L10n.of(context).a11yPageOf(index + 1, count),
      excludeSemantics: true,
      child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // The page you are on is a seal; the ones you are not are the
        // faint marks between seals in a margin.
        for (var i = 0; i < count; i++)
          TweenAnimationBuilder<double>(
            tween: Tween(end: i == index ? 1.0 : 0.0),
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: SizedBox(
                width: 10,
                height: 10,
                child: Center(
                  child: SealGlyph(
                    size: 4.5 + 5.5 * v,
                    color: Color.lerp(
                      AppColors.stroke,
                      AppColors.goldBright,
                      v,
                    )!,
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
