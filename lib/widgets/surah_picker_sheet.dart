import 'dart:async';

import 'package:flutter/material.dart';

import '../data/quran_repository.dart';
import '../data/quran_search.dart';
import '../data/settings_service.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import 'a11y.dart';

/// What the picker answers with: a surah, and — when the search named
/// one — the ayah to go to, or the run of them.
class SurahPick {
  final SurahInfo surah;
  final int? ayah;
  final int? endAyah;

  const SurahPick(this.surah, {this.ayah, this.endAyah});

  int get number => surah.number;
}

/// Opens the surah picker and answers with the pick, or null.
///
/// [unavailable] are the surahs the chosen voice hasn't recorded (see
/// [Reciter.missingSurahs]): still listed, so nobody wonders where they
/// went, but not to be picked.
Future<SurahPick?> showSurahPicker(BuildContext context,
        {Set<int> unavailable = const {}}) =>
    showModalBottomSheet<SurahPick>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => SurahPickerSheet(unavailable: unavailable),
    );

/// The parts of a search: what names the surah, and the ayah (or run
/// of ayahs) after it, if any. See [SurahPickerSheet.parse].
class SurahQuery {
  final String surah;
  final int? ayah;
  final int? endAyah;
  const SurahQuery(this.surah, {this.ayah, this.endAyah});

  @override
  bool operator ==(Object other) =>
      other is SurahQuery &&
      other.surah == surah &&
      other.ayah == ayah &&
      other.endAyah == endAyah;

  @override
  int get hashCode => Object.hash(surah, ayah, endAyah);

  @override
  String toString() => 'SurahQuery($surah, $ayah-$endAyah)';
}

/// Search-as-you-type list of all 114 surahs. Matches English name,
/// Arabic name, or number — and takes an ayah after any of them, so
/// "2:255", "baqarah 255", "البقرة ٢٥٥" or "2 255-257" all open the
/// surah on that verse. Words find the verses that carry them, listed
/// under the surahs: Arabic words against the bundled text, and words
/// in any other script against the translation the reader has chosen
/// — see [QuranSearch.search] and [QuranSearch.searchTranslation].
/// Shared by the verse picker and the series planner, which is why it
/// is not private to either.
class SurahPickerSheet extends StatefulWidget {
  /// Surahs listed but not offered; see [showSurahPicker].
  final Set<int> unavailable;

  const SurahPickerSheet({super.key, this.unavailable = const {}});

  /// Splits [raw] into the surah part and the ayah part. The ayah is
  /// the trailing number — after a colon, a space or a dash from the
  /// surah — with an optional second number for a run. A bare number
  /// is a surah number, not an ayah: "36" is Ya-Sin, "36:1" its first
  /// verse. Arabic-Indic digits count as digits.
  static SurahQuery parse(String raw) {
    final q = _westernDigits(raw).trim();
    final m = RegExp(r'^(.*?)[\s:]+(\d+)(?:\s*[-–]\s*(\d+))?$').firstMatch(q);
    if (m == null) return SurahQuery(q);
    final head = m.group(1)!.trim().replaceAll(RegExp(r'[\s:]+$'), '');
    if (head.isEmpty) return SurahQuery(q);
    // tryParse: twenty-odd digits overflow an int, and parse would
    // throw out of the search into the error box.
    final a = int.tryParse(m.group(2)!);
    final e = m.group(3) == null ? null : int.tryParse(m.group(3)!);
    if (a == null || a < 1) return SurahQuery(head);
    return SurahQuery(head, ayah: a, endAyah: e != null && e >= a ? e : null);
  }

  static String _westernDigits(String s) {
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    final b = StringBuffer();
    for (final r in s.runes) {
      final c = String.fromCharCode(r);
      var i = arabic.indexOf(c);
      if (i < 0) i = persian.indexOf(c);
      b.write(i >= 0 ? '$i' : c);
    }
    return b.toString();
  }

  @override
  State<SurahPickerSheet> createState() => _SurahPickerSheetState();
}

class _SurahPickerSheetState extends State<SurahPickerSheet> {
  String _query = '';

  /// Verses whose words the query is in, for the query they were
  /// found for — so a slow read of the index never shows results for
  /// what was typed two keystrokes ago.
  List<VerseHit> _hits = const [];
  String _hitsFor = '';

  /// A translation search is a request, so it waits for the typing to
  /// stop. The Arabic index is in memory and needs no such manners.
  Timer? _debounce;

  bool _searching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// Arabic letters anywhere in [v] — which is what decides whether
  /// the bundled text or the translation is the thing to search. Not
  /// the app's language and not the keyboard: somebody reading the
  /// interface in English still types Arabic to find an Arabic phrase,
  /// and the query itself is the only honest signal.
  static bool _isArabic(String v) => RegExp('[؀-ۿ]').hasMatch(v);

