import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/card_compose.dart';
import 'package:ayah_reels/data/card_deck.dart';
import 'package:ayah_reels/data/card_style.dart';
import 'package:ayah_reels/data/reel_effects.dart';

/// The typography of a card, measured rather than asserted.
///
/// A card is a fraction of a rectangle all the way down — see the
/// header of `card_style.dart` — and the whole promise of that is that
/// the composer at 320pt and the export at 1080px are the same
/// picture, and that a card re-cut from a story to a square is still a
/// card. Neither can be checked by reading the code; both fall out of
/// laying real text out in the real faces.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    const files = {
      'HafsUthmani': ['assets/fonts/UthmanicHafs.ttf'],
      'AmiriQuran': ['assets/fonts/AmiriQuran.ttf'],
      'ScheherazadeNew': ['assets/fonts/ScheherazadeNew.ttf'],
      'NotoNaskhArabic': ['assets/fonts/NotoNaskhArabic.ttf'],
      'Lateef': ['assets/fonts/Lateef.ttf'],
      'IBMPlexSansArabic': ['assets/fonts/IBMPlexSansArabic.ttf'],
      'NotoNastaliqUrdu': ['assets/fonts/NotoNastaliqUrdu.ttf'],
      'Inter': ['assets/fonts/Inter.ttf', 'assets/fonts/InterItalic.ttf'],
      'SourceSerif4': ['assets/fonts/SourceSerif4.ttf'],
      'Spectral': ['assets/fonts/Spectral.ttf'],
      'CormorantGaramond': ['assets/fonts/CormorantGaramond.ttf'],
      'Literata': ['assets/fonts/Literata.ttf'],
      'Amiri': ['assets/fonts/Amiri.ttf'],
      'NotoKufiArabic': ['assets/fonts/NotoKufiArabic.ttf'],
      'MarkaziText': ['assets/fonts/MarkaziText.ttf'],
      'EBGaramond': ['assets/fonts/EBGaramond.ttf'],
      'LibreBaskerville': ['assets/fonts/LibreBaskerville.ttf'],
    };
    for (final entry in files.entries) {
      final loader = FontLoader(entry.key);
      for (final path in entry.value) {
        loader.addFont(rootBundle.load(path));
      }
      await loader.load();
    }
  });

  const ayah = 'وَقُل رَّبِّ زِدْنِى عِلْمًا';
  const longAyah = 'ٱللَّهُ لَآ إِلَٰهَ إِلَّا هُوَ ٱلْحَىُّ ٱلْقَيُّومُ ۚ '
      'لَا تَأْخُذُهُۥ سِنَةٌ وَلَا نَوْمٌ ۚ لَّهُۥ مَا فِى ٱلسَّمَٰوَٰتِ '
      'وَمَا فِى ٱلْأَرْضِ';
  const english = 'And say, "My Lord, increase me in knowledge."';

  /// Where a block's box lands on the card, in export pixels.
  Rect boxOf(CardTextBlock b, CardFormat f) {
    const w = CardFormat.exportWidth;
    final h = w / f.aspect;
    final height = CardCompose.heightOf(b, f);
    return Rect.fromCenter(
      center: Offset(b.x * w, b.y * h),
      width: b.width * w,
      height: height,
    );
  }

  group('a quotation becomes a card', () {
    test('every template sets the verse inside the card, every shape', () {
      for (final template in CardTemplate.values) {
        for (final format in CardFormat.values) {
          final slide = CardCompose.quote(
            id: 'x',
            text: longAyah,
            translation: english,
            reference: 'Al-Baqarah · 2:255',
            format: format,
            template: template,
            quran: true,
          );
          expect(slide.blocks, hasLength(3));
          final cardH = CardFormat.exportWidth / format.aspect;
          for (final b in slide.blocks) {
            final box = boxOf(b, format);
            expect(box.top, greaterThanOrEqualTo(0),
                reason: '${template.name}/${format.name} runs off the top');
            expect(box.bottom, lessThanOrEqualTo(cardH),
                reason:
                    '${template.name}/${format.name} runs off the bottom');
            expect(box.left, greaterThanOrEqualTo(0));
            expect(box.right, lessThanOrEqualTo(CardFormat.exportWidth));
          }
        }
      }
    });

    test('the blocks are stacked in order and never overlap', () {
      for (final format in CardFormat.values) {
        final slide = CardCompose.quote(
          id: 'x',
          text: ayah,
          translation: english,
          reference: 'Ta-Ha · 20:114',
          format: format,
          quran: true,
        );
        final boxes = [for (final b in slide.blocks) boxOf(b, format)];
        for (var i = 1; i < boxes.length; i++) {
          expect(boxes[i].top, greaterThanOrEqualTo(boxes[i - 1].bottom - 1),
              reason: '${format.name}: block $i sits on the one above it');
        }
      }
    });

    test('a short verse is set larger than a long one', () {
      final short = CardCompose.quote(
          id: 'a', text: ayah, format: CardFormat.portrait, quran: true);
      final long = CardCompose.quote(
          id: 'b', text: longAyah, format: CardFormat.portrait, quran: true);
      expect(short.blocks.first.size,
          greaterThan(long.blocks.first.size));
      // And neither is set past the range the slider can reach, or the
      // composer would open on a size it cannot show.
      for (final s in [short, long]) {
        expect(s.blocks.first.size,
            inInclusiveRange(CardTextBlock.minSize, CardTextBlock.maxSize));
      }
    });

    test('the script decides the face, and a hadith is never set in a '
        'Quran face', () {
      final verse = CardCompose.quote(
          id: 'a', text: ayah, format: CardFormat.square, quran: true);
      expect(verse.blocks.first.face.mushaf, isTrue);
      expect(verse.blocks.first.rtl, isTrue);

      final hadith = CardCompose.quote(
          id: 'b', text: 'الدِّينُ النَّصِيحَةُ', format: CardFormat.square);
      expect(hadith.blocks.first.face, CardFace.arabicProse);
      expect(hadith.blocks.first.face.mushaf, isFalse);
      expect(hadith.blocks.first.face.arabicScript, isTrue);

      final own = CardCompose.quote(
          id: 'c', text: 'Be the reason someone hears a verse today',
          format: CardFormat.square);
      expect(own.blocks.first.rtl, isFalse);
      expect(own.blocks.first.face.arabicScript, isFalse);
    });

    test('a card on a photograph is written in white and lifted off it',
        () {
      final onPhoto = CardCompose.quote(
        id: 'a',
        text: ayah,
        format: CardFormat.portrait,
        background: const CardBackground(sceneId: 'sky_pexels_01'),
        quran: true,
      );
      expect(onPhoto.blocks.first.colourArgb, 0xFFFFFFFF);
      expect(onPhoto.blocks.first.skin, isNot(CardSkin.none));

      final onPaper = CardCompose.quote(
        id: 'b',
        text: ayah,
        format: CardFormat.portrait,
        template: CardTemplate.page,
        quran: true,
      );
      expect(onPaper.blocks.first.colourArgb, CardPaper.ivory.inkArgb);
    });
  });

  group('re-cutting the card', () {
    test('a composition keeps its proportions in every other shape', () {
      final story = CardCompose.quote(
        id: 'x',
        text: longAyah,
        translation: english,
        reference: 'Al-Baqarah · 2:255',
        format: CardFormat.story,
        quran: true,
      );
      for (final to in CardFormat.values) {
        final moved = CardCompose.reshape(story, CardFormat.story, to);
        final cardH = CardFormat.exportWidth / to.aspect;
        for (var i = 0; i < moved.blocks.length; i++) {
          final box = boxOf(moved.blocks[i], to);
          expect(box.top, greaterThanOrEqualTo(-1),
              reason: '${to.name}: block $i runs off the top');
          expect(box.bottom, lessThanOrEqualTo(cardH + 1),
              reason: '${to.name}: block $i runs off the bottom');
        }
        // The order of the stack survives the move.
        final ys = [for (final b in moved.blocks) b.y];
        final sorted = [...ys]..sort();
        expect(ys, sorted);
      }
    });

    test('re-cutting and back again lands where it started', () {
      final square = CardCompose.quote(
          id: 'x', text: ayah, format: CardFormat.square, quran: true);
      final there =
          CardCompose.reshape(square, CardFormat.square, CardFormat.story);
      final back =
          CardCompose.reshape(there, CardFormat.story, CardFormat.square);
      expect(back.blocks.first.y, closeTo(square.blocks.first.y, 0.001));
      expect(back.blocks.first.size, closeTo(square.blocks.first.size, 1e-9));
    });
  });

  group('carrying a look across a deck', () {
    test('the ground, the frame and the type travel; the words do not', () {
      final a = CardCompose.quote(
              id: 'a', text: ayah, format: CardFormat.square, quran: true)
          .copyWith(frame: CardFrame.khatam, frameArgb: 0xFF00FF00);
      final styled = a.withBlock(
          a.blocks.first.copyWith(colourArgb: 0xFF123456, skin: CardSkin.glow));
      final b = CardCompose.quote(
          id: 'b',
          text: 'الدِّينُ النَّصِيحَةُ',
          format: CardFormat.square);
      final carried = CardCompose.carry(styled, b);
      expect(carried.frame, CardFrame.khatam);
      expect(carried.frameArgb, 0xFF00FF00);
      expect(carried.blocks.first.colourArgb, 0xFF123456);
      expect(carried.blocks.first.skin, CardSkin.glow);
      // The words, the place and the size are the card's own.
      expect(carried.blocks.first.text, 'الدِّينُ النَّصِيحَةُ');
      expect(carried.blocks.first.y, b.blocks.first.y);
    });

    test('the photograph travels, and so does the crop', () {
      // "Apply to all" used to carry the paper, the dim and the blur
      // and leave the scenery behind, so a deck styled onto a mountain
      // came out as one mountain and nine black cards with the right
      // frame on them. The scenery is the thing a card is most
      // transformed by; a copy of a card without it is not a copy.
      final source = CardCompose.quote(
        id: 'a',
        text: ayah,
        format: CardFormat.square,
        quran: true,
      ).copyWith(
        background: const CardBackground(
          paper: CardPaper.ink,
          sceneId: 'mountains_pexels_01',
          focusY: 0.18,
          zoom: 1.4,
          dim: 0.5,
          blur: 0.2,
        ),
      );
      final target = CardCompose.quote(
          id: 'b', text: ayah, format: CardFormat.square, quran: true);
      expect(target.background.hasPicture, isFalse);

      final carried = CardCompose.carry(source, target);
      expect(carried.background.sceneId, 'mountains_pexels_01');
      expect(carried.background.focusY, closeTo(0.18, 1e-9));
      expect(carried.background.zoom, closeTo(1.4, 1e-9));
      expect(carried.background.dim, closeTo(0.5, 1e-9));
      expect(carried.background.blur, closeTo(0.2, 1e-9));

      // And a card carried off a scenery onto paper loses the picture,
      // which is the same rule read the other way.
      final back = CardCompose.carry(target, carried);
      expect(back.background.hasPicture, isFalse);
    });

    test('a photograph the user picked travels too', () {
      final source = CardCompose.quote(
        id: 'a',
        text: ayah,
        format: CardFormat.square,
        quran: true,
      ).copyWith(
        background: const CardBackground(filePath: '/tmp/mine.jpg'),
      );
      final target = CardCompose.quote(
          id: 'b', text: ayah, format: CardFormat.square, quran: true);
      expect(CardCompose.carry(source, target).background.filePath,
          '/tmp/mine.jpg');
    });

    test('a Latin face is never carried onto an Arabic line', () {
      final latin = CardCompose.quote(
          id: 'a', text: 'A line of English', format: CardFormat.square);
      final arabic = CardCompose.quote(
          id: 'b', text: ayah, format: CardFormat.square, quran: true);
      final carried = CardCompose.carry(latin, arabic);
      expect(carried.blocks.first.face.arabicScript, isTrue);
    });
  });

  group('a paragraph becomes a carousel', () {
    test('it is cut into whole sentences, never mid-word', () {
      final text = List.filled(9,
              'Allah does not burden a soul beyond what it can bear. '
              'And He is the Most Merciful of the merciful.')
          .join(' ');
      final cards = CardCompose.paginate(text);
      expect(cards.length, greaterThan(1));
      expect(cards.length, lessThanOrEqualTo(CardDeck.maxSlides));
      for (final c in cards) {
        expect(c.trim(), isNotEmpty);
      }
      // Nothing is lost and nothing is invented.
      final rejoined = cards.join(' ').replaceAll(RegExp(r'\s+'), ' ');
      expect(rejoined, text.replaceAll(RegExp(r'\s+'), ' '));
    });

    test('a short passage stays one card', () {
      expect(CardCompose.paginate('Short enough to fit.'), hasLength(1));
      expect(CardCompose.paginate('   '), isEmpty);
    });
  });

  group('the deck survives a round trip through its file', () {
    test('everything a card is made of comes back', () {
      final slide = CardCompose.quote(
        id: 'a',
        text: ayah,
        translation: english,
        reference: 'Ta-Ha · 20:114',
        format: CardFormat.portrait,
        template: CardTemplate.gilded,
        background: const CardBackground(
            sceneId: 'sky_pexels_01', focusY: 0.2, dim: 0.4, blur: 0.3),
        effects: const ReelEffects(look: ReelLook.dusk, grain: 0.5),
        source: const CardSource.verse(20, 114, 114),
        quran: true,
      );
      final deck = CardCompose.deck(slide, format: CardFormat.portrait);
      final back = CardDeck.fromJson(deck.toJson());
      expect(back.format, deck.format);
      expect(back.slides.first.frame, slide.frame);
      expect(back.slides.first.background.sceneId, 'sky_pexels_01');
      expect(back.slides.first.background.focusY, 0.2);
      expect(back.slides.first.background.blur, 0.3);
      expect(back.slides.first.effects.look, ReelLook.dusk);
      expect(back.slides.first.effects.grain, 0.5);
      expect(back.slides.first.source.isVerse, isTrue);
      expect(back.slides.first.source.surah, 20);
      for (var i = 0; i < slide.blocks.length; i++) {
        final a = slide.blocks[i], b = back.slides.first.blocks[i];
        expect(b.text, a.text);
        expect(b.face, a.face);
        expect(b.size, a.size);
        expect(b.colourArgb, a.colourArgb);
        expect(b.x, a.x);
        expect(b.y, a.y);
        expect(b.skin, a.skin);
        expect(b.rtl, a.rtl);
      }
    });

    test('a file from a build that knew other names still opens', () {
      final deck = CardDeck.fromJson(const {
        'id': 'x',
        'format': 'panorama',
        'slides': [
          {
            'id': 's',
            'background': {'paper': 'moss', 'dim': 0.5},
            'frame': 'filigree',
            'blocks': [
              {'text': 'hello', 'face': 'blackletter', 'skin': 'emboss'},
            ],
          },
        ],
      });
      expect(deck.format, CardFormat.portrait);
      expect(deck.slides.first.frame, CardFrame.none);
      expect(deck.slides.first.background.paper, CardPaper.night);
      expect(deck.slides.first.blocks.first.face, CardFace.cormorant);
      expect(deck.slides.first.blocks.first.skin, CardSkin.shadow);
      // And a file with no cards at all opens on one rather than
      // crashing the composer.
      expect(CardDeck.fromJson(const {'id': 'y'}).slides, hasLength(1));
    });
  });
}
