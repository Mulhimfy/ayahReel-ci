import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/card_deck.dart';
import '../data/hadith_library.dart';
import '../data/models.dart';
import '../data/quran_search.dart';
import '../data/quran_text_service.dart';
import '../data/settings_service.dart';
import '../data/surah_index.dart';
import '../data/verse_translation.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import 'a11y.dart';
import 'illumination.dart';
import 'surah_picker_sheet.dart';

/// One piece of text on its way to a card: what it says, what it says
/// in the reader's language, where it is from.
///
/// The finder always returns a list. One quotation is a list of one,
/// and a passage the user asked to break up is a list of several — so
/// the composer has a single path from "found some words" to "made a
/// card", whether it ends in one card or in a carousel.
class ScriptureQuote {
  final String text;
  final String translation;
  final String reference;
  final CardSource source;

  /// Whether the text is the Quran's own, which is what decides
  /// whether a face cut for the mushaf may set it.
  final bool quran;

  const ScriptureQuote({
    required this.text,
    this.translation = '',
    this.reference = '',
    this.source = CardSource.own,
    this.quran = false,
  });
}

/// Opens the finder and returns what the user chose, or null.
Future<List<ScriptureQuote>?> showScriptureFinder(
  BuildContext context, {
  bool hadith = false,
}) {
  return showModalBottomSheet<List<ScriptureQuote>>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => ScriptureFinder(startOnHadith: hadith),
  );
}

/// Searching the Quran and the hadith library, and choosing what of a
/// result actually goes on the card.
///
/// Two halves, one sheet. The top half finds; the bottom half is
/// where a result is turned into a quotation — because "put this on a
/// card" is almost never the whole of a hadith with its chain, and
/// often not the whole of a long verse either. The piece picker is the
/// one unusual thing here and the reason the whole sheet exists: tap
/// the first word, tap the last, and what lies between them is what
/// travels.
class ScriptureFinder extends StatefulWidget {
  final bool startOnHadith;

  const ScriptureFinder({super.key, this.startOnHadith = false});

  @override
  State<ScriptureFinder> createState() => _ScriptureFinderState();
}

class _ScriptureFinderState extends State<ScriptureFinder> {
  late bool _hadith = widget.startOnHadith;
  final _controller = TextEditingController();

  /// The search in flight, so a keystroke arriving mid-search cannot
  /// be overtaken by the older answer.
  int _searchGeneration = 0;

  /// The surah read in flight, counted apart from the searches: one
  /// shared counter let a keystroke discard a surah still loading (a
  /// spinner forever) and a surah pick discard a search (stuck on
  /// "searching").
  int _surahGeneration = 0;

  List<Hadith> _hadiths = const [];
  bool _searching = false;
  bool _loadingLibrary = false;

  /// The surah the Quran side is showing, its verses, and the one the
  /// search asked for.
  ///
  /// The Quran half of this sheet is a *reader*, not a search box, and
  /// that is a correction: a search box over the Quran can only match
  /// the Arabic — the text is bundled, the translations are not — so
  /// anybody typing "mercy" into it got nothing at all and concluded,
  /// correctly, that it did not work. The reels have always asked for
  /// a surah first, through a picker that searches names, numbers and
  /// references in either script, and then shown its verses to read.
  /// This is that picker and that list, which also means one
  /// implementation of the searching rather than a second, worse one.
  int _surah = 1;
  List<Ayah>? _ayahs;
  int? _focus;

  /// Where they were last time, remembered across launches — see
  /// [AppSettings.lastSurah].
  void _remember(int surah, int ayah) {
    final st = SettingsService.state.value;
    if (st.lastSurah == surah && st.lastAyah == ayah) return;
    unawaited(SettingsService.update(
        st.copyWith(lastSurah: surah, lastAyah: ayah)));
  }
  bool _translated = true;

  /// Verses the words matched, and the query they were found for.
  ///
  /// The Quran half used to have no search box at all — a surah
  /// picker behind a "Change" button, and the picker's own field is
  /// where the words went. Somebody looking for "mercy" in the Cards
  /// tab therefore had nothing to type into, which is indistinguishable
  /// from a search that does not work. The box is here now, and it
  /// searches whichever half of the verse the query is written in:
  /// Arabic against the bundled text, anything else against the
  /// translation.
  List<VerseHit> _verseHits = const [];
  String _hitsFor = '';

