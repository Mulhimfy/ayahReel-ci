import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'app_version.dart';
import 'debug_log.dart';

/// Tells the app when a newer build is actually downloadable, so it can
/// offer the user the store instead of leaving them on an old version
/// forever.
///
/// The whole mechanism is one number on a server. The app knows what it
/// is ([kAppVersion]); the feed says what the stores are handing out;
/// anything below that gets a soft prompt. Nothing about it needs
/// changing per release — at release time you raise the feed's number
/// and every older phone starts asking, on its own.
///
/// The feed is the source of truth *because the stores are not*. Google
/// publishes no version API at all, and Apple's lookup endpoint trails
/// a release by hours — long enough for a user to be told about an
/// update that is not there yet, which is worse than being told late.
///
/// Every failure here is silent by design. No network, a 404, a broken
/// JSON body, a clock skew — all of them end as "no update", never as
/// an error the user has to dismiss. An update prompt is a courtesy; it
/// may never stand between somebody and a recitation.
abstract final class UpdateService {
  /// Where the live store versions are published.
  ///
  /// A public gist, deliberately: the app's own repo is private, so its
  /// raw URLs 404 for everybody, and this file must be readable by
  /// phones that hold no credentials. It carries no secret — two
  /// version strings that the store listings state publicly anyway.
  ///
  /// Empty disables the check outright.
  ///
  /// The URL is the hashless `/raw/update.json` form on purpose: gist
  /// raw URLs also come in a `/raw/<revision-sha>/update.json` shape
  /// that is pinned to one edit and would freeze the feed at whatever
  /// version it named the day it was pasted here.
  ///
  /// The file's shape:
  /// ```json
  /// { "ios": {"latest": "1.0.3"}, "android": {"latest": "1.0.3"} }
  /// ```
  static const feedUrl = 'https://gist.githubusercontent.com/Mulhimfy/'
      '941b3343d0d50daaf32772a0c912e961/raw/update.json';

  /// One check per launch, however many times a screen asks.
  static bool _checkedThisRun = false;

  /// The platform's key in the feed. iOS and Android are released
  /// separately and routinely sit on different versions, so one shared
  /// number would nag whichever store is behind.
  static String get platformKey => Platform.isIOS ? 'ios' : 'android';

  /// The version the stores are handing out, or null if that could not
  /// be established for any reason at all.
  static Future<String?> latestOnStore({http.Client? client}) async {
    if (feedUrl.isEmpty) return null;
    final c = client ?? http.Client();
    try {
      final r = await c
          .get(Uri.parse(feedUrl))
          .timeout(const Duration(seconds: 6));
      if (r.statusCode != 200) {
        rlog('update: feed ${r.statusCode}');
        return null;
      }
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final entry = j[platformKey] as Map<String, dynamic>?;
      final latest = entry?['latest'] as String?;
      return latest == null || latest.trim().isEmpty ? null : latest.trim();
    } catch (e) {
      rlog('update: feed unreachable — $e');
      return null;
    } finally {
      if (client == null) c.close();
    }
  }

  /// The version to prompt for, or null to stay quiet. Answers null on
  /// every call after the first in a launch.
  static Future<String?> due({http.Client? client}) async {
    if (_checkedThisRun) return null;
    _checkedThisRun = true;
    final latest = await latestOnStore(client: client);
    if (!updateDue(current: kAppVersion, latest: latest)) return null;
    return latest;
  }

  /// Exposed for tests: resets the once-per-launch latch.
  static void resetForTest() => _checkedThisRun = false;
}

/// Whether the prompt is owed, given everything known. Pure, so the one
/// piece of judgement in this feature can be tested without a network,
/// a disk or a clock.
///
/// There is no snooze. "Not now" dismisses this launch's dialog and
/// nothing more: the ask returns on the next launch, and every launch
/// after that, until the user is actually on the published version.
/// A day's grace sounded polite and in practice meant a user who
/// opened the app once a day never saw the prompt twice — the update
/// it was pointing at could sit unreached for weeks. The dialog is
/// still not a wall; it is answered in one tap and never blocks a
/// recitation.
bool updateDue({required String current, required String? latest}) {
  if (latest == null || latest.isEmpty) return false;
  return compareVersions(current, latest) < 0;
}
