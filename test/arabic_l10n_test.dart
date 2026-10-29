import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/fatiha_data.dart';
import 'package:ayah_reels/data/reminder_copy.dart';
import 'package:ayah_reels/l10n/l10n.dart';
import 'package:ayah_reels/screens/settings_screen.dart';
import 'package:ayah_reels/theme/app_theme.dart';

/// Every language has to be complete — every reciter, background
/// and notification line covered — and the right-to-left ones
/// have to mirror the app without touching behaviour. These tests pin
/// that down for all five.
void main() {
  const en = L10n(AppLang.en);
  const ar = L10n(AppLang.ar);

  /// Every language but English, which is the one the data itself is
  /// written in and so has nothing to look up.
  const translated = [AppLang.ar, AppLang.ur, AppLang.id, AppLang.de];

  test('every reciter has a style and a name in every language', () {
    for (final lang in translated) {
      final l = L10n(lang);
      for (final r in reciters) {
        expect(l.reciterStyle(r), isNot(r.style),
            reason: '${r.id} is missing a ${lang.code} style');
        expect(l.reciterStyle(r), isNotEmpty);
        // Another recording's note, beside its chips, is read in the
        // app's language too.
        if (r.recordingNote != null) {
          expect(l.recordingNote(r), isNot(r.recordingNote),
              reason: '${r.id} is missing a ${lang.code} recording note');
        }
      }
    }
    // The name itself is only swapped where the names are read in
    // Arabic script; the Latin languages keep the Latin name.
    expect(ar.reciterName(reciters.first), reciters.first.arabicName);
    expect(const L10n(AppLang.ur).reciterName(reciters.first),
        reciters.first.arabicName);
    expect(const L10n(AppLang.de).reciterName(reciters.first),
        reciters.first.name);
    expect(en.reciterName(reciters.first), reciters.first.name);
  });

  test('no language is missing a scene category', () {
    // Checked on the tables rather than the rendered names: some
    // categories are the same word in two languages — Indonesian for
    // aurora is "Aurora" — so a name matching the English is not
    // evidence of a gap, and asserting otherwise fails on a correct
    // translation.
    final tables = L10n.sceneCategoryTables;
    final keys = tables[AppLang.ar]!.keys.toSet();
    for (final lang in translated) {
      expect(tables[lang], isNotNull, reason: '${lang.code} has no table');
      expect(tables[lang]!.keys.toSet(), keys,
          reason: '${lang.code} does not cover the same categories');
      for (final e in tables[lang]!.entries) {
        expect(e.value, isNotEmpty,
            reason: '${lang.code} ${e.key} is empty');
      }
    }
  });

  test('every bundled background gets a name in every language', () {
    for (final lang in translated) {
      final l = L10n(lang);
      for (final b in backgrounds) {
        expect(l.backgroundName(b), isNotEmpty,
            reason: '${b.id} has no ${lang.code} name');
      }
    }
    // The Arabic-script languages always differ from the English,
    // which is the case a shared spelling can never mask.
    for (final lang in [AppLang.ar, AppLang.ur]) {
      final l = L10n(lang);
      for (final b in backgrounds) {
        expect(l.backgroundName(b), isNot(b.name),
            reason: '${b.id} is missing a ${lang.code} name');
      }
    }
    for (final b in backgrounds) {
      expect(en.backgroundName(b), b.name);
    }
  });

  test('every scene tab and motif is named in every language', () {
    const tabs = ['sky', 'mountains', 'desert', 'water', 'forest', 'road',
        'sacred', 'abstract', 'aerial', 'cinematic'];
    const motifs = ['night', 'sky', 'clouds', 'rain', 'sea', 'water', 'snow',
        'mountain', 'desert', 'garden', 'land', 'road', 'sacred', 'light',
        'fire', 'fallback'];
    for (final lang in AppLang.values) {
      final l = L10n(lang);
      for (final tab in tabs) {
        expect(l.sceneTab(tab), isNot(tab),
            reason: '$tab has no ${lang.code} name');
      }
      for (final m in motifs) {
        expect(l.motifName(m), isNotEmpty,
            reason: '$m has no ${lang.code} name');
      }
    }
  });

  test('the two right-to-left languages are the Arabic-script ones', () {
    expect(AppLang.values.where((l) => l.rtl),
        [AppLang.ar, AppLang.ur]);
    expect(AppLang.values.where((l) => l.arabicScript),
        [AppLang.ar, AppLang.ur]);
    for (final lang in AppLang.values) {
      expect(lang.nativeName, isNotEmpty);
      expect(AppLang.fromCode(lang.code), lang);
    }
    // Anything unrecognised lands on English rather than crashing.
    expect(AppLang.fromCode('zz'), AppLang.en);
    expect(AppLang.fromCode(null), AppLang.en);
  });

  test('saved-reel names localize by lookup and survive unknown input', () {
    expect(ar.localizedSurahName('Al-Fatiha'), 'الفاتحة');
    expect(en.localizedSurahName('Al-Fatiha'), 'Al-Fatiha');
    expect(ar.localizedSurahName('Not A Surah'), 'Not A Surah');
    expect(ar.localizedReciterName('Mishary Alafasy'), 'مشاري العفاسي');
    expect(ar.localizedReciterName('Unknown'), 'Unknown');
  });

  test('Arabic verse counts use the dual and plural forms', () {
    expect(ar.versesCount(1), 'آية واحدة');
    expect(ar.versesCount(2), 'آيتان');
    expect(ar.versesCount(7), '7 آيات');
    expect(ar.versesCount(114), '114 آية');
    expect(en.versesCount(1), '1 verse');
    expect(en.versesCount(3), '3 verses');
  });

  test('every notification pool matches the English one', () {
    for (final pools in [ReminderCopy.quizPools, ReminderCopy.reelPools]) {
      final en = pools[AppLang.en]!;
      for (final lang in AppLang.values) {
        final pool = pools[lang]!;
        expect(pool, hasLength(en.length),
            reason: '${lang.code} has a different number of lines');
        expect(pool.map((l) => l.title).toSet(), hasLength(pool.length),
            reason: '${lang.code} repeats a title');
        for (final line in pool) {
          expect(line.title, isNotEmpty);
          expect(line.body, isNotEmpty);
        }
      }
    }
    // Same rotation, different language: a day lands on the same line,
    // said for the same part of the day in that day's words for it,
    // whatever the phone is set to.
    final day = DateTime(2026, 7, 25, 21);
    final kind = ReminderCopy.kindOn(day);
    final i = ReminderCopy.ordinalOn(day) % 15;
    for (final lang in AppLang.values) {
      final pool = (kind == NudgeKind.quiz
          ? ReminderCopy.quizPools
          : ReminderCopy.reelPools)[lang]!;
      final night = ReminderCopy.phraseFor(day, lang);
      expect(ReminderCopy.timePhrases[lang]![DayPart.night], contains(night));
      final said = ReminderCopy.forDay(day, lang: lang);
      expect(said.title, pool[i].title.replaceAll('{t}', night));
      expect(said.body, pool[i].body.replaceAll('{t}', night));
    }
  });

  testWidgets('Arabic locale renders Settings in Arabic and RTL',
      (t) async {
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.dark(lang: AppLang.ar),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        L10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: SettingsScreen(permissionCheck: () async => true),
      ),
    ));
    await t.pumpAndSettle();

    expect(find.text('الإعدادات'), findsOneWidget);
    expect(find.text('تذكير المواظبة اليومي'), findsOneWidget);
    expect(find.text('لغة التطبيق'), findsOneWidget);
    expect(find.text('ترجمة الآيات'), findsOneWidget);
    // The whole tree mirrors: RTL comes from the locale, not from
    // hand-placed Directionality widgets.
    final direction = Directionality.of(
        t.element(find.text('الإعدادات')));
    expect(direction, TextDirection.rtl);
  });

  testWidgets('English locale still renders the original strings',
      (t) async {
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      locale: const Locale('en'),
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        L10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: SettingsScreen(permissionCheck: () async => true),
      ),
    ));
    await t.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Daily streak nudge'), findsOneWidget);
    final direction =
        Directionality.of(t.element(find.text('Settings')));
    expect(direction, TextDirection.ltr);
  });
}
