import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ayah_reels/data/band_glow.dart';
import 'package:ayah_reels/data/models.dart';
import 'package:ayah_reels/data/verse_font.dart';
import 'package:ayah_reels/data/verse_ink.dart';
import 'package:ayah_reels/data/verse_lines.dart';
import 'package:ayah_reels/data/verse_motion.dart';
import 'package:ayah_reels/data/verse_numbering.dart';
import 'package:ayah_reels/data/verse_translation.dart';
import 'package:ayah_reels/data/word_align_service.dart';
import 'package:ayah_reels/render/ayah_rasterizer.dart';
import 'package:ayah_reels/render/verse_planner.dart';
import 'package:ayah_reels/render/video_renderer.dart';
import 'package:ayah_reels/state/creation_state.dart' show TextPreset;
import 'package:ayah_reels/widgets/surah_title.dart';
import 'package:ayah_reels/widgets/verse_stage.dart';

/// The export of a reel whose long verses go line by line and move,
/// made by the real cards and the real command builder, for a desktop
/// FFmpeg to run: Ayat al-Kursi and the verse after it, cut into lines,
/// in five motions, and once more as a new install makes it (a line at a
/// time, the light, no surah name). Beside each command, the preview's own stage drawn
/// at the same moments, so a frame of the file can be laid next to what
/// the phone showed. Not a test of anything; skipped unless pointed
/// somewhere:
///
///   EXPORT_MOTION_OUT=/tmp/motion flutter test test/tools/export_motion_tool_test.dart
///
/// Then, in that folder, `sh run.sh` encodes every reel and pulls its
/// frames (paths are rewritten to wherever the folder now is).
class _Tmp extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _Tmp(this.dir);
  final String dir;
  @override
  Future<String?> getTemporaryPath() async => dir;
  @override
  Future<String?> getApplicationSupportPath() async => dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

const _kursi = Ayah(
  number: 255,
  arabic: 'ٱللَّهُ لَآ إِلَـٰهَ إِلَّا هُوَ ٱلْحَىُّ ٱلْقَيُّومُ ۚ لَا تَأْخُذُهُۥ سِنَةٌ وَلَا نَوْمٌ ۚ لَّهُۥ مَا فِى ٱلسَّمَـٰوَٰتِ وَمَا فِى ٱلْأَرْضِ ۗ مَن ذَا ٱلَّذِى يَشْفَعُ عِندَهُۥٓ إِلَّا بِإِذْنِهِۦ ۚ يَعْلَمُ مَا بَيْنَ أَيْدِيهِمْ وَمَا خَلْفَهُمْ ۖ وَلَا يُحِيطُونَ بِشَىْءٍ مِّنْ عِلْمِهِۦٓ إِلَّا بِمَا شَآءَ ۚ وَسِعَ كُرْسِيُّهُ ٱلسَّمَـٰوَٰتِ وَٱلْأَرْضَ ۖ وَلَا يَـُٔودُهُۥ حِفْظُهُمَا ۚ وَهُوَ ٱلْعَلِىُّ ٱلْعَظِيمُ',
  translation: 'Allāh - there is no deity except Him, the Ever-Living, the Self-Sustaining. Neither drowsiness overtakes Him nor sleep. To Him belongs whatever is in the heavens and whatever is on the earth. Who is it that can intercede with Him except by His permission? He knows what is [presently] before them and what will be after them, and they encompass not a thing of His knowledge except for what He wills. His Kursī extends over the heavens and the earth, and their preservation tires Him not. And He is the Most High, the Most Great.',
);

const _next = Ayah(
  number: 256,
  arabic: 'لَآ إِكْرَاهَ فِى ٱلدِّينِ ۖ قَد تَّبَيَّنَ ٱلرُّشْدُ مِنَ ٱلْغَىِّ ۚ فَمَن يَكْفُرْ بِٱلطَّـٰغُوتِ وَيُؤْمِنۢ بِٱللَّهِ فَقَدِ ٱسْتَمْسَكَ بِٱلْعُرْوَةِ ٱلْوُثْقَىٰ لَا ٱنفِصَامَ لَهَا ۗ وَٱللَّهُ سَمِيعٌ عَلِيمٌ',
  translation: 'There shall be no compulsion in [acceptance of] the religion. The right course has become distinct from the wrong. So whoever disbelieves in ṭāghūt and believes in Allāh has grasped the most trustworthy handhold with no break in it. And Allāh is Hearing and Knowing.',
);

