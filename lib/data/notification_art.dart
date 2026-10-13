import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import '../render/on_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/quran_sun.dart';
import 'debug_log.dart';
import 'quran_verses.dart';
import 'reminder_copy.dart';
import 'verse_light.dart';

/// The picture a daily notification opens into — the big picture on
/// Android, the attachment on iOS — so it reads as the app's own and not
/// as one more line of grey text.
///
/// Drawn here, on the phone, rather than shipped: a picture in the
/// bundle is an asset, and an asset change can't reach an installed app
/// by patch. Everything they are made of is already inside — the Uthmani
/// face, the curated verses the home card carries, the bundled
/// scenery — so they are drawn once, kept on disk, and drawn again only
/// when [version] moves.
///
///  * **A quiz** is the night sky the arena lives under: a thread of
///    gold stars, and a verse with its last word taken out, waiting in a
///    gold blank — the question before the question.
///  * **A reel** is what the app makes: a scene from the library, and a
///    verse set on it in gold.
///
/// Neither carries a word of any language but the Quran's, so one set
/// of pictures serves every language the notifications are written in.
abstract final class NotificationArt {
  /// Bumped when a picture's design changes, so the old ones are drawn
  /// again rather than served.
  static const version = 1;

  /// Twice as wide as tall: what Android's big picture crops to, and
  /// what iOS shows whole when a notification is opened.
  static const width = 960.0;
  static const height = 480.0;

  /// How many pictures of each kind there are. The days of one kind
  /// walk through them in turn, as they walk through its lines.
  static const perKind = 6;

  /// The scenes the reel pictures are made from — stills in the bundle
  /// — and where the wide band is cut from each portrait, as a share of
  /// the height the band can travel: the minaret against its sunset, the
  /// moon over the sea, the line of trees under the glow.
  static const scenes = <(String, double)>[
    ('sacred_pexels_03', 0.60),
    ('desert_pexels_01', 0.60),
    ('aurora_pexels_02', 0.50),
    ('forest_pixabay_02', 0.94),
    ('ocean_pixabay_01', 0.08),
    ('mountains_pexels_01', 0.66),
  ];

  /// Where a picture is kept. Null when it can't be drawn — the
  /// notification then goes out as text, which is what it always was.
  static Future<String?> path(NudgeKind kind, int index) async {
    try {
      final i = index % perKind;
      final dir = Directory(
          '${(await getApplicationSupportDirectory()).path}/notification_art'
          '/v$version');
      final f = File('${dir.path}/${kind.name}_$i.png');
      if (f.existsSync() && f.lengthSync() > 0) return f.path;
      dir.createSync(recursive: true);
      final png = kind == NudgeKind.quiz ? await drawQuiz(i) : await drawReel(i);
      final tmp = File('${f.path}.part');
      await tmp.writeAsBytes(png, flush: true);
      tmp.renameSync(f.path);
      return f.path;
    } catch (e, st) {
      rlogError('notification art ${kind.name} $index', e, st);
      return null;
    }
  }

  /// Verses short enough to stand as one line on a picture, in the
  /// order the home card's rotation keeps them.
  static List<String> get _lines => [
        for (final v in quranVerses)
          if (_words(v.excerpt ?? v.arabic).length case >= 3 && <= 6)
            v.excerpt ?? v.arabic,
      ];

  static List<String> _words(String s) =>
      s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

  // ---- the quiz ------------------------------------------------------

