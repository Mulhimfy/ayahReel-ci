import 'models.dart';
import 'verse_translation.dart';

/// Surah Al-Fatiha, Uthmani script (Tanzil.net) + Saheeh International.
///
/// Bundled so the first run never touches the network for text. That
/// promise has to hold in every language, not only English, or picking
/// Urdu during onboarding and then being offline would leave the first
/// reel with nothing to show — so [fatihaIn] carries the same seven
/// verses in every edition the app offers.
const fatiha = <Ayah>[
  Ayah(
    number: 1,
    arabic: 'بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ',
    translation:
        'In the name of Allah, the Entirely Merciful, the Especially Merciful.',
  ),
  Ayah(
    number: 2,
    arabic: 'ٱلْحَمْدُ لِلَّهِ رَبِّ ٱلْعَـٰلَمِينَ',
    translation: 'All praise is due to Allah, Lord of the worlds.',
  ),
  Ayah(
    number: 3,
    arabic: 'ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ',
    translation: 'The Entirely Merciful, the Especially Merciful.',
  ),
  Ayah(
    number: 4,
    arabic: 'مَـٰلِكِ يَوْمِ ٱلدِّينِ',
    translation: 'Sovereign of the Day of Recompense.',
  ),
  Ayah(
    number: 5,
    arabic: 'إِيَّاكَ نَعْبُدُ وَإِيَّاكَ نَسْتَعِينُ',
    translation: 'It is You we worship and You we ask for help.',
  ),
  Ayah(
    number: 6,
    arabic: 'ٱهْدِنَا ٱلصِّرَٰطَ ٱلْمُسْتَقِيمَ',
    translation: 'Guide us to the straight path.',
  ),
  Ayah(
    number: 7,
    arabic:
        'صِرَٰطَ ٱلَّذِينَ أَنْعَمْتَ عَلَيْهِمْ غَيْرِ ٱلْمَغْضُوبِ عَلَيْهِمْ وَلَا ٱلضَّآلِّينَ',
    translation:
        'The path of those upon whom You have bestowed favor, not of those who have earned Your anger or of those who are astray.',
  ),
];

/// Al-Fatiha's translation in every offered edition, ayah 1 to 7.
///
/// Fetched from the same source and cleaned by the same pipeline as
/// everything else — see tool/verify_translations.py. The English is
/// the wording [fatiha] has always carried, kept exactly, so nothing
/// that reads the bundled surah changes.
const _fatihaTranslations = <Map<String, String>>[
  {
    'en':
        'In the name of Allah, the Entirely Merciful, the Especially Merciful.',
    'ur':
        'شروع الله کا نام لے کر جو بڑا مہربان نہایت رحم والا ہے',
    'id':
        'Dengan nama Allah Yang Maha Pengasih, Maha Penyayang.',
    'de':
        'Im Namen Allahs, des Allerbarmers, des Barmherzigen.',
  },
  {
    'en':
        'All praise is due to Allah, Lord of the worlds.',
    'ur':
        'سب طرح کی تعریف خدا ہی کو (سزاوار) ہے جو تمام مخلوقات کا پروردگار ہے',
    'id':
        'Segala puji bagi Allah, Tuhan seluruh alam,',
    'de':
        '(Alles) Lob gehört Allah, dem Herrn der Welten,',
  },
  {
    'en':
        'The Entirely Merciful, the Especially Merciful.',
    'ur':
        'بڑا مہربان نہایت رحم والا',
    'id':
        'Yang Maha Pengasih, Maha Penyayang,',
    'de':
        'dem Allerbarmer, dem Barmherzigen,',
  },
  {
    'en':
        'Sovereign of the Day of Recompense.',
    'ur':
        'انصاف کے دن کا حاکم',
    'id':
        'Pemilik hari pembalasan.',
    'de':
        'dem Herrscher am Tag des Gerichts.',
  },
  {
    'en':
        'It is You we worship and You we ask for help.',
    'ur':
        '(اے پروردگار) ہم تیری ہی عبادت کرتے ہیں اور تجھ ہی سے مدد مانگتے ہیں',
    'id':
        'Hanya kepada Engkaulah kami menyembah dan hanya kepada Engkaulah kami mohon pertolongan.',
    'de':
        'Dir allein dienen wir, und zu Dir allein flehen wir um Hilfe.',
  },
  {
    'en':
        'Guide us to the straight path.',
    'ur':
        'ہم کو سیدھے رستے چلا',
    'id':
        'Tunjukilah kami jalan yang lurus,',
    'de':
        'Leite uns den geraden Weg,',
  },
  {
    'en':
        'The path of those upon whom You have bestowed favor, not of those who have earned Your anger or of those who are astray.',
    'ur':
        'ان لوگوں کے رستے جن پر تو اپنا فضل وکرم کرتا رہا نہ ان کے جن پر غصے ہوتا رہا اور نہ گمراہوں کے',
    'id':
        '(yaitu) jalan orang-orang yang telah Engkau beri nikmat kepadanya; bukan (jalan) mereka yang dimurkai, dan bukan (pula jalan) mereka yang sesat.',
    'de':
        'den Weg derjenigen, denen Du Gunst erwiesen hast, nicht derjenigen, die (Deinen) Zorn erregt haben, und nicht der Irregehenden!',
  },
];

/// The bundled Al-Fatiha in one edition. Falls back to English for an
/// edition without a bundled translation, which cannot happen today
/// and would still show a verse if it ever did.
List<Ayah> fatihaIn(VerseTranslation t) => [
      for (var i = 0; i < fatiha.length; i++)
        Ayah(
          number: fatiha[i].number,
          arabic: fatiha[i].arabic,
          translation:
              _fatihaTranslations[i][t.code] ?? fatiha[i].translation,
        ),
    ];

