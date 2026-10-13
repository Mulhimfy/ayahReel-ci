import 'dart:io';

import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/notification_art.dart';

/// Draws every notification picture to disk, to be looked at without a
/// phone. Skipped unless pointed somewhere:
///
///   NOTIF_PREVIEW_OUT=/tmp/notif flutter test test/tools/notification_art_preview_test.dart
void main() {
  final out = Platform.environment['NOTIF_PREVIEW_OUT'];

  testWidgets('notification art preview', (t) async {
    final loader = FontLoader('HafsUthmani')
      ..addFont(rootBundle.load('assets/fonts/UthmanicHafs.ttf'));
    await loader.load();
    await t.runAsync(() async {
      for (var i = 0; i < NotificationArt.perKind; i++) {
        for (final (name, draw) in [
          ('quiz', NotificationArt.drawQuiz),
          ('reel', NotificationArt.drawReel),
        ]) {
          final png = await draw(i);
          final f = File('$out/${name}_$i.png')..writeAsBytesSync(png);
          // ignore: avoid_print
          print('wrote ${f.path} ${png.length ~/ 1024} KB');
        }
      }
    });
  }, skip: out == null);
}
