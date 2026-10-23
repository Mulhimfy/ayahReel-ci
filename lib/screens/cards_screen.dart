import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/card_compose.dart';
import '../data/card_deck.dart';
import '../data/card_library.dart';
import '../data/card_style.dart';
import '../data/dedication.dart';
import '../data/quran_verses.dart';
import '../data/settings_service.dart';
import '../data/surah_index.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import '../widgets/a11y.dart';
import '../widgets/ambient_motion.dart';
import '../widgets/app_toast.dart';
import '../widgets/illumination.dart';
import '../widgets/arena_history.dart';
import '../widgets/arena_portal.dart';
import '../widgets/nudge_dot.dart';
import '../widgets/scripture_finder.dart';
import 'card_studio_screen.dart';

/// The look a new card starts on, as last chosen.
CardTemplate get cardTemplateSetting =>
    CardTemplate.fromName(SettingsService.state.value.cardTemplate);

/// And the shape. Chosen in the composer, where the result of the
/// change is on screen, and remembered from there.
CardFormat get cardFormatSetting {
  final saved = SettingsService.state.value.cardFormat;
  return saved.isEmpty ? CardFormat.portrait : CardFormat.fromName(saved);
}

/// The ground a new card opens on: the template's paper, with a
/// scenery drawn at random laid over it — a different one every time,
/// so a card starts as a picture and not as the dark, and never waits
/// on a download for it (see [CardCompose.drawScene]). The user
/// changes it or takes it off like any other. Darkened a little more
/// than a chosen one, since nobody has looked at this photograph
/// behind these words yet. Before the catalog is in, the template's
/// own bundled scenery, as before.
CardBackground groundFor(CardTemplate template) {
  final drawn = CardCompose.drawScene();
  return CardBackground(
    paper: template.paper,
    sceneId: drawn.isNotEmpty ? drawn : CardCompose.sceneFor(template.sceneFamily),
    dim: drawn.isNotEmpty ? math.max(template.dim, 0.4) : template.dim,
  );
}

/// Quotes as a deck, in the look and shape the user last chose.
///
/// Top-level because two places make one: the Cards tab, and the
/// choice the home screen's verse offers. Two copies of this would be
/// two answers to "what does a new card look like".
CardDeck deckOfQuotes(BuildContext context, List<ScriptureQuote> quotes) {
  final template = cardTemplateSetting;
  final format = cardFormatSetting;
  final ground = groundFor(template);
  return CardDeck(
    id: newId(),
    format: format,
    slides: [
      for (final q in quotes)
        CardCompose.quote(
          id: newId(),
          text: q.text,
          translation: q.translation,
          reference: q.reference,
          format: format,
          template: template,
          background: ground,
          source: q.source,
          quran: q.quran,
        ),
    ],
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
}

/// One of the app's own daily verses as a deck of one.
///
/// Every word of it is bundled — the Arabic and all five translations
/// — so this cannot fail and cannot wait on a network.
CardDeck deckForVerse(BuildContext context, QuranVerse v) {
  final l = L10n.of(context);
  return deckOfQuotes(context, [
    ScriptureQuote(
      text: v.arabic,
      // An Arabic reader is reading the verse itself; a line under it
      // saying the same thing in Arabic is not a translation.
      translation: l.ar
          ? ''
          : v.translationIn(SettingsService.state.value.translation),
      reference:
          l.cardVerseReference(v.surahName, v.surah, v.startAyah, v.endAyah),
      source: CardSource.verse(v.surah, v.startAyah, v.endAyah),
      quran: true,
    ),
  ]);
}

/// Opens the composer on [deck]. [fresh] says the deck was just made,
/// on a scenery drawn for it rather than chosen.
Future<void> openCardStudio(BuildContext context, CardDeck deck,
    {bool write = false, bool fresh = false}) {
  HapticFeedback.selectionClick();
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => CardStudioScreen(
          deck: deck, writeImmediately: write, drawnScenery: fresh),
    ),
  );
}

