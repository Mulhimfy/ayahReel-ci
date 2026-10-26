import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/models.dart';
import 'package:ayah_reels/data/settings_service.dart';
import 'package:ayah_reels/data/verse_numbering.dart';
import 'package:ayah_reels/data/verse_translation.dart';
import 'package:ayah_reels/widgets/ayah_overlay.dart';

/// "None" in the verse-translation picker: the Arabic alone on a card,
/// with the edition kept underneath for the day it is picked again.
void main() {
  tearDown(() => SettingsService.state.value = AppSettings.defaults);

  test('is off by default, and on an install that predates it', () {
    expect(AppSettings.defaults.verseTranslationOff, isFalse);
    expect(AppSettings.fromJson(const {}).verseTranslationOff, isFalse);
  });

  test('survives a round trip, and keeps the edition', () {
    final back = AppSettings.fromJson(AppSettings.defaults
        .copyWith(
            translation: VerseTranslation.urdu, verseTranslationOff: true)
        .toJson());
    expect(back.verseTranslationOff, isTrue);
    expect(back.translation, VerseTranslation.urdu);
  });

  group('the card', () {
    const ayah = Ayah(
      number: 255,
      arabic: 'ٱللَّهُ لَآ إِلَٰهَ إِلَّا هُوَ',
      translation: 'Allah - there is no deity except Him.',
    );

    Widget host({bool? show}) => MaterialApp(
          theme: ThemeData(fontFamily: 'Inter'),
          home: Scaffold(
            body: Center(
              child: AyahOverlay(
                ayah: ayah,
                width: 360,
                translation: VerseTranslation.english,
                showTranslation: show,
                numbering: VerseNumbering.off,
              ),
            ),
          ),
        );

    testWidgets('carries the translation by default', (t) async {
      await t.pumpWidget(host());
      expect(find.text(ayah.translation), findsOneWidget);
      expect(find.byKey(AyahOverlay.dividerKey), findsOneWidget);
    });

    testWidgets('leaves the line and its rule off when told to', (t) async {
      await t.pumpWidget(host(show: false));
      expect(find.text(ayah.arabic), findsOneWidget);
      expect(find.text(ayah.translation), findsNothing);
      expect(find.byKey(AyahOverlay.dividerKey), findsNothing);
    });

    testWidgets('follows Settings when not told', (t) async {
      SettingsService.state.value =
          AppSettings.defaults.copyWith(verseTranslationOff: true);
      await t.pumpWidget(host());
      expect(find.text(ayah.translation), findsNothing);
    });
  });
}