/// A stand-in alignment: each word its share of the verse by letters,
/// a breath after each pause sign, as a reciter would take one.
Map<int, List<WordSpan>> _alignment(Recitation rec, List<Ayah> verses) {
  final out = <int, List<WordSpan>>{};
  for (final a in verses) {
    final t = rec.timing(a.number);
    final tokens = VerseText.tokens(a.arabic);
    final words = <(int, int, bool)>[]; // letters, align index, breath after
    var w = 0;
    for (var k = 0; k < tokens.length; k++) {
      if (!VerseText.isWord(tokens[k])) continue;
      final breath = k + 1 < tokens.length &&
          !VerseText.isWord(tokens[k + 1]) &&
          VerseText.pauseAfter(tokens[k + 1]) != null;
      words.add((VerseText.letters(tokens[k]), w++, breath));
    }
    const lead = 400, tail = 300, breathMs = 650;
    final breaths = words.where((x) => x.$3).length;
    final total = words.fold<int>(0, (n, x) => n + x.$1);
    final speech = t.durationMs - lead - tail - breaths * breathMs;
    var at = lead;
    final spans = <WordSpan>[];
    for (final (letters, i, breath) in words) {
      final len = speech * letters ~/ total;
      spans.add(WordSpan(i, i + 1, at, at + (len * 0.9).round()));
      at += len + (breath ? breathMs : 0);
    }
    out[a.number] = spans;
  }
  return out;
}

