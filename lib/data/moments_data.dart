import '../l10n/app_lang.dart';

/// One card's wording in one language.
typedef MomentWording = ({String title, String subtitle});

/// A curated one-tap starting point: a beloved passage with a voice
/// that suits it. Tapping a Moment fills in reciter + verses; the user
/// still chooses the scenery and fine-tunes in the preview.
class Moment {
  /// The card's wording, per app language. English is the one that has
  /// to be there; [title] and [subtitle] fall back to it, so a moment
  /// added without every language still shows rather than crashing.
  ///
  /// The subtitle is usually a surah reference. Arabic and Urdu read
  /// those in Arabic script; Indonesian and German use the same Latin
  /// transliteration English does, so they often repeat it — that is
  /// correct, not an oversight.
  final Map<AppLang, MomentWording> wording;

  final int surah;
  final int startAyah;
  final int endAyah;

  /// Must match a [Reciter.id] in the reciters list; resolved at tap
  /// time so a missing id can fall back gracefully.
  final String reciterId;

  const Moment({
    required this.wording,
    required this.surah,
    required this.startAyah,
    required this.endAyah,
    required this.reciterId,
  });

  MomentWording _of(AppLang lang) => wording[lang] ?? wording[AppLang.en]!;

  String title(AppLang lang) => _of(lang).title;
  String subtitle(AppLang lang) => _of(lang).subtitle;
}

