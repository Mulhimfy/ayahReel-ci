import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/card_style.dart';
import 'package:ayah_reels/l10n/l10n.dart';
import 'package:ayah_reels/theme/app_theme.dart';
import 'package:ayah_reels/widgets/discover_sheet.dart';

/// The list of things the app does that nobody would guess.
///
/// Two things have to hold for it to be worth having. Every entry has
/// to be written in every language — a discovery sheet that falls back
/// to English is a sheet an Urdu reader closes — and every entry has
/// to be about something that is actually there, which is what the
/// ids pin down: each one names an affordance the app's own tests
/// cover elsewhere.
void main() {
  const languages = AppLang.values;

  test('every discovery is written in every language', () {
    for (final lang in languages) {
      final l = L10n(lang);
      for (final d in discoveries) {
        final (title, body) = l.discovery(d.id);
        expect(title, isNotEmpty, reason: '${d.id} has no ${lang.code} title');
        expect(body, isNotEmpty, reason: '${d.id} has no ${lang.code} body');
        expect(title, isNot(d.id),
            reason: '${d.id} is unwritten in ${lang.code}');
        // A body long enough to say something and short enough to be
        // read on a phone.
        expect(body.length, greaterThan(40));
        expect(body.length, lessThan(360),
            reason: '${d.id} runs long in ${lang.code}');
      }
      expect(l.discoverTitle, isNotEmpty);
      expect(l.discoverBlurb, isNotEmpty);
      expect(l.discoverRow, isNotEmpty);
    }
  });

  test('the languages that are not English say something different', () {
    const en = L10n.en;
    for (final lang in [AppLang.ar, AppLang.ur, AppLang.id, AppLang.de]) {
      final l = L10n(lang);
      for (final d in discoveries) {
        expect(l.discovery(d.id).$1, isNot(en.discovery(d.id).$1),
            reason: '${d.id} was left in English for ${lang.code}');
      }
    }
  });

  test('no discovery is listed twice', () {
    final ids = [for (final d in discoveries) d.id];
    expect(ids.toSet(), hasLength(ids.length));
  });

  testWidgets('the sheet lists every one of them, readably', (t) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorScheme: const ColorScheme.dark(
            primary: AppColors.gold, surface: AppColors.surface),
      ),
      localizationsDelegates: const [L10n.delegate],
      home: const Scaffold(body: DiscoverSheet()),
    ));
    await t.pumpAndSettle();
    const l = L10n.en;
    expect(find.text(l.discoverTitle), findsOneWidget);
    // The first few are on screen; the rest are a scroll away.
    expect(find.text(l.discovery(discoveries.first.id).$1), findsOneWidget);
    // The list grows as the app does; scroll until the end of it is
    // actually on screen rather than guessing a distance.
    final last = find.text(l.discovery(discoveries.last.id).$1);
    for (var i = 0; i < 20 && last.evaluate().isEmpty; i++) {
      await t.drag(find.byType(ListView), const Offset(0, -400));
      await t.pumpAndSettle();
    }
    expect(find.text(l.discovery(discoveries.last.id).$1), findsOneWidget);
  });

  test('the card vocabulary is named in every language', () {
    // Every enum the composer puts in front of somebody has to have a
    // word for each of its values, in each language — a picker of
    // seven frames where three are called "none" is not a picker.
    for (final lang in languages) {
      final l = L10n(lang);
      final frames = {for (final f in CardFrame.values) l.cardFrameName(f.name)};
      expect(frames, hasLength(CardFrame.values.length),
          reason: 'two frames share a name in ${lang.code}');
      final papers = {for (final p in CardPaper.values) l.cardPaperName(p.name)};
      expect(papers, hasLength(CardPaper.values.length),
          reason: 'two papers share a name in ${lang.code}');
      final skins = {for (final s in CardSkin.values) l.cardSkinName(s.name)};
      expect(skins, hasLength(CardSkin.values.length),
          reason: 'two finishes share a name in ${lang.code}');
      final shapes =
          {for (final f in CardFormat.values) l.cardFormatName(f.name)};
      expect(shapes, hasLength(CardFormat.values.length));
      for (final topic in const [
        'mercy', 'prayer', 'charity', 'knowledge', 'patience', 'parents',
        'kindness', 'gratitude', 'dhikr', 'quran', 'forgiveness',
        'brotherhood', 'character', 'paradise', 'faith', 'dua', 'time',
        'hardship',
      ]) {
        expect(l.hadithTopicName(topic), isNot(topic),
            reason: '$topic is unnamed in ${lang.code}');
      }
      for (final collection in const [
        'bukhari', 'muslim', 'nawawi', 'qudsi', 'tirmidhi', 'abudawud',
        'nasai', 'ibnmajah', 'malik',
      ]) {
        expect(l.hadithCollectionName(collection), isNot(collection),
            reason: '$collection is unnamed in ${lang.code}');
      }
    }
  });
}
