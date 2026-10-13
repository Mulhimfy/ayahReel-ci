import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/fatiha_data.dart';
import 'package:ayah_reels/l10n/l10n.dart';
import 'package:ayah_reels/screens/reciter_screen.dart';
import 'package:ayah_reels/theme/app_theme.dart';

/// The voice list, once it is too long to scroll by eye, is searched.
void main() {
  const l = L10n(AppLang.en);

  setUp(() {
    // The screen's sample player talks to its plugin from the moment it
    // is made. Answer it — every call a success, every stream empty —
    // and leave the framework's own channels (text input above all) to
    // their usual handlers.
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

  Future<void> open(WidgetTester t) async {
    await t.pumpWidget(MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'Inter',
        scaffoldBackgroundColor: AppColors.bg,
      ),
      home: const ReciterScreen(),
    ));
    await t.pump();
  }

  Finder field() => find.byType(TextField);

  testWidgets('past forty voices, a field to search them by', (t) async {
    expect(reciters.length, greaterThan(40));
    await open(t);
    expect(field(), findsOneWidget);
    expect(find.text(l.searchReciters(reciters.length)), findsOneWidget);
    // The upload leads the list while nothing is being looked for.
    expect(find.text(l.useYourOwnAudio), findsOneWidget);
  });

  testWidgets('typing narrows the list, and the upload steps aside',
      (t) async {
    await open(t);
    await t.enterText(field(), 'alafasy');
    await t.pump();
    expect(find.text('Mishary Alafasy'), findsOneWidget);
    expect(find.text('Mahmoud Al-Husary'), findsNothing);
    expect(find.text(l.useYourOwnAudio), findsNothing);

    // By the Arabic name as well, whatever the interface language.
    await t.enterText(field(), 'الحصري');
    await t.pump();
    expect(find.text('Mahmoud Al-Husary'), findsOneWidget);
    expect(find.text('Al-Husary · Mujawwad'), findsOneWidget);
    expect(find.text('Mishary Alafasy'), findsNothing);
  });

  testWidgets('a name that matches no one says so', (t) async {
    await open(t);
    await t.enterText(field(), 'zzqx');
    await t.pump();
    expect(find.text(l.noReciterMatch), findsOneWidget);
    expect(find.text('Mishary Alafasy'), findsNothing);
  });

  testWidgets('clearing the field brings the whole list back', (t) async {
    await open(t);
    await t.enterText(field(), 'zzqx');
    await t.pump();
    await t.tap(find.byTooltip(l.clear));
    await t.pump();
    expect(find.text(l.noReciterMatch), findsNothing);
    expect(find.text(l.useYourOwnAudio), findsOneWidget);
    expect(find.text('Mishary Alafasy'), findsOneWidget);
    expect(t.widget<TextField>(field()).controller!.text, isEmpty);
  });
}