/// The passages that go viral as recitation clips — dramatic openings,
/// soaring moments, verses everyone has heard a famous reel of. Not a
/// daily-adhkar list. All ranges are short reels, well inside the cap.
const moments = <Moment>[
  Moment(
    wording: {
      AppLang.en: (title: 'Whose is the earth?', subtitle: 'Al-Mu\'minun 84–89'),
      AppLang.ar: (title: 'لمن الأرض؟', subtitle: 'المؤمنون 84–89'),
      AppLang.ur: (title: 'زمین کس کی ہے؟', subtitle: 'المؤمنون 84–89'),
      AppLang.id: (title: 'Milik siapa bumi ini?', subtitle: 'Al-Mu\'minun 84–89'),
      AppLang.de: (title: 'Wem gehört die Erde?', subtitle: 'Al-Mu\'minun 84–89'),
    },
    surah: 23,
    startAyah: 84,
    endAyah: 89,
    reciterId: 'dussary',
  ),
  Moment(
    wording: {
      AppLang.en: (title: 'Kaf Ha Ya Ain Sad', subtitle: 'Maryam opens'),
      AppLang.ar: (title: 'كهيعص', subtitle: 'فواتح مريم'),
      AppLang.ur: (title: 'کھیعص', subtitle: 'مریم کا آغاز'),
      AppLang.id: (title: 'Kaf Ha Ya Ain Sad', subtitle: 'Pembuka Maryam'),
      AppLang.de: (title: 'Kaf Ha Ya Ain Sad', subtitle: 'Maryam beginnt'),
    },
    surah: 19,
    startAyah: 1,
    endAyah: 6,
    reciterId: 'minshawi',
  ),
  Moment(
    wording: {
      AppLang.en: (title: 'O reassured soul', subtitle: 'Al-Fajr 27–30'),
      AppLang.ar: (title: 'يا أيتها النفس المطمئنة', subtitle: 'الفجر 27–30'),
      AppLang.ur: (title: 'اے نفسِ مطمئنہ', subtitle: 'الفجر 27–30'),
      AppLang.id: (title: 'Wahai jiwa yang tenang', subtitle: 'Al-Fajr 27–30'),
      AppLang.de: (title: 'O du beruhigte Seele', subtitle: 'Al-Fadschr 27–30'),
    },
    surah: 89,
    startAyah: 27,
    endAyah: 30,
    reciterId: 'sudais',
  ),
  Moment(
    wording: {
      AppLang.en: (title: 'The angels descend', subtitle: 'Fussilat 30–32'),
      AppLang.ar: (title: 'تتنزّل الملائكة', subtitle: 'فصلت 30–32'),
      AppLang.ur: (title: 'فرشتے اترتے ہیں', subtitle: 'فصلت 30–32'),
      AppLang.id: (title: 'Para malaikat turun', subtitle: 'Fussilat 30–32'),
      AppLang.de: (title: 'Die Engel steigen herab', subtitle: 'Fussilat 30–32'),
    },
    surah: 41,
    startAyah: 30,
    endAyah: 32,
    reciterId: 'alafasy',
  ),
  Moment(
    wording: {
      AppLang.en: (title: 'The Great News', subtitle: 'An-Naba opens'),
      AppLang.ar: (title: 'النبأ العظيم', subtitle: 'فواتح النبأ'),
      AppLang.ur: (title: 'خبرِ عظیم', subtitle: 'النبأ کا آغاز'),
      AppLang.id: (title: 'Berita Besar', subtitle: 'Pembuka An-Naba'),
      AppLang.de: (title: 'Die gewaltige Kunde', subtitle: 'An-Naba beginnt'),
    },
    surah: 78,
    startAyah: 1,
    endAyah: 16,
    reciterId: 'shuraym',
  ),
  Moment(
    wording: {
      AppLang.en: (title: 'Ta-Ha', subtitle: 'Not to distress you'),
      AppLang.ar: (title: 'طه', subtitle: 'ما أنزلنا عليك القرآن لتشقى'),
      AppLang.ur: (title: 'طٰہٰ', subtitle: 'تاکہ تم مشقت میں نہ پڑو'),
      AppLang.id: (title: 'Ta-Ha', subtitle: 'Bukan untuk menyusahkanmu'),
      AppLang.de: (title: 'Ta-Ha', subtitle: 'Nicht, um dich zu bedrücken'),
    },
    surah: 20,
    startAyah: 1,
    endAyah: 8,
    reciterId: 'abdulbasit',
  ),
  Moment(
    wording: {
      AppLang.en: (title: 'The Inevitable', subtitle: 'Al-Waqi\'ah 1–12'),
      AppLang.ar: (title: 'الواقعة', subtitle: 'الواقعة 1–12'),
      AppLang.ur: (title: 'الواقعہ', subtitle: 'الواقعة 1–12'),
      AppLang.id: (title: 'Hari Kiamat', subtitle: 'Al-Waqi\'ah 1–12'),
      AppLang.de: (title: 'Das Unausweichliche', subtitle: 'Al-Waqi\'a 1–12'),
    },
    surah: 56,
    startAyah: 1,
    endAyah: 12,
    reciterId: 'husary',
  ),
  Moment(
    wording: {
      AppLang.en: (title: 'By the sun', subtitle: 'Ash-Shams 1–10'),
      AppLang.ar: (title: 'والشمس وضحاها', subtitle: 'الشمس 1–10'),
      AppLang.ur: (title: 'قسم ہے سورج کی', subtitle: 'الشمس 1–10'),
      AppLang.id: (title: 'Demi matahari', subtitle: 'Asy-Syams 1–10'),
      AppLang.de: (title: 'Bei der Sonne', subtitle: 'Asch-Schams 1–10'),
    },
    surah: 91,
    startAyah: 1,
    endAyah: 10,
    reciterId: 'shatri',
  ),
  Moment(
    wording: {
      AppLang.en: (title: 'Light upon light', subtitle: 'An-Nur 35'),
      AppLang.ar: (title: 'نور على نور', subtitle: 'النور 35'),
      AppLang.ur: (title: 'نور علیٰ نور', subtitle: 'النور 35'),
      AppLang.id: (title: 'Cahaya di atas cahaya', subtitle: 'An-Nur 35'),
      AppLang.de: (title: 'Licht über Licht', subtitle: 'An-Nur 35'),
    },
    surah: 24,
    startAyah: 35,
    endAyah: 35,
    reciterId: 'muaiqly',
  ),
  Moment(
    wording: {
      AppLang.en: (title: 'The morning light', subtitle: 'Ad-Duha'),
      AppLang.ar: (title: 'والضحى', subtitle: 'سورة الضحى'),
      AppLang.ur: (title: 'چاشت کی روشنی', subtitle: 'سورۃ الضحیٰ'),
      AppLang.id: (title: 'Cahaya pagi', subtitle: 'Ad-Duha'),
      AppLang.de: (title: 'Das Morgenlicht', subtitle: 'Ad-Duha'),
    },
    surah: 93,
    startAyah: 1,
    endAyah: 11,
    reciterId: 'qatami',
  ),
];
