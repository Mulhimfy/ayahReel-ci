import 'dart:io';

import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ayah_reels/data/card_compose.dart';
import 'package:ayah_reels/data/card_deck.dart';
import 'package:ayah_reels/data/card_style.dart';
import 'package:ayah_reels/data/dedication.dart';
import 'package:ayah_reels/data/reel_effects.dart';
import 'package:ayah_reels/render/card_exporter.dart';

/// Draws real cards on a desk, so they can be looked at without a
/// phone. Not a test of anything: it is skipped unless it is pointed
/// somewhere.
///
///   CARD_PREVIEW_OUT=/tmp/cards flutter test test/tools/card_preview_test.dart
///
/// One card per template in each shape, plus the finishes and the
/// frames on the two grounds that are hardest to read on. What it is
/// for is the question no test can answer: does it look like something
/// somebody would post.
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

void main() {
  final out = Platform.environment['CARD_PREVIEW_OUT'];
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('card preview', (t) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    // Every family the app declares, read out of pubspec.yaml — a
    // hand-written list beside sixty faces is a list that stops
    // covering the ones added after it, and a face that is not loaded
    // draws a wall of tofu boxes that looks exactly like a broken
    // font rather than a broken harness.
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
    for (final entry in families.entries) {
      final loader = FontLoader(entry.key);
      for (final path in entry.value) {
        loader.addFont(rootBundle.load(path));
      }
      await loader.load();
    }
    PathProviderPlatform.instance = _Tmp(out!);

    const ayah = 'وَقُل رَّبِّ زِدْنِى عِلْمًا';
    const translation = 'And say, "My Lord, increase me in knowledge."';
    const hadith = 'لَا يُؤْمِنُ أَحَدُكُمْ حَتَّى يُحِبَّ لِأَخِيهِ '
        'مَا يُحِبُّ لِنَفْسِهِ';
    const long = 'ٱللَّهُ لَآ إِلَٰهَ إِلَّا هُوَ ٱلْحَىُّ ٱلْقَيُّومُ ۚ '
        'لَا تَأْخُذُهُۥ سِنَةٌ وَلَا نَوْمٌ';

    await t.runAsync(() async {
      Future<void> write(String name, CardDeck deck) async {
        final files = await CardExporter.render(deck);
        for (var i = 0; i < files.length; i++) {
          final to = File('$out/$name${files.length > 1 ? '_$i' : ''}.png');
          await files[i].copy(to.path);
        }
      }

      // Every designed start, in the shape a post is made in.
      for (final template in CardTemplate.values) {
        await write(
          'template_${template.name}',
          CardCompose.deck(
            CardCompose.quote(
              id: 'x',
              text: ayah,
              translation: translation,
              reference: 'Ta-Ha · 20:114',
              format: CardFormat.portrait,
              template: template,
              quran: true,
            ),
          ),
        );
      }

      // The same words in all three shapes.
      for (final format in CardFormat.values) {
        await write(
          'shape_${format.name}',
          CardCompose.deck(
            CardCompose.quote(
              id: 'x',
              text: long,
              translation:
                  'Allah — there is no deity except Him, the Ever-Living, '
                      'the Sustainer of existence. Neither drowsiness '
                      'overtakes Him nor sleep.',
              reference: 'Al-Baqarah · 2:255',
              format: format,
              quran: true,
            ),
            format: format,
          ),
        );
      }

      // Every frame, on the ground that shows a frame worst.
      for (final frame in CardFrame.values) {
        final slide = CardCompose.quote(
          id: 'x',
          text: hadith,
          reference: 'Sahih al-Bukhari 13',
          format: CardFormat.square,
          template: CardTemplate.quiet,
        );
        await write(
          'frame_${frame.name}',
          CardCompose.deck(slide.copyWith(frame: frame),
              format: CardFormat.square),
        );
      }

      // Every finish, on a paper where a shadow has nowhere to hide.
      for (final skin in CardSkin.values) {
        final slide = CardCompose.quote(
          id: 'x',
          text: ayah,
          translation: translation,
          format: CardFormat.square,
          template: CardTemplate.gilded,
          quran: true,
        );
        await write(
          'skin_${skin.name}',
          CardCompose.deck(
            slide.copyWith(
              blocks: [for (final b in slide.blocks) b.copyWith(skin: skin)],
            ),
            format: CardFormat.square,
          ),
        );
      }

      // And the grade, over a paper so the effect is the only thing
      // changing.
      await write(
        'finish_graded',
        CardCompose.deck(
          CardCompose.quote(
            id: 'x',
            text: ayah,
            translation: translation,
            reference: 'Ta-Ha · 20:114',
            format: CardFormat.portrait,
            template: CardTemplate.mihrab,
            effects: const ReelEffects(vignette: 0.55, grain: 0.6),
            quran: true,
          ),
        ),
      );

      // Every face the composer offers, setting the same verse — the
      // only honest way to look at a type list.
      for (final face in CardFace.values) {
        final rtl = face.arabicScript;
        final slide = CardCompose.quote(
          id: 'x',
          text: rtl ? ayah : 'And say, "My Lord, increase me in knowledge."',
          reference: face.label,
          format: CardFormat.square,
          template: CardTemplate.page,
          quran: rtl,
        );
        await write(
          'face_${face.name}',
          CardCompose.deck(
            slide.copyWith(blocks: [
              slide.blocks.first.copyWith(face: face),
              ...slide.blocks.skip(1),
            ]),
            format: CardFormat.square,
          ),
        );
      }

      // Made for somebody: the line above the mark, both intentions.
      for (final kind in DedicationKind.values) {
        await write(
          'dedication_${kind.name}',
          CardDeck(
            id: 'd',
            format: CardFormat.portrait,
            slides: [
              CardCompose.quote(
                id: 'x',
                text: ayah,
                translation: translation,
                reference: 'Ta-Ha · 20:114',
                format: CardFormat.portrait,
                quran: true,
              ),
            ],
            createdAt: DateTime(2026, 3, 12),
            updatedAt: DateTime(2026, 3, 12),
            dedication: Dedication(kind: kind, name: 'Maryam bint Ahmad'),
          ),
        );
      }

      // A card re-cut for a story.
      for (final template in [CardTemplate.page, CardTemplate.classic]) {
        final deck = CardDeck(
          id: 'd',
          format: CardFormat.portrait,
          slides: [
            CardCompose.quote(
              id: 'x',
              text: ayah,
              translation: translation,
              reference: 'Ta-Ha · 20:114',
              format: CardFormat.portrait,
              template: template,
              quran: true,
            ),
          ],
          createdAt: DateTime(2026, 3, 12),
          updatedAt: DateTime(2026, 3, 12),
        );
        final story = CardExporter.prepare(deck, asStory: true);
        await write('story_${template.name}',
            CardCompose.deck(story.slides.first, format: story.format));
      }

      // A carousel: one passage across three cards.
      final pieces = CardCompose.paginate(
        'Allah does not burden a soul beyond what it can bear. It will '
        'have the consequence of what good it has gained, and it will '
        'bear the consequence of what evil it has earned. Our Lord, do '
        'not impose blame upon us if we have forgotten or erred.',
      );
      await write(
        'carousel',
        CardDeck(
          id: 'd',
          format: CardFormat.portrait,
          slides: [
            for (final piece in pieces)
              CardCompose.quote(
                id: piece.hashCode.toString(),
                text: piece,
                format: CardFormat.portrait,
                template: CardTemplate.page,
              ),
          ],
          createdAt: DateTime(2026, 3, 12),
          updatedAt: DateTime(2026, 3, 12),
        ),
      );
    });
    for (var e = t.takeException(); e != null; e = t.takeException()) {
      if (!e.toString().contains('allowRuntimeFetching')) throw e;
    }
  }, skip: out == null);
}
