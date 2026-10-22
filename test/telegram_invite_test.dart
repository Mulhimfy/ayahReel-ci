import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/l10n/l10n.dart';
import 'package:ayah_reels/theme/app_theme.dart';

import 'package:ayah_reels/widgets/telegram_invite.dart';

/// The Telegram invitation: early — after the first good moment, or on
/// the second launch — back again later after every "Not now", and
/// never again once joined, already a member, or told not to ask.
void main() {
  final t0 = DateTime(2026, 10, 14, 12);

  bool due(
    TelegramInviteRecord r, {
    DateTime? now,
    bool opened = false,
    int reelsMade = 0,
  }) =>
      TelegramInvite.due(r, now ?? t0, opened: opened, reelsMade: reelsMade);

  test('early: after the first good moment, or on the second launch', () {
    expect(due(const TelegramInviteRecord()), isFalse,
        reason: 'a first open with nothing done');
    expect(due(const TelegramInviteRecord(launches: 1)), isFalse);
    expect(due(const TelegramInviteRecord(moments: 1)), isTrue,
        reason: 'the first reel saved');
    expect(due(const TelegramInviteRecord(launches: 2)), isTrue,
        reason: 'came back a second time');
    expect(due(const TelegramInviteRecord(), reelsMade: 1), isTrue,
        reason: 'reels made before the moments were counted');
  });

  test('"Not now" brings it back later, every time, each wait longer, '
      'then every ten days', () {
    var r = const TelegramInviteRecord(moments: 1, shows: 1);
    var at = t0;
    final waits = <int>[];
    for (var i = 0; i < 6; i++) {
      r = TelegramInvite.answered(r, TelegramAnswer.notNow, at);
      expect(r.joined, isFalse);
      final next = r.nextAt!;
      waits.add(next.difference(at).inDays);
      expect(due(r, now: next.subtract(const Duration(minutes: 1))), isFalse);
      expect(due(r, now: next), isTrue, reason: 'back after "Not now" #$i');
      at = next;
      r = r.copyWith(shows: r.shows + 1, lastShown: at);
    }
    expect(waits, [2, 4, 7, 10, 10, 10]);
  });

  test('waved away is a "Not now"', () {
    final r = TelegramInvite.answered(
        const TelegramInviteRecord(moments: 1, shows: 1),
        TelegramAnswer.notNow,
        t0);
    expect(r.snoozes, 1);
    expect(r.nextAt, t0.add(const Duration(days: 2)));
  });

  test('joined, already a member, or "Don\'t ask again": never again', () {
    for (final a in [
      TelegramAnswer.join,
      TelegramAnswer.joined,
      TelegramAnswer.never,
    ]) {
      final r = TelegramInvite.answered(
          const TelegramInviteRecord(moments: 3, shows: 1), a, t0);
      expect(r.joined, isTrue, reason: a.name);
      expect(due(r, now: t0.add(const Duration(days: 400))), isFalse,
          reason: a.name);
    }
    expect(due(const TelegramInviteRecord(moments: 5), opened: true), isFalse,
        reason: 'the channel already opened from Settings');
  });

  test('a record from before "Not now" came back waits from its last show',
      () {
    final old = TelegramInviteRecord(
        moments: 5, shows: 2, firstShown: t0, lastShown: t0);
    expect(due(old, now: t0.add(const Duration(days: 1))), isFalse);
    expect(due(old, now: t0.add(const Duration(days: 2))), isTrue);
  });

  test('the record survives a restart', () {
    final r = TelegramInviteRecord(
        moments: 4,
        shows: 1,
        firstShown: t0,
        lastShown: t0,
        joined: true,
        launches: 3,
        snoozes: 2,
        nextAt: t0.add(const Duration(days: 4)));
    final back = TelegramInviteRecord.fromJson(r.toJson());
    expect(back.moments, 4);
    expect(back.shows, 1);
    expect(back.firstShown, t0);
    expect(back.lastShown, t0);
    expect(back.joined, isTrue);
    expect(back.launches, 3);
    expect(back.snoozes, 2);
    expect(back.nextAt, t0.add(const Duration(days: 4)));
  });

  test('each moment waits as long as asked', () {
    expect(TelegramMoment.achievement.delay, const Duration(seconds: 8));
    expect(TelegramMoment.quiz.delay, const Duration(seconds: 10));
    expect(TelegramMoment.card.delay, const Duration(seconds: 8));
    expect(TelegramMoment.reel.delay, const Duration(seconds: 15));
  });

  testWidgets('the invitation answers Join, Not now, Already joined and '
      "Don't ask again, and a tap outside is Not now", (t) async {
    TelegramAnswer? got;
    var closed = false;
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: const [
        L10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            closed = false;
            got = await showDialog<TelegramAnswer>(
                context: context, builder: (_) => TelegramInvite.dialog());
            closed = true;
          },
          child: const Text('open'),
        ),
      ),
    ));
    for (final (label, answer) in [
      ('Join', TelegramAnswer.join),
      ('Not now', TelegramAnswer.notNow),
      ('Already joined', TelegramAnswer.joined),
      ("Don't ask again", TelegramAnswer.never),
    ]) {
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.text('Join us on Telegram'), findsOneWidget);
      await t.tap(find.text(label));
      await t.pumpAndSettle();
      expect(closed, isTrue);
      expect(got, answer, reason: label);
    }
    // Waved away: no answer, which the invitation reads as Not now.
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.tapAt(const Offset(4, 4));
    await t.pumpAndSettle();
    expect(closed, isTrue);
    expect(got, isNull);
  });
}