  /// The night sky, a constellation, and a verse missing its last word.
  static Future<Uint8List> drawQuiz(int i) async {
    final lines = _lines;
    final verse = _words(lines[(i * 7 + 3) % lines.length]);
    final rnd = Random(4201 + i * 97);
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    const rect = Rect.fromLTWH(0, 0, width, height);

    c.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0A0F1F), Color(0xFF141B31), Color(0xFF1B2440)],
          ).createShader(rect));
    // A warm glow where the thread begins, as if the first star lit it.
    c.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.7, -0.5),
            radius: 0.9,
            colors: [
              AppColors.gold.withValues(alpha: 0.16),
              AppColors.gold.withValues(alpha: 0),
            ],
          ).createShader(rect));

    for (var s = 0; s < 150; s++) {
      final p = Offset(rnd.nextDouble() * width, rnd.nextDouble() * height);
      final r = 0.5 + rnd.nextDouble() * 1.3;
      final warm = rnd.nextDouble() < 0.18;
      c.drawCircle(
          p,
          r,
          Paint()
            ..color = (warm ? AppColors.goldBright : const Color(0xFFE8ECF6))
                .withValues(alpha: 0.15 + rnd.nextDouble() * 0.6));
    }

    // The thread: six stars across the left half, joined in order.
    final nodes = <Offset>[];
    for (var k = 0; k < 6; k++) {
      nodes.add(Offset(
        64 + k * 52 + rnd.nextDouble() * 28,
        110 + rnd.nextDouble() * 260,
      ));
    }
    final thread = Paint()
      ..color = AppColors.gold.withValues(alpha: 0.55)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    for (var k = 0; k < nodes.length - 1; k++) {
      c.drawLine(nodes[k], nodes[k + 1], thread);
    }
    for (final n in nodes) {
      c.drawCircle(
          n,
          14,
          Paint()
            ..shader = RadialGradient(colors: [
              AppColors.goldBright.withValues(alpha: 0.55),
              AppColors.goldBright.withValues(alpha: 0),
            ]).createShader(Rect.fromCircle(center: n, radius: 14)));
      c.drawCircle(n, 3.2, Paint()..color = AppColors.goldBright);
    }

    // The verse, its last word held back behind a gold blank — on one
    // line, the size stepping down until it fits: a blank left alone on
    // a second line reads as a layout fault, not a question.
    final shown = verse.sublist(0, verse.length - 1).join(' ');
    final missing = verse.last;
    const measure = 500.0;
    late ui.Paragraph para;
    late double size;
    for (size = 48; size >= 32; size -= 4) {
      final quran = ui.TextStyle(
        color: const Color(0xFFF3EEE2),
        fontFamily: 'HafsUthmani',
        fontSize: size,
        height: 1.9,
      );
      final b = ui.ParagraphBuilder(ui.ParagraphStyle(
        textDirection: TextDirection.rtl,
        textAlign: TextAlign.center,
        maxLines: 2,
      ))
        ..pushStyle(quran)
        ..addText('$shown ')
        ..addPlaceholder(_measure(missing, quran) + 28, size * 1.05,
            ui.PlaceholderAlignment.middle);
      para = b.build()..layout(const ui.ParagraphConstraints(width: measure));
      if (para.computeLineMetrics().length == 1) break;
    }
    final top = (height - para.height) / 2;
    const left = width - measure - 36;
    c.drawParagraph(para, const Offset(left, 0).translate(0, top));
    for (final box in para.getBoxesForPlaceholders()) {
      final r = RRect.fromRectAndRadius(
          box.toRect().shift(Offset(left, top)).deflate(2),
          const Radius.circular(10));
      c.drawRRect(r, Paint()..color = AppColors.gold.withValues(alpha: 0.18));
      c.drawRRect(
          r,
          Paint()
            ..color = AppColors.goldBright
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    }
    return _png(rec);
  }

  // ---- the reel ------------------------------------------------------

  /// A scene from the library with a verse set on it, as a reel would.
  static Future<Uint8List> drawReel(int i) async {
    final lines = _lines;
    final verse = lines[(i * 11 + 5) % lines.length];
    final (scene, bandAt) = scenes[i];
    final data = await rootBundle.load('assets/backgrounds/$scene.jpg');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List(),
        targetWidth: width.toInt());
    final photo = (await codec.getNextFrame()).image;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    const rect = Rect.fromLTWH(0, 0, width, height);

    final ph = photo.height.toDouble(), pw = photo.width.toDouble();
    final bandH = pw * height / width;
    final bandTop = ((ph - bandH) * bandAt).clamp(0.0, ph - bandH);
    c.drawImageRect(photo, Rect.fromLTWH(0, bandTop, pw, bandH), rect,
        Paint()..filterQuality = FilterQuality.high);
    photo.dispose();
    c.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF05070D).withValues(alpha: 0.10),
              const Color(0xFF05070D).withValues(alpha: 0.28),
              const Color(0xFF05070D).withValues(alpha: 0.55),
            ],
          ).createShader(rect));
    // A soft pool of shade behind the line, so gold reads on any scene
    // without the whole picture going dark.
    c.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            radius: 0.75,
            colors: [
              const Color(0xFF05070D).withValues(alpha: 0.55),
              const Color(0xFF05070D).withValues(alpha: 0),
            ],
          ).createShader(rect));

    final b = ui.ParagraphBuilder(ui.ParagraphStyle(
      textDirection: TextDirection.rtl,
      textAlign: TextAlign.center,
      maxLines: 2,
    ))
      ..pushStyle(ui.TextStyle(
        color: AppColors.goldBright,
        fontFamily: 'HafsUthmani',
        fontSize: 44,
        height: 1.9,
        shadows: const [
          Shadow(color: Color(0xCC000000), blurRadius: 18),
        ],
      ))
      ..addText(verse);
    final para = b.build()..layout(const ui.ParagraphConstraints(width: 820));
    final top = (height - para.height) / 2 - 8;
    c.drawParagraph(para, Offset((width - 820) / 2, top));
    // A short rule under the verse, the way the reel's own card closes.
    final y = top + para.height + 6;
    c.drawLine(Offset(width / 2 - 34, y), Offset(width / 2 + 34, y),
        Paint()
          ..color = AppColors.gold.withValues(alpha: 0.8)
          ..strokeWidth = 1.4);
    return _png(rec);
  }

  // ---- one's own: the share notifications ---------------------------

  /// The user's own "Your verses" card as a notification picture: the
  /// sun with their verses burning on it, in the night it stands in on
  /// the card. Kept under [key], which moves when what it shows does,
  /// and the one before it let go. Null when it can't be drawn.
  static Future<String?> versesPath(VerseLight light, String key) =>
      _own('verses', key, () => drawVerses(light));

  /// The round a share notification offers: its score in gold over the
  /// thread of its answers, lit where they were right.
  static Future<String?> roundPath(String id, int score, List<bool> right) =>
      _own('round', id, () => drawRound(score, right));

  static Future<String?> _own(
      String kind, String key, Future<Uint8List> Function() draw) async {
    try {
      final dir = Directory(
          '${(await getApplicationSupportDirectory()).path}/notification_art'
          '/v$version/own');
      final f = File('${dir.path}/${kind}_$key.png');
      if (f.existsSync() && f.lengthSync() > 0) return f.path;
      dir.createSync(recursive: true);
      // A window is laid whole, so the picture the last one used is no
      // one's once this one is drawn.
      for (final old in dir.listSync()) {
        if (old is File && old.uri.pathSegments.last.startsWith('${kind}_')) {
          try {
            old.deleteSync();
          } catch (_) {}
        }
      }
      final png = await draw();
      final tmp = File('${f.path}.part');
      await tmp.writeAsBytes(png, flush: true);
      tmp.renameSync(f.path);
      return f.path;
    } catch (e, st) {
      rlogError('notification art $kind $key', e, st);
      return null;
    }
  }

  /// The card's night, and the sun on it as tall as the picture: the
  /// big picture crops to the middle, and the middle is the sun.
  static Future<Uint8List> drawVerses(VerseLight light) async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    const rect = Rect.fromLTWH(0, 0, width, height);
    _night(c, rect, seed: 11);
    c.drawRect(
        rect,
        Paint()
          ..shader = const RadialGradient(
            radius: 0.62,
            colors: [Color(0x3DD4A947), Color(0x146E50A0), Color(0x00000000)],
            stops: [0, 0.45, 1],
          ).createShader(rect));
    const side = height - 20;
    c.save();
    c.translate((width - side) / 2, 10);
    QuranSun.paintStill(c, const Size(side, side), light);
    c.restore();
    return _png(rec);
  }

  /// The score, large and gold, and under it the round's answers as a
  /// thread of stars: bright where right, faint where not.
  static Future<Uint8List> drawRound(int score, List<bool> right) async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    const rect = Rect.fromLTWH(0, 0, width, height);
    _night(c, rect, seed: 4201);
    c.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(0, -0.15),
            radius: 0.7,
            colors: [
              AppColors.gold.withValues(alpha: 0.2),
              AppColors.gold.withValues(alpha: 0),
            ],
          ).createShader(rect));

    final b = ui.ParagraphBuilder(ui.ParagraphStyle(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 1,
    ))
      ..pushStyle(ui.TextStyle(
        fontFamily: 'CormorantGaramond',
        fontSize: 168,
        fontWeight: FontWeight.w600,
        fontVariations: const [ui.FontVariation('wght', 600)],
        fontFeatures: const [ui.FontFeature.liningFigures()],
        height: 1,
        foreground: Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFF2CE), Color(0xFFEEC96B), Color(0xFFC9973B)],
          ).createShader(const Rect.fromLTWH(0, 70, width, 180)),
        shadows: [
          Shadow(color: AppColors.gold.withValues(alpha: 0.45), blurRadius: 28),
        ],
      ))
      ..addText('$score');
    final para = b.build()..layout(const ui.ParagraphConstraints(width: width));
    c.drawParagraph(para, const Offset(0, 74));

    // The answers, one star each, across the foot.
    final n = right.length;
    if (n > 0) {
      const y = 372.0;
      final span = min(640.0, 64.0 * (n - 1));
      final x0 = (width - span) / 2;
      final step = n == 1 ? 0.0 : span / (n - 1);
      final thread = Paint()
        ..color = AppColors.gold.withValues(alpha: 0.4)
        ..strokeWidth = 1.6;
      if (n > 1) c.drawLine(Offset(x0, y), Offset(x0 + span, y), thread);
      for (var k = 0; k < n; k++) {
        final p = Offset(x0 + step * k, y);
        if (right[k]) {
          c.drawCircle(
              p,
              16,
              Paint()
                ..shader = RadialGradient(colors: [
                  AppColors.goldBright.withValues(alpha: 0.6),
                  AppColors.goldBright.withValues(alpha: 0),
                ]).createShader(Rect.fromCircle(center: p, radius: 16)));
          c.drawCircle(p, 6, Paint()..color = AppColors.goldBright);
        } else {
          c.drawCircle(p, 5.5, Paint()..color = const Color(0xFF0B1020));
          c.drawCircle(
              p,
              5.5,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.4
                ..color = const Color(0xFF9BA3AE).withValues(alpha: 0.6));
        }
      }
    }
    return _png(rec);
  }

  /// A night sky to stand a picture on: the card's blues and a seeded
  /// sprinkle of stars, the same stars every time.
  static void _night(Canvas c, Rect rect, {required int seed}) {
    c.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0E1424), Color(0xFF090D18), Color(0xFF05070D)],
          ).createShader(rect));
    final rnd = Random(seed);
    for (var s = 0; s < 130; s++) {
      final p = Offset(rnd.nextDouble() * rect.width, rnd.nextDouble() * rect.height);
      final warm = rnd.nextDouble() < 0.16;
      c.drawCircle(
          p,
          0.5 + rnd.nextDouble() * 1.2,
          Paint()
            ..color = (warm ? AppColors.goldBright : const Color(0xFFE8ECF6))
                .withValues(alpha: 0.12 + rnd.nextDouble() * 0.5));
    }
  }

  // ---- shared ----------------------------------------------------------

  static double _measure(String text, ui.TextStyle style) {
    final b = ui.ParagraphBuilder(ui.ParagraphStyle(
      textDirection: TextDirection.rtl,
    ))
      ..pushStyle(style)
      ..addText(text);
    final p = b.build()..layout(const ui.ParagraphConstraints(width: 2000));
    return p.maxIntrinsicWidth;
  }

  static Future<Uint8List> _png(ui.PictureRecorder rec) async {
    final picture = rec.endRecording();
    await OnScreen.settle('notification art');
    final image = await picture.toImage(width.toInt(), height.toInt());
    picture.dispose();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return bytes!.buffer.asUint8List();
  }
}