  /// What the user is looking at right now, if they have opened a
  /// result. Null while the list is showing.
  _Opened? _open;

  /// Debounce: a search over six thousand hadith is cheap, but running
  /// it on every keystroke of a five-letter word is five times the
  /// work for the same answer.
  Timer? _debounce;

  /// The verse list's own controller, and the row of the verse the
  /// search named. Both live as long as the sheet does: a controller
  /// built inside [build] is a new controller every frame, which can
  /// only ever park the list once, on the frame it happened to be
  /// created.
  final _verseScroll = ScrollController();
  GlobalKey? _focusKey;

  @override
  void initState() {
    super.initState();
    // Where they were, not where the Quran starts. A reader that opens
    // on Al-Fatiha 1 every time makes somebody working through a surah
    // find their place again by hand, every single card. Set before
    // the Hadith return too, so switching to Quran from there opens
    // on their surah rather than on Al-Fatiha.
    final st = SettingsService.state.value;
    _surah = st.lastSurah >= 1 && st.lastSurah <= 114 ? st.lastSurah : 1;
    if (_hadith) {
      _ensureLibrary();
      return;
    }
    _loadSurah(_surah, focus: st.lastAyah >= 1 ? st.lastAyah : null);
  }

  /// Reads a surah for the list: the Arabic and the translation the
  /// reader has chosen, exactly as the reel flow reads it.
  ///
  /// A surah is one fetch, cached to disk forever after — and when
  /// there is no network to make it, the Arabic still comes off the
  /// bundled search index, so every verse of the Quran can be put on a
  /// card offline. Only the line under it needs a connection.
  Future<void> _loadSurah(int surah, {int? focus}) async {
    setState(() {
      _surah = surah;
      _focus = focus;
      _focusKey = focus == null ? null : GlobalKey();
      _ayahs = null;
      _translated = true;
    });
    final gen = ++_surahGeneration;
    try {
      final ayahs = await QuranTextService.load(surah);
      if (!mounted || gen != _surahGeneration) return;
      setState(() => _ayahs = ayahs);
    } catch (_) {
      final arabic = await QuranSearch.surah(surah);
      if (!mounted || gen != _surahGeneration) return;
      setState(() {
        _translated = false;
        _ayahs = [
          for (var i = 0; i < arabic.length; i++)
            Ayah(number: i + 1, arabic: arabic[i], translation: ''),
        ];
      });
    }
    if (gen == _surahGeneration) unawaited(_revealFocus(gen));
  }

