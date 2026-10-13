import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import '../theme/app_theme.dart';
import 'debug_log.dart';
import 'quran_verses.dart';
import 'reminder_copy.dart';

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
    final image = await picture.toImage(width.toInt(), height.toInt());
    picture.dispose();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return bytes!.buffer.asUint8List();
  }
}
