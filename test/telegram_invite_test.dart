import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/widgets/telegram_invite.dart';

/// The Telegram invitation: never to someone new, twice in a lifetime
/// at most, both inside one week, and never again once joined.
void main() {
  final t0 = DateTime(2026, 10, 14, 12);

  bool due(
    TelegramInviteRecord r, {
    DateTime? now,
    bool aged = true,
    bool opened = false,
    int reelsMade = 0,
  }) =>
      TelegramInvite.due(r, now ?? t0,
          aged: aged, opened: opened, reelsMade: reelsMade);

  test('not for someone new, nor before a few good moments', () {
    expect(due(const TelegramInviteRecord(moments: 9), aged: false), isFalse,
        reason: 'installed under three days ago');
    expect(due(const TelegramInviteRecord(moments: 1)), isFalse,
        reason: 'a first badge');
    expect(due(const TelegramInviteRecord(moments: 2)), isFalse);
    expect(due(const TelegramInviteRecord(moments: 3)), isTrue);
    expect(due(const TelegramInviteRecord(moments: 1), reelsMade: 5), isTrue,
        reason: 'reels made before the moments were counted');
  });

  test('a second time two days on, inside the week, and never a third', () {
    final once = TelegramInviteRecord(
        moments: 5, shows: 1, firstShown: t0, lastShown: t0);
    expect(due(once, now: t0.add(const Duration(days: 1))), isFalse);
    expect(due(once, now: t0.add(const Duration(days: 2))), isTrue);
    expect(due(once, now: t0.add(const Duration(days: 7))), isFalse,
        reason: 'the week is over');
    final twice = once.copyWith(
        shows: 2, lastShown: t0.add(const Duration(days: 3)));
    expect(due(twice, now: t0.add(const Duration(days: 6))), isFalse);
  });

  test('joined, here or from Settings, is never asked again', () {
    expect(due(const TelegramInviteRecord(moments: 5, joined: true)), isFalse);
    expect(due(const TelegramInviteRecord(moments: 5), opened: true), isFalse);
  });

  test('the record survives a restart', () {
    final r = TelegramInviteRecord(
        moments: 4, shows: 1, firstShown: t0, lastShown: t0, joined: true);
    final back = TelegramInviteRecord.fromJson(r.toJson());
    expect(back.moments, 4);
    expect(back.shows, 1);
    expect(back.firstShown, t0);
    expect(back.lastShown, t0);
    expect(back.joined, isTrue);
  });

  test('each moment waits as long as asked', () {
    expect(TelegramMoment.achievement.delay, const Duration(seconds: 8));
    expect(TelegramMoment.quiz.delay, const Duration(seconds: 10));
    expect(TelegramMoment.card.delay, const Duration(seconds: 8));
    expect(TelegramMoment.reel.delay, const Duration(seconds: 15));
  });
}