  /// Scrolls the reader to the verse the search named.
  ///
  /// A surah is up to 286 verses and they are nothing like the same
  /// height — a one-line ayah and a ten-line one sit in the same list
  /// — so there is no offset to compute. What used to be here was a
  /// flat 150 pixels a verse, which on anything past the first page
  /// was off by whole screens and on Al-Baqarah asked for an offset
  /// past the end of the list, landing the reader at the bottom of the
  /// surah instead of at their verse.
  ///
  /// This converges instead. Each pass jumps to where the list's own
  /// estimate says the verse is; that jump builds the rows around it,
  /// which sharpens the estimate, and as soon as the row itself exists
  /// [Scrollable.ensureVisible] finishes the job exactly. Four or five
  /// passes is all it takes, and the loop is bounded either way.
  Future<void> _revealFocus(int gen) async {
    final focus = _focus;
    final key = _focusKey;
    if (focus == null || key == null) return;
    for (var pass = 0; pass < 12; pass++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || gen != _surahGeneration || _focus != focus) return;
      final ctx = key.currentContext;
      if (ctx != null && ctx.mounted) {
        // A little below the top edge, so the verse reads as the
        // answer rather than as the thing that got cut off.
        await Scrollable.ensureVisible(ctx,
            alignment: 0.12, duration: const Duration(milliseconds: 240));
        return;
      }
      if (!_verseScroll.hasClients) continue;
      final pos = _verseScroll.position;
      final total = _ayahs?.length ?? 0;
      if (total == 0 || pos.maxScrollExtent <= 0) continue;
      final want =
          (pos.maxScrollExtent * (focus - 1) / total).clamp(0.0, pos.maxScrollExtent);
      if ((want - pos.pixels).abs() < 1) continue;
      pos.jumpTo(want);
    }
  }

  /// The reels' own surah picker: names in either script, numbers, and
  /// references like "2:255" or "baqarah 255" — and a few Arabic words
  /// find the verses that carry them, listed under the surahs.
  Future<void> _pickSurah() async {
    final pick = await showSurahPicker(context);
    if (pick == null || !mounted) return;
    _remember(pick.number, pick.ayah ?? 0);
    await _loadSurah(pick.number, focus: pick.ayah);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _verseScroll.dispose();
    super.dispose();
  }

  Future<void> _ensureLibrary() async {
    // Always ask the library: load() costs nothing when the edition in
    // memory is the chosen one, and otherwise swaps in the new
    // language. Returning on isLoaded (true for any edition) left a
    // reader who changed translation reading hadith in the old one.
    // The spinner is only for when there is nothing to show meanwhile.
    final empty = !HadithLibrary.isLoaded;
    if (empty) setState(() => _loadingLibrary = true);
    await HadithLibrary.load();
    if (!mounted) return;
    if (empty) setState(() => _loadingLibrary = false);
    if (_controller.text.isNotEmpty) _search(_controller.text);
  }

  void _onTyped(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), () => _search(q));
  }

  Future<void> _search(String query) async {
    final gen = ++_searchGeneration;
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _hadiths = const [];
        _verseHits = const [];
        _hitsFor = '';
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    if (!_hadith) {
      final hits = await _versesMatching(q);
      if (!mounted || gen != _searchGeneration) return;
      setState(() {
        _verseHits = hits;
        _hitsFor = q;
        _searching = false;
      });
      return;
    }
    final hits = HadithLibrary.search(q);
    if (!mounted || gen != _searchGeneration) return;
    setState(() {
      _hadiths = hits;
      _searching = false;
    });
  }

  /// Verses carrying [q]: the bundled Arabic text when that is what
  /// was typed, and otherwise the translation the reader has chosen.
  ///
  /// The script decides, not the app's language and not the keyboard —
  /// somebody reading the interface in English still types Arabic to
  /// find an Arabic phrase, and the query is the only honest signal.
  Future<List<VerseHit>> _versesMatching(String q) {
    if (RegExp('[؀-ۿ]').hasMatch(q)) {
      return QuranSearch.letterCount(q) < 2
          ? Future.value(const [])
          : QuranSearch.search(q);
    }
    if (q.length < 3) return Future.value(const []);
    return QuranSearch.searchTranslation(
      q,
      resourceId: SettingsService.state.value.translation.resourceId,
    );
  }

  /// A verse a search turned up, opened to be put on a card.
  ///
  /// The surah is read first so the card gets the real translation
  /// rather than the snippet the search answered with — it is one
  /// fetch, cached, and the same one the reader below makes. When
  /// there is no network the hit's own lines are what there is.
  Future<void> _openHit(VerseHit hit) async {
    HapticFeedback.selectionClick();
    final l = L10n.of(context);
    final info = surahIndex[hit.surah - 1];
    var text = hit.text;
    var translation = hit.translation;
    try {
      final ayahs = await QuranTextService.load(hit.surah);
      if (hit.ayah <= ayahs.length) {
        text = ayahs[hit.ayah - 1].arabic;
        translation = ayahs[hit.ayah - 1].translation;
      }
    } catch (_) {/* the hit's own lines will do */}
    if (!mounted) return;
    _remember(hit.surah, hit.ayah);
    setState(() {
      _open = _Opened(
        text: text,
        translation: translation,
        reference: l.cardVerseReference(
            info.nameEnglish, hit.surah, hit.ayah, hit.ayah),
        source: CardSource.verse(hit.surah, hit.ayah, hit.ayah),
        quran: true,
      );
    });
  }

  void _openVerse(Ayah ayah) {
    final info = surahIndex[_surah - 1];
    HapticFeedback.selectionClick();
    _remember(_surah, ayah.number);
    setState(() {
      _open = _Opened(
        text: ayah.arabic,
        translation: ayah.translation,
        reference: L10n.of(context).cardVerseReference(
            info.nameEnglish, _surah, ayah.number, ayah.number),
        source: CardSource.verse(_surah, ayah.number, ayah.number),
        quran: true,
      );
    });
  }

  void _openHadith(Hadith h) {
    HapticFeedback.selectionClick();
    final l = L10n.of(context);
    setState(() {
      _open = _Opened(
        // The finder opens on the saying itself rather than on the
        // chain in front of it — that is what somebody is quoting —
        // and "All of it" is one tap away.
        text: HadithLibrary.quotable(h.arabic),
        whole: h.arabic,
        translation: HadithLibrary.quotable(h.translation),
        wholeTranslation: h.translation,
        reference: l.hadithReference(h.collection, h.number),
        grading: h.grading,
        source: CardSource.hadith(h.collection, h.number),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final open = _open;
    return Padding(
      // The keyboard: the sheet rides above it rather than under it.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.86,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.stroke,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            if (open == null) ...[
              _header(l),
              Expanded(child: _results(l)),
            ] else
              Expanded(
                child: _Compose(
                  opened: open,
                  onBack: () => setState(() => _open = null),
                  onDone: (quotes) => Navigator.of(context).pop(quotes),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _header(L10n l) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          A11yHeader(child: Text(l.findTitle, style: t.titleMedium)),
          const SizedBox(height: 12),
          Row(
            children: [
              _Segment(
                label: l.findQuran,
                selected: !_hadith,
                onTap: () {
                  if (_hadith) {
                    setState(() => _hadith = false);
                    if (_ayahs == null) _loadSurah(_surah);
                    // What is typed was answered from hadith; ask
                    // again of the Quran, as the Hadith tab does.
                    _search(_controller.text);
                  }
                },
              ),
              const SizedBox(width: 8),
              _Segment(
                label: l.findHadith,
                selected: _hadith,
                onTap: () {
                  if (_hadith) return;
                  setState(() => _hadith = true);
                  _ensureLibrary();
                  _search(_controller.text);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!_hadith) ...[
            _surahRow(l),
            const SizedBox(height: 10),
          ],
          _searchField(l),
        ],
      ),
    );
  }

  /// Which surah is open, and the one control that changes it.
  Widget _surahRow(L10n l) {
    final info = surahIndex[_surah - 1];
    final name = l.localizedSurahName(info.nameEnglish);
    return A11yTap(
      label: '$name. ${l.a11ySurahCount(info.ayahCount)}',
      hint: l.a11yOpensSurahPicker,
      onTap: _pickSurah,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _pickSurah,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
          decoration: BoxDecoration(
            color: AppColors.gold.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: AppColors.gold.withValues(alpha: 0.38)),
          ),
          child: Row(
            children: [
              Text('$_surah',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.goldBright)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary),
                ),
              ),
              const SizedBox(width: 8),
              Text(l.findChooseSurah,
                  style: const TextStyle(
                      fontSize: 11.5, color: AppColors.textSecondary)),
              const Icon(Icons.expand_more_rounded,
                  size: 16, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchField(L10n l) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
            controller: _controller,
            onChanged: _onTyped,
            // The hadith half is a search and nothing else, so it
            // takes the keyboard on the way in. The Quran half opens
            // on a surah to read, which the keyboard would cover.
            autofocus: _hadith,
            textInputAction: TextInputAction.search,
            style: t.bodyMedium?.copyWith(color: AppColors.textPrimary),
            decoration: InputDecoration(
              isDense: true,
              hintText: _hadith ? l.findHadithHint : l.findVerseHint,
              prefixIcon: const Icon(Icons.search_rounded,
                  size: 18, color: AppColors.textSecondary),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      color: AppColors.textSecondary,
                      onPressed: () {
                        _controller.clear();
                        _search('');
                      },
                    ),
              filled: true,
              fillColor: AppColors.bg.withValues(alpha: 0.6),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.stroke),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.gold),
              ),
            ),
          ),
      ],
    );
  }

  Widget _results(L10n l) {
    final t = Theme.of(context).textTheme;
    if (!_hadith) {
      final typed = _controller.text.trim();
      if (typed.isEmpty) return _verseList(l);
      if (_searching) return _Note(text: l.findOpening, spinner: true, style: t);
      final hits = _hitsFor == typed ? _verseHits : const <VerseHit>[];
      if (hits.isEmpty) {
        return _Note(
          text: typed.length < 3 ? l.findTypeMore : l.findNothing,
          style: t,
        );
      }
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
        itemCount: hits.length,
        separatorBuilder: (_, __) => const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: OrnamentHairline(towardsEnd: true),
        ),
        itemBuilder: (context, i) =>
            _HitRow(hit: hits[i], onTap: () => _openHit(hits[i])),
      );
    }
    if (_loadingLibrary) {
      return _Note(text: l.findOpening, spinner: true, style: t);
    }
    if (_controller.text.trim().isEmpty) return _topics(l);
    if (_searching) {
      return _Note(text: l.findOpening, spinner: true, style: t);
    }
    if (_hadiths.isEmpty) {
      return _Note(
        text: _controller.text.trim().length < 3
            ? l.findTypeMore
            : l.findNothing,
        style: t,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
      itemCount: _hadiths.length,
      separatorBuilder: (_, __) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: OrnamentHairline(towardsEnd: true),
      ),
      itemBuilder: (context, i) => _HadithRow(
          hadith: _hadiths[i], onTap: () => _openHadith(_hadiths[i])),
    );
  }

  /// Every verse of the open surah, to read and to choose from.
  Widget _verseList(L10n l) {
    final ayahs = _ayahs;
    final t = Theme.of(context).textTheme;
    if (ayahs == null) {
      return _Note(text: l.findOpening, spinner: true, style: t);
    }
    return ListView.separated(
      // The search can name a verse, and a surah is up to 286 of them:
      // opening on the one that was asked for is the difference
      // between an answer and a haystack. See [_revealFocus].
      controller: _verseScroll,
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
      itemCount: ayahs.length + (_translated ? 0 : 1),
      separatorBuilder: (_, __) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: OrnamentHairline(towardsEnd: true),
      ),
      itemBuilder: (context, i) {
        if (!_translated && i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              l.findArabicOnly,
              style: t.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 11.5,
                  height: 1.5),
            ),
          );
        }
        final ayah = ayahs[i - (_translated ? 0 : 1)];
        final focused = ayah.number == _focus;
        return _AyahRow(
          key: focused ? _focusKey : null,
          surah: _surah,
          ayah: ayah,
          highlighted: focused,
          onTap: () => _openVerse(ayah),
        );
      },
    );
  }

  /// What the hadith side shows before anything is typed: the topics
  /// the library is filed under. Somebody making a card rarely arrives
  /// with a phrase — they arrive wanting "something about mercy".
  Widget _topics(L10n l) {
    final topics = HadithLibrary.topics;
    if (topics.isEmpty) {
      return _Note(text: l.findHadithHint, style: Theme.of(context).textTheme);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.findBrowse,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final id in topics)
                A11yTap(
                  label: l.hadithTopicName(id),
                  onTap: () => setState(() {
                    _hadiths = HadithLibrary.byTopic(id);
                    _controller.text = l.hadithTopicName(id);
                  }),
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _hadiths = HadithLibrary.byTopic(id);
                      _controller.text = l.hadithTopicName(id);
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 13, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.gold.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: AppColors.gold.withValues(alpha: 0.28)),
                      ),
                      child: Text(
                        l.hadithTopicName(id),
                        style: const TextStyle(
                            fontSize: 12.5, color: AppColors.textPrimary),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            l.findCredit(HadithLibrary.credit),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary, fontSize: 11, height: 1.5),
          ),
        ],
      ),
    );
  }
}

