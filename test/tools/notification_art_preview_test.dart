import 'dart:io';

import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/notification_art.dart';
import 'package:ayah_reels/data/reel_library.dart';
import 'package:ayah_reels/data/verse_light.dart';

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
    final serif = FontLoader('CormorantGaramond')
      ..addFont(rootBundle.load('assets/fonts/CormorantGaramond.ttf'));
    await serif.load();
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
      // The share notifications' own pictures: a library's verses, and
      // a round of eight right in ten.
      SavedReel reel(String surah, int from, int to, int day) => SavedReel(
            id: 'r$day',
            fileName: 'reel_r$day.mp4',
            reciterName: 'Mishary Alafasy',
            surahName: surah,
            startAyah: from,
            endAyah: to,
            gradientArgb: const [0xFF1B2433, 0xFF0B0F17],
            createdAt: DateTime(2026, 6, day),
          );
      final light = VerseLight.of([
        reel('Al-Fatiha', 1, 7, 1),
        reel('Al-Baqarah', 255, 257, 2),
        reel('Al-Kahf', 1, 10, 3),
        reel('Ya-Sin', 1, 12, 4),
        reel('Ar-Rahman', 1, 13, 5),
        reel('Al-Mulk', 1, 5, 6),
        reel('Al-Ikhlas', 1, 4, 7),
      ]);
      File('$out/share_verses.png')
          .writeAsBytesSync(await NotificationArt.drawVerses(light));
      File('$out/share_round.png').writeAsBytesSync(await NotificationArt
          .drawRound(960, [for (var i = 0; i < 10; i++) i != 2 && i != 6]));
    });
  }, skip: out == null);
}
