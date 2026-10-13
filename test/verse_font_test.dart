import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/models.dart';
import 'package:ayah_reels/data/verse_font.dart';
import 'package:ayah_reels/data/verse_translation.dart';
import 'package:ayah_reels/state/creation_state.dart'
    show TextPreset, versePalette;
import 'package:ayah_reels/theme/app_theme.dart';
import 'package:ayah_reels/widgets/ayah_overlay.dart';

/// The typography, measured rather than asserted.
///
/// A font picker is only worth having if the faces it offers are
/// *aligned* — the same nominal size on every one of them, and a line
/// box none of them spills out of. Both of those are numbers in
/// [VerseFace] and [TranslationFace] derived from the files
/// themselves, and the only honest way to check a derived number is to
/// lay real text out in the real face and measure what comes back.
///
/// So this loads the bundled ttfs into the test's font collection —
/// they are declared in pubspec.yaml and served by rootBundle, exactly
/// as they are on a device — and shapes with them.
///
/// `tool/verify_fonts.py` is the other half of this: it checks the
/// same faces against all 6236 verses and every translation edition
/// for glyph coverage, which needs the network and therefore cannot
/// live here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Every family the app declares, loaded once.
  ///
  /// Read out of pubspec.yaml rather than listed here, and that is the
  /// point: the app ships sixty-odd faces now, and a hand-written list
  /// beside them is a list that silently stops covering the ones added
  /// after it. Anything declared is loaded; anything loaded is
  /// measured by the tests below.
  setUpAll(() async {
    final pubspec = File('pubspec.yaml').readAsLinesSync();
    final families = <String, List<String>>{};
    String? family;
    for (final line in pubspec) {
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
    expect(families.length, greaterThan(20),
        reason: 'the fonts block of pubspec.yaml was not understood');
    for (final entry in families.entries) {
      expect(entry.value, isNotEmpty,
          reason: '${entry.key} declares no file');
      final loader = FontLoader(entry.key);
      for (final path in entry.value) {
        loader.addFont(rootBundle.load(path));
      }
      await loader.load();
    }
  });

  /// Lays [text] out in [style] and answers its painted size.
  Size measure(String text, TextStyle style,
      {double width = 1080, TextDirection dir = TextDirection.rtl}) {
    final p = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: dir,
      textAlign: TextAlign.center,
    )..layout(maxWidth: width);
    return Size(p.width, p.height);
  }

  group('the verse faces', () {
    // Two lines of real Quranic text, marks and all.
    const line = 'ٱلْحَمْدُ لِلَّهِ رَبِّ ٱلْعَٰلَمِينَ';

    test('every face the app names is declared and on disk', () async {
      // A family with no file behind it lays out in the fallback, and
      // the fallback's metrics are identical for all of them — which
      // is exactly the failure this whole group exists to catch. It is
      // also the one failure that cannot be caught by loading the
      // fonts by hand, as the rest of this file does: `pubspec.yaml`
      // is what registers them on a device.
      // Off disk, not out of the bundle: pubspec.yaml is the manifest
      // that builds the bundle, so it is never in it.
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final declared = RegExp(r'- family:\s*(\S+)')
          .allMatches(pubspec)
          .map((m) => m.group(1))
          .toSet();
      final assets = RegExp(r'- asset:\s*(\S+)')
          .allMatches(pubspec)
          .map((m) => m.group(1)!)
          .toSet();
      for (final family in [
        for (final f in VerseFace.values) ...[f.family, ...f.fallback],
        for (final f in TranslationFace.values) ...[f.family, ...f.fallback],
      ]) {
        expect(declared, contains(family),
            reason: '$family is not declared in pubspec.yaml');
      }
      for (final path in assets) {
        final bytes = await rootBundle.load(path);
        expect(bytes.lengthInBytes, greaterThan(1000),
            reason: '$path is not a font');
      }
    });

    test('every face sets the verse at the same size', () {
      final ref = measure(line, AppTheme.quran(size: 64), width: 4000);
      for (final f in VerseFace.values) {
        final got = measure(line, AppTheme.quran(size: 64, face: f),
            width: 4000);
        // Width is the size factor alone — the advance of the same
        // glyphs, with no leading in it — so this is the tight one,
        // and it is the whole claim [VerseFace.sizeFactor] makes.
        //
        // Some faces are allowed more room, and in every case the
        // reason is the face rather than the number — the factor
        // normalises *ink height*, and two faces of the same letter
        // height can still set to different widths:
        //
        //  * Kufi is geometric rather than cursive, at every weight.
        //    At the height of a naskh it is a genuinely different line.
        //  * Amiri Text is Amiri Quran's own letters without the
        //    spacing a mushaf's raised marks need, so it sets the same
        //    verse tighter than the cut beside it; its bold, tighter
        //    still.
        //  * Weight and width move the advance and not the ink height:
        //    Noto Sans Black sets wider than its regular, and the
        //    ExtraCondensed cut — drawn narrow on purpose — narrower.
        //  * Estedad is a Persian sans on geometric lines, and sets
        //    as wide as the kufi does.
        //
        // Every face cut in the same tradition as the mushaf's own is
        // held to a tenth.
        const wider = {
          VerseFace.kufi,
          VerseFace.kufiThin,
          VerseFace.kufiBold,
          VerseFace.amiriText,
          VerseFace.amiriBold,
          VerseFace.notoSansBlack,
          VerseFace.notoSansNarrow,
          VerseFace.estedad,
        };
        expect(got.width / ref.width,
            closeTo(1.0, wider.contains(f) ? 0.25 : 0.15),
            reason: '${f.label} sets the verse at the wrong size');
        // Height carries the line box too, so Amiri stands a little
        // taller: its own file asks for a line two and a half times
        // its size, and lines that overlap are worse than lines that
        // breathe.
        expect(got.height / ref.height, closeTo(1.0, 0.20),
            reason: '${f.label} leads the verse far off the mushaf face');
      }
    });

    test('no face is set tighter than its own line box', () {
      // Two lines: if the leading is short of what the face declares,
      // the second line's marks climb into the first and the pair is
      // shorter than twice one line. Every face here must be at least
      // that tall.
      for (final f in VerseFace.values) {
        final style = AppTheme.quran(size: 40, face: f);
        final one = measure(line, style, width: 2000).height;
        final two = measure('$line\n$line', style, width: 2000).height;
        expect(two, greaterThanOrEqualTo(one * 2 - 0.5),
            reason: '${f.label} runs its lines into each other');
        expect(f.height, greaterThanOrEqualTo(1.2));
        expect(f.sizeFactor, inInclusiveRange(0.5, 2.0));
      }
    });

    test('a face actually changes the shaping, not just the name', () {
      final widths = {
        for (final f in VerseFace.values)
          f: measure(line, AppTheme.quran(size: 64, face: f), width: 4000).width
      };
      // If the fonts had not loaded, every one of these would be the
      // fallback's width to the pixel.
      expect(widths.values.toSet().length, VerseFace.values.length,
          reason: 'two faces shaped the same line identically');
    });
  });

  group('the translation faces', () {
    test('each script offers only its own faces, default first', () {
      final latin = TranslationFace.forScript(arabicScript: false);
      final arabic = TranslationFace.forScript(arabicScript: true);
      expect(latin, isNotEmpty);
      expect(arabic, isNotEmpty);
      expect(latin.every((f) => !f.arabicScript), isTrue);
      expect(arabic.every((f) => f.arabicScript), isTrue);
      expect(latin.first, TranslationFace.defaultFor(arabicScript: false));
      expect(arabic.first, TranslationFace.defaultFor(arabicScript: true));
      // Every face is on exactly one of the two lists.
      expect(latin.length + arabic.length, TranslationFace.values.length);
    });

    test('the Latin faces set the line at the same size', () {
      const line = 'All praise is due to Allah, Lord of the worlds.';
      final ref = measure(line, AppTheme.translation(size: 30),
              dir: TextDirection.ltr)
          .height;
      for (final f in TranslationFace.forScript(arabicScript: false)) {
        final h = measure(line, AppTheme.translation(size: 30, face: f),
                dir: TextDirection.ltr)
            .height;
        // Looser than the verse's, and deliberately: these are
        // normalised on x-height, which is what the eye reads a text
        // face by, and a serif at Inter's x-height is genuinely a
        // taller object than Inter is.
        expect(h / ref, closeTo(1.0, 0.25), reason: '${f.label} is off');
      }
    });

    test('Nastaliq is given the room it asks for', () {
      // The one face here whose own line box is two and a half times
      // its size. Set at a naskh's leading it would be unreadable, so
      // the number is pinned rather than left to drift.
      expect(TranslationFace.nastaliq.height, greaterThanOrEqualTo(2.4));
      // One short word, so this is the line box and not the line
      // count: Nastaliq is a good deal narrower than a naskh and fits
      // more on a line, which would otherwise hide a leading that is
      // far too tight behind a block that happens to be shorter.
      const word = 'اللہ';
      final plain = measure(word, AppTheme.translation(size: 30, arabic: true),
          width: 600);
      final nast = measure(
          word,
          AppTheme.translation(
              size: 30, face: TranslationFace.nastaliq, arabic: true),
          width: 600);
      expect(nast.height, greaterThan(plain.height));
      // And it must not run away with the card either: a face given
      // two and a half times its size as a line box is one bad number
      // away from a translation taller than the frame.
      expect(nast.height, lessThan(plain.height * 1.7));
    });

    test('a name from a build that offered something else falls back', () {
      expect(TranslationFace.fromName('nastaliq', arabicScript: false),
          TranslationFace.inter);
      expect(TranslationFace.fromName('cormorant', arabicScript: true),
          TranslationFace.plex);
      expect(TranslationFace.fromName(null, arabicScript: false),
          TranslationFace.inter);
      expect(VerseFace.fromName('something-else'), VerseFace.uthmani);
    });

    test('the pair is resolved by the edition, not by the reel', () {
      const pair = (
        verse: VerseFace.amiri,
        latin: TranslationFace.spectral,
        arabic: TranslationFace.nastaliq,
      );
      ReelTypography of(VerseTranslation t) => ReelTypography.of(
            verse: pair.verse,
            latin: pair.latin,
            arabicScript: pair.arabic,
            edition: t,
          );
      expect(of(VerseTranslation.english).translation,
          TranslationFace.spectral);
      expect(of(VerseTranslation.german).translation, TranslationFace.spectral);
      expect(of(VerseTranslation.urdu).translation, TranslationFace.nastaliq);
      // And the key changes with it, so a card rasterized for one
      // edition is never served for the other.
      expect(of(VerseTranslation.english).key,
          isNot(of(VerseTranslation.urdu).key));
    });
  });

  group('the card', () {
    const ayah = Ayah(
      number: 2,
      arabic: 'ٱلْحَمْدُ لِلَّهِ رَبِّ ٱلْعَٰلَمِينَ',
      translation: 'All praise is due to Allah, Lord of the worlds.',
    );

    testWidgets('every pair of faces lays out without overflowing',
        (t) async {
      for (final v in VerseFace.values) {
        for (final f in TranslationFace.forScript(arabicScript: false)) {
          await t.pumpWidget(MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 360,
                  child: AyahOverlay(
                    ayah: ayah,
                    width: 360,
                    verseFace: v,
                    translationFace: f,
                    preset: TextPreset.classic,
                  ),
                ),
              ),
            ),
          ));
          await t.pump();
          expect(t.takeException(), isNull,
              reason: '${v.label} + ${f.label} overflowed');
        }
      }
    });

    testWidgets('the accent colours the rule and the lit word', (t) async {
      const accent = Color(0xFF5BC0C6);
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Center(
            child: AyahOverlay(
              ayah: ayah,
              width: 360,
              accent: accent,
              highlightTokens: (start: 0, end: 1),
            ),
          ),
        ),
      ));
      await t.pump();
      final rule = t.widget<Container>(find.byKey(AyahOverlay.dividerKey));
      final gradient =
          (rule.decoration as BoxDecoration).gradient as LinearGradient;
      expect(gradient.colors[1].toARGB32() & 0xFFFFFF,
          accent.toARGB32() & 0xFFFFFF);
      expect(
          AyahOverlay.highlightColorFor(Colors.white, accent: accent), accent);
    });

    test('an accent too close to the verse gives way to the contrast', () {
      // Bright gold on bright gold is the case the old equality test
      // caught; the deeper gold on the bright one is the same case
      // with different literals, and must be caught too.
      expect(
          AyahOverlay.highlightColorFor(const Color(0xFFEEC96B),
              accent: const Color(0xFFEEC96B)),
          Colors.white);
      expect(
          AyahOverlay.highlightColorFor(const Color(0xFFEEC96B),
              accent: const Color(0xFFD4A947)),
          Colors.white);
      // Two colours anybody would call different stay as chosen.
      expect(
          AyahOverlay.highlightColorFor(const Color(0xFF9FE8C9),
              accent: const Color(0xFFEEC96B)),
          const Color(0xFFEEC96B));
    });

    test('a refused accent never lands on the verse’s own colour', () {
      // The case the first fix walked into: white ink and a sand
      // accent are near enough that the accent is refused, and the
      // contrast colour for darkened scenery is white — the colour
      // the verse is already set in. Every pair in the palette has to
      // come back as something you can see.
      for (final ink in versePalette) {
        for (final accent in versePalette) {
          for (final onLight in [false, true]) {
            final lit = AyahOverlay.highlightColorFor(Color(ink),
                onLight: onLight, accent: Color(accent));
            expect(lit.toARGB32(), isNot(ink),
                reason: 'ink ${ink.toRadixString(16)} + accent '
                    '${accent.toRadixString(16)}: the lit word is the '
                    'same colour as the rest of the verse');
          }
        }
      }
    });
  });
}