/// The Cards tab: four ways in, and everything you have made.
///
/// The tab is deliberately not a composer. Making a card is a focused
/// screen pushed on top — the same arrangement reel creation has — so
/// nobody switches tabs with a half-written card behind them. What
/// lives here is the decision that comes first: where the words are
/// coming from, and what the card should look like.
class CardsScreen extends StatefulWidget {
  const CardsScreen({super.key});

  /// Asks the tab to show its cards rather than the quiz: bumped when
  /// Home's Create leads here for a card.
  static final ValueNotifier<int> cardsRequests = ValueNotifier(0);

  @override
  State<CardsScreen> createState() => _CardsScreenState();
}

class _CardsScreenState extends State<CardsScreen> {
  List<CardDeck>? _decks;

  /// Which of the tab's two sections is open: the arena, or the cards.
  bool _arena = false;

  @override
  void initState() {
    super.initState();
    _load();
    CardLibrary.revision.addListener(_load);
    CardsScreen.cardsRequests.addListener(_showCards);
    // The dot on the tab's glyph has done its work the moment somebody
    // looks. Fire and forget: a lost write costs one more sighting.
    final s = SettingsService.state.value;
    if (!s.cardsSeen) {
      unawaited(SettingsService.update(s.copyWith(cardsSeen: true)));
    }
  }

  @override
  void dispose() {
    CardLibrary.revision.removeListener(_load);
    CardsScreen.cardsRequests.removeListener(_showCards);
    super.dispose();
  }

  void _showCards() {
    if (mounted && _arena) setState(() => _arena = false);
  }

  Future<void> _load() async {
    final decks = await CardLibrary.load();
    if (mounted) setState(() => _decks = decks);
  }

  // ---- the four ways in --------------------------------------------

  Future<void> _fromScripture({required bool hadith}) async {
    final quotes = await showScriptureFinder(context, hadith: hadith);
    if (quotes == null || quotes.isEmpty || !mounted) return;
    _openStudio(_deckOf(quotes), fresh: true);
  }

  /// The verse the home screen is carrying, straight onto a card. Every
  /// word of it is bundled — the Arabic and all five translations — so
  /// this is the one way in that cannot fail and cannot wait.
  void _fromToday() => _openStudio(
      deckForVerse(context, QuranVerses.at(DateTime.now())),
      fresh: true);

  void _blank() {
    final template = cardTemplateSetting;
    _openStudio(
      CardCompose.deck(
        CardSlide(
          id: newId(),
          background: groundFor(template),
          frame: template.frame,
          frameArgb: template.paper.accentArgb,
        ),
        format: cardFormatSetting,
      ),
      write: true,
      fresh: true,
    );
  }

  /// A quote — or several — as a deck, in the look and shape the user
  /// last chose.
  CardDeck _deckOf(List<ScriptureQuote> quotes) =>
      deckOfQuotes(context, quotes);