/// A result the user has opened, and the state of turning it into a
/// quotation. Mutable on purpose: the translation of a verse arrives
/// after the sheet has already drawn it.
/// The direction of the line under the Arabic: its edition's, not
/// the app's. English under an Arabic interface, or Urdu under an
/// English one, otherwise runs the wrong way and its full stop lands
/// at the wrong end of the line.
TextDirection _quranTranslationDirection() =>
    SettingsService.state.value.translation.direction;

/// The same for a hadith, whose translation is in whichever edition
/// the library loaded (English for a German reader).
TextDirection _hadithTranslationDirection() =>
    VerseTranslation.fromCode(HadithLibrary.lang).direction;

class _Opened {
  _Opened({
    required this.text,
    String? whole,
    this.translation = '',
    String? wholeTranslation,
    required this.reference,
    required this.source,
    this.grading = '',
    this.quran = false,
  })  : whole = whole ?? text,
        wholeTranslation = wholeTranslation ?? translation;

  /// What is offered first — the saying, for a hadith whose chain the
  /// edition marks off; the verse itself, for a verse.
  final String text;

  /// Everything, chain and all.
  final String whole;

  String translation;
  String wholeTranslation;
  bool translationFailed = false;

  final String reference;
  final String grading;
  final CardSource source;
  final bool quran;
}

