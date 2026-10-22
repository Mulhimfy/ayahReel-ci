import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'settings_service.dart';
import 'whole_file.dart';

/// When this phone first opened the app — or, for somebody who was
/// already using it on the day the app started keeping the date, that
/// they were, which is all the record can honestly say about them.
///
/// Neither store tells an app when it was installed, and nothing here
/// kept the day before [trackedFrom]. So the first run of this code
/// decides once: a phone whose onboarding is still to come is a new
/// install, dated now; one that finished onboarding earlier was here
/// before, and stays "before" — its saved reels and played rounds are
/// what can narrow that down, and [ArenaShareReport] looks at them.
///
/// Read for one thing: the note a Tanafus share sends, which says
/// whether the sharer is new to the app.
abstract final class InstallDate {
  /// The first day the date was kept.
  static const trackedFrom = '2026-10-10';

  static DateTime? _since;
  static bool _before = false;
  static Future<void>? _loading;

  /// At boot, after [SettingsService.init]: its `onboardingDone` is what
  /// tells an old install from a new one on the first run of this code.
  static Future<void> init() => _loading ??= _load();

  /// The day of the first open; null for somebody who was here before
  /// [trackedFrom], or when the record could not be read.
  static DateTime? get since => _since;

  /// Here already before the date was kept.
  static bool get before => _before;

  static Future<void> _load() async {
    try {
      final f = await _file();
      if (f.existsSync()) {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        _since = DateTime.tryParse(j['since'] as String? ?? '');
        _before = j['before'] as bool? ?? false;
        return;
      }
      _before = SettingsService.state.value.onboardingDone;
      _since = _before ? null : DateTime.now();
      await writeWhole(
          f,
          jsonEncode({
            if (_since != null) 'since': _since!.toIso8601String(),
            'before': _before,
          }));
    } catch (_) {/* best-effort, like every count kept here */}
  }

  static Future<File> _file() async =>
      File('${(await getApplicationSupportDirectory()).path}/install.json');

  @visibleForTesting
  static void resetForTest({DateTime? since, bool before = false}) {
    _loading = Future.value();
    _since = since;
    _before = before;
  }
}
