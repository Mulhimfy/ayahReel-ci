import 'package:flutter/foundation.dart'
    show SynchronousFuture, visibleForTesting;
import 'package:flutter/widgets.dart';

import '../data/arena_engine.dart';
import '../data/band_glow.dart';
import '../data/dedication.dart';
import '../data/fatiha_data.dart';
import '../data/models.dart';
import '../data/reel_limits.dart';
import '../data/settings_service.dart';
import '../data/store_links.dart';
import '../data/surah_index.dart';
import '../data/surah_title_look.dart';
import '../data/trouble.dart';
import '../data/verse_ink.dart';
import '../data/verse_numbering.dart';
import 'app_lang.dart';

export 'app_lang.dart';

/// Every user-facing string in the app, in all five languages.
///
/// One getter per string, every language on the same line, so a copy
/// change can never update one language and forget the others. English
/// is the exact wording the app always had — tests pin it.
///
/// The five arguments of [_t] are all required and all positional, in
/// the order the enum declares. That is deliberate: it makes a missing
/// translation a compile error rather than a string that silently falls
/// back to English on somebody's phone. Adding a sixth language breaks
/// the build in exactly the 260-odd places that need a sentence
/// written, which is the only honest way to add one.
///
/// Widgets read it via [L10n.of], which registers a dependency on the
/// Localizations scope: changing the language in Settings changes the
/// MaterialApp locale and every dependent widget rebuilds in place —
/// no restart, no lost navigation state.
class L10n {
  final AppLang lang;
  const L10n(this.lang);

  static const en = L10n(AppLang.en);

  /// True when the app is showing Arabic.
  ///
  /// Still its own getter, and still means Arabic alone, because a
  /// handful of decisions are about Arabic the language rather than
  /// about the script or the direction: the surah name already being
  /// Arabic, and the translation line under a verse being redundant
  /// when the reader is reading the verse itself. For the typographic
  /// rules use [arabicScript]; for layout use [rtl].
  bool get ar => lang == AppLang.ar;

  bool get rtl => lang.rtl;
  bool get arabicScript => lang.arabicScript;
  TextDirection get direction => lang.direction;

  /// Falls back to the current setting when no delegate is installed
  /// (plain test harnesses), so widgets never null-crash.
  static L10n of(BuildContext context) =>
      Localizations.of<L10n>(context, L10n) ?? current;

  /// For code with no BuildContext (notifications, share messages).
  static L10n get current => L10n(SettingsService.state.value.lang);

  static const LocalizationsDelegate<L10n> delegate = _L10nDelegate();

  /// Picks this language's wording. See the class comment for why all
  /// five are required.
  String _t(String en, String ar, String ur, String id, String de) =>
      switch (lang) {
        AppLang.en => en,
        AppLang.ar => ar,
        AppLang.ur => ur,
        AppLang.id => id,
        AppLang.de => de,
      };

  /// The list form of [_t], for the two step-by-step blocks.
  List<String> _tl(List<String> en, List<String> ar, List<String> ur,
          List<String> id, List<String> de) =>
      switch (lang) {
        AppLang.en => en,
        AppLang.ar => ar,
        AppLang.ur => ur,
        AppLang.id => id,
        AppLang.de => de,
      };

  /// The comma this language separates a clause with. Arabic script
  /// takes its own (U+060C), which sits on the baseline the other way
  /// round; a Latin comma in an Urdu line reads as a typo. Public
  /// because the spoken labels built outside this class join with it
  /// too.
  String get comma => arabicScript ? '،' : ',';

  // ---- shell ------------------------------------------------------
  String get navHome => _t('Home', 'الرئيسية', 'ہوم', 'Beranda', 'Start');
  /// The third tab: everything the user has made — the reels, and the
  /// card of every verse lit across the app. Named for the works, not
  /// for one kind of them.
  String get navWorks =>
      _t('My works', 'أعمالي', 'میری تخلیقات', 'Karya saya', 'Meine Werke');
  String get navSettings =>
      _t('Settings', 'الإعدادات', 'ترتیبات', 'Pengaturan', 'Einstellungen');

  // ---- home -------------------------------------------------------
  /// The time-of-day greeting, with the user's name appended when they
  /// have given one in Settings — "Good evening, Yusuf". Arabic script
  /// joins with its own comma; every language falls back to the bare
  /// greeting when [name] is empty, so an unnamed user never sees a
  /// stray comma.
  String greeting(int hour, {String name = ''}) {
    final base = _greetingBase(hour);
    final n = name.trim();
    if (n.isEmpty) return base;
    return '$base$comma $n';
  }

  String _greetingBase(int hour) {
    if (hour < 5) return _peacefulNight;
    if (hour < 12) {
      return _t('Good morning', 'صباح الخير', 'صبح بخیر', 'Selamat pagi',
          'Guten Morgen');
    }
    if (hour < 17) {
      return _t('Good afternoon', 'طاب نهارُك', 'دوپہر بخیر', 'Selamat siang',
          'Guten Tag');
    }
    if (hour < 22) {
      return _t('Good evening', 'مساء الخير', 'شام بخیر', 'Selamat sore',
          'Guten Abend');
    }
    return _peacefulNight;
  }

  String get _peacefulNight => _t('Peaceful night', 'ليلة مباركة', 'شب مبارک',
      'Malam yang tenang', 'Gesegnete Nacht');

  String get beTheReason => _t(
      "Be the reason there's Quran on someone's phone today",
      'كُن سببًا في وصول القرآن إلى هاتف أحدهم اليوم',
      'آج کسی کے فون تک قرآن پہنچنے کا سبب بنیں',
      'Jadilah sebab hadirnya Al-Qur’an di ponsel seseorang hari ini',
      'Sei der Grund, warum heute Quran auf jemandes Handy landet');
  String get createCardBody => _t(
      'Quran reels, Quran quizzes and Islamic cards, made beautiful, easy '
          'and fast.',
      'مقاطع قرآنية ومسابقات قرآنية وبطاقات إسلامية، جميلة وسهلة وسريعة '
          'الصنع.',
      'قرآنی ریلز، قرآنی کوئز اور اسلامی کارڈز — خوبصورت، آسان اور تیز۔',
      'Reel Al-Qur’an, kuis Al-Qur’an, dan kartu Islami yang indah, mudah, '
          'dan cepat dibuat.',
      'Quran-Reels, Quran-Quiz und islamische Karten: schön, einfach und '
          'schnell gemacht.');
  String get createAReel => _t('Create a reel', 'أنشئ مقطعًا', 'ریل بنائیں',
      'Buat reel', 'Reel erstellen');

  /// Home's one button, which opens the choice of what to make.
  String get createButton =>
      _t('Create', 'أنشئ', 'بنائیں', 'Buat', 'Erstellen');
  String get a11yOpensCreateChoice => _t(
      'Choose a video, a quiz or a card',
      'اختر فيديو أو مسابقة أو بطاقة',
      'ویڈیو، کوئز یا کارڈ منتخب کریں',
      'Pilih video, kuis, atau kartu',
      'Video, Quiz oder Karte wählen');
  String get createChooserTitle => _t(
      'What would you like to make?',
      'ماذا تريد أن تصنع؟',
      'آپ کیا بنانا چاہیں گے؟',
      'Mau membuat apa?',
      'Was möchtest du machen?');
  String get chooseReel => _t('Quran video', 'فيديو قرآني', 'قرآنی ویڈیو',
      'Video Al-Qur’an', 'Quran-Video');
  String get chooseReelLine => _t(
      'A verse, a voice and a scenery, ready to share',
      'آية وصوت ومشهد، جاهز للمشاركة',
      'آیت، آواز اور منظر، شیئر کے لیے تیار',
      'Ayat, suara, dan pemandangan, siap dibagikan',
      'Ein Vers, eine Stimme, eine Szenerie, bereit zum Teilen');
  String get chooseQuiz => _t('Quran quiz', 'مسابقة قرآنية', 'قرآنی کوئز',
      'Kuis Al-Qur’an', 'Quran-Quiz');
  String get chooseQuizLine => _t(
      'Test yourself, or challenge a friend',
      'اختبر نفسك أو تحدَّ صديقًا',
      'خود کو آزمائیں یا کسی دوست کو چیلنج کریں',
      'Uji diri sendiri atau tantang teman',
      'Teste dich oder fordere jemanden heraus');
  String get chooseCard => _t('Islamic card', 'بطاقة إسلامية', 'اسلامی کارڈ',
      'Kartu Islami', 'Islamische Karte');
  String get chooseCardLine => _t(
      'A verse or a hadith, beautifully set',
      'آية أو حديث في تصميم جميل',
      'آیت یا حدیث، خوبصورت انداز میں',
      'Ayat atau hadis, ditata dengan indah',
      'Ein Vers oder Hadith, schön gestaltet');
  String get recentReels => _t('Recent reels', 'أحدث المقاطع', 'حالیہ ریلز',
      'Reel terbaru', 'Neueste Reels');
  String get recentReelsSubtitle => _t(
      'Replay or share again',
      'أعد التشغيل أو شارك من جديد',
      'دوبارہ چلائیں یا پھر شیئر کریں',
      'Putar ulang atau bagikan lagi',
      'Noch einmal ansehen oder teilen');
  String get seeAll => _t('See all', 'عرض الكل', 'سب دیکھیں', 'Lihat semua',
      'Alle ansehen');

  // ---- creation wizard: reciter ----------------------------------
  String get chooseTheVoice => _t('Choose the voice', 'اختر الصوت',
      'آواز منتخب کریں', 'Pilih suara', 'Stimme wählen');
  String get tapToListen => _t(
      'Tap to listen. This becomes your reel.',
      'انقر للاستماع. هذا سيكون صوت مقطعك.',
      'سننے کے لیے ٹیپ کریں۔ یہی آپ کی ریل کی آواز ہوگی۔',
      'Ketuk untuk mendengar. Inilah suara reel Anda.',
      'Zum Anhören tippen. Das wird die Stimme deines Reels.');

  /// The field over the voices once there are too many to scroll by
  /// eye. [n] is always well past ten, so Arabic's singular accusative
  /// is the right form.
  String searchReciters(int n) => _t('Search $n reciters', 'ابحث بين $n قارئًا',
      '$n قاریوں میں تلاش کریں', 'Cari di antara $n qari',
      '$n Rezitatoren durchsuchen');
  /// The reciter card, when the surah is already chosen and this voice
  /// never recorded it.
  String noRecordingOf(String surah) => _t(
      'No recording of $surah',
      'لا توجد له تلاوة لسورة $surah',
      '$surah کی تلاوت موجود نہیں',
      'Tidak ada rekaman $surah',
      'Keine Aufnahme von $surah');

  /// A surah row in the picker, when the chosen voice never recorded it.
  String get notRecordedByVoice => _t(
      'Not recorded by this voice',
      'لم يسجّلها هذا القارئ',
      'اس قاری نے یہ سورت ریکارڈ نہیں کی',
      'Tidak direkam oleh qari ini',
      'Von dieser Stimme nicht aufgenommen');

  /// The preview, when a voice and a surah it never recorded meet.
  String surahNotRecorded(String voice, String surah) => _t(
      '$voice has no recording of $surah.\nChoose another voice or surah.',
      'لا توجد تلاوة لسورة $surah بصوت $voice.\nاختر قارئًا أو سورة أخرى.',
      '$voice کی آواز میں $surah کی تلاوت موجود نہیں۔\nکوئی اور قاری یا سورت منتخب کریں۔',
      '$voice tidak memiliki rekaman $surah.\nPilih qari atau surah lain.',
      '$voice hat $surah nicht aufgenommen.\nWähle eine andere Stimme oder Sure.');
  /// The scenery screen's reset: every scenery chosen for this reel let
  /// go. One word on the pill.
  String get resetScenery =>
      _t('Reset', 'إعادة', 'ری سیٹ', 'Atur ulang', 'Zurücksetzen');
  String get a11yResetSceneryHint => _t(
      'Clears every scenery chosen for this reel',
      'يلغي كل المناظر المختارة لهذا المقطع',
      'اس ریل کے لیے چنے گئے سب مناظر ہٹا دیتا ہے',
      'Menghapus semua pemandangan yang dipilih untuk reel ini',
      'Entfernt alle für dieses Reel gewählten Hintergründe');

  /// After the reset: nothing chosen, pick again.
  String get sceneryCleared => _t(
      'Cleared. Pick your sceneries again.',
      'تم المسح. اختر المناظر من جديد.',
      'صاف ہو گیا۔ مناظر دوبارہ چنیں۔',
      'Dihapus. Pilih pemandangan lagi.',
      'Geleert. Wähle die Hintergründe neu.');

  // ---- offline -----------------------------------------------------
  String get offlineTitle => _t('Download for offline',
      'تنزيل للاستخدام دون إنترنت', 'آف لائن کے لیے ڈاؤن لوڈ',
      'Unduh untuk offline', 'Für offline laden');
  String get offlineSection =>
      _t('Offline', 'دون إنترنت', 'آف لائن', 'Offline', 'Offline');
  String get offlineBody => _t(
      'Make reels with no internet. It downloads while you use the app.',
      'اصنع مقاطع دون إنترنت. يجري التنزيل وأنت تستخدم التطبيق.',
      'انٹرنیٹ کے بغیر ریلز بنائیں۔ ڈاؤن لوڈ ایپ چلاتے ہوئے ہوتا رہتا ہے۔',
      'Buat reel tanpa internet. Unduhan berjalan sambil kamu memakai aplikasi.',
      'Reels ohne Internet machen. Es lädt, während du die App nutzt.');
  String get offlineRowNote => _t(
      'Keep your voice, the verses and the sceneries on the phone',
      'احفظ صوت قارئك والآيات والمشاهد على هاتفك',
      'اپنے قاری کی آواز، آیات اور مناظر فون پر رکھیں',
      'Simpan suara qari, ayat, dan pemandangan di ponsel',
      'Stimme, Verse und Kulissen auf dem Handy behalten');
  String get offlineText => _t('Verses and translation', 'الآيات والترجمة',
      'آیات اور ترجمہ', 'Ayat dan terjemahan', 'Verse und Übersetzung');
  String offlineTextNote(String size) => _t(
      'All 114 surahs · $size',
      'السور كلها، 114 سورة · $size',
      'تمام 114 سورتیں · $size',
      'Semua 114 surah · $size',
      'Alle 114 Suren · $size');
  String offlineScope(String name) => switch (name) {
        'none' => _t('None', 'بدون', 'کچھ نہیں', 'Tidak', 'Keine'),
        'short' =>
          _t("Juz' 30", 'جزء عمّ', 'پارہ 30', 'Juz 30', "Juz' 30"),
        'surah' => _t('A surah', 'سورة', 'ایک سورت', 'Satu surah',
            'Eine Sure'),
        _ => _t('A juz', 'جزء', 'ایک پارہ', 'Satu juz', 'Ein Juz'),
      };

  /// A juz chosen for offline, by its number.
  String offlineJuzNumber(int juz) => _t("Juz' $juz", 'الجزء $juz',
      'پارہ $juz', 'Juz $juz', "Juz' $juz");
  String get offlinePickJuz => _t('Choose a juz', 'اختر جزءًا',
      'پارہ منتخب کریں', 'Pilih juz', 'Juz wählen');

  /// The shelf of sceneries to keep on the phone, one at a time.
  String get offlineScenes => _t('Sceneries', 'المشاهد', 'مناظر',
      'Pemandangan', 'Kulissen');
  String get offlineChangeVoice => _t('Change voice', 'غيّر القارئ',
      'قاری بدلیں', 'Ganti qari', 'Stimme ändern');
  String get offlineStills => _t('Still sceneries', 'المناظر الثابتة',
      'ساکن مناظر', 'Pemandangan diam', 'Stehende Kulissen');
  String get offlineClips => _t('Moving sceneries', 'المناظر المتحركة',
      'متحرک مناظر', 'Pemandangan bergerak', 'Bewegte Kulissen');
  String offlineScenesNote(int n, String size) => _t(
      '$n · $size', '$n · $size', '$n · $size', '$n · $size', '$n · $size');
  String offlineTotal(String size) => _t(
      'About $size · best on Wi-Fi',
      'نحو $size · الأفضل عبر Wi-Fi',
      'تقریباً $size · وائی فائی پر بہتر',
      'Sekitar $size · sebaiknya lewat Wi-Fi',
      'Etwa $size · am besten im WLAN');
  String get offlineStart =>
      _t('Download', 'تنزيل', 'ڈاؤن لوڈ', 'Unduh', 'Laden');
  String get offlineStop =>
      _t('Stop', 'إيقاف', 'روکیں', 'Hentikan', 'Stopp');
  String offlineRunning(int pct) => _t(
      'Downloading… $pct%',
      'جارٍ التنزيل… $pct%',
      'ڈاؤن لوڈ ہو رہا ہے… $pct%',
      'Mengunduh… $pct%',
      'Lädt … $pct %');
  String get offlineOnPhone => _t('On your phone', 'على هاتفك',
      'آپ کے فون پر', 'Di ponselmu', 'Auf dem Handy');
  String get offlineDone => _t(
      'Done. Reels work with no internet now.',
      'تمّ. تعمل المقاطع الآن دون إنترنت.',
      'ہو گیا۔ اب ریلز انٹرنیٹ کے بغیر بنیں گی۔',
      'Selesai. Reel kini bisa dibuat tanpa internet.',
      'Fertig. Reels gehen jetzt ohne Internet.');
  String offlineMissed(int n) => _t(
      '$n files did not come. Tap Download to try them again.',
      'لم يصل $n ملفًا. اضغط «تنزيل» لإعادة المحاولة.',
      '$n فائلیں نہیں آئیں۔ دوبارہ کوشش کے لیے ڈاؤن لوڈ دبائیں۔',
      '$n berkas belum masuk. Ketuk Unduh untuk mencoba lagi.',
      '$n Dateien kamen nicht. Tippe auf Laden, um es nochmal zu versuchen.');
  String get offlineNoNet => _t(
      'No connection. What came down is kept: tap Download to carry on.',
      'لا يوجد اتصال. ما نُزّل محفوظ: اضغط «تنزيل» لتكمل.',
      'کنکشن نہیں۔ جو آ گیا وہ محفوظ ہے: جاری رکھنے کے لیے ڈاؤن لوڈ دبائیں۔',
      'Tidak ada koneksi. Yang sudah masuk tetap tersimpan: ketuk Unduh untuk lanjut.',
      'Keine Verbindung. Was da ist, bleibt: Tippe auf Laden, um weiterzumachen.');
  String get offlineFull => _t(
      'Your phone is full. Free some space, then tap Download to carry on.',
      'مساحة هاتفك ممتلئة. أفرغ بعض المساحة ثم اضغط «تنزيل» لتكمل.',
      'فون بھر گیا ہے۔ کچھ جگہ خالی کریں، پھر ڈاؤن لوڈ دبائیں۔',
      'Ponselmu penuh. Kosongkan sedikit ruang, lalu ketuk Unduh untuk lanjut.',
      'Dein Handy ist voll. Mach etwas Platz frei und tippe dann auf Laden.');
  String get offlineStopped => _t(
      'Stopped. What came down is kept.',
      'توقّف. ما نُزّل محفوظ.',
      'روک دیا گیا۔ جو آ گیا وہ محفوظ ہے۔',
      'Dihentikan. Yang sudah masuk tetap tersimpan.',
      'Angehalten. Was da ist, bleibt.');

  String get noReciterMatch => _t(
      'No reciter by that name',
      'لا يوجد قارئ بهذا الاسم',
      'اس نام کا کوئی قاری نہیں',
      'Tidak ada qari dengan nama itu',
      'Kein Rezitator mit diesem Namen');
  String get continueLabel =>
      _t('Continue', 'متابعة', 'جاری رکھیں', 'Lanjutkan', 'Weiter');

  /// Marks the reciters whose recordings have released word-by-word
  /// timings, so their reels light the ayah one word at a time. Kept
  /// to a whisper beside the name: it is a bonus on a voice, never a
  /// reason to pick one.
  String get perWordHighlight => _t('Per-word highlight', 'تمييز كل كلمة',
      'ہر لفظ نمایاں', 'Sorot per kata', 'Wort-für-Wort-Hervorhebung');

  /// Over the numbered chips of a voice with more than one recording.
  /// Another recording is the same reciter in another performance, so
  /// reels of the same verses can sound different.
  String get recordingsLabel => _t('Recordings', 'التسجيلات', 'ریکارڈنگز',
      'Rekaman', 'Aufnahmen');

  /// A recording chip, read aloud: which of how many, and what sets it
  /// apart when the list says.
  String a11yRecording(int n, int of, String? note) => _t(
      'Recording $n of $of${note == null ? '' : ', $note'}',
      'التسجيل $n من $of${note == null ? '' : '، $note'}',
      'ریکارڈنگ $n از $of${note == null ? '' : '، $note'}',
      'Rekaman $n dari $of${note == null ? '' : ', $note'}',
      'Aufnahme $n von $of${note == null ? '' : ', $note'}');

  /// Under the chips, a hint that is only true while the voice has more
  /// than one: a different recording is a different sound for the same
  /// verses.
  String get recordingsHint => _t(
      'Same voice, another recitation',
      'الصوت نفسه، تلاوة أخرى',
      'وہی آواز، دوسری تلاوت',
      'Suara sama, bacaan lain',
      'Dieselbe Stimme, eine andere Rezitation');

  // ---- creation wizard: your own audio ---------------------------
  String get useYourOwnAudio => _t('Use your own audio', 'استخدم صوتك',
      'اپنی آڈیو استعمال کریں', 'Pakai audio sendiri', 'Eigene Audio nutzen');

  /// Two short sentences: the card gives this two lines, and the
  /// sheet behind it already says what happens to a video.
  String get useYourOwnAudioBody => _t(
      'Upload a recitation from your phone. A video works too.',
      'ارفع تلاوة من هاتفك. والفيديو يصلح أيضًا.',
      'اپنے فون سے تلاوت اپ لوڈ کریں۔ ویڈیو بھی چل جائے گی۔',
      'Unggah rekaman dari ponsel Anda. Video pun bisa.',
      'Lade eine Rezitation vom Handy hoch. Ein Video geht auch.');

  /// Title of the sheet that asks where the recording is.
  String get whereIsYourAudio => _t('Where is it?', 'أين تسجيلك؟',
      'وہ کہاں ہے؟', 'Di mana filenya?', 'Wo liegt sie?');
  String get pickAudioFile =>
      _t('Audio file', 'ملف صوتي', 'آڈیو فائل', 'Berkas audio', 'Audiodatei');
  String get pickAudioFileBody => _t('MP3, M4A, WAV and the rest',
      'MP3، M4A، WAV وغيرها', 'MP3، M4A، WAV وغیرہ', 'MP3, M4A, WAV, dan lainnya',
      'MP3, M4A, WAV und der Rest');
  String get pickVideoFile =>
      _t('Video', 'فيديو', 'ویڈیو', 'Video', 'Video');
  String get pickVideoFileBody => _t(
      'We take the sound out of it',
      'نأخذ الصوت منه',
      'ہم اس سے آواز نکال لیں گے',
      'Kami ambil suaranya saja',
      'Wir holen den Ton heraus');
  String get preparingYourAudio => _t('Preparing your audio…', 'نُجهّز صوتك…',
      'آپ کی آڈیو تیار ہو رہی ہے…', 'Menyiapkan audio Anda…',
      'Deine Audio wird vorbereitet …');
  String get chooseAnotherFile => _t('Choose another file', 'اختر ملفًا آخر',
      'دوسری فائل منتخب کریں', 'Pilih berkas lain', 'Andere Datei wählen');

  /// The stand-in voice an upload is carried under. Sits where a
  /// reciter's name would, in the picker and on a saved reel.
  String get yourRecitation => _t('Your recitation', 'تسجيلك', 'آپ کی تلاوت',
      'Rekaman Anda', 'Deine Rezitation');
  String get yourAudioStyle => _t('Your own audio', 'صوتك الخاص',
      'آپ کی اپنی آڈیو', 'Audio Anda sendiri', 'Deine eigene Audio');

  /// Why an uploaded file could not be used. One line per way it can
  /// fail, so the user is told what to do about it rather than that
  /// something went wrong.
  String userAudioError(String kind) {
    switch (kind) {
      case 'noAudio':
        return _t(
            'There is no sound in that file.',
            'لا صوت في هذا الملف.',
            'اس فائل میں کوئی آواز نہیں ہے۔',
            'Tidak ada suara dalam berkas itu.',
            'In dieser Datei ist kein Ton.');
      case 'tooShort':
        return _t(
            'That recording is too short to hold a verse.',
            'هذا التسجيل أقصر من أن يحمل آية.',
            'یہ ریکارڈنگ اتنی مختصر ہے کہ ایک آیت بھی نہیں سما سکتی۔',
            'Rekaman itu terlalu pendek untuk memuat satu ayat.',
            'Diese Aufnahme ist zu kurz für einen Vers.');
      default:
        return _t(
            'Could not read that file. Try an audio file, or a video.',
            'تعذّر قراءة هذا الملف. جرّب ملفًا صوتيًا أو فيديو.',
            'یہ فائل پڑھی نہیں جا سکی۔ کوئی آڈیو فائل یا ویڈیو آزمائیں۔',
            'Berkas itu tidak terbaca. Coba berkas audio atau video.',
            'Diese Datei ließ sich nicht lesen. Versuch eine Audiodatei oder ein Video.');
    }
  }

  // ---- creation wizard: matching an upload to the verses ---------
  String get matchTheVerses => _t('Match the verses', 'طابق الآيات',
      'آیات کو ملائیں', 'Cocokkan ayat', 'Verse zuordnen');
  String get matchTheVersesBody => _t(
      'Every verse is placed on your audio. Play it, and move '
          'anything that sits wrong.',
      'وضعنا كل آية على صوتك. شغّله، وحرّك ما وقع في غير موضعه.',
      'ہر آیت آپ کی آڈیو پر رکھ دی گئی ہے۔ چلائیں، اور جو غلط جگہ ہو اسے کھسکا دیں۔',
      'Setiap ayat sudah ditempatkan pada audio Anda. Putar, lalu geser yang kurang pas.',
      'Jeder Vers liegt auf deiner Audio. Spiel sie ab und verschieb, was nicht sitzt.');
  String get listeningToYourAudio => _t('Listening to your audio…',
      'نستمع إلى تسجيلك…', 'آپ کی آڈیو سنی جا رہی ہے…',
      'Mendengarkan audio Anda…', 'Deine Audio wird abgehört …');
  String get placeThemAgain => _t('Place them again', 'أعد التوزيع',
      'دوبارہ ترتیب دیں', 'Tempatkan ulang', 'Neu verteilen');
  String get tapAlong => _t('Tap along', 'انقر مع التلاوة', 'ساتھ ساتھ ٹیپ کریں',
      'Ketuk mengikuti', 'Mittippen');
  String get tapAlongBody => _t(
      'Play the recording, and tap as each verse begins.',
      'شغّل التسجيل، وانقر عند بداية كل آية.',
      'ریکارڈنگ چلائیں، اور ہر آیت کے آغاز پر ٹیپ کریں۔',
      'Putar rekamannya, lalu ketuk setiap kali ayat dimulai.',
      'Spiel die Aufnahme ab und tippe, wenn ein Vers beginnt.');
  String tapAlongNext(int ayah) => _t(
      'Verse $ayah starts now',
      'الآية $ayah تبدأ الآن',
      'آیت $ayah اب شروع ہو رہی ہے',
      'Ayat $ayah dimulai sekarang',
      'Vers $ayah beginnt jetzt');
  String get tapAlongFinish =>
      _t('Finish', 'أنهِ', 'ختم کریں', 'Selesai', 'Fertig');

  /// Over tap-along's own arrows: what they act on is the tap just
  /// made, not the verse selected in the list behind them.
  String get moveTheLastTap => _t(
      'Move the last tap, or start over',
      'حرّك آخر نقرة، أو ابدأ من جديد',
      'آخری ٹیپ کھسکائیں، یا نئے سرے سے شروع کریں',
      'Geser ketukan terakhir, atau mulai lagi',
      'Letztes Tippen verschieben oder neu anfangen');
  String get startsHere => _t('Starts here', 'تبدأ هنا', 'یہاں سے شروع',
      'Mulai di sini', 'Beginnt hier');
  String get dragTheHandles => _t(
      'Drag the gold handles, or pick a verse and set its start.',
      'اسحب المقابض الذهبية، أو اختر آية واضبط بدايتها.',
      'سنہری ہینڈل کھینچیں، یا کوئی آیت چن کر اس کا آغاز مقرر کریں۔',
      'Seret pegangan emas, atau pilih ayat lalu tentukan awalnya.',
      'Zieh die goldenen Griffe, oder wähl einen Vers und setz seinen Anfang.');
  String get verseLabel => _t('Verse', 'آية', 'آیت', 'Ayat', 'Vers');
  String timingTrimmedToAyah(int ayah) => _t(
      'Your audio fits up to ayah $ayah within the reel cap.',
      'صوتك يتسع حتى الآية $ayah ضمن حدّ المقطع.',
      'ریل کی حد میں آپ کی آڈیو آیت $ayah تک سماتی ہے۔',
      'Dalam batas reel, audio Anda muat sampai ayat $ayah.',
      'Innerhalb der Reel-Grenze passt deine Audio bis Vers $ayah.');

  /// A position in a recording: m:ss, or h:mm:ss past an hour.
  String clock(int ms) {
    final total = ms < 0 ? 0 : (ms / 1000).floor();
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    final ss = s.toString().padLeft(2, '0');
    if (h == 0) return '$m:$ss';
    return '$h:${m.toString().padLeft(2, '0')}:$ss';
  }

  // ---- creation wizard: verses -----------------------------------
  String get chooseTheVerses => _t('Choose the verses', 'اختر الآيات',
      'آیات منتخب کریں', 'Pilih ayat', 'Verse wählen');
  String get tapFirstThenLast => _t(
      'Tap the first verse, then the last.',
      'انقر الآية الأولى، ثم الأخيرة.',
      'پہلی آیت ٹیپ کریں، پھر آخری۔',
      'Ketuk ayat pertama, lalu yang terakhir.',
      'Tippe den ersten Vers an, dann den letzten.');

  /// The verse picker's "?" sheet: its rules, a line each.
  String get versesHowToTitle => _t('How to choose verses',
      'كيف تختار الآيات', 'آیات کیسے چنیں', 'Cara memilih ayat',
      'So wählst du Verse');
  String get versesHowToRange => _t(
      'Tap the first verse, then the last: everything between is chosen.',
      'انقر الآية الأولى ثم الأخيرة، فيُختار كل ما بينهما.',
      'پہلی آیت ٹیپ کریں، پھر آخری: درمیان کی سب آیات چن لی جائیں گی۔',
      'Ketuk ayat pertama, lalu yang terakhir: semua di antaranya ikut terpilih.',
      'Tippe den ersten Vers an, dann den letzten: alles dazwischen ist gewählt.');
  String get versesHowToEdges => _t(
      'Tap the first or last chosen verse to drop it, or the one just '
          'outside to add it.',
      'انقر أول آية مختارة أو آخرها لتحذفها، أو الآية التي تليها مباشرة لتضيفها.',
      'منتخب آیات میں سے پہلی یا آخری کو ٹیپ کریں تو وہ ہٹ جائے گی، ساتھ والی کو ٹیپ کریں تو شامل ہو جائے گی۔',
      'Ketuk ayat pertama atau terakhir yang terpilih untuk melepasnya, '
          'atau ayat tepat di sebelahnya untuk menambahkannya.',
      'Tippe den ersten oder letzten gewählten Vers an, um ihn abzuwählen, '
          'oder den direkt daneben, um ihn hinzuzufügen.');
  String get versesHowToRestart => _t(
      'Tap a verse further away to start again from it.',
      'انقر آية أبعد لتبدأ اختيارًا جديدًا منها.',
      'دور کی کسی آیت کو ٹیپ کریں تو وہیں سے نیا انتخاب شروع ہو گا۔',
      'Ketuk ayat yang lebih jauh untuk mulai lagi dari situ.',
      'Tippe einen weiter entfernten Vers an, um dort neu zu beginnen.');
  String get versesHowToHold => _t(
      'Hold a verse to stretch your selection to it.',
      'اضغط مطوّلًا على آية لتمدّ اختيارك إليها.',
      'کسی آیت کو دبائے رکھیں تاکہ انتخاب وہاں تک پھیل جائے۔',
      'Tahan sebuah ayat untuk merentangkan pilihanmu sampai ke sana.',
      'Halte einen Vers gedrückt, um deine Auswahl bis dorthin zu ziehen.');
  String get versesHowToListen => _t(
      'Tap a verse’s number to hear it.',
      'انقر رقم الآية لتسمعها.',
      'آیت سننے کے لیے اس کے نمبر پر ٹیپ کریں۔',
      'Ketuk nomor ayat untuk mendengarkannya.',
      'Tippe auf die Nummer eines Verses, um ihn zu hören.');

  /// The toast when a tap far from the run starts a new one.
  String versesStartedAgain(int n) => _t(
      'Started again from ayah $n',
      'بدأ اختيار جديد من الآية $n',
      'آیت $n سے نیا انتخاب شروع ہوا',
      'Mulai lagi dari ayat $n',
      'Neu begonnen ab Vers $n');
  String get undo =>
      _t('Undo', 'تراجع', 'واپس', 'Urungkan', 'Rückgängig');
  String get surahLoadError => _t(
      'Could not load the surah text.\nCheck your connection and try again.',
      'تعذّر تحميل نص السورة.\nتحقق من اتصالك وحاول مجددًا.',
      'سورت کا متن لوڈ نہیں ہو سکا۔\nاپنا کنکشن دیکھیں اور دوبارہ کوشش کریں۔',
      'Teks surah tidak dapat dimuat.\nPeriksa koneksi Anda lalu coba lagi.',
      'Der Surentext ließ sich nicht laden.\nPrüf deine Verbindung und versuch es erneut.');

  /// The surah text failed for a reason that isn't the connection — the
  /// server answered with something unusable. See [surahLoadError] for
  /// the offline one.
  String get surahTextFailed => _t(
      'Could not load the surah text.\nTry again in a little while.',
      'تعذّر تحميل نص السورة.\nحاول بعد قليل.',
      'سورت کا متن لوڈ نہیں ہو سکا۔\nتھوڑی دیر بعد دوبارہ کوشش کریں۔',
      'Teks surah tidak dapat dimuat.\nCoba lagi sebentar lagi.',
      'Der Surentext ließ sich nicht laden.\nVersuch es gleich noch einmal.');
  String get tryAgain => _t('Try again', 'حاول مجددًا', 'دوبارہ کوشش کریں',
      'Coba lagi', 'Erneut versuchen');
  String get reelCapReached => _t(
      'Reels are capped at ${ReelLimits.maxReelMinutes} minutes — '
          'that is the last ayah that fits.',
      'الحد الأقصى للمقطع ${ReelLimits.maxReelMinutes} دقيقة — هذه آخر آية تتسع.',
      'ریل کی حد ${ReelLimits.maxReelMinutes} منٹ ہے — اس میں یہی آخری آیت سماتی ہے۔',
      'Reel dibatasi ${ReelLimits.maxReelMinutes} menit — itu ayat terakhir yang muat.',
      'Reels sind auf ${ReelLimits.maxReelMinutes} Minuten begrenzt — das ist der letzte Vers, der passt.');
  String get searchSurahHint => _t(
      'Surah, ayah "2:255", or any words of one',
      'سورة، أو آية «2:255»، أو كلمات منها',
      'سورت، آیت «2:255»، یا آیت کے الفاظ',
      'Surah, ayat "2:255", atau kata dalam ayat',
      'Sure, Vers „2:255“ oder Wörter eines Verses');

  /// The heading over the verses a word search found.
  String versesMatching(int n) => _t(
      n >= 40 ? 'VERSES WITH THESE WORDS · FIRST $n' : 'VERSES WITH THESE WORDS · $n',
      n >= 40 ? 'آيات فيها هذه الكلمات · الأولى $n' : 'آيات فيها هذه الكلمات · $n',
      n >= 40 ? 'ان الفاظ والی آیات · پہلی $n' : 'ان الفاظ والی آیات · $n',
      n >= 40 ? 'AYAT DENGAN KATA INI · $n PERTAMA' : 'AYAT DENGAN KATA INI · $n',
      n >= 40 ? 'VERSE MIT DIESEN WÖRTERN · ERSTE $n' : 'VERSE MIT DIESEN WÖRTERN · $n');

  /// The picker row's line when the search named an ayah.
  String goToAyah(int a, int e) => _t(
      a == e ? 'Go to ayah $a' : 'Go to ayahs $a–$e',
      a == e ? 'إلى الآية $a' : 'إلى الآيات $a–$e',
      a == e ? 'آیت $a پر جائیں' : 'آیات $a–$e پر جائیں',
      a == e ? 'Ke ayat $a' : 'Ke ayat $a–$e',
      a == e ? 'Zu Vers $a' : 'Zu den Versen $a–$e');
  /// The Quran half of the card finder searches the verse itself in
  /// Arabic and the translation in anything else, so the hint has to
  /// promise both without naming five languages.
  String get findVerseHint => _t(
      'A word of a verse, in Arabic or your language',
      'كلمة من آية، بالعربية أو بلغتك',
      'آیت کا کوئی لفظ، عربی میں یا اپنی زبان میں',
      'Sepotong kata dari ayat, dalam bahasa Arab atau bahasamu',
      'Ein Wort aus einem Vers, auf Arabisch oder in deiner Sprache');

  String get noSurahMatch => _t('No surah matches that', 'لا توجد سورة مطابقة',
      'کوئی سورت اس سے میل نہیں کھاتی', 'Tidak ada surah yang cocok',
      'Keine Sure passt dazu');

  /// While a search of the translation is still out. The Arabic index
  /// answers from memory and never shows this.
  String get searching => _t('Searching…', 'يجري البحث…', 'تلاش ہو رہی ہے…',
      'Mencari…', 'Suche läuft…');

  /// How long the reel runs, in the coarsest unit that still says
  /// something: seconds under a minute, minutes and seconds under an
  /// hour, hours and minutes past it.
  String reelLength(int ms) {
    final total = (ms / 1000).round();
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    if (h > 0) {
      return _t('${h}h ${_two(m)}m reel', 'مقطع $h:${_two(m)} ساعة',
          '$h:${_two(m)} گھنٹے کی ریل', 'Reel $h j ${_two(m)} mnt',
          '$h Std. ${_two(m)} Min. Reel');
    }
    if (m > 0) {
      return _t('${m}m ${_two(s)}s reel', 'مقطع $m:${_two(s)} دقيقة',
          '$m:${_two(s)} منٹ کی ریل', 'Reel $m mnt ${_two(s)} dtk',
          '$m Min. ${_two(s)} Sek. Reel');
    }
    return _t('${s}s reel', 'مقطع $s ثانية', '$s سیکنڈ کی ریل',
        'Reel $s dtk', '$s Sek. Reel');
  }

  static String _two(int n) => n < 10 ? '0$n' : '$n';

  /// [reelLength] for a length nobody has measured yet — the picker's
  /// estimate, before the recitation is on the device. Marked as an
  /// estimate wherever it is shown, so a reel that comes out a minute
  /// either side of it reads as expected rather than as a fault.
  String reelLengthAbout(int ms) => _t(
      '~${reelLength(ms)}',
      'نحو ${reelLength(ms)}',
      'تقریباً ${reelLength(ms)}',
      '±${reelLength(ms)}',
      'ca. ${reelLength(ms)}');

  String continueWith(String length) => '$continueLabel · $length';

  /// The banner on the verse picker when the run is longer than a reel
  /// may be. Says the cap, and the way out is the button beside it.
  String get overReelCap => _t(
      'This selection runs past ${ReelLimits.maxReelMinutes} minutes, '
          'which is as long as a reel can be.',
      'هذا الاختيار أطول من ${ReelLimits.maxReelMinutes} دقيقة — '
          'وهي أقصى مدة للمقطع.',
      'یہ انتخاب ${ReelLimits.maxReelMinutes} منٹ سے آگے نکل جاتا ہے، اور ریل اس سے لمبی نہیں ہو سکتی۔',
      'Pilihan ini melewati ${ReelLimits.maxReelMinutes} menit, dan itu batas panjang sebuah reel.',
      'Diese Auswahl überschreitet ${ReelLimits.maxReelMinutes} Minuten — länger darf ein Reel nicht sein.');

  /// Cuts the selection back to what fits, from the picker's banner.
  String get trimToFit => _t('Trim to fit', 'قصّه ليتّسع', 'حسبِ گنجائش کاٹیں',
      'Pangkas agar muat', 'Passend kürzen');

  // ---- the verse picker's live recitation -------------------------
  // The surah plays at the head of the verse picker, and the list
  // follows the voice. These are its controls, said aloud.
  String get liveBack10 => _t('Back 10 seconds', 'رجوع 10 ثوانٍ',
      '10 سیکنڈ پیچھے', 'Mundur 10 detik', '10 Sekunden zurück');
  String get liveForward10 => _t('Forward 10 seconds', 'تقدّم 10 ثوانٍ',
      '10 سیکنڈ آگے', 'Maju 10 detik', '10 Sekunden vor');
  String get liveLoading => _t('Loading the recitation', 'جارٍ تحميل التلاوة',
      'تلاوت لوڈ ہو رہی ہے', 'Memuat bacaan', 'Rezitation wird geladen');
  String get liveFailed => _t(
      'The recitation didn’t load. Tap to try again.',
      'تعذّر تحميل التلاوة. انقر للمحاولة مجددًا.',
      'تلاوت لوڈ نہیں ہو سکی۔ دوبارہ کوشش کے لیے ٹیپ کریں۔',
      'Bacaan tidak dapat dimuat. Ketuk untuk mencoba lagi.',
      'Die Rezitation ließ sich nicht laden. Tippe, um es erneut zu versuchen.');
  String get a11yLiveLine => _t('Recitation', 'التلاوة', 'تلاوت', 'Bacaan',
      'Rezitation');

  /// '1 verse' / 'n verses', with Arabic dual and plural forms.
  String versesCount(int n) => switch (lang) {
        AppLang.en => n == 1 ? '1 verse' : '$n verses',
        AppLang.ar => n == 1
            ? 'آية واحدة'
            : n == 2
                ? 'آيتان'
                : n <= 10
                    ? '$n آيات'
                    : '$n آية',
        AppLang.ur => n == 1 ? 'ایک آیت' : '$n آیات',
        AppLang.id => '$n ayat',
        AppLang.de => n == 1 ? '1 Vers' : '$n Verse',
      };

  /// Chip label for a template length: 'Ayah 56' / 'Ayahs 56–57'.
  String ayahRange(int start, int end) => switch (lang) {
        AppLang.en => end == start ? 'Ayah $start' : 'Ayahs $start–$end',
        AppLang.ar => end == start
            ? 'الآية $start'
            : end == start + 1
                ? 'الآيتان $start–$end'
                : 'الآيات $start–$end',
        AppLang.ur => end == start ? 'آیت $start' : 'آیات $start–$end',
        AppLang.id => end == start ? 'Ayat $start' : 'Ayat $start–$end',
        AppLang.de => end == start ? 'Vers $start' : 'Verse $start–$end',
      };

  // ---- creation wizard: scenery ----------------------------------
  String get chooseTheScenery => _t('Choose the scenery', 'اختر المشهد',
      'منظر منتخب کریں', 'Pilih pemandangan', 'Kulisse wählen');
  String get sceneryBody => _t(
      "Pick one, or use a photo or video from your "
          "gallery. You'll see the verses on it next.",
      'اختر واحدًا، أو استخدم صورة أو فيديو من معرضك. '
          'سترى الآيات عليه في الخطوة التالية.',
      'کوئی ایک چنیں، یا اپنی گیلری سے تصویر یا ویڈیو لیں۔ '
          'اگلے مرحلے میں آیات اسی پر نظر آئیں گی۔',
      'Pilih satu, atau pakai foto atau video dari galeri Anda. '
          'Ayatnya akan tampil di atasnya berikutnya.',
      'Wähl eine aus, oder nimm ein Foto oder Video aus deiner '
          'Galerie. Die Verse siehst du gleich darauf.');

  // ---- creation wizard: scenery tour ------------------------------
  /// Coach marks shown once, the first time this screen opens.
  String get tourNext => _t('OK', 'حسنًا', 'ٹھیک ہے', 'Oke', 'OK');
  String get tourDone =>
      _t('Got it', 'تم', 'سمجھ گیا', 'Paham', 'Verstanden');
  String tourStepOf(int step, int total) => _t('$step of $total',
      '$step من $total', '$total میں سے $step', '$step dari $total',
      '$step von $total');
  String get tourThemesTitle => _t('Choose a place', 'اختر مكانًا',
      'جگہ چنیں', 'Pilih tempat', 'Wähl einen Ort');
  String get tourThemesBody => _t(
      'Nearly 1,900 sceneries by place: sky, water, mountains, sacred '
          'places and more. Tap one to set it behind your verses. The '
          'first pill picks one for each verse by itself.',
      'قرابة 1900 مشهد حسب المكان: سماء، ماء، جبال، أماكن مقدسة وغيرها. '
          'انقر مشهدًا ليظهر خلف آياتك. وأول زر يختار لكل آية مشهدًا '
          'بنفسه.',
      'جگہ کے حساب سے تقریباً 1900 مناظر: آسمان، پانی، پہاڑ، مقدس مقامات '
          'اور بہت کچھ۔ کسی منظر کو ٹیپ کریں تو وہ آیات کے پیچھے آ جائے۔ '
          'پہلا بٹن ہر آیت کے لیے خود منظر چنتا ہے۔',
      'Hampir 1.900 pemandangan menurut tempat: langit, air, gunung, '
          'tempat suci, dan lainnya. Ketuk satu untuk memasangnya di '
          'belakang ayat. Tombol pertama memilihkan satu untuk tiap ayat.',
      'Fast 1.900 Kulissen nach Ort: Himmel, Wasser, Berge, heilige Orte '
          'und mehr. Tippe eine an, um sie hinter deine Verse zu legen. '
          'Der erste Knopf wählt selbst eine für jeden Vers.');
  String get tourMultiTitle => _t('A scenery for each verse',
      'مشهد لكل آية', 'ہر آیت کے لیے منظر', 'Pemandangan per ayat',
      'Eine Kulisse je Vers');
  String get tourMultiBody => _t(
      'Turn this on and tap several: the reel moves through them, verse '
          'by verse or line by line, in the order you tap them.',
      'فعّل هذا وانقر عدة مشاهد: يمرّ المقطع عليها آيةً آيةً أو سطرًا '
          'سطرًا، بالترتيب الذي نقرتها به.',
      'اسے آن کر کے کئی منظر ٹیپ کریں: ریل انہی میں آیت بہ آیت یا سطر بہ '
          'سطر اسی ترتیب سے گزرے گی جس سے آپ نے ٹیپ کیا۔',
      'Aktifkan ini lalu ketuk beberapa: reel berpindah di antaranya, '
          'ayat demi ayat atau baris demi baris, sesuai urutan ketukan.',
      'Schalte das ein und tippe mehrere an: das Reel geht sie Vers für '
          'Vers oder Zeile für Zeile durch, in deiner Reihenfolge.');
  String get tourFrameTitle => _t('Full screen or wide card',
      'ملء الشاشة أو بطاقة عريضة', 'پوری اسکرین یا چوڑا کارڈ',
      'Layar penuh atau kartu lebar', 'Vollbild oder breite Karte');
  String get tourFrameBody => _t(
      'Full screen fills the frame with the scenery. Wide card keeps a '
          'landscape video whole, with the verse beneath it.',
      '«ملء الشاشة» يملأ الإطار بالمشهد. «البطاقة العريضة» تُبقي الفيديو '
          'الأفقي كاملًا والآية تحته.',
      '«پوری اسکرین» فریم کو منظر سے بھر دیتی ہے۔ «چوڑا کارڈ» افقی ویڈیو '
          'کو پورا رکھتا ہے، اور آیت اس کے نیچے۔',
      '"Layar penuh" mengisi bingkai dengan pemandangan. "Kartu lebar" '
          'menjaga video horizontal tetap utuh, dengan ayat di bawahnya.',
      '„Vollbild“ füllt den Rahmen mit der Kulisse. „Breite Karte“ lässt '
          'ein Querformat-Video ganz, mit dem Vers darunter.');
  String get tourResetTitle => _t('Start over', 'ابدأ من جديد',
      'دوبارہ شروع کریں', 'Mulai lagi', 'Neu anfangen');
  String get tourResetBody => _t(
      'Clears every scenery chosen for this reel.',
      'يزيل كل المشاهد المختارة لهذا المقطع.',
      'اس ریل کے لیے چنے گئے سب مناظر ہٹا دیتا ہے۔',
      'Menghapus semua pemandangan yang dipilih untuk reel ini.',
      'Entfernt alle für dieses Reel gewählten Kulissen.');

  // ---- creation wizard: several sceneries ------------------------
  String get multipleScenes => _t('Multiple scenes', 'مشاهد متعددة',
      'متعدد مناظر', 'Beberapa adegan', 'Mehrere Szenen');

  /// Picker pill once multi-scene is on: how many are chosen out of
  /// how many this reel takes.
  String scenesChosen(int n, int of) => _t('$n of $of', '$n من $of',
      '$of میں سے $n', '$n dari $of', '$n von $of');

  /// Replaces the scenery blurb while several are being picked: what
  /// tapping does here, now that it adds to a run rather than choosing
  /// one scenery. What the run should *hold* is [sceneryFills], which
  /// is advice and stands on its own line.
  String get sceneryMultiBody => _t(
      'Tap the sceneries you want, in the order you want them. '
          'Fewer, and a scene carries several verses; more, and a '
          'verse takes several.',
      'انقر المشاهد بالترتيب الذي تريده. أقل: يحمل المشهد أكثر من '
          'آية. أكثر: تتقاسم الآية مشهدين.',
      'جو مناظر چاہیں اسی ترتیب سے ٹیپ کریں جس ترتیب سے چاہیں۔ '
          'کم ہوں تو ایک منظر کئی آیات اٹھاتا ہے؛ زیادہ ہوں تو ایک آیت '
          'کئی مناظر لے لیتی ہے۔',
      'Ketuk pemandangan yang Anda mau, sesuai urutan yang Anda mau. '
          'Makin sedikit, satu adegan membawa beberapa ayat; makin banyak, '
          'satu ayat memakai beberapa adegan.',
      'Tippe die Kulissen in der Reihenfolge an, die du willst. Weniger, '
          'und eine Szene trägt mehrere Verse; mehr, und ein Vers nimmt mehrere.');

  /// The recommendation itself: how many sceneries these verses ask
  /// for. Gold, above the frame — it is the only line on that screen
  /// telling the user what to aim at.
  String sceneryFills(int n) => _t(
      'A scene per verse — $n fills this reel.',
      'مشهد لكل آية — $n تملأ هذا المقطع.',
      'ہر آیت کے لیے ایک منظر — $n سے یہ ریل بھر جاتی ہے۔',
      'Satu adegan per ayat — $n mengisi reel ini.',
      'Eine Szene pro Vers — $n füllen dieses Reel.');

  /// The same, when the reel's long verses go line by line and the
  /// scenery follows the lines.
  String sceneryFillsLines(int n) => _t(
      'A scene per line — $n fills this reel.',
      'مشهد لكل سطر — $n تملأ هذا المقطع.',
      'ہر سطر کے لیے ایک منظر — $n سے یہ ریل بھر جاتی ہے۔',
      'Satu adegan per baris — $n mengisi reel ini.',
      'Eine Szene pro Zeile — $n füllen dieses Reel.');

  /// Refusing a scene past what the reel can hold.
  String sceneLimit(int n) => _t(
      'This reel holds $n scenes.',
      // Arabic counts: one, two, three to ten, eleven and up.
      'هذا المقطع يتسع ${n == 1 ? 'لمشهد واحد' : n == 2 ? 'لمشهدين' : n <= 10 ? 'لـ $n مشاهد' : 'لـ $n مشهدًا'}.',
      'اس ریل میں $n مناظر سماتے ہیں۔',
      'Reel ini memuat $n adegan.',
      'Dieses Reel fasst $n Szenen.');

  String get scenesLabel =>
      _t('Scenes', 'المشاهد', 'مناظر', 'Adegan', 'Szenen');
  String get scenePace => _t('Pace of scenes', 'إيقاع المشاهد',
      'مناظر کی رفتار', 'Tempo adegan', 'Tempo der Szenen');
  String get pacePerVerse => _t('Per verse', 'لكل آية', 'فی آیت', 'Per ayat',
      'Pro Vers');
  String get paceEven => _t('Even', 'متساوٍ', 'برابر', 'Merata', 'Gleichmäßig');
  String get sceneBlend =>
      _t('Blend', 'الانتقال', 'انتقال', 'Transisi', 'Übergang');
  String get blendCut => _t('Cut', 'قطع', 'کٹ', 'Potong', 'Schnitt');
  String get blendFade =>
      _t('Fade', 'تلاشٍ', 'دھیرے دھیرے', 'Pudar', 'Blende');

  /// The one-line summary on the collapsed control: 'Scenes · 5 · Fade'.
  String scenesSummary(int n, String blend) => '$scenesLabel · $n · $blend';

  /// A clip is shorter than the turn it was given. The reel will not be
  /// finished by freezing or looping it, so the way out is more scenes
  /// — which is also fewer seconds each.
  String scenesTooShort(int n) => _t(
      n == 1
          ? 'One clip is shorter than its turn. Add another scene, or swap it.'
          : '$n clips are shorter than their turn. Add more scenes, or swap them.',
      n == 1
          ? 'لقطة واحدة أقصر من دورها. أضف مشهدًا آخر، أو استبدلها.'
          : n == 2
              ? 'لقطتان أقصر من دورهما. أضف مشاهد أخرى، أو استبدلهما.'
              : n <= 10
                  ? '$n لقطات أقصر من دورها. أضف مشاهد أخرى، أو استبدلها.'
                  : '$n لقطةً أقصر من دورها. أضف مشاهد أخرى، أو استبدلها.',
      n == 1
          ? 'ایک کلپ اپنی باری سے چھوٹا ہے۔ ایک اور منظر شامل کریں، یا اسے بدل دیں۔'
          : '$n کلپ اپنی باری سے چھوٹے ہیں۔ مزید مناظر شامل کریں، یا انہیں بدل دیں۔',
      n == 1
          ? 'Satu klip lebih pendek dari jatahnya. Tambah satu adegan, atau ganti.'
          : '$n klip lebih pendek dari jatahnya. Tambah adegan, atau ganti.',
      n == 1
          ? 'Ein Clip ist kürzer als sein Abschnitt. Füg eine Szene hinzu oder tausch ihn.'
          : '$n Clips sind kürzer als ihr Abschnitt. Füg Szenen hinzu oder tausch sie.');

  String get addScenes => _t('Add scenes', 'أضف مشاهد', 'مناظر شامل کریں',
      'Tambah adegan', 'Szenen hinzufügen');

  /// Under the ribbon while it is being resized.
  String get tapForMoreRoom => _t(
      'Tap a scene to give it more room',
      'انقر مشهدًا لتوسيع مساحته',
      'کسی منظر کو ٹیپ کریں تاکہ اسے زیادہ جگہ ملے',
      'Ketuk satu adegan untuk memberinya ruang lebih',
      'Tippe eine Szene an, um ihr mehr Raum zu geben');

  /// Said when a tap on the ribbon left the reel exactly as it was:
  /// per-verse cuts on ayah boundaries, so a scene per verse has
  /// nothing left to give and 2x changes nothing.
  String get extendNeedsEven => _t(
      'Choose Even to make a scene longer.',
      'اختر «متساوٍ» لإطالة مشهد.',
      'کسی منظر کو لمبا کرنے کے لیے «برابر» چنیں۔',
      'Pilih "Merata" untuk memperpanjang satu adegan.',
      'Wähl „Gleichmäßig“, um eine Szene länger zu machen.');

  /// Said when changing the frame threw the chosen scenery out: the
  /// two frames take different footage, so the selection could not
  /// come along. Names the next step rather than the loss.
  String get pickForNewFrame => _t(
      'Pick a scenery for the new frame',
      'اختر مشهدًا للإطار الجديد',
      'نئے فریم کے لیے منظر چنیں',
      'Pilih pemandangan untuk bingkai baru',
      'Wähl eine Kulisse für den neuen Rahmen');

  /// Picker tab label. Tabs come from the scene catalog, so an unknown
  /// one falls back to its own id rather than showing nothing.
  String sceneTab(String tab) => _sceneTabs[lang]![tab] ?? tab;

  static const _sceneTabs = <AppLang, Map<String, String>>{
    AppLang.en: {
      'sky': 'Sky',
      'mountains': 'Mountains',
      'desert': 'Desert',
      'water': 'Water',
      'forest': 'Forest',
      'road': 'Road',
      'sacred': 'Sacred',
      'abstract': 'Abstract',
      'aerial': 'Aerial',
      'cinematic': 'Cinematic',
    },
    AppLang.ar: {
      'sky': 'السماء',
      'mountains': 'الجبال',
      'desert': 'الصحراء',
      'water': 'الماء',
      'forest': 'الغابة',
      'road': 'الطريق',
      'sacred': 'مشاهد إسلامية',
      'abstract': 'تجريدي',
      'aerial': 'تصوير جوي',
      'cinematic': 'سينمائي',
    },
    AppLang.ur: {
      'sky': 'آسمان',
      'mountains': 'پہاڑ',
      'desert': 'صحرا',
      'water': 'پانی',
      'forest': 'جنگل',
      'road': 'راستہ',
      'sacred': 'مقدس مقامات',
      'abstract': 'تجریدی',
      'aerial': 'فضائی',
      'cinematic': 'سینمائی',
    },
    AppLang.id: {
      'sky': 'Langit',
      'mountains': 'Gunung',
      'desert': 'Gurun',
      'water': 'Air',
      'forest': 'Hutan',
      'road': 'Jalan',
      'sacred': 'Tempat suci',
      'abstract': 'Abstrak',
      'aerial': 'Udara',
      'cinematic': 'Sinematik',
    },
    AppLang.de: {
      'sky': 'Himmel',
      'mountains': 'Berge',
      'desert': 'Wüste',
      'water': 'Wasser',
      'forest': 'Wald',
      'road': 'Straße',
      'sacred': 'Heilige Orte',
      'abstract': 'Abstrakt',
      'aerial': 'Luftaufnahme',
      'cinematic': 'Filmisch',
    },
  };

  /// The two shapes the scenery library is authored at. Labels the
  /// toggle above the tab rail, which follows the chosen frame.
  String get sceneShapeVertical =>
      _t('Vertical', 'رأسي', 'عمودی', 'Vertikal', 'Hochformat');
  String get sceneShapeWide =>
      _t('Wide', 'عريض', 'چوڑا', 'Lebar', 'Breit');

  /// Shown in place of the scenery grid when the catalog came back
  /// with nothing — a broken or missing `assets/catalog.json`. It is a
  /// bundled asset, so this is a broken install rather than a bad
  /// connection, and there is nothing for the user to retry.
  String get sceneCatalogEmpty => _t(
      'The scenery library couldn’t be opened.',
      'تعذّر فتح مكتبة المشاهد.',
      'مناظر کی لائبریری نہیں کھل سکی۔',
      'Pustaka pemandangan tidak bisa dibuka.',
      'Die Kulissen-Bibliothek ließ sich nicht öffnen.');

  String get sceneDownloadFailed => _t(
      'Couldn’t download that scenery. Check your connection.',
      'تعذّر تنزيل المشهد. تحقّق من اتصالك.',
      'یہ منظر ڈاؤن لوڈ نہیں ہو سکا۔ اپنا کنکشن دیکھیں۔',
      'Pemandangan itu gagal diunduh. Periksa koneksi Anda.',
      'Diese Kulisse ließ sich nicht laden. Prüf deine Verbindung.');

  // ---- creation wizard: frame format -----------------------------
  String get frameFormat =>
      _t('Frame', 'الإطار', 'فریم', 'Bingkai', 'Rahmen');
  String get frameFull => _t('Full frame', 'ملء الإطار', 'پورا فریم',
      'Bingkai penuh', 'Vollbild');
  String get frameLetterbox => _t('Wide card', 'بطاقة عريضة', 'چوڑا کارڈ',
      'Kartu lebar', 'Breite Karte');
  String get frameLetterboxHint => _t(
      'A wide video keeps its shape, with the verse below it.',
      'يبقى الفيديو الأفقي بشكله، والآية تحته.',
      'چوڑی ویڈیو اپنی شکل میں رہتی ہے، اور آیت اس کے نیچے۔',
      'Video lebar tetap bentuknya, dengan ayat di bawahnya.',
      'Ein breites Video behält seine Form, mit dem Vers darunter.');
  String get roundedCorners => _t('Rounded corners', 'زوايا دائرية',
      'گول کونے', 'Sudut membulat', 'Abgerundete Ecken');
  String get topAndBottom => _t('Top & bottom', 'الأعلى والأسفل',
      'اوپر اور نیچے', 'Atas & bawah', 'Oben & unten');
  String get backdropBlur =>
      _t('Blur', 'ضبابي', 'دھندلاہٹ', 'Buram', 'Unschärfe');

  String get chooseAPhoto => _t('Choose a photo', 'اختر صورة',
      'تصویر منتخب کریں', 'Pilih foto', 'Foto wählen');
  String get chooseAVideo => _t('Choose a video', 'اختر فيديو',
      'ویڈیو منتخب کریں', 'Pilih video', 'Video wählen');
  String get yourPhoto =>
      _t('Your photo', 'صورتك', 'آپ کی تصویر', 'Foto Anda', 'Dein Foto');
  String get yourVideo => _t('Your video', 'الفيديو الخاص بك', 'آپ کی ویڈیو',
      'Video Anda', 'Dein Video');
  String get useYourOwn => _t('Use your own', 'استخدم صورك', 'اپنی استعمال کریں',
      'Pakai milik Anda', 'Eigene nutzen');
  String get photoOrVideoFromGallery => _t(
      'Photo or video\nfrom your gallery',
      'صورة أو فيديو\nمن معرضك',
      'آپ کی گیلری سے\nتصویر یا ویڈیو',
      'Foto atau video\ndari galeri Anda',
      'Foto oder Video\naus deiner Galerie');
  String get replace =>
      _t('Replace', 'استبدال', 'تبدیل کریں', 'Ganti', 'Ersetzen');
  String get previewMyReel => _t('Preview my video', 'معاينة الفيديو',
      'میری ویڈیو کا پیش منظر', 'Pratinjau video saya', 'Video-Vorschau');
  String get galleryPickFailed => _t(
      'Couldn’t open your gallery. Try again.',
      'تعذّر فتح المعرض. حاول مجددًا.',
      'آپ کی گیلری نہیں کھل سکی۔ دوبارہ کوشش کریں۔',
      'Galeri Anda tidak dapat dibuka. Coba lagi.',
      'Deine Galerie ließ sich nicht öffnen. Versuch es erneut.');
  String get galleryBlockedTitle => _t(
      'AyahReel can’t reach your gallery',
      'لا يستطيع AyahReel الوصول إلى معرضك',
      'AyahReel آپ کی گیلری تک نہیں پہنچ سکتا',
      'AyahReel tidak bisa mengakses galeri Anda',
      'AyahReel kommt nicht an deine Galerie');
  String get galleryBlockedBody => _t(
      'Your phone is blocking photo and video access for AyahReel. '
          'Allow it in settings to use your own scenery.',
      'هاتفك يمنع AyahReel من الوصول إلى الصور والفيديو. '
          'اسمح بذلك من الإعدادات لاستخدام مشهدك الخاص.',
      'آپ کا فون AyahReel کو تصویر اور ویڈیو تک رسائی سے روک رہا ہے۔ '
          'اپنا منظر استعمال کرنے کے لیے ترتیبات میں اجازت دیں۔',
      'Ponsel Anda memblokir akses foto dan video untuk AyahReel. '
          'Izinkan di pengaturan untuk memakai pemandangan sendiri.',
      'Dein Handy blockiert für AyahReel den Zugriff auf Fotos und Videos. '
          'Erlaube ihn in den Einstellungen, um eigene Kulissen zu nutzen.');

  // ---- creation wizard: style ------------------------------------
  String get styleMyReel => _t('Style my video', 'نسّق الفيديو',
      'میری ویڈیو سنواریں', 'Tata gaya video saya', 'Video gestalten');
  String get styleTitle => _t('Make it yours', 'اجعله على ذوقك',
      'اسے اپنا بنائیں', 'Jadikan milikmu', 'Mach es zu deinem');
  String get styleBody => _t(
      'The type, the colour, the effects and the motion.',
      'الخط واللون والتأثيرات والحركة.',
      'خط، رنگ، ایفیکٹس اور حرکت۔',
      'Huruf, warna, efek, dan gerak.',
      'Schrift, Farbe, Effekte und Bewegung.');
  String get styleTabType =>
      _t('Type', 'الخط', 'خط', 'Huruf', 'Schrift');
  String get styleTabColour =>
      _t('Colour', 'اللون', 'رنگ', 'Warna', 'Farbe');
  String get styleTabEffects =>
      _t('Effects', 'التأثيرات', 'ایفیکٹس', 'Efek', 'Effekte');
  String get styleReset => _t('Reset', 'إعادة الضبط', 'ری سیٹ',
      'Atur ulang', 'Zurücksetzen');

  /// Headings over the two face rows. The verse is always Arabic; the
  /// translation's row is headed by the edition's own name instead, so
  /// somebody setting an Urdu line sees اردو and not "Translation".
  String get styleVerseFace =>
      _t('The verse', 'الآية', 'آیت', 'Ayat', 'Der Vers');
  String get styleTranslationFace => _t('The translation', 'الترجمة',
      'ترجمہ', 'Terjemahan', 'Die Übersetzung');
  String get styleVerseColour =>
      _t('Verse', 'الآية', 'آیت', 'Ayat', 'Vers');
  /// The wide card's second colour: what fills the band above and below
  /// it, set on the style step alone.
  String get styleBackdropColour =>
      _t('Background', 'الخلفية', 'پس منظر', 'Latar', 'Hintergrund');
  String get styleAccentColour => _t('Accent', 'اللون المميّز',
      'نمایاں رنگ', 'Aksen', 'Akzent');

  /// A luminous ground for the wide card's band, by name.
  String bandGlowName(BandGlow g) => switch (g) {
        BandGlow.midnight => _t('Midnight', 'منتصف الليل', 'آدھی رات',
            'Tengah malam', 'Mitternacht'),
        BandGlow.emerald =>
          _t('Emerald', 'زمرّد', 'زمرد', 'Zamrud', 'Smaragd'),
        BandGlow.amethyst =>
          _t('Amethyst', 'جمشت', 'جمشت', 'Kecubung', 'Amethyst'),
        BandGlow.aurora => _t('Aurora', 'الشفق القطبي', 'شفقِ قطبی',
            'Aurora', 'Polarlicht'),
        BandGlow.ember => _t('Ember', 'جمر', 'انگارہ', 'Bara', 'Glut'),
        BandGlow.gold => _t('Gold leaf', 'ورق الذهب', 'سونے کا ورق',
            'Daun emas', 'Blattgold'),
        BandGlow.dusk =>
          _t('Dusk', 'الغسق', 'شام', 'Senja', 'Abenddämmerung'),
        BandGlow.ocean => _t('Deep sea', 'أعماق البحر', 'گہرا سمندر',
            'Laut dalam', 'Tiefsee'),
        BandGlow.rose => _t('Rose', 'وردي', 'گلابی', 'Mawar', 'Rosé'),
        BandGlow.obsidian => _t('Obsidian', 'سَبَج', 'سنگِ سیاہ',
            'Obsidian', 'Obsidian'),
        BandGlow.pearl =>
          _t('Pearl', 'لؤلؤ', 'موتی', 'Mutiara', 'Perlmutt'),
        BandGlow.dawn =>
          _t('Dawn', 'الفجر', 'صبح', 'Fajar', 'Morgenröte'),
      };

  /// Where the effects panel's one slider waits, until an effect that
  /// has an amount is on.
  String get styleEffectAmountHint => _t(
      'Turn an effect on to set how much',
      'فعّل تأثيرًا لتضبط مقداره',
      'مقدار طے کرنے کے لیے کوئی ایفیکٹ آن کریں',
      'Nyalakan efek untuk mengatur kadarnya',
      'Schalte einen Effekt ein, um seine Stärke zu wählen');

  /// Headings over the colour panel's two rails: the inks that glow,
  /// and the flat colours.
  String get styleLuminous =>
      _t('Luminous', 'ألوان متوهجة', 'چمکدار رنگ', 'Bercahaya', 'Leuchtend');
  /// The flat colours' line in the verse's colours, beside [styleLuminous].
  String get styleSolid =>
      _t('Solid', 'ألوان ثابتة', 'سادہ رنگ', 'Polos', 'Uni');
  String get styleLook => _t('Look', 'المظهر', 'لُک', 'Tampilan', 'Look');
  String get effectWarmth =>
      _t('Warmth', 'الدفء', 'گرماہٹ', 'Kehangatan', 'Wärme');
  String get effectVibrance => _t('Vibrance', 'حيوية الألوان',
      'رنگوں کی شدت', 'Vibransi', 'Farbtiefe');
  String get effectVignette => _t('Vignette', 'تعتيم الأطراف',
      'کناروں کا سایہ', 'Vignette', 'Vignette');
  String get effectGrain =>
      _t('Grain', 'حُبيبات', 'دانہ داری', 'Butiran', 'Korn');
  String get effectFade => _t('Fade in and out', 'ظهور واختفاء تدريجي',
      'آہستہ ابھرنا اور معدوم ہونا', 'Muncul dan memudar',
      'Ein- und ausblenden');

  /// The same, where a switch has half a row for its name; the reader
  /// still hears [effectFade].
  String get effectFadeShort =>
      _t('Fade', 'تلاشٍ', 'فیڈ', 'Memudar', 'Blende');

  /// The designed grades, by name. Each is a whole look in one tap;
  /// the rows under them nudge it.
  String lookName(String look) => switch (look) {
        'golden' => _t('Golden hour', 'ساعة ذهبية', 'سنہری گھڑی',
            'Jam emas', 'Goldene Stunde'),
        'dusk' => _t('Dusk', 'الغسق', 'شام', 'Senja', 'Dämmerung'),
        'moonlight' => _t('Moonlight', 'ضوء القمر', 'چاندنی',
            'Cahaya bulan', 'Mondlicht'),
        'emerald' =>
          _t('Emerald', 'زمرّدي', 'زمرد', 'Zamrud', 'Smaragd'),
        'sand' => _t('Sand', 'رملي', 'ریت', 'Pasir', 'Sand'),
        'rose' => _t('Rose', 'وردي', 'گلابی', 'Mawar', 'Rosé'),
        'noir' => _t('Noir', 'أبيض وأسود', 'سیاہ و سفید', 'Hitam putih',
            'Schwarzweiß'),
        _ => _t('None', 'بدون', 'کوئی نہیں', 'Tanpa', 'Ohne'),
      };

  String get a11yStyleStage => _t(
      'Still frame of your reel',
      'لقطة ثابتة من مقطعك',
      'آپ کی ریل کا ساکن فریم',
      'Bingkai diam dari reel Anda',
      'Standbild deines Reels');
  String get a11ySetsFace => _t(
      'Sets the text in this face',
      'يضبط النص بهذا الخط',
      'متن کو اس خط میں ترتیب دیتا ہے',
      'Menata teks dengan huruf ini',
      'Setzt den Text in dieser Schrift');
  String get a11yAppliesLook => _t(
      'Grades the picture this way',
      'يمنح الصورة هذه المعالجة',
      'تصویر کو اس انداز میں ڈھالتا ہے',
      'Menerapkan gradasi ini pada gambar',
      'Legt diese Farbstimmung über das Bild');

  // ---- creation wizard: preview ----------------------------------
  String get presetClassic =>
      _t('Classic', 'كلاسيكي', 'کلاسیکی', 'Klasik', 'Klassisch');
  String get presetGlow => _t('Glow', 'توهّج', 'چمک', 'Cahaya', 'Leuchten');
  String get presetMinimal =>
      _t('Minimal', 'بسيط', 'سادہ', 'Minimal', 'Minimal');
  String get highlightRecitedWord => _t(
      'Highlight recited word',
      'إبراز الكلمة المتلوّة',
      'تلاوت شدہ لفظ نمایاں کریں',
      'Sorot kata yang dibaca',
      'Rezitiertes Wort hervorheben');
  /// Under that switch: the reel's verses no word timing reaches, which
  /// play without the per-word shading (the owner's ask, 2026-10-26).
  String noWordTimingFor(List<int> verses) {
    final shown = verses.length > 8
        ? '${verses.take(8).join('$comma ')}$comma …'
        : verses.join('$comma ');
    final one = verses.length == 1;
    return one
        ? _t('No word timing for verse $shown: it plays without per-word shading.',
            'لا توقيت للكلمات في الآية $shown: تُعرض دون تظليل كلمة بكلمة.',
            'آیت $shown کے الفاظ کی ٹائمنگ نہیں: یہ لفظ بہ لفظ روشنی کے بغیر چلے گی۔',
            'Ayat $shown tanpa waktu per kata: tampil tanpa sorotan per kata.',
            'Keine Wort-Zeiten für Vers $shown: er läuft ohne Hervorhebung Wort für Wort.')
        : _t('No word timing for verses $shown: they play without per-word shading.',
            'لا توقيت للكلمات في الآيات $shown: تُعرض دون تظليل كلمة بكلمة.',
            'آیات $shown کے الفاظ کی ٹائمنگ نہیں: یہ لفظ بہ لفظ روشنی کے بغیر چلیں گی۔',
            'Ayat $shown tanpa waktu per kata: tampil tanpa sorotan per kata.',
            'Keine Wort-Zeiten für die Verse $shown: sie laufen ohne Hervorhebung Wort für Wort.');
  }
  /// The same, where a line has room for two words.
  String get wordLightShort => _t('Highlight word', 'إبراز الكلمة',
      'لفظ نمایاں', 'Sorot kata', 'Wort hervorheben');
  String get dragToMoveVerse => _t('Drag to move the verse',
      'اسحب لتحريك الآية', 'آیت کھسکانے کے لیے کھینچیں',
      'Seret untuk memindahkan ayat', 'Zum Verschieben des Verses ziehen');
  String get share => _t('Share', 'مشاركة', 'شیئر کریں', 'Bagikan', 'Teilen');
  String get sendToWhatsApp => _t('To WhatsApp', 'إلى واتساب',
      'واٹس ایپ پر', 'Ke WhatsApp', 'Zu WhatsApp');
  String get sendToInstagram => _t('To Instagram', 'إلى إنستغرام',
      'انسٹاگرام پر', 'Ke Instagram', 'Zu Instagram');

  /// The two answers in the small panel "To Instagram" opens: the reel
  /// as a story, or as a reel. One word each, Instagram's own.
  String get igStory => _t('Story', 'القصة', 'اسٹوری', 'Story', 'Story');
  String get igReel => _t('Reel', 'ريلز', 'ریل', 'Reel', 'Reel');
  String get a11yIgStory => _t(
      'To your Instagram story',
      'إلى قصتك على إنستغرام',
      'آپ کی انسٹاگرام اسٹوری پر',
      'Ke Story Instagram Anda',
      'In deine Instagram-Story');
  String get a11yIgReel => _t(
      'As an Instagram reel',
      'كريلز على إنستغرام',
      'انسٹاگرام ریل کے طور پر',
      'Sebagai Reel Instagram',
      'Als Instagram-Reel');

  /// Sits beside "Share AyahReel" in the invite sheet at half the
  /// width, so it is the destination alone: no "To", which the reel
  /// button under the preview has room for and this one does not.
  String get sendToInstagramStory => _t('Instagram story', 'ستوري إنستغرام',
      'انسٹاگرام سٹوری', 'Story Instagram', 'Instagram-Story');
  String get saveToDevice => _t('Save to device', 'حفظ على الجهاز',
      'ڈیوائس میں محفوظ کریں', 'Simpan ke perangkat', 'Auf Gerät speichern');
  String get renderingShimmer => _t(
      'Every share is sadaqah jariyah, you are '
          'among the ones earning daily deeds',
      'كل مشاركة صدقة جارية، وأنت ممن يكسبون الحسنات كل يوم',
      'ہر شیئر صدقہ جاریہ ہے، آپ ان میں سے ہیں جو روز نیکیاں کما رہے ہیں',
      'Setiap berbagi adalah sedekah jariah, Anda termasuk yang '
          'menuai pahala setiap hari',
      'Jedes Teilen ist Sadaqa Dschāriya — du gehörst zu denen, die '
          'täglich Lohn sammeln');
  String get preparingRecitation => _t('Preparing recitation…',
      'جارٍ تجهيز التلاوة…', 'تلاوت تیار ہو رہی ہے…',
      'Menyiapkan bacaan…', 'Rezitation wird vorbereitet …');
  String preparingRecitationPct(int pct) => _t(
      'Preparing recitation · $pct%',
      'جارٍ تجهيز التلاوة · $pct%',
      'تلاوت تیار ہو رہی ہے · $pct%',
      'Menyiapkan bacaan · $pct%',
      'Rezitation wird vorbereitet · $pct %');
  String get firstTimeOnly => _t(
      'First time for this surah only',
      'مرة واحدة فقط لكل سورة',
      'صرف اس سورت کے لیے پہلی بار',
      'Hanya sekali untuk surah ini',
      'Nur beim ersten Mal für diese Sure');

  /// Why a recitation couldn't be prepared, told as it is: the
  /// connection only when it was the connection. See [Trouble]; the
  /// missing-surah case has its own sentence, [surahNotRecorded].
  String get recitationOffline => _t(
      'Couldn’t download this recitation.\nThe phone seems to be offline, '
          'or the connection dropped. Check it and try again.',
      'تعذّر تنزيل هذه التلاوة.\nيبدو أن الهاتف غير متصل، أو أن الاتصال '
          'انقطع. تحقق منه وحاول مجددًا.',
      'یہ تلاوت ڈاؤن لوڈ نہیں ہو سکی۔\nلگتا ہے فون آف لائن ہے یا کنکشن ٹوٹ '
          'گیا۔ اسے دیکھیں اور دوبارہ کوشش کریں۔',
      'Bacaan ini tidak dapat diunduh.\nPonsel tampaknya sedang offline, '
          'atau koneksinya terputus. Periksa lalu coba lagi.',
      'Diese Rezitation ließ sich nicht herunterladen.\nDas Handy scheint '
          'offline zu sein, oder die Verbindung ist abgebrochen. Prüf sie '
          'und versuch es erneut.');
  String get recitationHost => _t(
      'The server for this recitation didn’t send it properly.\nTry again '
          'in a little while, or choose another voice.',
      'لم يُرسل خادم هذه التلاوة الملف كما ينبغي.\nحاول بعد قليل، أو اختر '
          'قارئًا آخر.',
      'اس تلاوت کے سرور نے اسے ٹھیک سے نہیں بھیجا۔\nتھوڑی دیر بعد دوبارہ '
          'کوشش کریں، یا کوئی اور قاری منتخب کریں۔',
      'Server bacaan ini tidak mengirimkannya dengan benar.\nCoba lagi '
          'sebentar lagi, atau pilih qari lain.',
      'Der Server dieser Rezitation hat sie nicht richtig geliefert.\n'
          'Versuch es gleich noch einmal oder wähle eine andere Stimme.');
  String get recitationStorage => _t(
      'There isn’t enough space on this phone for the recitation.\nFree '
          'some up and try again.',
      'لا توجد مساحة كافية على الهاتف لهذه التلاوة.\nأفرغ بعض المساحة '
          'وحاول مجددًا.',
      'اس تلاوت کے لیے فون میں کافی جگہ نہیں۔\nکچھ جگہ خالی کریں اور '
          'دوبارہ کوشش کریں۔',
      'Ruang penyimpanan ponsel tidak cukup untuk bacaan ini.\nKosongkan '
          'sebagian lalu coba lagi.',
      'Auf dem Handy ist nicht genug Platz für die Rezitation.\nMach etwas '
          'Platz frei und versuch es erneut.');
  String get recitationDevice => _t(
      'Something went wrong preparing this recitation on your phone.\n'
          'Try again.',
      'حدث خطأ أثناء تجهيز هذه التلاوة على هاتفك.\nحاول مجددًا.',
      'آپ کے فون پر یہ تلاوت تیار کرتے ہوئے کچھ غلط ہو گیا۔\nدوبارہ کوشش '
          'کریں۔',
      'Terjadi kesalahan saat menyiapkan bacaan ini di ponsel Anda.\n'
          'Coba lagi.',
      'Beim Vorbereiten dieser Rezitation auf deinem Handy ist etwas '
          'schiefgegangen.\nVersuch es erneut.');

  /// The sentence for a recitation that failed with [t].
  String recitationFailed(Trouble t) => switch (t) {
        Trouble.offline => recitationOffline,
        Trouble.host => recitationHost,
        Trouble.storage => recitationStorage,
        Trouble.device || Trouble.missing => recitationDevice,
      };

  /// The line under every error a user may want us to hear about: where
  /// the report goes, by the names the Settings screen itself uses.
  String get reportInSettings {
    final s = settingsTitle, f = feedbackRowTitle;
    return _t(
        'If it keeps happening, report it in $s → $f.',
        'إن تكرّر ذلك، أبلغنا عنه من $s ← $f.',
        'اگر یہ بار بار ہو تو $s ← $f سے ہمیں بتائیں۔',
        'Jika terus terjadi, laporkan lewat $s → $f.',
        'Wenn das öfter passiert, melde es unter $s → $f.');
  }

  /// Everything after the two downloads have already landed:
  /// planning the cuts, opening the scenery, starting playback. None
  /// of it touches the network, so none of it may tell the user to go
  /// and look at their connection — that sends people to their router
  /// over a failure on their own phone, and hides which half of the
  /// screen actually went wrong.
  String get previewError => _t(
      'Could not put this reel together.\nTry again.',
      'تعذّر تجهيز هذا المقطع للعرض.\nحاول مجددًا.',
      'یہ ریل جوڑی نہیں جا سکی۔\nدوبارہ کوشش کریں۔',
      'Reel ini tidak dapat disusun.\nCoba lagi.',
      'Dieses Reel ließ sich nicht zusammensetzen.\nVersuch es erneut.');
  String trimmedToAyah(int ayah) => _t(
      'Reels are capped at ${ReelLimits.maxReelMinutes} minutes, '
          'trimmed to ayah $ayah.',
      'الحد الأقصى للمقطع ${ReelLimits.maxReelMinutes} دقيقة، '
          'تم الاقتصاص حتى الآية $ayah.',
      'ریل کی حد ${ReelLimits.maxReelMinutes} منٹ ہے، اس لیے آیت $ayah تک کاٹ دی گئی۔',
      'Reel dibatasi ${ReelLimits.maxReelMinutes} menit, dipangkas sampai ayat $ayah.',
      'Reels sind auf ${ReelLimits.maxReelMinutes} Minuten begrenzt, '
          'gekürzt bis Vers $ayah.');
  String get longRenderNote => _t(
      'A long reel takes a few minutes to export — keep the app open.',
      'المقاطع الطويلة تستغرق بضع دقائق للتصدير — أبقِ التطبيق مفتوحًا.',
      'لمبی ریل برآمد ہونے میں چند منٹ لیتی ہے — ایپ کھلی رکھیں۔',
      'Reel panjang butuh beberapa menit untuk diekspor — biarkan aplikasi terbuka.',
      'Ein langes Reel braucht ein paar Minuten zum Export — lass die App offen.');
  /// Under the share buttons while a video is made: it is the reel as
  /// it stood when Share or Save was tapped, and leaving stops it.
  String get renderHoldStill => _t(
      'Please stay here and change nothing until your video is ready.',
      'رجاءً ابقَ هنا ولا تغيّر شيئًا حتى يجهز الفيديو.',
      'براہِ کرم یہیں رہیں اور ویڈیو تیار ہونے تک کچھ نہ بدلیں۔',
      'Tetap di sini dan jangan ubah apa pun sampai videomu siap.',
      'Bitte bleib hier und ändere nichts, bis dein Video fertig ist.');
  String exportFailed(Object e) => _t('Export failed: $e', 'فشل التصدير: $e',
      'برآمد ناکام: $e', 'Ekspor gagal: $e', 'Export fehlgeschlagen: $e');

  /// The two ways an export can end that are worth a sentence rather
  /// than FFmpeg's log tail. The memory one names the two things the
  /// user can actually change: word highlighting draws one card per
  /// word, which is what makes a reel expensive to hold.
  String get exportOutOfMemory => _t(
      'Couldn’t finish the reel — it needed more memory than the '
          'phone allowed. Try a shorter reel, or turn word '
          'highlighting off.',
      'لم يكتمل المقطع: احتاج ذاكرة أكثر مما سمح به الهاتف. '
          'جرّب مقطعًا أقصر، أو أوقف إبراز الكلمات.',
      'ریل مکمل نہیں ہو سکی — اسے فون کی اجازت سے زیادہ میموری چاہیے تھی۔ '
          'چھوٹی ریل آزمائیں، یا الفاظ نمایاں کرنا بند کر دیں۔',
      'Reel tidak selesai — butuh memori lebih dari yang diizinkan ponsel. '
          'Coba reel lebih pendek, atau matikan sorot kata.',
      'Das Reel wurde nicht fertig — es brauchte mehr Speicher, als das '
          'Handy zuließ. Versuch ein kürzeres Reel oder schalte die '
          'Wort-Hervorhebung aus.');
  /// The phone is full. Said for what it is, with the one place in the
  /// app that can give room back: "try again" on a full phone fails at
  /// the same step every time, which is how it reached us as "every
  /// video fails right at the end".
  String get phoneStorageFull {
    final s = settingsTitle, m = manageStorage;
    return _t(
        'Your phone is out of storage, so the reel couldn’t be saved. '
            'Free up some space — $s → $m clears what AyahReel keeps — '
            'then try again.',
        'مساحة التخزين في هاتفك ممتلئة، فتعذّر حفظ المقطع. '
            'أفرغ بعض المساحة — من $s ← $m تمسح ما يحتفظ به AyahReel — '
            'ثم حاول مجددًا.',
        'آپ کے فون کی سٹوریج بھر گئی ہے، اس لیے ریل محفوظ نہیں ہو سکی۔ '
            'کچھ جگہ خالی کریں — $s ← $m سے AyahReel کی رکھی چیزیں صاف ہوتی ہیں — '
            'پھر دوبارہ کوشش کریں۔',
        'Penyimpanan ponsel Anda penuh, jadi reel tidak bisa disimpan. '
            'Kosongkan sedikit ruang — $s → $m membersihkan simpanan '
            'AyahReel — lalu coba lagi.',
        'Der Speicher deines Handys ist voll, deshalb konnte das Reel '
            'nicht gespeichert werden. Mach etwas Platz frei — unter '
            '$s → $m räumst du auf, was AyahReel ablegt — und versuch '
            'es dann erneut.');
  }

  String get exportUnfinished => _t(
      'Couldn’t finish the reel. Please try again.',
      'لم يكتمل المقطع. حاول مجددًا.',
      'ریل مکمل نہیں ہو سکی۔ براہِ کرم دوبارہ کوشش کریں۔',
      'Reel tidak selesai. Silakan coba lagi.',
      'Das Reel wurde nicht fertig. Bitte versuch es erneut.');
  String shareFailed(Object e) => _t('Could not share: $e',
      'تعذّرت المشاركة: $e', 'شیئر نہیں ہو سکا: $e', 'Gagal membagikan: $e',
      'Teilen nicht möglich: $e');
  String get whatsappUnavailable => _t(
      'WhatsApp not available. Opening the share sheet.',
      'واتساب غير متاح. سيتم فتح نافذة المشاركة.',
      'واٹس ایپ دستیاب نہیں۔ شیئر شیٹ کھولی جا رہی ہے۔',
      'WhatsApp tidak tersedia. Membuka lembar berbagi.',
      'WhatsApp ist nicht verfügbar. Das Teilen-Menü wird geöffnet.');
  String get instagramUnavailable => _t(
      'Instagram not available. Opening the share sheet.',
      'إنستغرام غير متاح. سيتم فتح نافذة المشاركة.',
      'انسٹاگرام دستیاب نہیں۔ شیئر شیٹ کھولی جا رہی ہے۔',
      'Instagram tidak tersedia. Membuka lembar berbagi.',
      'Instagram ist nicht verfügbar. Das Teilen-Menü wird geöffnet.');
  String get alreadyInGallery => _t(
      'This reel is already in your gallery.',
      'هذا الريل محفوظ في المعرض بالفعل.',
      'یہ ریل پہلے ہی آپ کی گیلری میں ہے۔',
      'Reel ini sudah ada di galeri Anda.',
      'Dieses Reel ist schon in deiner Galerie.');
  String get saveAgain => _t('Save again', 'احفظ مجددًا', 'دوبارہ محفوظ کریں',
      'Simpan lagi', 'Erneut speichern');
  String get savedToDevice => _t(
      'Saved to your phone’s gallery.',
      'حُفظ في معرض هاتفك.',
      'آپ کے فون کی گیلری میں محفوظ ہو گیا۔',
      'Tersimpan di galeri ponsel Anda.',
      'In der Galerie deines Handys gespeichert.');
  String get galleryWriteBlockedTitle => _t(
      'AyahReel can’t save to your gallery',
      'تعذّر الحفظ في المعرض',
      'AyahReel آپ کی گیلری میں محفوظ نہیں کر سکتا',
      'AyahReel tidak bisa menyimpan ke galeri Anda',
      'AyahReel kann nicht in deiner Galerie speichern');
  String get galleryWriteBlocked => _t(
      'Your phone is blocking AyahReel from saving to your gallery. '
          'Allow photo and video access in settings.',
      'هاتفك يمنع AyahReel من الحفظ في المعرض. اسمح بالوصول إلى '
          'الصور والفيديو من الإعدادات.',
      'آپ کا فون AyahReel کو گیلری میں محفوظ کرنے سے روک رہا ہے۔ '
          'ترتیبات میں تصویر اور ویڈیو کی اجازت دیں۔',
      'Ponsel Anda menghalangi AyahReel menyimpan ke galeri. '
          'Izinkan akses foto dan video di pengaturan.',
      'Dein Handy hindert AyahReel daran, in deiner Galerie zu speichern. '
          'Erlaube den Zugriff auf Fotos und Videos in den Einstellungen.');
  String saveFailed(Object e) => _t(
      'Could not save to your gallery: $e',
      'تعذّر الحفظ في المعرض: $e',
      'گیلری میں محفوظ نہیں ہو سکا: $e',
      'Gagal menyimpan ke galeri Anda: $e',
      'Speichern in deiner Galerie fehlgeschlagen: $e');
  String savedToGallery(int points) => _t(
      'Saved to Gallery and $navWorks · +$points ✦',
      'حُفظ في المعرض وفي $navWorks · ‎+$points ✦',
      'گیلری اور $navWorks میں محفوظ · ‎+$points ✦',
      'Tersimpan di Galeri dan $navWorks · +$points ✦',
      'In Galerie und $navWorks gespeichert · +$points ✦');

  /// The reel reached the gallery but the app's own copy of it did
  /// not. [savedToGallery] claims both, and claiming a copy that isn't
  /// there is what sends someone looking through My works for a reel
  /// the app never kept.
  String get savedToGalleryOnly => _t(
      'Saved to your gallery — but it couldn’t be added to $navWorks.',
      'حُفظ في المعرض، لكن تعذّر إضافته إلى $navWorks.',
      'گیلری میں محفوظ ہو گیا — مگر $navWorks میں شامل نہ ہو سکا۔',
      'Tersimpan di galeri Anda — tetapi gagal ditambahkan ke $navWorks.',
      'In deiner Galerie gespeichert — konnte aber nicht zu $navWorks hinzugefügt werden.');
  String surahCaption(String surahName, String reciterName) => _t(
      'Surah $surahName · $reciterName',
      'سورة ${localizedSurahName(surahName)} · '
          '${localizedReciterName(reciterName)}',
      'سورۃ $surahName · $reciterName',
      'Surah $surahName · $reciterName',
      'Sure $surahName · $reciterName');

  // ---- hashtags ----------------------------------------------------
  String get hashtags =>
      _t('Hashtags', 'وسوم', 'ہیش ٹیگز', 'Tagar', 'Hashtags');
  String get hashtagsSubtitle => _t(
      'One tap copies a set. Paste it under your post.',
      'انسخ المجموعة بنقرة، ثم الصقها تحت منشورك.',
      'ایک ٹیپ سے پورا سیٹ کاپی۔ اپنی پوسٹ کے نیچے چسپاں کریں۔',
      'Sekali ketuk menyalin satu set. Tempel di bawah unggahan Anda.',
      'Ein Tippen kopiert einen Satz. Füg ihn unter deinem Beitrag ein.');
  String get copy => _t('Copy', 'نسخ', 'کاپی', 'Salin', 'Kopieren');
  String get copied =>
      _t('Copied', 'تم النسخ', 'کاپی ہو گیا', 'Tersalin', 'Kopiert');

  /// Arabic counts the way Arabic does: three to ten take the plural,
  /// eleven and up go back to the singular. No block here is shorter
  /// than three, so those are the only two cases.
  String tagCount(int n) => switch (lang) {
        AppLang.en => '$n tags',
        AppLang.ar => n <= 10 ? '$n وسوم' : '$n وسمًا',
        AppLang.ur => '$n ہیش ٹیگز',
        AppLang.id => '$n tagar',
        AppLang.de => '$n Hashtags',
      };

  /// Brand names stay as they are written — Instagram is Instagram in
  /// every language, and a transliterated one reads as a knock-off.
  String get platformInstagram => 'Instagram';
  String get platformTikTok => 'TikTok';
  String get platformYouTube => 'YouTube';
  String get moreLanguages => _t('More languages', 'لغات أخرى',
      'مزید زبانیں', 'Bahasa lain', 'Weitere Sprachen');
  String get platformMore =>
      _t('More', 'المزيد', 'مزید', 'Lainnya', 'Mehr');

  /// What one block of tags is for, by its key in `hashtag_sets.dart`.
  /// [surahName] is only read by the block cut for one surah.
  String hashtagSetLabel(String key, {String surahName = ''}) => switch (key) {
        'recitation' => _t('Recitation', 'تلاوة', 'تلاوت', 'Bacaan',
            'Rezitation'),
        'arabic' =>
          _t('Arabic', 'بالعربية', 'عربی', 'Bahasa Arab', 'Arabisch'),
        'reminders' => _t('Reminders', 'تذكير', 'یاد دہانی', 'Pengingat',
            'Erinnerungen'),
        'night' =>
          _t('Night', 'قيام الليل', 'شب بیداری', 'Malam', 'Nacht'),
        'hifz' => _t('Memorization', 'حفظ', 'حفظ', 'Hafalan',
            'Auswendiglernen'),
        'ramadan' =>
          _t('Ramadan', 'رمضان', 'رمضان', 'Ramadan', 'Ramadan'),
        'dhikr' => _t('Dhikr', 'ذكر', 'ذکر', 'Zikir', 'Dhikr'),
        'dawah' => _t('Dawah', 'دعوة', 'دعوت', 'Dakwah', 'Dawa'),
        'surah' => _t(
            'Surah $surahName',
            'سورة ${localizedSurahName(surahName)}',
            'سورۃ $surahName',
            'Surah $surahName',
            'Sure $surahName'),
        _ => key,
      };

  // ---- my reels ---------------------------------------------------
  String get manageStorage => _t('Manage storage', 'إدارة التخزين',
      'سٹوریج سنبھالیں', 'Kelola penyimpanan', 'Speicher verwalten');
  String get noReelsYet => _t('No reels yet', 'لا مقاطع بعد',
      'ابھی کوئی ریل نہیں', 'Belum ada reel', 'Noch keine Reels');
  String get noReelsBody => _t(
      'Reels you share or save will appear here.',
      'ستظهر هنا المقاطع التي تشاركها أو تحفظها.',
      'جو ریلز آپ شیئر یا محفوظ کریں گے وہ یہاں نظر آئیں گی۔',
      'Reel yang Anda bagikan atau simpan akan muncul di sini.',
      'Reels, die du teilst oder speicherst, erscheinen hier.');
  String get createFirstReel => _t('Create your first video',
      'أنشئ أول فيديو لك', 'اپنی پہلی ویڈیو بنائیں', 'Buat video pertama Anda',
      'Erstell dein erstes Video');
  String get deleteReelTitle => _t('Delete this reel?', 'حذف هذا المقطع؟',
      'یہ ریل حذف کریں؟', 'Hapus reel ini?', 'Dieses Reel löschen?');
  String get deleteReelBody => _t(
      'It will be removed from the app. Copies already saved to '
          'your gallery or shared elsewhere are not affected.',
      'سيُحذف من التطبيق. النسخ المحفوظة في معرضك أو التي '
          'شاركتها لن تتأثر.',
      'یہ ایپ سے ہٹ جائے گی۔ جو نقلیں آپ کی گیلری میں محفوظ ہیں یا '
          'کہیں شیئر ہو چکی ہیں، ان پر اثر نہیں پڑے گا۔',
      'Reel akan dihapus dari aplikasi. Salinan yang sudah tersimpan di '
          'galeri atau yang sudah dibagikan tidak terpengaruh.',
      'Es wird aus der App entfernt. Kopien, die schon in deiner Galerie '
          'liegen oder geteilt wurden, bleiben unberührt.');
  String get cancel =>
      _t('Cancel', 'إلغاء', 'منسوخ کریں', 'Batal', 'Abbrechen');
  String get delete => _t('Delete', 'حذف', 'حذف کریں', 'Hapus', 'Löschen');

  // ---- settings ---------------------------------------------------
  String get settingsTitle => _t('Settings', 'الإعدادات', 'ترتیبات',
      'Pengaturan', 'Einstellungen');
  String get sectionLanguage =>
      _t('LANGUAGE', 'اللغة', 'زبان', 'BAHASA', 'SPRACHE');

  /// The row that opens the app-language picker. Its subtitle is the
  /// language currently chosen, in that language's own name, so the
  /// row reads correctly even to somebody who cannot read the label.
  String get appLanguageTitle => _t('App language', 'لغة التطبيق',
      'ایپ کی زبان', 'Bahasa aplikasi', 'App-Sprache');
  String get appLanguageSubtitle => _t(
      'The buttons and headings. The Quran stays in Arabic.',
      'الأزرار والعناوين. أما القرآن فيبقى بالعربية.',
      'بٹن اور سرخیاں۔ قرآن عربی ہی میں رہے گا۔',
      'Tombol dan judul. Al-Qur’an tetap dalam bahasa Arab.',
      'Schaltflächen und Überschriften. Der Quran bleibt Arabisch.');

  /// The row that opens the verse-translation picker.
  String get verseTranslationTitle => _t('Verse translation',
      'ترجمة الآيات', 'آیات کا ترجمہ', 'Terjemahan ayat', 'Versübersetzung');

  /// The verse-translation picker's first row, and what the Settings
  /// row shows while it is chosen: the Arabic alone on every card.
  String get translationNone => _t('None', 'بلا ترجمة', 'بغیر ترجمہ',
      'Tanpa terjemahan', 'Keine Übersetzung');
  String get translationNoneNote => _t(
      'The Arabic alone on each card',
      'الآية بالعربية وحدها على كل بطاقة',
      'ہر کارڈ پر صرف عربی آیت',
      'Hanya teks Arab di setiap kartu',
      'Nur der arabische Text auf jeder Karte');

  // ---- verse numbers on a reel --------------------------------------
  String get verseNumbersTitle => _t('Verse numbers', 'أرقام الآيات',
      'آیات کے نمبر', 'Nomor ayat', 'Versnummern');

  /// The choices in the Settings dropdown, one per [VerseNumbering].
  String verseNumberingLabel(VerseNumbering v) => switch (v) {
        VerseNumbering.off =>
          _t('Off', 'بدون', 'بند', 'Mati', 'Aus'),
        VerseNumbering.mark => _t('Verse-end mark', 'علامة نهاية الآية',
            'آیت کے اختتام کا نشان', 'Tanda akhir ayat', 'Versende-Zeichen'),
        // Named for what the line says — "Al-Baqarah 2:255" — rather
        // than for being a line: سطر المرجع read as a bibliography.
        VerseNumbering.reference => _t('Reference line', 'السورة والآية',
            'سورت اور آیت', 'Baris rujukan', 'Stellenangabe'),
        VerseNumbering.both => _t('Mark and reference',
            'العلامة مع السورة والآية', 'نشان، سورت اور آیت',
            'Tanda dan rujukan', 'Zeichen und Stellenangabe'),
      };

  /// Under the heading of those choices: where they end up, since the
  /// menu sits in Settings, a long way from any reel.
  /// The sample under the verse-number chips, read aloud.
  String a11yNumberingSample(String choice) => _t(
      'How the end of a verse looks with: $choice',
      'شكل نهاية الآية مع: $choice',
      'آیت کا اختتام اس کے ساتھ: $choice',
      'Akhir ayat dengan: $choice',
      'So endet ein Vers mit: $choice');

  /// Under the sample when the choice is Off: the verse ends with its
  /// last word and nothing after it.
  String get numberingNothingAdded => _t(
      'Nothing added',
      'بلا إضافة',
      'کچھ شامل نہیں',
      'Tanpa tambahan',
      'Nichts dazu');

  String get verseNumbersNote => _t(
      'Shown on your reels',
      'تظهر على مقاطعك',
      'آپ کی ریلز پر نظر آتا ہے',
      'Tampil di reel Anda',
      'Erscheint auf deinen Reels');

  // ---- the Customize row, and the menu it drops ---------------------
  /// Names none of the settings in its menu, so none reads as the
  /// point of it.
  String get customizeTitle =>
      _t('Customize', 'تخصيص', 'حسب ضرورت بنائیں', 'Sesuaikan', 'Anpassen');

  /// The row's title says nothing of what it holds, so a screen reader
  /// is told.
  String get a11yCustomizeHint => _t(
      'Opens long verses, scenes, verse motion, the word highlight, the '
          'surah name, verse numbers and video quality',
      'يفتح الآيات الطويلة والمشاهد وحركة الآية وإبراز الكلمات واسم السورة '
          'وأرقام الآيات وجودة الفيديو',
      'لمبی آیات، مناظر، آیت کی حرکت، الفاظ کی نمایاں کاری، سورت کا نام، '
          'آیات کے نمبر اور ویڈیو کا معیار کھولتا ہے',
      'Membuka ayat panjang, adegan, gerak ayat, sorot kata, nama surah, '
          'nomor ayat, dan kualitas video',
      'Öffnet lange Verse, Szenen, Versbewegung, Worthervorhebung, '
          'Surenname, Versnummern und Videoqualität');

  String get highQualityVideo => _t(
      'High-quality video',
      'فيديو عالي الجودة',
      'اعلیٰ معیار کی ویڈیو',
      'Video kualitas tinggi',
      'Video in hoher Qualität');

  /// Under the switch: the cost, said as plainly as the gain.
  String get highQualityNote => _t(
      'Sharper, larger files',
      'أوضح، وحجم ملف أكبر',
      'زیادہ واضح، بڑی فائلیں',
      'Lebih tajam, file lebih besar',
      'Schärfer, größere Dateien');
  String get verseTranslationSubtitle => _t(
      'The line printed under each verse, in your reels and in the app.',
      'السطر الذي يُطبع تحت كل آية، في مقاطعك وفي التطبيق.',
      'وہ سطر جو ہر آیت کے نیچے چھپتی ہے — آپ کی ریلز میں اور ایپ میں۔',
      'Baris yang tercetak di bawah setiap ayat, di reel dan di aplikasi.',
      'Die Zeile unter jedem Vers — in deinen Reels und in der App.');

  /// The two picker sheets' titles.
  String get chooseAppLanguage => _t('Choose your language', 'اختر لغتك',
      'اپنی زبان چنیں', 'Pilih bahasa Anda', 'Wähl deine Sprache');
  String get chooseVerseTranslation => _t('Choose a translation',
      'اختر ترجمة', 'ترجمہ منتخب کریں', 'Pilih terjemahan',
      'Wähl eine Übersetzung');

  /// Under the translation picker. Says the one thing that matters
  /// about it: the Arabic is not what is being changed.
  String get translationPickerNote => _t(
      'The Arabic never changes. This only sets the translation beneath it.',
      'النص العربي لا يتغير. هذا يضبط الترجمة تحته فقط.',
      'عربی متن کبھی نہیں بدلتا۔ یہ صرف اس کے نیچے کا ترجمہ مقرر کرتا ہے۔',
      'Teks Arabnya tidak pernah berubah. Ini hanya mengatur terjemahan di bawahnya.',
      'Der arabische Text ändert sich nie. Dies setzt nur die Übersetzung darunter.');

  /// Shown on a translation row while its surah is being re-fetched
  /// after a switch — the text for the new edition is not on the
  /// device yet, and a card with last edition's line on it would be
  /// wrong rather than merely late.
  String get translationSwitching => _t('Fetching that translation…',
      'جارٍ جلب الترجمة…', 'وہ ترجمہ لایا جا رہا ہے…',
      'Mengambil terjemahan itu…', 'Übersetzung wird geholt …');

  String get sectionYou => _t('YOU', 'أنت', 'آپ', 'ANDA', 'DU');
  String get yourNameTitle =>
      _t('Your name', 'اسمك', 'آپ کا نام', 'Nama Anda', 'Dein Name');
  String get yourNameEmptySubtitle => _t(
      'Add your name and the app will greet you by it.',
      'أضف اسمك ليحييك التطبيق به.',
      'اپنا نام شامل کریں، ایپ اسی سے سلام کرے گی۔',
      'Tambahkan nama Anda dan aplikasi akan menyapa dengan nama itu.',
      'Gib deinen Namen an, dann begrüßt dich die App damit.');
  String yourNameSetSubtitle(String name) => _t(
      'The app greets you as $name',
      'يحييك التطبيق بـ $name',
      'ایپ آپ کو $name کہہ کر سلام کرتی ہے',
      'Aplikasi menyapa Anda sebagai $name',
      'Die App begrüßt dich als $name');
  String get yourNameDialogTitle => _t('What should we call you?',
      'ما اسمك؟', 'ہم آپ کو کیا کہیں؟', 'Kami panggil Anda apa?',
      'Wie sollen wir dich nennen?');
  String get yourNameDialogBody => _t(
      'It shows in the greeting on your home screen — '
          '"Good evening, ...".',
      'سيظهر في تحيّة الصفحة الرئيسية — «مساء الخير، ...».',
      'یہ ہوم سکرین کے سلام میں نظر آئے گا — «شام بخیر، ...»۔',
      'Nama ini tampil pada sapaan di layar beranda — '
          '"Selamat sore, ...".',
      'Er erscheint in der Begrüßung auf deinem Startbildschirm — '
          '„Guten Abend, …“.');
  String get yourNameHint =>
      _t('Your name', 'اسمك', 'آپ کا نام', 'Nama Anda', 'Dein Name');
  String get save => _t('Save', 'حفظ', 'محفوظ کریں', 'Simpan', 'Speichern');
  String get back => _t('Back', 'رجوع', 'واپس', 'Kembali', 'Zurück');
  String get remove =>
      _t('Remove', 'إزالة', 'ہٹا دیں', 'Hapus', 'Entfernen');
  String get sectionNotifications => _t('NOTIFICATIONS', 'الإشعارات',
      'اطلاعات', 'NOTIFIKASI', 'MITTEILUNGEN');
  String get streakNudgeTitle => _t('Daily streak nudge',
      'تذكير المواظبة اليومي', 'روزانہ تسلسل کی یاد دہانی',
      'Pengingat rentetan harian', 'Täglicher Serien-Anstoß');
  String get streakNudgeSubtitle => _t(
      'One gentle invitation a day, two on Jumu‘ah: a Quran quiz, a reel, '
          'or something of yours to share.',
      'دعوة لطيفة كل يوم، واثنتان يوم الجمعة: مسابقة قرآنية أو مقطع أو شيء من صنعك تشاركه.',
      'روزانہ ایک نرم دعوت، جمعہ کو دو: قرآنی کوئز، ایک ریل، یا شیئر کرنے کو آپ کی اپنی کوئی چیز۔',
      'Satu ajakan lembut setiap hari, dua di hari Jumat: kuis Al-Qur’an, '
          'reel, atau karyamu untuk dibagikan.',
      'Eine sanfte Einladung am Tag, zwei am Freitag: ein Quran-Quiz, ein '
          'Reel oder etwas von dir zum Teilen.');
  String get myReminderTitle => _t('My reminder', 'تذكيري',
      'میری یاد دہانی', 'Pengingat saya', 'Meine Erinnerung');
  String myReminderOnSubtitle(String time) => _t(
      'Every day at $time, tap to change',
      'كل يوم في $time، انقر للتغيير',
      'روزانہ $time بجے، بدلنے کے لیے ٹیپ کریں',
      'Setiap hari pukul $time, ketuk untuk mengubah',
      'Täglich um $time, zum Ändern tippen');
  String get myReminderOffSubtitle => _t(
      'Your own reminder, at a time you choose.',
      'تذكيرك الخاص، في الوقت الذي تختاره.',
      'آپ کی اپنی یاد دہانی، آپ کے چنے ہوئے وقت پر۔',
      'Pengingat Anda sendiri, pada waktu yang Anda pilih.',
      'Deine eigene Erinnerung, zu einer Zeit deiner Wahl.');
  String get remindersDeliveryNote => _t(
      'Reminders are delivered by your device and can arrive '
          'a few minutes after the set time.',
      'تُسلَّم التذكيرات عبر جهازك وقد تصل بعد دقائق من الوقت المحدد.',
      'یاد دہانیاں آپ کا آلہ بھیجتا ہے اور مقررہ وقت کے چند منٹ بعد بھی آ سکتی ہیں۔',
      'Pengingat dikirim oleh perangkat Anda dan bisa datang '
          'beberapa menit setelah waktu yang ditetapkan.',
      'Erinnerungen werden von deinem Gerät zugestellt und können '
          'ein paar Minuten nach der eingestellten Zeit ankommen.');
  String get sectionSharing =>
      _t('SHARING', 'المشاركة', 'شیئرنگ', 'BERBAGI', 'TEILEN');
  String get sectionStorage =>
      _t('STORAGE', 'التخزين', 'سٹوریج', 'PENYIMPANAN', 'SPEICHER');
  String get manageStorageSubtitle => _t(
      'See what takes space, clear caches safely.',
      'اطّلع على ما يشغل المساحة وامسح الملفات المؤقتة بأمان.',
      'دیکھیں کیا جگہ لے رہا ہے، اور کیشے محفوظ طریقے سے صاف کریں۔',
      'Lihat apa yang memakan ruang, bersihkan singgahan dengan aman.',
      'Sieh, was Platz braucht, und leer die Zwischenspeicher gefahrlos.');

  // ---- rating ------------------------------------------------------
  // The row and the sheet behind it. Deliberately worded as a favour
  // asked once, in a place the user walked to — nothing here ever
  // opens by itself, which is what keeps it clear of the App Store's
  // ban on custom review prompts.
  String get sectionRate =>
      _t('RATE', 'التقييم', 'درجہ بندی', 'BERI NILAI', 'BEWERTEN');
  String get rateAppTitle => _t('Rate AyahReel', 'قيّم AyahReel',
      'AyahReel کو ریٹ کریں', 'Beri nilai AyahReel', 'AyahReel bewerten');
  String get rateAppSubtitle => _t(
      'Five stars is how the next person finds this.',
      'خمس نجوم تعرّف غيرك على التطبيق.',
      'پانچ ستارے ہی اگلے شخص تک اسے پہنچاتے ہیں۔',
      'Lima bintang adalah cara orang berikutnya menemukan ini.',
      'Fünf Sterne sind, wie der Nächste das hier findet.');
  String get rateSheetTitle => _t('Enjoying AyahReel?', 'هل أعجبك؟',
      'AyahReel پسند آ رہا ہے؟', 'Menikmati AyahReel?',
      'Gefällt dir AyahReel?');
  String get rateSheetBody => _t(
      'A rating on the store is what puts this in front of the next '
          'person looking for a way to share a verse. It takes a minute.',
      'تقييمك في المتجر يرفع التطبيق أمام من يبحث عن مقاطع قرآنية '
          'يشاركها. دقيقة واحدة، وأثرها يدوم.',
      'سٹور پر ایک ریٹنگ ہی اسے اس اگلے شخص کے سامنے لاتی ہے جو آیت '
          'شیئر کرنے کا راستہ ڈھونڈ رہا ہے۔ ایک منٹ لگتا ہے۔',
      'Penilaian di toko itulah yang menampilkan ini kepada orang '
          'berikutnya yang mencari cara membagikan ayat. Hanya semenit.',
      'Eine Bewertung im Store bringt das hier vor die Augen des '
          'Nächsten, der einen Weg sucht, einen Vers zu teilen. Dauert eine Minute.');

  /// Says which store it is about to open, because the button leaves
  /// the app — a "Rate us" that silently jumps to another app is a
  /// worse surprise than a longer label.
  String get openAppStore => _t('Open the App Store', 'افتح App Store',
      'App Store کھولیں', 'Buka App Store', 'App Store öffnen');
  String get openPlayStore => _t('Open Google Play', 'افتح Google Play',
      'Google Play کھولیں', 'Buka Google Play', 'Google Play öffnen');
  String get storeOpenFailed => _t(
      'Couldn’t open the store. Check your connection.',
      'تعذّر فتح المتجر. تحقق من اتصالك.',
      'سٹور نہیں کھل سکا۔ اپنا کنکشن دیکھیں۔',
      'Toko tidak dapat dibuka. Periksa koneksi Anda.',
      'Der Store ließ sich nicht öffnen. Prüf deine Verbindung.');
  String get sectionShareReward => _t('SHARE THE REWARD', 'شارك الأجر',
      'اجر میں شریک کریں', 'BAGIKAN PAHALANYA', 'DEN LOHN TEILEN');
  String get joinTelegramTitle => _t('Join Telegram', 'انضم إلى تيليجرام',
      'ٹیلیگرام جوائن کریں', 'Gabung Telegram', 'Telegram beitreten');

  /// The Telegram invitation that follows a good moment
  /// (TelegramInvite).
  String get telegramInviteTitle => _t(
      'Join us on Telegram',
      'انضم إلينا على تيليجرام',
      'ٹیلیگرام پر ہمارے ساتھ شامل ہوں',
      'Gabung bersama kami di Telegram',
      'Komm zu uns auf Telegram');
  String get telegramInviteBody => _t(
      'New reciters and features are announced there first.',
      'نعلن هناك أولًا عن القرّاء والميزات الجديدة.',
      'نئے قاری اور نئی سہولتوں کا اعلان سب سے پہلے وہیں ہوتا ہے۔',
      'Qari dan fitur baru diumumkan di sana lebih dulu.',
      'Neue Rezitatoren und Funktionen kündigen wir dort zuerst an.');
  String get telegramJoin =>
      _t('Join', 'انضم', 'شامل ہوں', 'Gabung', 'Beitreten');
  String get telegramJoined => _t('Already joined', 'انضممت بالفعل',
      'میں پہلے سے شامل ہوں', 'Sudah bergabung', 'Bin schon dabei');

  /// The invitation's way out for good.
  String get telegramNever => _t("Don't ask again", 'لا تسألني مرة أخرى',
      'دوبارہ مت پوچھیں', 'Jangan tanya lagi', 'Nicht mehr fragen');
  String get inviteEarnTitle => _t('Invite someone · earn ✦ 5',
      'ادعُ أحدًا · اكسب ✦ 5', 'کسی کو مدعو کریں · کمائیں ✦ 5',
      'Ajak seseorang · dapat ✦ 5', 'Lade jemanden ein · verdien ✦ 5');
  String get inviteEarnSubtitle => _t(
      'Whoever guides another to goodness shares in their reward.',
      'من دلّ على الخير فله مثل أجر فاعله.',
      'جو کسی کو بھلائی کی طرف رہنمائی کرے، اسے بھی اتنا ہی اجر ملتا ہے۔',
      'Siapa menunjukkan kebaikan kepada orang lain, ia beroleh pahala seperti pelakunya.',
      'Wer einen anderen zum Guten leitet, hat Anteil an dessen Lohn.');

  // ---- feedback ----------------------------------------------------
  // The only channel that carries a sentence back from a user. Worded
  // as a question about the app rather than a request for praise —
  // what arrives has to be usable, and "how are we doing?" collects
  // compliments while "what would make this better?" collects work.
  String get sectionFeedback =>
      _t('FEEDBACK', 'ملاحظاتك', 'آپ کی رائے', 'MASUKAN', 'RÜCKMELDUNG');
  String get feedbackRowTitle => _t('Send feedback', 'أرسل ملاحظة',
      'رائے بھیجیں', 'Kirim masukan', 'Rückmeldung senden');
  String get feedbackRowSubtitle => _t(
      'What to fix, what to add. It comes straight to us.',
      'ما الذي نُصلحه أو نضيفه؟ تصل إلينا مباشرة.',
      'کیا ٹھیک کریں، کیا شامل کریں۔ سیدھا ہم تک پہنچتی ہے۔',
      'Apa yang perlu diperbaiki, apa yang perlu ditambah. Langsung sampai ke kami.',
      'Was zu beheben, was hinzuzufügen ist. Es kommt direkt bei uns an.');
  String get feedbackSheetTitle => _t('What would make this better?',
      'ما الذي يجعله أفضل؟', 'اسے بہتر کیا بنائے گا؟',
      'Apa yang membuat ini lebih baik?', 'Was würde das hier besser machen?');
  String get feedbackSheetBody => _t(
      'A problem or an idea. Every note is read.',
      'مشكلة أو فكرة. نقرأ كل رسالة.',
      'کوئی مسئلہ یا کوئی خیال۔ ہر پیغام پڑھا جاتا ہے۔',
      'Masalah atau gagasan. Setiap pesan kami baca.',
      'Ein Problem oder eine Idee. Jede Nachricht wird gelesen.');

  /// The one line over the field on Settings' feedback sheet: what makes
  /// a report something we can act on.
  String get feedbackDetailHint => _t(
      'Reporting a problem? Tell us what happened in as much detail as '
          'you can, so we can fix it exactly.',
      'تبلّغ عن مشكلة؟ صف ما حدث بأكبر قدر من التفاصيل لنصلحه بدقة.',
      'کوئی مسئلہ بتا رہے ہیں؟ جو ہوا، جتنی تفصیل سے ہو سکے لکھیں، تاکہ ہم '
          'اسے ٹھیک ٹھیک درست کر سکیں۔',
      'Melaporkan masalah? Ceritakan apa yang terjadi sedetail mungkin, '
          'agar kami bisa memperbaikinya dengan tepat.',
      'Du meldest ein Problem? Beschreib so genau wie möglich, was passiert '
          'ist, damit wir es gezielt beheben können.');

  /// The automatic ask. Names what they have already done, because a
  /// question that arrives out of nowhere gets a shrug and one that
  /// arrives after five reels gets an answer.
  String get feedbackAfterRenderTitle => _t('How has it been so far?',
      'كيف كانت التجربة؟', 'اب تک کیسا رہا؟', 'Sejauh ini bagaimana?',
      'Wie war es bisher?');
  String get feedbackAfterRenderBody => _t(
      'You have made a few reels now. What should have been easier?',
      'صنعتَ عدة مقاطع. ما الذي كان ينبغي أن يكون أسهل؟',
      'آپ کچھ ریلز بنا چکے ہیں۔ کیا چیز آسان ہونی چاہیے تھی؟',
      'Anda sudah membuat beberapa reel. Apa yang seharusnya lebih mudah?',
      'Du hast jetzt ein paar Reels gemacht. Was hätte leichter sein sollen?');
  String get feedbackHint =>
      _t('Type here…', 'اكتب هنا…', 'یہاں لکھیں…', 'Tulis di sini…',
          'Hier tippen …');
  String get feedbackContactHint => _t(
      'Your email, if you want a reply (optional)',
      'بريدك، إن أردت ردًا (اختياري)',
      'آپ کا ای میل، اگر جواب چاہیے (اختیاری)',
      'Email Anda, jika ingin dibalas (opsional)',
      'Deine E-Mail, falls du eine Antwort willst (optional)');
  String get feedbackSend =>
      _t('Send', 'إرسال', 'بھیجیں', 'Kirim', 'Senden');
  String get feedbackThanks => _t('Sent. Thank you ✦',
      'وصلت رسالتك. جزاك الله خيرًا ✦', 'بھیج دیا گیا۔ جزاک اللہ خیراً ✦',
      'Terkirim. Terima kasih ✦', 'Gesendet. Vielen Dank ✦');
  /// The button on a save's failure message, and on the notice after
  /// the app closed during one. It opens the feedback sheet with the
  /// note already written.
  String get reportProblem =>
      _t('Report', 'أبلغنا', 'رپورٹ کریں', 'Laporkan', 'Melden');
  String get feedbackExportTitle => _t(
      'Tell us what went wrong',
      'أخبرنا بما حدث',
      'ہمیں بتائیں کیا ہوا',
      'Ceritakan apa yang terjadi',
      'Sag uns, was schiefging');
  String get feedbackExportBody => _t(
      'What happened on your phone is attached to this note — which step '
          'failed, and how much memory the phone has. Add anything you '
          'noticed, or just send it.',
      'أرفقنا بهذه الرسالة ما حدث على هاتفك — أي خطوة تعثّرت، وكم في '
          'الهاتف من ذاكرة. أضف ما لاحظت، أو أرسلها كما هي.',
      'آپ کے فون پر جو ہوا وہ اس پیغام کے ساتھ لگا ہے — کون سا مرحلہ ناکام '
          'ہوا، اور فون میں کتنی میموری ہے۔ جو آپ نے دیکھا وہ لکھ دیں، یا '
          'ویسے ہی بھیج دیں۔',
      'Apa yang terjadi di ponsel Anda sudah terlampir di pesan ini — '
          'langkah mana yang gagal, dan berapa memori ponsel Anda. '
          'Tambahkan yang Anda perhatikan, atau langsung kirim.',
      'Was auf deinem Handy passiert ist, hängt an dieser Nachricht — '
          'welcher Schritt fehlschlug und wie viel Arbeitsspeicher das Handy '
          'hat. Ergänze, was dir aufgefallen ist, oder schick sie einfach so.');

  /// What the Report sheet opens with, so Send works at once.
  String get feedbackExportDraft => _t(
      'My reel didn’t save.',
      'لم يُحفظ المقطع.',
      'میری ریل محفوظ نہیں ہوئی۔',
      'Reel saya tidak tersimpan.',
      'Mein Reel wurde nicht gespeichert.');

  /// Shown once, at the next launch, when the app closed while a reel
  /// was saving — which, on a phone short of memory, is the system
  /// killing it and leaves nothing on screen to explain itself.
  String get exportLostNotice => _t(
      'AyahReel closed while your last reel was saving — usually because '
          'the phone ran short of memory. Saves on this phone now go in '
          'smaller steps: slower, but they finish.',
      'أُغلق AyahReel أثناء حفظ مقطعك الأخير — غالبًا لأن ذاكرة الهاتف لم '
          'تكفِ. صار الحفظ على هذا الهاتف يتم على مراحل أصغر: أبطأ، لكنه '
          'يكتمل.',
      'آپ کی پچھلی ریل محفوظ ہوتے ہوئے AyahReel بند ہو گیا — عموماً فون کی '
          'میموری کم پڑنے سے۔ اس فون پر اب محفوظ کرنا چھوٹے مراحل میں ہوتا '
          'ہے: آہستہ، مگر مکمل ہوتا ہے۔',
      'AyahReel tertutup saat reel terakhir Anda sedang disimpan — biasanya '
          'karena memori ponsel tidak cukup. Penyimpanan di ponsel ini '
          'sekarang dilakukan bertahap: lebih lambat, tapi selesai.',
      'AyahReel hat sich geschlossen, während dein letztes Reel gespeichert '
          'wurde — meist, weil dem Handy der Arbeitsspeicher ausging. Auf '
          'diesem Handy wird jetzt in kleineren Schritten gespeichert: '
          'langsamer, aber es wird fertig.');
  String get feedbackFailed => _t(
      'Couldn’t send. Check your connection and try again — nothing '
          'you wrote was lost.',
      'تعذّر الإرسال. تحقق من اتصالك وحاول مجددًا — لم تفقد ما كتبت.',
      'بھیجا نہ جا سکا۔ اپنا کنکشن دیکھیں اور دوبارہ کوشش کریں — آپ کا '
          'لکھا ہوا کچھ ضائع نہیں ہوا۔',
      'Gagal terkirim. Periksa koneksi Anda lalu coba lagi — tulisan Anda '
          'tidak hilang.',
      'Senden fehlgeschlagen. Prüf deine Verbindung und versuch es erneut '
          '— nichts von dem, was du geschrieben hast, ging verloren.');
  String get sectionLegal =>
      _t('LEGAL', 'قانوني', 'قانونی', 'HUKUM', 'RECHTLICHES');
  String get privacyPolicy => _t('Privacy policy', 'سياسة الخصوصية',
      'رازداری کی پالیسی', 'Kebijakan privasi', 'Datenschutzerklärung');
  String get privacyPolicySubtitle => _t(
      'What the app fetches, and what never leaves your device.',
      'ما يجلبه التطبيق، وما لا يغادر جهازك أبدًا.',
      'ایپ کیا لاتی ہے، اور کیا کبھی آپ کے آلے سے باہر نہیں جاتا۔',
      'Apa yang diambil aplikasi, dan apa yang tak pernah keluar dari perangkat Anda.',
      'Was die App holt und was dein Gerät nie verlässt.');
  String get termsOfUse => _t('Terms of use', 'شروط الاستخدام',
      'شرائطِ استعمال', 'Ketentuan penggunaan', 'Nutzungsbedingungen');
  String get termsOfUseSubtitle => _t(
      'Apple’s standard end-user licence agreement.',
      'اتفاقية أبل القياسية للمستخدم النهائي.',
      'ایپل کا معیاری اینڈ یوزر لائسنس معاہدہ۔',
      'Perjanjian lisensi pengguna akhir standar Apple.',
      'Apples Standard-Lizenzvereinbarung für Endnutzer.');
  String reminderSetSnack(String time) => _t(
      'Set. See you every day at $time ✦',
      'تم. نلقاك كل يوم في $time ✦',
      'طے ہو گیا۔ روزانہ $time بجے ملاقات ✦',
      'Tersetel. Sampai jumpa setiap hari pukul $time ✦',
      'Eingestellt. Bis täglich um $time ✦');
  String get linkOpenFailed => _t(
      'Couldn’t open the link. Check your connection.',
      'تعذّر فتح الرابط. تحقق من اتصالك.',
      'لنک نہیں کھل سکا۔ اپنا کنکشن دیکھیں۔',
      'Tautan tidak dapat dibuka. Periksa koneksi Anda.',
      'Der Link ließ sich nicht öffnen. Prüf deine Verbindung.');
  String get notificationsBlockedSnack => _t(
      'Your phone is blocking notifications for AyahReel.',
      'هاتفك يحظر إشعارات AyahReel.',
      'آپ کا فون AyahReel کی اطلاعات روک رہا ہے۔',
      'Ponsel Anda memblokir notifikasi AyahReel.',
      'Dein Handy blockiert Mitteilungen für AyahReel.');
  String get openSettings => _t('Open settings', 'فتح الإعدادات',
      'ترتیبات کھولیں', 'Buka pengaturan', 'Einstellungen öffnen');
  String get blockedBannerTitle => _t('Your reminders can’t reach you',
      'تذكيراتك لا تصلك', 'آپ کی یاد دہانیاں آپ تک نہیں پہنچ رہیں',
      'Pengingat Anda tidak bisa sampai', 'Deine Erinnerungen erreichen dich nicht');
  String get blockedBannerBody => _t(
      'Notifications are switched off for AyahReel in your '
          'phone’s settings. Nothing below can be delivered '
          'until they are back on.',
      'الإشعارات مطفأة لتطبيق AyahReel في إعدادات هاتفك. '
          'لن يصلك شيء مما بالأسفل حتى تُعاد تفعيلها.',
      'آپ کے فون کی ترتیبات میں AyahReel کی اطلاعات بند ہیں۔ جب تک وہ '
          'دوبارہ آن نہ ہوں، نیچے کی کوئی چیز نہیں پہنچ سکتی۔',
      'Notifikasi untuk AyahReel dimatikan di pengaturan ponsel Anda. '
          'Tidak ada di bawah ini yang bisa dikirim sampai dinyalakan lagi.',
      'Mitteilungen sind für AyahReel in den Einstellungen deines Handys '
          'ausgeschaltet. Nichts hierunter kann zugestellt werden, bis sie wieder an sind.');
  String get openPhoneSettings => _t('Open phone settings',
      'افتح إعدادات الهاتف', 'فون کی ترتیبات کھولیں',
      'Buka pengaturan ponsel', 'Handy-Einstellungen öffnen');

  // ---- storage sheet ----------------------------------------------
  String get storageTitle =>
      _t('Storage', 'التخزين', 'سٹوریج', 'Penyimpanan', 'Speicher');
  String get storageBody => _t(
      'Downloads rebuild themselves when needed. Clearing them '
          'never loses a reel.',
      'التنزيلات تُعيد بناء نفسها عند الحاجة. مسحها لا يفقدك أي مقطع.',
      'ڈاؤن لوڈز ضرورت پڑنے پر خود دوبارہ بن جاتے ہیں۔ انہیں صاف کرنے '
          'سے کوئی ریل ضائع نہیں ہوتی۔',
      'Unduhan membangun dirinya lagi saat dibutuhkan. Membersihkannya '
          'tidak pernah menghilangkan reel.',
      'Downloads bauen sich bei Bedarf neu auf. Sie zu leeren kostet nie ein Reel.');
  String get savedReels => _t('Saved reels', 'المقاطع المحفوظة',
      'محفوظ ریلز', 'Reel tersimpan', 'Gespeicherte Reels');
  String get savedCards => _t('Saved cards', 'البطاقات المحفوظة',
      'محفوظ کارڈز', 'Kartu tersimpan', 'Gespeicherte Karten');
  String get cardStills => _t('Card stills', 'لقطات البطاقات',
      'کارڈ کی تصاویر', 'Bingkai kartu', 'Karten-Standbilder');
  String get downloadedRecitations => _t('Downloaded recitations',
      'التلاوات المنزَّلة', 'ڈاؤن لوڈ شدہ تلاوتیں', 'Bacaan terunduh',
      'Geladene Rezitationen');
  String get downloadedScenery => _t('Downloaded scenery',
      'المشاهد المنزَّلة', 'ڈاؤن لوڈ شدہ مناظر', 'Pemandangan terunduh',
      'Geladene Kulissen');
  String get quranTextCache => _t('Quran text cache', 'نص القرآن المخزّن',
      'قرآنی متن کا کیشے', 'Singgahan teks Al-Qur’an', 'Quran-Textspeicher');
  String get renderCache => _t('Render cache', 'ملفات التصدير المؤقتة',
      'رینڈر کیشے', 'Singgahan render', 'Render-Zwischenspeicher');
  String get clear => _t('Clear', 'مسح', 'صاف کریں', 'Bersihkan', 'Leeren');

  // ---- invite -----------------------------------------------------
  String get inviteHeadline => _t(
      'Share it, and every verse\nthey share counts for you too',
      'شاركه، وكلّ آيةٍ ينشرونها\nتُكتب لك أيضًا',
      'اسے شیئر کریں، ان کی ہر آیت\nآپ کے نامۂ اعمال میں بھی',
      'Bagikan, dan setiap ayat yang mereka\nbagikan terhitung untuk Anda juga',
      'Teile es, und jeder Vers, den sie\nteilen, zählt auch für dich');
  String get inviteBody => _t(
      'Whoever you bring here, every verse they send from '
          'now on is written for you as well, for as long as '
          'they keep sending them.',
      'كل من تدلّه على التطبيق، تُكتب لك كل آية يرسلها من '
          'الآن فصاعدًا، ما دام يواصل إرسالها.',
      'جس کو بھی آپ یہاں لائیں، وہ اب سے جو آیت بھی بھیجے گا وہ آپ کے '
          'لیے بھی لکھی جائے گی، جب تک وہ بھیجتا رہے۔',
      'Siapa pun yang Anda bawa ke sini, setiap ayat yang ia kirim mulai '
          'sekarang juga tercatat untuk Anda, selama ia terus mengirimnya.',
      'Wen immer du herbringst — jeder Vers, den er von jetzt an sendet, '
          'wird auch dir geschrieben, solange er sie weiter sendet.');
  String get hadithGuidesToGood => _t(
      '“Whoever guides to good has a reward\nlike the one who does it.”',
      '«مَن دَلَّ عَلَى خَيْرٍ فَلَهُ مِثْلُ\nأَجْرِ فَاعِلِهِ»',
      '«جو بھلائی کی طرف رہنمائی کرے، اُس کے لیے\nکرنے والے جیسا اجر ہے۔»',
      '"Siapa menunjukkan kepada kebaikan, baginya pahala\nseperti pelakunya."',
      '„Wer zum Guten weist, dem gebührt Lohn\nwie dem, der es tut.“');
  String get sahihMuslim => _t('Sahih Muslim', 'صحيح مسلم', 'صحیح مسلم',
      'Sahih Muslim', 'Sahih Muslim');
  String get shareAyahReel => _t('Share AyahReel', 'شارك AyahReel',
      'AyahReel شیئر کریں', 'Bagikan AyahReel', 'AyahReel teilen');

  /// What the invite's story card says under the hadith. A story is
  /// looked at, not read, so this is one line: what the app is and
  /// that it costs nothing. The store links are for the caption the
  /// user adds, not the picture.
  String get storyTagline => _t('Quran reels in under a minute',
      'مقاطع قرآنية في أقل من دقيقة', 'ایک منٹ سے کم میں قرآنی ریلز',
      'Reel Al-Qur’an dalam kurang dari semenit',
      'Quran-Reels in unter einer Minute');
  String get storyFooter => _t(
      'Free on the App Store & Google Play',
      'مجانًا على App Store و Google Play',
      'App Store اور Google Play پر مفت',
      'Gratis di App Store & Google Play',
      'Kostenlos im App Store & bei Google Play');

  /// The one ask on the story card, set in gold at its foot.
  String get storyCta => _t(
      'Search "AyahReel"\nto download the app',
      'ابحث عن "AyahReel"\nلتحميل التطبيق',
      '"AyahReel" تلاش کریں\nاور ایپ ڈاؤن لوڈ کریں',
      'Cari "AyahReel"\nuntuk mengunduh aplikasinya',
      'Suche „AyahReel“\num die App zu laden');
  String get notNow =>
      _t('Not now', 'ليس الآن', 'ابھی نہیں', 'Nanti saja', 'Jetzt nicht');

  /// The soft update prompt. Never a wall: the user can always carry on
  /// with the version they have, and is asked again next launch.
  String get updateTitle => _t('A new version is out', 'صدر إصدار جديد',
      'نیا ورژن آ گیا ہے', 'Versi baru sudah keluar',
      'Eine neue Version ist da');
  String updateBody(String version) => _t(
      'Version $version is on the store, with the newest scenes and fixes.',
      'الإصدار $version متاح الآن في المتجر، بأحدث المشاهد والتحسينات.',
      'ورژن $version سٹور پر ہے، تازہ ترین مناظر اور بہتریوں کے ساتھ۔',
      'Versi $version sudah di toko, dengan adegan dan perbaikan terbaru.',
      'Version $version ist im Store, mit den neuesten Szenen und Korrekturen.');
  String get updateNow =>
      _t('Update', 'تحديث', 'اپ ڈیٹ', 'Perbarui', 'Aktualisieren');
  String get loseRewardsConfirm => _t(
      'Are you sure you want to lose the rewards?',
      'أمتأكد أنك تريد تفويت هذا الأجر؟',
      'کیا واقعی آپ یہ اجر گنوانا چاہتے ہیں؟',
      'Yakin ingin melewatkan pahalanya?',
      'Willst du wirklich auf den Lohn verzichten?');
  String get leave => _t('Leave', 'مغادرة', 'چھوڑ دیں', 'Keluar', 'Verlassen');
  String get stay => _t('Stay', 'البقاء', 'رکے رہیں', 'Tetap', 'Bleiben');
  String get inviteSomeone => _t('Invite someone', 'ادعُ أحدًا',
      'کسی کو مدعو کریں', 'Ajak seseorang', 'Jemanden einladen');
  String get inviteSomeoneSemantics => _t(
      'Invite someone to AyahReel',
      'ادعُ أحدًا إلى AyahReel',
      'کسی کو AyahReel کی دعوت دیں',
      'Ajak seseorang ke AyahReel',
      'Jemanden zu AyahReel einladen');

  // ---- app share --------------------------------------------------
  /// Both stores, always, in whichever language the sender is using:
  /// the sender's platform says nothing about the recipient's, and a
  /// message that only names one store is a dead end for half the
  /// people it reaches.
  String get appShareMessage => _t(
      '🎬 Make a Quran reel in a minute — no editing. Pick a reciter and '
          'your verses, and it is ready to post.\n'
          '🧠 Test how much Quran you carry in Tanafus, and dare a friend '
          'to beat your score.\n\n'
          '📲 Download AyahReel\n'
          'iPhone: $appStoreUrl\n'
          'Android: $playStoreUrl',
      '🎬 اصنع مقطعًا قرآنيًا في دقيقة — بلا مونتاج. اختر القارئ '
          'وآياتك، ويجهز للنشر.\n'
          '🧠 اختبر كم تحمل من القرآن في تنافُس، وتحدَّ صديقًا أن يتفوّق '
          'على نتيجتك.\n\n'
          '📲 حمّل AyahReel\n'
          'آيفون: $appStoreUrl\n'
          'أندرويد: $playStoreUrl',
      '🎬 ایک منٹ میں قرآنی ریل بنائیں — بغیر ایڈیٹنگ۔ قاری اور اپنی آیات '
          'چنیں، اور پوسٹ کے لیے تیار۔\n'
          '🧠 تنافُس میں آزمائیں کہ آپ کتنا قرآن جانتے ہیں، اور دوست کو '
          'اپنا اسکور ہرانے کا چیلنج دیں۔\n\n'
          '📲 AyahReel ڈاؤن لوڈ کریں\n'
          'آئی فون: $appStoreUrl\n'
          'اینڈرائیڈ: $playStoreUrl',
      '🎬 Buat reel Al-Qur’an dalam semenit — tanpa mengedit. Pilih qari '
          'dan ayatmu, langsung siap diunggah.\n'
          '🧠 Uji seberapa banyak Al-Qur’an yang kamu hafal di Tanafus, dan '
          'tantang teman mengalahkan skormu.\n\n'
          '📲 Unduh AyahReel\n'
          'iPhone: $appStoreUrl\n'
          'Android: $playStoreUrl',
      '🎬 Mach ein Quran-Reel in einer Minute – ohne Schneiden. Rezitator '
          'und Verse wählen, fertig zum Posten.\n'
          '🧠 Teste in Tanafus, wie viel Quran du in dir trägst, und fordere '
          'einen Freund heraus, deine Punkte zu schlagen.\n\n'
          '📲 AyahReel laden\n'
          'iPhone: $appStoreUrl\n'
          'Android: $playStoreUrl');

  /// The caption a reel goes out with: what it is, and where it came
  /// from. No store links: a reel is posted to a feed, where a link is
  /// noise, and only a gift handed to a person carries them — see
  /// [dedicationShareMessage].
  String reelShareCaption(String surahName, String reciterName) => _t(
      '🎧 Surah $surahName · $reciterName\n'
          '✨ Made with AyahReel — a Quran reel in a minute, no editing',
      '🎧 سورة ${localizedSurahName(surahName)} · '
          '${localizedReciterName(reciterName)}\n'
          '✨ صُنع بتطبيق AyahReel — مقطع قرآني في دقيقة، بلا مونتاج',
      '🎧 سورۃ $surahName · $reciterName\n'
          '✨ AyahReel سے بنایا گیا — ایک منٹ میں قرآنی ریل، بغیر ایڈیٹنگ',
      '🎧 Surah $surahName · $reciterName\n'
          '✨ Dibuat dengan AyahReel — reel Al-Qur’an dalam semenit, tanpa '
          'mengedit',
      '🎧 Sure $surahName · $reciterName\n'
          '✨ Gemacht mit AyahReel – ein Quran-Reel in einer Minute, ohne '
          'Schneiden');
  String get shareCancelled => _t(
      'Share cancelled, no ✦ this time.',
      'أُلغيت المشاركة، لا ✦ هذه المرة.',
      'شیئرنگ منسوخ، اس بار ✦ نہیں۔',
      'Berbagi dibatalkan, tidak ada ✦ kali ini.',
      'Teilen abgebrochen, diesmal kein ✦.');
  String shareAwarded(int points) => _t(
      '✦ +$points, may it reach someone who needs it.',
      '‎+$points ✦، عسى أن يصل إلى من يحتاجه.',
      '✦ ‎+$points، اللہ کرے یہ اُس تک پہنچے جسے اس کی ضرورت ہے۔',
      '✦ +$points, semoga sampai kepada yang membutuhkannya.',
      '✦ +$points — möge es jemanden erreichen, der es braucht.');
  String get shareAlreadyEarned => _t(
      'Already earned today. Share again tomorrow for more ✦.',
      'كسبت أجر اليوم بالفعل. شارك غدًا لمزيد من ✦.',
      'آج کا اجر مل چکا۔ مزید ✦ کے لیے کل پھر شیئر کریں۔',
      'Sudah didapat hari ini. Bagikan lagi besok untuk ✦ lainnya.',
      'Heute schon verdient. Teile morgen wieder für mehr ✦.');

  // ---- Badges ----

  String get badgesTitle =>
      _t('Badges', 'الأوسمة', 'اعزازات', 'Lencana', 'Abzeichen');
  String get badgesBody => _t(
      'One for each milestone on the way. Earned once, kept for good.',
      'وسام لكل مرحلة تبلغها. يُكسب مرة، ويبقى.',
      'راستے کے ہر سنگِ میل کے لیے ایک۔ ایک بار ملے، ہمیشہ کے لیے رہے۔',
      'Satu untuk tiap tonggak di perjalanan. Sekali diraih, selamanya milik Anda.',
      'Eines für jeden Meilenstein. Einmal verdient, für immer behalten.');

  /// The badge's name, by its id (see Badge in rewards_service.dart).
  String badgeName(String id) => switch (id) {
        'reels1' => _t('First reel', 'أول مقطع', 'پہلی ریل', 'Reel pertama',
            'Erstes Reel'),
        'reels5' => _t('Five reels', 'خمسة مقاطع', 'پانچ ریلز', 'Lima reel',
            'Fünf Reels'),
        'reels10' => _t('Ten reels', 'عشرة مقاطع', 'دس ریلز', 'Sepuluh reel',
            'Zehn Reels'),
        'reels25' => _t('Twenty-five reels', 'خمسة وعشرون مقطعًا',
            'پچیس ریلز', 'Dua puluh lima reel', 'Fünfundzwanzig Reels'),
        'reels50' => _t('Fifty reels', 'خمسون مقطعًا', 'پچاس ریلز',
            'Lima puluh reel', 'Fünfzig Reels'),
        'reels100' => _t('A hundred reels', 'مئة مقطع', 'سو ریلز',
            'Seratus reel', 'Hundert Reels'),
        'widget' => _t('Verse on the home screen', 'آية على الشاشة',
            'ہوم سکرین پر آیت', 'Ayat di layar beranda',
            'Vers auf dem Startbildschirm'),
        _ => id,
      };

  /// What an unearned badge wants: the reels still to make, or the
  /// widget still to place.
  String badgeReelsToGo(int n) => _t(
      '${reelsCount(n)} to go',
      'بقي ${reelsCount(n)}',
      '${reelsCount(n)} باقی',
      '${reelsCount(n)} lagi',
      'noch ${reelsCount(n)}');
  String get badgeWidgetToGo => _t(
      'Put the widget on your home screen',
      'ضع الأداة على شاشتك الرئيسية',
      'ویجٹ اپنی ہوم سکرین پر رکھیں',
      'Pasang widget di layar beranda Anda',
      'Setz das Widget auf deinen Startbildschirm');

  /// Toast when a reel earns a badge.
  String badgeEarned(String name) => _t('✦ New badge: $name',
      '✦ وسام جديد: $name', '✦ نیا اعزاز: $name', '✦ Lencana baru: $name',
      '✦ Neues Abzeichen: $name');

  /// Toast when the widget is found on the home screen for the first
  /// time.
  String widgetBadgeEarned(int points) => _t(
      '✦ New badge: Verse on the home screen · +$points',
      '✦ وسام جديد: آية على الشاشة · ‎+$points',
      '✦ نیا اعزاز: ہوم سکرین پر آیت · ‎+$points',
      '✦ Lencana baru: Ayat di layar beranda · +$points',
      '✦ Neues Abzeichen: Vers auf dem Startbildschirm · +$points');

  // ---- reminder dialogs -------------------------------------------
  String get proudExportTitle => _t(
      'That reel turned out beautifully ✦',
      'مقطعك خرج في غاية الجمال ✦',
      'یہ ریل بہت خوبصورت بنی ✦',
      'Reel itu jadi indah sekali ✦',
      'Das Reel ist wunderschön geworden ✦');
  String get proudExportBodyNoTime => _t(
      'Want a daily nudge to create one verse a day and keep '
          'your streak going?',
      'أتريد تذكيرًا يوميًا لصنع آية واحدة كل يوم والحفاظ على مواظبتك؟',
      'کیا آپ روزانہ ایک یاد دہانی چاہیں گے کہ ہر دن ایک آیت بنائیں '
          'اور اپنا تسلسل جاری رکھیں؟',
      'Mau pengingat harian untuk membuat satu ayat sehari dan menjaga '
          'rentetan Anda?',
      'Möchtest du täglich einen Anstoß, einen Vers am Tag zu machen und '
          'deine Serie zu halten?');
  String proudExportBodyWithTime(String time) => _t(
      'You asked us to meet you at $time. Allow '
          'notifications and we will be there, one quiet '
          'reminder a day, nothing else.',
      'طلبت أن نوافيك في $time. اسمح بالإشعارات وسنكون هناك: '
          'تذكير هادئ واحد في اليوم، لا غير.',
      'آپ نے کہا تھا کہ $time بجے ملیں۔ اطلاعات کی اجازت دیں، ہم وہاں '
          'ہوں گے: دن میں ایک خاموش یاد دہانی، اور کچھ نہیں۔',
      'Anda meminta kami menemui Anda pukul $time. Izinkan notifikasi '
          'dan kami akan hadir: satu pengingat tenang sehari, tidak lebih.',
      'Du wolltest, dass wir dich um $time treffen. Erlaube Mitteilungen, '
          'und wir sind da: eine stille Erinnerung am Tag, sonst nichts.');
  String get remindMeDaily => _t('Remind me daily', 'ذكّرني يوميًا',
      'روزانہ یاد دلائیں', 'Ingatkan saya tiap hari',
      'Täglich erinnern');
  String get yesRemindMe => _t('Yes, remind me', 'نعم، ذكّرني',
      'ہاں، یاد دلائیں', 'Ya, ingatkan saya', 'Ja, erinner mich');
  String get oneSwitchAway => _t('One switch away', 'يفصلك زر واحد',
      'بس ایک سوئچ کی دوری', 'Tinggal satu sakelar',
      'Nur ein Schalter entfernt');
  String get oneSwitchAwayBody => _t(
      'Your phone has notifications turned off for AyahReel and '
          'will not ask again. Turn them on in Settings and your '
          'reminder starts tomorrow.',
      'هاتفك أوقف إشعارات AyahReel ولن يسأل مرة أخرى. فعّلها من '
          'الإعدادات وسيبدأ تذكيرك غدًا.',
      'آپ کے فون نے AyahReel کی اطلاعات بند کر دی ہیں اور وہ دوبارہ نہیں '
          'پوچھے گا۔ ترتیبات میں انہیں آن کریں، آپ کی یاد دہانی کل سے شروع ہو جائے گی۔',
      'Ponsel Anda mematikan notifikasi AyahReel dan tidak akan bertanya '
          'lagi. Nyalakan di Pengaturan, pengingat Anda mulai besok.',
      'Dein Handy hat Mitteilungen für AyahReel ausgeschaltet und fragt '
          'nicht erneut. Schalte sie in den Einstellungen ein, dann startet '
          'deine Erinnerung morgen.');
  String get later => _t('Later', 'لاحقًا', 'بعد میں', 'Nanti', 'Später');
  String get channelDailyName => _t('Daily reminder', 'التذكير اليومي',
      'روزانہ یاد دہانی', 'Pengingat harian', 'Tägliche Erinnerung');
  String get channelDailyDescription => _t(
      'One invitation a day: a Quran quiz to play, or an ayah reel to make',
      'دعوة واحدة كل يوم: مسابقة قرآنية تلعبها، أو مقطع آية تصنعه',
      'روزانہ ایک دعوت: کھیلنے کو قرآنی کوئز، یا بنانے کو آیت کی ریل',
      'Satu ajakan setiap hari: kuis Al-Qur’an untuk dimainkan, atau reel '
          'ayat untuk dibuat',
      'Eine Einladung am Tag: ein Quran-Quiz zum Spielen oder ein '
          'Vers-Reel zum Machen');
  String get channelPersonalName => _t('My reminder', 'تذكيري',
      'میری یاد دہانی', 'Pengingat saya', 'Meine Erinnerung');
  String get channelPersonalDescription => _t(
      'Your daily reminder, at the time you chose in Settings: a Quran quiz '
          'or a reel',
      'تذكيرك اليومي، في الوقت الذي اخترته في الإعدادات: مسابقة قرآنية أو '
          'مقطع',
      'آپ کی روزانہ یاد دہانی، اُس وقت پر جو آپ نے ترتیبات میں چنا: قرآنی '
          'کوئز یا ریل',
      'Pengingat harian Anda, pada waktu yang Anda pilih di Pengaturan: '
          'kuis Al-Qur’an atau reel',
      'Deine tägliche Erinnerung, zur in den Einstellungen gewählten Zeit: '
          'ein Quran-Quiz oder ein Reel');
  String get remindMeHelpText => _t('REMIND ME EVERY DAY AT',
      'ذكّرني كل يوم في', 'مجھے روزانہ یاد دلائیں', 'INGATKAN SAYA TIAP HARI PUKUL',
      'ERINNER MICH TÄGLICH UM');

  // ---- featured / voice sheet -------------------------------------
  String get voiceSheetSubtitle => _t(
      'Your reel starts playing the moment you tap',
      'يبدأ مقطعك بالتشغيل لحظة النقر',
      'ٹیپ کرتے ہی آپ کی ریل چلنے لگتی ہے',
      'Reel Anda mulai diputar begitu Anda mengetuk',
      'Dein Reel startet, sobald du tippst');

  // ---- reel player ------------------------------------------------
  String reelTitle(String surahName, int start, int end) => _t(
      '$surahName · $start–$end',
      '${localizedSurahName(surahName)} · $start–$end',
      '$surahName · $start–$end',
      '$surahName · $start–$end',
      '$surahName · $start–$end');
  String get play => _t('Play', 'تشغيل', 'چلائیں', 'Putar', 'Abspielen');
  String get pause =>
      _t('Pause', 'إيقاف مؤقت', 'وقفہ', 'Jeda', 'Pause');
  String get replay => _t('Play from start', 'من البداية',
      'شروع سے چلائیں', 'Putar dari awal', 'Von vorn abspielen');
  String get reelUnavailable => _t(
      'This reel could not be opened.',
      'تعذّر فتح هذا المقطع.',
      'یہ ریل نہیں کھل سکی۔',
      'Reel ini tidak dapat dibuka.',
      'Dieses Reel ließ sich nicht öffnen.');

  // ---- onboarding -------------------------------------------------
  String get skip => _t('Skip', 'تخطّي', 'چھوڑ دیں', 'Lewati',
      'Überspringen');
  String get begin => _t('Begin', 'ابدأ', 'شروع کریں', 'Mulai', 'Beginnen');
  String get allowNotifications => _t('Allow notifications',
      'السماح بالإشعارات', 'اطلاعات کی اجازت دیں', 'Izinkan notifikasi',
      'Mitteilungen erlauben');
  String get maybeLater => _t('Maybe later', 'ربما لاحقًا', 'شاید بعد میں',
      'Mungkin nanti', 'Vielleicht später');

  String get obLangLabel => _t('FIRST, YOUR LANGUAGE', 'أولًا، لغتك',
      'سب سے پہلے، آپ کی زبان', 'PERTAMA, BAHASA ANDA', 'ZUERST DEINE SPRACHE');
  String get obLangHeadline => _t('Which language\ndo you read in?',
      'بأي لغة\nتقرأ؟', 'آپ کس زبان میں\nپڑھتے ہیں؟',
      'Anda membaca\ndalam bahasa apa?', 'In welcher Sprache\nliest du?');
  String get obLangBody => _t(
      'This sets the app itself. The Quran stays in Arabic, always.',
      'هذا يضبط لغة التطبيق وحده. أما القرآن فيبقى بالعربية، دائمًا.',
      'یہ صرف ایپ کی زبان مقرر کرتا ہے۔ قرآن ہمیشہ عربی ہی میں رہے گا۔',
      'Ini hanya mengatur aplikasinya. Al-Qur’an tetap dalam bahasa Arab, selalu.',
      'Das stellt nur die App ein. Der Quran bleibt Arabisch, immer.');
  String get obLangHint => _t(
      'You can change this any time in Settings.',
      'يمكنك تغيير هذا متى شئت من الإعدادات.',
      'آپ اسے ترتیبات میں جب چاہیں بدل سکتے ہیں۔',
      'Anda bisa mengubahnya kapan saja di Pengaturan.',
      'Du kannst das jederzeit in den Einstellungen ändern.');

  String get obDreamLabel => _t('WHAT THIS IS FOR', 'الغاية من هذا',
      'یہ کس لیے ہے', 'UNTUK APA INI', 'WOFÜR DAS IST');
  String get obDreamHeadline => _t(
      'One verse can travel\nfurther than you ever will',
      'آية واحدة قد تسافر\nأبعد مما ستسافر يومًا',
      'ایک آیت آپ سے کہیں\nدور تک سفر کر سکتی ہے',
      'Satu ayat bisa menempuh\nlebih jauh dari Anda',
      'Ein Vers kann weiter reisen,\nals du je reisen wirst');
  String get obDreamBody => _t(
      'Something you send tonight can be read in a city you will '
          'never visit, by someone you will never meet, long after you '
          'have forgotten you sent it.',
      'ما ترسله الليلة قد يُقرأ في مدينة لن تزورها، من شخص لن '
          'تلقاه، بعد أن تكون قد نسيت أنك أرسلته.',
      'جو آپ آج رات بھیجیں گے وہ ایسے شہر میں پڑھا جا سکتا ہے جہاں آپ '
          'کبھی نہیں جائیں گے، ایسے شخص کے ہاتھوں جس سے آپ کبھی نہیں '
          'ملیں گے، اور اُس وقت جب آپ بھول چکے ہوں گے کہ آپ نے بھیجا تھا۔',
      'Yang Anda kirim malam ini bisa dibaca di kota yang tak pernah '
          'Anda kunjungi, oleh orang yang tak pernah Anda temui, lama '
          'setelah Anda lupa pernah mengirimnya.',
      'Was du heute Nacht sendest, kann in einer Stadt gelesen werden, '
          'die du nie besuchst, von jemandem, den du nie triffst — lange '
          'nachdem du vergessen hast, dass du es gesendet hast.');

  String get obProblemLabel => _t('WHAT IS IN THE WAY',
      'ما الذي يعترض الطريق', 'راستے میں کیا ہے', 'APA YANG MENGHALANGI',
      'WAS IM WEG STEHT');
  String get obProblemHeadline => _t(
      'The feed was never\ngoing to carry it',
      'صفحات التمرير ما كانت\nلتحمله من تلقاء نفسها',
      'فیڈ اسے خود سے\nکبھی نہ اٹھاتی',
      'Linimasa memang tak akan\npernah membawanya',
      'Der Feed hätte es nie\nvon selbst getragen');
  String get obProblemBody => _t(
      'Millions of Muslims scroll past things that dull the heart, '
          'not because they chose them, but because nothing better was '
          'ever in the queue.',
      'ملايين المسلمين يمرّرون ما يُقسّي القلب، لا لأنهم اختاروه، '
          'بل لأن الأفضل لم يكن يومًا في الطريق إليهم.',
      'لاکھوں مسلمان ایسی چیزوں سے گزرتے ہیں جو دل کو کند کر دیتی ہیں — '
          'اس لیے نہیں کہ انہوں نے انہیں چنا، بلکہ اس لیے کہ اس سے بہتر '
          'کبھی قطار میں تھا ہی نہیں۔',
      'Jutaan Muslim menggulir melewati hal-hal yang menumpulkan hati, '
          'bukan karena memilihnya, tetapi karena tak pernah ada yang '
          'lebih baik dalam antrean.',
      'Millionen Muslime scrollen an Dingen vorbei, die das Herz stumpf '
          'machen — nicht, weil sie sie gewählt hätten, sondern weil nie '
          'etwas Besseres in der Warteschlange war.');

  String get obAnswerLabel => _t('SO HERE IS THE TURN', 'وهنا يأتي دورك',
      'تو یہاں آتا ہے آپ کا موڑ', 'DI SINILAH GILIRANNYA',
      'HIER KOMMT DIE WENDE');
  String get obAnswerBody => _t(
      'Ayah Reels puts you on the other side of the feed. Not '
          'scrolling it. Filling it.',
      'يضعك AyahReel على الجانب الآخر من الشاشة: لا تُمرّرها، بل تملؤها.',
      'AyahReel آپ کو فیڈ کی دوسری طرف لے آتا ہے۔ اسے سکرول کرنے والے '
          'نہیں — اسے بھرنے والے۔',
      'AyahReel menempatkan Anda di sisi lain linimasa. Bukan '
          'menggulirnya. Mengisinya.',
      'AyahReel stellt dich auf die andere Seite des Feeds. Nicht '
          'scrollen. Füllen.');

  String get obRewardLabel => _t('AND WHAT IT IS WORTH', 'وما قيمة ذلك',
      'اور اس کی قیمت کیا ہے', 'DAN APA NILAINYA', 'UND WAS ES WERT IST');
  String get obRewardBody => _t(
      'You send it once. It keeps working while you sleep, while '
          'you work, long after you have moved on.',
      'ترسلها مرة واحدة، وتظل تعمل وأنت نائم، وأنت في عملك، '
          'وبعد أن تمضي في حياتك.',
      'آپ اسے ایک بار بھیجتے ہیں۔ وہ آپ کے سوتے میں، آپ کے کام میں، '
          'اور آپ کے آگے بڑھ جانے کے بعد بھی کام کرتی رہتی ہے۔',
      'Anda mengirimnya sekali. Ia terus bekerja saat Anda tidur, saat '
          'Anda bekerja, lama setelah Anda melanjutkan hidup.',
      'Du sendest es einmal. Es wirkt weiter, während du schläfst, '
          'während du arbeitest, lange nachdem du weitergezogen bist.');

  /// The Tanafus page: the arena, in the same three beats as the rest.
  String get obArenaLabel => _t('AND WHEN YOU WANT A CHALLENGE',
      'وإن أردت تحدّيًا', 'اور جب آپ مقابلہ چاہیں',
      'DAN SAAT KAMU INGIN TANTANGAN', 'UND WENN DU DICH MESSEN WILLST');
  String get obArenaHeadline => _t(
      'Test how much Quran you carry — then dare a friend',
      'اختبر كم تحمل من القرآن، ثم تحدَّ صديقًا',
      'آزمائیں آپ کتنا قرآن جانتے ہیں، پھر دوست کو للکاریں',
      'Uji seberapa banyak Al-Qur’an yang kamu bawa, lalu tantang teman',
      'Teste, wie viel Quran du in dir trägst, dann fordere einen Freund '
          'heraus');
  String get obArenaBody => _t(
      'Tanafus asks questions from any juz or surah: complete the verse, '
          'find the missing word, name the surah. Your score becomes a '
          'constellation of the verses you met, and your code lets a '
          'friend play the very same round to beat it.',
      'تنافُس يسألك من أي جزء أو سورة: أكمل الآية، اعثر على الكلمة '
          'الناقصة، سمِّ السورة. تصير نتيجتك كوكبةً من الآيات التي قابلتها، '
          'ورمزك يتيح لصديق أن يلعب الجولة نفسها ليتفوّق عليك.',
      'تنافُس کسی بھی پارے یا سورت سے سوال کرتا ہے: آیت مکمل کریں، غائب '
          'لفظ ڈھونڈیں، سورت کا نام بتائیں۔ آپ کا اسکور ان آیات کا جھرمٹ بن '
          'جاتا ہے جن سے آپ ملے، اور آپ کا کوڈ دوست کو وہی راؤنڈ کھیل کر آپ '
          'کو ہرانے دیتا ہے۔',
      'Tanafus bertanya dari juz atau surah mana pun: lengkapi ayat, '
          'temukan kata yang hilang, sebutkan surahnya. Skormu menjadi rasi '
          'ayat-ayat yang kamu temui, dan kodemu membuat teman memainkan '
          'ronde yang sama untuk mengalahkannya.',
      'Tanafus fragt aus jedem Dschuz oder jeder Sure: Vers ergänzen, '
          'fehlendes Wort finden, Sure benennen. Deine Punkte werden zum '
          'Sternbild der Verse, denen du begegnet bist, und mit deinem Code '
          'spielt ein Freund genau dieselbe Runde, um dich zu schlagen.');

  String get obCraftLabel => _t('AND IT IS NOT HARD', 'وهو ليس صعبًا',
      'اور یہ مشکل نہیں', 'DAN INI TIDAK SULIT', 'UND ES IST NICHT SCHWER');
  String get obCraftHeadline => _t('Four taps.\nUnder a minute.',
      'أربع نقرات.\nأقل من دقيقة.', 'چار ٹیپ۔\nایک منٹ سے کم۔',
      'Empat ketukan.\nKurang dari semenit.', 'Vier Tipps.\nUnter einer Minute.');
  String get obCraftBody => _t(
      'Choose a reciter, choose your verses, choose the scenery. The '
          'reel plays back instantly in 9:16, ready for Reels, Shorts, '
          'Status and WhatsApp.',
      'اختر قارئًا، اختر آياتك، اختر المشهد. يُعرض مقطعك فورًا '
          'بمقاس 9:16، جاهزًا لريلز وشورتس والحالة وواتساب.',
      'قاری چنیں، اپنی آیات چنیں، منظر چنیں۔ ریل فوراً 9:16 میں چل پڑتی '
          'ہے — ریلز، شارٹس، سٹیٹس اور واٹس ایپ کے لیے تیار۔',
      'Pilih qari, pilih ayat Anda, pilih pemandangan. Reel langsung '
          'diputar dalam 9:16, siap untuk Reels, Shorts, Status, dan WhatsApp.',
      'Wähl einen Rezitator, wähl deine Verse, wähl die Kulisse. Das Reel '
          'läuft sofort in 9:16 — bereit für Reels, Shorts, Status und WhatsApp.');
  String get stepReciter =>
      _t('Reciter', 'القارئ', 'قاری', 'Qari', 'Rezitator');
  String get stepVerses => _t('Verses', 'الآيات', 'آیات', 'Ayat', 'Verse');
  String get stepScenery => _t('Scenery', 'المشهد', 'منظر', 'Pemandangan',
      'Kulisse');
  String get stepShare =>
      _t('Share', 'المشاركة', 'شیئرنگ', 'Berbagi', 'Teilen');

  String get obHabitLabel => _t('ONE LAST THING', 'أمر أخير',
      'ایک آخری بات', 'SATU HAL TERAKHIR', 'EINE LETZTE SACHE');
  String get obHabitHeadline => _t('Pick your daily moment',
      'اختر لحظتك اليومية', 'اپنا روزانہ کا لمحہ چنیں',
      'Pilih momen harian Anda', 'Wähl deinen täglichen Moment');
  String obHabitBodyEnabled(String time) => _t(
      'Every day at $time, one quiet reminder to send a '
          'verse out. Tap the clock to change it.',
      'كل يوم في $time، تذكير هادئ واحد لإرسال آية. '
          'انقر على الساعة لتغييره.',
      'روزانہ $time بجے، ایک آیت بھیجنے کی ایک خاموش یاد دہانی۔ '
          'بدلنے کے لیے گھڑی ٹیپ کریں۔',
      'Setiap hari pukul $time, satu pengingat tenang untuk mengirim '
          'ayat. Ketuk jamnya untuk mengubah.',
      'Täglich um $time eine stille Erinnerung, einen Vers zu senden. '
          'Tippe auf die Uhr, um sie zu ändern.');
  String get obHabitBodyDeclined => _t(
      'No reminder for now. You can set one any time in Settings.',
      'لا تذكير الآن. يمكنك ضبطه في أي وقت من الإعدادات.',
      'فی الحال کوئی یاد دہانی نہیں۔ آپ ترتیبات میں جب چاہیں مقرر کر سکتے ہیں۔',
      'Belum ada pengingat. Anda bisa mengaturnya kapan saja di Pengaturan.',
      'Vorerst keine Erinnerung. Du kannst sie jederzeit in den Einstellungen setzen.');
  String get setYourTime => _t('Set your time', 'حدد وقتك',
      'اپنا وقت مقرر کریں', 'Tentukan waktu Anda', 'Setz deine Zeit');
  String get setATime => _t('Set a time', 'حدد وقتًا', 'وقت مقرر کریں',
      'Tentukan waktu', 'Zeit festlegen');
  String get everyDay =>
      _t('every day', 'كل يوم', 'روزانہ', 'setiap hari', 'täglich');
  String get tapToSet => _t('tap to set', 'انقر للضبط', 'مقرر کرنے کو ٹیپ کریں',
      'ketuk untuk mengatur', 'zum Einstellen tippen');
  String get phoneWillAskNext => _t(
      'Your phone will ask next. One reminder a day, nothing else, ever.',
      'سيسألك هاتفك بعد قليل. تذكير واحد في اليوم، لا شيء غيره أبدًا.',
      'اب آپ کا فون پوچھے گا۔ دن میں ایک یاد دہانی، اس کے سوا کبھی کچھ نہیں۔',
      'Ponsel Anda akan bertanya berikutnya. Satu pengingat sehari, tidak lebih, selamanya.',
      'Gleich fragt dein Handy. Eine Erinnerung am Tag, sonst nie etwas.');
  String get noReminderThanks => _t('No reminder, thanks', 'لا تذكير، شكرًا',
      'یاد دہانی نہیں، شکریہ', 'Tidak perlu pengingat, terima kasih',
      'Keine Erinnerung, danke');
  String get myDailyMoment => _t('MY DAILY MOMENT', 'لحظتي اليومية',
      'میرا روزانہ کا لمحہ', 'MOMEN HARIAN SAYA', 'MEIN TÄGLICHER MOMENT');

  String get obBismillahHeadline => _t('Then let us make\nyour first one',
      'هيا نصنع\nمقطعك الأول', 'تو آئیے بنائیں\nآپ کی پہلی ریل',
      'Mari buat\nyang pertama untuk Anda', 'Dann machen wir\ndein erstes');
  String get obBismillahBody => _t(
      'Pick a verse that moved you. Someone out there is about to need it.',
      'اختر آية لامست قلبك. فثمة من سيحتاجها قريبًا.',
      'کوئی ایسی آیت چنیں جس نے آپ کو چھوا ہو۔ کہیں کوئی ہے جسے ابھی اس کی ضرورت پڑنے والی ہے۔',
      'Pilih ayat yang menyentuh Anda. Di luar sana ada yang sebentar lagi membutuhkannya.',
      'Wähl einen Vers, der dich bewegt hat. Irgendwo braucht ihn gleich jemand.');

  // ---- home: the verse card -----------------------------------------
  /// The cartouche over the verse. Not "of the day": the card turns
  /// twice a day, and the label is what the thing is, not when.
  String get verseFromTheQuran => _t('Verse from the Quran', 'آية من القرآن',
      'قرآن کی ایک آیت', 'Ayat dari Al-Qur’an', 'Vers aus dem Quran');

  // ---- the home-screen widget --------------------------------------
  /// The small door on the verse card. One word: it shares the card's
  /// first row with the cartouche.
  String get widgetPill =>
      _t('Widget', 'أداة', 'ویجٹ', 'Widget', 'Widget');

  /// The sheet that walks through adding the widget.
  String get widgetSheetTitle => _t('A verse on your home screen',
      'آية على شاشتك الرئيسية', 'آپ کی ہوم سکرین پر ایک آیت',
      'Satu ayat di layar beranda Anda', 'Ein Vers auf deinem Startbildschirm');
  String get widgetSheetBody => _t(
      'The AyahReel widget puts a verse from the Quran on your home '
          'screen — a new one every morning and afternoon, on a new '
          'scenery, without opening the app. Tap it to open the app.',
      'تعرض أداة AyahReel آية من القرآن على شاشتك الرئيسية — آية '
          'جديدة كل صباح وبعد الظهر، على خلفية جديدة، دون فتح التطبيق. '
          'انقرها لفتح التطبيق.',
      'AyahReel کا ویجٹ آپ کی ہوم سکرین پر قرآن کی ایک آیت رکھتا ہے — '
          'ہر صبح اور دوپہر ایک نئی آیت، نئے منظر پر، ایپ کھولے بغیر۔ '
          'ایپ کھولنے کے لیے اسے ٹیپ کریں۔',
      'Widget AyahReel menampilkan satu ayat Al-Qur’an di layar beranda '
          'Anda — ayat baru setiap pagi dan siang, dengan pemandangan baru, '
          'tanpa membuka aplikasi. Ketuk untuk membuka aplikasi.',
      'Das AyahReel-Widget setzt einen Vers aus dem Quran auf deinen '
          'Startbildschirm — jeden Morgen und Nachmittag einen neuen, auf '
          'einer neuen Kulisse, ohne die App zu öffnen. Tipp darauf, um die App zu öffnen.');

  /// The steps, in the order the phone asks for them. Android's
  /// launcher and iOS's home screen each have their own; the sheet
  /// shows the one for the phone it is on.
  List<String> get widgetStepsAndroid => _tl(
        const [
          'Touch and hold an empty spot on your home screen.',
          'Tap Widgets.',
          'Find AyahReel, then touch and hold the widget and drop it '
              'where you want it.',
        ],
        const [
          'اضغط مطولًا على مكان فارغ في الشاشة الرئيسية.',
          'انقر «الأدوات».',
          'ابحث عن AyahReel، ثم اضغط مطولًا على الأداة وأفلتها حيث تريد.',
        ],
        const [
          'ہوم سکرین پر کسی خالی جگہ کو دبا کر رکھیں۔',
          '«ویجٹس» پر ٹیپ کریں۔',
          'AyahReel تلاش کریں، پھر ویجٹ کو دبا کر رکھیں اور جہاں چاہیں چھوڑ دیں۔',
        ],
        const [
          'Sentuh dan tahan area kosong di layar beranda Anda.',
          'Ketuk Widget.',
          'Cari AyahReel, lalu sentuh dan tahan widgetnya dan letakkan '
              'di tempat yang Anda mau.',
        ],
        const [
          'Tippe und halte eine leere Stelle auf deinem Startbildschirm.',
          'Tippe auf Widgets.',
          'Such AyahReel, halte dann das Widget gedrückt und leg es ab, '
              'wo du es haben willst.',
        ],
      );
  List<String> get widgetStepsIos => _tl(
        const [
          'Touch and hold an empty spot on your home screen until the '
              'apps jiggle.',
          'Tap Edit, then Add Widget. (On older versions of iOS, tap '
              'the + in the corner.)',
          'Search for AyahReel, choose a size, and tap Add Widget.',
        ],
        const [
          'اضغط مطولًا على مكان فارغ في الشاشة الرئيسية حتى تهتز '
              'التطبيقات.',
          'انقر «تعديل» ثم «إضافة أداة». (في إصدارات iOS الأقدم، انقر '
              'علامة + في الزاوية.)',
          'ابحث عن AyahReel، واختر الحجم، ثم انقر «إضافة أداة».',
        ],
        const [
          'ہوم سکرین پر کسی خالی جگہ کو اُس وقت تک دبا کر رکھیں جب تک '
              'ایپس ہلنے نہ لگیں۔',
          '«ایڈٹ» پھر «ایڈ ویجٹ» ٹیپ کریں۔ (iOS کے پرانے ورژن میں کونے '
              'کا + ٹیپ کریں۔)',
          'AyahReel تلاش کریں، سائز چنیں، اور «ایڈ ویجٹ» ٹیپ کریں۔',
        ],
        const [
          'Sentuh dan tahan area kosong di layar beranda sampai '
              'aplikasinya bergoyang.',
          'Ketuk Edit, lalu Tambah Widget. (Pada iOS versi lama, ketuk '
              'tanda + di sudut.)',
          'Cari AyahReel, pilih ukuran, lalu ketuk Tambah Widget.',
        ],
        const [
          'Tippe und halte eine leere Stelle auf dem Startbildschirm, '
              'bis die Apps wackeln.',
          'Tippe auf Bearbeiten, dann Widget hinzufügen. (In älteren '
              'iOS-Versionen auf das + in der Ecke tippen.)',
          'Such AyahReel, wähl eine Größe und tippe auf Widget hinzufügen.',
        ],
      );

  /// Android only: the launcher can be asked to place it directly.
  String get widgetAddNow => _t('Add it now', 'أضِفها الآن', 'ابھی شامل کریں',
      'Tambahkan sekarang', 'Jetzt hinzufügen');

  /// The steps' heading, under the body.
  String get widgetHowToAdd => _t('How to add it', 'كيف تضيفها',
      'اسے کیسے شامل کریں', 'Cara menambahkannya', 'So fügst du es hinzu');

  /// Under the steps, once the widget is already on the home screen.
  String get widgetAlreadyAdded => _t(
      'The widget is already on your home screen.',
      'الأداة على شاشتك الرئيسية بالفعل.',
      'ویجٹ پہلے ہی آپ کی ہوم سکرین پر ہے۔',
      'Widget sudah ada di layar beranda Anda.',
      'Das Widget ist schon auf deinem Startbildschirm.');

  /// Settings: the row that opens the sheet.
  String get sectionHomeScreen => _t('HOME SCREEN', 'الشاشة الرئيسية',
      'ہوم سکرین', 'LAYAR BERANDA', 'STARTBILDSCHIRM');
  String get widgetRowTitle => _t('Verse widget', 'أداة الآية', 'آیت ویجٹ',
      'Widget ayat', 'Vers-Widget');
  String get widgetRowSubtitle => _t(
      'A verse from the Quran on your home screen, twice a day.',
      'آية من القرآن على شاشتك الرئيسية، مرتين في اليوم.',
      'دن میں دو بار، آپ کی ہوم سکرین پر قرآن کی ایک آیت۔',
      'Satu ayat Al-Qur’an di layar beranda Anda, dua kali sehari.',
      'Ein Vers aus dem Quran auf deinem Startbildschirm, zweimal am Tag.');
  String get widgetRowInstalledSubtitle => _t(
      'On your home screen. Tap for the steps to add another.',
      'على شاشتك الرئيسية. انقر لخطوات إضافة أخرى.',
      'آپ کی ہوم سکرین پر ہے۔ ایک اور شامل کرنے کے مراحل کے لیے ٹیپ کریں۔',
      'Ada di layar beranda Anda. Ketuk untuk langkah menambah satu lagi.',
      'Auf deinem Startbildschirm. Tipp für die Schritte, ein weiteres hinzuzufügen.');

  /// The home-tab nudge, back every other day until the widget is
  /// actually there.
  String get widgetNudgeTitle => _t('Put a verse on your home screen',
      'ضع آية على شاشتك الرئيسية', 'اپنی ہوم سکرین پر ایک آیت رکھیں',
      'Taruh satu ayat di layar beranda Anda',
      'Setz einen Vers auf deinen Startbildschirm');
  String get widgetNudgeBody => _t(
      'A new verse every morning and afternoon, on a new scenery, '
          'without opening the app.',
      'آية جديدة كل صباح وبعد الظهر، على خلفية جديدة، دون فتح التطبيق.',
      'ہر صبح اور دوپہر ایک نئی آیت، نئے منظر پر، ایپ کھولے بغیر۔',
      'Ayat baru setiap pagi dan siang, dengan pemandangan baru, '
          'tanpa membuka aplikasi.',
      'Jeden Morgen und Nachmittag ein neuer Vers, auf einer neuen '
          'Kulisse, ohne die App zu öffnen.');
  String get widgetShowMeHow => _t('Show me how', 'أرِني كيف',
      'مجھے دکھائیں کیسے', 'Tunjukkan caranya', 'Zeig mir wie');

  /// Friday's label, and the only day the card changes its dress. It
  /// says which day it is and nothing more: a greeting the app hands
  /// out on the user's behalf is a wish nobody asked it to make.
  String get jumuahToday => _t('It’s Jumu’ah', 'اليوم الجمعة',
      'آج جمعہ ہے', 'Hari ini Jumat', 'Heute ist Dschumu’a');

  /// What the verse is, and only that — where it is read is a claim
  /// about the khutbah that is not ours to make.
  String get jumuahCardBody => _t('The verse of Salawat',
      'آية الصلاة على النبي ﷺ', 'درود کی آیت', 'Ayat salawat',
      'Der Vers des Salawat');

  /// The one door on the Friday card. Short: it shares the card's
  /// first row with the label.
  String get makeSalawatReel => _t('Make the video', 'اصنع الفيديو',
      'ویڈیو بنائیں', 'Buat videonya', 'Video machen');
  String get makeThisVerse => _t('Make this verse', 'اصنع مقطع هذه الآية',
      'اس آیت کی ریل بنائیں', 'Buat ayat ini', 'Diesen Vers machen');

  /// 'Ar-Ra’d · 28' — the caption under a daily verse.
  String verseReference(String surahName, int start, int end) {
    final name = localizedSurahName(surahName);
    final range = end == start ? '$start' : '$start–$end';
    return '$name · $range';
  }

  // ---- counted ------------------------------------------------------

  String reelsCount(int n) => switch (lang) {
        AppLang.en => n == 1 ? '1 reel' : '$n reels',
        AppLang.ar => n == 1
            ? 'مقطع واحد'
            : n == 2
                ? 'مقطعان'
                : n <= 10
                    ? '$n مقاطع'
                    : '$n مقطعًا',
        AppLang.ur => n == 1 ? 'ایک ریل' : '$n ریلز',
        AppLang.id => '$n reel',
        AppLang.de => n == 1 ? '1 Reel' : '$n Reels',
      };

  /// Rounds of the quiz, counted: the share notification's "5 rounds".
  String roundsCount(int n) => switch (lang) {
        AppLang.en => n == 1 ? '1 round' : '$n rounds',
        AppLang.ar => n == 1
            ? 'جولة واحدة'
            : n == 2
                ? 'جولتين'
                : n <= 10
                    ? '$n جولات'
                    : '$n جولة',
        AppLang.ur => n == 1 ? 'ایک راؤنڈ' : '$n راؤنڈ',
        AppLang.id => '$n ronde',
        AppLang.de => n == 1 ? '1 Runde' : '$n Runden',
      };

  /// Every tenth reel: the "Your verses" card, offered.
  String versesMilestoneTitle(int n) => _t(
      '${reelsCount(n)} of the Quran',
      '${reelsCount(n)} من القرآن',
      'قرآن کی ${reelsCount(n)}',
      '${reelsCount(n)} dari Al-Qur’an',
      '${reelsCount(n)} aus dem Koran');
  String get versesMilestoneBody => _t(
      'Every verse you’ve made shines on your card. Share it with someone '
          'you love.',
      'كل آية صنعتها تضيء على بطاقتك. شاركها مع من تحب.',
      'آپ کی بنائی ہر آیت آپ کے کارڈ پر چمکتی ہے۔ اسے کسی پیارے کے ساتھ شیئر کریں۔',
      'Setiap ayat yang kamu buat bersinar di kartumu. Bagikan kepada orang '
          'tersayang.',
      'Jeder Vers, den du gemacht hast, leuchtet auf deiner Karte. Teile sie '
          'mit jemandem, den du liebst.');
  String get versesMilestoneCta => _t('See my card', 'اعرض بطاقتي',
      'میرا کارڈ دیکھیں', 'Lihat kartuku', 'Meine Karte ansehen');

  String get whichSurah => _t('Which surah?', 'أي سورة؟', 'کون سی سورت؟',
      'Surah yang mana?', 'Welche Sure?');

  String get doneLabel =>
      _t('Done', 'تم', 'ہو گیا', 'Selesai', 'Fertig');

  // ---- scenery: matched to the verses ------------------------------
  /// The pill at the head of the scenery rail. Short: it shares a row
  /// with the tabs and must not push the first few off the screen.
  String get matchScenesToVerses => _t('Match', 'حسب الآيات', 'موافق',
      'Cocokkan', 'Passend');
  String get matchingScenes => _t('Choosing sceneries…', 'نختار المشاهد…',
      'مناظر چنے جا رہے ہیں…', 'Memilih pemandangan…', 'Kulissen werden gewählt …');
  String scenesMatched(int n) => _t(
      '$n ${n == 1 ? 'scenery' : 'sceneries'} chosen from the verses',
      'اختيرت ${_scenesN(n)} من كلمات الآيات',
      'آیات کے الفاظ سے $n مناظر چنے گئے',
      '$n pemandangan dipilih dari ayat-ayatnya',
      '$n ${n == 1 ? 'Kulisse' : 'Kulissen'} aus den Versen gewählt');
  String _scenesN(int n) {
    if (n == 1) return 'مشهد واحد';
    if (n == 2) return 'مشهدان';
    if (n <= 10) return '$n مشاهد';
    return '$n مشهدًا';
  }

  String get matchedNothing => _t(
      'The sceneries could not be fetched. Check your connection.',
      'تعذّر تنزيل المشاهد. تحقّق من اتصالك.',
      'مناظر نہیں لائے جا سکے۔ اپنا کنکشن دیکھیں۔',
      'Pemandangan tidak dapat diambil. Periksa koneksi Anda.',
      'Die Kulissen ließen sich nicht holen. Prüf deine Verbindung.');

  /// A motif the matcher chose by, for the line that says why.
  String motifName(String id) => _motifs[lang]![id] ?? id;

  static const _motifs = <AppLang, Map<String, String>>{
    AppLang.en: {
      'night': 'night', 'sky': 'sky', 'clouds': 'clouds', 'rain': 'rain',
      'sea': 'sea', 'water': 'water', 'snow': 'snow', 'mountain': 'mountains',
      'desert': 'desert', 'garden': 'garden', 'land': 'land', 'road': 'path',
      'sacred': 'sacred', 'light': 'light', 'fire': 'fire', 'fallback': 'sky',
    },
    AppLang.ar: {
      'night': 'ليل', 'sky': 'سماء', 'clouds': 'سحاب', 'rain': 'مطر',
      'sea': 'بحر', 'water': 'ماء', 'snow': 'ثلج', 'mountain': 'جبال',
      'desert': 'صحراء', 'garden': 'جنة', 'land': 'أرض', 'road': 'طريق',
      'sacred': 'مشهد إسلامي', 'light': 'نور', 'fire': 'نار', 'fallback': 'سماء',
    },
    AppLang.ur: {
      'night': 'رات', 'sky': 'آسمان', 'clouds': 'بادل', 'rain': 'بارش',
      'sea': 'سمندر', 'water': 'پانی', 'snow': 'برف', 'mountain': 'پہاڑ',
      'desert': 'صحرا', 'garden': 'باغ', 'land': 'زمین', 'road': 'راستہ',
      'sacred': 'مقدس', 'light': 'نور', 'fire': 'آگ', 'fallback': 'آسمان',
    },
    AppLang.id: {
      'night': 'malam', 'sky': 'langit', 'clouds': 'awan', 'rain': 'hujan',
      'sea': 'laut', 'water': 'air', 'snow': 'salju', 'mountain': 'gunung',
      'desert': 'gurun', 'garden': 'taman', 'land': 'bumi', 'road': 'jalan',
      'sacred': 'suci', 'light': 'cahaya', 'fire': 'api', 'fallback': 'langit',
    },
    AppLang.de: {
      'night': 'Nacht', 'sky': 'Himmel', 'clouds': 'Wolken', 'rain': 'Regen',
      'sea': 'Meer', 'water': 'Wasser', 'snow': 'Schnee', 'mountain': 'Berge',
      'desert': 'Wüste', 'garden': 'Garten', 'land': 'Land', 'road': 'Weg',
      'sacred': 'heilig', 'light': 'Licht', 'fire': 'Feuer', 'fallback': 'Himmel',
    },
  };

  // ---- edit again ---------------------------------------------------
  String get editAgain => _t('Edit again', 'عدّل مجددًا', 'دوبارہ ترمیم',
      'Edit lagi', 'Nochmal bearbeiten');
  String get reopeningReel => _t('Opening your reel…', 'نفتح مقطعك…',
      'آپ کی ریل کھولی جا رہی ہے…', 'Membuka reel Anda…',
      'Dein Reel wird geöffnet …');
  String get reopenFetchingScenes => _t('Fetching the sceneries…',
      'نجلب المشاهد…', 'مناظر لائے جا رہے ہیں…', 'Mengambil pemandangan…',
      'Kulissen werden geholt …');
  String get reopenFailed => _t(
      'Couldn’t open this reel for editing.',
      'تعذّر فتح هذا المقطع للتعديل.',
      'یہ ریل ترمیم کے لیے نہیں کھل سکی۔',
      'Reel ini tidak dapat dibuka untuk diedit.',
      'Dieses Reel ließ sich nicht zum Bearbeiten öffnen.');
  String get reelNotEditable => _t(
      'This reel was made before editing was possible.',
      'صُنع هذا المقطع قبل أن يصبح التعديل ممكنًا.',
      'یہ ریل اُس وقت بنی تھی جب ترمیم ممکن نہ تھی۔',
      'Reel ini dibuat sebelum pengeditan tersedia.',
      'Dieses Reel entstand, bevor Bearbeiten möglich war.');

  // ---- accessibility ----------------------------------------------
  // What a screen reader says for the controls that have no words of
  // their own — a painted tile, a pill, a drag — and the hints that say
  // what a double tap will do. Read aloud, never shown, so these can
  // be a shade longer than a label the eye has to take in at once.

  /// The mark on a tab or row a new install is being pointed at.
  String get a11yNew => _t('New', 'جديد', 'نیا', 'Baru', 'Neu');

  /// The wizard's progress dots.
  String a11yStep(int step, int total) => _t(
      'Step $step of $total',
      'الخطوة $step من $total',
      '$total میں سے مرحلہ $step',
      'Langkah $step dari $total',
      'Schritt $step von $total');

  /// Onboarding's page dots.
  String a11yPageOf(int page, int total) => _t(
      'Page $page of $total',
      'الصفحة $page من $total',
      '$total میں سے صفحہ $page',
      'Halaman $page dari $total',
      'Seite $page von $total');

  /// A button that is working on what it was asked for.
  String a11yBusy(String label) => _t(
      '$label, please wait',
      '$label، انتظر قليلًا',
      '$label، ذرا انتظار کریں',
      '$label, mohon tunggu',
      '$label, bitte warten');

  /// The streak cartouche on the home tab.
  String a11yRewards(int streak, int points, int badges) {
    final parts = <String>[
      if (streak > 0)
        _t('$streak-day streak', 'مواظبة $streak أيام', '$streak دن کا تسلسل',
            'rentetan $streak hari', '$streak-Tage-Serie'),
      _t('$points points', '$points نقاط', '$points پوائنٹس', '$points poin',
          '$points Punkte'),
      if (badges > 0)
        _t('$badges badges', '$badges أوسمة', '$badges اعزازات',
            '$badges lencana', '$badges Abzeichen'),
    ];
    final lead = _t('Your rewards: ', 'مكافآتك: ', 'آپ کے انعامات: ',
        'Imbalan Anda: ', 'Deine Belohnungen: ');
    return lead + parts.join('$comma ');
  }

  String get a11yOpensBadges => _t('Opens your badges', 'يفتح أوسمتك',
      'آپ کے اعزازات کھولتا ہے', 'Membuka lencana Anda',
      'Öffnet deine Abzeichen');

  /// A reel card, on the home rail or in My Reels.
  String a11yReel(String surahName, String reciterName, String date) => _t(
      'Reel: $surahName, $reciterName, $date',
      'مقطع: ${localizedSurahName(surahName)}، '
          '${localizedReciterName(reciterName)}، $date',
      'ریل: ${localizedSurahName(surahName)}، '
          '${localizedReciterName(reciterName)}، $date',
      'Reel: $surahName, $reciterName, $date',
      'Reel: $surahName, $reciterName, $date');
  String get a11yPlaysReel => _t('Plays the reel', 'يشغّل المقطع',
      'ریل چلاتا ہے', 'Memutar reel', 'Spielt das Reel ab');
  String get a11yReelOptions => _t('Reel options', 'خيارات المقطع',
      'ریل کے اختیارات', 'Opsi reel', 'Reel-Optionen');

  /// The verse card: what it is, then the verse, then its meaning. The
  /// translation is only spoken where it is shown — in Arabic the card
  /// carries the verse alone.
  String a11yVerseCard(String reference, String arabic, String translation) =>
      _t(
          '$verseFromTheQuran, $reference. $arabic. $translation',
          '$verseFromTheQuran، $reference. $arabic',
          '$verseFromTheQuran، $reference۔ $arabic۔ $translation',
          '$verseFromTheQuran, $reference. $arabic. $translation',
          '$verseFromTheQuran, $reference. $arabic. $translation');
  String get a11yMakesVerseReel => _t(
      'Makes a video of this verse',
      'يصنع فيديو لهذه الآية',
      'اس آیت کی ویڈیو بناتا ہے',
      'Membuat video dari ayat ini',
      'Macht ein Video aus diesem Vers');

  String get a11yChangesReminderTime => _t(
      'Changes the reminder time',
      'يغيّر وقت التذكير',
      'یاد دہانی کا وقت بدلتا ہے',
      'Mengubah waktu pengingat',
      'Ändert die Erinnerungszeit');
  String get a11ySetsLanguage => _t('Sets the app language', 'يضبط لغة التطبيق',
      'ایپ کی زبان مقرر کرتا ہے', 'Mengatur bahasa aplikasi',
      'Stellt die App-Sprache ein');

  /// The row that chooses the translation printed under a verse.
  String get a11ySetsTranslation => _t(
      'Sets the verse translation',
      'يضبط ترجمة الآيات',
      'آیات کا ترجمہ مقرر کرتا ہے',
      'Mengatur terjemahan ayat',
      'Stellt die Versübersetzung ein');
  String get a11yPicksVoice => _t(
      'Selects this voice and plays a sample',
      'يختار هذا الصوت ويشغّل عيّنة',
      'یہ آواز منتخب کر کے نمونہ چلاتا ہے',
      'Memilih suara ini dan memutar contoh',
      'Wählt diese Stimme und spielt eine Probe');
  String get a11yChoosesFile => _t('Opens the file picker', 'يفتح اختيار الملفات',
      'فائل چننے والا کھولتا ہے', 'Membuka pemilih berkas',
      'Öffnet die Dateiauswahl');
  String get a11yOpensSurahPicker => _t('Opens the surah picker',
      'يفتح قائمة السور', 'سورتوں کی فہرست کھولتا ہے', 'Membuka pemilih surah',
      'Öffnet die Surenauswahl');
  String get a11yOpensVoicePicker => _t('Opens the voice picker',
      'يفتح قائمة القرّاء', 'قاریوں کی فہرست کھولتا ہے', 'Membuka pemilih suara',
      'Öffnet die Stimmenauswahl');
  String get a11yVerseTileHint => _t(
      'Double tap to choose. Double tap and hold to stretch the selection to it.',
      'انقر مرتين للاختيار. انقر مرتين مع الاستمرار لمدّ الاختيار إليها.',
      'چننے کے لیے دو بار ٹیپ کریں۔ انتخاب کو یہاں تک پھیلانے کے لیے دو بار ٹیپ کر کے دبائے رکھیں۔',
      'Ketuk dua kali untuk memilih. Ketuk dua kali dan tahan untuk merentangkan pilihan sampai ke sini.',
      'Zweimal tippen zum Auswählen. Zweimal tippen und halten, um die Auswahl bis hierher zu ziehen.');

  /// The number on a verse in the picker, which plays it.
  String a11yListenFrom(int n) => _t('Listen from ayah $n',
      'استمع من الآية $n', 'آیت $n سے سنیں', 'Dengarkan dari ayat $n',
      'Ab Vers $n anhören');

  /// The run's name under the verse list, which scrolls back to it.
  String get a11yShowsChosenVerses => _t('Shows them in the list',
      'يعرضها في القائمة', 'انہیں فہرست میں دکھاتا ہے',
      'Menampilkannya di daftar', 'Zeigt sie in der Liste');

  // Scenery.
  String get a11yMatchesScenes => _t(
      'Picks a scenery for each verse',
      'يختار مشهدًا لكل آية',
      'ہر آیت کے لیے منظر چنتا ہے',
      'Memilih pemandangan untuk tiap ayat',
      'Wählt für jeden Vers eine Kulisse');
  String get a11yMultiSceneHint => _t(
      'Lets the reel run through several sceneries',
      'يجعل المقطع يمرّ على عدة مشاهد',
      'ریل کو کئی مناظر سے گزرنے دیتا ہے',
      'Membuat reel melewati beberapa pemandangan',
      'Lässt das Reel durch mehrere Kulissen laufen');
  String get a11yVideo => _t('video', 'فيديو', 'ویڈیو', 'video', 'Video');
  String get a11yNeedsDownload => _t('needs download', 'يتطلب تنزيلًا',
      'ڈاؤن لوڈ درکار', 'perlu diunduh', 'muss geladen werden');
  String a11yDownloading(int pct) => _t(
      'downloading $pct%',
      'جارٍ التنزيل $pct%',
      'ڈاؤن لوڈ ہو رہا ہے $pct%',
      'mengunduh $pct%',
      'lädt $pct %');
  String a11ySceneOrder(int n) => _t(
      'scene $n in the run',
      'المشهد $n في التسلسل',
      'ترتیب میں منظر $n',
      'adegan $n dalam urutan',
      'Szene $n im Ablauf');
  String get a11yOpensGallery => _t('Opens your gallery', 'يفتح معرض الصور',
      'آپ کی گیلری کھولتا ہے', 'Membuka galeri Anda', 'Öffnet deine Galerie');

  /// A scenery's spoken name: the category the tile belongs to, in
  /// the app's language, with the tile's own number after it.
  String sceneName(String id, String label) {
    final table = _sceneCategories[lang];
    if (table == null) return label;
    for (final key in _sceneCategoriesByLength) {
      if (!id.startsWith('${key}_')) continue;
      final n = RegExp(r'\d+$').firstMatch(label)?.group(0);
      final word = table[key]!;
      return n == null ? word : '$word $n';
    }
    return label;
  }

  /// 'Sky, 3 of 40': one tile among the many of its tab that share
  /// its name.
  String a11yNthOf(String name, int n, int of) => _t(
      '$name, $n of $of',
      '$name، $n من $of',
      '$name، $of میں سے $n',
      '$name, $n dari $of',
      '$name, $n von $of');

  /// The check at the end of the widget row, once it is placed.
  String get a11yWidgetPlaced => _t('on your home screen',
      'على شاشتك الرئيسية', 'آپ کی ہوم سکرین پر', 'di layar beranda Anda',
      'auf deinem Startbildschirm');

  /// Names for the handful of colours the app offers.
  String colourName(int argb) => switch (argb & 0xFFFFFF) {
        0xEEC96B => _t('gold', 'ذهبي', 'سنہری', 'emas', 'Gold'),
        // The rest of the verse palette. Every swatch the style step
        // offers is named: a reader told only "colour" twenty-four
        // times has been handed a grid it cannot use.
        0xD4A947 => _t('deep gold', 'ذهبي داكن', 'گہرا سنہری', 'emas tua',
            'Dunkelgold'),
        0xEADFC8 => _t('sand', 'رملي', 'ریتلا', 'pasir', 'Sand'),
        0xD7DEE6 => _t('mist', 'ضبابي', 'دھندلا', 'kabut', 'Nebelgrau'),
        0xA9B2BD => _t('stone', 'حجري', 'پتھری', 'batu', 'Steingrau'),
        0x5C6673 => _t('slate', 'أردوازي', 'سلیٹی', 'batu tulis',
            'Schiefer'),
        0xE8A33D => _t('amber', 'كهرماني', 'عنبری', 'ambar', 'Bernstein'),
        0xD07C4A =>
          _t('copper', 'نحاسي', 'تانبے کا', 'tembaga', 'Kupfer'),
        0xC96A5A => _t('terracotta', 'طيني', 'اینٹ رنگ', 'terakota',
            'Terrakotta'),
        0xF3C9C2 => _t('blush', 'زهري فاتح', 'ہلکا گلابی', 'merona',
            'Zartrosa'),
        0xB98AB5 => _t('plum', 'برقوقي', 'آلوبخاری', 'plum', 'Pflaume'),
        0x5FBF9B => _t('jade', 'يشمي', 'یشب سبز', 'giok', 'Jade'),
        0x5BC0C6 => _t('teal', 'أزرق مخضر', 'نیلگوں سبز', 'toska',
            'Petrol'),
        0x6FA8E8 => _t('azure', 'لازوردي', 'نیلگوں', 'biru azur', 'Azur'),
        0xA9A7F0 => _t('periwinkle', 'بنفسجي مزرق', 'نیلا جامنی',
            'biru lavender', 'Blauviolett'),
        0xBFD4B4 => _t('sage', 'مريمي', 'زیتونی سبز', 'sage', 'Salbeigrün'),
        0x9FE8C9 => _t('mint', 'نعناعي', 'پودینہ سبز', 'mint', 'Mintgrün'),
        0x9CC7F5 => _t('sky blue', 'سماوي', 'آسمانی', 'biru langit',
            'Himmelblau'),
        0xF5A8B8 => _t('rose', 'وردي', 'گلابی', 'merah muda', 'Rosé'),
        0xC9B8F5 =>
          _t('lavender', 'بنفسجي فاتح', 'ہلکا جامنی', 'lavender', 'Lavendel'),
        0xFFFFFF => _t('white', 'أبيض', 'سفید', 'putih', 'Weiß'),
        0x15181C || 0x14181D =>
          _t('charcoal', 'فحمي', 'کوئلہ سیاہ', 'arang', 'Anthrazit'),
        0x000000 => _t('black', 'أسود', 'سیاہ', 'hitam', 'Schwarz'),
        0xF3EADA => _t('ivory', 'عاجي', 'عاجی', 'gading', 'Elfenbein'),
        0x0E2A22 => _t('deep green', 'أخضر داكن', 'گہرا سبز', 'hijau tua',
            'Dunkelgrün'),
        0x101A2E => _t('night blue', 'أزرق ليلي', 'شبی نیلا', 'biru malam',
            'Nachtblau'),
        _ => _t('colour', 'لون', 'رنگ', 'warna', 'Farbe'),
      };
  /// Names for the luminous inks. Shown under each one in the picker,
  /// so unlike the flat colours these are read by everybody, not only
  /// by a screen reader.
  String inkName(VerseInk ink) => switch (ink) {
        VerseInk.none => _t('plain', 'عادي', 'سادہ', 'polos', 'Schlicht'),
        VerseInk.iris => _t('Iris', 'قزحي', 'دھنک', 'Pelangi', 'Iris'),
        VerseInk.ember => _t('Ember', 'جمر', 'انگارہ', 'Bara', 'Glut'),
        VerseInk.aurora =>
          _t('Aurora', 'شفق قطبي', 'قطبی روشنی', 'Aurora', 'Polarlicht'),
        VerseInk.gilded =>
          _t('Gilded', 'مُذهَّب', 'طلائی', 'Sepuh emas', 'Vergoldet'),
        VerseInk.starlight => _t('Starlight', 'ضوء النجوم', 'ستاروں کی روشنی',
            'Cahaya bintang', 'Sternenlicht'),
        VerseInk.moonlight => _t('Moonlight', 'ضوء القمر', 'چاندنی',
            'Cahaya bulan', 'Mondlicht'),
        VerseInk.nebula =>
          _t('Nebula', 'سديم', 'سحابیہ', 'Nebula', 'Sternennebel'),
        VerseInk.sunset =>
          _t('Sunset', 'غروب', 'شفق', 'Senja', 'Abendrot'),
        VerseInk.dawn => _t('Dawn', 'فجر', 'سحر', 'Fajar', 'Morgenrot'),
        VerseInk.roseGold => _t('Rose gold', 'ذهب وردي', 'گلابی سونا',
            'Emas mawar', 'Roségold'),
        VerseInk.carnelian =>
          _t('Carnelian', 'عقيق', 'عقیق', 'Akik', 'Karneol'),
        VerseInk.pearl => _t('Pearl', 'لؤلؤ', 'موتی', 'Mutiara', 'Perlmutt'),
        VerseInk.amethyst =>
          _t('Amethyst', 'جَمَشْت', 'جامنی نگینہ', 'Kecubung', 'Amethyst'),
        VerseInk.sapphire =>
          _t('Sapphire', 'ياقوت أزرق', 'نیلم', 'Safir', 'Saphir'),
        VerseInk.frost =>
          _t('Frost', 'صقيع', 'کہر', 'Embun beku', 'Raureif'),
        VerseInk.seaGlass => _t('Sea glass', 'زجاج البحر', 'سمندری شیشہ',
            'Kaca laut', 'Meerglas'),
        VerseInk.emerald =>
          _t('Emerald', 'زمرد', 'زمرد', 'Zamrud', 'Smaragd'),
        VerseInk.firefly => _t('Firefly', 'يراعة', 'جگنو', 'Kunang-kunang',
            'Glühwürmchen'),
        VerseInk.neon => _t('Neon', 'نيون', 'نیون', 'Neon', 'Neon'),
        VerseInk.obsidian => _t('Obsidian', 'زجاج بركاني', 'سنگِ سیاہ',
            'Obsidian', 'Obsidian'),
        VerseInk.henna => _t('Henna', 'حنّاء', 'مہندی', 'Inai', 'Henna'),
        VerseInk.deepSea => _t('Deep sea', 'أعماق البحر', 'گہرا سمندر',
            'Laut dalam', 'Tiefsee'),
      };
  String a11yInkSwatch(VerseInk ink) => _t(
      '${inkName(ink)}, glowing colour',
      '${inkName(ink)}، لون متوهج',
      '${inkName(ink)}، چمکتا رنگ',
      '${inkName(ink)}, warna bercahaya',
      '${inkName(ink)}, leuchtende Farbe');

  String a11yColourSwatch(int argb) => _t(
      '${colourName(argb)} colour',
      'لون: ${colourName(argb)}',
      'رنگ: ${colourName(argb)}',
      'warna ${colourName(argb)}',
      'Farbe ${colourName(argb)}');

  // Preview.
  String get a11yReelPreview => _t('Reel preview', 'معاينة المقطع',
      'ریل کا پیش منظر', 'Pratinjau reel', 'Reel-Vorschau');
  String a11yVersePosition(int pct) => _t(
      'Verse $pct% of the way down the frame',
      'موضع الآية $pct% من أعلى الإطار',
      'آیت فریم میں اوپر سے $pct% پر',
      'Ayat $pct% dari atas bingkai',
      'Vers $pct % von oben im Rahmen');
  /// Make it yours: the two buttons beside the frame that move the verse.
  String get verseUp => _t('Move the verse up', 'حرّك الآية لأعلى',
      'آیت اوپر کریں', 'Geser ayat ke atas', 'Vers nach oben');
  String get verseDown => _t('Move the verse down', 'حرّك الآية لأسفل',
      'آیت نیچے کریں', 'Geser ayat ke bawah', 'Vers nach unten');
  String get a11yVersePositionHint => _t(
      'Adjust to move the verse up or down',
      'اضبط لتحريك الآية لأعلى أو لأسفل',
      'آیت اوپر یا نیچے کرنے کے لیے ایڈجسٹ کریں',
      'Sesuaikan untuk menggeser ayat naik atau turun',
      'Verstellen, um den Vers nach oben oder unten zu schieben');
  String get a11ySceneControlsHint => _t(
      'Shows the scene controls',
      'يعرض عناصر التحكم بالمشاهد',
      'مناظر کے کنٹرول دکھاتا ہے',
      'Menampilkan kontrol adegan',
      'Zeigt die Szenensteuerung');
  String a11ySceneSegment(int n, int weight, bool playing) => _t(
      'Scene $n, $weight× room${playing ? ', playing now' : ''}',
      'المشهد $n، مساحة $weight×${playing ? '، يُعرض الآن' : ''}',
      'منظر $n، $weight× جگہ${playing ? '، ابھی چل رہا ہے' : ''}',
      'Adegan $n, ruang $weight×${playing ? ', sedang diputar' : ''}',
      'Szene $n, $weight× Raum${playing ? ', läuft gerade' : ''}');
  String get a11yReelLength => _t('Reel length', 'مدة المقطع', 'ریل کی مدت',
      'Durasi reel', 'Reel-Länge');
  String get a11yTextSize => _t('Verse text size', 'حجم نص الآية',
      'آیت کے متن کا سائز', 'Ukuran teks ayat', 'Schriftgröße des Verses');
  String get a11yExporting => _t('Exporting the reel', 'جارٍ تصدير المقطع',
      'ریل برآمد ہو رہی ہے', 'Mengekspor reel', 'Reel wird exportiert');

  // Timing an upload.
  String get a11yRecordingTimeline => _t('Recording timeline',
      'الخط الزمني للتسجيل', 'ریکارڈنگ کی ٹائم لائن', 'Lini masa rekaman',
      'Zeitleiste der Aufnahme');
  String get a11yRecordingTimelineHint => _t(
      'Adjust to move through the recording',
      'اضبط للتنقل في التسجيل',
      'ریکارڈنگ میں آگے پیچھے جانے کے لیے ایڈجسٹ کریں',
      'Sesuaikan untuk bergerak dalam rekaman',
      'Verstellen, um durch die Aufnahme zu gehen');
  String get a11yBackFive => _t('Back 5 seconds', 'رجوع 5 ثوانٍ',
      '5 سیکنڈ پیچھے', 'Mundur 5 detik', '5 Sekunden zurück');
  String get a11yQuarterEarlier => _t('A quarter second earlier',
      'ربع ثانية أبكر', 'پاؤ سیکنڈ پہلے', 'Seperempat detik lebih awal',
      'Eine Viertelsekunde früher');
  String get a11yQuarterLater => _t('A quarter second later',
      'ربع ثانية لاحقًا', 'پاؤ سیکنڈ بعد', 'Seperempat detik lebih lambat',
      'Eine Viertelsekunde später');
  String get a11yPlaysFromVerse => _t(
      'Plays from the start of this verse',
      'يشغّل من بداية هذه الآية',
      'اس آیت کے آغاز سے چلاتا ہے',
      'Memutar dari awal ayat ini',
      'Spielt ab dem Anfang dieses Verses');
  String get a11yMarksVerseStart => _t(
      'Marks the verse start where playback is',
      'يعلّم بداية الآية عند موضع التشغيل',
      'جہاں پلے بیک ہے وہاں آیت کا آغاز نشان زد کرتا ہے',
      'Menandai awal ayat di posisi pemutaran',
      'Markiert den Versanfang an der Abspielstelle');

  // The player.
  String get a11yPlaybackPosition => _t('Playback position', 'موضع التشغيل',
      'پلے بیک کی جگہ', 'Posisi pemutaran', 'Abspielposition');
  String get a11yLoadingReel => _t('Loading the reel', 'جارٍ تحميل المقطع',
      'ریل لوڈ ہو رہی ہے', 'Memuat reel', 'Reel wird geladen');

  // Sheets.
  String get a11yWidgetPreview => _t(
      'Preview of the home-screen widget',
      'معاينة أداة الشاشة الرئيسية',
      'ہوم سکرین ویجٹ کا پیش منظر',
      'Pratinjau widget layar beranda',
      'Vorschau des Startbildschirm-Widgets');
  String get a11yEarned =>
      _t('earned', 'مُكتسب', 'حاصل شدہ', 'diraih', 'verdient');
  String a11yClearItem(String what) => _t('Clear $what', 'مسح $what',
      '$what صاف کریں', 'Bersihkan $what', '$what leeren');
  String get a11yCopiesTags => _t(
      'Copies this block to the clipboard',
      'ينسخ هذه المجموعة إلى الحافظة',
      'یہ مجموعہ کلپ بورڈ پر کاپی کرتا ہے',
      'Menyalin blok ini ke papan klip',
      'Kopiert diesen Block in die Zwischenablage');
  String get a11yOpensHashtags => _t(
      'Opens the hashtags for your post',
      'يفتح وسوم المنشور',
      'آپ کی پوسٹ کے ہیش ٹیگ کھولتا ہے',
      'Membuka tagar untuk unggahan Anda',
      'Öffnet die Hashtags für deinen Beitrag');

  // ---- data lookups -----------------------------------------------

  /// True where surah and reciter names are shown in Arabic script.
  ///
  /// Arabic and Urdu both read the names in their original script, and
  /// both would show a Latin transliteration as a foreign body in an
  /// otherwise right-to-left screen. This is also what the trailing
  /// Arabic name on a picker row keys off: where the main label is
  /// already the Arabic name, repeating it would just echo the row.
  bool get usesArabicNames => arabicScript;

  /// Display name of a surah: the English name, or 'سورة …' where the
  /// names are read in Arabic script.
  String surahTitle(SurahInfo info) => switch (lang) {
        AppLang.ar => 'سورة ${info.nameArabic}',
        AppLang.ur => 'سورۃ ${info.nameArabic}',
        _ => info.nameEnglish,
      };

  /// Localizes a surah name stored in English (saved reels keep the
  /// English name on disk so the library is stable across language
  /// switches). Falls back to the stored string.
  String localizedSurahName(String english) {
    if (!usesArabicNames) return english;
    for (final s in surahIndex) {
      if (s.nameEnglish == english) return s.nameArabic;
    }
    return english;
  }

  /// Display name of a reciter. The Arabic names ship with the data —
  /// except for an upload, which has no name of its own and is called
  /// what it is.
  String reciterName(Reciter r) => r.isUserAudio
      ? yourRecitation
      : (usesArabicNames ? r.arabicName : r.name);

  /// Localizes a reciter name stored in English. Falls back unchanged.
  String localizedReciterName(String english) {
    if (!usesArabicNames) return english;
    if (english == en.yourRecitation) return yourRecitation;
    for (final r in reciters) {
      if (r.name == english) return r.arabicName;
    }
    return english;
  }

  /// The line under a reciter's name. An upload's id is made from the
  /// file, so it can never be in the table below — it is answered
  /// before the lookup rather than falling through it into English.
  String reciterStyle(Reciter r) {
    if (r.isUserAudio) return yourAudioStyle;
    final table = _reciterStyles[lang];
    return table == null ? r.style : (table[r.id] ?? r.style);
  }

  /// What sets a voice's other recording apart, beside its chips. As
  /// with [reciterStyle], the English lives on the [Reciter].
  String? recordingNote(Reciter r) {
    final note = r.recordingNote;
    if (note == null) return null;
    return _recordingNotes[lang]?[r.id] ?? note;
  }

  static const _recordingNotes = <AppLang, Map<String, String>>{
    AppLang.ar: {
      'alafasy_2': 'تراويح · كاليفورنيا · 1430',
      'basfar_2': 'تسجيل المصحف · 2007',
    },
    AppLang.ur: {
      'alafasy_2': 'تراویح · کیلیفورنیا · 1430',
      'basfar_2': 'مصحف کی ریکارڈنگ · 2007',
    },
    AppLang.id: {
      'alafasy_2': 'Tarawih · Kalifornia · 1430',
      'basfar_2': 'Rekaman mushaf · 2007',
    },
    AppLang.de: {
      'alafasy_2': 'Tarawih · Kalifornien · 1430',
      'basfar_2': 'Mushaf-Aufnahme · 2007',
    },
  };

  /// English is absent on purpose: its wording lives on the [Reciter]
  /// itself, and a second copy here would be the one that goes stale.
  /// A voice's other recording ([Reciter.recordingOf]) has its voice's
  /// line, under its own id.
  static const _reciterStyles = <AppLang, Map<String, String>>{
    AppLang.ar: {
      'alafasy': 'مرتّل · دافئ شجي',
      'husary': 'مرتّل · متأنٍّ كلاسيكي',
      'abdulbasit': 'مرتّل · عميق رنّان',
      'minshawi': 'مرتّل · خالد مؤثر',
      'sudais': 'مرتّل · محلّق خاشع',
      'shuraym': 'مرتّل · مشرق ثابت',
      'muaiqly': 'مرتّل · هادئ رقيق',
      'hudhaify': 'مرتّل · مهيب دقيق',
      'dussary': 'مرتّل · غني عاطفي',
      'shatri': 'مرتّل · لطيف عذب',
      'ayyub': 'مرتّل · صادق أصيل',
      'ajmi': 'مرتّل · قوي مؤثر',
      'qatami': 'مرتّل · رقيق منساب',
      'qasim': 'مرتّل · رزين واضح',
      'budair': 'مرتّل · ناعم متمهل',
      'rifai': 'مرتّل · متّقد مؤثر',
      'tablawi': 'مرتّل · وقور، المدرسة المصرية',
      'jibreel': 'مرتّل · رنّان خاشع',
      'basfar': 'مرتّل · واضح متأمل',
      'bukhatir': 'مرتّل · مخملي هادئ',
      'qahtani': 'مرتّل · دافئ رحب',
      'matrood': 'مرتّل · حزين آسر',
      'neana': 'مرتّل · شجي، المدرسة المصرية',
      'salamah': 'مرتّل · سلس متأمل',
      'alaqimy': 'مرتّل · صافٍ متزن',
      'suesy': 'مرتّل · عذب لطيف',
      'alili': 'مرتّل · واضح متقن',
      'abdulkareem': 'مرتّل · سريع منضبط',
      'sahl_yassin': 'مرتّل · هادئ ممتد',
      'jaber': 'مرتّل · مهيب جليل',
      'abbad': 'مرتّل · انسيابي شاب',
      'sowaid': 'مرتّل · مدقّق في التجويد',
      'tunaiji': 'مرتّل · رهيف متأمل',
      'husary_mujawwad': 'مجوَّد · مزخرف متقن',
      'abdulbasit_mujawwad': 'مجوَّد · مهيب محلّق',
      'minshawi_mujawwad': 'مجوَّد · سامٍ كلاسيكي',
      'ghamdi': 'مرتّل · معتدل الإيقاع',
      'abkar': 'مرتّل · متمهّل',
      'thubaiti': 'مرتّل · سريع الإيقاع',
      'balilah': 'مرتّل · معتدل الإيقاع',
      'mustafa_ismail': 'مرتّل · متأنٍّ',
      'nufais': 'مرتّل · متمهّل',
      'salimi': 'مرتّل · متأنٍّ',
      'ibrahim_dosari': 'مرتّل · متمهّل',
      'yamani': 'مرتّل · متأنٍّ',
      'habdan': 'مرتّل · معتدل الإيقاع',
      'buaijan': 'مرتّل · سريع الإيقاع',
      'masrawi': 'مرتّل · متأنٍّ',
      'turki': 'مرتّل · معتدل الإيقاع',
      'zahrani': 'مرتّل · متمهّل',
      'kanakri': 'مرتّل · متأنٍّ',
      'khalaf': 'مرتّل · سريع الإيقاع',
      'harthi': 'مرتّل · معتدل الإيقاع',
      'majed': 'مرتّل · معتدل الإيقاع',
      'aloosi': 'مرتّل · متأنٍّ',
      'soufi': 'مرتّل · معتدل الإيقاع',
      'arkani': 'مرتّل · معتدل الإيقاع',
      'hawashi': 'مرتّل · سريع الإيقاع',
      'trabulsi': 'مرتّل · متأنٍّ',
      'amer': 'مرتّل · متأنٍّ',
      'deban': 'مرتّل · متأنٍّ',
      'shaheen': 'مرتّل · متأنٍّ',
      'alzain': 'مرتّل · معتدل الإيقاع',
      'emadi': 'مرتّل · معتدل الإيقاع',
      'hamza': 'مرتّل · معتدل الإيقاع',
      'hasan_saleh': 'مرتّل · سريع الإيقاع',
      'daghriri': 'مرتّل · معتدل الإيقاع',
      'osaimi': 'مرتّل · معتدل الإيقاع',
      'abdulkafi': 'مرتّل · سريع الإيقاع',
      'mohammadi': 'مرتّل · متأنٍّ',
      'alim_shah': 'مرتّل · سريع الإيقاع',
      'burhaji': 'مرتّل · معتدل الإيقاع',
      'hassan': 'مرتّل · متمهّل',
      'abdulhakam': 'مرتّل · معتدل الإيقاع',
      'hashim': 'مرتّل · متأنٍّ',
      'sahood': 'مرتّل · متأنٍّ',
      'shamrani': 'مرتّل · سريع الإيقاع',
      'hashemi': 'مرتّل · متأنٍّ',
      'taher': 'مرتّل · متأنٍّ',
      'jaleel': 'مرتّل · سريع الإيقاع',
      'albanna': 'مرتّل · معتدل الإيقاع',
      'khayyat': 'مرتّل · سريع الإيقاع',
      'nabil_rifai': 'مرتّل · معتدل الإيقاع',
      'akhdar': 'مرتّل · متمهّل',
      'raad_kurdi': 'مرتّل · متمهّل',
      'peshawa': 'مرتّل · معتدل الإيقاع',
      'zamil': 'مرتّل · معتدل الإيقاع',
      'saber': 'مرتّل · معتدل الإيقاع',
      'emad_hafez': 'مرتّل · متأنٍّ',
      'mohana': 'مرتّل · متأنٍّ',
      'bukheet': 'مرتّل · متأنٍّ',
      'abdulbari_mohammad': 'مرتّل · متمهّل',
      'mousa': 'مرتّل · معتدل الإيقاع',
      'rashad': 'مرتّل · متمهّل',
      'rayan': 'مرتّل · معتدل الإيقاع',
      'sanankoua': 'مرتّل · معتدل الإيقاع',
      'dukhain': 'مرتّل · متأنٍّ',
      'sayegh': 'مرتّل · معتدل الإيقاع',
      'obaikan': 'مرتّل · سريع الإيقاع',
      'daghistani': 'مرتّل · متمهّل',
      'haneef': 'مرتّل · سريع الإيقاع',
      'noah': 'مرتّل · سريع الإيقاع',
      'qari': 'مرتّل · معتدل الإيقاع',
      'asiri': 'مرتّل · متأنٍّ',
      'toure': 'مرتّل · متمهّل',
      'muaiqly_mujawwad': 'مجوَّد · متمهّل',
      'albanna_mujawwad': 'مجوَّد · متمهّل',
      'mustafa_ismail_mujawwad': 'مجوَّد · متمهّل',
      'alafasy_2': 'مرتّل · دافئ شجي',
      'basfar_2': 'مرتّل · واضح متأمل',
      'luhaidan': 'مرتّل · معتدل الإيقاع',
      'sobhi': 'مرتّل · خاشع مؤثّر',
    },
    AppLang.ur: {
      'alafasy': 'مرتّل · گرم جوش، سُریلا',
      'husary': 'مرتّل · ٹھہرا ہوا، کلاسیکی',
      'abdulbasit': 'مرتّل · گہرا، گونج دار',
      'minshawi': 'مرتّل · لازوال، اثر انگیز',
      'sudais': 'مرتّل · بلند، خشوع بھرا',
      'shuraym': 'مرتّل · روشن، ثابت قدم',
      'muaiqly': 'مرتّل · پُرسکون، نرم',
      'hudhaify': 'مرتّل · باوقار، دقیق',
      'dussary': 'مرتّل · بھرپور، جذباتی',
      'shatri': 'مرتّل · نرم، شیریں',
      'ayyub': 'مرتّل · مخلص، اصیل',
      'ajmi': 'مرتّل · قوی، اثر انگیز',
      'qatami': 'مرتّل · نازک، رواں',
      'qasim': 'مرتّل · متین، واضح',
      'budair': 'مرتّل · ریشمی، بے جلدی',
      'rifai': 'مرتّل · پُرجوش، دل ہلا دینے والا',
      'tablawi': 'مرتّل · باوقار، مصری مکتب',
      'jibreel': 'مرتّل · گونج دار، خاشع',
      'basfar': 'مرتّل · صاف، غور و فکر بھرا',
      'bukhatir': 'مرتّل · مخملی، پُرسکون',
      'qahtani': 'مرتّل · گرم جوش، کشادہ',
      'matrood': 'مرتّل · حزیں، دل موہ لینے والا',
      'neana': 'مرتّل · سُریلا، مصری مکتب',
      'salamah': 'مرتّل · لچکدار، مراقبانہ',
      'alaqimy': 'مرتّل · شفاف، متوازن',
      'suesy': 'مرتّل · شیریں، نرم',
      'alili': 'مرتّل · واضح، پختہ',
      'abdulkareem': 'مرتّل · تیز، منضبط',
      'sahl_yassin': 'مرتّل · خاموش، دراز',
      'jaber': 'مرتّل · سنجیدہ، باوقار',
      'abbad': 'مرتّل · رواں، جوان',
      'sowaid': 'مرتّل · تجوید میں نہایت دقیق',
      'tunaiji': 'مرتّل · لطیف، غور و فکر بھرا',
      'husary_mujawwad': 'مجوَّد · مزیّن، استادانہ',
      'abdulbasit_mujawwad': 'مجوَّد · شاندار، بلند',
      'minshawi_mujawwad': 'مجوَّد · بلند پایہ، کلاسیکی',
      'ghamdi': 'مرتّل · معتدل رفتار',
      'abkar': 'مرتّل · دھیمی رفتار',
      'thubaiti': 'مرتّل · تیز رفتار',
      'balilah': 'مرتّل · معتدل رفتار',
      'mustafa_ismail': 'مرتّل · ٹھہری ہوئی رفتار',
      'nufais': 'مرتّل · دھیمی رفتار',
      'salimi': 'مرتّل · ٹھہری ہوئی رفتار',
      'ibrahim_dosari': 'مرتّل · دھیمی رفتار',
      'yamani': 'مرتّل · ٹھہری ہوئی رفتار',
      'habdan': 'مرتّل · معتدل رفتار',
      'buaijan': 'مرتّل · تیز رفتار',
      'masrawi': 'مرتّل · ٹھہری ہوئی رفتار',
      'turki': 'مرتّل · معتدل رفتار',
      'zahrani': 'مرتّل · دھیمی رفتار',
      'kanakri': 'مرتّل · ٹھہری ہوئی رفتار',
      'khalaf': 'مرتّل · تیز رفتار',
      'harthi': 'مرتّل · معتدل رفتار',
      'majed': 'مرتّل · معتدل رفتار',
      'aloosi': 'مرتّل · ٹھہری ہوئی رفتار',
      'soufi': 'مرتّل · معتدل رفتار',
      'arkani': 'مرتّل · معتدل رفتار',
      'hawashi': 'مرتّل · تیز رفتار',
      'trabulsi': 'مرتّل · ٹھہری ہوئی رفتار',
      'amer': 'مرتّل · ٹھہری ہوئی رفتار',
      'deban': 'مرتّل · ٹھہری ہوئی رفتار',
      'shaheen': 'مرتّل · ٹھہری ہوئی رفتار',
      'alzain': 'مرتّل · معتدل رفتار',
      'emadi': 'مرتّل · معتدل رفتار',
      'hamza': 'مرتّل · معتدل رفتار',
      'hasan_saleh': 'مرتّل · تیز رفتار',
      'daghriri': 'مرتّل · معتدل رفتار',
      'osaimi': 'مرتّل · معتدل رفتار',
      'abdulkafi': 'مرتّل · تیز رفتار',
      'mohammadi': 'مرتّل · ٹھہری ہوئی رفتار',
      'alim_shah': 'مرتّل · تیز رفتار',
      'burhaji': 'مرتّل · معتدل رفتار',
      'hassan': 'مرتّل · دھیمی رفتار',
      'abdulhakam': 'مرتّل · معتدل رفتار',
      'hashim': 'مرتّل · ٹھہری ہوئی رفتار',
      'sahood': 'مرتّل · ٹھہری ہوئی رفتار',
      'shamrani': 'مرتّل · تیز رفتار',
      'hashemi': 'مرتّل · ٹھہری ہوئی رفتار',
      'taher': 'مرتّل · ٹھہری ہوئی رفتار',
      'jaleel': 'مرتّل · تیز رفتار',
      'albanna': 'مرتّل · معتدل رفتار',
      'khayyat': 'مرتّل · تیز رفتار',
      'nabil_rifai': 'مرتّل · معتدل رفتار',
      'akhdar': 'مرتّل · دھیمی رفتار',
      'raad_kurdi': 'مرتّل · دھیمی رفتار',
      'peshawa': 'مرتّل · معتدل رفتار',
      'zamil': 'مرتّل · معتدل رفتار',
      'saber': 'مرتّل · معتدل رفتار',
      'emad_hafez': 'مرتّل · ٹھہری ہوئی رفتار',
      'mohana': 'مرتّل · ٹھہری ہوئی رفتار',
      'bukheet': 'مرتّل · ٹھہری ہوئی رفتار',
      'abdulbari_mohammad': 'مرتّل · دھیمی رفتار',
      'mousa': 'مرتّل · معتدل رفتار',
      'rashad': 'مرتّل · دھیمی رفتار',
      'rayan': 'مرتّل · معتدل رفتار',
      'sanankoua': 'مرتّل · معتدل رفتار',
      'dukhain': 'مرتّل · ٹھہری ہوئی رفتار',
      'sayegh': 'مرتّل · معتدل رفتار',
      'obaikan': 'مرتّل · تیز رفتار',
      'daghistani': 'مرتّل · دھیمی رفتار',
      'haneef': 'مرتّل · تیز رفتار',
      'noah': 'مرتّل · تیز رفتار',
      'qari': 'مرتّل · معتدل رفتار',
      'asiri': 'مرتّل · ٹھہری ہوئی رفتار',
      'toure': 'مرتّل · دھیمی رفتار',
      'muaiqly_mujawwad': 'مجوَّد · دھیمی رفتار',
      'albanna_mujawwad': 'مجوَّد · دھیمی رفتار',
      'mustafa_ismail_mujawwad': 'مجوَّد · دھیمی رفتار',
      'alafasy_2': 'مرتّل · گرم جوش، سُریلا',
      'basfar_2': 'مرتّل · صاف، غور و فکر بھرا',
      'luhaidan': 'مرتّل · معتدل رفتار',
      'sobhi': 'مرتّل · خاشع، دل کو چھونے والا',
    },
    AppLang.id: {
      'alafasy': 'Murattal · hangat, merdu',
      'husary': 'Murattal · terukur, klasik',
      'abdulbasit': 'Murattal · dalam, menggema',
      'minshawi': 'Murattal · abadi, menyentuh',
      'sudais': 'Murattal · menjulang, khusyuk',
      'shuraym': 'Murattal · cerah, mantap',
      'muaiqly': 'Murattal · tenang, lembut',
      'hudhaify': 'Murattal · khidmat, cermat',
      'dussary': 'Murattal · kaya, penuh rasa',
      'shatri': 'Murattal · lembut, merdu',
      'ayyub': 'Murattal · tulus, klasik',
      'ajmi': 'Murattal · kuat, menyentuh',
      'qatami': 'Murattal · lembut, mengalir',
      'qasim': 'Murattal · tenang, jernih',
      'budair': 'Murattal · halus, tak tergesa',
      'rifai': 'Murattal · berapi, menggugah',
      'tablawi': 'Murattal · agung, mazhab Mesir',
      'jibreel': 'Murattal · menggema, khusyuk',
      'basfar': 'Murattal · jernih, perenung',
      'bukhatir': 'Murattal · beludru, tenteram',
      'qahtani': 'Murattal · hangat, lapang',
      'matrood': 'Murattal · sendu, memikat',
      'neana': 'Murattal · merdu, mazhab Mesir',
      'salamah': 'Murattal · luwes, meditatif',
      'alaqimy': 'Murattal · bening, seimbang',
      'suesy': 'Murattal · manis, lembut',
      'alili': 'Murattal · jelas, cermat',
      'abdulkareem': 'Murattal · gesit, disiplin',
      'sahl_yassin': 'Murattal · sunyi, panjang',
      'jaber': 'Murattal · khidmat, berwibawa',
      'abbad': 'Murattal · mulus, muda',
      'sowaid': 'Murattal · sangat teliti dalam tajwid',
      'tunaiji': 'Murattal · lapang, reflektif',
      'husary_mujawwad': 'Mujawwad · berhias, piawai',
      'abdulbasit_mujawwad': 'Mujawwad · megah, menjulang',
      'minshawi_mujawwad': 'Mujawwad · agung, klasik',
      'ghamdi': 'Murattal · tempo sedang',
      'abkar': 'Murattal · tempo pelan',
      'thubaiti': 'Murattal · tempo cepat',
      'balilah': 'Murattal · tempo sedang',
      'mustafa_ismail': 'Murattal · tempo terukur',
      'nufais': 'Murattal · tempo pelan',
      'salimi': 'Murattal · tempo terukur',
      'ibrahim_dosari': 'Murattal · tempo pelan',
      'yamani': 'Murattal · tempo terukur',
      'habdan': 'Murattal · tempo sedang',
      'buaijan': 'Murattal · tempo cepat',
      'masrawi': 'Murattal · tempo terukur',
      'turki': 'Murattal · tempo sedang',
      'zahrani': 'Murattal · tempo pelan',
      'kanakri': 'Murattal · tempo terukur',
      'khalaf': 'Murattal · tempo cepat',
      'harthi': 'Murattal · tempo sedang',
      'majed': 'Murattal · tempo sedang',
      'aloosi': 'Murattal · tempo terukur',
      'soufi': 'Murattal · tempo sedang',
      'arkani': 'Murattal · tempo sedang',
      'hawashi': 'Murattal · tempo cepat',
      'trabulsi': 'Murattal · tempo terukur',
      'amer': 'Murattal · tempo terukur',
      'deban': 'Murattal · tempo terukur',
      'shaheen': 'Murattal · tempo terukur',
      'alzain': 'Murattal · tempo sedang',
      'emadi': 'Murattal · tempo sedang',
      'hamza': 'Murattal · tempo sedang',
      'hasan_saleh': 'Murattal · tempo cepat',
      'daghriri': 'Murattal · tempo sedang',
      'osaimi': 'Murattal · tempo sedang',
      'abdulkafi': 'Murattal · tempo cepat',
      'mohammadi': 'Murattal · tempo terukur',
      'alim_shah': 'Murattal · tempo cepat',
      'burhaji': 'Murattal · tempo sedang',
      'hassan': 'Murattal · tempo pelan',
      'abdulhakam': 'Murattal · tempo sedang',
      'hashim': 'Murattal · tempo terukur',
      'sahood': 'Murattal · tempo terukur',
      'shamrani': 'Murattal · tempo cepat',
      'hashemi': 'Murattal · tempo terukur',
      'taher': 'Murattal · tempo terukur',
      'jaleel': 'Murattal · tempo cepat',
      'albanna': 'Murattal · tempo sedang',
      'khayyat': 'Murattal · tempo cepat',
      'nabil_rifai': 'Murattal · tempo sedang',
      'akhdar': 'Murattal · tempo pelan',
      'raad_kurdi': 'Murattal · tempo pelan',
      'peshawa': 'Murattal · tempo sedang',
      'zamil': 'Murattal · tempo sedang',
      'saber': 'Murattal · tempo sedang',
      'emad_hafez': 'Murattal · tempo terukur',
      'mohana': 'Murattal · tempo terukur',
      'bukheet': 'Murattal · tempo terukur',
      'abdulbari_mohammad': 'Murattal · tempo pelan',
      'mousa': 'Murattal · tempo sedang',
      'rashad': 'Murattal · tempo pelan',
      'rayan': 'Murattal · tempo sedang',
      'sanankoua': 'Murattal · tempo sedang',
      'dukhain': 'Murattal · tempo terukur',
      'sayegh': 'Murattal · tempo sedang',
      'obaikan': 'Murattal · tempo cepat',
      'daghistani': 'Murattal · tempo pelan',
      'haneef': 'Murattal · tempo cepat',
      'noah': 'Murattal · tempo cepat',
      'qari': 'Murattal · tempo sedang',
      'asiri': 'Murattal · tempo terukur',
      'toure': 'Murattal · tempo pelan',
      'muaiqly_mujawwad': 'Mujawwad · tempo pelan',
      'albanna_mujawwad': 'Mujawwad · tempo pelan',
      'mustafa_ismail_mujawwad': 'Mujawwad · tempo pelan',
      'alafasy_2': 'Murattal · hangat, merdu',
      'basfar_2': 'Murattal · jernih, perenung',
      'luhaidan': 'Murattal · tempo sedang',
      'sobhi': 'Murattal · khusyuk, menyentuh',
    },
    AppLang.de: {
      'alafasy': 'Murattal · warm, melodisch',
      'husary': 'Murattal · gemessen, klassisch',
      'abdulbasit': 'Murattal · tief, klangvoll',
      'minshawi': 'Murattal · zeitlos, bewegend',
      'sudais': 'Murattal · schwebend, andächtig',
      'shuraym': 'Murattal · hell, stetig',
      'muaiqly': 'Murattal · ruhig, zart',
      'hudhaify': 'Murattal · feierlich, präzise',
      'dussary': 'Murattal · voll, ausdrucksstark',
      'shatri': 'Murattal · sanft, melodiös',
      'ayyub': 'Murattal · aufrichtig, klassisch',
      'ajmi': 'Murattal · kraftvoll, ergreifend',
      'qatami': 'Murattal · zart, fließend',
      'qasim': 'Murattal · gefasst, klar',
      'budair': 'Murattal · seidig, unbeeilt',
      'rifai': 'Murattal · glühend, aufrüttelnd',
      'tablawi': 'Murattal · würdevoll, ägyptische Schule',
      'jibreel': 'Murattal · klangvoll, andächtig',
      'basfar': 'Murattal · klar, nachdenklich',
      'bukhatir': 'Murattal · samtig, ruhig',
      'qahtani': 'Murattal · warm, weit',
      'matrood': 'Murattal · wehmütig, fesselnd',
      'neana': 'Murattal · melodisch, ägyptische Schule',
      'salamah': 'Murattal · geschmeidig, meditativ',
      'alaqimy': 'Murattal · klar, ausgewogen',
      'suesy': 'Murattal · süß, sanft',
      'alili': 'Murattal · deutlich, sorgfältig',
      'abdulkareem': 'Murattal · zügig, diszipliniert',
      'sahl_yassin': 'Murattal · still, getragen',
      'jaber': 'Murattal · ernst, würdig',
      'abbad': 'Murattal · geschmeidig, jugendlich',
      'sowaid': 'Murattal · streng tadschwid-genau',
      'tunaiji': 'Murattal · luftig, besinnlich',
      'husary_mujawwad': 'Mujawwad · reich verziert, meisterhaft',
      'abdulbasit_mujawwad': 'Mujawwad · majestätisch, schwebend',
      'minshawi_mujawwad': 'Mujawwad · erhaben, klassisch',
      'ghamdi': 'Murattal · gleichmäßig',
      'abkar': 'Murattal · getragen',
      'thubaiti': 'Murattal · zügig',
      'balilah': 'Murattal · gleichmäßig',
      'mustafa_ismail': 'Murattal · gemessen',
      'nufais': 'Murattal · getragen',
      'salimi': 'Murattal · gemessen',
      'ibrahim_dosari': 'Murattal · getragen',
      'yamani': 'Murattal · gemessen',
      'habdan': 'Murattal · gleichmäßig',
      'buaijan': 'Murattal · zügig',
      'masrawi': 'Murattal · gemessen',
      'turki': 'Murattal · gleichmäßig',
      'zahrani': 'Murattal · getragen',
      'kanakri': 'Murattal · gemessen',
      'khalaf': 'Murattal · zügig',
      'harthi': 'Murattal · gleichmäßig',
      'majed': 'Murattal · gleichmäßig',
      'aloosi': 'Murattal · gemessen',
      'soufi': 'Murattal · gleichmäßig',
      'arkani': 'Murattal · gleichmäßig',
      'hawashi': 'Murattal · zügig',
      'trabulsi': 'Murattal · gemessen',
      'amer': 'Murattal · gemessen',
      'deban': 'Murattal · gemessen',
      'shaheen': 'Murattal · gemessen',
      'alzain': 'Murattal · gleichmäßig',
      'emadi': 'Murattal · gleichmäßig',
      'hamza': 'Murattal · gleichmäßig',
      'hasan_saleh': 'Murattal · zügig',
      'daghriri': 'Murattal · gleichmäßig',
      'osaimi': 'Murattal · gleichmäßig',
      'abdulkafi': 'Murattal · zügig',
      'mohammadi': 'Murattal · gemessen',
      'alim_shah': 'Murattal · zügig',
      'burhaji': 'Murattal · gleichmäßig',
      'hassan': 'Murattal · getragen',
      'abdulhakam': 'Murattal · gleichmäßig',
      'hashim': 'Murattal · gemessen',
      'sahood': 'Murattal · gemessen',
      'shamrani': 'Murattal · zügig',
      'hashemi': 'Murattal · gemessen',
      'taher': 'Murattal · gemessen',
      'jaleel': 'Murattal · zügig',
      'albanna': 'Murattal · gleichmäßig',
      'khayyat': 'Murattal · zügig',
      'nabil_rifai': 'Murattal · gleichmäßig',
      'akhdar': 'Murattal · getragen',
      'raad_kurdi': 'Murattal · getragen',
      'peshawa': 'Murattal · gleichmäßig',
      'zamil': 'Murattal · gleichmäßig',
      'saber': 'Murattal · gleichmäßig',
      'emad_hafez': 'Murattal · gemessen',
      'mohana': 'Murattal · gemessen',
      'bukheet': 'Murattal · gemessen',
      'abdulbari_mohammad': 'Murattal · getragen',
      'mousa': 'Murattal · gleichmäßig',
      'rashad': 'Murattal · getragen',
      'rayan': 'Murattal · gleichmäßig',
      'sanankoua': 'Murattal · gleichmäßig',
      'dukhain': 'Murattal · gemessen',
      'sayegh': 'Murattal · gleichmäßig',
      'obaikan': 'Murattal · zügig',
      'daghistani': 'Murattal · getragen',
      'haneef': 'Murattal · zügig',
      'noah': 'Murattal · zügig',
      'qari': 'Murattal · gleichmäßig',
      'asiri': 'Murattal · gemessen',
      'toure': 'Murattal · getragen',
      'muaiqly_mujawwad': 'Mujawwad · getragen',
      'albanna_mujawwad': 'Mujawwad · getragen',
      'mustafa_ismail_mujawwad': 'Mujawwad · getragen',
      'alafasy_2': 'Murattal · warm, melodisch',
      'basfar_2': 'Murattal · klar, nachdenklich',
      'luhaidan': 'Murattal · gleichmäßig',
      'sobhi': 'Murattal · andächtig, bewegend',
    },
  };

  /// Display name of a scenery; user-picked files get
  /// [yourPhoto]/[yourVideo] from the caller.
  ///
  /// Derived rather than listed. Scene ids are `<category>_<source>_<nn>`
  /// and there are hundreds of them, most not bundled — a hand-written
  /// name per scene would be stale the moment the library grew. The
  /// category is the part a reader actually recognises, so that is what
  /// gets translated, and the trailing number is carried across.
  String backgroundName(ReelBackground b) {
    final table = _sceneCategories[lang];
    if (table == null) return b.name;
    for (final key in _sceneCategoriesByLength) {
      if (!b.id.startsWith('${key}_')) continue;
      final n = RegExp(r'\d+$').firstMatch(b.name)?.group(0);
      final word = table[key]!;
      return n == null ? word : '$word $n';
    }
    return b.name;
  }

  /// The scene-category tables, for the test that checks no language
  /// is missing one. Checking the tables beats checking the rendered
  /// names: some categories are the same word in two languages —
  /// Indonesian for aurora is "Aurora" — so a rendered name that
  /// matches the English is not evidence of a gap.
  @visibleForTesting
  static Map<AppLang, Map<String, String>> get sceneCategoryTables =>
      _sceneCategories;

  /// Longest first, so `aerial_coast` is not swallowed by a shorter
  /// prefix that happens to match too. The keys are the same in every
  /// language, so one ordering serves them all.
  static final List<String> _sceneCategoriesByLength =
      _sceneCategories[AppLang.ar]!.keys.toList()
        ..sort((a, b) => b.length.compareTo(a.length));

  /// English is absent for the same reason it is absent from
  /// [_reciterStyles]: the scene's own name is already English.
  static const _sceneCategories = <AppLang, Map<String, String>>{
    AppLang.ar: {
      'desert': 'صحراء',
      'mountains': 'جبال',
      'ocean': 'محيط',
      'forest': 'غابة',
      'road': 'طريق',
      'sky': 'سماء',
      'rain': 'مطر',
      'snow': 'ثلج',
      'water': 'ماء',
      'rock': 'صخور',
      'clouds': 'غيوم',
      'sacred': 'مشهد إسلامي',
      'field': 'حقول',
      'abstract': 'تجريدي',
      'aurora': 'شفق قطبي',
      'cinematic': 'سينمائي',
      'aerial_mountain': 'جبال من الجو',
      'aerial_coast': 'ساحل من الجو',
      'aerial_forest': 'غابة من الجو',
      'aerial_desert': 'صحراء من الجو',
      'aerial_water': 'مياه من الجو',
      'aerial_land': 'أرض من الجو',
    },
    AppLang.ur: {
      'desert': 'صحرا',
      'mountains': 'پہاڑ',
      'ocean': 'سمندر',
      'forest': 'جنگل',
      'road': 'راستہ',
      'sky': 'آسمان',
      'rain': 'بارش',
      'snow': 'برف',
      'water': 'پانی',
      'rock': 'چٹانیں',
      'clouds': 'بادل',
      'sacred': 'مقدس منظر',
      'field': 'کھیت',
      'abstract': 'تجریدی',
      'aurora': 'قطبی روشنی',
      'cinematic': 'سینمائی',
      'aerial_mountain': 'فضا سے پہاڑ',
      'aerial_coast': 'فضا سے ساحل',
      'aerial_forest': 'فضا سے جنگل',
      'aerial_desert': 'فضا سے صحرا',
      'aerial_water': 'فضا سے پانی',
      'aerial_land': 'فضا سے زمین',
    },
    AppLang.id: {
      'desert': 'Gurun',
      'mountains': 'Gunung',
      'ocean': 'Samudra',
      'forest': 'Hutan',
      'road': 'Jalan',
      'sky': 'Langit',
      'rain': 'Hujan',
      'snow': 'Salju',
      'water': 'Air',
      'rock': 'Batuan',
      'clouds': 'Awan',
      'sacred': 'Tempat suci',
      'field': 'Ladang',
      'abstract': 'Abstrak',
      'aurora': 'Aurora',
      'cinematic': 'Sinematik',
      'aerial_mountain': 'Gunung dari udara',
      'aerial_coast': 'Pantai dari udara',
      'aerial_forest': 'Hutan dari udara',
      'aerial_desert': 'Gurun dari udara',
      'aerial_water': 'Perairan dari udara',
      'aerial_land': 'Daratan dari udara',
    },
    AppLang.de: {
      'desert': 'Wüste',
      'mountains': 'Berge',
      'ocean': 'Ozean',
      'forest': 'Wald',
      'road': 'Straße',
      'sky': 'Himmel',
      'rain': 'Regen',
      'snow': 'Schnee',
      'water': 'Wasser',
      'rock': 'Felsen',
      'clouds': 'Wolken',
      'sacred': 'Heiliger Ort',
      'field': 'Felder',
      'abstract': 'Abstrakt',
      'aurora': 'Polarlicht',
      'cinematic': 'Filmisch',
      'aerial_mountain': 'Berge aus der Luft',
      'aerial_coast': 'Küste aus der Luft',
      'aerial_forest': 'Wald aus der Luft',
      'aerial_desert': 'Wüste aus der Luft',
      'aerial_water': 'Wasser aus der Luft',
      'aerial_land': 'Land aus der Luft',
    },
  };


  // ===================================================================
  // Cards
  //
  // The third thing the app makes. A card is a still — a verse, a
  // hadith or the user's own words, set on a ground and exported as a
  // picture — and a run of them is a carousel. Everything below is
  // its vocabulary.
  // ===================================================================

  // ---- Tanafus, the arena --------------------------------------------
  /// The name is a name in every language, the way the app's is — it
  /// is the word of 83:26, and the Arabic-script languages set it in
  /// its own letters.
  String get arenaTitle =>
      _t('Tanafus', 'تنافُس', 'تنافُس', 'Tanafus', 'Tanafus');

  /// 83:26, the verse the arena is named for, in the reader's
  /// language. Empty for an Arabic reader, who reads the verse itself
  /// above it.
  String get arenaVerseLine => _t(
      'So for this let the competitors compete.',
      '',
      'اسی کے لیے مقابلہ کرنے والوں کو مقابلہ کرنا چاہیے۔',
      'Dan untuk yang demikian itu hendaknya orang berlomba-lomba.',
      'Und um dies sollen die Wettbewerbenden wetteifern.');

  /// The line under the verse: what the arena is for, in six words.
  String get arenaPitch => _t(
      'Play. Score. Dare a friend.',
      'العب. سجّل. تحدَّ صديقًا.',
      'کھیلیں۔ اسکور بنائیں۔ دوست کو للکاریں۔',
      'Main. Cetak skor. Tantang teman.',
      'Spiel. Punkte. Fordere heraus.');
  String get arenaPitchBody => _t(
      'Questions from the Quran. See where you stand, then send your '
          'code and see who can beat it.',
      'أسئلة من القرآن. اعرف أين أنت، ثم أرسل رمزك وانظر من '
          'يتفوّق عليه.',
      'قرآن سے سوالات۔ دیکھیں آپ کہاں کھڑے ہیں، پھر اپنا کوڈ بھیجیں اور '
          'دیکھیں کون اسے ہرا سکتا ہے۔',
      'Pertanyaan dari Al-Qur’an. Lihat posisimu, lalu kirim '
          'kodemu dan lihat siapa yang bisa mengalahkannya.',
      'Fragen aus dem Quran. Sieh, wo du stehst, dann schick deinen '
          'Code und sieh, wer ihn schlägt.');
  String get a11yOpensArena => _t(
      'Opens Tanafus, the Quran arena',
      'يفتح تنافُس، حلبة القرآن',
      'تنافُس کھولتا ہے، قرآن کا میدان',
      'Membuka Tanafus, arena Al-Qur’an',
      'Öffnet Tanafus, die Quran-Arena');
  /// Under the arena's name: what it is, in a few words.
  String get arenaWhat => _t(
      'A Quran quiz · test what you know',
      'مسابقة قرآنية · اختبر حفظك',
      'قرآنی کوئز · اپنا علم آزمائیں',
      'Kuis Al-Qur’an · uji hafalanmu',
      'Ein Quran-Quiz · teste dein Wissen');
  String get arenaModeTitle => _t('How do you play?', 'كيف تلعب؟',
      'کیسے کھیلیں گے؟', 'Cara bermain?', 'Wie spielst du?');
  String get arenaSolo =>
      _t('Play now', 'العب الآن', 'ابھی کھیلیں', 'Main sekarang', 'Jetzt spielen');
  String get arenaSoloHint => _t(
      'Questions from the Quran. Your best to beat.',
      'أسئلة من القرآن. وأفضل نتيجة لك هي ما تتحداه.',
      'قرآن سے سوالات۔ اپنا ہی بہترین اسکور ہرانے کو۔',
      'Pertanyaan dari Al-Qur’an. Rekormu sendiri untuk dikalahkan.',
      'Fragen aus dem Quran. Deine Bestleistung zu schlagen.');
  String get arenaChallenge =>
      _t('Beat a code', 'تحدَّ رمزًا', 'کوڈ ہرائیں', 'Kalahkan kode', 'Code schlagen');
  String get arenaChallengeHint => _t(
      'Play a friend’s round on the same questions, then send yours.',
      'العب جولة صديق بالأسئلة نفسها، ثم أرسل رمزك.',
      'دوست کا راؤنڈ انہی سوالوں پر کھیلیں، پھر اپنا بھیجیں۔',
      'Mainkan ronde teman dengan pertanyaan yang sama, lalu kirim '
          'kodemu.',
      'Spiel die Runde eines Freundes mit denselben Fragen, dann '
          'schick deine.');
  String get arenaScopeTitle => _t('Where do you compete?', 'أين تتنافس؟',
      'کہاں مقابلہ کریں گے؟', 'Di mana kamu bertanding?', 'Wo trittst du an?');
  String get arenaWholeQuran => _t('Whole Quran', 'القرآن كله', 'پورا قرآن',
      'Seluruh Al-Qur’an', 'Ganzer Quran');
  String arenaJuz(int n) =>
      _t('Juz $n', 'الجزء $n', 'پارہ $n', 'Juz $n', 'Dschuz $n');
  String get arenaJuzAmma =>
      _t('Juz Amma', 'جزء عمّ', 'پارہ عمّ', 'Juz Amma', 'Dschuz Amma');
  String get arenaPickJuz => _t('A juz', 'جزء', 'پارہ', 'Satu juz', 'Ein Dschuz');
  String get arenaPickSurah =>
      _t('A surah', 'سورة', 'سورت', 'Satu surah', 'Eine Sure');
  String arenaSurah(String name) => _t(
      'Surah $name',
      'سورة ${localizedSurahName(name)}',
      'سورۃ $name',
      'Surah $name',
      'Sure $name');
  String get arenaGamesTitle => _t('What is asked', 'ماذا يُسأل',
      'کیا پوچھا جائے گا', 'Yang ditanyakan', 'Was gefragt wird');
  String arenaGameName(ArenaGame g) => switch (g) {
        ArenaGame.completeVerse => _t('Complete the verse', 'أكمل الآية',
            'آیت مکمل کریں', 'Lengkapi ayat', 'Vers vervollständigen'),
        ArenaGame.missingWord => _t('The missing word', 'الكلمة الناقصة',
            'غائب لفظ', 'Kata yang hilang', 'Das fehlende Wort'),
        ArenaGame.whichSurah => _t('Which surah?', 'أي سورة؟',
            'کون سی سورت؟', 'Surah apa?', 'Welche Sure?'),
        ArenaGame.nextVerse => _t('What comes next', 'ما الآية التالية',
            'اگلی آیت', 'Ayat berikutnya', 'Was folgt'),
        ArenaGame.orderWords => _t('Order the words', 'رتّب الكلمات',
            'الفاظ ترتیب دیں', 'Urutkan kata', 'Wörter ordnen'),
        ArenaGame.surahFacts => _t('Know the surah', 'اعرف السورة',
            'سورت کو جانیں', 'Kenali surah', 'Die Sure kennen'),
      };
  String arenaPrompt(ArenaGame g) => switch (g) {
        ArenaGame.completeVerse => _t(
            'How does the verse go on?',
            'كيف تكتمل الآية؟',
            'آیت آگے کیسے چلتی ہے؟',
            'Bagaimana lanjutan ayatnya?',
            'Wie geht der Vers weiter?'),
        ArenaGame.missingWord => _t(
            'Which word is missing?',
            'ما الكلمة الناقصة؟',
            'کون سا لفظ غائب ہے؟',
            'Kata apa yang hilang?',
            'Welches Wort fehlt?'),
        ArenaGame.whichSurah => _t(
            'Which surah is this verse from?',
            'من أي سورة هذه الآية؟',
            'یہ آیت کس سورت سے ہے؟',
            'Ayat ini dari surah apa?',
            'Aus welcher Sure ist dieser Vers?'),
        ArenaGame.nextVerse => _t(
            'Which verse comes next?',
            'ما الآية التي تليها؟',
            'اگلی آیت کون سی ہے؟',
            'Ayat mana yang berikutnya?',
            'Welcher Vers folgt?'),
        ArenaGame.orderWords => _t(
            'Put the words in order',
            'رتّب الكلمات',
            'الفاظ کو ترتیب دیں',
            'Susun kata-katanya',
            'Bring die Wörter in Ordnung'),
        ArenaGame.surahFacts => _t('Know the surah', 'اعرف السورة',
            'سورت کو جانیں', 'Kenali surah', 'Die Sure kennen'),
      };
  String arenaFactVerseCount(String name) => _t(
      'How many verses does $name have?',
      'كم آية في سورة ${localizedSurahName(name)}؟',
      'سورۃ $name میں کتنی آیات ہیں؟',
      'Berapa ayat dalam surah $name?',
      'Wie viele Verse hat $name?');
  String arenaFactOrderNumber(int n) => _t(
      'Which surah is number $n in the mushaf?',
      'ما السورة رقم $n في المصحف؟',
      'مصحف میں نمبر $n کون سی سورت ہے؟',
      'Surah apa yang bernomor $n dalam mushaf?',
      'Welche Sure ist Nummer $n im Mushaf?');
  String arenaFactRevelation(String name) => _t(
      'Where was $name revealed?',
      'أين نزلت سورة ${localizedSurahName(name)}؟',
      'سورۃ $name کہاں نازل ہوئی؟',
      'Di mana surah $name diturunkan?',
      'Wo wurde $name offenbart?');
  String arenaFactComesAfter(String name) => _t(
      'Which surah comes right after $name?',
      'ما السورة التي تلي سورة ${localizedSurahName(name)}؟',
      'سورۃ $name کے فوراً بعد کون سی سورت ہے؟',
      'Surah apa yang tepat setelah $name?',
      'Welche Sure folgt direkt auf $name?');
  String arenaFactNameMeaning(String meaning) => _t(
      'Which surah’s name means “$meaning”?',
      'أي سورة يعني اسمها «$meaning»؟',
      'کس سورت کے نام کا مطلب ”$meaning“ ہے؟',
      'Surah mana yang namanya berarti “$meaning”?',
      'Welche Sure heißt „$meaning“?');
  String arenaFactOpensInJuz(String name) => _t(
      'In which juz does $name begin?',
      'في أي جزء تبدأ سورة ${localizedSurahName(name)}؟',
      'سورۃ $name کس پارے میں شروع ہوتی ہے؟',
      'Di juz berapa surah $name dimulai?',
      'In welchem Dschuz beginnt $name?');
  String get arenaMakkah => _t('Makkah', 'مكة', 'مکہ', 'Makkah', 'Mekka');
  String get arenaMadinah =>
      _t('Madinah', 'المدينة', 'مدینہ', 'Madinah', 'Medina');
  String get arenaBegin =>
      _t('Begin', 'ابدأ', 'شروع کریں', 'Mulai', 'Beginnen');
  String get arenaHaveCode => _t('Have a code?', 'لديك رمز؟', 'کوڈ ہے؟',
      'Punya kode?', 'Hast du einen Code?');
  String get arenaPlayCode =>
      _t('Play it', 'العب', 'کھیلیں', 'Mainkan', 'Spielen');
  String get arenaBadCode => _t(
      'That is not a Tanafus code',
      'هذا ليس رمز تنافُس',
      'یہ تنافُس کا کوڈ نہیں',
      'Itu bukan kode Tanafus',
      'Das ist kein Tanafus-Code');
  String arenaCodeFrom(String name) => _t(
      'A challenge from $name',
      'تحدٍّ من $name',
      '$name کی طرف سے چیلنج',
      'Tantangan dari $name',
      'Eine Herausforderung von $name');
  String get arenaCodeFromSomeone => _t(
      'A challenge for you',
      'تحدٍّ لك',
      'آپ کے لیے چیلنج',
      'Tantangan untukmu',
      'Eine Herausforderung für dich');
  String arenaCodeToBeat(int score) => _t(
      'Score to beat: $score',
      'النتيجة المطلوب تجاوزها: $score',
      'ہرانے کے لیے سکور: $score',
      'Skor yang harus dikalahkan: $score',
      'Zu schlagen: $score');
  String get arenaYourBest => _t('Your best', 'أفضل نتيجة لك',
      'آپ کا بہترین', 'Terbaikmu', 'Deine Bestleistung');
  String get arenaRecent => _t('Your rounds', 'جولاتك',
      'آپ کے راؤنڈز', 'Ronde-rondemu', 'Deine Runden');
  String get arenaNoRounds => _t(
      'Nothing played yet. The first round is the hardest to start.',
      'لم تُلعب أي جولة بعد. أصعب ما في الجولة الأولى أن تبدأها.',
      'ابھی کچھ نہیں کھیلا۔ پہلا راؤنڈ شروع کرنا سب سے مشکل ہے۔',
      'Belum ada yang dimainkan. Ronde pertama paling sulit dimulai.',
      'Noch nichts gespielt. Die erste Runde ist am schwersten zu beginnen.');
  String get arenaWon => _t('Won', 'فوز', 'جیت', 'Menang', 'Gewonnen');
  String get arenaLost => _t('Lost', 'خسارة', 'ہار', 'Kalah', 'Verloren');
  String get arenaDraw =>
      _t('Draw', 'تعادل', 'برابر', 'Seri', 'Unentschieden');
  String arenaQuestionOf(int i, int n) => _t(
      'Question $i of $n',
      'السؤال $i من $n',
      'سوال $i از $n',
      'Pertanyaan $i dari $n',
      'Frage $i von $n');
  String get arenaScore =>
      _t('Score', 'النتيجة', 'سکور', 'Skor', 'Punkte');
  String arenaStreak(int n) => _t(
      'Streak ×$n', 'سلسلة ×$n', 'سلسلہ ×$n', 'Beruntun ×$n', 'Serie ×$n');
  String get arenaRight =>
      _t('Right', 'صحيح', 'صحیح', 'Benar', 'Richtig');
  String get arenaNotThis =>
      _t('Not this one', 'ليست هذه', 'یہ نہیں', 'Bukan ini', 'Nicht dieses');
  String get arenaTheAnswer =>
      _t('The answer', 'الإجابة', 'جواب', 'Jawabannya', 'Die Antwort');
  String get arenaYourAnswer =>
      _t('Your answer', 'إجابتك', 'آپ کا جواب', 'Jawabanmu', 'Deine Antwort');
  String get arenaLeaveRound => _t('Leave the round?', 'مغادرة الجولة؟',
      'راؤنڈ چھوڑیں؟', 'Keluar dari ronde?', 'Runde verlassen?');
  String get arenaLeaveNoKeep => _t(
      'This round will not be kept.',
      'لن تُحفظ هذه الجولة.',
      'یہ راؤنڈ محفوظ نہیں ہوگا۔',
      'Ronde ini tidak akan disimpan.',
      'Diese Runde wird nicht gespeichert.');
  String get arenaUndo =>
      _t('Undo', 'تراجع', 'واپس', 'Urungkan', 'Rückgängig');
  String get arenaOpening => _t('Opening the mushaf…', 'يُفتح المصحف…',
      'مصحف کھل رہا ہے…', 'Membuka mushaf…', 'Der Mushaf wird geöffnet …');
  String get arenaRoundOver => _t('Round over', 'انتهت الجولة',
      'راؤنڈ ختم', 'Ronde selesai', 'Runde vorbei');
  String arenaRightOf(int c, int n) => _t(
      '$c of $n right',
      '$c من $n صحيحة',
      '$n میں سے $c صحیح',
      '$c dari $n benar',
      '$c von $n richtig');

  /// The standing a round earns. Every one of them is a word somebody
  /// can post: a low score is a fair round, not a beginner's.
  String arenaTierName(int tier) => switch (tier) {
        4 => _t('Flawless', 'كامل', 'بے عیب', 'Sempurna', 'Makellos'),
        3 => _t('Excellent', 'ممتاز', 'شاندار', 'Luar biasa', 'Ausgezeichnet'),
        2 => _t('Strong', 'قوي', 'مضبوط', 'Kuat', 'Stark'),
        1 => _t('Decent', 'جيّد', 'اچھا', 'Lumayan', 'Ordentlich'),
        _ => _t('Fair', 'مقبول', 'ٹھیک', 'Cukup', 'Solide'),
      };
  String get arenaNewBest => _t('New best', 'أفضل نتيجة جديدة',
      'نیا ریکارڈ', 'Rekor baru', 'Neue Bestleistung');
  String arenaBestRun(int n) => _t(
      'Best run: $n in a row',
      'أطول سلسلة: $n متتالية',
      'بہترین سلسلہ: لگاتار $n',
      'Rentetan terbaik: $n berturut',
      'Beste Serie: $n in Folge');

  /// Against a code: who stands where, said without a verdict on the
  /// one who stands lower.
  String arenaYouBeat(String name) => _t('You beat $name', 'تفوّقت على $name',
      'آپ نے $name کو ہرا دیا', 'Kamu mengalahkan $name', 'Du hast $name geschlagen');
  String arenaLevelWith(String name) => _t('Level with $name', 'تعادل مع $name',
      '$name کے برابر', 'Seri dengan $name', 'Gleichauf mit $name');
  String arenaStillLeads(String name) => _t('$name still leads',
      '$name ما زال في الصدارة', '$name اب بھی آگے ہے', '$name masih memimpin',
      '$name führt noch');
  String get arenaTheCode =>
      _t('the code', 'الرمز', 'کوڈ', 'kode itu', 'der Code');
  String get arenaSendChallenge => _t('Send the challenge', 'أرسل التحدي',
      'چیلنج بھیجیں', 'Kirim tantangan', 'Herausforderung senden');
  String get arenaShareCard => _t('Share the card', 'شارك البطاقة',
      'کارڈ شیئر کریں', 'Bagikan kartu', 'Karte teilen');
  String get arenaRematch =>
      _t('Rematch', 'جولة ثأر', 'دوبارہ مقابلہ', 'Tanding ulang', 'Revanche');
  String get arenaPlayAgain => _t('Play again', 'العب مجددًا',
      'دوبارہ کھیلیں', 'Main lagi', 'Nochmal spielen');
  String get arenaReview =>
      _t('Review', 'مراجعة', 'جائزہ', 'Tinjau', 'Rückblick');
  String get arenaShowReview => _t('Show the review', 'عرض المراجعة',
      'جائزہ دکھائیں', 'Tampilkan tinjauan', 'Rückblick zeigen');
  String get arenaHideReview => _t('Hide the review', 'إخفاء المراجعة',
      'جائزہ چھپائیں', 'Sembunyikan tinjauan', 'Rückblick ausblenden');
  String get arenaChallengeSent => _t('Challenge sent', 'أُرسل التحدي',
      'چیلنج بھیج دیا گیا', 'Tantangan terkirim', 'Herausforderung gesendet');
  String get arenaTapToContinue => _t('Tap to continue', 'انقر للمتابعة',
      'جاری رکھنے کے لیے ٹیپ کریں', 'Ketuk untuk lanjut', 'Tippen zum Fortfahren');
  String get arenaVs => _t('vs', 'ضد', 'بمقابلہ', 'vs', 'gegen');
  String get arenaYou => _t('You', 'أنت', 'آپ', 'Kamu', 'Du');
  String get arenaYourCode =>
      _t('Your code', 'رمزك', 'آپ کا کوڈ', 'Kodemu', 'Dein Code');
  String get arenaCodeCopied => _t('Code copied', 'نُسخ الرمز',
      'کوڈ کاپی ہو گیا', 'Kode disalin', 'Code kopiert');
  String arenaStoryScored(String name) => name.isEmpty
      ? _t('I scored', 'حقّقتُ', 'میں نے بنائے', 'Aku mencetak',
          'Ich habe erreicht')
      : _t('$name scored', 'حقّق $name', '$name نے بنائے', '$name mencetak',
          '$name hat erreicht');

  /// The three steps under the code on the result page: what to do
  /// with it, in as few words as a glance takes.
  String get arenaStepCopy => _t('Copy the code', 'انسخ الرمز',
      'کوڈ کاپی کریں', 'Salin kodenya', 'Code kopieren');
  String get arenaStepShare =>
      _t('Share it', 'شاركه', 'شیئر کریں', 'Bagikan', 'Teilen');
  String get arenaStepCompare => _t('See who beats it', 'وانظر من يتفوّق عليه',
      'دیکھیں کون ہراتا ہے', 'Lihat siapa yang mengalahkannya',
      'Sieh, wer ihn schlägt');

  /// Under the result's buttons: why the code is worth sending.
  String get arenaPitchTitle => _t(
      'Send it on — they get your exact quiz',
      'أرسله — يصلهم اختبارك نفسه',
      'آگے بھیجیں — انہیں آپ ہی کا کوئز ملے گا',
      'Kirimkan — mereka dapat kuis yang sama persis',
      'Weitersenden — sie bekommen genau dein Quiz');
  String get arenaPitchSame => _t(
      'The same 10 questions, in the same order: your code opens them.',
      'الأسئلة العشرة نفسها وبالترتيب نفسه: رمزك هو مفتاحها.',
      'وہی 10 سوال، اسی ترتیب میں: آپ کا کوڈ انہیں کھولتا ہے۔',
      '10 soal yang sama, urutan yang sama: kodemu yang membukanya.',
      'Dieselben 10 Fragen in derselben Reihenfolge: dein Code öffnet sie.');
  String get arenaPitchBeat => _t(
      'Your score is the one to beat. See who knows the Quran better.',
      'نتيجتك هي التحدي. لنرَ من يعرف القرآن أكثر.',
      'آپ کا اسکور ہی ہدف ہے۔ دیکھیں قرآن کون زیادہ جانتا ہے۔',
      'Skormu yang harus dikalahkan. Siapa paling paham Al-Qur\'an?',
      'Dein Ergebnis ist die Messlatte. Wer kennt den Koran besser?');
  String get arenaPitchReward => _t(
      '“Whoever guides to good has a reward like the one who does it.”',
      '«مَنْ دَلَّ عَلَى خَيْرٍ فَلَهُ مِثْلُ أَجْرِ فَاعِلِهِ»',
      '«جس نے بھلائی کی راہ دکھائی، اسے اس پر عمل کرنے والے جتنا اجر ملے گا»',
      '“Siapa yang menunjukkan kebaikan, baginya pahala seperti pelakunya.”',
      '„Wer zum Guten hinführt, hat den Lohn dessen, der es tut.“');
  String get arenaPitchRewardSource => _t('— Sahih Muslim', '— رواه مسلم',
      '— صحیح مسلم', '— HR. Muslim', '— Sahih Muslim');

  /// The Cards tab's door: it opens the lobby, as the roundel at the
  /// top does, and says so.
  String get arenaEnter => _t('Play Tanafus', 'العب تنافُس', 'تنافُس کھیلیں',
      'Main Tanafus', 'Tanafus spielen');
  String get arenaEnterHint => _t(
      'Choose a juz or surah, play, dare a friend',
      'اختر جزءًا أو سورة، العب، تحدَّ صديقًا',
      'پارہ یا سورت چنیں، کھیلیں، دوست کو للکاریں',
      'Pilih juz atau surah, main, tantang teman',
      'Wähle Dschuz oder Sure, spiel, fordere heraus');
  String get arenaSendBack => _t(
      'Send your score back — it is the same questions.',
      'أرسل نتيجتك — إنها الأسئلة نفسها.',
      'اپنا سکور واپس بھیجیں — یہی سوال ہیں۔',
      'Kirim balik skormu — pertanyaan yang sama.',
      'Schick deine Punkte zurück – es sind dieselben Fragen.');
  String get arenaDeleteRound => _t('Delete this round?', 'حذف هذه الجولة؟',
      'یہ راؤنڈ حذف کریں؟', 'Hapus ronde ini?', 'Diese Runde löschen?');
  String get arenaDelete =>
      _t('Delete', 'حذف', 'حذف کریں', 'Hapus', 'Löschen');
  String get arenaKeep => _t('Keep', 'إبقاء', 'رکھیں', 'Simpan', 'Behalten');
  String get arenaRoundDeleted => _t('Round deleted', 'حُذفت الجولة',
      'راؤنڈ حذف ہو گیا', 'Ronde dihapus', 'Runde gelöscht');

  /// The note shown once, the first time the arena opens.
  String get arenaIntroTitle => _t(
      'How much Quran do you carry?',
      'كم تحمل من القرآن؟',
      'آپ کتنا قرآن جانتے ہیں؟',
      'Seberapa banyak Al-Qur’an yang kamu hafal?',
      'Wie viel Quran trägst du in dir?');
  String get arenaIntroPlay => _t(
      'Play questions from any juz or surah.',
      'العب أسئلة من أي جزء أو سورة.',
      'کسی بھی پارے یا سورت سے سوالات کھیلیں۔',
      'Main pertanyaan dari juz atau surah mana pun.',
      'Spiel Fragen aus jedem Dschuz oder jeder Sure.');
  String get arenaIntroScore => _t(
      'See your score drawn as a constellation of the verses you met.',
      'شاهد نتيجتك مرسومة كوكبةً من الآيات التي قابلتها.',
      'اپنا اسکور ان آیات کے جھرمٹ کی صورت دیکھیں جن سے آپ ملے۔',
      'Lihat skormu tergambar sebagai rasi ayat-ayat yang kamu temui.',
      'Sieh deine Punkte als Sternbild der Verse, denen du begegnet bist.');
  String get arenaIntroDare => _t(
      'Send your code. Whoever plays it gets your exact questions — and has '
          'your score to beat.',
      'أرسل رمزك. من يلعبه يحصل على أسئلتك نفسها — ونتيجتك '
          'ليتفوّق عليها.',
      'اپنا کوڈ بھیجیں۔ جو کھیلے گا اسے آپ کے وہی سوال ملیں گے — اور '
          'ہرانے کو آپ کا اسکور۔',
      'Kirim kodemu. Siapa pun yang memainkannya mendapat '
          'pertanyaan yang sama — dan skormu untuk dikalahkan.',
      'Schick deinen Code. Wer ihn spielt, bekommt genau deine Fragen – und '
          'deine Punkte zu schlagen.');
  String get arenaIntroGo =>
      _t('Let’s play', 'هيا نلعب', 'چلیں کھیلیں', 'Ayo main', 'Los geht’s');

  /// The message a challenge travels in: the code, and what to do with
  /// it in three short lines. The store links are for the friend who
  /// does not have the app yet, which is the whole reason the message
  /// exists.
  String arenaShareMessage({
    required String name,
    required int score,
    required int correct,
    required int asked,
    required String scope,
    required String code,
    bool showScore = true,
  }) {
    // With the score taken off the card it comes off the message too:
    // the dare is then the round itself, and the code still carries
    // the number to beat for whoever plays it.
    final head = showScore
        ? _t(
            '🏆 ${name.isEmpty ? 'I' : name} scored $score — can you beat it?',
            '🏆 ${name.isEmpty ? 'حقّقتُ' : 'حقّق $name'} $score — هل تتفوّق؟',
            '🏆 ${name.isEmpty ? 'میں نے' : '$name نے'} $score بنائے — '
                'کیا آپ ہرا سکتے ہیں؟',
            '🏆 ${name.isEmpty ? 'Aku' : name} mencetak $score — bisa '
                'mengalahkannya?',
            '🏆 ${name.isEmpty ? 'Ich habe' : '$name hat'} $score erreicht – '
                'schaffst du mehr?')
        : _t(
            name.isEmpty
                ? '🏆 Can you beat my round?'
                : '🏆 Can you beat $name’s round?',
            name.isEmpty
                ? '🏆 هل تتفوّق على جولتي؟'
                : '🏆 هل تتفوّق على جولة $name؟',
            name.isEmpty
                ? '🏆 کیا آپ میرا راؤنڈ ہرا سکتے ہیں؟'
                : '🏆 کیا آپ $name کا راؤنڈ ہرا سکتے ہیں؟',
            name.isEmpty
                ? '🏆 Bisa kalahkan ronde aku?'
                : '🏆 Bisa kalahkan ronde $name?',
            name.isEmpty
                ? '🏆 Schaffst du meine Runde?'
                : '🏆 Schaffst du die Runde von $name?');
    final rest = _t(
        '🔑 Copy this code: $code\n'
            '📲 Open AyahReel › Cards › Tanafus › Beat a code › paste it\n\n'
            'iPhone: $appStoreUrl\n'
            'Android: $playStoreUrl',
        '🔑 انسخ هذا الرمز: $code\n'
            '📲 افتح AyahReel ‹ البطاقات ‹ تنافُس ‹ تحدَّ رمزًا ‹ ألصقه\n\n'
            'آيفون: $appStoreUrl\n'
            'أندرويد: $playStoreUrl',
        '🔑 یہ کوڈ کاپی کریں: $code\n'
            '📲 AyahReel ‹ کارڈز ‹ تنافُس ‹ کوڈ ہرائیں کھولیں ‹ پیسٹ کریں\n\n'
            'آئی فون: $appStoreUrl\n'
            'اینڈرائیڈ: $playStoreUrl',
        '🔑 Salin kode ini: $code\n'
            '📲 Buka AyahReel › Kartu › Tanafus › Kalahkan kode › tempel\n\n'
            'iPhone: $appStoreUrl\n'
            'Android: $playStoreUrl',
        '🔑 Kopiere diesen Code: $code\n'
            '📲 Öffne AyahReel › Karten › Tanafus › Code schlagen › einfügen\n\n'
            'iPhone: $appStoreUrl\n'
            'Android: $playStoreUrl');
    return '$head\n$rest';
  }

  /// The two small switches above a Tanafus result's share buttons:
  /// what the shared card carries. The second is named for what the
  /// round was played in, so it reads as the thing it hides.
  String get arenaCardScore =>
      _t('Score', 'النتيجة', 'اسکور', 'Skor', 'Punkte');
  String arenaCardScope(ArenaScopeKind kind) => switch (kind) {
        ArenaScopeKind.surah =>
          _t('Surah', 'السورة', 'سورۃ', 'Surah', 'Sure'),
        ArenaScopeKind.juz => _t('Juz', 'الجزء', 'پارہ', 'Juz', 'Dschuz'),
        ArenaScopeKind.quran =>
          _t('Quran', 'القرآن', 'قرآن', 'Al-Qur’an', 'Quran'),
      };

  /// The lobby's "?": how a round works, in four steps that end on the
  /// code going out to friends and family.
  String get arenaGuideTitle => _t('How it works', 'كيف تلعب',
      'یہ کیسے کام کرتا ہے', 'Cara mainnya', 'So funktioniert’s');
  String get arenaGuideLead => _t(
      'Ten questions, one code — and everyone you send it to plays the '
          'same round.',
      'عشرة أسئلة ورمز واحد، وكل من ترسله إليه يلعب الجولة نفسها.',
      'دس سوال، ایک کوڈ — اور جسے بھی آپ بھیجیں وہ یہی راؤنڈ کھیلے گا۔',
      'Sepuluh soal, satu kode — dan semua yang kamu kirimi memainkan '
          'ronde yang sama.',
      'Zehn Fragen, ein Code – und alle, denen du ihn schickst, spielen '
          'dieselbe Runde.');
  String get arenaGuidePickTitle => _t('Pick a juz or a surah',
      'اختر جزءًا أو سورة', 'کوئی پارہ یا سورت چنیں', 'Pilih juz atau surah',
      'Wähle einen Dschuz oder eine Sure');
  String get arenaGuidePickBody => _t(
      'Start with one you know well. You can change it anytime.',
      'ابدأ بما تحفظه جيدًا، ويمكنك تغييره متى شئت.',
      'جو اچھی طرح یاد ہو اس سے شروع کریں۔ جب چاہیں بدل سکتے ہیں۔',
      'Mulai dari yang kamu hafal. Bisa diganti kapan saja.',
      'Fang mit einer an, die du gut kennst. Du kannst sie jederzeit ändern.');
  String get arenaGuidePlayTitle => _t('Answer 10 questions',
      'أجب عن عشرة أسئلة', 'دس سوالوں کے جواب دیں', 'Jawab 10 soal',
      'Beantworte 10 Fragen');
  String get arenaGuidePlayBody => _t(
      'No clock: take your time. Right answers in a row score more.',
      'بلا وقت محدد، فخذ وقتك. والإجابات الصحيحة المتتالية تزيد نقاطك.',
      'کوئی وقت کی پابندی نہیں، آرام سے جواب دیں۔ لگاتار صحیح جواب زیادہ '
          'پوائنٹس دیتے ہیں۔',
      'Tanpa batas waktu, santai saja. Jawaban benar beruntun dapat poin '
          'lebih.',
      'Keine Uhr: Lass dir Zeit. Richtige Antworten in Folge bringen mehr '
          'Punkte.');
  String get arenaGuideCodeTitle => _t('Get your card and your code',
      'احصل على بطاقتك ورمزك', 'اپنا کارڈ اور کوڈ پائیں',
      'Dapatkan kartu dan kodemu', 'Hol dir deine Karte und deinen Code');
  String get arenaGuideCodeBody => _t(
      'Every round ends with a card to share and a code for those exact '
          'questions.',
      'تنتهي كل جولة ببطاقة للمشاركة ورمز لتلك الأسئلة نفسها.',
      'ہر راؤنڈ کے آخر میں شیئر کرنے کو ایک کارڈ اور انہی سوالوں کا کوڈ '
          'ملتا ہے۔',
      'Setiap ronde berakhir dengan kartu untuk dibagikan dan kode untuk '
          'soal-soal itu.',
      'Jede Runde endet mit einer Karte zum Teilen und einem Code für genau '
          'diese Fragen.');
  String get arenaGuideSendTitle => _t('Send it to friends & family',
      'أرسله لأصدقائك وعائلتك', 'اسے دوستوں اور گھر والوں کو بھیجیں',
      'Kirim ke teman & keluarga', 'Schick ihn Freunden & Familie');
  String get arenaGuideSendBody => _t(
      'They enter your code and play the very same quiz — then you both '
          'see who scored higher.',
      'يُدخلون رمزك ويلعبون الاختبار نفسه، ثم ترون معًا من تفوّق.',
      'وہ آپ کا کوڈ ڈال کر بالکل یہی کوئز کھیلیں گے — پھر آپ دونوں دیکھیں '
          'گے کس کا اسکور زیادہ ہے۔',
      'Mereka memasukkan kodemu dan memainkan kuis yang sama — lalu kalian '
          'lihat siapa yang lebih unggul.',
      'Sie geben deinen Code ein und spielen genau dasselbe Quiz – dann seht '
          'ihr, wer besser war.');
  String arenaGuideHaveCode(String door) => _t(
      'Got a code? Tap “$door” to play it.',
      'وصلك رمز؟ اضغط «$door» لتلعبه.',
      'کوڈ ملا ہے؟ کھیلنے کے لیے «$door» دبائیں۔',
      'Dapat kode? Ketuk “$door” untuk memainkannya.',
      'Einen Code bekommen? Tippe auf „$door“.');

  /// The "?" sheets: how a screen works, in a few plain lines.
  String get howToGotIt =>
      _t('Got it', 'فهمت', 'سمجھ گیا', 'Mengerti', 'Verstanden');
  String get sceneryHowToTitle => _t('How to pick a scenery',
      'كيف تختار المشهد', 'منظر کیسے چنیں', 'Cara memilih pemandangan',
      'So wählst du eine Kulisse');
  String sceneryHowToFrame(String full, String wide) => _t(
      'Pick a frame: “$full” fills the screen, “$wide” sits in a band.',
      'اختر الإطار: «$full» يملأ الشاشة، و«$wide» بين شريطين.',
      'فریم چنیں: «$full» پوری اسکرین بھرتا ہے، «$wide» ایک پٹی میں رہتا ہے۔',
      'Pilih bingkai: “$full” memenuhi layar, “$wide” berada di dalam pita.',
      'Wähle den Rahmen: „$full“ füllt den Bildschirm, „$wide“ liegt in '
          'einem Band.');
  String get sceneryHowToTap => _t(
      'Tap a scenery to put it behind your verses.',
      'اضغط على مشهد ليظهر خلف آياتك.',
      'منظر پر ٹیپ کریں، وہ آپ کی آیات کے پیچھے آ جائے گا۔',
      'Ketuk pemandangan untuk menaruhnya di belakang ayatmu.',
      'Tippe auf eine Kulisse, um sie hinter deine Verse zu legen.');
  String sceneryHowToSeveral(String label) => _t(
      'Turn on “$label” to change scenery as the verses go.',
      'فعّل «$label» ليتغيّر المشهد مع الآيات.',
      '«$label» آن کریں تاکہ آیات کے ساتھ منظر بدلے۔',
      'Nyalakan “$label” agar pemandangan berganti seiring ayat.',
      'Schalte „$label“ ein, damit die Kulisse mit den Versen wechselt.');
  String sceneryHowToMatch(String label) => _t(
      'Tap “$label” and your verses pick sceneries that fit them.',
      'اضغط «$label» لتختار آياتك مشاهد تناسبها.',
      '«$label» پر ٹیپ کریں، آپ کی آیات اپنے مناسب منظر چنیں گی۔',
      'Ketuk “$label”, ayatmu memilih pemandangan yang cocok.',
      'Tippe auf „$label“ und deine Verse wählen passende Kulissen.');
  String get sceneryHowToOwn => _t(
      'The first tile adds your own photo or video.',
      'أول مربّع يضيف صورتك أو مقطعك.',
      'پہلا خانہ آپ کی اپنی تصویر یا ویڈیو شامل کرتا ہے۔',
      'Kotak pertama menambahkan foto atau videomu sendiri.',
      'Die erste Kachel fügt dein eigenes Foto oder Video hinzu.');

  /// The second tab of the Reels page: the card of every verse the user
  /// has made a reel of, lit on the whole Quran.
  String get reelsTabReels => _t('Reels', 'المقاطع', 'ریلز', 'Reel', 'Reels');

  /// The Home shelf's switch, beside "Reels": the quiz's rounds.
  String get shelfRounds =>
      _t('Rounds', 'الجولات', 'راؤنڈز', 'Ronde', 'Runden');
  String get reelsTabVerses => _t('Your verses', 'آياتك', 'آپ کی آیات',
      'Ayat-ayatmu', 'Deine Verse');
  String versesCardNumbers(int verses, int surahs) => _t(
      '${verses == 1 ? '1 verse' : '$verses verses'} · '
          '${surahs == 1 ? '1 surah' : '$surahs surahs'}',
      'آيات: $verses · سور: $surahs',
      '$verses آیات · $surahs سورتیں',
      '$verses ayat · $surahs surah',
      '${verses == 1 ? '1 Vers' : '$verses Verse'} · '
          '${surahs == 1 ? '1 Sure' : '$surahs Suren'}');
  String get versesCaption => _t(
      'The whole Quran, a ray for every surah. Yours are the ones alight.',
      'القرآن كله، شعاع لكل سورة. ما أضاء منها آياتك.',
      'پورا قرآن، ہر سورت کی ایک کرن۔ جو روشن ہیں وہ آپ کی آیات ہیں۔',
      'Seluruh Al-Qur’an, satu sinar untuk tiap surah. Yang menyala adalah '
          'ayat-ayatmu.',
      'Der ganze Quran, ein Strahl für jede Sure. Die leuchtenden sind deine.');
  String get versesEmpty => _t(
      'Every reel, card and $arenaTitle round lights its verses here, on '
          'the whole Quran.',
      'كل مقطع وبطاقة وجولة «$arenaTitle» تُضيء آياتها هنا، على القرآن كله.',
      'ہر ریل، کارڈ اور «$arenaTitle» کا راؤنڈ اپنی آیات یہاں، پورے قرآن '
          'پر روشن کرتا ہے۔',
      'Setiap reel, kartu, dan ronde $arenaTitle menyalakan ayatnya di '
          'sini, di seluruh Al-Qur’an.',
      'Jedes Reel, jede Karte und jede $arenaTitle-Runde lässt ihre Verse '
          'hier aufleuchten – im ganzen Quran.');
  String get versesToggleName =>
      _t('Name', 'الاسم', 'نام', 'Nama', 'Name');
  String get versesToggleNumbers =>
      _t('Numbers', 'الأرقام', 'اعداد', 'Angka', 'Zahlen');

  /// The "?" beside the card: what the sun is, what lights it, and
  /// what to do with it.
  String get sunHowToTitle => _t('How your verses light up', 'كيف تُضيء آياتك',
      'آپ کی آیات کیسے روشن ہوتی ہیں', 'Bagaimana ayatmu menyala',
      'Wie deine Verse aufleuchten');
  String get sunHowToRays => _t(
      'The whole Quran as a sun: a ray for each of its 114 surahs, longer '
          'for the longer ones.',
      'القرآن كله شمسٌ: شعاع لكل سورة من سوره الـ114، أطول للسور الأطول.',
      'پورا قرآن ایک سورج: اس کی 114 سورتوں میں سے ہر ایک کی ایک کرن، لمبی '
          'سورت کی لمبی کرن۔',
      'Seluruh Al-Qur’an sebagai matahari: satu sinar untuk tiap 114 '
          'surahnya, lebih panjang untuk surah yang lebih panjang.',
      'Der ganze Quran als Sonne: ein Strahl für jede seiner 114 Suren, '
          'länger für die längeren.');
  String get sunHowToLight => _t(
      'A verse lights up when you meet it here: in a reel you make, a card '
          'that quotes it, a question in $arenaTitle.',
      'تُضيء الآية حين تلقاها هنا: في مقطع تصنعه، أو بطاقة تقتبسها، أو سؤال '
          'في «$arenaTitle».',
      'آیت تب روشن ہوتی ہے جب آپ اسے یہاں پاتے ہیں: اپنی بنائی ریل میں، اسے '
          'نقل کرنے والے کارڈ میں، یا «$arenaTitle» کے کسی سوال میں۔',
      'Ayat menyala saat kamu menjumpainya di sini: di reel yang kamu buat, '
          'kartu yang mengutipnya, atau pertanyaan di $arenaTitle.',
      'Ein Vers leuchtet auf, sobald du ihm hier begegnest: in einem Reel, '
          'das du machst, einer Karte, die ihn zitiert, einer Frage in '
          '$arenaTitle.');
  String get sunHowToOnCard => _t(
      '“$versesToggleNumbers” adds how many are lit, and '
          '“$versesToggleName” your name.',
      '«$versesToggleNumbers» يضيف عدد ما أضاء، و«$versesToggleName» اسمك.',
      '«$versesToggleNumbers» روشن آیات کی گنتی جوڑتا ہے، اور '
          '«$versesToggleName» آپ کا نام۔',
      '“$versesToggleNumbers” menambahkan jumlah yang menyala, dan '
          '“$versesToggleName” namamu.',
      '„$versesToggleNumbers“ fügt hinzu, wie viele leuchten, und '
          '„$versesToggleName“ deinen Namen.');
  String get sunHowToShare => _t(
      'Share it as a picture or to your story. It keeps growing, so share '
          'it again later.',
      'شاركها صورةً أو في قصتك. وهي تكبر معك، فشاركها مجددًا لاحقًا.',
      'اسے تصویر کے طور پر یا اپنی اسٹوری میں شیئر کریں۔ یہ بڑھتا رہتا ہے، '
          'بعد میں پھر شیئر کریں۔',
      'Bagikan sebagai gambar atau ke story-mu. Ia terus bertambah, jadi '
          'bagikan lagi nanti.',
      'Teile sie als Bild oder in deiner Story. Sie wächst weiter – teile '
          'sie später wieder.');
  String get a11yVersesCard => _t(
      'Your verses, lit on the whole Quran, as the card will be shared',
      'آياتك مضاءة على القرآن كله، كما ستُشارك البطاقة',
      'آپ کی آیات پورے قرآن پر روشن، جیسے کارڈ شیئر ہوگا',
      'Ayat-ayatmu menyala di seluruh Al-Qur’an, seperti kartu akan dibagikan',
      'Deine Verse im ganzen Quran erleuchtet, so wie die Karte geteilt wird');
  String get versesShareMessage => _t(
      '✨ The verses I’ve lived with, lit up across the whole Quran — a ray '
          'for every surah.\n\n'
          '📲 Light yours with AyahReel\n'
          'iPhone: $appStoreUrl\n'
          'Android: $playStoreUrl',
      '✨ الآيات التي عشتُ معها، مضاءة على القرآن كله — شعاع لكل سورة.\n\n'
          '📲 أضئ آياتك مع AyahReel\n'
          'آيفون: $appStoreUrl\n'
          'أندرويد: $playStoreUrl',
      '✨ وہ آیات جن کے ساتھ میں نے وقت گزارا، پورے قرآن پر روشن — ہر سورت کی ایک کرن۔\n\n'
          '📲 AyahReel کے ساتھ اپنی آیات روشن کریں\n'
          'آئی فون: $appStoreUrl\n'
          'اینڈرائیڈ: $playStoreUrl',
      '✨ Ayat-ayat yang kujalani, menyala di seluruh Al-Qur’an — satu '
          'sinar untuk tiap surah.\n\n'
          '📲 Nyalakan ayatmu dengan AyahReel\n'
          'iPhone: $appStoreUrl\n'
          'Android: $playStoreUrl',
      '✨ Die Verse, mit denen ich gelebt habe, leuchtend im ganzen Quran – '
          'ein Strahl für jede Sure.\n\n'
          '📲 Bring deine mit AyahReel zum Leuchten\n'
          'iPhone: $appStoreUrl\n'
          'Android: $playStoreUrl');

  /// The custom colour circle at the end of every row of swatches, and
  /// the picker it opens.
  String get customColour => _t('Your own colour', 'لونك الخاص',
      'اپنا رنگ', 'Warna pilihanmu', 'Eigene Farbe');
  String customColourIs(String hex) => _t('Your colour $hex',
      'لونك $hex', 'آپ کا رنگ $hex', 'Warnamu $hex', 'Deine Farbe $hex');
  String get customColourTitle => _t('Mix your colour', 'امزج لونك',
      'اپنا رنگ بنائیں', 'Racik warnamu', 'Mische deine Farbe');
  String get customColourSave => _t('Save', 'حفظ', 'محفوظ کریں', 'Simpan',
      'Speichern');
  String get customColourKept => _t('SAVED', 'المحفوظة', 'محفوظ', 'TERSIMPAN',
      'GESPEICHERT');
  String get customColourKeptEmpty => _t(
      'Colours you save appear here, ready for every card and reel.',
      'تظهر هنا الألوان التي تحفظها، جاهزة لكل بطاقة ومقطع.',
      'جو رنگ آپ محفوظ کریں گے وہ یہاں ہر کارڈ اور ریل کے لیے تیار ملیں گے۔',
      'Warna yang kamu simpan muncul di sini, siap untuk setiap kartu dan reel.',
      'Gespeicherte Farben erscheinen hier, bereit für jede Karte und jedes Reel.');
  String get customColourKeptHint => _t('Hold to remove', 'اضغط مطولًا للحذف',
      'ہٹانے کے لیے دبائے رکھیں', 'Tahan untuk menghapus', 'Halten zum Entfernen');

  /// The small switch beside the kept colours: taps let them go until
  /// "Done".
  String get customColourRemove =>
      _t('Remove', 'إزالة', 'ہٹائیں', 'Hapus', 'Entfernen');
  String get customColourRemoveDone =>
      _t('Done', 'تم', 'ہو گیا', 'Selesai', 'Fertig');
  String get customColourTapToRemove => _t('Tap to remove', 'اضغط للإزالة',
      'ہٹانے کے لیے ٹیپ کریں', 'Ketuk untuk menghapus', 'Tippen zum Entfernen');
  String get customColourField => _t('Shade', 'الدرجة', 'شیڈ', 'Corak',
      'Farbton und Helligkeit');
  String get customColourHue => _t('Hue', 'اللون', 'رنگت', 'Rona', 'Farbton');
  String customColourHueValue(int degrees) => _t('$degrees degrees',
      '$degrees درجة', '$degrees ڈگری', '$degrees derajat', '$degrees Grad');

  /// The pill under the card on a Tanafus result that opens the menu
  /// of what the card carries, and that menu's rows.
  String get arenaCardMenu =>
      _t('On the card', 'على البطاقة', 'کارڈ پر', 'Di kartu', 'Auf der Karte');
  String arenaCardMenuHint(int on, int of) => _t(
      '$on of $of shown — opens the choices',
      'يظهر $on من $of — يفتح الخيارات',
      '$of میں سے $on نظر آ رہے ہیں — انتخاب کھولتا ہے',
      '$on dari $of ditampilkan — membuka pilihan',
      '$on von $of sichtbar – öffnet die Auswahl');
  String get arenaCardName => _t('Name', 'الاسم', 'نام', 'Nama', 'Name');
  String get arenaAddName => _t('Add your name', 'أضف اسمك',
      'اپنا نام شامل کریں', 'Tambahkan namamu', 'Namen hinzufügen');

  /// What the story button says, in place of its own name, the moment
  /// it has put the code on the clipboard — just before Instagram opens.
  String get arenaYourCodeCopied => _t("Your code's copied", 'نُسخ رمزك',
      'آپ کا کوڈ کاپی ہو گیا', 'Kodemu sudah disalin', 'Dein Code ist kopiert');
  String get a11yArenaCardPreview => _t(
      'Your card, as it will be shared',
      'بطاقتك كما ستُشارَك',
      'آپ کا کارڈ، جیسا شیئر ہوگا',
      'Kartumu, seperti yang akan dibagikan',
      'Deine Karte, so wie sie geteilt wird');
  String get cardsArenaBody => _t(
      'Quiz a friend on the Quran — complete the verse, find the word, '
          'name the surah',
      'تحدَّ صديقًا في القرآن — أكمل الآية، اعثر على الكلمة، سمِّ السورة',
      'دوست کو قرآن پر چیلنج کریں — آیت مکمل کریں، لفظ تلاش کریں، سورت بتائیں',
      'Tantang teman soal Al-Qur’an — lengkapi ayat, temukan kata, sebutkan '
          'surah',
      'Fordere einen Freund im Quran heraus – Vers vervollständigen, Wort '
          'finden, Sure benennen');
  String get a11yAnswersWith => _t('Answers with this', 'يجيب بهذا',
      'یہ جواب دیتا ہے', 'Menjawab dengan ini', 'Antwortet damit');
  String get a11yPlacesWord => _t('Places this word next', 'يضع هذه الكلمة تاليًا',
      'یہ لفظ اگلا رکھتا ہے', 'Menempatkan kata ini berikutnya',
      'Setzt dieses Wort als nächstes');
  String get a11yOpensRound => _t('Opens this round', 'يفتح هذه الجولة',
      'یہ راؤنڈ کھولتا ہے', 'Membuka ronde ini', 'Öffnet diese Runde');
  String get a11yShowsQuestion => _t('Shows the question', 'يعرض السؤال',
      'سوال دکھاتا ہے', 'Menampilkan pertanyaan', 'Zeigt die Frage');

  String get navCards => _t('Cards', 'البطاقات', 'کارڈز', 'Kartu', 'Karten');

  String get cardsTitle =>
      _t('Cards', 'البطاقات', 'کارڈز', 'Kartu', 'Karten');

  String get cardsBlurb => _t(
      'A verse, a hadith, or your own words — set on a ground and ready '
          'to post.\n'
          'Make Cards, Carousels and Slideshows very easily.',
      'آية أو حديث أو كلماتك أنت — على خلفية جاهزة للنشر.\n'
          'اصنع البطاقات والمنشورات بسهولة تامة.',
      'ایک آیت، ایک حدیث، یا آپ کے اپنے الفاظ — ایک خوبصورت پس منظر پر، '
          'شیئر کرنے کے لیے تیار۔\n'
          'کارڈز، کیروسل اور سلائیڈ شو بہت آسانی سے بنائیں۔',
      'Satu ayat, satu hadis, atau kata-katamu sendiri — di atas latar '
          'yang siap diunggah.\n'
          'Buat kartu, carousel, dan slideshow dengan sangat mudah.',
      'Ein Vers, ein Hadith oder deine eigenen Worte — auf einem Grund, '
          'fertig zum Teilen.\n'
          'Erstelle Karten, Karussells und Slideshows ganz einfach.');

  String get cardsNew => _t('New card', 'بطاقة جديدة', 'نیا کارڈ',
      'Kartu baru', 'Neue Karte');

  String get cardsFromVerse => _t('From a verse', 'من آية', 'آیت سے',
      'Dari ayat', 'Aus einem Vers');

  String get cardsFromHadith => _t('From a hadith', 'من حديث', 'حدیث سے',
      'Dari hadis', 'Aus einem Hadith');

  String get cardsBlank =>
      _t('Blank', 'فارغة', 'خالی', 'Kosong', 'Leer');

  String get cardsTodaysVerse => _t("Today's verse", 'آية اليوم', 'آج کی آیت',
      'Ayat hari ini', 'Vers des Tages');

  String get cardsYours =>
      _t('Your cards', 'بطاقاتك', 'آپ کے کارڈز', 'Kartumu', 'Deine Karten');

  String get cardsEmptyTitle => _t('No cards yet', 'لا بطاقات بعد',
      'ابھی کوئی کارڈ نہیں', 'Belum ada kartu', 'Noch keine Karten');

  String get cardsEmptyBody => _t(
      'Start from a verse, a hadith, or an empty card.',
      'ابدأ بآية أو حديث أو بطاقة فارغة.',
      'آیت، حدیث یا خالی کارڈ سے شروع کریں۔',
      'Mulai dari ayat, hadis, atau kartu kosong.',
      'Beginne mit einem Vers, einem Hadith oder einer leeren Karte.');

  /// "3 cards" — and the Arabic dual, which is a word of its own and
  /// not a number with an s on it.
  String cardCount(int n) => switch (lang) {
        AppLang.en => n == 1 ? '1 card' : '$n cards',
        AppLang.ar => switch (n) {
            1 => 'بطاقة واحدة',
            2 => 'بطاقتان',
            _ when n <= 10 => '$n بطاقات',
            _ => '$n بطاقة',
          },
        AppLang.ur => n == 1 ? 'ایک کارڈ' : '$n کارڈز',
        AppLang.id => '$n kartu',
        AppLang.de => n == 1 ? '1 Karte' : '$n Karten',
      };

  String get cardsDelete =>
      _t('Delete', 'حذف', 'حذف کریں', 'Hapus', 'Löschen');

  String get cardsDeleted =>
      _t('Deleted', 'حُذفت', 'حذف ہو گیا', 'Dihapus', 'Gelöscht');

  String get cardsDuplicate => _t('Duplicate', 'نسخة', 'نقل',
      'Gandakan', 'Duplizieren');

  // ---- the composer's tools ----------------------------------------

  String get cardText => _t('Words', 'الكلمات', 'الفاظ', 'Kata', 'Worte');

  String get cardType => _t('Type', 'الخط', 'خط', 'Huruf', 'Schrift');

  String get cardInk => _t('Ink', 'اللون', 'رنگ', 'Warna', 'Farbe');

  String get cardGround =>
      _t('Ground', 'الخلفية', 'پس منظر', 'Latar', 'Grund');

  String get cardLookTool =>
      _t('Look', 'المظهر', 'انداز', 'Nuansa', 'Look');

  String get cardFrameTool =>
      _t('Frame', 'الإطار', 'فریم', 'Bingkai', 'Rahmen');

  String get cardShape =>
      _t('Shape', 'المقاس', 'سائز', 'Ukuran', 'Format');

  String get cardAdd =>
      _t('Add card', 'أضف بطاقة', 'کارڈ شامل کریں', 'Tambah kartu',
          'Karte hinzufügen');

  String get cardDuplicateSlide => _t('Duplicate card', 'نسخة من البطاقة',
      'کارڈ کی نقل', 'Gandakan kartu', 'Karte duplizieren');

  String get cardDeleteSlide => _t('Delete card', 'احذف البطاقة',
      'کارڈ حذف کریں', 'Hapus kartu', 'Karte löschen');

  String cardNumberOf(int i, int n) => _t('Card $i of $n',
      'البطاقة $i من $n', '$n میں سے کارڈ $i', 'Kartu $i dari $n',
      'Karte $i von $n');

  String get cardAddText => _t('Add words', 'أضف كلمات', 'الفاظ شامل کریں',
      'Tambah kata', 'Worte hinzufügen');

  String get cardEditText =>
      _t('Edit', 'تحرير', 'تدوین', 'Ubah', 'Bearbeiten');

  String get cardRemoveText =>
      _t('Remove', 'إزالة', 'ہٹائیں', 'Hapus', 'Entfernen');

  String get cardWriteHint => _t('Write something…', 'اكتب شيئًا…',
      'کچھ لکھیے…', 'Tulis sesuatu…', 'Schreibe etwas …');

  String get cardApplyAll => _t('Apply to every card', 'طبّق على كل البطاقات',
      'سب کارڈز پر لاگو کریں', 'Terapkan ke semua kartu',
      'Auf alle Karten anwenden');

  String get cardAppliedAll => _t('Applied to every card',
      'طُبّق على كل البطاقات', 'سب کارڈز پر لاگو ہو گیا',
      'Diterapkan ke semua kartu', 'Auf alle Karten angewendet');

  String get cardSize => _t('Size', 'الحجم', 'سائز', 'Ukuran', 'Größe');

  String get cardAlign =>
      _t('Align', 'المحاذاة', 'ترتیب', 'Perataan', 'Ausrichtung');

  /// The three alignment buttons, named for where the text lands on
  /// the card (for an Arabic block, start is the right).
  String get cardAlignLeft => _t('Align left', 'محاذاة لليسار',
      'بائیں جانب', 'Rata kiri', 'Linksbündig');

  String get cardAlignCentre => _t('Align centre', 'توسيط', 'درمیان میں',
      'Rata tengah', 'Zentriert');

  String get cardAlignRight => _t('Align right', 'محاذاة لليمين',
      'دائیں جانب', 'Rata kanan', 'Rechtsbündig');

  String get cardLineHeight =>
      _t('Leading', 'تباعد الأسطر', 'سطری فاصلہ', 'Spasi baris',
          'Zeilenabstand');

  String get cardTracking =>
      _t('Letter spacing', 'تباعد الحروف', 'حروف کا فاصلہ', 'Spasi huruf',
          'Laufweite');

  String get cardTurn => _t('Turn', 'الميل', 'جھکاؤ', 'Kemiringan',
      'Neigung');

  String get cardOpacity =>
      _t('Fade', 'الشفافية', 'دھندلاہٹ', 'Transparansi', 'Deckkraft');

  String get cardFinish =>
      _t('Finish', 'اللمسة', 'فنش', 'Sentuhan', 'Finish');

  String get cardDim => _t('Darken', 'التعتيم', 'تاریکی', 'Gelapkan',
      'Abdunkeln');

  String get cardBlur =>
      _t('Blur', 'الضبابية', 'دھندلا', 'Buram', 'Unschärfe');

  String get cardZoom => _t('Zoom', 'التقريب', 'زوم', 'Perbesar', 'Zoom');

  String get cardReframeHint => _t('Drag the picture to reframe it',
      'اسحب الصورة لتغيير موضعها', 'تصویر کو کھینچ کر جگہ بدلیں',
      'Geser gambar untuk mengatur letaknya',
      'Zieh das Bild, um den Ausschnitt zu wählen');

  String get cardPaper =>
      _t('Paper', 'الورق', 'کاغذ', 'Kertas', 'Papier');

  String get cardPhoto => _t('Your photo', 'صورتك', 'آپ کی تصویر',
      'Fotomu', 'Dein Foto');

  String get cardScenery =>
      _t('Scenery', 'المشاهد', 'مناظر', 'Pemandangan', 'Kulissen');

  /// Shown once, quietly, under a card that is still standing on
  /// paper. The scenery library is what a card is most transformed by
  /// and the one thing nobody thinks to look for — see the glowing
  /// chip in the ground panel, which is the same argument.
  String get cardSceneryNote => _t(
      'Pick your own scenery',
      'اختر مشهدك بنفسك',
      'اپنا منظر خود چنیں',
      'Pilih pemandanganmu sendiri',
      'Wähle deine eigene Kulisse');

  String get cardUndo =>
      _t('Undo', 'تراجع', 'واپس', 'Urungkan', 'Rückgängig');

  String get cardRedo =>
      _t('Redo', 'إعادة', 'دوبارہ', 'Ulangi', 'Wiederholen');

  String get cardSaveToGallery => _t('Save', 'حفظ', 'محفوظ کریں', 'Simpan',
      'Speichern');

  String get cardShare =>
      _t('Share', 'مشاركة', 'شیئر', 'Bagikan', 'Teilen');

  String cardSavedToGallery(int n) => _t(
      n == 1 ? 'Saved to your gallery' : 'Saved $n cards to your gallery',
      n == 1 ? 'حُفظت في معرض صورك' : 'حُفظت ${cardCount(n)} في معرض صورك',
      n == 1 ? 'گیلری میں محفوظ ہو گیا' : '$n کارڈز گیلری میں محفوظ ہو گئے',
      n == 1 ? 'Tersimpan di galeri' : '$n kartu tersimpan di galeri',
      n == 1
          ? 'In deiner Galerie gespeichert'
          : '$n Karten in deiner Galerie gespeichert');

  String get cardExporting => _t('Making your cards…', 'نجهّز بطاقاتك…',
      'آپ کے کارڈز تیار ہو رہے ہیں…', 'Menyiapkan kartumu…',
      'Deine Karten werden erstellt …');

  String get cardExportFailed => _t('Could not make the cards',
      'تعذّر إنشاء البطاقات', 'کارڈز نہیں بن سکے',
      'Kartu tidak bisa dibuat', 'Karten konnten nicht erstellt werden');

  String get cardDeckFull => _t('A carousel holds ten cards',
      'لا يتّسع العرض لأكثر من عشر بطاقات', 'ایک کیروسل میں دس کارڈ آتے ہیں',
      'Satu carousel memuat sepuluh kartu',
      'Ein Karussell fasst zehn Karten');

  String get cardSplit => _t('Split into cards', 'قسّمها إلى بطاقات',
      'کارڈز میں تقسیم کریں', 'Pecah jadi beberapa kartu',
      'In Karten aufteilen');

  String get cardWithTranslation => _t('Translation', 'الترجمة', 'ترجمہ',
      'Terjemahan', 'Übersetzung');

  String get cardWithReference => _t('Reference', 'المرجع', 'حوالہ',
      'Rujukan', 'Quelle');

  /// The designed starting points, by [CardTemplate.name].
  String cardTemplateName(String name) => switch (name) {
        'classic' =>
          _t('Classic', 'كلاسيكية', 'کلاسیکی', 'Klasik', 'Klassisch'),
        'scenery' =>
          _t('Scenery', 'مشهد', 'منظر', 'Pemandangan', 'Kulisse'),
        'page' => _t('Page', 'صفحة', 'صفحہ', 'Halaman', 'Seite'),
        'gilded' => _t('Gilded', 'مذهّبة', 'سنہری', 'Emas', 'Vergoldet'),
        'quiet' => _t('Quiet', 'هادئة', 'سادہ', 'Tenang', 'Ruhig'),
        'mihrab' => _t('Mihrab', 'محراب', 'محراب', 'Mihrab', 'Mihrab'),
        _ => name,
      };

  /// The borders, by [CardFrame.name].
  String cardFrameName(String name) => switch (name) {
        'none' => _t('None', 'بلا', 'کوئی نہیں', 'Tanpa', 'Ohne'),
        'hairline' =>
          _t('Rule', 'خط', 'لکیر', 'Garis', 'Linie'),
        'double_' =>
          _t('Double', 'خطان', 'دوہری لکیر', 'Ganda', 'Doppelt'),
        'corners' => _t('Corners', 'زوايا', 'کونے', 'Sudut', 'Ecken'),
        'khatam' => _t('Seal', 'ختم', 'مہر', 'Segel', 'Siegel'),
        'arch' => _t('Arch', 'قوس', 'محراب', 'Lengkung', 'Bogen'),
        'panel' => _t('Panel', 'لوح', 'پینل', 'Panel', 'Tafel'),
        'gilt' => _t('Gilt', 'مذهّب', 'سنہرا', 'Sepuh', 'Vergoldet'),
        'glass' => _t('Glass', 'زجاج', 'شیشہ', 'Kaca', 'Glas'),
        'layers' => _t('Layers', 'طبقات', 'تہیں', 'Lapisan', 'Lagen'),
        'glow' => _t('Glow', 'وهج', 'چمک', 'Pendar', 'Leuchten'),
        'girih' => _t('Girih', 'عقدة', 'گرہ', 'Girih', 'Girih'),
        'zellige' => _t('Zellige', 'زليج', 'زلیج', 'Zellige', 'Zellige'),
        'lattice' => _t('Lattice', 'مشربية', 'جالی', 'Kisi', 'Gitter'),
        'arabesque' => _t('Arabesque', 'أرابيسك', 'عربسک', 'Arabes', 'Arabeske'),
        'cartouche' => _t('Cartouche', 'خرطوشة', 'کارتوش', 'Kartus', 'Kartusche'),
        'stars' => _t('Stars', 'نجوم', 'ستارے', 'Bintang', 'Sterne'),
        _ => name,
      };

  /// The grounds, by [CardPaper.name].
  String cardPaperName(String name) => switch (name) {
        'night' => _t('Night', 'ليل', 'رات', 'Malam', 'Nacht'),
        'ivory' => _t('Ivory', 'عاجي', 'عاجی', 'Gading', 'Elfenbein'),
        'sand' => _t('Sand', 'رملي', 'ریتلا', 'Pasir', 'Sand'),
        'olive' => _t('Olive', 'زيتوني', 'زیتونی', 'Zaitun', 'Oliv'),
        'ink' => _t('Ink', 'حبر', 'سیاہی', 'Tinta', 'Tinte'),
        'sea' => _t('Sea', 'بحري', 'سمندری', 'Laut', 'Meer'),
        'rose' => _t('Rose', 'وردي', 'گلابی', 'Mawar', 'Rosé'),
        'gilt' => _t('Gilt', 'ذهبي', 'طلائی', 'Emas', 'Gold'),
        _ => name,
      };

  /// How a block of words is lifted off its ground, by [CardSkin.name].
  String cardSkinName(String name) => switch (name) {
        'none' => _t('Plain', 'بلا', 'سادہ', 'Polos', 'Schlicht'),
        'shadow' => _t('Shadow', 'ظل', 'سایہ', 'Bayangan', 'Schatten'),
        'glow' => _t('Glow', 'وهج', 'چمک', 'Cahaya', 'Schein'),
        'plate' => _t('Plate', 'لوح', 'تختی', 'Bidang', 'Platte'),
        'rule' => _t('Rule', 'فاصل', 'لکیر', 'Garis', 'Linie'),
        _ => name,
      };

  /// The three shapes, by [CardFormat.name].
  String cardFormatName(String name) => switch (name) {
        'square' => _t('Square', 'مربّع', 'مربع', 'Persegi', 'Quadrat'),
        'portrait' => _t('Post', 'منشور', 'پوسٹ', 'Postingan', 'Post'),
        'story' => _t('Story', 'ستوري', 'اسٹوری', 'Story', 'Story'),
        _ => name,
      };

  // ---- finding the words -------------------------------------------

  String get findTitle => _t('Find the words', 'ابحث عن النص',
      'الفاظ تلاش کریں', 'Cari teksnya', 'Worte finden');

  String get findQuran =>
      _t('Quran', 'القرآن', 'قرآن', 'Al-Qur’an', 'Koran');

  String get findHadith =>
      _t('Hadith', 'الحديث', 'حدیث', 'Hadis', 'Hadith');

  String get findQuranHint => _t('A word or two of the verse',
      'كلمة أو كلمتان من الآية', 'آیت کا ایک دو لفظ',
      'Satu dua kata dari ayatnya', 'Ein, zwei Wörter des Verses');

  String get findHadithHint => _t('A word or two of the hadith',
      'كلمة أو كلمتان من الحديث', 'حدیث کا ایک دو لفظ',
      'Satu dua kata dari hadisnya', 'Ein, zwei Wörter des Hadith');

  String get findNothing => _t('Nothing found', 'لا نتائج', 'کچھ نہیں ملا',
      'Tidak ditemukan', 'Nichts gefunden');

  String get findTypeMore => _t('Type a little more', 'اكتب المزيد',
      'کچھ اور لکھیے', 'Ketik sedikit lagi', 'Schreib noch etwas');

  String get findWhole =>
      _t('All of it', 'كامل النص', 'پورا متن', 'Seluruhnya', 'Ganz');

  String get findPart =>
      _t('Part of it', 'جزء منه', 'کچھ حصہ', 'Sebagian', 'Ein Teil');

  String get findPartHint => _t('Tap the first word, then the last',
      'اضغط الكلمة الأولى ثم الأخيرة', 'پہلا لفظ چھوئیں، پھر آخری',
      'Ketuk kata pertama, lalu yang terakhir',
      'Tippe das erste Wort an, dann das letzte');

  String get findAdd => _t('Add to card', 'أضف إلى البطاقة',
      'کارڈ میں شامل کریں', 'Tambahkan ke kartu', 'Zur Karte hinzufügen');

  String get findOpening => _t('Opening the library…', 'نفتح المكتبة…',
      'لائبریری کھل رہی ہے…', 'Membuka pustaka…', 'Bibliothek wird geöffnet …');

  String findCredit(String edition) => _t(
      'Translation: $edition',
      'الترجمة: $edition',
      'ترجمہ: $edition',
      'Terjemahan: $edition',
      'Übersetzung: $edition');

  String a11yAyah(int number) => _t('Verse $number', 'الآية $number',
      'آیت $number', 'Ayat $number', 'Vers $number');

  String get findChooseSurah =>
      _t('Change', 'تغيير', 'بدلیں', 'Ganti', 'Ändern');

  String get findArabicOnly => _t(
      'No connection: the Arabic is here, the translation is not.',
      'لا اتصال: النص العربي متاح والترجمة لا.',
      'انٹرنیٹ نہیں: عربی متن موجود ہے، ترجمہ نہیں۔',
      'Tidak ada koneksi: teks Arabnya ada, terjemahannya belum.',
      'Keine Verbindung: der arabische Text ist da, die Übersetzung nicht.');

  String a11ySurahCount(int ayahs) => _t(
      '$ayahs verses',
      '$ayahs آية',
      '$ayahs آیات',
      '$ayahs ayat',
      '$ayahs Verse');

  String get findBrowse =>
      _t('Browse', 'تصفّح', 'دیکھیں', 'Jelajahi', 'Stöbern');

  String findGrading(String grade) => _t('Grading: $grade',
      'الدرجة: $grade', 'درجہ: $grade', 'Derajat: $grade', 'Einstufung: $grade');

  /// What a hadith library topic is called.
  String hadithTopicName(String id) => switch (id) {
        'mercy' => _t('Mercy', 'الرحمة', 'رحمت', 'Kasih sayang',
            'Barmherzigkeit'),
        'prayer' => _t('Prayer', 'الصلاة', 'نماز', 'Salat', 'Gebet'),
        'charity' => _t('Charity', 'الصدقة', 'صدقہ', 'Sedekah',
            'Wohltätigkeit'),
        'knowledge' =>
          _t('Knowledge', 'العلم', 'علم', 'Ilmu', 'Wissen'),
        'patience' => _t('Patience', 'الصبر', 'صبر', 'Sabar', 'Geduld'),
        'parents' => _t('Parents', 'الوالدان', 'والدین', 'Orang tua',
            'Eltern'),
        'kindness' => _t('Kindness', 'الإحسان', 'حسن سلوک', 'Kebaikan',
            'Güte'),
        'gratitude' => _t('Gratitude', 'الشكر', 'شکر', 'Syukur',
            'Dankbarkeit'),
        'dhikr' => _t('Remembrance', 'الذكر', 'ذکر', 'Zikir', 'Gedenken'),
        'quran' => _t('Quran', 'القرآن', 'قرآن', 'Al-Qur’an', 'Koran'),
        'forgiveness' => _t('Forgiveness', 'المغفرة', 'مغفرت', 'Ampunan',
            'Vergebung'),
        'brotherhood' => _t('Brotherhood', 'الأخوّة', 'بھائی چارہ',
            'Persaudaraan', 'Brüderlichkeit'),
        'character' => _t('Character', 'الأخلاق', 'اخلاق', 'Akhlak',
            'Charakter'),
        'paradise' => _t('Paradise', 'الجنة', 'جنت', 'Surga', 'Paradies'),
        'faith' => _t('Faith', 'الإيمان', 'ایمان', 'Iman', 'Glaube'),
        'dua' => _t('Supplication', 'الدعاء', 'دعا', 'Doa', 'Bittgebet'),
        'time' => _t('Times', 'الأوقات', 'اوقات', 'Waktu', 'Zeiten'),
        'hardship' => _t('Hardship', 'الشدّة', 'مشکل', 'Kesulitan',
            'Not'),
        _ => id,
      };

  /// What a hadith collection is called. The Arabic-script languages
  /// read the collection's own Arabic name; the rest read the English
  /// transliteration, which is what those editions print.
  String hadithCollectionName(String id) => switch (id) {
        'bukhari' => _t('Sahih al-Bukhari', 'صحيح البخاري', 'صحیح بخاری',
            'Sahih al-Bukhari', 'Sahih al-Buchari'),
        'muslim' => _t('Sahih Muslim', 'صحيح مسلم', 'صحیح مسلم',
            'Sahih Muslim', 'Sahih Muslim'),
        'nawawi' => _t("An-Nawawi's Forty", 'الأربعون النووية',
            'اربعین نووی', 'Empat Puluh Hadis an-Nawawi',
            'Die vierzig Hadithe an-Nawawis'),
        'qudsi' => _t('Forty Hadith Qudsi', 'الأربعون القدسية',
            'چالیس احادیث قدسی', 'Empat Puluh Hadis Qudsi',
            'Vierzig Hadithe Qudsi'),
        'tirmidhi' => _t('Jami at-Tirmidhi', 'جامع الترمذي', 'جامع ترمذی',
            'Jami at-Tirmidzi', 'Dschami at-Tirmidhi'),
        'abudawud' => _t('Sunan Abu Dawud', 'سنن أبي داود', 'سنن ابو داؤد',
            'Sunan Abu Dawud', 'Sunan Abu Dawud'),
        'nasai' => _t("Sunan an-Nasa'i", 'سنن النسائي', 'سنن نسائی',
            "Sunan an-Nasa'i", 'Sunan an-Nasai'),
        'ibnmajah' => _t('Sunan Ibn Majah', 'سنن ابن ماجه', 'سنن ابن ماجہ',
            'Sunan Ibnu Majah', 'Sunan Ibn Madscha'),
        'malik' => _t('Muwatta Malik', 'موطأ مالك', 'موطأ امام مالک',
            'Muwatta Malik', 'Muwatta Malik'),
        _ => id,
      };

  /// The reference printed on a card and under a result.
  String hadithReference(String collection, int number) =>
      '${hadithCollectionName(collection)} $number';

  /// What a card prints under a verse: the surah as the reader names
  /// it, then chapter and verse the way every edition numbers them.
  ///
  /// Not [verseReference], which is the home screen's caption and
  /// leaves the surah number out — on a card the reference is the
  /// whole of what lets a stranger find the verse again, and "255" on
  /// its own finds nothing.
  String cardVerseReference(String surahName, int surah, int start, int end) {
    final name = localizedSurahName(surahName);
    final range = end == start ? '$start' : '$start–$end';
    return '$name · $surah:$range';
  }

  // ---- what a reader hears -----------------------------------------

  String get a11yCardPreview => _t('Card preview', 'معاينة البطاقة',
      'کارڈ کا پیش منظر', 'Pratinjau kartu', 'Kartenvorschau');

  String a11yCardBlock(String text) => _t('Words: $text',
      'الكلمات: $text', 'الفاظ: $text', 'Kata: $text', 'Worte: $text');

  String get a11ySelectsBlock => _t('Selects it to move and restyle',
      'يحدّدها للتحريك وتغيير الشكل', 'منتخب کر کے ہلائیں یا انداز بدلیں',
      'Memilihnya untuk dipindah dan diubah',
      'Wählt sie aus, zum Verschieben und Umgestalten');

  String get a11yOpensCard => _t('Opens the card', 'يفتح البطاقة',
      'کارڈ کھولتا ہے', 'Membuka kartu', 'Öffnet die Karte');

  String get a11yAddsToCard => _t('Puts it on the card',
      'يضعه على البطاقة', 'کارڈ پر رکھتا ہے', 'Menaruhnya di kartu',
      'Setzt es auf die Karte');

  String get a11yCardWord => _t('Word', 'كلمة', 'لفظ', 'Kata', 'Wort');

  String a11yCardsInDeck(int n) => _t('$n in this set',
      '$n في هذه المجموعة', 'اس سیٹ میں $n', '$n dalam set ini',
      '$n in diesem Satz');


  // ===================================================================
  // Made for somebody
  //
  // A reel or a card can be dedicated: a gift for somebody who will
  // see it, or sadaqah jariyah on behalf of somebody — most often
  // somebody who has died. The line below is drawn on the reel and on
  // the card, above the app's own mark, and it is the one piece of
  // wording the app puts into somebody else's hands.
  // ===================================================================

  /// The line the reel or the card carries. [name] is what the user
  /// typed; everything around it is this app's.
  String dedicationLine(DedicationKind kind, String name) =>
      switch (kind) {
        DedicationKind.gift => _t(
            'A gift for $name',
            'هدية إلى $name',
            '$name کے لیے تحفہ',
            'Hadiah untuk $name',
            'Ein Geschenk für $name'),
        DedicationKind.sadaqah => _t(
            'Sadaqah jariyah for $name',
            'صدقة جارية عن $name',
            '$name کے لیے صدقہ جاریہ',
            'Sedekah jariah untuk $name',
            'Sadaqa Jariya für $name'),
      };

  String get makeTitle => _t('Make it', 'اصنعها', 'بنائیں',
      'Buat sesuatu', 'Etwas machen');

  String get makeBlurb => _t(
      'A video to post, or a card to send. The verse is already chosen.',
      'فيديو للنشر أو بطاقة للإرسال. الآية مختارة بالفعل.',
      'پوسٹ کے لیے ویڈیو، یا بھیجنے کے لیے کارڈ۔ آیت پہلے سے منتخب ہے۔',
      'Video untuk diunggah, atau kartu untuk dikirim. Ayatnya sudah dipilih.',
      'Ein Video zum Posten oder eine Karte zum Senden. Der Vers steht schon '
          'fest.');

  String get makeReel => _t('A video', 'فيديو', 'ویڈیو', 'Video', 'Ein Video');

  String get makeReelHint => _t('Recited, with a moving picture',
      'بصوت القارئ وصورة متحركة', 'تلاوت کے ساتھ، چلتی تصویر پر',
      'Dilantunkan, dengan gambar bergerak',
      'Rezitiert, mit bewegtem Bild');

  String get makeCard => _t('A card', 'بطاقة', 'کارڈ', 'Kartu', 'Eine Karte');

  String get makeCardHint => _t('A still, ready in seconds',
      'صورة ثابتة تجهز في ثوانٍ', 'ایک ساکن تصویر، سیکنڈوں میں تیار',
      'Gambar diam, jadi dalam hitungan detik',
      'Ein Standbild, in Sekunden fertig');

  /// The last card of a deck: who made it, and what with.
  ///
  /// The maker's name leads. "Made by Yusuf" is a thing a friend keeps
  /// and a stranger wants one of; "made with AyahReel" alone is an
  /// advertisement, and an advertisement is what gets cropped off
  /// before a carousel is posted.
  String inviteMadeBy(String name) => _t(
      'made by $name',
      'من صنع $name',
      '$name کی طرف سے',
      'dibuat oleh $name',
      'gemacht von $name');

  String get inviteWith => _t('with AyahReel', 'بتطبيق AyahReel',
      'AyahReel سے', 'dengan AyahReel', 'mit AyahReel');

  String get inviteCardRow => _t('Last card: the invite',
      'البطاقة الأخيرة: الدعوة', 'آخری کارڈ: دعوت',
      'Kartu terakhir: undangan', 'Letzte Karte: die Einladung');

  String get inviteCardOff => _t('Last card: off', 'بلا بطاقة أخيرة',
      'آخری کارڈ: بند', 'Tanpa kartu terakhir', 'Ohne letzte Karte');

  /// The card composer's own door to Instagram's story camera. Named
  /// with its "To", and painted in Instagram's colours, so it reads as
  /// the same door the invite sheet opens rather than as one more
  /// Share — see [instagramMesh].
  String get shareToStory => _t('To story', 'إلى الستوري', 'اسٹوری پر',
      'Ke story', 'Zur Story');

  String get dedicateRow => _t('Make it for someone', 'اجعله لشخص',
      'کسی کے نام کریں', 'Buat untuk seseorang', 'Für jemanden machen');

  String get dedicateTitle => _t('Who is it for?', 'لمن هذا؟',
      'یہ کس کے لیے ہے؟', 'Untuk siapa ini?', 'Für wen ist das?');

  String get dedicateBlurb => _t(
      'Their name goes on it, quietly, above the mark — and whoever you '
          'send it to sees who it was made for.',
      'يُكتب اسمه بهدوء فوق العلامة، ويراه كل من ترسله إليه.',
      'ان کا نام نشان کے اوپر آہستگی سے لکھا جائے گا — اور جسے بھی آپ '
          'بھیجیں گے وہ دیکھے گا کہ یہ کس کے لیے بنا۔',
      'Namanya tertulis dengan tenang di atas tanda — dan siapa pun yang '
          'kamu kirimi akan tahu ini dibuat untuk siapa.',
      'Der Name steht leise darüber, über dem Zeichen — und wer es '
          'bekommt, sieht, für wen es gemacht wurde.');

  String get dedicateGift =>
      _t('A gift', 'هدية', 'تحفہ', 'Hadiah', 'Ein Geschenk');

  String get dedicateSadaqah => _t('Sadaqah jariyah', 'صدقة جارية',
      'صدقہ جاریہ', 'Sedekah jariah', 'Sadaqa Jariya');

  String get dedicateGiftHint => _t(
      'For someone who will see it.',
      'لشخص سيراه.',
      'اُس کے لیے جو اسے دیکھے گا۔',
      'Untuk orang yang akan melihatnya.',
      'Für jemanden, der es sehen wird.');

  String get dedicateSadaqahHint => _t(
      'On behalf of someone — so the reward carries on.',
      'عن شخص، ليجري له الأجر.',
      'کسی کی طرف سے — تاکہ اجر جاری رہے۔',
      'Atas nama seseorang — agar pahalanya terus mengalir.',
      'Im Namen von jemandem — damit der Lohn weiterläuft.');

  String get dedicateNameHint => _t('Their name', 'الاسم', 'اُن کا نام',
      'Namanya', 'Der Name');

  /// Under the line in the sheet: it can be moved once it is on the
  /// reel, and put back.
  String get dedicateMoveHint => _t(
      'On a reel, drag the line to place it anywhere. Double-tap it to put it back.',
      'على المقطع، اسحب السطر لتضعه حيث تشاء، وانقر عليه مرتين لإعادته.',
      'ریل پر سطر کو گھسیٹ کر جہاں چاہیں رکھیں، دو بار تھپتھپا کر واپس لائیں۔',
      'Di reel, geser barisnya ke mana saja. Ketuk dua kali untuk mengembalikannya.',
      'Im Reel die Zeile beliebig verschieben, doppelt tippen setzt sie zurück.');

  String get dedicateNameMissing => _t('A name first', 'اكتب الاسم أولًا',
      'پہلے نام لکھیے', 'Tulis namanya dulu', 'Erst der Name');

  String get dedicateDone => _t('Dedicated', 'تم الإهداء', 'نام ہو گیا',
      'Sudah didedikasikan', 'Gewidmet');

  /// What goes with the file when a dedicated reel or card is shared.
  ///
  /// It speaks to whoever receives it, and it carries the two store
  /// links — a gift somebody cannot answer with one of their own is a
  /// gift that stops where it lands.
  String dedicationShareMessage(DedicationKind kind, String name) =>
      switch (kind) {
        DedicationKind.gift => _t(
            '🎁 $name — I made this for you. 🤍\n\n'
                '✨ Made with AyahReel. Make one back:\n'
                'iPhone: $appStoreUrl\n'
                'Android: $playStoreUrl',
            '🎁 $name — صنعت لك هذا. 🤍\n\n'
                '✨ صُنع بتطبيق AyahReel، اصنع واحدًا وأهده:\n'
                'آيفون: $appStoreUrl\n'
                'أندرويد: $playStoreUrl',
            '🎁 $name — یہ میں نے آپ کے لیے بنایا ہے۔ 🤍\n\n'
                '✨ AyahReel سے بنایا گیا۔ آپ بھی بنائیں:\n'
                'آئی فون: $appStoreUrl\n'
                'اینڈرائیڈ: $playStoreUrl',
            '🎁 $name — ini kubuat untukmu. 🤍\n\n'
                '✨ Dibuat dengan AyahReel. Buat juga untukku:\n'
                'iPhone: $appStoreUrl\n'
                'Android: $playStoreUrl',
            '🎁 $name — das habe ich für dich gemacht. 🤍\n\n'
                '✨ Gemacht mit AyahReel. Mach auch eins:\n'
                'iPhone: $appStoreUrl\n'
                'Android: $playStoreUrl'),
        DedicationKind.sadaqah => _t(
            '🤲 Sadaqah jariyah for $name. Pass it on — every share carries '
                'its reward further.\n\n'
                '✨ Made with AyahReel:\n'
                'iPhone: $appStoreUrl\n'
                'Android: $playStoreUrl',
            '🤲 صدقة جارية عن $name. شاركه، فكل مشاركة تحمل أجره أبعد.\n\n'
                '✨ صُنع بتطبيق AyahReel:\n'
                'آيفون: $appStoreUrl\n'
                'أندرويد: $playStoreUrl',
            '$name کے لیے صدقہ جاریہ۔ آگے بھیجیے — ہر شیئر اجر کو اور '
                'آگے لے جاتا ہے۔\n\n'
                'AyahReel سے بنایا گیا:\n'
                'آئی فون: $appStoreUrl\n'
                'اینڈرائیڈ: $playStoreUrl',
            'Sedekah jariah untuk $name. Teruskan — setiap kali dibagikan, '
                'pahalanya mengalir lebih jauh.\n\n'
                'Dibuat dengan AyahReel:\n'
                'iPhone: $appStoreUrl\n'
                'Android: $playStoreUrl',
            'Sadaqa Jariya für $name. Gib es weiter — jedes Teilen trägt '
                'den Lohn weiter.\n\n'
                'Gemacht mit AyahReel:\n'
                'iPhone: $appStoreUrl\n'
                'Android: $playStoreUrl'),
      };

  String a11yDedication(String line) => _t(
      'Made for someone: $line',
      'مُهدى: $line',
      'کسی کے نام: $line',
      'Dibuat untuk seseorang: $line',
      'Für jemanden gemacht: $line');

  String get a11yOpensDedication => _t(
      'Says who this was made for',
      'يحدد لمن صُنع هذا',
      'بتاتا ہے کہ یہ کس کے لیے بنا',
      'Menentukan untuk siapa ini dibuat',
      'Legt fest, für wen das gemacht ist');

  // ===================================================================
  // Things you may not have found
  // ===================================================================

  String get discoverRow => _t('Things you may not have found',
      'أشياء قد لا تكون وجدتها', 'وہ باتیں جو شاید آپ نے نہ دیکھی ہوں',
      'Hal yang mungkin belum kamu temukan',
      'Dinge, die du vielleicht noch nicht kennst');

  String get discoverTitle => _t('Hidden in plain sight',
      'ظاهرٌ ولا يُنتبه له', 'سامنے ہی چھپی ہوئی باتیں',
      'Tersembunyi di depan mata', 'Versteckt, aber sichtbar');

  String get discoverBlurb => _t(
      'Small things the app does that nobody would guess. Nothing here '
          'needs setting up — it already works.',
      'أمور صغيرة يفعلها التطبيق ولا يخطر ببال أحد. لا شيء هنا يحتاج '
          'إعدادًا، كلّه يعمل الآن.',
      'چھوٹی چھوٹی باتیں جو ایپ کرتی ہے مگر کسی کے خیال میں نہیں آتیں۔ '
          'کچھ ترتیب دینے کی ضرورت نہیں — یہ سب پہلے سے کام کرتا ہے۔',
      'Hal-hal kecil yang bisa dilakukan aplikasi ini tanpa orang tahu. '
          'Tidak ada yang perlu disetel — semuanya sudah aktif.',
      'Kleine Dinge, die die App kann und die niemand erraten würde. '
          'Nichts davon muss eingerichtet werden — es funktioniert schon.');

  /// Title and body of each discovery, by [Discovery.id]. Written as
  /// one switch rather than a pair of getters each, so a new discovery
  /// is one block of text in five languages and not two.
  (String, String) discovery(String id) => switch (id) {
        'verse-to-reel' => (
            _t('Tap the verse on Home',
                'اضغط الآية في الرئيسية',
                'ہوم پر آیت دبائیں',
                'Ketuk ayat di Beranda',
                'Tippe auf den Vers der Startseite'),
            _t(
                'It starts a reel of that verse, or a card, with the verse already in it.',
                'يبدأ به مقطعًا لتلك الآية، أو بطاقة، والآية فيها من الآن.',
                'اسی آیت کی ریل یا کارڈ شروع ہو جاتا ہے، آیت پہلے سے اس میں ہوتی ہے۔',
                'Langsung memulai reel atau kartu dari ayat itu, ayatnya sudah ada di dalamnya.',
                'Es beginnt ein Reel oder eine Karte zu diesem Vers, der Vers ist schon drin.'),
          ),
        'hold-to-extend' => (
            _t('Hold a verse to select up to it',
                'اضغط مطوّلًا لتختار حتى آية',
                'آیت دبا کر رکھیں تو وہاں تک چن لی جائیں',
                'Tahan satu ayat untuk memilih sampai ke sana',
                'Halte einen Vers, um bis dorthin zu wählen'),
            _t(
                'In the verse list a tap adds one verse; press and hold a later one to take every verse up to it.',
                'في قائمة الآيات تضيف النقرة آية واحدة؛ واضغط مطوّلًا على آية لاحقة لتختار كل ما قبلها.',
                'آیات کی فہرست میں ایک ٹیپ ایک آیت بڑھاتا ہے؛ آگے کی آیت دبا کر رکھیں تو وہاں تک سب چن لی جاتی ہیں۔',
                'Di daftar ayat, sekali ketuk menambah satu ayat; tahan ayat yang lebih jauh untuk memilih semua sampai ke sana.',
                'In der Versliste fügt ein Tippen einen Vers hinzu; halte einen späteren, um alle bis dorthin zu wählen.'),
          ),
        'blur-backdrop' => (
            _t('The wide card can stand in its own light',
                'البطاقة العريضة تقف في ضوئها',
                'چوڑا کارڈ اپنی ہی روشنی میں',
                'Kartu lebar bisa berdiri dalam cahayanya sendiri',
                'Die breite Karte steht in ihrem eigenen Licht'),
            _t(
                'Choose the wide frame in the scenery step and the bands '
                    'above and below can be filled with the same scenery, '
                    'blurred — instead of flat black.',
                'اختر الإطار العريض في خطوة المشاهد، فيمكن ملء الشريطين '
                    'أعلى وأسفل بالمشهد نفسه مضبَّبًا بدل السواد.',
                'مناظر والے مرحلے میں چوڑا فریم چنیں تو اوپر نیچے کی پٹیاں '
                    'اسی منظر سے، دھندلا کر کے بھری جا سکتی ہیں — سادہ کالے '
                    'کی جگہ۔',
                'Pilih bingkai lebar di langkah pemandangan, lalu bidang '
                    'atas dan bawah bisa diisi pemandangan yang sama, dibuat '
                    'buram — bukan hitam polos.',
                'Wähl im Kulissen-Schritt den breiten Rahmen: Die Balken '
                    'oben und unten lassen sich mit derselben Kulisse füllen, '
                    'unscharf statt schwarz.'),
          ),
        'scene-match' => (
            _t('Let the verses pick the scenery',
                'دع الآيات تختار المشهد',
                'آیات کو منظر چننے دیں',
                'Biarkan ayat memilih pemandangan',
                'Lass die Verse die Kulisse wählen'),
            _t(
                'Tap the spark at the start of the scenery tabs: it reads the verses and picks a picture for each.',
                'اضغط الشرارة في أول تبويبات المشاهد: تقرأ الآيات وتختار صورة لكل منها.',
                'مناظر کے ٹیبز کے شروع میں چمک دبائیں: یہ آیات پڑھ کر ہر ایک کے لیے تصویر چنتی ہے۔',
                'Ketuk percikan di awal tab pemandangan: ia membaca ayat dan memilih gambar untuk masing-masing.',
                'Tippe auf den Funken am Anfang der Kulissen-Tabs: Er liest die Verse und wählt zu jedem ein Bild.'),
          ),
        'reel-edit' => (
            _t('Change a finished reel',
                'عدّل مقطعًا جاهزًا',
                'تیار ریل میں تبدیلی کریں',
                'Ubah reel yang sudah jadi',
                'Ein fertiges Reel ändern'),
            _t(
                'Open it from My works and tap Edit again: every choice comes back as you left it.',
                'افتحه من «أعمالي» واضغط «عدّل مجددًا»: تعود كل اختياراتك كما تركتها.',
                '«میری تخلیقات» سے کھولیں اور «دوبارہ ترمیم» دبائیں: ہر انتخاب ویسا ہی لوٹ آتا ہے جیسا چھوڑا تھا۔',
                'Buka dari Karya saya lalu ketuk Edit lagi: semua pilihan kembali seperti saat kamu tinggalkan.',
                'Öffne es in „Meine Werke“ und tippe auf „Nochmal bearbeiten“: Alles ist wieder so, wie du es gelassen hast.'),
          ),
        'drag-verse' => (
            _t('The verse goes where you put it',
                'الآية تستقرّ حيث تضعها', 'آیت وہیں ٹھہرتی ہے جہاں رکھیں',
                'Ayat berhenti di tempat kamu menaruhnya',
                'Der Vers steht, wo du ihn hinsetzt'),
            _t(
                'In the preview, drag the verse up or down the frame. The '
                    'app mark follows it, so a crop can never take the mark '
                    'without taking the verse.',
                'في المعاينة، اسحب الآية أعلى الإطار أو أسفله. وعلامة '
                    'التطبيق تتبعها، فلا يمكن لقصٍّ أن يأخذ العلامة دون أن '
                    'يأخذ الآية.',
                'پیش منظر میں آیت کو اوپر نیچے کھینچیں۔ ایپ کا نشان اس کے '
                    'ساتھ چلتا ہے، سو کوئی کٹائی نشان کو آیت کے بغیر نہیں لے '
                    'جا سکتی۔',
                'Di pratinjau, geser ayat ke atas atau ke bawah. Tanda '
                    'aplikasi ikut bergerak, jadi pemotongan tak bisa '
                    'menghapus tanda tanpa memotong ayatnya.',
                'Zieh den Vers in der Vorschau nach oben oder unten. Das '
                    'App-Zeichen folgt ihm — ein Zuschnitt bekommt das '
                    'Zeichen nie ohne den Vers.'),
          ),
        'multi-scene' => (
            _t('One reel, several sceneries', 'مقطع واحد بمشاهد عدّة',
                'ایک ریل، کئی مناظر', 'Satu reel, beberapa pemandangan',
                'Ein Reel, mehrere Kulissen'),
            _t(
                'Turn on the pill above the grid and the tiles take numbers '
                    'instead of a tick: the reel runs through them in the '
                    'order you tapped.',
                'شغّل الزر فوق الشبكة فتأخذ المربّعات أرقامًا بدل العلامة، '
                    'ويمرّ المقطع عليها بترتيب ضغطك.',
                'گرڈ کے اوپر والا بٹن چالو کریں تو خانوں پر ٹک کی جگہ نمبر آ '
                    'جاتے ہیں: ریل انہی کی ترتیب سے چلتی ہے۔',
                'Nyalakan pil di atas kisi, ubin akan bernomor alih-alih '
                    'bercentang: reel melewatinya sesuai urutan ketukanmu.',
                'Schalt die Pille über dem Raster ein: Die Kacheln bekommen '
                    'Nummern statt Häkchen, und das Reel läuft in deiner '
                    'Tippreihenfolge durch sie.'),
          ),
        'verse-choice' => (
            _t('The verse asks what to make of it',
                'الآية تسألك ماذا تصنع بها',
                'آیت پوچھتی ہے کہ اس کا کیا بنانا ہے',
                'Ayat itu bertanya, mau dijadikan apa',
                'Der Vers fragt, was daraus werden soll'),
            _t(
                'Tapping the verse on Home offers both: a reel to post, or '
                    'a card to send. Whichever you pick, the verse is '
                    'already in it.',
                'اضغط آية الرئيسية فتُعرض عليك الاثنتان: مقطع للنشر أو بطاقة '
                    'للإرسال، والآية جاهزة في كليهما.',
                'ہوم پر آیت چھونے سے دونوں پیش ہوتے ہیں: پوسٹ کے لیے ریل، یا '
                    'بھیجنے کے لیے کارڈ۔ جو بھی چنیں، آیت اس میں پہلے سے ہے۔',
                'Ketuk ayat di Beranda dan keduanya ditawarkan: reel untuk '
                    'diunggah, atau kartu untuk dikirim — ayatnya sudah ada '
                    'di dalamnya.',
                'Tippe den Vers auf der Startseite an, und beides steht zur '
                    'Wahl: ein Reel zum Posten oder eine Karte zum Senden — '
                    'der Vers ist schon drin.'),
          ),
        'card-story' => (
            _t('A card becomes a story on the way out',
                'البطاقة تصير ستوري عند الخروج',
                'کارڈ باہر جاتے ہوئے اسٹوری بن جاتا ہے',
                'Kartu berubah jadi story saat dikirim',
                'Eine Karte wird unterwegs zur Story'),
            _t(
                'The Story button re-cuts the card to 9:16 rather than '
                    'letting Instagram box it, and lifts the mark clear of '
                    'the bar Instagram draws along the bottom.',
                'زر الستوري يعيد قص البطاقة إلى 9:16 بدل أن يؤطّرها إنستغرام، '
                    'ويرفع العلامة فوق الشريط الذي يرسمه أسفل الشاشة.',
                'اسٹوری کا بٹن کارڈ کو 9:16 میں دوبارہ کاٹتا ہے، اور نشان کو '
                    'انسٹاگرام کی نیچے والی پٹی سے اوپر اٹھا دیتا ہے۔',
                'Tombol Story memotong ulang kartu ke 9:16 alih-alih dikotak '
                    'oleh Instagram, dan menaikkan tanda di atas bilah bawah '
                    'Instagram.',
                'Der Story-Knopf schneidet die Karte auf 9:16 um, statt sie '
                    'von Instagram einrahmen zu lassen, und hebt das Zeichen '
                    'über Instagrams untere Leiste.'),
          ),
        'card-invite' => (
            _t('The last card carries your name',
                'البطاقة الأخيرة تحمل اسمك',
                'آخری کارڈ پر آپ کا نام ہوتا ہے',
                'Kartu terakhir membawa namamu',
                'Die letzte Karte trägt deinen Namen'),
            _t(
                'A deck ends with one more card in its own style — "made by '
                    'you", and the app under it. It is on the filmstrip '
                    'before you export, and one tap on it takes it off.',
                'تنتهي المجموعة ببطاقة أخرى بالنمط نفسه — "من صنعك" واسم '
                    'التطبيق تحته. تراها في الشريط قبل التصدير، وضغطة واحدة '
                    'عليها تزيلها.',
                'ڈیک ایک اور کارڈ پر ختم ہوتا ہے، اُسی انداز میں — «آپ کی طرف '
                    'سے»، نیچے ایپ کا نام۔ برآمد سے پہلے فلم اسٹرپ میں نظر '
                    'آتا ہے، اور ایک ٹیپ سے ہٹ جاتا ہے۔',
                'Satu set diakhiri satu kartu lagi dengan gaya yang sama — '
                    '"dibuat olehmu", dengan nama aplikasi di bawahnya. Sudah '
                    'terlihat di filmstrip sebelum diekspor, dan satu ketukan '
                    'menghapusnya.',
                'Ein Satz endet mit einer weiteren Karte im selben Stil — '
                    '„von dir gemacht“, darunter die App. Sie steht vor dem '
                    'Export im Filmstreifen, und ein Tipp nimmt sie weg.'),
          ),
        'card-streak' => (
            _t('A card keeps the streak too', 'البطاقة تحفظ المواظبة أيضًا',
                'کارڈ بھی تسلسل برقرار رکھتا ہے',
                'Kartu juga menjaga rentetanmu',
                'Auch eine Karte hält die Serie'),
            _t(
                'A day you only had a minute is still a day you made '
                    'something: saving or sharing a card advances the same '
                    'streak a reel does.',
                'اليوم الذي لم تملك فيه إلا دقيقة يبقى يومًا صنعت فيه شيئًا: '
                    'حفظ بطاقة أو مشاركتها يقدّم المواظبة كما يفعل المقطع.',
                'جس دن آپ کے پاس صرف ایک منٹ ہو، وہ بھی کچھ بنانے کا دن ہے: '
                    'کارڈ محفوظ کرنا یا شیئر کرنا وہی تسلسل بڑھاتا ہے جو ریل '
                    'بڑھاتی ہے۔',
                'Hari saat kamu cuma punya semenit tetap hari kamu membuat '
                    'sesuatu: menyimpan atau membagikan kartu menambah '
                    'rentetan yang sama seperti reel.',
                'Ein Tag mit nur einer Minute ist immer noch ein Tag, an dem '
                    'du etwas gemacht hast: Eine Karte zu speichern oder zu '
                    'teilen führt dieselbe Serie fort wie ein Reel.'),
          ),
        'card-part' => (
            _t('A card can quote a piece', 'البطاقة تقتبس جزءًا',
                'کارڈ ایک ٹکڑا بھی لے سکتا ہے',
                'Kartu bisa mengutip sepotong',
                'Eine Karte kann einen Teil zitieren'),
            _t(
                'In the finder, choose "Part of it": tap the first word and '
                    'then the last, and only what lies between them lands on '
                    'the card.',
                'في البحث اختر "جزء منه": اضغط الكلمة الأولى ثم الأخيرة، فلا '
                    'يصل إلى البطاقة إلا ما بينهما.',
                'تلاش میں «کچھ حصہ» چنیں: پہلا لفظ چھوئیں پھر آخری، اور صرف '
                    'ان کے درمیان کا حصہ کارڈ پر آئے گا۔',
                'Di pencarian, pilih "Sebagian": ketuk kata pertama lalu '
                    'yang terakhir — hanya yang di antaranya yang masuk ke '
                    'kartu.',
                'Wähl in der Suche „Ein Teil“: Tippe das erste und dann das '
                    'letzte Wort — nur was dazwischen liegt, kommt auf die '
                    'Karte.'),
          ),
        'card-carry' => (
            _t('Style one card, style them all',
                'نسّق بطاقةً واحدة، تُنسَّق البقيّة',
                'ایک کارڈ سجائیں، سب سج جائیں',
                'Tata satu kartu, semua ikut',
                'Gestalte eine Karte, gestalte alle'),
            _t(
                'Get one card right, then tap Apply to every card: the ground, frame and type move over, the words stay.',
                'اضبط بطاقة ثم اضغط «طبّق على كل البطاقات»: تنتقل الخلفية والإطار والخط، ويبقى النص.',
                'ایک کارڈ ٹھیک کریں، پھر «سب کارڈز پر لاگو کریں» دبائیں: پس منظر، فریم اور خط منتقل ہوتے ہیں، الفاظ وہی رہتے ہیں۔',
                'Rapikan satu kartu, lalu ketuk Terapkan ke semua kartu: latar, bingkai, dan huruf ikut pindah, katanya tetap.',
                'Bring eine Karte in Form und tippe auf „Auf alle Karten anwenden“: Grund, Rahmen und Schrift wandern mit, die Worte bleiben.'),
          ),
        'card-shape' => (
            _t('One card, three shapes', 'بطاقة واحدة بثلاثة مقاسات',
                'ایک کارڈ، تین سائز', 'Satu kartu, tiga ukuran',
                'Eine Karte, drei Formate'),
            _t(
                'Square, post or story — change the shape at any point and '
                    'everything on the card moves with it, because nothing '
                    'on it was ever measured in pixels.',
                'مربّع أو منشور أو ستوري — غيّر المقاس متى شئت وينتقل كل ما '
                    'على البطاقة معه، لأن لا شيء فيها قيس بالبكسل.',
                'مربع، پوسٹ یا اسٹوری — جب چاہیں سائز بدلیں، کارڈ کی ہر چیز '
                    'ساتھ چلتی ہے، کیونکہ اس پر کچھ بھی پکسل میں نہیں ناپا '
                    'گیا۔',
                'Persegi, postingan, atau story — ubah ukurannya kapan saja '
                    'dan semua di kartu ikut menyesuaikan, sebab tak ada yang '
                    'diukur dalam piksel.',
                'Quadrat, Post oder Story — ändere das Format jederzeit, '
                    'alles auf der Karte geht mit, denn nichts darauf wurde '
                    'je in Pixeln gemessen.'),
          ),
        'invite-anywhere' => (
            _t('The invitation is on every tab',
                'الدعوة في كل تبويب', 'دعوت ہر ٹیب پر موجود ہے',
                'Undangan ada di setiap tab',
                'Die Einladung ist auf jedem Tab'),
            _t(
                'The small floating spark passes the app on — as a message '
                    'or as a story card — and earns you a point a day for it.',
                'الشرارة الصغيرة العائمة تُهدي التطبيق لغيرك — رسالةً أو '
                    'بطاقة ستوري — وتكسب بها نقطة كل يوم.',
                'چھوٹی تیرتی چنگاری ایپ کو آگے بھیجتی ہے — پیغام کے طور پر یا '
                    'اسٹوری کارڈ کے طور پر — اور روزانہ ایک پوائنٹ دلاتی ہے۔',
                'Percikan kecil yang melayang itu membagikan aplikasi ini — '
                    'sebagai pesan atau kartu story — dan memberimu satu poin '
                    'sehari.',
                'Der kleine schwebende Funke gibt die App weiter — als '
                    'Nachricht oder Story-Karte — und bringt dir täglich '
                    'einen Punkt.'),
          ),
        'living-home' => (
            _t('Home changes its picture',
                'الرئيسية تغيّر صورتها',
                'ہوم اپنی تصویر بدلتا ہے',
                'Beranda berganti gambar',
                'Die Startseite wechselt ihr Bild'),
            _t(
                'A new place behind the greeting each time you open the app, from the whole library of sceneries.',
                'مكان جديد خلف التحية كلما فتحت التطبيق، من مكتبة المشاهد كلها.',
                'ہر بار ایپ کھولنے پر سلام کے پیچھے نئی جگہ، مناظر کے پورے ذخیرے سے۔',
                'Tempat baru di balik sapaan setiap kali aplikasi dibuka, dari seluruh pustaka pemandangan.',
                'Bei jedem Öffnen ein neuer Ort hinter der Begrüßung, aus der ganzen Kulissen-Bibliothek.'),
          ),
        'recordings' => (
            _t('A voice can have more than one recording',
                'قد يكون للقارئ أكثر من تسجيل',
                'ایک قاری کی ایک سے زیادہ ریکارڈنگز ہو سکتی ہیں',
                'Satu qari bisa punya lebih dari satu rekaman',
                'Eine Stimme kann mehrere Aufnahmen haben'),
            _t(
                'Tap a number under the name: the same reciter, another recitation. Reels of the same verses then sound different.',
                'اضغط رقمًا تحت الاسم: القارئ نفسه بتلاوة أخرى، فتختلف مقاطع الآيات نفسها في صوتها.',
                'نام کے نیچے کوئی نمبر دبائیں: وہی قاری، دوسری تلاوت۔ یوں ایک ہی آیات کی ریلز الگ سنائی دیتی ہیں۔',
                'Ketuk angka di bawah nama: qari yang sama, bacaan lain. Reel dari ayat yang sama jadi terdengar berbeda.',
                'Tippe auf eine Zahl unter dem Namen: derselbe Rezitator, eine andere Rezitation. So klingen Reels derselben Verse verschieden.'),
          ),
        'luminous' => (
            _t('Colours that glow',
                'ألوان تتوهّج',
                'چمکتے رنگ',
                'Warna yang bercahaya',
                'Farben, die leuchten'),
            _t(
                'In Make it yours: the first row under Colour, the colours under Motion, and the wide card’s Background. Swipe a row for more.',
                'في «اجعله على ذوقك»: الصف الأول تحت «اللون»، وألوان «الحركة»، و«الخلفية» في البطاقة العريضة. اسحب الصف لترى المزيد.',
                '«اسے اپنا بنائیں» میں: «رنگ» کی پہلی قطار، «حرکت» کے رنگ، اور چوڑے کارڈ کا «پس منظر»۔ مزید کے لیے قطار کھسکائیں۔',
                'Di Jadikan milikmu: baris pertama di Warna, warna di Gerak, dan Latar kartu lebar. Geser barisnya untuk melihat lebih banyak.',
                'In „Mach es zu deinem“: die erste Reihe unter Farbe, die Farben unter Bewegung und der Hintergrund der breiten Karte. Wisch für mehr.'),
          ),
        'size-on-reel' => (
            _t('Move and size the verse and the surah name',
                'حرّك الآية واسم السورة وغيّر حجمهما',
                'آیت اور سورت کا نام ہلائیں اور ان کا سائز بدلیں',
                'Geser dan ubah ukuran ayat dan nama surah',
                'Vers und Surenname verschieben und skalieren'),
            _t(
                'On the reel, drag them. Touch one to show its corners, then drag a corner, or pinch. A double tap puts it back.',
                'في المقطع اسحبهما. المس أحدهما لتظهر زواياه، ثم اسحب زاوية أو قرّب إصبعيك وباعدهما. والنقر مرتين يعيده كما كان.',
                'ریل پر انہیں کھینچیں۔ کسی کو چھوئیں تو اس کے کونے دکھائی دیں گے، پھر کونا کھینچیں یا چٹکی لیں۔ دو بار تھپتھپانے سے وہ واپس آ جاتا ہے۔',
                'Di reel, seret keduanya. Sentuh salah satunya untuk memunculkan sudutnya, lalu seret sudut atau cubit. Ketuk dua kali untuk mengembalikannya.',
                'Zieh sie im Reel. Berühre eines, damit seine Ecken erscheinen, dann zieh eine Ecke oder zieh mit zwei Fingern. Doppeltippen setzt es zurück.'),
          ),
        'offline' => (
            _t('Make reels with no internet',
                'اصنع مقاطع بلا إنترنت',
                'انٹرنیٹ کے بغیر ریلز بنائیں',
                'Buat reel tanpa internet',
                'Reels ohne Internet machen'),
            _t(
                'Settings → Customize → Download for offline keeps your voice, the text and the sceneries on the phone.',
                'الإعدادات ← تخصيص ← تنزيل للاستخدام دون إنترنت: يبقى صوت قارئك والنص والمشاهد على هاتفك.',
                'ترتیبات ← حسب ضرورت بنائیں ← آف لائن کے لیے ڈاؤن لوڈ: آپ کے قاری کی آواز، متن اور مناظر فون پر رہتے ہیں۔',
                'Pengaturan → Sesuaikan → Unduh untuk offline menyimpan suara qari, teks, dan pemandangan di ponsel.',
                'Einstellungen → Anpassen → Für offline laden behält deine Stimme, den Text und die Kulissen auf dem Handy.'),
          ),
        _ => (id, ''),
      };

  // ---- long verses, line by line ------------------------------------

  /// The Customize panel's first section: what happens to a verse too
  /// long for the frame.
  String get longVersesTitle => _t('Long verses', 'الآيات الطويلة',
      'لمبی آیات', 'Ayat panjang', 'Lange Verse');
  String get longVersesNote => _t(
      'How a verse too long for the frame appears',
      'كيف تظهر الآية الأطول من الإطار',
      'فریم سے لمبی آیت کیسے دکھائی دے',
      'Cara ayat yang terlalu panjang untuk bingkai ditampilkan',
      'Wie ein Vers erscheint, der zu lang für das Bild ist');
  String get versesWhole => _t('Whole verse', 'الآية كاملة', 'پوری آیت',
      'Ayat utuh', 'Ganzer Vers');
  String get versesWholeNote => _t('Shrinks to fit', 'تصغر لتتسع',
      'سمانے کے لیے چھوٹی ہو جاتی ہے', 'Mengecil agar muat',
      'Wird kleiner, bis er passt');
  String get versesLines => _t('Line by line', 'سطرًا سطرًا',
      'سطر بہ سطر', 'Baris demi baris', 'Zeile für Zeile');
  String get versesLinesNote => _t(
      'Each line as it is recited',
      'كل سطر حين يُتلى',
      'ہر سطر جب پڑھی جائے',
      'Setiap baris saat dibacakan',
      'Jede Zeile, während sie rezitiert wird');
  String get linesAtOnce => _t('Lines at a time', 'عدد الأسطر معًا',
      'ایک وقت میں سطریں', 'Baris sekaligus', 'Zeilen auf einmal');
  String linesCount(int n) => switch (lang) {
        AppLang.ar => switch (n) {
            1 => 'سطر واحد',
            2 => 'سطران',
            _ => '$n أسطر',
          },
        AppLang.ur => n == 1 ? 'ایک سطر' : '$n سطریں',
        AppLang.id => '$n baris',
        AppLang.de => n == 1 ? '1 Zeile' : '$n Zeilen',
        _ => n == 1 ? '1 line' : '$n lines',
      };

  /// Under the choice: what timing the cuts follow, so nobody wonders
  /// whether a line can change in the middle of a word.
  String get linesTimingNote => _t(
      'Each line changes as the reciter finishes it.',
      'يتغير كل سطر حين ينتهي القارئ منه.',
      'ہر سطر قاری کے ختم کرتے ہی بدلتی ہے۔',
      'Setiap baris berganti saat qari selesai membacanya.',
      'Jede Zeile wechselt, wenn der Rezitator sie beendet.');

  /// Under the lines choice, when some of this reel's long verses could
  /// not be cut to the recitation and are shown whole.
  String get linesSomeWhole => _t(
      'Some verses here stay whole.',
      'بعض الآيات هنا تبقى كاملة.',
      'یہاں کچھ آیات پوری رہتی ہیں۔',
      'Beberapa ayat di sini tetap utuh.',
      'Einige Verse bleiben hier ganz.');

  /// And when none of them could.
  String get linesAllWhole => _t(
      'With this voice, these verses stay whole.',
      'مع هذا الصوت تبقى هذه الآيات كاملة.',
      'اس آواز کے ساتھ یہ آیات پوری رہتی ہیں۔',
      'Dengan suara ini, ayat-ayat ini tetap utuh.',
      'Mit dieser Stimme bleiben diese Verse ganz.');
  String get scenesChangeTitle => _t('Scenes change', 'تتغير المشاهد',
      'مناظر بدلتے ہیں', 'Adegan berganti', 'Szenen wechseln');
  String get scenesEveryLine => _t('Every line', 'مع كل سطر', 'ہر سطر پر',
      'Setiap baris', 'Mit jeder Zeile');
  String get scenesEveryVerse => _t('Every verse', 'مع كل آية',
      'ہر آیت پر', 'Setiap ayat', 'Mit jedem Vers');
  String get scenesChangeNote => _t(
      'When a reel has several sceneries and its verses go line by line',
      'حين يكون للمقطع عدة مشاهد وتظهر آياته سطرًا سطرًا',
      'جب ریل میں کئی مناظر ہوں اور اس کی آیات سطر بہ سطر ہوں',
      'Saat reel punya beberapa adegan dan ayatnya tampil baris demi baris',
      'Wenn ein Reel mehrere Szenen hat und die Verse Zeile für Zeile kommen');
  String get pacePerLine =>
      _t('Per line', 'لكل سطر', 'فی سطر', 'Per baris', 'Pro Zeile');

  // ---- the surah's name ---------------------------------------------

  String get surahNameTitle =>
      _t('Surah name', 'اسم السورة', 'سورت کا نام', 'Nama surah', 'Surenname');
  String get surahNameNote => _t(
      'At the top of new reels. Drag it anywhere on the preview, and '
          'pinch it to size.',
      'أعلى المقاطع الجديدة. اسحبه إلى أي مكان في المعاينة، وقرّب '
          'إصبعيك أو باعدهما لتغيير حجمه.',
      'نئی ریلز کے اوپر۔ پیش نظارہ میں اسے کہیں بھی گھسیٹیں، اور دو '
          'انگلیوں سے چھوٹا بڑا کریں۔',
      'Di atas reel baru. Seret ke mana saja di pratinjau, dan cubit '
          'untuk mengubah ukurannya.',
      'Oben in neuen Reels. Zieh ihn in der Vorschau, wohin du willst, '
          'und zieh ihn mit zwei Fingern größer oder kleiner.');
  String a11ySurahNamePill(bool on) => on
      ? _t('Surah name, shown', 'اسم السورة، ظاهر', 'سورت کا نام، دکھایا گیا',
          'Nama surah, ditampilkan', 'Surenname, sichtbar')
      : _t('Surah name, hidden', 'اسم السورة، مخفي', 'سورت کا نام، چھپا ہوا',
          'Nama surah, disembunyikan', 'Surenname, ausgeblendet');
  String get a11ySurahNameHint => _t(
      'Shows or hides it on the reel',
      'يُظهره أو يخفيه في المقطع',
      'ریل پر دکھاتا یا چھپاتا ہے',
      'Menampilkan atau menyembunyikannya di reel',
      'Blendet ihn im Reel ein oder aus');

  // ---- motion ----------------------------------------------------------

  /// The reel screen's button that opens the apps a reel can go
  /// straight to.
  String get shareTo =>
      _t('Share to', 'شارك إلى', 'شیئر کریں', 'Bagikan ke', 'Teilen in');
  String get shareToInstagramReel => _t('Instagram Reel', 'ريلز إنستغرام',
      'انسٹاگرام ریل', 'Reel Instagram', 'Instagram-Reel');
  String get shareToInstagramStory => _t('Instagram Story',
      'قصة إنستغرام', 'انسٹاگرام اسٹوری', 'Story Instagram', 'Instagram-Story');
  String get shareToYouTube => _t('YouTube Shorts', 'يوتيوب شورتس',
      'یوٹیوب شارٹس', 'YouTube Shorts', 'YouTube Shorts');

  /// A card into Instagram's feed.
  String get shareToInstagramPost => _t('Instagram Post', 'منشور إنستغرام',
      'انسٹاگرام پوسٹ', 'Postingan Instagram', 'Instagram-Beitrag');

  /// Over the apps a card can go straight to.
  String get shareToCardNote => _t(
      'The card goes straight in, its caption and hashtags copied',
      'تُرسل البطاقة مباشرة، مع نسخ الوصف والوسوم',
      'کارڈ سیدھا جاتا ہے، کیپشن اور ہیش ٹیگز کاپی ہو جاتے ہیں',
      'Kartu langsung masuk, keterangan dan tagarnya tersalin',
      'Die Karte geht direkt hinein, Text und Hashtags kopiert');

  /// The line a card's caption opens with, before its hashtags.
  String get cardShareLine => _t(
      '✨ Made with AyahReel — Islamic cards and Quran reels',
      '✨ صُنعت بتطبيق AyahReel — بطاقات إسلامية ومقاطع قرآنية',
      '✨ AyahReel سے بنایا گیا — اسلامی کارڈز اور قرآنی ریلز',
      '✨ Dibuat dengan AyahReel — kartu Islami dan reel Al-Qur’an',
      '✨ Gemacht mit AyahReel – islamische Karten und Quran-Reels');

  /// After a card was saved and its app opened (iOS): where it is.
  String shareCardOpenHint(String app) => _t(
      'Saved to your gallery. In $app, tap + and pick the newest picture; '
          'the caption and hashtags are copied.',
      'حُفظت في معرضك. في $app اضغط + واختر أحدث صورة؛ الوصف والوسوم منسوخة.',
      'گیلری میں محفوظ ہو گیا۔ $app میں + دبائیں اور تازہ ترین تصویر چنیں؛ '
          'کیپشن اور ہیش ٹیگز کاپی ہیں۔',
      'Tersimpan di galeri. Di $app, ketuk + lalu pilih gambar terbaru; '
          'keterangan dan tagar sudah tersalin.',
      'In der Galerie gespeichert. Tippe in $app auf + und wähle das neueste '
          'Bild; Text und Hashtags sind kopiert.');
  String get shareToCaptionNote => _t(
      'The reel goes straight in, its caption and hashtags copied',
      'يُرسل المقطع مباشرة، مع نسخ الوصف والوسوم',
      'ریل سیدھی جاتی ہے، کیپشن اور ہیش ٹیگز کاپی ہو جاتے ہیں',
      'Reel langsung masuk, keterangan dan tagarnya tersalin',
      'Das Reel geht direkt hinein, Text und Hashtags kopiert');
  String get shareCaptionCopied => _t(
      'Caption and hashtags copied: paste them in',
      'نُسخ الوصف والوسوم: الصقها هناك',
      'کیپشن اور ہیش ٹیگز کاپی ہو گئے: وہاں پیسٹ کریں',
      'Keterangan dan tagar tersalin: tempelkan di sana',
      'Text und Hashtags kopiert: dort einfügen');
  String shareOpenHint(String app) => _t(
      'Saved to your gallery. In $app, tap + and pick the newest video; '
          'the caption and hashtags are copied.',
      'حُفظ في معرضك. في $app اضغط + واختر أحدث فيديو؛ الوصف والوسوم منسوخة.',
      'گیلری میں محفوظ ہو گئی۔ $app میں + دبائیں اور تازہ ترین ویڈیو چنیں؛ '
          'کیپشن اور ہیش ٹیگز کاپی ہیں۔',
      'Tersimpan di galeri. Di $app, ketuk + lalu pilih video terbaru; '
          'keterangan dan tagar sudah tersalin.',
      'In der Galerie gespeichert. Tippe in $app auf + und wähle das neueste '
          'Video; Text und Hashtags sind kopiert.');
  String shareAppMissing(String app) => _t(
      '$app isn’t on this phone',
      '$app غير مثبّت على هذا الهاتف',
      '$app اس فون پر نہیں ہے',
      '$app tidak ada di ponsel ini',
      '$app ist nicht auf diesem Handy');

  /// Customize: the basmala before a surah's first verse.
  String get basmalaTitle => _t('Bismillah before verse 1',
      'البسملة قبل الآية الأولى', 'پہلی آیت سے پہلے بسم اللہ',
      'Basmalah sebelum ayat 1', 'Basmala vor Vers 1');
  String get basmalaNote => _t(
      'A reel from a surah’s first verse opens with the reciter’s own Bismillah',
      'المقطع من أول آية في السورة يبدأ ببسملة القارئ نفسه',
      'سورت کی پہلی آیت سے ریل قاری کی اپنی بسم اللہ سے شروع ہوتی ہے',
      'Reel dari ayat pertama surah dibuka dengan basmalah sang qari',
      'Ein Reel ab dem ersten Vers einer Sure beginnt mit der Basmala des Rezitators');

  /// The verse picker, above a surah's first verse once it is chosen:
  /// the same switch as [basmalaTitle].
  String get includeBasmala => _t('Include Bismillah', 'تضمين البسملة',
      'بسم اللہ شامل کریں', 'Sertakan Basmalah', 'Mit Basmala');

  /// The style step's panel for the surah's name.
  String get styleTabName => _t('Name', 'الاسم', 'نام', 'Nama', 'Name');
  String get titleShown => _t('Surah name', 'اسم السورة', 'سورت کا نام',
      'Nama surah', 'Surenname');
  String get titleGold =>
      _t('Gold', 'ذهبي', 'سنہرا', 'Emas', 'Gold');
  String get titleFrameHeading =>
      _t('Frame', 'الإطار', 'فریم', 'Bingkai', 'Rahmen');
  String titleFaceName(TitleFace f) => switch (f) {
        TitleFace.ruqaa => _t('Ruqaa', 'رقعة', 'رقعہ', 'Riqah', 'Ruqaa'),
        TitleFace.naskh => _t('Naskh', 'نسخ', 'نسخ', 'Naskhi', 'Naschi'),
        TitleFace.kufi => _t('Kufi', 'كوفي', 'کوفی', 'Kufi', 'Kufi'),
        TitleFace.diwani =>
          _t('Calligraphy', 'خط فني', 'خطاطی', 'Kaligrafi', 'Kalligrafie'),
        TitleFace.bold => _t('Bold', 'عريض', 'موٹا', 'Tebal', 'Fett'),
        TitleFace.mushaf => _t('Mushaf', 'المصحف', 'مصحف', 'Mushaf', 'Mushaf'),
        TitleFace.qahiri =>
          _t('Qahiri', 'قاهري', 'قاہری', 'Qahiri', 'Qahiri'),
        TitleFace.messiri =>
          _t('Messiri', 'المسيري', 'مسیری', 'Messiri', 'Messiri'),
        TitleFace.mirza => _t('Mirza', 'ميرزا', 'مرزا', 'Mirza', 'Mirza'),
        TitleFace.scheherazade => _t('Scheherazade', 'شهرزاد', 'شہرزاد',
            'Scheherazade', 'Scheherazade'),
        TitleFace.lateef => _t('Lateef', 'لطيف', 'لطیف', 'Lateef', 'Lateef'),
        TitleFace.changa => _t('Changa', 'شانغا', 'چانگا', 'Changa', 'Changa'),
        TitleFace.markazi =>
          _t('Markazi', 'مركزي', 'مرکزی', 'Markazi', 'Markazi'),
      };
  String titleFrameName(TitleFrame f) => switch (f) {
        TitleFrame.rules =>
          _t('Rules', 'خطوط', 'لکیریں', 'Garis', 'Linien'),
        TitleFrame.plain => _t('None', 'بدون', 'کوئی نہیں', 'Tanpa', 'Ohne'),
        TitleFrame.cartouche =>
          _t('Cartouche', 'خرطوشة', 'کارتوش', 'Kartusy', 'Kartusche'),
        TitleFrame.band =>
          _t('Heading', 'ترويسة', 'سرخی', 'Kepala', 'Kopfband'),
      };

  String get styleTabMotion =>
      _t('Motion', 'الحركة', 'حرکت', 'Gerak', 'Bewegung');
  String get motionTitle =>
      _t('Verse motion', 'حركة الآية', 'آیت کی حرکت', 'Gerak ayat', 'Versbewegung');
  String get motionBody => _t(
      'How the verse moves as it is recited. Your saved reel moves the same.',
      'كيف تتحرك الآية وهي تُتلى. ويتحرك مقطعك المحفوظ بالطريقة نفسها.',
      'تلاوت کے ساتھ آیت کیسے حرکت کرے۔ محفوظ ریل بھی ویسے ہی حرکت کرے گی۔',
      'Cara ayat bergerak saat dibacakan. Reel yang Anda simpan bergerak sama.',
      'Wie sich der Vers beim Rezitieren bewegt. Dein gespeichertes Reel '
          'bewegt sich genauso.');
  /// For a reel on the user's own recording (OwnAudioNote): kind and
  /// plain, and Still always there. [still] is Still's own name.
  String ownAudioMotionNote(String still) => _t(
      'With your own recording, the light and the thread can’t know '
          'exactly when each word is said, so they follow the pauses in '
          'your recording: a gentle best guess. If you’d prefer, you can '
          'always choose $still.',
      'مع تسجيلك الخاص لا يعرف النور والخيط متى تُقال كل كلمة بالضبط، '
          'فيتبعان وقفات تسجيلك: تقديرٌ لطيف. وإن شئت، يمكنك دائمًا '
          'اختيار «$still».',
      'آپ کی اپنی ریکارڈنگ میں نور اور دھاگا ٹھیک سے نہیں جان سکتے کہ ہر '
          'لفظ کب ادا ہوا، اس لیے وہ آپ کی ریکارڈنگ کے وقفوں کے ساتھ چلتے '
          'ہیں: ایک نرم سا اندازہ۔ چاہیں تو آپ ہمیشہ «$still» چن سکتے ہیں۔',
      'Dengan rekamanmu sendiri, cahaya dan benang tidak bisa tahu persis '
          'kapan tiap kata diucapkan, jadi keduanya mengikuti jeda '
          'rekamanmu: perkiraan yang lembut. Kalau lebih suka, kamu selalu '
          'bisa memilih $still.',
      'Bei deiner eigenen Aufnahme wissen Licht und Faden nicht genau, '
          'wann jedes Wort gesprochen wird, also folgen sie den Pausen '
          'deiner Aufnahme: eine sanfte Schätzung. Wenn dir das lieber '
          'ist, kannst du jederzeit „$still“ wählen.');
  /// The put-away note's pill, which opens it again.
  String get ownAudioNoteAgain => _t('About the light', 'عن النور',
      'نور کے بارے میں', 'Tentang cahaya', 'Über das Licht');
  String motionPresetName(String key) => switch (key) {
        'still' => _t('Still', 'ثابت', 'ساکن', 'Diam', 'Ruhig'),
        'thread' => _t('Golden thread', 'خيط ذهبي', 'سنہری دھاگا',
            'Benang emas', 'Goldener Faden'),
        'light' => _t('Light', 'نور', 'نور', 'Cahaya', 'Licht'),
        'unveil' =>
          _t('Unveil', 'إظهار', 'نمودار', 'Singkap', 'Enthüllen'),
        'gilded' =>
          _t('Gilded', 'مُذهَّب', 'سنہرا', 'Berlapis emas', 'Vergoldet'),
        _ => key,
      };
  /// The motion's colour, on the style step: the light, the thread and
  /// the lit words all take it.
  String get motionColour => _t('Motion colour', 'لون الحركة', 'حرکت کا رنگ',
      'Warna gerak', 'Farbe der Bewegung');

  /// A motion mixed by hand, matching none of the designed looks: what
  /// the Customize row says after the lines.
  String get motionCustom => _t('Your mix', 'مزيجك الخاص', 'آپ کا امتزاج',
      'Campuran Anda', 'Eigene Mischung');
  String get motionFollowsWords => _t(
      'Follows each word with voices that have word timing',
      'يتبع كل كلمة مع الأصوات التي لها توقيت للكلمات',
      'لفظی وقت والی آوازوں کے ساتھ ہر لفظ کے پیچھے چلتا ہے',
      'Mengikuti setiap kata pada suara yang punya waktu per kata',
      'Folgt jedem Wort bei Stimmen mit Wort-Timing');
  String get motionNeedsWords => _t(
      'Needs a voice with word timing',
      'يحتاج صوتًا له توقيت للكلمات',
      'لفظی وقت والی آواز درکار ہے',
      'Perlu suara dengan waktu per kata',
      'Braucht eine Stimme mit Wort-Timing');

  /// A look tapped that the voice can't play here: said for a moment
  /// under the cards, in place of the line above.
  String motionNotForVoice(String look) => _t(
      '$look isn’t available for this voice',
      '«$look» غير متاح لهذا الصوت',
      '«$look» اس آواز کے لیے دستیاب نہیں',
      '$look tidak tersedia untuk suara ini',
      '$look gibt es für diese Stimme nicht');
  String get a11yMotionPillHint => _t(
      'Opens the verse motion',
      'يفتح حركة الآية',
      'آیت کی حرکت کھولتا ہے',
      'Membuka gerak ayat',
      'Öffnet die Versbewegung');

  // ---- Settings → Customize, the page ---------------------------------

  /// Under the page's title: what the page is for, and that a reel can
  /// still differ.
  String get customizeIntro => _t(
      'Set once for every reel you make. Any reel can still change them.',
      'تُضبط مرة واحدة لكل مقاطعك، ويبقى بإمكان أي مقطع تغييرها.',
      'ایک بار طے کریں، ہر ریل کے لیے۔ کوئی بھی ریل انہیں پھر بھی بدل سکتی ہے۔',
      'Atur sekali untuk setiap reel Anda. Tiap reel tetap bisa mengubahnya.',
      'Einmal festlegen, für jedes Reel. Jedes Reel kann sie trotzdem ändern.');

  /// Under the reel playing at the head of the page.
  String get customizePreviewCaption => _t(
      'Ayat al-Kursi, as your reels show it',
      'آية الكرسي كما تظهر في مقاطعك',
      'آیت الکرسی، جیسے آپ کی ریلز میں نظر آتی ہے',
      'Ayat Kursi, seperti tampil di reel Anda',
      'Ajat al-Kursi, so wie deine Reels ihn zeigen');
  String get a11yCustomizePreview => _t(
      'A reel playing Ayat al-Kursi with these choices',
      'مقطع يعرض آية الكرسي بهذه الاختيارات',
      'ان انتخابات کے ساتھ آیت الکرسی دکھاتی ریل',
      'Reel yang memutar Ayat Kursi dengan pilihan ini',
      'Ein Reel, das Ajat al-Kursi mit diesen Einstellungen zeigt');

  /// Under the motion's heading on the page: it is where every reel
  /// starts, not a lock on every reel.
  String get customizeMotionNote => _t(
      'Every new reel starts with this. Any reel can change it while you '
          'style it.',
      'يبدأ بها كل مقطع جديد، ويمكن تغييرها لأي مقطع أثناء تنسيقه.',
      'ہر نئی ریل اسی سے شروع ہوتی ہے۔ کسی بھی ریل کو سجاتے وقت اسے بدل سکتے ہیں۔',
      'Setiap reel baru dimulai dengan ini. Reel mana pun bisa mengubahnya '
          'saat Anda menatanya.',
      'Jedes neue Reel beginnt damit. Beim Gestalten kann jedes Reel es '
          'ändern.');

  /// Under the word highlight's switch.
  String get wordHighlightNote => _t(
      'Each word lights as the reciter says it, with every voice that has '
          'word timing',
      'تضيء كل كلمة حين ينطقها القارئ، مع كل صوت له توقيت للكلمات',
      'ہر لفظ قاری کے پڑھتے ہی روشن ہوتا ہے، ہر اُس آواز کے ساتھ جس کا '
          'لفظی وقت موجود ہو',
      'Setiap kata menyala saat qari mengucapkannya, pada setiap suara yang '
          'punya waktu per kata',
      'Jedes Wort leuchtet auf, wenn der Rezitator es spricht – bei jeder '
          'Stimme mit Wort-Timing');
  String get customizeOnReel =>
      _t('On the reel', 'على المقطع', 'ریل پر', 'Di reel', 'Im Reel');
  String get customizeVideo =>
      _t('Video', 'الفيديو', 'ویڈیو', 'Video', 'Video');

  /// The page's last button: its own choices back to the app's, and
  /// nothing else in Settings.
  String get customizeReset => _t(
      'Back to the defaults',
      'العودة إلى الإعدادات الأصلية',
      'اصل ترتیبات پر واپس',
      'Kembali ke bawaan',
      'Zurück zu den Standardwerten');
  String get customizeResetDone => _t(
      'Defaults restored',
      'عادت الإعدادات الأصلية',
      'اصل ترتیبات بحال ہو گئیں',
      'Kembali ke bawaan',
      'Standardwerte wiederhergestellt');

  /// '12 Mar 2026' / '12 مارس 2026'.
  String formatDate(DateTime d) {
    const months = <AppLang, List<String>>{
      AppLang.en: [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ],
      AppLang.ar: [
        'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
        'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
      ],
      AppLang.ur: [
        'جنوری', 'فروری', 'مارچ', 'اپریل', 'مئی', 'جون',
        'جولائی', 'اگست', 'ستمبر', 'اکتوبر', 'نومبر', 'دسمبر',
      ],
      AppLang.id: [
        'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
        'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
      ],
      AppLang.de: [
        'Jan.', 'Feb.', 'März', 'Apr.', 'Mai', 'Juni',
        'Juli', 'Aug.', 'Sep.', 'Okt.', 'Nov.', 'Dez.',
      ],
    };
    // German writes the day as an ordinal: '4. Okt. 2026'.
    final day = lang == AppLang.de ? '${d.day}.' : '${d.day}';
    return '$day ${months[lang]![d.month - 1]} ${d.year}';
  }
}

class _L10nDelegate extends LocalizationsDelegate<L10n> {
  const _L10nDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppLang.values.any((l) => l.code == locale.languageCode);

  @override
  Future<L10n> load(Locale locale) =>
      SynchronousFuture(L10n(AppLang.fromCode(locale.languageCode)));

  @override
  bool shouldReload(_L10nDelegate old) => false;
}
