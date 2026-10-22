import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/fatiha_data.dart';
import 'package:ayah_reels/data/models.dart';
import 'package:ayah_reels/data/quran_text_service.dart';
import 'package:ayah_reels/data/surah_index.dart';
import 'package:ayah_reels/data/word_align_service.dart';

void main() {
  test('range recitation looks timings up by ayah number, not index', () {
    // A range-only build of ayahs 3..5: the table starts at ayah 3 and
    // its clock starts at 0 in that file.
    const rec = Recitation(
      reciterId: 'r',
      surah: 2,
      audioPath: 'x',
      timings: [
        AyahTiming(3, 0, 1000),
        AyahTiming(4, 1000, 2600),
        AyahTiming(5, 2600, 3600),
      ],
    );
    expect(rec.firstAyah, 3);
    expect(rec.lastAyah, 5);
    expect(rec.covers(3, 5), isTrue);
    expect(rec.covers(4, 4), isTrue);
    expect(rec.covers(2, 4), isFalse);
    expect(rec.covers(4, 6), isFalse);
    expect(rec.timing(4).startMs, 1000);
    expect(rec.timing(4).endMs, 2600);
    expect(rec.timing(5).durationMs, 1000);
  });

  test('Fatiha has 7 ayahs', () {
    expect(fatiha.length, 7);
  });

  test('surah index covers the whole Quran, in order', () {
    expect(surahIndex.length, 114);
    for (var i = 0; i < 114; i++) {
      expect(surahIndex[i].number, i + 1);
      expect(surahIndex[i].ayahCount, greaterThan(0));
    }
    // Total ayah count of the Quran (Hafs/Kufic count).
    final total =
        surahIndex.fold<int>(0, (sum, s) => sum + s.ayahCount);
    expect(total, 6236);
  });

  test('reciter ids are unique', () {
    // Sources, and their shape, are pinned in reciter_sources_test.dart.
    final ids = reciters.map((r) => r.id).toSet();
    expect(ids.length, reciters.length);
  });

  test('bundled reciters have one timing window per ayah, contiguous', () {
    final bundled = reciters.where((r) => r.hasBundledFatiha);
    expect(bundled, isNotEmpty,
        reason: 'first-run experience needs offline voices');
    for (final r in bundled) {
      final timings = r.timings!;
      expect(timings.length, fatiha.length, reason: r.id);
      for (var i = 0; i < timings.length; i++) {
        expect(timings[i].durationMs, greaterThan(0), reason: '${r.id} $i');
        if (i > 0) {
          expect(timings[i].startMs, timings[i - 1].endMs,
              reason: '${r.id} gap before ayah ${i + 1}');
        }
      }
    }
  });

  group('stripLeadingBasmala', () {
    // Exactly as alquran.cloud serves 112:1 — basmala glued in front.
    const glued112 =
        'بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ قُلْ هُوَ ٱللَّهُ أَحَدٌ';
    const clean112 = 'قُلْ هُوَ ٱللَّهُ أَحَدٌ';

    test('strips the glued basmala from ayah 1', () {
      expect(
          QuranTextService.stripLeadingBasmala(112, 1, glued112), clean112);
    });

    test('also matches the tatweel/dagger-alif spelling variant', () {
      const variant =
          'بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ قُلْ هُوَ ٱللَّهُ أَحَدٌ';
      expect(
          QuranTextService.stripLeadingBasmala(112, 1, variant), clean112);
    });

    test('is a no-op on already-clean text (old disk caches re-pass)', () {
      expect(
          QuranTextService.stripLeadingBasmala(112, 1, clean112), clean112);
    });

    test('never touches Al-Fatiha, where the basmala IS ayah 1', () {
      final basmala = fatiha.first.arabic;
      expect(QuranTextService.stripLeadingBasmala(1, 1, basmala), basmala);
    });

    test('never touches ayahs other than the first', () {
      expect(QuranTextService.stripLeadingBasmala(112, 2, glued112),
          glued112);
    });
  });

  group('dropWrongSideIqlabMeem', () {
    const lowMeem = 'ۭ', highMeem = 'ۢ';
    const fathatan = 'ً', dammatan = 'ٌ', kasratan = 'ٍ';

    test('drops the low meem mirrored under fathatan (2:2 هُدًى)', () {
      expect(
          QuranTextService.dropWrongSideIqlabMeem(
              'هُد$fathatan$lowMeemى'),
          'هُد$fathatanى');
    });

    test('drops the low meem mirrored under dammatan (2:54 خَيْرٌ)', () {
      expect(
          QuranTextService.dropWrongSideIqlabMeem(
              'خَيْر$dammatan$lowMeem'),
          'خَيْر$dammatan');
    });

    test('drops the high meem mirrored over kasratan (2:20 شَىْءٍ)', () {
      expect(
          QuranTextService.dropWrongSideIqlabMeem(
              'شَىْء$kasratan$highMeem'),
          'شَىْء$kasratan');
    });

    test('keeps the low meem the mushaf prints under kasratan (نَفْسٍۭ)', () {
      const kept = 'نَفْس$kasratan$lowMeem';
      expect(QuranTextService.dropWrongSideIqlabMeem(kept), kept);
    });

    test('keeps the high meem the mushaf prints over dammatan (عَلِيمٌۢ)', () {
      const kept = 'عَلِيم$dammatan$highMeem';
      expect(QuranTextService.dropWrongSideIqlabMeem(kept), kept);
    });

    test('keeps the high meem that follows a bare noon (مِنۢ)', () {
      const kept = 'مِن$highMeem';
      expect(QuranTextService.dropWrongSideIqlabMeem(kept), kept);
    });

    test('leaves ayahs with no tanween alone', () {
      final fatihaOne = fatiha.first.arabic;
      expect(QuranTextService.dropWrongSideIqlabMeem(fatihaOne), fatihaOne);
    });

    test('clears both meems in one line (31:3)', () {
      const luqman =
          'هُد$fathatan$lowMeemى وَرَحْمَة$fathatan$lowMeem لِّلْمُحْسِنِينَ';
      expect(QuranTextService.dropWrongSideIqlabMeem(luqman),
          'هُد$fathatanى وَرَحْمَة$fathatan لِّلْمُحْسِنِينَ');
    });
  });

  group('stripCircleMarks', () {
    // The verse that surfaced them: 33:56, where three silent alifs in
    // a row each carry a rounded zero. Blown up to reel size they read
    // as white beads threaded through the line.
    const zero = '۟'; // ۟ rounded zero, over a silent letter
    const upright = '۠'; // ۠ its "only when continuing" twin
    const rosette = '۞'; // ۞ start of a rub' el hizb

    test('drops the rounded zero over every silent alif (33:56)', () {
      const ahzab = 'ٱلَّذِينَ ءَامَنُوا$zero صَلُّوا$zero عَلَيْهِ '
          'وَسَلِّمُوا$zero تَسْلِيمًا';
      expect(QuranTextService.stripCircleMarks(ahzab),
          'ٱلَّذِينَ ءَامَنُوا صَلُّوا عَلَيْهِ وَسَلِّمُوا تَسْلِيمًا');
    });

    test('drops the upright zero too', () {
      expect(QuranTextService.stripCircleMarks('أَنَا$upright'), 'أَنَا');
    });

    test('takes the rosette and the gap it leaves behind (18:17)', () {
      // It arrives as its own space-separated token, so removing the
      // character alone would leave a double space in the middle of
      // the card.
      expect(QuranTextService.stripCircleMarks('$rosette وَتَرَى ٱلشَّمْسَ'),
          'وَتَرَى ٱلشَّمْسَ');
      expect(QuranTextService.stripCircleMarks('وَقُلِ $rosette ٱلْحَقُّ'),
          'وَقُلِ ٱلْحَقُّ');
    });

    test('leaves the pause marks and the harakat alone', () {
      // The small jeem is a waqf mark, not a circle, and it sits in
      // 33:56 right beside the zeros that do come off.
      const withJeem = 'عَلَى ٱلنَّبِىِّ ۚ يَٰٓأَيُّهَا';
      expect(QuranTextService.stripCircleMarks(withJeem), withJeem);
    });

    test('is a no-op on already-clean text (old disk caches re-pass)', () {
      final fatihaOne = fatiha.first.arabic;
      expect(QuranTextService.stripCircleMarks(fatihaOne), fatihaOne);
    });

    test('never changes the word count the highlight indexes by', () {
      // Word highlighting maps quran-align indices onto space-split
      // tokens of this same string. A stripped mark that swallowed a
      // space would light the wrong word for the rest of the verse.
      const ahzab = 'ءَامَنُوا$zero صَلُّوا$zero عَلَيْهِ';
      expect(QuranTextService.stripCircleMarks(ahzab).split(' ').length,
          ahzab.split(' ').length);
    });
  });

  group('stripFootnoteMarkup', () {
    test('drops the tag and the bare digit it wraps', () {
      expect(
        QuranTextService.stripFootnoteMarkup(
            'This is the Book about which there is no doubt, a guidance for '
            'those conscious of Allāh<sup foot_note=195936>1</sup> -'),
        'This is the Book about which there is no doubt, a guidance for '
        'those conscious of Allāh -',
      );
    });

    test('drops several footnotes in one ayah', () {
      expect(
        QuranTextService.stripFootnoteMarkup(
            'Who believe in the unseen, establish prayer,'
            '<sup foot_note=195938>1</sup> and spend out of what We'
            '<sup foot_note=195937>2</sup> have provided for them,'),
        'Who believe in the unseen, establish prayer, and spend out of what '
        'We have provided for them,',
      );
    });

    test('leaves a plain translation untouched', () {
      const plain = 'All praise is due to Allah, Lord of the worlds.';
      expect(QuranTextService.stripFootnoteMarkup(plain), plain);
    });
  });

  group('displayRange across the mushaf spelling of بَعْدَمَا', () {
    // 2:181 — the mushaf splits `بَعْدَ مَا`, quran-align counts it as one
    // word, so the pair has to occupy a single align slot or every
    // highlight after it in the verse lands one word late.
    const ayah181 = 'فَمَنۢ بَدَّلَهُۥ بَعْدَ مَا سَمِعَهُۥ فَإِنَّمَآ إِثْمُهُۥ عَلَى ٱلَّذِينَ '
        'يُبَدِّلُونَهُۥٓ ۚ إِنَّ ٱللَّهَ سَمِيعٌ عَلِيمٌ';

    test('the pair occupies one align slot', () {
      // align word 2 == بَعْدَمَا -> display tokens 2..3 inclusive
      expect(WordAlignService.displayRange(ayah181, 2, 3),
          (start: 2, end: 4));
    });

    test('words after it still line up', () {
      // align word 3 == سَمِعَهُۥ, which is display token 4
      expect(WordAlignService.displayRange(ayah181, 3, 4),
          (start: 4, end: 5));
    });

    test('the verse offers exactly the 13 words the alignment expects', () {
      expect(WordAlignService.displayRange(ayah181, 0, 13), isNotNull);
      expect(WordAlignService.displayRange(ayah181, 0, 14), isNull);
    });

    test('بَعْدِ مَا (kasra) is a different phrase and stays two words', () {
      // 2:75 — 27 ayahs carry this one; merging it would break them all.
      const ayah75 = '۞ أَفَتَطْمَعُونَ أَن يُؤْمِنُوا۟ لَكُمْ وَقَدْ كَانَ فَرِيقٌ مِّنْهُمْ '
          'يَسْمَعُونَ كَلَـٰمَ ٱللَّهِ ثُمَّ يُحَرِّفُونَهُۥ مِنۢ بَعْدِ مَا عَقَلُوهُ وَهُمْ يَعْلَمُونَ';
      // بَعْدِ is display token 13, مَا is 14 — two separate align slots
      expect(WordAlignService.displayRange(ayah75, 12, 13),
          (start: 13, end: 14));
      expect(WordAlignService.displayRange(ayah75, 13, 14),
          (start: 14, end: 15));
    });
  });

}
