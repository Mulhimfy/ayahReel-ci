import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/settings_service.dart';
import 'package:ayah_reels/data/verse_translation.dart';
import 'package:ayah_reels/l10n/l10n.dart';
import 'package:ayah_reels/theme/app_theme.dart';
import 'package:ayah_reels/widgets/language_sheet.dart';

/// Picking a language closes the sheet at once, and pops nothing else.
///
/// A language change re-lays every scheduled reminder, which is a
/// platform call per queued day — hundreds on Android, a quarter of a
/// minute on one phone. The pop used to wait for that. A user who
/// swiped the sheet away in the meantime then had the pop land on the
/// app's only route instead: an empty Navigator, which paints as a
/// black screen, and a back press that closes the app.
///
/// The notifications plugin is stood in for here by a channel that
/// takes five seconds to initialise, which is the shape of that wait.
void main() {
  const notifications =
      MethodChannel('dexterous.com/flutter/local_notifications');

  setUp(() {
    SettingsService.state.value = AppSettings.defaults;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notifications, (call) async {
      if (call.method == 'initialize') {
        await Future<void>.delayed(const Duration(seconds: 5));
        return true;
      }
      return null;
    });
  });

  tearDown(() {
    SettingsService.state.value = AppSettings.defaults;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notifications, null);
  });

  Widget host(void Function(BuildContext) open) => MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: const [
          L10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: [for (final l in AppLang.values) Locale(l.code)],
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => open(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

  Future<void> pickAndWalkAway(WidgetTester t, String row) async {
    t.view.physicalSize = const Size(390 * 3, 844 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    await t.tap(find.text('open'));
    await t.pump(const Duration(milliseconds: 600));
    await t.ensureVisible(find.text(row).last);
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text(row).last);

    // The sheet is on its way out before anything slow has finished.
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.text(row), findsNothing, reason: 'sheet still open');

    // What an impatient user does next: taps where the barrier was.
    await t.tapAt(const Offset(195, 100));
    await t.pump(const Duration(seconds: 6));
  }

  testWidgets('the app-language sheet closes at once and leaves the '
      'route under it alone', (t) async {
    await t.pumpWidget(host(showAppLanguageSheet));
    await pickAndWalkAway(t, AppLang.ar.nativeName);
    expect(SettingsService.state.value.lang, AppLang.ar);
    expect(find.text('open'), findsOneWidget,
        reason: 'the home route was popped');
  });

  testWidgets('the verse-translation sheet closes at once and leaves the '
      'route under it alone', (t) async {
    await t.pumpWidget(host(showVerseTranslationSheet));
    await pickAndWalkAway(t, VerseTranslation.urdu.nativeName);
    expect(SettingsService.state.value.translation, VerseTranslation.urdu);
    expect(find.text('open'), findsOneWidget,
        reason: 'the home route was popped');
  });
}