/// TIMING DATA — exact by construction: each bundled mp3 was built by
/// concatenating EveryAyah's per-ayah files, and each window below is
/// the cumulative sum of those files' measured durations (ffprobe).
/// If an audio asset is ever replaced, re-run the process in
/// tool/verify_timings.md.
const reciters = <Reciter>[
  Reciter(
    id: 'alafasy',
    name: 'Mishary Alafasy',
    arabicName: 'مشاري العفاسي',
    style: 'Murattal · warm, melodic',
    source: AyahFiles.everyAyah('Alafasy_128kbps'),
    audioAsset: 'assets/audio/alafasy_001.mp3',
    timings: [
      AyahTiming(1, 0, 6031),
      AyahTiming(2, 6031, 11565),
      AyahTiming(3, 11565, 16137),
      AyahTiming(4, 16137, 20739),
      AyahTiming(5, 20739, 27391),
      AyahTiming(6, 27391, 32935),
      AyahTiming(7, 32935, 46122),
    ],
  ),
  Reciter(
    id: 'husary',
    name: 'Mahmoud Al-Husary',
    arabicName: 'محمود الحصري',
    style: 'Murattal · measured, classical',
    source: AyahFiles.everyAyah('Husary_128kbps'),
    audioAsset: 'assets/audio/husary_001.mp3',
    timings: [
      AyahTiming(1, 0, 5128),
      AyahTiming(2, 5128, 11405),
      AyahTiming(3, 11405, 15906),
      AyahTiming(4, 15906, 20538),
      AyahTiming(5, 20538, 27390),
      AyahTiming(6, 27390, 32753),
      AyahTiming(7, 32753, 47647),
    ],
  ),
  Reciter(
    id: 'abdulbasit',
    name: 'Abdul Basit',
    arabicName: 'عبد الباسط عبد الصمد',
    style: 'Murattal · deep, resonant',
    source: AyahFiles.everyAyah('Abdul_Basit_Murattal_192kbps'),
    audioAsset: 'assets/audio/abdulbasit_001.mp3',
    timings: [
      AyahTiming(1, 0, 4368),
      AyahTiming(2, 4368, 9676),
      AyahTiming(3, 9676, 13704),
      AyahTiming(4, 13704, 18255),
      AyahTiming(5, 18255, 23876),
      AyahTiming(6, 23876, 28688),
      AyahTiming(7, 28688, 41796),
    ],
  ),

  // ── Streamed voices ──────────────────────────────────────────────
  // No bundled asset: every surah (Al-Fatiha included) is built
  // on-device from EveryAyah per-ayah files, timings measured with
  // ffprobe at assembly time — exact by construction. Each folder
  // name below is verified to serve audio before shipping. To add a
  // reciter: verify `https://everyayah.com/data/<folder>/001002.mp3`
  // responds, then add one entry here. Nothing else changes.
  Reciter(
    id: 'minshawi',
    name: 'Al-Minshawi',
    arabicName: 'محمد صديق المنشاوي',
    style: 'Murattal · timeless, moving',
    source: AyahFiles.everyAyah('Minshawy_Murattal_128kbps'),
  ),
  Reciter(
    id: 'sudais',
    name: 'Abdur-Rahman As-Sudais',
    arabicName: 'عبد الرحمن السديس',
    style: 'Murattal · soaring, heartfelt',
    source: AyahFiles.everyAyah('Abdurrahmaan_As-Sudais_192kbps'),
  ),
  Reciter(
    id: 'shuraym',
    name: 'Saud Ash-Shuraym',
    arabicName: 'سعود الشريم',
    style: 'Murattal · bright, steady',
    source: AyahFiles.everyAyah('Saood_ash-Shuraym_128kbps'),
  ),
  Reciter(
    id: 'muaiqly',
    name: 'Maher Al-Muaiqly',
    arabicName: 'ماهر المعيقلي',
    style: 'Murattal · serene, tender',
    source: AyahFiles.everyAyah('MaherAlMuaiqly128kbps'),
  ),
  Reciter(
    id: 'hudhaify',
    name: 'Ali Al-Hudhaify',
    arabicName: 'علي الحذيفي',
    style: 'Murattal · solemn, precise',
    source: AyahFiles.everyAyah('Hudhaify_128kbps'),
  ),
  Reciter(
    id: 'dussary',
    name: 'Yasser Ad-Dussary',
    arabicName: 'ياسر الدوسري',
    style: 'Murattal · rich, emotive',
    source: AyahFiles.everyAyah('Yasser_Ad-Dussary_128kbps'),
  ),
  Reciter(
    id: 'shatri',
    name: 'Abu Bakr Ash-Shatri',
    arabicName: 'أبو بكر الشاطري',
    style: 'Murattal · gentle, melodious',
    source: AyahFiles.everyAyah('Abu_Bakr_Ash-Shaatree_128kbps'),
  ),
  Reciter(
    id: 'ayyub',
    name: 'Muhammad Ayyub',
    arabicName: 'محمد أيوب',
    style: 'Murattal · earnest, classic',
    source: AyahFiles.everyAyah('Muhammad_Ayyoub_128kbps'),
  ),
  Reciter(
    id: 'ajmi',
    name: 'Ahmed Al-Ajmi',
    arabicName: 'أحمد العجمي',
    style: 'Murattal · powerful, heartfelt',
    source: AyahFiles.everyAyah('ahmed_ibn_ali_al_ajamy_128kbps'),
  ),
  Reciter(
    id: 'qatami',
    name: 'Nasser Al-Qatami',
    arabicName: 'ناصر القطامي',
    style: 'Murattal · tender, flowing',
    source: AyahFiles.everyAyah('Nasser_Alqatami_128kbps'),
  ),
  Reciter(
    id: 'qasim',
    name: 'Muhsin Al-Qasim',
    arabicName: 'محسن القاسم',
    style: 'Murattal · composed, clear',
    source: AyahFiles.everyAyah('Muhsin_Al_Qasim_192kbps'),
  ),
  Reciter(
    id: 'juhani',
    name: 'Abdullah Al-Juhani',
    arabicName: 'عبد الله الجهني',
    style: 'Murattal · luminous, agile',
    source: AyahFiles.everyAyah('Abdullaah_3awwaad_Al-Juhaynee_128kbps'),
  ),
  Reciter(
    id: 'budair',
    name: 'Salah Al-Budair',
    arabicName: 'صلاح البدير',
    style: 'Murattal · silken, unhurried',
    source: AyahFiles.everyAyah('Salah_Al_Budair_128kbps'),
  ),
  Reciter(
    id: 'rifai',
    name: 'Hani Ar-Rifai',
    arabicName: 'هاني الرفاعي',
    style: 'Murattal · fervent, stirring',
    source: AyahFiles.everyAyah('Hani_Rifai_192kbps'),
  ),
  Reciter(
    id: 'tablawi',
    name: 'Mohammad Al-Tablawi',
    arabicName: 'محمد الطبلاوي',
    style: 'Murattal · stately, Egyptian school',
    source: AyahFiles.everyAyah('Mohammad_al_Tablaway_128kbps'),
  ),
  Reciter(
    id: 'jibreel',
    name: 'Muhammad Jibreel',
    arabicName: 'محمد جبريل',
    style: 'Murattal · resonant, devout',
    source: AyahFiles.everyAyah('Muhammad_Jibreel_128kbps'),
  ),
  Reciter(
    id: 'basfar',
    name: 'Abdullah Basfar',
    arabicName: 'عبد الله بصفر',
    style: 'Murattal · clear, contemplative',
    source: AyahFiles.everyAyah('Abdullah_Basfar_192kbps'),
  ),
  Reciter(
    id: 'bukhatir',
    name: 'Salah Bukhatir',
    arabicName: 'صلاح بوخاطر',
    style: 'Murattal · velvet, tranquil',
    source: AyahFiles.everyAyah('Salaah_AbdulRahman_Bukhatir_128kbps'),
  ),
  Reciter(
    id: 'qahtani',
    name: 'Khalid Al-Qahtani',
    arabicName: 'خالد القحطاني',
    style: 'Murattal · warm, expansive',
    source: AyahFiles.everyAyah('Khaalid_Abdullaah_al-Qahtaanee_192kbps'),
  ),
  Reciter(
    id: 'matrood',
    name: 'Abdullah Al-Matrood',
    arabicName: 'عبد الله المطرود',
    style: 'Murattal · plaintive, absorbing',
    source: AyahFiles.everyAyah('Abdullah_Matroud_128kbps'),
  ),
  Reciter(
    id: 'neana',
    name: 'Ahmed Neana',
    arabicName: 'أحمد نعينع',
    style: 'Murattal · melodic, Egyptian school',
    source: AyahFiles.everyAyah('Ahmed_Neana_128kbps'),
  ),
  Reciter(
    id: 'salamah',
    name: 'Yaser Salamah',
    arabicName: 'ياسر سلامة',
    style: 'Murattal · supple, meditative',
    source: AyahFiles.everyAyah('Yaser_Salamah_128kbps'),
  ),
  Reciter(
    id: 'alaqimy',
    name: 'Akram Al-Alaqimy',
    arabicName: 'أكرم العلاقمي',
    style: 'Murattal · lucid, even-paced',
    source: AyahFiles.everyAyah('Akram_AlAlaqimy_128kbps'),
  ),
  Reciter(
    id: 'suesy',
    name: 'Ali Hajjaj Al-Suesy',
    arabicName: 'علي حجاج السويسي',
    style: 'Murattal · sweet, lilting',
    source: AyahFiles.everyAyah('Ali_Hajjaj_AlSuesy_128kbps'),
  ),
  Reciter(
    id: 'alili',
    name: 'Aziz Alili',
    arabicName: 'عزيز عليلي',
    style: 'Murattal · crisp, articulate',
    source: AyahFiles.everyAyah('aziz_alili_128kbps'),
  ),
  Reciter(
    id: 'abdulkareem',
    name: 'Muhammad AbdulKareem',
    arabicName: 'محمد عبد الكريم',
    style: 'Murattal · brisk, disciplined',
    source: AyahFiles.everyAyah('Muhammad_AbdulKareem_128kbps'),
  ),
  Reciter(
    id: 'sahl_yassin',
    name: 'Sahl Yassin',
    arabicName: 'سهل ياسين',
    style: 'Murattal · quiet, sustained',
    source: AyahFiles.everyAyah('Sahl_Yassin_128kbps'),
  ),


  // ── 64 kbps ──────────────────────────────────────────────────────
  // A deliberate exception to the ≥128 kbps rule the rest of this list
  // follows. These four voices exist on EveryAyah at no higher rate,
  // and are the last complete Hafs sets the host has that aren't
  // already above. Verified 5/5 across the mushaf. Don't take the
  // presence of this section as licence to add more low-bitrate sets:
  // it was a considered trade for four well-known reciters, not a
  // lowered bar.
  Reciter(
    id: 'jaber',
    name: 'Ali Jaber',
    arabicName: 'علي جابر',
    style: 'Murattal · grave, dignified',
    source: AyahFiles.everyAyah('Ali_Jaber_64kbps'),
  ),
  Reciter(
    id: 'abbad',
    name: 'Fares Abbad',
    arabicName: 'فارس عباد',
    style: 'Murattal · smooth, youthful',
    source: AyahFiles.everyAyah('Fares_Abbad_64kbps'),
  ),
  Reciter(
    id: 'sowaid',
    name: 'Ayman Sowaid',
    arabicName: 'أيمن سويد',
    style: 'Murattal · exacting, tajwid-precise',
    source: AyahFiles.everyAyah('Ayman_Sowaid_64kbps'),
  ),
  Reciter(
    id: 'tunaiji',
    name: 'Khalifa Al-Tunaiji',
    arabicName: 'خليفة الطنيجي',
    style: 'Murattal · airy, reflective',
    source: AyahFiles.everyAyah('khalefa_al_tunaiji_64kbps'),
  ),
  // ── Beyond EveryAyah ─────────────────────────────────────────────
  // EveryAyah has no complete Hafs set left at 64 kbps or better that
  // isn't above, so every voice from here on comes from elsewhere:
  // - per-ayah files from Tarteel's CDN and King Saud University's
  //   Ayat project — exact by construction, like EveryAyah's;
  // - one file per surah from mp3quran.net, with its published table
  //   of where each ayah is in it (ayat_timing). The app fetches only
  //   the bytes a reel needs and snaps every boundary to the reciter's
  //   breath; see SurahSlice. Mahmoud Ali Al-Banna comes from
  //   quranicaudio.com with the Quranic Universal Library's table
  //   (QulTiming), which times the basmala as part of verse 1; his
  //   openingMs has the app start a verse-1 reel after it.
  // None is here without passing tool/verify_reciters.py — every file,
  // every table, and the tables heard against the audio — and
  // test/reciter_sources_test.dart holds the list to that. [pace] is
  // what the tool measured, and the style line says it in words. A few
  // voices lack a surah or two (SurahFiles.missing), which the pickers
  // then don't offer them for; a few were kept though the tool can't
  // vouch for their sync or their sound, and the tool's USER_ACCEPTED
  // says which and why.
  Reciter(
    id: 'ghamdi',
    name: 'Saad Al-Ghamdi',
    arabicName: 'سعد الغامدي',
    style: 'Murattal · steady pace',
    source: SurahFiles(
      'https://server7.mp3quran.net/s_gmd',
      timing: Mp3QuranTiming(30),
    ),
    pace: 1.072,
  ),
  Reciter(
    id: 'abkar',
    name: 'Idrees Abkar',
    arabicName: 'إدريس أبكر',
    style: 'Murattal · unhurried',
    source: SurahFiles(
      'https://server6.mp3quran.net/abkr',
      timing: Mp3QuranTiming(12),
    ),
    pace: 1.311,
  ),
  Reciter(
    id: 'thubaiti',
    name: 'Abdulbari Al-Thubaiti',
    arabicName: 'عبد الباري الثبيتي',
    style: 'Murattal · brisk',
    source: SurahFiles(
      'https://server6.mp3quran.net/thubti',
      timing: Mp3QuranTiming(49),
    ),
    pace: 0.857,
  ),
  Reciter(
    id: 'balilah',
    name: 'Bandar Balilah',
    arabicName: 'بندر بليلة',
    style: 'Murattal · steady pace',
    source: SurahFiles(
      'https://server6.mp3quran.net/balilah',
      timing: Mp3QuranTiming(217),
    ),
    pace: 1.144,
  ),
  Reciter(
    id: 'jaleel',
    name: 'Khalid Al-Jaleel',
    arabicName: 'خالد الجليل',
    style: 'Murattal · brisk',
    source: SurahFiles(
      'https://server10.mp3quran.net/jleel',
      timing: Mp3QuranTiming(20),
    ),
    pace: 0.992,
  ),
  Reciter(
    id: 'mustafa_ismail',
    name: 'Mustafa Ismail',
    arabicName: 'مصطفى إسماعيل',
    style: 'Murattal · measured pace',
    source: AyahFiles.ksu('Mostafa_Ismail_128kbps'),
    pace: 1.243,
  ),
  Reciter(
    id: 'albanna',
    name: 'Mahmoud Ali Al-Banna',
    arabicName: 'محمود علي البنا',
    style: 'Murattal · steady pace',
    source: SurahFiles(
      'https://download.quranicaudio.com/quran/mahmood_ali_albana',
      timing: QulTiming(129),
      openingMs: 3600,
    ),
    pace: 1.143,
  ),
  Reciter(
    id: 'nufais',
    name: 'Ahmad Al-Nufais',
    arabicName: 'أحمد النفيس',
    style: 'Murattal · unhurried',
    source: AyahFiles.tarteel('alnufais'),
    pace: 1.408,
  ),
  Reciter(
    id: 'salimi',
    name: 'Mansour Al-Salimi',
    arabicName: 'منصور السالمي',
    style: 'Murattal · measured pace',
    source: SurahFiles(
      'https://server14.mp3quran.net/mansor',
      timing: Mp3QuranTiming(245),
    ),
    pace: 1.265,
  ),
  Reciter(
    id: 'ibrahim_dosari',
    name: 'Ibrahim Al-Dosari',
    arabicName: 'إبراهيم الدوسري',
    style: 'Murattal · unhurried',
    source: SurahFiles(
      'https://server10.mp3quran.net/ibrahim_dosri/Rewayat-Hafs-A-n-Assem',
      timing: Mp3QuranTiming(232),
    ),
    pace: 1.403,
  ),
  Reciter(
    id: 'yamani',
    name: 'Wadee Al-Yamani',
    arabicName: 'وديع اليمني',
    style: 'Murattal · measured pace',
    source: SurahFiles(
      'https://server6.mp3quran.net/wdee3',
      timing: Mp3QuranTiming(219),
    ),
    pace: 1.266,
  ),
  Reciter(
    id: 'habdan',
    name: 'Saleh Al-Habdan',
    arabicName: 'صالح الهبدان',
    style: 'Murattal · steady pace',
    source: SurahFiles(
      'https://server6.mp3quran.net/habdan',
      timing: Mp3QuranTiming(42),
    ),
    pace: 1.144,
  ),
  Reciter(
    id: 'buaijan',
    name: 'Abdullah Al-Buaijan',
    arabicName: 'عبد الله البعيجان',
    style: 'Murattal · brisk',
    source: SurahFiles(
      'https://server8.mp3quran.net/buajan',
      timing: Mp3QuranTiming(58),
    ),
    pace: 0.933,
  ),
  Reciter(
    id: 'khayyat',
    name: 'Abdullah Khayyat',
    arabicName: 'عبد الله خياط',
    style: 'Murattal · brisk',
    source: SurahFiles(
      'https://server12.mp3quran.net/kyat',
      timing: Mp3QuranTiming(61),
    ),
    pace: 0.852,
  ),
  Reciter(
    id: 'masrawi',
    name: 'Ahmad Issa Al-Masrawi',
    arabicName: 'أحمد عيسى المعصراوي',
    style: 'Murattal · measured pace',
    source: SurahFiles(
      'https://server16.mp3quran.net/a_maasaraawi/Rewayat-Hafs-A-n-Assem',
      timing: Mp3QuranTiming(289),
    ),
    pace: 1.182,
  ),
  Reciter(
    id: 'turki',
    name: 'Abdulaziz Al-Turki',
    arabicName: 'عبد العزيز التركي',
    style: 'Murattal · steady pace',
    source: SurahFiles(
      'https://server16.mp3quran.net/a_turki/Rewayat-Hafs-A-n-Assem',
      timing: Mp3QuranTiming(282),
    ),
    pace: 1.118,
  ),
  Reciter(
    id: 'zahrani',
    name: 'Abdulaziz Al-Zahrani',
    arabicName: 'عبد العزيز الزهراني',
    style: 'Murattal · unhurried',
    source: SurahFiles(
      'https://server9.mp3quran.net/zahrani',
      timing: Mp3QuranTiming(56),
    ),
    pace: 1.388,
  ),
  Reciter(
    id: 'abdulbari_mohammad',
    name: 'Abdulbari Mohammad',
    arabicName: 'عبد الباري محمد',
    style: 'Murattal · unhurried',
    source: SurahFiles(
      'https://server12.mp3quran.net/bari',
      timing: Mp3QuranTiming(50),
    ),
    pace: 1.576,
  ),
  Reciter(
    id: 'kanakri',
    name: 'Abdulhadi Kanakri',
    arabicName: 'عبد الهادي كناكري',
    style: 'Murattal · measured pace',
    source: SurahFiles(
      'https://server6.mp3quran.net/kanakeri',
      timing: Mp3QuranTiming(70),
    ),
    pace: 1.206,
  ),
  Reciter(
    id: 'khalaf',
    name: 'Abdullah Al-Khalaf',
    arabicName: 'عبد الله الخلف',
    style: 'Murattal · brisk',
    source: SurahFiles(
      'https://server14.mp3quran.net/khalf',
      timing: Mp3QuranTiming(244),
    ),
    pace: 0.968,
  ),
  Reciter(
    id: 'mousa',
    name: 'Abdullah Al-Mousa',
    arabicName: 'عبد الله الموسى',
    style: 'Murattal · steady pace',
    source: SurahFiles(
      'https://server14.mp3quran.net/mousa/Rewayat-Hafs-A-n-Assem',
      timing: Mp3QuranTiming(243),
    ),
    pace: 1.125,
  ),
  Reciter(
    id: 'harthi',
    name: 'Abdulmohsin Al-Harthi',
    arabicName: 'عبد المحسن الحارثي',
    style: 'Murattal · steady pace',
    source: SurahFiles(
      'https://server6.mp3quran.net/mohsin_harthi',
      timing: Mp3QuranTiming(66),
    ),
    pace: 1.049,
  ),
  Reciter(
    id: 'obaikan',
    name: 'Abdulmohsin Al-Obaikan',
    arabicName: 'عبد المحسن العبيكان',
    style: 'Murattal · brisk',
    source: SurahFiles(
      'https://server12.mp3quran.net/obk',
      timing: Mp3QuranTiming(69),
    ),
    pace: 0.83,
  ),
  Reciter(
    id: 'majed',
    name: 'Abdulrahman Al-Majed',
    arabicName: 'عبد الرحمن الماجد',
    style: 'Murattal · steady pace',
    source: SurahFiles(
      'https://server10.mp3quran.net/a_majed',
      timing: Mp3QuranTiming(236),
    ),
    pace: 1.031,
  ),
  Reciter(
    id: 'aloosi',
    name: 'Abdulrahman Al-Ossi',
    arabicName: 'عبد الرحمن العوسي',
    style: 'Murattal · measured pace',
    source: SurahFiles(
      'https://server6.mp3quran.net/aloosi',
      timing: Mp3QuranTiming(225),
    ),
    pace: 1.19,
  ),
  Reciter(
    id: 'soufi',
    name: 'Abdulrasheed Soufi',
    arabicName: 'عبد الرشيد صوفي',
    style: 'Murattal · steady pace',
    source: SurahFiles(
      'https://server16.mp3quran.net/soufi/Rewayat-Hafs-A-n-Assem',
      timing: Mp3QuranTiming(258),
    ),
    pace: 1.059,
  ),
  Reciter(
    id: 'haneef',
    name: 'Abdulwadood Haneef',
    arabicName: 'عبد الودود حنيف',
    style: 'Murattal · brisk',
    source: SurahFiles(
      'https://server8.mp3quran.net/wdod',
      timing: Mp3QuranTiming(71),
    ),
    pace: 0.809,
  ),
  Reciter(
    id: 'arkani',
    name: 'Abdulwali Al-Arkani',
    arabicName: 'عبد الولي الأركاني',
    style: 'Murattal · steady pace',
    source: SurahFiles(
      'https://server6.mp3quran.net/arkani',
      timing: Mp3QuranTiming(72),
    ),
    pace: 1.059,
  ),
  Reciter(
    id: 'rayan',
    name: 'Adel Rayan',
    arabicName: 'عادل ريان',
    style: 'Murattal · steady pace',
    source: SurahFiles(
      'https://server8.mp3quran.net/ryan',
      timing: Mp3QuranTiming(48),
    ),
    pace: 1.088,
  ),
  Reciter(
    id: 'hawashi',
    name: 'Ahmad Al-Hawashi',
    arabicName: 'أحمد الحواشي',
    style: 'Murattal · brisk',
    source: SurahFiles(
      'https://server11.mp3quran.net/hawashi',
      timing: Mp3QuranTiming(6),
    ),
    pace: 0.985,
  ),
  Reciter(
    id: 'trabulsi',
    name: 'Ahmad Al-Trabulsi',
    arabicName: 'أحمد الطرابلسي',
    style: 'Murattal · measured pace',
    source: SurahFiles(
      'https://server10.mp3quran.net/trabulsi',
      timing: Mp3QuranTiming(201),
    ),
    pace: 1.255,
  ),
  Reciter(
    id: 'amer',
    name: 'Ahmad Amer',
    arabicName: 'أحمد عامر',
    style: 'Murattal · measured pace',
    source: SurahFiles(
      'https://server10.mp3quran.net/Aamer',
      timing: Mp3QuranTiming(203),
    ),
    pace: 1.22,
  ),
  Reciter(
    id: 'deban',
    name: 'Ahmad Deban',
    arabicName: 'أحمد ديبان',
    style: 'Murattal · measured pace',
    source: SurahFiles(
      'https://server16.mp3quran.net/deban/Rewayat-Hafs-A-n-Assem',
      timing: Mp3QuranTiming(265),
    ),
    pace: 1.181,
  ),
  Reciter(
    id: 'saber',
    name: 'Ahmad Saber',
    arabicName: 'أحمد صابر',
    style: 'Murattal · steady pace',
    source: SurahFiles(
      'https://server8.mp3quran.net/saber',
      timing: Mp3QuranTiming(8),
    ),
    pace: 1.137,
  ),
  Reciter(
    id: 'shaheen',
    name: 'Ahmad Shaheen',
    arabicName: 'أحمد خليل شاهين',
    style: 'Murattal · measured pace',
    source: SurahFiles(
      'https://server16.mp3quran.net/shaheen/Rewayat-Hafs-A-n-Assem',
      timing: Mp3QuranTiming(256),
    ),
    pace: 1.249,
  ),
  Reciter(
    id: 'alzain',
    name: 'Alzain Mohammad Ahmad',
    arabicName: 'الزين محمد أحمد',
    style: 'Murattal · steady pace',
    source: SurahFiles(
      'https://server9.mp3quran.net/alzain',
      timing: Mp3QuranTiming(13),
    ),
    pace: 1.006,
  ),
  Reciter(
    id: 'emadi',
    name: 'Anas Al-Emadi',
    arabicName: 'أنس العمادي',
    style: 'Murattal · steady pace',
    source: SurahFiles(
      'https://server16.mp3quran.net/a_alemadi/Rewayat-Hafs-A-n-Assem',
      timing: Mp3QuranTiming(314),
    ),
    pace: 1.112,
  ),
  Reciter(
    id: 'hamza',
    name: 'Dawood Hamza',
    arabicName: 'داود حمزة',
    style: 'Murattal · steady pace',
    source: SurahFiles(
      'https://server9.mp3quran.net/hamza',
      timing: Mp3QuranTiming(25),
    ),
    pace: 1.117,
  ),
  Reciter(
    id: 'emad_hafez',
    name: 'Emad Hafez',
    arabicName: 'عماد زهير حافظ',
    style: 'Murattal · measured pace',
    source: SurahFiles(
      'https://server6.mp3quran.net/hafz',
      timing: Mp3QuranTiming(78),
    ),
    pace: 1.253,
  ),
  Reciter(
    id: 'toure',
    name: 'Hady Toure',
    arabicName: 'هادي توري',
    style: 'Murattal · unhurried',
    source: SurahFiles(
      'https://download.quranicaudio.com/qdc/hadi_toure/mp3',
      timing: QulTiming(172),
      padded: false,
    ),
    pace: 1.49,
  ),
  Reciter(
    id: 'dukhain',
    name: 'Haitham Al-Dukhain',
    arabicName: 'هيثم الدخين',
    style: 'Murattal · measured pace',
    source: SurahFiles(
      'https://server16.mp3quran.net/h_dukhain/Rewayat-Hafs-A-n-Assem',
      timing: Mp3QuranTiming(273),
    ),
    pace: 1.214,
  ),
  Reciter(
    id: 'hasan_saleh',
    name: 'Hasan Saleh',
    arabicName: 'حسن صالح',
    style: 'Murattal · brisk',
    source: SurahFiles(
      'https://server16.mp3quran.net/h_saleh/Rewayat-Hafs-A-n-Assem',
      timing: Mp3QuranTiming(299),
    ),
    pace: 0.902,
  ),
  Reciter(
    id: 'daghriri',
    name: 'Hassan Al-Daghriri',
    arabicName: 'حسن الدغريري',
    style: 'Murattal · steady pace',
    source: SurahFiles(
      'https://server16.mp3quran.net/H-Aldaghriri/Rewayat-Hafs-A-n-Assem',
      timing: Mp3QuranTiming(10905),
    ),
    pace: 1.129,
  ),
  Reciter(
    id: 'akhdar',
    name: 'Ibrahim Al-Akhdar',
    arabicName: 'إبراهيم الأخضر',
    style: 'Murattal · unhurried',
    source: SurahFiles(
      'https://server6.mp3quran.net/akdr',
      timing: Mp3QuranTiming(1),
      missing: {93},
    ),
    pace: 1.456,
  ),
  Reciter(
    id: 'asiri',
    name: 'Ibrahim Al-Asiri',
    arabicName: 'إبراهيم العسيري',
    style: 'Murattal · measured pace',
    source: SurahFiles(
      'https://server6.mp3quran.net/3siri',
      timing: Mp3QuranTiming(3),
    ),
    pace: 1.291,
  ),
  Reciter(
    id: 'sanankoua',
    name: 'Issa Omar Sanankoua',
    arabicName: 'عيسى عمر سناكو',
    style: 'Murattal · steady pace',
    source: SurahFiles(
      'https://server16.mp3quran.net/i_sanankoua/Rewayat-Hafs-A-n-Assem',
      timing: Mp3QuranTiming(303),
    ),
    pace: 1.127,
  ),
  Reciter(
    id: 'osaimi',
    name: 'Jamaan Al-Osaimi',
    arabicName: 'جمعان العصيمي',
    style: 'Murattal · steady pace',
    source: SurahFiles(
      'https://server6.mp3quran.net/jaman',
      timing: Mp3QuranTiming(181),
    ),
    pace: 1.025,
  ),
  Reciter(
    id: 'abdulkafi',
    name: 'Khalid Abdulkafi',
    arabicName: 'خالد عبد الكافي',
    style: 'Murattal · brisk',
    source: SurahFiles(
      'https://server11.mp3quran.net/kafi',
      timing: Mp3QuranTiming(22),
    ),
    pace: 0.969,
  ),
  Reciter(
    id: 'mohana',
    name: 'Khalid Al-Mohana',
    arabicName: 'خالد المهنا',
    style: 'Murattal · measured pace',
    source: SurahFiles(
      'https://server11.mp3quran.net/mohna',
      timing: Mp3QuranTiming(159),
    ),
    pace: 1.292,
  ),
  Reciter(
    id: 'mohammadi',
    name: 'Khalid Mohammadi',
    arabicName: 'خالد كريم محمدي',
    style: 'Murattal · measured pace',
    source: SurahFiles(
      'https://server16.mp3quran.net/kh_mohammadi/Rewayat-Hafs-A-n-Assem',
      timing: Mp3QuranTiming(295),
    ),
    pace: 1.17,
  ),
  Reciter(
    id: 'zamil',
    name: 'Majed Al-Zamil',
    arabicName: 'ماجد الزامل',
    style: 'Murattal · steady pace',
    source: SurahFiles(
      'https://server9.mp3quran.net/zaml',
      timing: Mp3QuranTiming(139),
      missing: {3, 31},
    ),
    pace: 1.023,
  ),
  Reciter(
    id: 'bukheet',
    name: 'Mohammad Al-Bukheet',
    arabicName: 'محمد البخيت',
    style: 'Murattal · measured pace',
    source: SurahFiles(
      'https://server14.mp3quran.net/bukheet',
      timing: Mp3QuranTiming(250),
    ),
    pace: 1.292,
  ),
  Reciter(
    id: 'qari',
    name: 'Mohammad Khalil Al-Qari',
    arabicName: 'محمد خليل القارئ',
    style: 'Murattal · steady pace',
    source: SurahFiles(
      'https://server8.mp3quran.net/m_qari',
      timing: Mp3QuranTiming(229),
    ),
    pace: 1.064,
  ),
  Reciter(
    id: 'rashad',
    name: 'Mohammad Rashad Al-Sharif',
    arabicName: 'محمد رشاد الشريف',
    style: 'Murattal · unhurried',
    source: SurahFiles(
      'https://server10.mp3quran.net/rashad',
      timing: Mp3QuranTiming(198),
    ),
    pace: 1.302,
  ),
  Reciter(
    id: 'alim_shah',
    name: 'Mohammad Saleh Alim Shah',
    arabicName: 'محمد صالح عالم شاه',
    style: 'Murattal · brisk',
    source: SurahFiles(
      'https://server12.mp3quran.net/shah',
      timing: Mp3QuranTiming(110),
    ),
    pace: 0.969,
  ),
  Reciter(
    id: 'burhaji',
    name: 'Muhammad Burhaji',
    arabicName: 'محمد برهجي',
    style: 'Murattal · steady pace',
    source: SurahFiles(
      'https://server16.mp3quran.net/M_Burhaji/Rewayat-Hafs-A-n-Assem',
      timing: Mp3QuranTiming(340),
    ),
    pace: 1.057,
  ),
  Reciter(
    id: 'nabil_rifai',
    name: 'Nabil Ar-Rifai',
    arabicName: 'نبيل الرفاعي',
    style: 'Murattal · steady pace',
    source: SurahFiles(
      'https://server9.mp3quran.net/nabil',
      timing: Mp3QuranTiming(87),
      missing: {27},
    ),
    pace: 1.06,
  ),
  Reciter(
    id: 'hassan',
    name: 'Neamah Al-Hassan',
    arabicName: 'نعمة الحسان',
    style: 'Murattal · unhurried',
    source: SurahFiles(
      'https://server8.mp3quran.net/namh',
      timing: Mp3QuranTiming(88),
    ),
    pace: 1.323,
  ),
  Reciter(
    id: 'peshawa',
    name: 'Peshawa Qadr Al-Kurdi',
    arabicName: 'بيشه وا قادر الكردي',
    style: 'Murattal · steady pace',
    source: SurahFiles(
      'https://server16.mp3quran.net/peshawa/Rewayat-Hafs-A-n-Assem',
      timing: Mp3QuranTiming(268),
      missing: {63},
    ),
    pace: 1.081,
  ),
  Reciter(
    id: 'raad_kurdi',
    name: 'Raad Al-Kurdi',
    arabicName: 'رعد محمد الكردي',
    style: 'Murattal · unhurried',
    source: SurahFiles(
      'https://server6.mp3quran.net/kurdi',
      timing: Mp3QuranTiming(221),
      missing: {23},
    ),
    pace: 1.398,
  ),
  Reciter(
    id: 'abdulhakam',
    name: 'Saber Abdulhakam',
    arabicName: 'صابر عبد الحكم',
    style: 'Murattal · steady pace',
    source: SurahFiles(
      'https://server12.mp3quran.net/hkm',
      timing: Mp3QuranTiming(39),
    ),
    pace: 1.027,
  ),
  Reciter(
    id: 'hashim',
    name: 'Salah Al-Hashim',
    arabicName: 'صلاح الهاشم',
    style: 'Murattal · measured pace',
    source: SurahFiles(
      'https://server12.mp3quran.net/salah_hashim_m',
      timing: Mp3QuranTiming(44),
    ),
    pace: 1.152,
  ),
  Reciter(
    id: 'sahood',
    name: 'Saleh Al-Sahood',
    arabicName: 'صالح الصاهود',
    style: 'Murattal · measured pace',
    source: SurahFiles(
      'https://server8.mp3quran.net/sahood',
      timing: Mp3QuranTiming(40),
    ),
    pace: 1.165,
  ),
  Reciter(
    id: 'shamrani',
    name: 'Saleh Al-Shamrani',
    arabicName: 'صالح الشمراني',
    style: 'Murattal · brisk',
    source: SurahFiles(
      'https://server16.mp3quran.net/shamrani/Rewayat-Hafs-A-n-Assem',
      timing: Mp3QuranTiming(300),
    ),
    pace: 0.996,
  ),
  Reciter(
    id: 'hashemi',
    name: 'Sayed Ahmad Hashemi',
    arabicName: 'سيد أحمد هاشمي',
    style: 'Murattal · measured pace',
    source: SurahFiles(
      'https://server16.mp3quran.net/s_hashemi/Rewayat-Hafs-A-n-Assem',
      timing: Mp3QuranTiming(294),
    ),
    pace: 1.231,
  ),
  Reciter(
    id: 'taher',
    name: 'Shirzad Taher',
    arabicName: 'شيرزاد عبد الرحمن طاهر',
    style: 'Murattal · measured pace',
    source: SurahFiles(
      'https://server12.mp3quran.net/taher',
      timing: Mp3QuranTiming(38),
    ),
    pace: 1.257,
  ),
  Reciter(
    id: 'sayegh',
    name: 'Tawfeeq As-Sayegh',
    arabicName: 'توفيق الصايغ',
    style: 'Murattal · steady pace',
    source: SurahFiles(
      'https://server6.mp3quran.net/twfeeq',
      timing: Mp3QuranTiming(17),
    ),
    pace: 1.107,
  ),
  Reciter(
    id: 'noah',
    name: 'Yousef Bin Noah Ahmad',
    arabicName: 'يوسف بن نوح أحمد',
    style: 'Murattal · brisk',
    source: SurahFiles(
      'https://server8.mp3quran.net/noah',
      timing: Mp3QuranTiming(193),
    ),
    pace: 0.958,
  ),
  Reciter(
    id: 'daghistani',
    name: 'Zaki Daghistani',
    arabicName: 'زكي داغستاني',
    style: 'Murattal · unhurried',
    source: SurahFiles(
      'https://server9.mp3quran.net/zaki',
      timing: Mp3QuranTiming(33),
    ),
    pace: 1.544,
  ),
  // His one complete recording (the King Fahd Complex's of 2019, on
  // mp3quran) comes with no verse table, so it reads one of our own,
  // made from the recording itself and checked against it like any
  // other, served only to the app (OwnTiming: VerseTables in
  // lib/data/verse_tables.dart, tool/verse_table.py).
  Reciter(
    id: 'luhaidan',
    name: 'Mohammed Al-Luhaidan',
    arabicName: 'محمد اللحيدان',
    style: 'Murattal · steady pace',
    source: SurahFiles(
      'https://cdn.mp3quran.net/audio/muhammad-luhaidan/r1',
      timing: OwnTiming('luhaidan'),
    ),
    pace: 1.098,
  ),
  // ── Mujawwad ─────────────────────────────────────────────────────
  // The ornate, slow style of the great Egyptian masters — kept as
  // separate voices so the murattal sets above stay the default.
  // [Reciter.pace] says how much longer they take over the same text,
  // which is the only thing the verse picker has to go on before a
  // note of the recitation has been downloaded.
  Reciter(
    id: 'husary_mujawwad',
    name: 'Al-Husary · Mujawwad',
    arabicName: 'محمود الحصري',
    style: 'Mujawwad · ornate, masterly',
    source: AyahFiles.everyAyah('Husary_128kbps_Mujawwad'),
    pace: 2.0,
  ),
  Reciter(
    id: 'abdulbasit_mujawwad',
    name: 'Abdul Basit · Mujawwad',
    arabicName: 'عبد الباسط عبد الصمد',
    style: 'Mujawwad · majestic, soaring',
    source: AyahFiles.everyAyah('Abdul_Basit_Mujawwad_128kbps'),
    pace: 2.2,
  ),
  Reciter(
    id: 'minshawi_mujawwad',
    name: 'Al-Minshawi · Mujawwad',
    arabicName: 'محمد صديق المنشاوي',
    style: 'Mujawwad · transcendent, classic',
    source: AyahFiles.everyAyah('Minshawy_Mujawwad_192kbps'),
    pace: 2.1,
  ),
  Reciter(
    id: 'muaiqly_mujawwad',
    name: 'Al-Muaiqly · Mujawwad',
    arabicName: 'ماهر المعيقلي',
    style: 'Mujawwad · unhurried',
    source: SurahFiles(
      'https://server12.mp3quran.net/maher/Almusshaf-Al-Mojawwad',
      timing: Mp3QuranTiming(133),
    ),
    pace: 1.407,
  ),
  Reciter(
    id: 'albanna_mujawwad',
    name: 'Al-Banna · Mujawwad',
    arabicName: 'محمود علي البنا',
    style: 'Mujawwad · unhurried',
    source: SurahFiles(
      'https://server8.mp3quran.net/bna/Almusshaf-Al-Mojawwad',
      timing: Mp3QuranTiming(122),
    ),
    pace: 2.943,
  ),
  Reciter(
    id: 'mustafa_ismail_mujawwad',
    name: 'Mustafa Ismail · Mujawwad',
    arabicName: 'مصطفى إسماعيل',
    style: 'Mujawwad · unhurried',
    source: SurahFiles(
      'https://server8.mp3quran.net/mustafa/Almusshaf-Al-Mojawwad',
      timing: Mp3QuranTiming(288),
    ),
    pace: 3.367,
  ),
  // ── Other recordings ─────────────────────────────────────────────
  // Another performance by a voice above, so that reels of the same
  // verses need not all carry the same sound ([Reciter.recordingOf]).
  // Each passed tool/verify_reciters.py as a voice of its own — every
  // file, every table, its pace — and was compared with every other
  // recording of its voice, waveforms and verse lengths over 162 verses
  // (9. in its docstring): the same performance from another host,
  // re-encoded or cut another way, is not another recording. Every
  // other set of the app's voices with verse files or a verse table was
  // looked at; the tool's docstring says what was left out and why.
  Reciter(
    id: 'alafasy_2',
    name: 'Mishary Alafasy',
    arabicName: 'مشاري العفاسي',
    style: 'Murattal · warm, melodic',
    source: SurahFiles(
      'https://download.quranicaudio.com/quran/mishaari_california',
      timing: QulTiming(95),
    ),
    pace: 1.271,
    recordingOf: 'alafasy',
    recordingNote: 'Taraweeh · California · 1430',
  ),
  // mp3quran's table for Al-Baqarah gives 2:149 no length (its start is
  // 2:150's), so that one surah is not offered with this recording.
  Reciter(
    id: 'basfar_2',
    name: 'Abdullah Basfar',
    arabicName: 'عبد الله بصفر',
    style: 'Murattal · clear, contemplative',
    source: SurahFiles(
      'https://cdn.mp3quran.net/audio/abdullah-basfar/r1',
      timing: Mp3QuranTiming(60),
      missing: {2},
    ),
    pace: 1.101,
    recordingOf: 'basfar',
    recordingNote: 'Mushaf recording · 2007',
  ),
];

