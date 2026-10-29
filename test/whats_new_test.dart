import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/fatiha_data.dart';
import 'package:ayah_reels/l10n/l10n.dart';
import 'package:ayah_reels/theme/app_theme.dart';
import 'package:ayah_reels/widgets/whats_new.dart';

/// The note of what 1.0.10 brought: once, to the people who had the app
/// before it, and never to a new install or in another version.
void main() {
  group('who sees it', () {
    bool pending(String version, bool? recorded, bool onboarded) =>
        WhatsNew.pending(
            version: version, recorded: recorded, onboarded: onboarded);

    test('an old user, on the first launch of 1.0.10', () {
      expect(pending('1.0.10', null, true), isTrue);
    });

    test('never a new install, even once onboarding is done', () {
      // The first launch writes "told" for a new phone, so the next
      // launch, onboarded by then, reads the record, not the flag.
      expect(pending('1.0.10', null, false), isFalse);
      expect(pending('1.0.10', false, true), isFalse);
    });

    test('once: shown is the end of it', () {
      expect(pending('1.0.10', true, true), isTrue);
      expect(pending('1.0.10', false, true), isFalse);
    });

    test('never in another version', () {
      for (final v in ['1.0.9', '1.0.11', '1.1.0', '2.0.0']) {
        expect(pending(v, null, true), isFalse, reason: v);
        expect(pending(v, true, true), isFalse, reason: v);
      }
    });
  });

  Future<void> open(WidgetTester t, Locale locale) async {
    final lang = AppLang.values.firstWhere((l) => l.name == locale.languageCode);
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.dark(lang: lang),
      locale: locale,
      supportedLocales: const [
        Locale('en'),
        Locale('ar'),
        Locale('ur'),
        Locale('id'),
        Locale('de'),
      ],
      localizationsDelegates: const [
        L10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog<void>(
              context: context, builder: (_) => WhatsNew.dialog()),
          child: const Text('open'),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
  }

  testWidgets('says what is new, names the two voices, and closes',
      (t) async {
    await open(t, const Locale('en'));
    expect(find.text("What's new in AyahReel"), findsOneWidget);
    expect(find.text(WhatsNew.forVersion), findsOneWidget);
    expect(
        find.text('New reciters: Mohammed Al-Luhaidan and Islam Sobhi.'),
        findsOneWidget);
    expect(find.textContaining('the light follows each word'), findsOneWidget);
    await t.tap(find.text('Got it'));
    await t.pumpAndSettle();
    expect(find.text("What's new in AyahReel"), findsNothing);
  });

  testWidgets('Arabic names the voices in Arabic', (t) async {
    await open(t, const Locale('ar'));
    expect(find.text('الجديد في AyahReel'), findsOneWidget);
    expect(find.text('قرّاء جدد: محمد اللحيدان وإسلام صبحي.'), findsOneWidget);
  });

  testWidgets('fits a small phone in every language', (t) async {
    t.view.physicalSize = const Size(320 * 2, 568 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    for (final code in ['en', 'ar', 'ur', 'id', 'de']) {
      await open(t, Locale(code));
      // An overflow is a test failure on its own; the button must be
      // there to close it.
      expect(find.byType(FilledButton), findsOneWidget, reason: code);
      await t.tap(find.byType(FilledButton));
      await t.pumpAndSettle();
    }
  });

  test('Al-Luhaidan and Islam Sobhi come straight after Yasser Ad-Dussary',
      () {
    final ids = [for (final v in voices) v.id];
    final at = ids.indexOf('dussary');
    expect(at, greaterThanOrEqualTo(0));
    expect(ids.sublist(at, at + 3), ['dussary', 'luhaidan', 'sobhi']);
  });
}