void main() {
  final out = Platform.environment['EXPORT_MOTION_OUT'];

  testWidgets('export motion tool', (t) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final families = <String, List<String>>{};
    String? family;
    for (final line in File('pubspec.yaml').readAsLinesSync()) {
      final fam = RegExp(r'^\s{4}- family:\s*(\S+)').firstMatch(line);
      if (fam != null) {
        family = fam.group(1)!;
        families[family] = [];
        continue;
      }
      final asset =
          RegExp(r'^\s+- asset:\s*(assets/fonts/\S+\.ttf)').firstMatch(line);
      if (asset != null && family != null) {
        families[family]!.add(asset.group(1)!);
      }
    }
    await t.runAsync(() async {
      for (final e in families.entries) {
        final loader = FontLoader(e.key);
        for (final p in e.value) {
          loader.addFont(rootBundle.load(p));
        }
        await loader.load();
      }
    });
    PathProviderPlatform.instance = _Tmp(out!);
    t.view.physicalSize = const Size(1080, 1920);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);

    const rec = Recitation(
      reciterId: 'tool',
      surah: 2,
      audioPath: '',
      timings: [AyahTiming(255, 0, 30000), AyahTiming(256, 30000, 44000)],
    );
    final ayahs = List<Ayah>.filled(256, _kursi)..[255] = _next;
    final spans = _alignment(rec, const [_kursi, _next]);
    final windows = WordAlignService.highlightPlan(
      recitation: rec,
      ayahs: ayahs,
      spansByAyah: spans,
      startAyah: 255,
      endAyah: 256,
    );
    final times = VersePlanner.wordTimes(ayahs, spans, 255, 256);
    const look = VerseLook(
      textScale: 1,
      preset: TextPreset.classic,
      typography: ReelTypography(),
      edition: VerseTranslation.english,
      numbering: VerseNumbering.mark,
      showTranslation: true,
      ink: VerseInk.none,
      surah: 2,
    );
    late VerseLinePlan plan;
    // And as a new install makes it: a line at a time.
    late VerseLinePlan single;
    await t.runAsync(() async {
      plan = await VersePlanner.plan(
        lines: 2,
        ayahs: ayahs,
        recitation: rec,
        startAyah: 255,
        endAyah: 256,
        look: look,
        words: spans,
      );
      single = await VersePlanner.plan(
        lines: 1,
        ayahs: ayahs,
        recitation: rec,
        startAyah: 255,
        endAyah: 256,
        look: look,
        words: spans,
      );
    });
    final report = StringBuffer()
      ..writeln('highlight windows: ${windows?.values.fold<int>(0, (n, l) => n + l.length)}');
    for (final (name, lp) in [('two lines', plan), ('one line', single)]) {
      report.writeln('---- $name');
      for (final e in lp.byAyah.entries) {
        for (final p in e.value) {
          report.writeln('${e.key}.${p.index}/${p.count} '
              '${p.startMs}-${p.endMs} fit ${p.fit.toStringAsFixed(3)} '
              'h ${p.height}\n  ${p.arabic}\n  ${p.translation}');
        }
      }
    }
    File('$out/plan.txt').writeAsStringSync(report.toString());

    late String bg;
    await t.runAsync(() async {
      bg = (await AyahRasterizer.rasterizeGradientBackdrop(
              const [0xFF0E1A2E, 0xFF5B4630]))
          .path;
    });

    // Each reel: its motion, its cut, and whether it carries the
    // surah's name. 'defaults' is what a new install makes: a line at a
    // time, the light, the highlight, no name.
    final scenarios = <String, (VerseMotion, VerseLinePlan, bool)>{
      'still': (VerseMotion.none, plan, true),
      'thread': (MotionPreset.thread.motion, plan, true),
      'light': (MotionPreset.light.motion, plan, true),
      'gilded': (MotionPreset.gilded.motion, plan, true),
      'unveil': (MotionPreset.unveil.motion, plan, true),
      'defaults': (VerseMotion.standard, single, false),
      // And as a reel was made before: whole verses, still, untitled.
      'before': (VerseMotion.none, VerseLinePlan.empty, false),
    };
    // The preview's stage, at the same moments as the frames to pull.
    final clock = ValueNotifier<int>(0);
    final key = GlobalKey();
    for (final s in scenarios.entries) {
      if (s.key == 'still' || s.key == 'unveil' || s.key == 'before') {
        continue;
      }
      final (motion, cut, titled) = s.value;
      final units = VerseUnit.of(rec, 255, 256, cut);
      await t.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
          key: key,
          child: SizedBox(
            width: 1080,
            height: 1920,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Painted, not decoded: an image loaded under the
                // test's fake clock never finishes loading.
                const ColoredBox(color: Color(0xFF1A2233)),
                OverflowBox(
                  alignment: Alignment.center,
                  minHeight: 0,
                  maxHeight: double.infinity,
                  child: VerseStage(
                    clock: clock,
                    units: units,
                    ayahs: ayahs,
                    recitation: rec,
                    motion: motion,
                    words: windows,
                    highlight: true,
                    wordTimes: times,
                    width: 1080,
                    textColor: Colors.white,
                    accent: const Color(0xFFEEC96B),
                    ink: VerseInk.none,
                    accentInk: VerseInk.none,
                    textScale: 1,
                    preset: TextPreset.classic,
                    onLight: false,
                    translation: VerseTranslation.english,
                    numbering: VerseNumbering.mark,
                    showTranslation: true,
                    surah: 2,
                    verseFace: VerseFace.uthmani,
                    translationFace: TranslationFace.inter,
                    onHeight: (_) {},
                  ),
                ),
                if (titled)
                  const Positioned.fill(
                    child: ReelSurahTitle(
                      width: 1080,
                      surah: 2,
                      edition: VerseTranslation.english,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ));
      for (final ms in const [1200, 3000, 9000]) {
        clock.value = ms;
        await t.pump();
        await t.runAsync(() async {
          final b =
              key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          // Half size: a full-size frame takes the test's software
          // renderer most of a minute, and half is enough to compare.
          final image = await b.toImage(pixelRatio: 0.5);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          File('$out/stage_${s.key}_$ms.png')
              .writeAsBytesSync(data!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
    final run = StringBuffer()
      ..writeln('#!/bin/sh')
      ..writeln('set -e')
      ..writeln('cd "\$(dirname "\$0")"')
      ..writeln('HERE="\$(pwd)"');
    for (final s in scenarios.entries) {
      final (motion, cut, titled) = s.value;
      late String cmd;
      await t.runAsync(() async {
        cmd = await VideoRenderer.unitReelCommand(
          recitation: rec,
          ayahs: ayahs,
          startAyah: 255,
          endAyah: 256,
          background: bg,
          out: '$out/reel_${s.key}.mp4',
          lines: cut,
          motion: motion,
          highlight: windows,
          words: windows,
          wordTimes: times,
          numbering: VerseNumbering.mark,
          surahTitle: titled,
          fileTag: 'tool_${s.key}_',
        );
      });
      File('$out/cmd_${s.key}.txt').writeAsStringSync(cmd);
      run.writeln("ffmpeg -hide_banner -v error \$(sed \"s#$out#\$HERE#g\" "
          "cmd_${s.key}.txt | sed 's/\"//g')");
    }
    // The wide card over a luminous band, and a light in another
    // colour with the name pinched larger: the graphs those add.
    final extras = <String, Future<String> Function()>{
      'band': () => VideoRenderer.unitReelCommand(
            recitation: rec,
            ayahs: ayahs,
            startAyah: 255,
            endAyah: 256,
            background: bg,
            out: '$out/reel_band.mp4',
            lines: single,
            motion: VerseMotion.standard,
            highlight: windows,
            words: windows,
            wordTimes: times,
            numbering: VerseNumbering.mark,
            surahTitle: true,
            letterboxAspect: 16 / 9,
            band: BandGlow.aurora,
            fileTag: 'tool_band_',
          ),
      'sky': () => VideoRenderer.unitReelCommand(
            recitation: rec,
            ayahs: ayahs,
            startAyah: 255,
            endAyah: 256,
            background: bg,
            out: '$out/reel_sky.mp4',
            lines: single,
            motion: MotionPreset.gilded.motion,
            highlight: windows,
            words: windows,
            wordTimes: times,
            accentArgb: 0xFF9CC7F5,
            numbering: VerseNumbering.mark,
            surahTitle: true,
            surahTitleScale: 1.4,
            fileTag: 'tool_sky_',
          ),
    };
    for (final e in extras.entries) {
      late String cmd;
      await t.runAsync(() async => cmd = await e.value());
      File('$out/cmd_${e.key}.txt').writeAsStringSync(cmd);
      run.writeln("ffmpeg -hide_banner -v error \$(sed \"s#$out#\$HERE#g\" "
          "cmd_${e.key}.txt | sed 's/\"//g')");
    }
    File('$out/run.sh').writeAsStringSync(run.toString());

  }, skip: out == null, timeout: const Timeout(Duration(minutes: 35)));
}