  Future<void> _openStudio(CardDeck deck,
      {bool write = false, bool fresh = false}) async {
    HapticFeedback.selectionClick();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CardStudioScreen(
            deck: deck, writeImmediately: write, drawnScenery: fresh),
      ),
    );
    _load();
  }

  Future<void> _deckMenu(CardDeck deck) async {
    HapticFeedback.selectionClick();
    final l = L10n.of(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheet) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            ListTile(
              leading: const Icon(Icons.copy_rounded,
                  size: 19, color: AppColors.gold),
              title: Text(l.cardsDuplicate,
                  style: const TextStyle(
                      fontSize: 14, color: AppColors.textPrimary)),
              onTap: () => Navigator.of(sheet).pop('copy'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  size: 19, color: AppColors.gold),
              title: Text(l.cardsDelete,
                  style: const TextStyle(
                      fontSize: 14, color: AppColors.textPrimary)),
              onTap: () => Navigator.of(sheet).pop('delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'delete') {
      await CardLibrary.remove(deck.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(toast(l.cardsDeleted, tone: ToastTone.done));
      return;
    }
    // A copy is a new deck with new ids all the way down, so editing
    // it cannot reach into the one it came from.
    final copy = CardDeck.fromJson(deck.toJson())
        .copyWith(updatedAt: DateTime.now());
    _openStudio(CardDeck(
      id: newId(),
      format: copy.format,
      slides: [
        for (final s in copy.slides)
          CardSlide.fromJson({...s.toJson(), 'id': newId()}),
      ],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    final motion = AmbientScope.maybeOf(context);
    final decks = _decks;
    final body = SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(22, 26, 22, 0),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                A11yHeader(child: Text(l.cardsTitle, style: t.headlineMedium)),
                const SizedBox(height: 8),
                const Row(
                  children: [
                    Expanded(child: OrnamentHairline(towardsEnd: true)),
                    SizedBox(width: 8),
                    SealGlyph(size: 7, color: Color(0x99D4A947)),
                  ],
                ),
                const SizedBox(height: 12),
                const SizedBox(height: 14),
                _SectionSwitch(
                  arena: _arena,
                  onChange: (v) {
                    HapticFeedback.selectionClick();
                    setState(() => _arena = v);
                  },
                ),
                const SizedBox(height: 18),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 360),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, a) => FadeTransition(
                    opacity: a,
                    child: SlideTransition(
                      position: Tween(
                        begin: const Offset(0, 0.03),
                        end: Offset.zero,
                      ).animate(a),
                      child: child,
                    ),
                  ),
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.topCenter,
                    children: [...previous, if (current != null) current],
                  ),
                  child: _arena
                      ? const _ArenaSection(key: ValueKey('arena'))
                      : Column(
                          key: const ValueKey('cards'),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l.cardsBlurb,
                                style: t.bodyMedium?.copyWith(height: 1.5)),
                            const SizedBox(height: 18),
                            _Starts(
                              onVerse: () => _fromScripture(hadith: false),
                              onHadith: () => _fromScripture(hadith: true),
                              onToday: _fromToday,
                              onBlank: _blank,
                            ),
                            const SizedBox(height: 24),
                            if (decks != null && decks.isNotEmpty) ...[
                              A11yHeader(
                                child: Text(l.cardsYours,
                                    style: t.titleMedium
                                        ?.copyWith(fontSize: 15)),
                              ),
                              const SizedBox(height: 12),
                            ],
                          ],
                        ),
                ),
              ]),
            ),
          ),
          if (_arena)
            const SliverToBoxAdapter(child: SizedBox.shrink())
          else if (decks == null)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(
                    child: CircularProgressIndicator(color: AppColors.gold)),
              ),
            )
          else if (decks.isEmpty)
            SliverToBoxAdapter(child: _Empty(style: t))
          else
            SliverToBoxAdapter(
              // A shelf rather than a grid: a deck is a wide thing and
              // a shelf shows it whole, the way the templates above it
              // are shown. It also keeps the four ways in on screen —
              // a grid pushed them off the top the moment somebody had
              // made a few.
              child: SizedBox(
                height: _DeckCard.height + 34,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
                  itemCount: decks.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, i) => _DeckCard(
                    // Identity, not position: the shelf is
                    // newest-first, so every export shifts each card
                    // along one and an unkeyed row would hand each
                    // card's state to the deck that replaced it.
                    key: ValueKey(decks[i].id),
                    deck: decks[i],
                    onTap: () => _openStudio(decks[i]),
                    onHold: () => _deckMenu(decks[i]),
                  ),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 128)),
        ],
      ),
    );
    if (motion == null) return body;
    // Scrolling this tab pushes the shell's sky exactly as the others
    // do, so the room is one room.
    return AmbientScrollSensor(motion: motion, child: body);
  }
}

