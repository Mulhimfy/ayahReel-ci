import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:ayah_reels/l10n/l10n.dart';
import 'package:ayah_reels/render/invite_story.dart';

/// Draws the invite's Instagram story card on a desk, so it can be
/// looked at without a phone. Not a test of anything: it is skipped
/// unless it is pointed somewhere.
///
///   INVITE_STORY_OUT=C:\Users\me\Desktop \
///   INVITE_STORY_FONTS=C:\path\to\ttfs \
///   flutter test test/tools/invite_story_preview_test.dart
///
/// The test runner has no network, so google_fonts cannot fetch the
/// card's faces; INVITE_STORY_FONTS is a folder of the same TTFs,
/// named `<Family>_<weight><style>.ttf` (e.g. `Inter_700normal.ttf`),
/// registered under the family names google_fonts would have used.
/// Without it the card still renders, in the runner's fallback face.
void main() {
  final out = Platform.environment['INVITE_STORY_OUT'];
  final fonts = Platform.environment['INVITE_STORY_FONTS'];

  testWidgets('invite story preview', (t) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await t.runAsync(() async {
      if (fonts != null) await _registerFonts(Directory(fonts));
      for (final l in [L10n.en, const L10n(AppLang.ar)]) {
        final bytes = await InviteStory.png(l);
        final f = File('$out/invite_story_${l.ar ? 'ar' : 'en'}.png');
        await f.writeAsBytes(bytes, flush: true);
        // ignore: avoid_print
        print('wrote ${f.path}');
      }
    });
    // The runner cannot fetch, and google_fonts reports that as an
    // error per face. The faces were registered by hand above, so
    // those reports are noise; anything else would still fail the
    // test below.
    for (var e = t.takeException(); e != null; e = t.takeException()) {
      if (!e.toString().contains('allowRuntimeFetching')) throw e;
    }
  }, skip: out == null);
}

/// Loads each `<Family>_<weight><style>.ttf` as google_fonts' family
/// `<Family>_<variant>` — `regular`/`italic` for w400, `700` etc.
/// otherwise. A weight the folder lacks is served by its nearest
/// neighbour, the way the phone's fallback would.
Future<void> _registerFonts(Directory dir) async {
  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.ttf'))
      .toList();
  final byFamily = <String, Map<int, File>>{};
  for (final f in files) {
    final name = f.uri.pathSegments.last.replaceAll('.ttf', '');
    final m = RegExp(r'^(.+)_(\d{3})normal$').firstMatch(name);
    if (m == null) continue;
    byFamily.putIfAbsent(m.group(1)!, () => {})[int.parse(m.group(2)!)] =
        f;
  }
  for (final e in byFamily.entries) {
    for (final w in [400, 500, 700, 800]) {
      final file = e.value[w] ??
          e.value.entries
              .reduce((a, b) =>
                  (a.key - w).abs() <= (b.key - w).abs() ? a : b)
              .value;
      final bytes = ByteData.sublistView(await file.readAsBytes());
      final variants = w == 400 ? ['regular', 'italic'] : ['$w'];
      for (final v in variants) {
        await (FontLoader('${e.key}_$v')..addFont(Future.value(bytes)))
            .load();
      }
    }
  }
}
