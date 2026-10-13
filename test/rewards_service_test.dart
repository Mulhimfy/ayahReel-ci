import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/rewards_service.dart';

/// Badges are earned once and kept: a reel count that crosses a
/// milestone hands one back, the widget's first sighting hands one
/// back, and neither is handed back twice.
void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('rewards');
    RewardsService.fileOverride = File('${tmp.path}/rewards.json');
    RewardsService.reelCountOverride = () async => 0;
    RewardsService.resetForTest();
  });
  tearDown(() {
    RewardsService.fileOverride = null;
    RewardsService.reelCountOverride = null;
    RewardsService.resetForTest();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {/* Windows holds the handle; the runner cleans up */}
  });

  test('the first reel earns the first badge, the second earns nothing',
      () async {
    expect(await RewardsService.recordReelCreated(), RewardBadge.all.first);
    expect(RewardsService.state.value.reelsMade, 1);
    expect(RewardsService.state.value.badges, [RewardBadge.all.first]);
    expect(await RewardsService.recordReelCreated(), isNull);
    expect(RewardsService.state.value.reelsMade, 2);
  });

  test('every milestone hands its badge back exactly once', () async {
    final earned = <RewardBadge>[];
    for (var i = 0; i < 100; i++) {
      final b = await RewardsService.recordReelCreated();
      if (b != null) earned.add(b);
    }
    expect(earned.map((b) => b.reels), RewardBadge.reelMilestones);
    expect(RewardsService.state.value.badges.length, 6);
  });

  test('the widget badge is awarded once, with its points', () async {
    expect(await RewardsService.recordWidgetPlaced(), isTrue);
    expect(RewardsService.state.value.points, RewardsService.pointsForWidget);
    expect(RewardsService.state.value.badges, [RewardBadge.widget]);
    expect(await RewardsService.recordWidgetPlaced(), isFalse);
    expect(RewardsService.state.value.points, RewardsService.pointsForWidget);
  });

  test('badges survive a restart', () async {
    await RewardsService.recordReelCreated();
    await RewardsService.recordWidgetPlaced();
    RewardsService.resetForTest();
    await RewardsService.init();
    final s = RewardsService.state.value;
    expect(s.reelsMade, 1);
    expect(s.widgetPlaced, isTrue);
    expect(s.badges, [RewardBadge.all.first, RewardBadge.widget]);
  });

  test('a file from before the badges counts the reels in the library',
      () async {
    RewardsService.fileOverride!
        .writeAsStringSync(jsonEncode({'points': 120, 'streak': 3}));
    RewardsService.reelCountOverride = () async => 12;
    await RewardsService.init();
    final s = RewardsService.state.value;
    expect(s.reelsMade, 12);
    expect(s.points, 120);
    expect(s.badges.map((b) => b.reels), [1, 5, 10]);
    // The next reel is the thirteenth: no milestone, no badge.
    expect(await RewardsService.recordReelCreated(), isNull);
  });

  test('an unearned reel badge says how many reels are left', () async {
    await RewardsService.recordReelCreated();
    final five = RewardBadge.all[1];
    expect(five.reelsToGo(RewardsService.state.value), 4);
    expect(RewardBadge.widget.reelsToGo(RewardsService.state.value), 0);
  });
}
