import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/fatiha_data.dart';
import 'package:ayah_reels/data/quran_text_service.dart';
import 'package:ayah_reels/data/quran_verses.dart';
import 'package:ayah_reels/data/settings_service.dart';
import 'package:ayah_reels/data/verse_translation.dart';
import 'package:ayah_reels/l10n/l10n.dart';

/// The verse translation a reel carries is the one thing in this app
/// that cannot be taken back: it is burned into an exported video and
/// shared. tool/verify_translations.py checks every offered edition
/// whole against the live API; these tests pin the parts of that which
/// live in Dart, using the exact text the verifier found.
void main() {
  group('the editions offered', () {
    test('every one has a resource, a code and a translator', () {
      for (final t in VerseTranslation.values) {
        expect(t.resourceId, greaterThan(0));
        expect(t.code, isNotEmpty);
        expect(t.nativeName, isNotEmpty);
        expect(t.translator, isNotEmpty);
      }
      // Two editions sharing a resource id would share a cache file.
      expect(VerseTranslation.values.map((t) => t.resourceId).toSet(),
          hasLength(VerseTranslation.values.length));
      expect(VerseTranslation.values.map((t) => t.code).toSet(),
          hasLength(VerseTranslation.values.length));
    });

    test('Urdu is the only right-to-left one, and English is the default',
        () {
      expect(VerseTranslation.values.where((t) => t.rtl),
          [VerseTranslation.urdu]);
      expect(VerseTranslation.values.where((t) => t.arabicScript),
          [VerseTranslation.urdu]);
      expect(AppSettings.defaults.translation, VerseTranslation.english);
      // Saheeh International, which is what the app has always served.
      expect(VerseTranslation.english.resourceId, 20);
    });

    test('an unknown code falls back rather than crashing', () {
      expect(VerseTranslation.fromCode('ur'), VerseTranslation.urdu);
      expect(VerseTranslation.fromCode('zz'), VerseTranslation.english);
      expect(VerseTranslation.fromCode(null), VerseTranslation.english);
      // Every app language except Arabic has an edition of its own;
      // Arabic hides the line, so English is where it rests.
      for (final lang in AppLang.values) {
        expect(VerseTranslation.forAppLang(lang.code), isNotNull);
      }
      expect(VerseTranslation.forAppLang('ar'), VerseTranslation.english);
      expect(VerseTranslation.forAppLang('de'), VerseTranslation.german);
    });
  });

  group('normalizeSpaces', () {
    // Each of these is a real string from the edition named, found by
    // tool/verify_translations.py. The English edition carries none of
    // them, which is why this did not exist before.
    test('drops the Indonesian soft hyphens, which Inter cannot draw', () {
      // 2:119, where they come in clusters.
      const raw = 'diminta (pertang­­­gung­­ '
          'jawaban) tentang';
      expect(QuranTextService.normalizeSpaces(raw),
          'diminta (pertanggung jawaban) tentang');
      expect(QuranTextService.normalizeSpaces(raw), isNot(contains('­')));
    });

    test('flattens the German hard break sitting mid-clause', () {
      // 4:140: a CR LF between 'ihnen' and '(zusammen)'.
      const raw = 'dann sitzt nicht mit ihnen\r\n(zusammen), bis sie';
      expect(QuranTextService.normalizeSpaces(raw),
          'dann sitzt nicht mit ihnen (zusammen), bis sie');
    });

    test('turns the Urdu no-break spaces into ordinary ones', () {
      // 27:7, where a NBSP is used as a plain word space.
      const raw = 'میں نے آگ دیکھی ہے';
      expect(QuranTextService.normalizeSpaces(raw), 'میں نے آگ دیکھی ہے');
      expect(QuranTextService.normalizeSpaces(raw), isNot(contains(' ')));
    });

    test('leaves joining controls alone — they are spelling, not space',
        () {
      // ZWNJ and ZWJ decide whether Arabic-script letters join. Dropping
      // them would misspell Urdu words.
      const raw = 'ا‌ب‍ج';
      expect(QuranTextService.normalizeSpaces(raw), raw);
    });

    test('is a no-op on clean text, and idempotent', () {
      const clean = 'Indeed, Allah is with the patient.';
      expect(QuranTextService.normalizeSpaces(clean), clean);
      const messy = 'a­ b  c\n d';
      final once = QuranTextService.normalizeSpaces(messy);
      expect(QuranTextService.normalizeSpaces(once), once);
      expect(once, 'a b c d');
    });
  });

  group('the settings file', () {
    test('an install that predates the picker keeps the language it had',
        () {
      // The old shape: an 'arabic' boolean and no 'lang'. Somebody who
      // had chosen Arabic must not be dropped back into English.
      final wasArabic = AppSettings.fromJson({'arabic': true});
      expect(wasArabic.lang, AppLang.ar);
      expect(wasArabic.arabic, isTrue);
      final wasEnglish = AppSettings.fromJson({'arabic': false});
      expect(wasEnglish.lang, AppLang.en);
      // And either way they carry on reading Saheeh International.
      expect(wasArabic.translation, VerseTranslation.english);
      expect(wasEnglish.translation, VerseTranslation.english);
    });

    test('the language code wins once it is written', () {
      final s = AppSettings.fromJson({'arabic': true, 'lang': 'de'});
      expect(s.lang, AppLang.de);
      expect(s.arabic, isFalse);
    });

    test('a round trip keeps both choices', () {
      final s = AppSettings.defaults.copyWith(
        lang: AppLang.ur,
        translation: VerseTranslation.urdu,
      );
      final back = AppSettings.fromJson(s.toJson());
      expect(back.lang, AppLang.ur);
      expect(back.translation, VerseTranslation.urdu);
    });

    test('a language this build does not carry opens on English', () {
      final s = AppSettings.fromJson({'lang': 'xx', 'translation': 'xx'});
      expect(s.lang, AppLang.en);
      expect(s.translation, VerseTranslation.english);
    });
  });

  group('the bundled Al-Fatiha', () {
    test('is complete in every edition, so a first run works offline', () {
      for (final t in VerseTranslation.values) {
        final surah = fatihaIn(t);
        expect(surah, hasLength(7), reason: t.code);
        for (var i = 0; i < 7; i++) {
          expect(surah[i].number, i + 1);
          // The Arabic never varies with the edition.
          expect(surah[i].arabic, fatiha[i].arabic);
          expect(surah[i].translation, isNotEmpty, reason: '${t.code} $i');
          expect(surah[i].translation,
              QuranTextService.normalizeSpaces(surah[i].translation));
        }
      }
    });

    test('leaves the English wording exactly as it always was', () {
      final english = fatihaIn(VerseTranslation.english);
      for (var i = 0; i < 7; i++) {
        expect(english[i].translation, fatiha[i].translation);
      }
    });

    test('the other editions actually differ from the English', () {
      for (final t in VerseTranslation.values) {
        if (t == VerseTranslation.english) continue;
        final surah = fatihaIn(t);
        expect(surah.map((a) => a.translation),
            isNot(fatiha.map((a) => a.translation)),
            reason: '${t.code} is just the English list');
      }
    });
  });

  group('the curated verse rotation', () {
    test('every verse carries every edition, and none is empty', () {
      for (final v in [jumuahVerse, ...quranVerses]) {
        for (final t in VerseTranslation.values) {
          expect(v.translations[t.code], isNotNull,
              reason: '${v.reference} has no ${t.code} translation');
          expect(v.translationIn(t), isNotEmpty);
        }
        // The native widgets read this one and are not language-aware.
        expect(v.translation, v.translations['en']);
      }
    });

    test('no translation carries markup or an invisible', () {
      for (final v in [jumuahVerse, ...quranVerses]) {
        for (final t in VerseTranslation.values) {
          final line = v.translationIn(t);
          expect(line, isNot(contains('<')), reason: v.reference);
          expect(line, QuranTextService.normalizeSpaces(line),
              reason: '${v.reference} ${t.code} was not normalized');
        }
      }
    });
  });
}
