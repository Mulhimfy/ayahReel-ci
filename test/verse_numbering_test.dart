import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/models.dart';
import 'package:ayah_reels/data/settings_service.dart';
import 'package:ayah_reels/data/verse_font.dart';
import 'package:ayah_reels/data/verse_numbering.dart';
import 'package:ayah_reels/data/verse_translation.dart';
import 'package:ayah_reels/screens/settings_screen.dart';
import 'package:ayah_reels/theme/app_theme.dart';
import 'package:ayah_reels/widgets/ayah_overlay.dart';

/// Verse numbers on a reel: the numbered end-of-verse sign after the
/// Arabic, the reference line under the translation, either or both —
/// and neither unless the user asks, from a dropdown in Settings.
void main() {
  tearDown(() => SettingsService.state.value = AppSettings.defaults);

  group('the setting', () {
    test('is off by default, and on an install that predates it', () {
      expect(AppSettings.defaults.verseNumbering, VerseNumbering.off);
      expect(AppSettings.fromJson(const {}).verseNumbering,
          VerseNumbering.off);
    });

    test('survives a round trip through the settings file', () {
      for (final v in VerseNumbering.values) {
        final back = AppSettings.fromJson(
            AppSettings.defaults.copyWith(verseNumbering: v).toJson());
        expect(back.verseNumbering, v);
      }
    });

    test('an unknown code reads as off rather than failing', () {
      expect(VerseNumbering.fromCode('nonsense'), VerseNumbering.off);
    });

    test('each choice shows what it names', () {
      expect(VerseNumbering.off.showsMark, isFalse);
      expect(VerseNumbering.off.showsReference, isFalse);
      expect(VerseNumbering.mark.showsMark, isTrue);
      expect(VerseNumbering.mark.showsReference, isFalse);
      expect(VerseNumbering.reference.showsMark, isFalse);
      expect(VerseNumbering.reference.showsReference, isTrue);
      expect(VerseNumbering.both.showsMark, isTrue);
      expect(VerseNumbering.both.showsReference, isTrue);
    });
  });

  group('the text', () {
    test('digits are Arabic-Indic', () {
      expect(arabicIndicDigits(0), '٠');
      expect(arabicIndicDigits(255), '٢٥٥');
      expect(arabicIndicDigits(7), '٧');
    });

    test('the Hafs face draws bare digits as the sign', () {
      final m = ayahEndMark(VerseFace.uthmani, 255);
      expect(m.text, '٢٥٥');
      expect(m.face, VerseFace.uthmani);
    });

    test('the other faces are asked with END OF AYAH', () {
      final m = ayahEndMark(VerseFace.amiri, 12);
      expect(m.text, '۝١٢');
      expect(m.face, VerseFace.amiri);
    });

    test('Mada, which cannot enclose, borrows a face that can', () {
      final m = ayahEndMark(VerseFace.mada, 3);
      expect(m.text, '۝٣');
      expect(m.face, VerseFace.notoSansArabic);
    });

    test('so do IBM Plex, and Mada Light from the lighter sans', () {
      expect(ayahEndMark(VerseFace.plex, 3).face, VerseFace.notoSansArabic);
      expect(
          ayahEndMark(VerseFace.plexBold, 3).face, VerseFace.notoSansArabic);
      expect(ayahEndMark(VerseFace.madaLight, 3).face,
          VerseFace.notoSansExtraLight);
      // A face that encloses keeps its own sign.
      expect(ayahEndMark(VerseFace.kufiBold, 3).face, VerseFace.kufiBold);
    });

    test('the reference is in the translation’s script', () {
      expect(verseReferenceLine(2, 255, VerseTranslation.english),
          'Al-Baqarah 2:255');
      expect(verseReferenceLine(2, 255, VerseTranslation.urdu), 'البقرة ٢٥٥');
    });

    test('an unknown surah gives no reference rather than a wrong one', () {
      expect(verseReferenceLine(0, 1, VerseTranslation.english), isEmpty);
      expect(verseReferenceLine(115, 1, VerseTranslation.english), isEmpty);
    });
  });

  group('the card', () {
    const ayah = Ayah(
      number: 255,
      arabic: 'ٱللَّهُ لَآ إِلَٰهَ إِلَّا هُوَ',
      translation: 'Allah - there is no deity except Him.',
    );

    Widget host(VerseNumbering n, {int surah = 2, bool lit = false}) =>
        MaterialApp(
          theme: ThemeData(fontFamily: 'Inter'),
          home: Scaffold(
            body: Center(
              child: AyahOverlay(
                ayah: ayah,
                surah: surah,
                width: 360,
                numbering: n,
                translation: VerseTranslation.english,
                highlightTokens: lit ? (start: 0, end: 1) : null,
              ),
            ),
          ),
        );

    String arabicLine(WidgetTester t) => t
        .widgetList<RichText>(find.byType(RichText))
        .first
        .text
        .toPlainText();

    testWidgets('off draws the verse exactly as before', (t) async {
      await t.pumpWidget(host(VerseNumbering.off));
      expect(find.text(ayah.arabic), findsOneWidget);
      expect(find.byKey(AyahOverlay.referenceKey), findsNothing);
    });

    testWidgets('the mark follows the last word, joined to it', (t) async {
      await t.pumpWidget(host(VerseNumbering.mark));
      expect(arabicLine(t), '${ayah.arabic} ٢٥٥');
      expect(find.byKey(AyahOverlay.referenceKey), findsNothing);
    });

    testWidgets('the mark does not shift the highlighted words', (t) async {
      await t.pumpWidget(host(VerseNumbering.mark, lit: true));
      final root =
          t.widgetList<Text>(find.byType(Text)).first.textSpan! as TextSpan;
      final spans = root.children!.cast<TextSpan>();
      // One span per word, then the sign: the word count is intact.
      expect(spans.length, ayah.arabic.split(' ').length + 1);
      expect(spans.last.text, ' ٢٥٥');
    });

    testWidgets('the reference sits under the translation', (t) async {
      await t.pumpWidget(host(VerseNumbering.reference));
      final ref = find.byKey(AyahOverlay.referenceKey);
      expect(ref, findsOneWidget);
      expect(find.text('Al-Baqarah 2:255'), findsOneWidget);
      expect(t.getCenter(ref).dy,
          greaterThan(t.getCenter(find.text(ayah.translation)).dy));
      expect(arabicLine(t), ayah.arabic);
    });

    testWidgets('both draws both', (t) async {
      await t.pumpWidget(host(VerseNumbering.both));
      expect(arabicLine(t), endsWith('٢٥٥'));
      expect(find.byKey(AyahOverlay.referenceKey), findsOneWidget);
    });

    testWidgets('a card that does not know its surah draws no reference',
        (t) async {
      await t.pumpWidget(host(VerseNumbering.both, surah: 0));
      expect(find.byKey(AyahOverlay.referenceKey), findsNothing);
    });

    testWidgets('left unsaid, the card follows Settings', (t) async {
      SettingsService.state.value =
          AppSettings.defaults.copyWith(verseNumbering: VerseNumbering.mark);
      await t.pumpWidget(MaterialApp(
        theme: ThemeData(fontFamily: 'Inter'),
        home: AyahOverlay(ayah: ayah, surah: 2, width: 360),
      ));
      expect(arabicLine(t), endsWith('٢٥٥'));
    });
  });

  testWidgets('Settings sets it from the Customize menu', (t) async {
    t.view.physicalSize = const Size(390 * 3, 844 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: SettingsScreen(permissionCheck: () async => true),
      ),
    ));
    await t.pump();

    // The row names none of what it holds.
    expect(find.text('Verse numbers'), findsNothing);
    expect(find.text('Off'), findsNothing);
    await t.scrollUntilVisible(find.text('Customize'), 200);
    // At the foot of the card of switches: the next row down from the
    // last of them.
    final row = t.getRect(find.text('Customize'));
    final series = t.getRect(find.text('Reel series on Home'));
    expect(row.top, greaterThan(series.bottom));
    expect(row.top - series.top, lessThan(80));

    await t.tap(find.text('Customize'));
    await t.pumpAndSettle();
    for (final label in [
      'Verse numbers',
      'Off',
      'Verse-end mark',
      'Reference line',
      'Mark and reference',
    ]) {
      expect(find.text(label), findsOneWidget);
    }

    // Says where the choice ends up.
    expect(find.text('Shown on your reels'), findsOneWidget);

    await t.tap(find.text('Mark and reference'));
    await t.pumpAndSettle();
    expect(SettingsService.state.value.verseNumbering, VerseNumbering.both);
    // The menu stays open, ticking the new choice, so the next one can
    // be tried without reopening it.
    var picked = t.widget<Text>(find.text('Mark and reference'));
    expect(picked.style?.fontWeight, FontWeight.w600);
    await t.tap(find.text('Verse-end mark'));
    await t.pumpAndSettle();
    expect(SettingsService.state.value.verseNumbering, VerseNumbering.mark);
    expect(t.widget<Text>(find.text('Verse-end mark')).style?.fontWeight,
        FontWeight.w600);
    expect(t.widget<Text>(find.text('Mark and reference')).style?.fontWeight,
        FontWeight.w400);

    // Dismissed, then opened again, it ticks the last choice.
    await t.tapAt(const Offset(8, 8));
    await t.pumpAndSettle();
    expect(find.text('Verse-end mark'), findsNothing);
    await t.tap(find.text('Customize'));
    await t.pumpAndSettle();
    picked = t.widget<Text>(find.text('Verse-end mark'));
    expect(picked.style?.fontWeight, FontWeight.w600);
  });
}