/// The four ways to start a card. A grid rather than a list: these are
/// the whole of what this tab asks, and asking it in two rows means
/// none of it is below the fold on any phone.
class _Starts extends StatelessWidget {
  final VoidCallback onVerse;
  final VoidCallback onHadith;
  final VoidCallback onToday;
  final VoidCallback onBlank;

  const _Starts({
    required this.onVerse,
    required this.onHadith,
    required this.onToday,
    required this.onBlank,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Column(
      children: [
        Row(children: [
          Expanded(
            child: _Start(
              icon: Icons.menu_book_rounded,
              label: l.cardsFromVerse,
              gold: true,
              onTap: onVerse,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _Start(
              icon: Icons.format_quote_rounded,
              label: l.cardsFromHadith,
              gold: true,
              onTap: onHadith,
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: _Start(
              icon: Icons.today_rounded,
              label: l.cardsTodaysVerse,
              onTap: onToday,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _Start(
              icon: Icons.edit_outlined,
              label: l.cardsBlank,
              onTap: onBlank,
            ),
          ),
        ]),
      ],
    );
  }
}

class _Start extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool gold;
  final VoidCallback onTap;

  const _Start({
    required this.icon,
    required this.label,
    required this.onTap,
    this.gold = false,
  });

  @override
  Widget build(BuildContext context) {
    return A11yTap(
      label: label,
      hint: L10n.of(context).a11yOpensCard,
      onTap: onTap,
      child: Pressable(
        onTap: onTap,
        child: Container(
          height: 62,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: gold ? 0.86 : 0.7),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: gold
                  ? AppColors.gold.withValues(alpha: 0.42)
                  : AppColors.stroke,
            ),
          ),
          child: Row(
            children: [
              Icon(icon,
                  size: 18,
                  color: gold ? AppColors.goldBright : AppColors.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.25,
                    fontWeight: gold ? FontWeight.w700 : FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One saved deck: its cover, what it quotes, and how many cards it
/// holds.
class _DeckCard extends StatelessWidget {
  final CardDeck deck;
  final VoidCallback onTap;
  final VoidCallback onHold;

  /// How tall a deck stands on the shelf. Its width follows from the
  /// shape it was made in, so a story and a square sit side by side as
  /// what they are.
  static const height = 196.0;

  const _DeckCard({
    super.key,
    required this.deck,
    required this.onTap,
    required this.onHold,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final caption = _caption(l);
    final dedication = deck.dedication.isEmpty
        ? ''
        : ' ${l.dedicationLine(deck.dedication.kind, deck.dedication.name)}.';
    return A11yTap(
      label: '$caption.$dedication ${l.cardCount(deck.slides.length)}',
      hint: l.a11yOpensCard,
      onTap: onTap,
      onLongPress: onHold,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onHold,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: height,
              width: height * deck.format.aspect,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: deck.slides.first.background.groundColours,
                        ),
                      ),
                    ),
                    FutureBuilder<File>(
                      future: CardLibrary.coverFile(deck.id),
                      builder: (context, snap) {
                        final f = snap.data;
                        if (f == null || !f.existsSync()) {
                          return const SizedBox.shrink();
                        }
                        return Image.file(
                          f,
                          fit: BoxFit.cover,
                          // The cover is re-rendered under the same
                          // name every time the deck is saved, and
                          // Flutter caches a file image by its path:
                          // without this the shelf would show the
                          // first cover a deck ever had, for good.
                          key: ValueKey('${deck.id}-${deck.updatedAt}'),
                          errorBuilder: (_, __, ___) =>
                              const SizedBox.shrink(),
                        );
                      },
                    ),
                    if (deck.dedication.isNotEmpty)
                      PositionedDirectional(
                        top: 6,
                        start: 6,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Icon(
                            deck.dedication.kind == DedicationKind.sadaqah
                                ? Icons.all_inclusive_rounded
                                : Icons.card_giftcard_rounded,
                            size: 11,
                            color: AppColors.goldBright,
                          ),
                        ),
                      ),
                    if (deck.slides.length > 1)
                      PositionedDirectional(
                        top: 6,
                        end: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${deck.slides.length}',
                            style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.white),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 7),
            SizedBox(
              width: height * deck.format.aspect,
              child: Text(
                caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 11.5, color: AppColors.textPrimary),
              ),
            ),
            Text(
              l.formatDate(deck.updatedAt),
              style: const TextStyle(
                  fontSize: 10.5, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  /// What the deck is called: what it quotes, if it quotes anything,
  /// and its own first words if not.
  String _caption(L10n l) {
    final source = deck.source;
    if (source.isVerse && source.surah >= 1 && source.surah <= 114) {
      return l.cardVerseReference(surahIndex[source.surah - 1].nameEnglish,
          source.surah, source.startAyah, source.endAyah);
    }
    if (source.isHadith) {
      return l.hadithReference(source.collection, source.number);
    }
    final words = deck.caption;
    return words.isEmpty ? l.cardsNew : words;
  }
}

class _Empty extends StatelessWidget {
  final TextTheme style;
  const _Empty({required this.style});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 60),
      child: Column(
        children: [
          const SealGlyph(size: 16, color: Color(0x66D4A947)),
          const SizedBox(height: 14),
          Text(l.cardsEmptyTitle,
              style: style.titleMedium?.copyWith(fontSize: 15)),
          const SizedBox(height: 6),
          Text(
            l.cardsEmptyBody,
            textAlign: TextAlign.center,
            style: style.bodySmall?.copyWith(
                color: AppColors.textSecondary, fontSize: 12.5, height: 1.5),
          ),
        ],
      ),
    );
  }
}


/// Which of the tab's two rooms is open: a pair of cartouches, the
/// open one lit, with a dot on the arena's until it has been visited.
class _SectionSwitch extends StatelessWidget {
  final bool arena;
  final ValueChanged<bool> onChange;
  const _SectionSwitch({required this.arena, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    Widget seg(String label, bool on, VoidCallback tap, {bool dot = false}) =>
        Expanded(
          child: A11yTap(
            label: dot ? '$label${l.comma} ${l.a11yNew}' : label,
            selected: on,
            onTap: tap,
            child: Pressable(
              onTap: tap,
              scale: 0.97,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: on
                          ? AppColors.gold.withValues(alpha: 0.16)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: on
                            ? AppColors.gold.withValues(alpha: 0.7)
                            : Colors.transparent,
                      ),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: on ? FontWeight.w700 : FontWeight.w600,
                        color: on ? AppColors.goldBright : AppColors.textSecondary,
                      ),
                    ),
                  ),
                  PositionedDirectional(
                    top: 6,
                    end: 10,
                    child: NudgeDot(on: dot, size: 6),
                  ),
                ],
              ),
            ),
          ),
        );
    return ValueListenableBuilder<AppSettings>(
      valueListenable: SettingsService.state,
      builder: (context, s, _) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.stroke),
        ),
        child: Row(
          children: [
            seg(l.navCards, !arena, () => onChange(false)),
            const SizedBox(width: 4),
            seg(l.arenaTitle, arena, () => onChange(true), dot: !s.arenaSeen),
          ],
        ),
      ),
    );
  }
}

/// The arena's room on the Cards tab: the pitch, the door to the lobby,
/// and the rounds already played.
class _ArenaSection extends StatelessWidget {
  const _ArenaSection({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ArenaPitch(centered: false),
        const SizedBox(height: 18),
        const ArenaPortal(),
        const SizedBox(height: 26),
        A11yHeader(
          child: Text(l.arenaRecent,
              style: t.titleMedium?.copyWith(fontSize: 15)),
        ),
        const SizedBox(height: 12),
        const ArenaHistoryStrip(limit: 12),
      ],
    );
  }
}