/// The voices the pickers list: one card per reciter, each its first
/// recording. A voice's other recordings ([Reciter.recordingOf]) are
/// chosen on its card, never listed beside it.
final List<Reciter> voices = List.unmodifiable(
    [for (final r in reciters) if (r.recordingOf == null) r]);

/// Every recording of [r]'s reciter: the voice's first recording, then
/// the others in list order. Just `[r]` for a voice with one.
List<Reciter> recordingsOf(Reciter r) {
  final root = r.recordingOf ?? r.id;
  return [
    for (final x in reciters)
      if (x.id == root || x.recordingOf == root) x,
  ];
}

/// The voice [r] is a recording of: [r] itself for a first recording.
Reciter voiceOf(Reciter r) {
  final root = r.recordingOf;
  if (root == null) return r;
  for (final x in reciters) {
    if (x.id == root) return x;
  }
  return r;
}

/// The sceneries bundled inside the app. The full library is much
/// larger and lives in [SceneCatalog]; these are the ones that work
/// before the device has ever seen a network, so every picker tab has
/// something in it on a cold install.
const backgrounds = <ReelBackground>[
  ReelBackground.still(
    id: 'abstract_pexels_01',
    name: 'Abstract 1',
    imageAsset: 'assets/backgrounds/abstract_pexels_01.jpg',
    gradientArgb: [0xFF0E0A0A, 0xFF9A2B01],
  ),
  ReelBackground.still(
    id: 'abstract_pexels_02',
    name: 'Abstract 2',
    imageAsset: 'assets/backgrounds/abstract_pexels_02.jpg',
    gradientArgb: [0xFF353A25, 0xFF312C15],
  ),
  ReelBackground(
    id: 'abstract_pexels_05',
    name: 'Abstract 3',
    videoAsset: 'assets/backgrounds/abstract_pexels_05.mp4',
    gradientArgb: [0xFF232018, 0xFF1E1B15],
  ),
  ReelBackground(
    id: 'abstract_pexels_18',
    name: 'Abstract 4',
    videoAsset: 'assets/backgrounds/abstract_pexels_18.mp4',
    gradientArgb: [0xFF0A0D0B, 0xFF0F0F0C],
  ),
  ReelBackground.still(
    id: 'desert_pexels_01',
    name: 'Desert 1',
    imageAsset: 'assets/backgrounds/desert_pexels_01.jpg',
    gradientArgb: [0xFF1C5179, 0xFF482A19],
  ),
  ReelBackground.still(
    id: 'desert_pexels_02',
    name: 'Desert 2',
    imageAsset: 'assets/backgrounds/desert_pexels_02.jpg',
    gradientArgb: [0xFF0C1B2F, 0xFFA96220],
  ),
  ReelBackground.still(
    id: 'forest_pixabay_02',
    name: 'Forest 1',
    imageAsset: 'assets/backgrounds/forest_pixabay_02.jpg',
    gradientArgb: [0xFF171C2E, 0xFF4B5344],
  ),
  ReelBackground.still(
    id: 'forest_wallhaven_01',
    name: 'Forest 2',
    imageAsset: 'assets/backgrounds/forest_wallhaven_01.jpg',
    gradientArgb: [0xFF114F5A, 0xFF092429],
  ),
  ReelBackground.still(
    id: 'mountains_pexels_01',
    name: 'Mountains 1',
    imageAsset: 'assets/backgrounds/mountains_pexels_01.jpg',
    gradientArgb: [0xFF63533A, 0xFF151711],
  ),
  ReelBackground.still(
    id: 'mountains_pexels_02',
    name: 'Mountains 2',
    imageAsset: 'assets/backgrounds/mountains_pexels_02.jpg',
    gradientArgb: [0xFF72766F, 0xFF000000],
  ),
  ReelBackground(
    id: 'mountains_pexels_06',
    name: 'Mountains 3',
    videoAsset: 'assets/backgrounds/mountains_pexels_06.mp4',
    gradientArgb: [0xFF797A7A, 0xFF0D0E10],
  ),
  ReelBackground.still(
    id: 'road_openverse_01',
    name: 'Road 1',
    imageAsset: 'assets/backgrounds/road_openverse_01.jpg',
    gradientArgb: [0xFF515D65, 0xFF4C555A],
  ),
  ReelBackground.still(
    id: 'road_pexels_01',
    name: 'Road 2',
    imageAsset: 'assets/backgrounds/road_pexels_01.jpg',
    gradientArgb: [0xFF06485F, 0xFF272827],
  ),
  ReelBackground.still(
    id: 'sacred_pexels_03',
    name: 'Sacred 1',
    imageAsset: 'assets/backgrounds/sacred_pexels_03.jpg',
    gradientArgb: [0xFF4D3935, 0xFF111011],
  ),
  ReelBackground.still(
    id: 'aurora_pexels_01',
    name: 'Aurora 1',
    imageAsset: 'assets/backgrounds/aurora_pexels_01.jpg',
    gradientArgb: [0xFF2E252A, 0xFF111C14],
  ),
  ReelBackground.still(
    id: 'aurora_pexels_02',
    name: 'Aurora 2',
    imageAsset: 'assets/backgrounds/aurora_pexels_02.jpg',
    gradientArgb: [0xFF201238, 0xFF000001],
  ),
  ReelBackground.still(
    id: 'ocean_pixabay_01',
    name: 'Ocean 1',
    imageAsset: 'assets/backgrounds/ocean_pixabay_01.jpg',
    gradientArgb: [0xFF25345C, 0xFF202C4C],
  ),
  ReelBackground.still(
    id: 'ocean_pixabay_02',
    name: 'Ocean 2',
    imageAsset: 'assets/backgrounds/ocean_pixabay_02.jpg',
    gradientArgb: [0xFF3A2F6A, 0xFF45346C],
  ),
  ReelBackground(
    id: 'rain_pixabay_06',
    name: 'Rain',
    videoAsset: 'assets/backgrounds/rain_pixabay_06.mp4',
    gradientArgb: [0xFF010201, 0xFF020202],
  ),
  ReelBackground.still(
    id: 'aerial_coast_openverse_01',
    name: 'Aerial coast 1',
    imageAsset: 'assets/backgrounds/aerial_coast_openverse_01.jpg',
    gradientArgb: [0xFF404140, 0xFF7C8081],
    knownAspect: 1920 / 1080,
  ),
  ReelBackground.still(
    id: 'aerial_coast_pexels_04',
    name: 'Aerial coast 2',
    imageAsset: 'assets/backgrounds/aerial_coast_pexels_04.jpg',
    gradientArgb: [0xFF5E5141, 0xFF725C46],
    knownAspect: 1920 / 1080,
  ),
  ReelBackground.still(
    id: 'cinematic_commons_01',
    name: 'Cinematic 1',
    imageAsset: 'assets/backgrounds/cinematic_commons_01.jpg',
    gradientArgb: [0xFF9BABAC, 0xFF476236],
    knownAspect: 1920 / 1080,
  ),
  ReelBackground.still(
    id: 'cinematic_pixabay_12',
    name: 'Cinematic 2',
    imageAsset: 'assets/backgrounds/cinematic_pixabay_12.jpg',
    gradientArgb: [0xFF8B8367, 0xFF3D3629],
    knownAspect: 1920 / 1080,
  ),
];
