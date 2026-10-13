import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/fatiha_data.dart';
import 'package:ayah_reels/data/models.dart';
import 'package:ayah_reels/data/quran_repository.dart';
import 'package:ayah_reels/data/recitation_service.dart';
import 'package:ayah_reels/l10n/l10n.dart';
import 'package:ayah_reels/screens/reciter_screen.dart';
import 'package:ayah_reels/theme/app_theme.dart';
import 'package:ayah_reels/widgets/surah_picker_sheet.dart';

/// A voice that never recorded a surah is never offered it: the surah
/// picker greys the surah out for it, the voice list greys the voice out
/// for it, and if the pair meets anyway the recitation says what is
/// wrong instead of blaming the connection.
void main() {
  const l = L10n(AppLang.en);
  final gapped = reciters.firstWhere((r) => r.missingSurahs.isNotEmpty);
  final gap = gapped.missingSurahs.first;
  final gapName = l.surahTitle(QuranRepository.surahInfo(gap));

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .allMessagesHandler = (channel, handler, message) {
      if (channel.startsWith('xyz.luan/audioplayers')) {
        return Future.value(
            const StandardMethodCodec().encodeSuccessEnvelope(null));
      }
      return handler?.call(message);
    };
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .allMessagesHandler = null;
  });

  Widget host(Widget child) => MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          fontFamily: 'Inter',
          scaffoldBackgroundColor: AppColors.bg,
        ),
        home: child,
      );

  test('the recitation refuses the pair, by name, before any download',
      () async {
    await expectLater(
      RecitationService.load(gapped, gap),
      throwsA(isA<SurahUnavailable>()
          .having((e) => e.surah, 'surah', gap)
          .having((e) => e.reciter.id, 'reciter', gapped.id)),
    );
  });

  test('the preview names both, and does not blame the connection', () {
    final m = l.surahNotRecorded(l.reciterName(gapped), gapName);
    expect(m, contains(gapped.name));
    expect(m, contains(gapName));
    expect(m.toLowerCase(), isNot(contains('connection')));
  });

  testWidgets('the surah picker shows the surah but will not pick it',
      (t) async {
    SurahPick? picked;
    await t.pumpWidget(host(Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async => picked =
              await showSurahPicker(context, unavailable: {gap}),
          child: const Text('open'),
        ),
      ),
    )));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '$gap');
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text(l.notRecordedByVoice), findsOneWidget);
    await t.tap(find.text(l.notRecordedByVoice));
    await t.pump();
    expect(picked, isNull, reason: 'the row is not a way in');
    // Another surah still is.
    final other = gap == 2 ? 3 : 2;
    await t.enterText(find.byType(TextField), '$other');
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text(l.notRecordedByVoice), findsNothing);
  });

  testWidgets('with the surah chosen, a voice without it cannot be picked',
      (t) async {
    await t.pumpWidget(host(ReciterScreen(surah: gap)));
    await t.pump();
    await t.enterText(find.byType(TextField), gapped.name);
    await t.pump();
    expect(find.text(l.noRecordingOf(gapName)), findsOneWidget);
    final card = find.descendant(
        of: find.byType(ListView), matching: find.text(gapped.name));
    await t.tap(card);
    await t.pump();
    final button = t.widget<Semantics>(find
        .ancestor(
            of: card,
            matching: find.byWidgetPredicate((w) =>
                w is Semantics && (w.properties.button ?? false)))
        .first);
    expect(button.properties.enabled, isFalse);
    // The same voice, for a surah it has, is an ordinary card.
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(host(const ReciterScreen(surah: 1)));
    await t.pump();
    await t.enterText(find.byType(TextField), gapped.name);
    await t.pump();
    expect(find.text(l.reciterStyle(gapped)), findsOneWidget);
  });

  test('every voice with a gap still has every other surah', () {
    for (final r in reciters.where((r) => r.missingSurahs.isNotEmpty)) {
      expect(r.source, isA<SurahFiles>());
      expect(r.missingSurahs.length, lessThan(5), reason: r.id);
    }
  });
}
