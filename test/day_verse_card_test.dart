import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/fatiha_data.dart';
import 'package:ayah_reels/data/quran_verses.dart';
import 'package:ayah_reels/data/surah_index.dart';
import 'package:ayah_reels/l10n/l10n.dart';
import 'package:ayah_reels/state/creation_state.dart';
import 'package:ayah_reels/theme/app_theme.dart';
import 'package:ayah_reels/widgets/day_verse_card.dart';

/// The home screen's verse card: two short verses a day from a fixed
/// rotation, and Jumu'ah's on Friday. What is pinned here is the
/// clock — the card turns at midnight and at noon, Friday and only
/// Friday changes its dress, and nothing repeats for forty-five days —
/// the shape of the curated list (ninety, short, no duplicates, every
/// reference real, every excerpt an opening), and what a tap sets up.
///
/// The card breathes on endless loops, so nothing here pumpAndSettles;
/// every pump advances by a fixed duration, like the onboarding tests.
void main() {
  Widget host(DateTime date, {bool widgetPlaced = false}) => MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: const [
          L10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('ar')],
        home: Scaffold(
          body: SingleChildScrollView(
            child: DayVerseCard(
              date: date,
              isInstalled: () async => widgetPlaced,
            ),
          ),
        ),
      );

  // 2026-09-04 is a Friday; the 3rd a Thursday.
  final friday = DateTime(2026, 9, 4, 12);
  final thursday = DateTime(2026, 9, 3, 12);

  group('the clock', () {
    test('Friday is Jumu\'ah, and the other six days are not', () {
      for (var d = 0; d < 7; d++) {
        final day = thursday.add(Duration(days: d));
        expect(QuranVerses.isJumuah(day), day.weekday == DateTime.friday,
            reason: '$day');
      }
    });

    test('Friday carries the verse of Salawat, morning and afternoon', () {
      for (final hour in [0, 11, 12, 23]) {
        final v = QuranVerses.at(DateTime(2026, 9, 4, hour));
        expect(v.surah, 33);
        expect(v.startAyah, 56);
        expect(v.endAyah, 56);
      }
      // The card shows the opening clause; the reel gets the whole.
      expect(jumuahVerse.arabic, startsWith(jumuahVerse.shown));
      expect(jumuahVerse.shown.split(' ').length,
          lessThan(jumuahVerse.arabic.split(' ').length));
    });

    test('the page turns at noon and at midnight, and not between', () {
      final morning = QuranVerses.at(DateTime(2026, 9, 5, 0, 0));
      expect(QuranVerses.at(DateTime(2026, 9, 5, 11, 59)).reference,
          morning.reference);
      final afternoon = QuranVerses.at(DateTime(2026, 9, 5, 12, 0));
      expect(afternoon.reference, isNot(morning.reference));
      expect(QuranVerses.at(DateTime(2026, 9, 5, 23, 59)).reference,
          afternoon.reference);
      expect(QuranVerses.at(DateTime(2026, 9, 6, 0, 0)).reference,
          isNot(afternoon.reference));

      expect(QuranVerses.nextChange(DateTime(2026, 9, 5, 8, 30)),
          DateTime(2026, 9, 5, 12));
      expect(QuranVerses.nextChange(DateTime(2026, 9, 5, 12)),
          DateTime(2026, 9, 6));
    });

    test('Friday is skipped over, not swallowed: Saturday follows Thursday',
        () {
      final before = QuranVerses.rotationSlot(DateTime(2026, 9, 3, 18));
      final after = QuranVerses.rotationSlot(DateTime(2026, 9, 5, 6));
      expect(after, before + 1);
    });

    test('no verse repeats within forty-five days', () {
      final seen = <String>[];
      for (var d = 0; d < 45; d++) {
        for (final hour in [3, 15]) {
          final day = thursday.add(Duration(days: d));
          final at = DateTime(day.year, day.month, day.day, hour);
          if (QuranVerses.isJumuah(at)) continue;
          seen.add(QuranVerses.at(at).reference);
        }
      }
      expect(seen.toSet(), hasLength(seen.length),
          reason: 'a verse came round within the cycle');
      expect(seen, isNot(contains(jumuahVerse.reference)));
    });

    test('same moment, same verse, whatever the zone or the second', () {
      expect(QuranVerses.at(DateTime(2026, 9, 5, 1, 0, 0)).reference,
          QuranVerses.at(DateTime(2026, 9, 5, 11, 59, 59)).reference);
      // The day count is by calendar date, so a 23-hour daylight-saving
      // day still counts as one.
      expect(QuranVerses.daysSinceEpoch(DateTime(2026, 3, 29, 3)),
          QuranVerses.daysSinceEpoch(DateTime(2026, 3, 28, 3)) + 1);
      expect(QuranVerses.daysSinceEpoch(QuranVerses.epoch.toLocal()), 0);
      // Before the epoch — a phone with no clock — is not a crash.
      expect(QuranVerses.daysSinceEpoch(DateTime(1999, 12, 31)), 0);
    });

    test('the background count runs on every day, Fridays too', () {
      final thu = QuranVerses.backgroundSlot(DateTime(2026, 9, 3, 18));
      final fri = QuranVerses.backgroundSlot(DateTime(2026, 9, 4, 6));
      final sat = QuranVerses.backgroundSlot(DateTime(2026, 9, 5, 6));
      expect(fri, thu + 1);
      expect(sat, fri + 2);
    });
  });

  group('the curated list', () {
    test('ninety verses, and every reference a real verse', () {
      expect(quranVerses, hasLength(90));
      for (final v in [jumuahVerse, ...quranVerses]) {
        final surah = surahIndex[v.surah - 1];
        expect(surah.number, v.surah);
        expect(surah.nameEnglish, v.surahName, reason: v.reference);
        expect(v.startAyah, greaterThanOrEqualTo(1));
        expect(v.endAyah, greaterThanOrEqualTo(v.startAyah));
        expect(v.endAyah, lessThanOrEqualTo(surah.ayahCount),
            reason: v.reference);
      }
    });

    test('every verse is short enough to stand on a card', () {
      final letters = RegExp('[ء-يٱ]');
      for (final v in quranVerses) {
        final words =
            v.shown.split(' ').where((w) => letters.hasMatch(w)).length;
        expect(words, lessThanOrEqualTo(14),
            reason: '${v.reference} runs long');
        expect(v.arabic, isNotEmpty);
        expect(v.translation, isNotEmpty);
      }
    });

    test('an excerpt is the verse\'s own opening, cut at a pause', () {
      for (final v in [jumuahVerse, ...quranVerses]) {
        final e = v.excerpt;
        if (e == null) continue;
        expect(v.arabic, startsWith('$e '), reason: v.reference);
        // The next token after the excerpt is one of the pause marks.
        final next = v.arabic.substring(e.length + 1).split(' ').first;
        expect(next.runes.single, inInclusiveRange(0x06D6, 0x06DB),
            reason: '${v.reference} is not cut at a pause mark');
      }
    });

    test('no verse appears twice', () {
      final refs = quranVerses.map((v) => v.reference).toList();
      expect(refs.toSet(), hasLength(refs.length));
      expect(refs, isNot(contains(jumuahVerse.reference)));
    });

    test('carries no circle marks or footnote markup', () {
      for (final v in [jumuahVerse, ...quranVerses]) {
        for (final c in v.arabic.runes) {
          expect(c, isNot(isIn([0x06DD, 0x06DE, 0x06DF, 0x06E0])),
              reason: '${v.reference} carries a mark the reel strips');
        }
        expect(v.translation, isNot(contains('<')));
      }
    });
  });

  group('the card', () {
    testWidgets('on a weekday: the verse and its label, nothing else',
        (t) async {
      await t.pumpWidget(host(thursday));
      await t.pump(const Duration(milliseconds: 100));
      final v = QuranVerses.at(thursday);
      expect(find.text(v.shown), findsOneWidget);
      expect(find.textContaining('Verse from the Quran'), findsOneWidget);
      expect(find.textContaining('Verse of the day'), findsNothing);
      expect(find.text('It’s Jumu’ah'), findsNothing);
      expect(find.text('Make the reel'), findsNothing);
    });

    testWidgets('on Friday: Jumu\'ah, the Salawat verse, one small door',
        (t) async {
      await t.pumpWidget(host(friday));
      await t.pump(const Duration(milliseconds: 100));
      // The whole verse, not the opening clause the rotation is cut to,
      // and its meaning under it — Friday's card is the one card that
      // carries a verse it never shortens.
      expect(find.text(jumuahVerse.arabic), findsOneWidget);
      expect(find.text(jumuahVerse.translation), findsOneWidget);
      expect(find.text('It’s Jumu’ah'), findsOneWidget);
      expect(find.text('Make the reel'), findsOneWidget);
      expect(find.textContaining('Verse from the Quran'), findsNothing);
      // It says which day it is, and what the verse is. Not where the
      // verse is read, and no greeting on the user's behalf.
      expect(find.textContaining('Mubarak'), findsNothing);
      expect(find.textContaining('khutbah'), findsNothing);
      expect(find.textContaining('The verse of Salawat'), findsOneWidget);
    });

    testWidgets('a tap sets the verse up and goes to the voice', (t) async {
      await t.pumpWidget(host(friday));
      await t.pump(const Duration(milliseconds: 100));
      await t.tap(find.text('Make the reel'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(creationState.surah, 33);
      expect(creationState.startAyah, 56);
      expect(creationState.endAyah, 56);
      expect(creationState.seriesTarget, isNull);
      expect(find.text('Choose the voice'), findsOneWidget);
      expect(find.text(reciters.first.name), findsOneWidget);
    });

    testWidgets('stays compact at phone width', (t) async {
      t.view.physicalSize = const Size(360 * 3, 780 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      // The longest verse the rotation carries, the one with the
      // longest translation, and Friday's.
      QuranVerse longest = quranVerses.first;
      QuranVerse wordiest = quranVerses.first;
      for (final v in quranVerses) {
        if (v.shown.length > longest.shown.length) longest = v;
        if (v.translation.length > wordiest.translation.length) wordiest = v;
      }
      DateTime dateOf(QuranVerse target) {
        var d = DateTime(2026, 9, 5, 6);
        for (var i = 0; i < 200; i++) {
          if (QuranVerses.at(d).reference == target.reference) return d;
          d = d.add(const Duration(hours: 12));
        }
        fail('${target.reference} never comes round');
      }

      // The test font sets every glyph as a full square, so the
      // longest verse wraps harder here than the Uthmani face ever
      // makes it, and a translation shown whole — as it now is — runs
      // to two or three times the lines it takes in the real face.
      // The ceilings are for the card not ballooning, and the Moments
      // row still showing under it on a small phone.
      for (final (date, ceiling) in [
        (dateOf(longest), 360.0),
        (dateOf(wordiest), 520.0),
        // Friday sets the whole verse of Salawat and the whole of its
        // meaning, so it is no longer the shortest card of the week.
        (friday, 420.0)
      ]) {
        await t.pumpWidget(host(date));
        await t.pump(const Duration(milliseconds: 100));
        final h = t.getSize(find.byType(DayVerseCard)).height;
        expect(h, lessThan(ceiling), reason: '$date card is $h tall');
      }
    });
  });
}