  void _onQuery(String v) {
    setState(() => _query = v);
    _debounce?.cancel();
    if (_isArabic(v)) {
      if (QuranSearch.letterCount(v) < 2) {
        _clearHits(v);
        return;
      }
      QuranSearch.search(v).then((hits) => _show(v, hits));
      return;
    }
    // Fewer than three letters of a translation is "the" and "and".
    if (v.trim().length < 3) {
      _clearHits(v);
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 320), () {
      QuranSearch.searchTranslation(
        v,
        resourceId: SettingsService.state.value.translation.resourceId,
      ).then((hits) => _show(v, hits));
    });
  }

  void _clearHits(String v) {
    _hitsFor = v;
    if (_hits.isEmpty && !_searching) return;
    setState(() {
      _hits = const [];
      _searching = false;
    });
  }

  void _show(String v, List<VerseHit> hits) {
    if (!mounted || _query != v) return;
    setState(() {
      _hits = hits;
      _hitsFor = v;
      _searching = false;
    });
  }

  List<SurahInfo> _filtered(SurahQuery pq) {
    final q = pq.surah.toLowerCase();
    final a = pq.endAyah ?? pq.ayah;
    return QuranRepository.surahs.where((s) {
      // A surah with fewer verses than the ayah asked for is not a
      // match for it.
      if (a != null && a > s.ayahCount) return false;
      if (q.isEmpty) return true;
      return s.nameEnglish.toLowerCase().contains(q) ||
          s.nameArabic.contains(q) ||
          '${s.number}' == q;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    final pq = SurahPickerSheet.parse(_query);
    final results = _filtered(pq);
    final hits = _hitsFor == _query ? _hits : const <VerseHit>[];
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scroll) => Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.stroke,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
            child: TextField(
              autofocus: false,
              onChanged: _onQuery,
              style: t.bodyMedium?.copyWith(
                  color: AppColors.textPrimary, fontSize: 15.5),
              decoration: InputDecoration(
                hintText: l.searchSurahHint,
                hintStyle: t.bodyMedium,
                prefixIcon: const Icon(Icons.search_rounded,
                    color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.surfaceRaised,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          if (_searching)
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: SizedBox(
                height: 2,
                child: LinearProgressIndicator(
                  minHeight: 2,
                  color: AppColors.gold,
                  backgroundColor: Colors.transparent,
                ),
              ),
            ),
          Expanded(
            child: results.isEmpty && hits.isEmpty
                ? Center(
                    child: Text(_searching ? l.searching : l.noSurahMatch,
                        style: t.bodyMedium))
                : ListView.builder(
                    controller: scroll,
                    // Surahs first, then — when the words matched
                    // verses — a heading and the verses.
                    itemCount: results.length +
                        (hits.isEmpty ? 0 : hits.length + 1),
                    itemBuilder: (_, i) {
                      if (i < results.length) {
                        return _surahRow(context, results[i], pq);
                      }
                      if (i == results.length) {
                        return Padding(
                          padding:
                              const EdgeInsets.fromLTRB(20, 14, 20, 4),
                          child: A11yHeader(
                            child: Text(
                              l.versesMatching(hits.length),
                              style: t.bodySmall?.copyWith(
                                color: AppColors.gold,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        );
                      }
                      return _verseRow(
                          context, hits[i - results.length - 1]);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _surahRow(BuildContext context, SurahInfo s, SurahQuery pq) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    final a = pq.ayah;
    final off = widget.unavailable.contains(s.number);
    // Faded whole: the number and the Arabic name carry their own
    // colours, which a disabled tile alone would leave bright.
    return Opacity(
      opacity: off ? 0.4 : 1,
      child: ListTile(
        enabled: !off,
        onTap: () => Navigator.of(context).pop(
          SurahPick(s, ayah: a, endAyah: pq.endAyah),
        ),
        leading: SizedBox(
          width: 34,
          child: Text(
            '${s.number}',
            textAlign: TextAlign.center,
            style: t.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.gold,
            ),
          ),
        ),
        title: Text(l.surahTitle(s),
            style: t.titleMedium?.copyWith(fontSize: 15.5)),
        // With an ayah in the search, the row says where it will open;
        // without, how long the surah is.
        subtitle: Text(
            off
                ? l.notRecordedByVoice
                : a == null
                    ? l.versesCount(s.ayahCount)
                    : l.goToAyah(a, pq.endAyah ?? a),
            style: t.bodyMedium?.copyWith(
                fontSize: 12.5,
                color: a == null || off ? null : AppColors.gold)),
        // The same name again, in its own script: for the eye.
        trailing: l.usesArabicNames
            ? null
            : ExcludeSemantics(
                child: Text(
                  s.nameArabic,
                  style: AppTheme.quran(size: 17, color: AppColors.textPrimary),
                ),
              ),
      ),
    );
  }

  /// A verse the words matched: its reference over the verse itself,
  /// in the Quran face, two lines at most — and under that the
  /// translated line when it is the translation that matched, because
  /// somebody who searched in English has to be able to read the
  /// answer well enough to pick between two of them.
  Widget _verseRow(BuildContext context, VerseHit h) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    final info = QuranRepository.surahInfo(h.surah);
    final off = widget.unavailable.contains(h.surah);
    return Opacity(
      opacity: off ? 0.4 : 1,
      child: ListTile(
        enabled: !off,
        onTap: () => Navigator.of(context).pop(SurahPick(info, ayah: h.ayah)),
        isThreeLine: true,
        title: Text(
          l.verseReference(info.nameEnglish, h.ayah, h.ayah),
          style: t.bodySmall?.copyWith(
            color: AppColors.gold,
            fontWeight: FontWeight.w600,
            fontSize: 12.5,
          ),
        ),
        // Stretched, so a short verse still sits at the right like a
        // long one, rather than shrink-wrapped at the row's start.
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                h.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.start,
                style: AppTheme.quran(size: 16, color: AppColors.textPrimary)
                    .copyWith(height: 1.6),
              ),
            ),
            if (h.translation.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  h.translation,
                  // The edition's direction, not the app's, so its
                  // punctuation lands at the right end.
                  textDirection:
                      SettingsService.state.value.translation.direction,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodySmall?.copyWith(
                    fontSize: 12.5,
                    height: 1.45,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
