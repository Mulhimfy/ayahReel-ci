import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/app_version.dart';

/// The marketing version lives in two files that cannot see each other:
/// pubspec.yaml, which the build bakes into the binary and the stores
/// display, and [kAppVersion], which UpdateService compares the feed
/// against. Nothing at compile time links them.
///
/// A drift between the two is silent and one-directional-bad. Too low
/// and every user on the current release is told to update to the
/// version they already have; too high and users who are genuinely
/// behind are never told anything. Neither shows up in normal use of a
/// debug build, because the check only speaks when the feed disagrees.
///
/// tool/sync-version.sh (and its .ps1 twin) keeps them equal. This is
/// what makes forgetting to run it a failed build rather than a bad
/// release — it runs in the `flutter test` gate that both the store
/// build and the OTA patch have to pass.
void main() {
  test('kAppVersion matches the version in pubspec.yaml', () {
    final line = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('version:'),
            orElse: () => throw StateError('pubspec.yaml has no version:'));

    // `version: 1.0.2+13` — the build number after '+' is deliberately
    // not part of kAppVersion, so compare only the marketing half.
    final pubspecVersion = line.split(':')[1].trim().split('+').first;

    expect(
      kAppVersion,
      pubspecVersion,
      reason: 'lib/data/app_version.dart is out of step with pubspec.yaml. '
          'Run tool/sync-version.sh (or tool/sync-version.ps1) — do not '
          'edit kAppVersion by hand.',
    );
  });
}
