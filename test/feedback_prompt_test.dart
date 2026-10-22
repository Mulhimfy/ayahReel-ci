import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/app_version.dart';
import 'package:ayah_reels/data/feedback_service.dart';
import 'package:ayah_reels/data/settings_service.dart';
import 'package:ayah_reels/l10n/l10n.dart';
import 'package:ayah_reels/screens/settings_screen.dart';
import 'package:ayah_reels/theme/app_theme.dart';
import 'package:ayah_reels/widgets/feedback_sheet.dart';

/// Feedback is the only channel that carries a sentence back from a
/// user, and the only prompt in the app with no store quota holding it
/// down — nothing outside this file stops it from becoming a nag. So
/// what is pinned here is the restraint: two asks, at the fifteenth and
/// fortieth renders, none once a note has been sent, and a Settings
/// row that outlives all of it.
///
/// The POST itself is pinned by its payload rather than by a live
/// request. What the inbox is read by — `message`, `subject`, `email`
/// — has to keep arriving under those exact names: they were the
/// website contact form's, back when the endpoint was shared with it,
/// and the filters written against them outlived the sharing.
void main() {
  bool ask({required int renders, int asks = 0, bool sent = false}) =>
      FeedbackService.decide(renders: renders, asks: asks, sent: sent);

  tearDown(() {
    FeedbackService.resetForTest();
    SettingsService.state.value = AppSettings.defaults;
  });

  group('when it lets itself in', () {
    test('the asks land on the fifteenth and fortieth renders', () {
      // Late on purpose. Second-and-fifth collected first impressions
      // from people who had not formed one, and eight was still too
      // soon for users; fifteen reels is a habit, forty a regular.
      expect(FeedbackService.milestones, [15, 40]);
    });

    test('the early renders belong to the reminder and the rating', () {
      // Not a style preference: those two share the first renders
      // already, and a third sheet on a render where the user has seen
      // the app work a couple of times collects nothing worth reading.
      expect(FeedbackService.milestones.first, greaterThan(5));
      for (var r = 1; r < FeedbackService.milestones.first; r++) {
        expect(ask(renders: r), isFalse, reason: 'asked at render $r');
      }
    });

    test('each ask fires on the render that reaches its milestone', () {
      for (var i = 0; i < FeedbackService.milestones.length; i++) {
        final at = FeedbackService.milestones[i];
        expect(ask(renders: at - 1, asks: i), isFalse,
            reason: 'ask ${i + 1} fired a render early');
        expect(ask(renders: at, asks: i), isTrue,
            reason: 'ask ${i + 1} missed its own milestone');
      }
    });

    test('two unanswered sheets and it never opens itself again', () {
      final past = FeedbackService.milestones.last + 50;
      expect(ask(renders: past, asks: FeedbackService.milestones.length),
          isFalse);
      expect(ask(renders: past, asks: 99), isFalse);
    });

    test('a note that was actually sent ends the asking for good', () {
      for (var i = 0; i < FeedbackService.milestones.length; i++) {
        expect(ask(renders: 500, asks: i, sent: true), isFalse,
            reason: 'asked again after the user had already written in');
      }
    });

    test('counts alone decide it — no elapsed time anywhere', () {
      // Five reels in one sitting is exactly the user worth asking.
      // Waiting a day to catch them means catching them somewhere they
      // were not thinking about the app.
      expect(ask(renders: FeedbackService.milestones.first), isTrue);
    });
  });

  group('the render counter', () {
    test('counts every kept reel, asked or not', () async {
      FeedbackService.resetForTest();
      // Something else owned the moment on both of these; the renders
      // still have to count, or the ask never arrives at all.
      expect(await FeedbackService.offerAfterRender(mayAsk: false), isFalse);
      expect(await FeedbackService.offerAfterRender(mayAsk: false), isFalse);
      expect(FeedbackService.renders, 2);
    });

    test('a skipped ask slides to the next reel rather than being spent',
        () async {
      final first = FeedbackService.milestones.first;
      FeedbackService.resetForTest(renders: first - 1);
      // The milestone render itself was owned by something else.
      await FeedbackService.offerAfterRender(mayAsk: false);
      expect(await FeedbackService.offerAfterRender(), isTrue,
          reason: 'the ask was lost instead of postponed');
    });

    test('a sheet that opened is not offered again until the next milestone',
        () async {
      final first = FeedbackService.milestones.first;
      final second = FeedbackService.milestones.last;
      FeedbackService.resetForTest(renders: first - 1);
      expect(await FeedbackService.offerAfterRender(), isTrue,
          reason: 'render $first');
      for (var r = first + 1; r < second; r++) {
        expect(await FeedbackService.offerAfterRender(), isFalse,
            reason: 'render $r asked again');
      }
      expect(await FeedbackService.offerAfterRender(), isTrue,
          reason: 'render $second');
    });
  });

  group('what the form receives', () {
    test('the keys the shared inbox is read by are always present', () {
      final p = FeedbackService.payload(message: 'the audio drifts');
      // These three names are the website contact form's. Renaming any
      // of them silently empties a column in an inbox nobody is
      // watching.
      expect(p['message'], 'the audio drifts');
      expect(p['subject'], 'AyahReel feedback');
      expect(p['_subject'], contains('AyahReel feedback'));
      // Enough to act on a bug report, and no identifier of any kind.
      expect(p['app'], 'AyahReel');
      expect(p['version'], kAppVersion);
      expect(p['platform'], isNotEmpty);
      expect(p['language'], 'en');
      expect(p['source'], 'settings');
      expect(p.containsKey('name'), isFalse,
          reason: 'the Settings name is for the greeting, not the inbox');
    });

    test('the source is carried, because the two arrive in different moods',
        () {
      expect(
        FeedbackService.payload(
            message: 'x', source: FeedbackSource.afterRender)['source'],
        'afterRender',
      );
      expect(
        FeedbackService.payload(
            message: 'x', source: FeedbackSource.afterRender)['_subject'],
        contains('afterRender'),
      );
      // A report from a failed save is told apart in the inbox's
      // subject line, where it can be found without opening anything.
      expect(
        FeedbackService.payload(
            message: 'x', source: FeedbackSource.exportTrouble)['_subject'],
        contains('exportTrouble'),
      );
    });

    test('an address becomes the reply-to, under both of its names', () {
      final p = FeedbackService.payload(
          message: 'x', contact: '  reader@example.com ');
      expect(p['email'], 'reader@example.com');
      expect(p['_replyto'], 'reader@example.com');
      expect(p.containsKey('contact'), isFalse);
    });

    test('anything that is not an address stays out of the reply-to', () {
      // A malformed reply-to is how a whole submission gets rejected.
      // A note that arrives unreplyable still beats one that does not
      // arrive.
      for (final junk in ['@handle', 'no idea', 'reader@example', 'a b@c.d']) {
        final p = FeedbackService.payload(message: 'x', contact: junk);
        expect(p.containsKey('email'), isFalse, reason: '$junk passed as mail');
        expect(p.containsKey('_replyto'), isFalse, reason: '$junk as reply-to');
        expect(p['contact'], junk.trim());
      }
    });

    test('an empty contact adds no key at all', () {
      final p = FeedbackService.payload(message: 'x', contact: '   ');
      expect(p.containsKey('email'), isFalse);
      expect(p.containsKey('contact'), isFalse);
    });

    test('the language field follows the app, so replies match it', () {
      SettingsService.state.value =
          AppSettings.defaults.copyWith(lang: AppLang.ar);
      expect(FeedbackService.payload(message: 'x')['language'], 'ar');
    });

    test('a pasted logfile is capped rather than posted whole', () {
      final long = 'a' * (FeedbackService.maxMessageLength + 500);
      expect(FeedbackService.payload(message: long)['message'],
          hasLength(FeedbackService.maxMessageLength));
    });

    test('an empty note is never posted', () async {
      expect(await FeedbackService.send(message: '   '), isFalse);
    });
  });

  group('what counts as delivered', () {
    // FormSubmit answers 200 to submissions it refuses, and says so
    // only in the body. Every case below was a real 200 from the live
    // endpoint. If this group ever goes green on a refusal, the app
    // starts thanking users for notes it threw away.
    test('a refusal arrives as a perfectly ordinary 200', () {
      expect(FeedbackService.accepted('{"success":"false"}'), isFalse);
      expect(
        FeedbackService.accepted(
            '{"success":"false","message":"This form needs Activation."}'),
        isFalse,
      );
    });

    test('only an explicit success counts', () {
      expect(FeedbackService.accepted('{"success":"true"}'), isTrue);
      expect(FeedbackService.accepted('{"success":true}'), isTrue);
      expect(
        FeedbackService.accepted('{"success":"true","message":"sent"}'),
        isTrue,
      );
    });

    test('anything unreadable is a refusal, never a maybe', () {
      // The note is still in the box and retrying is one tap. A
      // wrongly cheerful snackbar loses it for good.
      for (final body in ['', 'null', '<html>502</html>', '[]', '{}',
          '{"ok":"true"}', '{"success":"yes"}']) {
        expect(FeedbackService.accepted(body), isFalse, reason: 'body: $body');
      }
    });
  });

  group('the Settings row', () {
    Widget host({bool arabic = false}) => MaterialApp(
          theme: AppTheme.dark(lang: arabic ? AppLang.ar : AppLang.en),
          locale: Locale(arabic ? 'ar' : 'en'),
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
        );

    /// Settles what can be settled. `pumpAndSettle` is unusable
    /// anywhere near this sheet: [GlowButton] breathes on a controller
    /// that repeats forever, so the frame queue never empties and the
    /// call times out on a screen that is working perfectly.
    Future<void> settle(WidgetTester t) async {
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
    }

    /// Feedback sits near the bottom of Settings, below the fold of a
    /// test viewport, and the list is lazy — so the row does not exist
    /// until something scrolls to it. A real phone has the same
    /// problem, which is the point of checking it this way.
    Future<void> scrollTo(WidgetTester t, Finder row) async {
      await t.scrollUntilVisible(row, 240,
          scrollable: find.byType(Scrollable).first);
      await settle(t);
    }

    testWidgets('is there in both languages', (t) async {
      await t.pumpWidget(host());
      await settle(t);
      await scrollTo(t, find.text('Send feedback'));
      expect(find.text('Send feedback'), findsOneWidget);

      await t.pumpWidget(host(arabic: true));
      await settle(t);
      await scrollTo(t, find.text('أرسل ملاحظة'));
      expect(find.text('أرسل ملاحظة'), findsOneWidget);
    });

    testWidgets('opens a box that will not send until something is typed',
        (t) async {
      await t.pumpWidget(host());
      await settle(t);
      await scrollTo(t, find.text('Send feedback'));
      await t.tap(find.text('Send feedback'));
      await settle(t);

      expect(find.text('What would make this better?'), findsOneWidget);
      final send = find.widgetWithText(FilledButton, 'Send');
      expect(send, findsOneWidget);
      expect(t.widget<FilledButton>(send).onPressed, isNull,
          reason: 'an empty note could be sent');

      await t.enterText(find.byType(TextField).first, 'the audio drifts');
      await settle(t);
      expect(t.widget<FilledButton>(send).onPressed, isNotNull);
    });

    testWidgets('a note of nothing but spaces still counts as empty',
        (t) async {
      await t.pumpWidget(host());
      await settle(t);
      await scrollTo(t, find.text('Send feedback'));
      await t.tap(find.text('Send feedback'));
      await settle(t);

      await t.enterText(find.byType(TextField).first, '    ');
      await settle(t);
      expect(
          t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Send'))
              .onPressed,
          isNull);
    });

    testWidgets('a report opens written, ready to send in one tap',
        (t) async {
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showFeedbackSheet(context,
                  source: FeedbackSource.exportTrouble),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await settle(t);

      expect(find.text('Tell us what went wrong'), findsOneWidget);
      expect(find.text('My reel didn’t save.'), findsOneWidget);
      expect(
          t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Send'))
              .onPressed,
          isNotNull,
          reason: 'the note is already written: Send works at once');
    });

    testWidgets('the automatic ask uses its own wording', (t) async {
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showFeedbackSheet(context,
                  source: FeedbackSource.afterRender),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await settle(t);

      expect(find.text('How has it been so far?'), findsOneWidget);
      expect(find.text('What would make this better?'), findsNothing);
    });
  });
}