/// The second half of the sheet: what of this result goes on the card.
class _Compose extends StatefulWidget {
  final _Opened opened;
  final VoidCallback onBack;
  final ValueChanged<List<ScriptureQuote>> onDone;

  const _Compose({
    required this.opened,
    required this.onBack,
    required this.onDone,
  });

  @override
  State<_Compose> createState() => _ComposeState();
}

class _ComposeState extends State<_Compose> {
  /// Whole text, or a run of words out of it.
  bool _part = false;

  /// The chosen run, as word indices into [_words]; null until the
  /// first word is tapped.
  int? _from;
  int? _to;

  bool _withTranslation = true;
  bool _withReference = true;

  /// The text the picker is working on: the saying, or the whole
  /// thing with its chain.
  bool _whole = false;

  String get _source => _whole ? widget.opened.whole : widget.opened.text;

  List<String> get _words =>
      _source.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

  String get _chosen {
    if (!_part || _from == null) return _source;
    final words = _words;
    final a = _from!;
    final b = _to ?? _from!;
    return words.sublist(a < b ? a : b, (a < b ? b : a) + 1).join(' ');
  }

  void _tapWord(int i) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_from == null || _to != null) {
        _from = i;
        _to = null;
      } else {
        _to = i;
      }
    });
  }

  void _done() {
    final o = widget.opened;
    final translation = _whole ? o.wholeTranslation : o.translation;
    widget.onDone([
      ScriptureQuote(
        text: _chosen,
        // A translation only travels with the whole quotation: a run
        // of five words out of a verse has no matching run in the
        // English, and cutting one to fit would be inventing it.
        translation: _withTranslation && !_part ? translation : '',
        reference: _withReference ? o.reference : '',
        source: o.source,
        quran: o.quran,
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final t = Theme.of(context).textTheme;
    final o = widget.opened;
    final rtl = CardTextBlock.rtlText(_source);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 18, 0),
          child: Row(
            children: [
              A11yTap(
                label: l.back,
                onTap: widget.onBack,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, size: 20),
                  color: AppColors.textSecondary,
                  onPressed: widget.onBack,
                ),
              ),
              Expanded(
                child: Text(o.reference,
                    style: t.bodySmall?.copyWith(
                        color: AppColors.goldBright, fontSize: 12.5)),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
            children: [
              // The two ways to take it. "Part of it" turns the text
              // below into something you tap rather than something you
              // read, which is the whole of the instruction.
              Row(
                children: [
                  _Segment(
                    label: l.findWhole,
                    selected: !_part,
                    onTap: () => setState(() => _part = false),
                  ),
                  const SizedBox(width: 8),
                  _Segment(
                    label: l.findPart,
                    selected: _part,
                    onTap: () => setState(() {
                      _part = true;
                      _from = null;
                      _to = null;
                    }),
                  ),
                ],
              ),
              if (_part) ...[
                const SizedBox(height: 8),
                Text(l.findPartHint,
                    style: t.bodySmall?.copyWith(
                        color: AppColors.textSecondary, fontSize: 11.5)),
              ],
              const SizedBox(height: 14),
              Directionality(
                textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                child: _part ? _wordPicker(rtl) : _plain(rtl),
              ),
              if (o.whole != o.text) ...[
                const SizedBox(height: 12),
                _Toggle(
                  label: l.findWhole,
                  value: _whole,
                  onChanged: (v) => setState(() {
                    _whole = v;
                    _from = null;
                    _to = null;
                  }),
                ),
              ],
              if (o.grading.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(l.findGrading(o.grading),
                    style: t.bodySmall?.copyWith(
                        color: AppColors.textSecondary, fontSize: 11.5)),
              ],
              const SizedBox(height: 14),
              const OrnamentHairline(towardsEnd: true),
              const SizedBox(height: 10),
              if (!_part)
                _Toggle(
                  label: l.cardWithTranslation,
                  value: _withTranslation && !o.translationFailed,
                  enabled:
                      !o.translationFailed && _translationOf(o).isNotEmpty,
                  onChanged: (v) => setState(() => _withTranslation = v),
                ),
              _Toggle(
                label: l.cardWithReference,
                value: _withReference,
                onChanged: (v) => setState(() => _withReference = v),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _chosen.trim().isEmpty ? null : _done,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: const Color(0xFF14100A),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                child: Text(l.findAdd,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _translationOf(_Opened o) => _whole ? o.wholeTranslation : o.translation;

  Widget _plain(bool rtl) {
    final o = widget.opened;
    final translation = _translationOf(o);
    // Stretched, so each line's own textAlign places it: a shrink-wrapped
    // line in an RTL column sat on the left, whatever it asked for.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _source,
          textAlign: rtl ? TextAlign.right : TextAlign.left,
          style: TextStyle(
            fontFamily: rtl ? 'NotoNaskhArabic' : null,
            fontSize: rtl ? 19 : 15,
            height: rtl ? 2.0 : 1.5,
            color: AppColors.textPrimary,
          ),
        ),
        if (translation.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            translation,
            textDirection: o.quran
                ? _quranTranslationDirection()
                : _hadithTranslationDirection(),
            style: const TextStyle(
                fontSize: 13, height: 1.5, color: AppColors.textSecondary),
          ),
        ],
      ],
    );
  }

  /// Every word as its own target, with the chosen run lit.
  ///
  /// A [Wrap] rather than a rich text with gesture recognizers: a word
  /// in a paragraph is a hit box six pixels tall, and this is a
  /// gesture people are meant to get right the first time.
  Widget _wordPicker(bool rtl) {
    final words = _words;
    final a = _from == null ? -1 : (_to == null ? _from! : (_from! < _to! ? _from! : _to!));
    final b = _from == null ? -1 : (_to == null ? _from! : (_from! < _to! ? _to! : _from!));
    final l = L10n.of(context);
    return Wrap(
      spacing: 4,
      runSpacing: 6,
      alignment: rtl ? WrapAlignment.end : WrapAlignment.start,
      children: [
        for (var i = 0; i < words.length; i++)
          A11yTap(
            label: '${l.a11yCardWord}: ${words[i]}',
            selected: i >= a && i <= b,
            onTap: () => _tapWord(i),
            child: GestureDetector(
              onTap: () => _tapWord(i),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                decoration: BoxDecoration(
                  color: i >= a && i <= b
                      ? AppColors.gold.withValues(alpha: 0.22)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  words[i],
                  style: TextStyle(
                    fontFamily: rtl ? 'NotoNaskhArabic' : null,
                    fontSize: rtl ? 19 : 15,
                    height: rtl ? 1.8 : 1.4,
                    color: i >= a && i <= b
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// Small parts
// ---------------------------------------------------------------------

/// One verse of the open surah: its number, the Arabic, and the line
/// under it in the reader's own edition.
class _AyahRow extends StatelessWidget {
  final int surah;
  final Ayah ayah;

  /// Lit when the search asked for this verse by name, so it is
  /// obvious which of them the list was scrolled to.
  final bool highlighted;
  final VoidCallback onTap;

  const _AyahRow({
    super.key,
    required this.surah,
    required this.ayah,
    required this.highlighted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return A11yTap(
      label: '${l.a11yAyah(ayah.number)}. ${ayah.arabic}',
      hint: l.a11yAddsToCard,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: highlighted
                ? AppColors.gold.withValues(alpha: 0.09)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            // Stretched, so the Arabic's right alignment holds even for a
            // verse shorter than the row.
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('$surah:${ayah.number}',
                  style: const TextStyle(
                      fontSize: 11.5, color: AppColors.goldBright)),
              const SizedBox(height: 6),
              Text(
                ayah.arabic,
                textAlign: TextAlign.right,
                textDirection: TextDirection.rtl,
                style: const TextStyle(
                  fontFamily: 'HafsUthmani',
                  fontSize: 19,
                  height: 1.9,
                  color: AppColors.textPrimary,
                ),
              ),
              if (ayah.translation.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  ayah.translation,
                  textDirection: _quranTranslationDirection(),
                  style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: AppColors.textSecondary),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One verse a search turned up: its reference, the Arabic, and the
/// translated line under it when that is what matched.
class _HitRow extends StatelessWidget {
  final VerseHit hit;
  final VoidCallback onTap;

  const _HitRow({required this.hit, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    final info = surahIndex[hit.surah - 1];
    return A11yTap(
      label: '${l.localizedSurahName(info.nameEnglish)} ${hit.ayah}',
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          // Stretched, so the Arabic's right alignment holds even for a
          // verse shorter than the row.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.cardVerseReference(
                  info.nameEnglish, hit.surah, hit.ayah, hit.ayah),
              style: t.bodySmall?.copyWith(
                color: AppColors.gold,
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hit.text,
              textDirection: TextDirection.rtl,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.quran(size: 19, color: AppColors.textPrimary)
                  .copyWith(height: 1.9),
            ),
            if (hit.translation.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                hit.translation,
                textDirection: _quranTranslationDirection(),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: t.bodyMedium?.copyWith(
                    fontSize: 13, height: 1.5, color: AppColors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HadithRow extends StatelessWidget {
  final Hadith hadith;
  final VoidCallback onTap;

  const _HadithRow({required this.hadith, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final reference = l.hadithReference(hadith.collection, hadith.number);
    final quote = HadithLibrary.quotable(hadith.translation);
    return A11yTap(
      label: '$reference. $quote',
      hint: l.a11yAddsToCard,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          // Stretched, so the Arabic's right alignment holds even for a
          // verse shorter than the row.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(reference,
                style: const TextStyle(
                    fontSize: 11.5, color: AppColors.goldBright)),
            const SizedBox(height: 6),
            Text(
              HadithLibrary.quotable(hadith.arabic),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
              style: const TextStyle(
                fontFamily: 'NotoNaskhArabic',
                fontSize: 17,
                height: 1.9,
                color: AppColors.textPrimary,
              ),
            ),
            if (quote.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                quote,
                textDirection: _hadithTranslationDirection(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12.5, height: 1.45, color: AppColors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Segment(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return A11yTap(
      label: label,
      selected: selected,
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.gold.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? AppColors.gold.withValues(alpha: 0.6)
                  : AppColors.stroke,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color:
                  selected ? AppColors.goldBright : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  final String label;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _Toggle({
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return A11yTap(
      label: label,
      toggled: value && enabled,
      enabled: enabled,
      onTap: enabled ? () => onChanged(!value) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged(!value) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              Icon(
                value && enabled
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                size: 18,
                color: enabled
                    ? (value ? AppColors.goldBright : AppColors.textSecondary)
                    : AppColors.stroke,
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color:
                      enabled ? AppColors.textPrimary : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  final String text;
  final bool spinner;
  final TextTheme style;

  const _Note({required this.text, required this.style, this.spinner = false});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(30, 0, 30, 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (spinner) ...[
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.gold),
              ),
              const SizedBox(height: 14),
            ],
            Text(
              text,
              textAlign: TextAlign.center,
              style: style.bodySmall?.copyWith(
                  color: AppColors.textSecondary, fontSize: 12.5, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
