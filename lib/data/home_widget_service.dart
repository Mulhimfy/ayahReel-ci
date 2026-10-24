import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'arena_service.dart';
import 'debug_log.dart';
import 'quran_verses.dart';

/// The app's side of the home-screen widget.
///
/// The widget itself is native on both platforms and needs nothing
/// from the app to draw: it carries its own copy of the verse list and
/// turns the page on its own clock (see `VerseSchedule.kt` and
/// `VerseSchedule.swift`). What crosses this channel is only the three
/// things the app cannot do alone:
///
///  * whether the widget is on the home screen, so the nudges stop;
///  * on Android, asking the launcher to place it — the one platform
///    with an API for that; iOS only has instructions;
///  * a tap on the widget, which opens the app with the verse it was
///    showing, so the reel it invites can be made.
abstract final class HomeWidgetService {
  static const _channel = MethodChannel('ayahreel/widget');

  /// `ayahreel://verse/<surah>/<from>[/<to>]` — what a tapped widget
  /// opens the app with.
  static const scheme = 'ayahreel';

  static final _links = StreamController<QuranVerse>.broadcast();

  /// A verse tapped on the widget while the app is running.
  static Stream<QuranVerse> get taps => _links.stream;

  static bool _listening = false;

  /// Starts listening for widget taps. Safe to call more than once.
  static void init() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onLink') {
        final link = call.arguments as String?;
        // Every link the app is handed goes past the arena too: a
        // challenge is `ayahreel://arena/<code>`, and the same channel
        // carries it.
        ArenaService.takeLink(link);
        final v = parseLink(link);
        if (v != null) _links.add(v);
      }
    });
  }

  /// The link the app was launched with, if it was launched with one.
  /// Answered once: the native side clears it after handing it over,
  /// so a later hot restart does not replay it.
  static Future<String?> launchLink() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return null;
    try {
      return await _channel.invokeMethod<String>('getLaunchLink');
    } catch (e) {
      rlog('widget: launch link failed: $e');
      return null;
    }
  }

  /// The verse the app was launched with, if the launch was a widget
  /// tap.
  static Future<QuranVerse?> launchVerse() async =>
      parseLink(await launchLink());

  /// Whether at least one of our widgets is on a home screen.
  static Future<bool> isInstalled() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return false;
    try {
      return await _channel.invokeMethod<bool>('isInstalled') ?? false;
    } catch (e) {
      rlog('widget: isInstalled failed: $e');
      return false;
    }
  }

  /// Android only: whether the launcher can be asked to place the
  /// widget straight from the app. False on iOS and on launchers
  /// without the pin API (Android 7 and below, some third-party ones).
  static Future<bool> canRequestPin() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('canRequestPin') ?? false;
    } catch (e) {
      rlog('widget: canRequestPin failed: $e');
      return false;
    }
  }

  /// Android only: asks the launcher to place the widget. The launcher
  /// shows its own confirmation; true means it was asked, not that
  /// the user said yes — the OS never reports that back.
  static Future<bool> requestPin() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('requestPin') ?? false;
    } catch (e) {
      rlog('widget: requestPin failed: $e');
      return false;
    }
  }

  /// The verse a widget link names — or null for anything else, and
  /// for a reference that is not in the list (a link from a widget
  /// built against a newer list than this app carries).
  static QuranVerse? parseLink(String? link) {
    if (link == null) return null;
    final uri = Uri.tryParse(link);
    if (uri == null || uri.scheme != scheme || uri.host != 'verse') {
      return null;
    }
    final List<int?> parts;
    try {
      parts = uri.pathSegments.map(int.tryParse).toList();
    } on FormatException {
      return null; // an escape that isn't UTF-8: not one of ours
    }
    if (parts.length < 2 || parts.any((p) => p == null)) return null;
    final surah = parts[0]!, from = parts[1]!;
    final to = parts.length > 2 ? parts[2]! : from;
    for (final v in [jumuahVerse, ...quranVerses]) {
      if (v.surah == surah && v.startAyah == from && v.endAyah == to) {
        return v;
      }
    }
    return null;
  }

  /// The link the widgets carry for [v]; the same string both native
  /// sides build.
  @visibleForTesting
  static String linkFor(QuranVerse v) => v.startAyah == v.endAyah
      ? '$scheme://verse/${v.surah}/${v.startAyah}'
      : '$scheme://verse/${v.surah}/${v.startAyah}/${v.endAyah}';
}
