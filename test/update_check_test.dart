import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/app_version.dart';
import 'package:ayah_reels/data/update_service.dart';

/// The update prompt has exactly one piece of judgement in it, and it
/// runs on every launch of every install. Everything around it —
/// network, disk, clock — is arranged so this can be tested without any
/// of them.
void main() {
  group('compareVersions', () {
    test('orders by number, not by string', () {
      // The whole reason this function exists: '1.0.10' sorts BELOW
      // '1.0.9' as text, which would leave a tenth patch un-prompted.
      expect(compareVersions('1.0.10', '1.0.9'), greaterThan(0));
      expect(compareVersions('1.0.9', '1.0.10'), lessThan(0));
      expect(compareVersions('2.0.0', '1.9.9'), greaterThan(0));
    });

    test('missing parts count as zero', () {
      expect(compareVersions('1.0', '1.0.0'), 0);
      expect(compareVersions('1.0.1', '1.0'), greaterThan(0));
    });

    test('build metadata and pre-release tags are ignored', () {
      expect(compareVersions('1.0.2+12', '1.0.2'), 0);
      expect(compareVersions('1.0.3+1', '1.0.2+99'), greaterThan(0));
      expect(compareVersions('1.0.2-beta', '1.0.2'), 0);
    });

    test('rubbish is survivable, never thrown', () {
      expect(compareVersions('', '1.0.0'), lessThan(0));
      expect(compareVersions('vNext', '0.0.0'), 0);
    });
  });

  group('updateDue', () {
    bool due({String current = '1.0.2', String? latest}) =>
        updateDue(current: current, latest: latest);

    test('prompts when the store is ahead', () {
      expect(due(latest: '1.0.3'), isTrue);
    });

    test('silent when current, or ahead of the feed', () {
      expect(due(latest: '1.0.2'), isFalse);
      // A tester on a build the feed has not caught up with yet.
      expect(due(latest: '1.0.1'), isFalse);
    });

    test('an unreachable or empty feed is silence, not a prompt', () {
      expect(due(latest: null), isFalse);
      expect(due(latest: ''), isFalse);
    });

    test('nothing holds the prompt back but installing the update', () {
      // There is no snooze any more. The answer depends on the two
      // versions and on nothing else — no stored dismissal, no clock —
      // so the ask returns every launch until the phone is current.
      expect(due(latest: '1.0.3'), isTrue);
      expect(due(current: '1.0.3', latest: '1.0.3'), isFalse);
    });

    // A "kAppVersion is at least <literal>" floor used to sit here. It
    // guarded a release that forgot to bump the constant — which
    // version_sync_test.dart already catches exactly, by comparing it
    // against pubspec.yaml rather than against a number typed in by
    // hand. The floor only ever restated that, and it broke the one
    // case it was most likely to be run against: a back-patch branch,
    // where the constant names an older release on purpose and is
    // supposed to be below main's. It failed there for precisely the
    // reason the branch was correct, so it is gone.
  });

  group('feed', () {
    test('the URL is the hashless raw form', () {
      // GitHub's "Raw" button hands out a /raw/<revision-sha>/ URL
      // pinned to one edit. Shipped, it would freeze the feed at
      // whatever version it named that day, and no amount of editing
      // the gist afterwards would ever reach a phone.
      const url = UpdateService.feedUrl;
      expect(url, endsWith('/raw/update.json'));
      expect(RegExp(r'/raw/[0-9a-f]{20,}/').hasMatch(url), isFalse,
          reason: 'pinned to a revision — the feed can never change');
    });
  });
}
