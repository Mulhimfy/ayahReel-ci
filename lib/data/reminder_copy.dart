import '../l10n/app_lang.dart';

/// One day's wording for a reminder.
typedef ReminderLine = ({String title, String body});

/// What a day's notification invites to: a Quran quiz round, or a reel.
enum NudgeKind { quiz, reel }

/// The part of the day a notification lands in, which its words name:
/// "…before you sleep", "…this morning".
enum DayPart { morning, afternoon, evening, night }

/// The one notification a day: which kind it is, and what it says.
///
/// **One a day, three quizzes to two reels.** The days run in fives —
/// quiz, reel, quiz, quiz, reel — so the mix is the same every week
/// without two quizzes ever arriving three days running.
///
/// **Never wallpaper.** Each kind has fifteen lines and walks through
/// them in order, one per day of that kind, so a quiz line comes back
/// after twenty-five days and a reel line after thirty-seven. The pick
/// is a pure function of the calendar day, so it needs nothing stored
/// and a window laid down twice says the same thing both times.
///
/// **Said for the hour it arrives.** A notification carries its text
/// from the moment it's scheduled, and the time it will fire is known
/// then, so every line names the part of the day it lands in — the `{t}`
/// in each template: "before you sleep", "tonight", "before bed" at
/// nine at night, taken in turn so the ending isn't the same every
/// night; "this morning" and its kin at seven. The lines used to be
/// written for the evening only, and "…while you sleep" at breakfast
/// read like a mistake.
///
/// The quiz lines never name the quiz: they say what it is — a verse
/// to finish, a surah to name, a friend to challenge.
abstract final class ReminderCopy {
  // ---- the plan -----------------------------------------------------

  /// Five days: three quizzes, two reels.
  static const pattern = [
    NudgeKind.quiz,
    NudgeKind.reel,
    NudgeKind.quiz,
    NudgeKind.quiz,
    NudgeKind.reel,
  ];

  /// Moves whenever what the notifications say changes. A window is
  /// laid down weeks ahead with its words fixed in it, so one laid in
  /// other words is laid again at the next launch rather than left to
  /// run out — see `ReminderService`.
  static const version = 2;

  /// Days since a fixed Monday, counted on UTC midnights of the local
  /// date: a local-time subtraction across a DST change is 23 or 25
  /// hours, and would skip or repeat a line.
  static int dayNumber(DateTime day) =>
      DateTime.utc(day.year, day.month, day.day)
          .difference(DateTime.utc(2024, 1, 1))
          .inDays;

  static NudgeKind kindOn(DateTime day) =>
      pattern[dayNumber(day) % pattern.length];

  /// How many days of [day]'s kind came before it: the index into that
  /// kind's lines (and pictures).
  static int ordinalOn(DateTime day) {
    final n = dayNumber(day);
    final kind = pattern[n % pattern.length];
    final perCycle = pattern.where((k) => k == kind).length;
    final before = [
      for (var i = 0; i < n % pattern.length; i++)
        if (pattern[i] == kind) i,
    ].length;
    return n ~/ pattern.length * perCycle + before;
  }

  /// Morning from four until noon, afternoon until five, evening until
  /// eight, and night — "before you sleep" — from eight until four.
  static DayPart partOf(int hour) => switch (hour) {
        >= 4 && < 12 => DayPart.morning,
        >= 12 && < 17 => DayPart.afternoon,
        >= 17 && < 20 => DayPart.evening,
        _ => DayPart.night,
      };

  /// The line for the notification at [when], in [lang].
  static ReminderLine forDay(DateTime when, {AppLang lang = AppLang.en}) {
    final pool = (kindOn(when) == NudgeKind.quiz ? quizPools : reelPools)[lang]!;
    final line = pool[ordinalOn(when) % pool.length];
    final t = phraseFor(when, lang);
    return (
      title: line.title.replaceAll('{t}', t),
      body: line.body.replaceAll('{t}', t),
    );
  }

  // ---- the part of the day ------------------------------------------

  /// What `{t}` becomes, by language and part of the day: a few ways of
  /// saying the same moment, taken in turn one day to the next, so a
  /// notification that comes at nine every night doesn't end the same
  /// way every night. The two that mean nearly the same — before you
  /// sleep, before bed — are never neighbours. Each is an adverbial
  /// every template can take, mid-sentence or at the end, and none
  /// mentions food or drink: a month of the year is spent fasting.
  static const timePhrases = <AppLang, Map<DayPart, List<String>>>{
    AppLang.en: {
      DayPart.morning: [
        'this morning',
        'while the day is young',
        'before the day gets busy',
      ],
      DayPart.afternoon: [
        'this afternoon',
        'before the day ends',
        'on your break',
      ],
      DayPart.evening: [
        'this evening',
        'tonight',
        'as the day winds down',
      ],
      DayPart.night: [
        'before you sleep',
        'tonight',
        'before bed',
        'at the end of your day',
      ],
    },
    AppLang.ar: {
      DayPart.morning: ['هذا الصباح', 'في أول يومك', 'قبل أن تنشغل بيومك'],
      DayPart.afternoon: ['بعد الظهر', 'قبل أن ينقضي يومك', 'في استراحتك'],
      DayPart.evening: ['هذا المساء', 'الليلة', 'مع انقضاء النهار'],
      DayPart.night: [
        'قبل أن تنام',
        'الليلة',
        'قبل أن تأوي إلى فراشك',
        'في ختام يومك',
      ],
    },
    AppLang.ur: {
      DayPart.morning: ['آج صبح', 'دن کے آغاز میں', 'دن کی مصروفیت سے پہلے'],
      DayPart.afternoon: ['آج دوپہر', 'دن ڈھلنے سے پہلے', 'اپنے وقفے میں'],
      DayPart.evening: ['آج شام', 'آج رات', 'دن ڈھلتے'],
      DayPart.night: [
        'سونے سے پہلے',
        'آج رات',
        'بستر پر جانے سے پہلے',
        'دن کے اختتام پر',
      ],
    },
    AppLang.id: {
      DayPart.morning: [
        'pagi ini',
        'di awal hari',
        'sebelum hari mulai sibuk',
      ],
      DayPart.afternoon: [
        'siang ini',
        'sebelum hari berakhir',
        'di sela istirahat',
      ],
      DayPart.evening: ['petang ini', 'malam ini', 'menjelang malam'],
      DayPart.night: [
        'sebelum tidur',
        'malam ini',
        'sebelum beristirahat',
        'di penghujung hari',
      ],
    },
    AppLang.de: {
      DayPart.morning: [
        'heute Morgen',
        'zum Start in den Tag',
        'vor dem Trubel des Tages',
      ],
      DayPart.afternoon: [
        'heute Nachmittag',
        'im Laufe des Tages',
        'in deiner Pause',
      ],
      DayPart.evening: ['heute Abend', 'zum Feierabend', 'am frühen Abend'],
      DayPart.night: [
        'vor dem Schlafen',
        'heute Abend',
        'vor dem Zubettgehen',
        'zum Tagesausklang',
      ],
    },
  };

  /// The phrase for the notification at [when]: the day's turn through
  /// its part of the day's phrases, so no two days running end alike.
  static String phraseFor(DateTime when, AppLang lang) {
    final phrases = timePhrases[lang]![partOf(when.hour)]!;
    return phrases[dayNumber(when) % phrases.length];
  }

  // ---- quizzes --------------------------------------------------------

  /// Fifteen invitations to a round: finish the verse, the missing
  /// word, which surah, what comes next, the words back in order — and
  /// the friend to send the same round to.
  static const quizLines = <ReminderLine>[
    (
      title: 'How well do you know the Quran? ✦',
      body: 'Five questions, one minute. Find out {t}.',
    ),
    (
      title: 'Finish the verse ✦',
      body: 'You know how it goes. Prove it in a Quran quiz {t}.',
    ),
    (
      title: 'Challenge a friend ✦',
      body: 'Play a Quran quiz {t}, then send them the same round to beat.',
    ),
    (
      title: 'Which surah is it? ✦',
      body: 'Name the surah from a single verse. Try a round {t}.',
    ),
    (
      title: 'One word is missing ✦',
      body: 'Find it against the clock. Play a Quran quiz {t}.',
    ),
    (
      title: 'Five questions from the Quran ✦',
      body: 'How many will you get right {t}?',
    ),
    (
      title: 'Test yourself with the Quran ✦',
      body: 'A short quiz on the verses you know best. Play it {t}.',
    ),
    (
      title: 'Keep what you’ve memorised ✦',
      body: 'A few questions {t} keep the verses fresh.',
    ),
    (
      title: 'Your score, their turn ✦',
      body: 'Play a Quran quiz {t}, then dare a friend to beat it.',
    ),
    (
      title: 'Which verse comes next? ✦',
      body: 'Put the next ayah in its place. One round {t}.',
    ),
    (
      title: 'Juz ʿAmma or Al-Baqarah? ✦',
      body: 'Pick the part you know and play a Quran quiz {t}.',
    ),
    (
      title: 'A minute with the Quran ✦',
      body: 'Test yourself {t}, then challenge a friend.',
    ),
    (
      title: 'Beat your best ✦',
      body: 'Your last Quran quiz score is waiting. Try again {t}.',
    ),
    (
      title: 'Put the verse back together ✦',
      body: 'The words are scattered. Set them in order {t}.',
    ),
    (
      title: 'Learn it, then share it ✦',
      body: 'Play a Quran quiz {t} and send a friend the same questions.',
    ),
  ];

  static const quizLinesAr = <ReminderLine>[
    (
      title: 'كم تعرف من القرآن؟ ✦',
      body: 'خمسة أسئلة في دقيقة واحدة. اكتشف ذلك {t}.',
    ),
    (
      title: 'أكمل الآية ✦',
      body: 'تعرف كيف تمضي. أثبت ذلك في مسابقة قرآنية {t}.',
    ),
    (
      title: 'تحدَّ صديقًا ✦',
      body: 'العب مسابقة قرآنية {t}، ثم أرسل له الجولة نفسها ليتغلب عليها.',
    ),
    (
      title: 'من أي سورة هذه؟ ✦',
      body: 'اعرف السورة من آية واحدة. جرّب جولة {t}.',
    ),
    (
      title: 'كلمة ناقصة ✦',
      body: 'سابِق الوقت لتجدها. العب مسابقة قرآنية {t}.',
    ),
    (
      title: 'خمسة أسئلة من القرآن ✦',
      body: 'كم منها ستجيب عنه إجابة صحيحة {t}؟',
    ),
    (
      title: 'اختبر نفسك في القرآن ✦',
      body: 'مسابقة قصيرة في الآيات التي تحفظها جيدًا. العبها {t}.',
    ),
    (
      title: 'حافظ على ما حفظت ✦',
      body: 'أسئلة قليلة {t} تُبقي الآيات حاضرة.',
    ),
    (
      title: 'نتيجتك، والدور عليه ✦',
      body: 'العب مسابقة قرآنية {t}، ثم تحدَّ صديقًا أن يتفوق عليك.',
    ),
    (
      title: 'ما الآية التالية؟ ✦',
      body: 'ضع الآية التالية في مكانها. جولة واحدة {t}.',
    ),
    (
      title: 'جزء عمّ أم البقرة؟ ✦',
      body: 'اختر الجزء الذي تعرفه والعب مسابقة قرآنية {t}.',
    ),
    (
      title: 'دقيقة مع القرآن ✦',
      body: 'اختبر نفسك {t}، ثم تحدَّ صديقًا.',
    ),
    (
      title: 'تغلّب على أفضل نتيجة لك ✦',
      body: 'نتيجتك في آخر مسابقة قرآنية بانتظارك. حاول مجددًا {t}.',
    ),
    (
      title: 'أعد ترتيب الآية ✦',
      body: 'الكلمات متفرقة. رتّبها {t}.',
    ),
    (
      title: 'تعلّم، ثم شارك ✦',
      body: 'العب مسابقة قرآنية {t} وأرسل لصديق الأسئلة نفسها.',
    ),
  ];

  static const quizLinesUr = <ReminderLine>[
    (
      title: 'آپ قرآن کو کتنا جانتے ہیں؟ ✦',
      body: 'پانچ سوال، ایک منٹ۔ {t} جان لیں۔',
    ),
    (
      title: 'آیت مکمل کریں ✦',
      body: 'آپ جانتے ہیں یہ کیسے آگے بڑھتی ہے۔ {t} قرآنی کوئز میں ثابت کریں۔',
    ),
    (
      title: 'کسی دوست کو چیلنج کریں ✦',
      body: '{t} قرآنی کوئز کھیلیں، پھر یہی راؤنڈ دوست کو بھیجیں۔',
    ),
    (
      title: 'یہ کون سی سورت ہے؟ ✦',
      body: 'ایک آیت سے سورت پہچانیں۔ {t} ایک راؤنڈ کھیلیں۔',
    ),
    (
      title: 'ایک لفظ غائب ہے ✦',
      body: 'وقت کے مقابلے میں اسے ڈھونڈیں۔ {t} قرآنی کوئز کھیلیں۔',
    ),
    (
      title: 'قرآن سے پانچ سوال ✦',
      body: '{t} آپ کتنے درست جواب دیں گے؟',
    ),
    (
      title: 'قرآن سے خود کو آزمائیں ✦',
      body: 'اُن آیات پر ایک مختصر کوئز جو آپ کو خوب یاد ہیں۔ {t} کھیلیں۔',
    ),
    (
      title: 'جو یاد کیا، اسے تازہ رکھیں ✦',
      body: '{t} چند سوال آیات کو تازہ رکھتے ہیں۔',
    ),
    (
      title: 'آپ کا اسکور، اب اُن کی باری ✦',
      body: '{t} قرآنی کوئز کھیلیں، پھر دوست کو ہرانے کا چیلنج دیں۔',
    ),
    (
      title: 'اگلی آیت کون سی ہے؟ ✦',
      body: 'اگلی آیت کو اس کی جگہ رکھیں۔ {t} ایک راؤنڈ۔',
    ),
    (
      title: 'جزء عمّ یا البقرہ؟ ✦',
      body: 'جو حصہ آپ جانتے ہیں وہ چنیں اور {t} قرآنی کوئز کھیلیں۔',
    ),
    (
      title: 'قرآن کے ساتھ ایک منٹ ✦',
      body: '{t} خود کو آزمائیں، پھر کسی دوست کو چیلنج کریں۔',
    ),
    (
      title: 'اپنا ریکارڈ توڑیں ✦',
      body: 'آپ کے پچھلے قرآنی کوئز کا اسکور منتظر ہے۔ {t} پھر کوشش کریں۔',
    ),
    (
      title: 'آیت کو پھر سے جوڑیں ✦',
      body: 'الفاظ بکھرے ہوئے ہیں۔ {t} انہیں ترتیب دیں۔',
    ),
    (
      title: 'سیکھیں، پھر شیئر کریں ✦',
      body: '{t} قرآنی کوئز کھیلیں اور دوست کو یہی سوال بھیجیں۔',
    ),
  ];

  static const quizLinesId = <ReminderLine>[
    (
      title: 'Seberapa kenal Anda dengan Al-Qur’an? ✦',
      body: 'Lima pertanyaan, satu menit. Cari tahu {t}.',
    ),
    (
      title: 'Lengkapi ayatnya ✦',
      body: 'Anda tahu lanjutannya. Buktikan di kuis Al-Qur’an {t}.',
    ),
    (
      title: 'Tantang seorang teman ✦',
      body: 'Main kuis Al-Qur’an {t}, lalu kirim ronde yang sama untuk ia '
          'kalahkan.',
    ),
    (
      title: 'Surah apakah ini? ✦',
      body: 'Tebak surahnya dari satu ayat. Coba satu ronde {t}.',
    ),
    (
      title: 'Satu kata hilang ✦',
      body: 'Temukan sambil berpacu dengan waktu. Main kuis Al-Qur’an {t}.',
    ),
    (
      title: 'Lima pertanyaan dari Al-Qur’an ✦',
      body: 'Berapa yang bisa Anda jawab benar {t}?',
    ),
    (
      title: 'Uji diri dengan Al-Qur’an ✦',
      body: 'Kuis singkat tentang ayat yang paling Anda hafal. Mainkan {t}.',
    ),
    (
      title: 'Jaga hafalan Anda ✦',
      body: 'Beberapa pertanyaan {t} menjaga ayat tetap segar.',
    ),
    (
      title: 'Skor Anda, gilirannya ✦',
      body: 'Main kuis Al-Qur’an {t}, lalu tantang teman untuk '
          'mengalahkannya.',
    ),
    (
      title: 'Ayat mana berikutnya? ✦',
      body: 'Letakkan ayat berikutnya di tempatnya. Satu ronde {t}.',
    ),
    (
      title: 'Juz ʿAmma atau Al-Baqarah? ✦',
      body: 'Pilih bagian yang Anda kuasai dan main kuis Al-Qur’an {t}.',
    ),
    (
      title: 'Semenit bersama Al-Qur’an ✦',
      body: 'Uji diri Anda {t}, lalu tantang seorang teman.',
    ),
    (
      title: 'Kalahkan rekor Anda ✦',
      body: 'Skor kuis Al-Qur’an terakhir Anda menunggu. Coba lagi {t}.',
    ),
    (
      title: 'Susun kembali ayatnya ✦',
      body: 'Kata-katanya berserakan. Susun urutannya {t}.',
    ),
    (
      title: 'Pelajari, lalu bagikan ✦',
      body: 'Main kuis Al-Qur’an {t} dan kirim pertanyaan yang sama ke teman.',
    ),
  ];

  static const quizLinesDe = <ReminderLine>[
    (
      title: 'Wie gut kennst du den Quran? ✦',
      body: 'Fünf Fragen, eine Minute. Find es {t} heraus.',
    ),
    (
      title: 'Vervollständige den Vers ✦',
      body: 'Du weißt, wie er weitergeht. Beweis es {t} in einem Quran-Quiz.',
    ),
    (
      title: 'Fordere einen Freund heraus ✦',
      body: 'Spiel {t} ein Quran-Quiz und schick ihm dieselbe Runde.',
    ),
    (
      title: 'Welche Sure ist das? ✦',
      body: 'Erkenne die Sure an einem einzigen Vers. Spiel {t} eine Runde.',
    ),
    (
      title: 'Ein Wort fehlt ✦',
      body: 'Finde es gegen die Uhr. Spiel {t} ein Quran-Quiz.',
    ),
    (
      title: 'Fünf Fragen aus dem Quran ✦',
      body: 'Wie viele beantwortest du {t} richtig?',
    ),
    (
      title: 'Teste dich mit dem Quran ✦',
      body: 'Ein kurzes Quiz zu den Versen, die du am besten kennst. Spiel es '
          '{t}.',
    ),
    (
      title: 'Halte Gelerntes frisch ✦',
      body: 'Ein paar Fragen {t} halten die Verse lebendig.',
    ),
    (
      title: 'Dein Punktestand, sein Zug ✦',
      body: 'Spiel {t} ein Quran-Quiz und fordere einen Freund heraus, es '
          'besser zu machen.',
    ),
    (
      title: 'Welcher Vers kommt als Nächstes? ✦',
      body: 'Setz den nächsten Vers an seinen Platz. Eine Runde {t}.',
    ),
    (
      title: 'Juz ʿAmma oder Al-Baqara? ✦',
      body: 'Wähl den Teil, den du kennst, und spiel {t} ein Quran-Quiz.',
    ),
    (
      title: 'Eine Minute mit dem Quran ✦',
      body: 'Teste dich {t} und fordere dann einen Freund heraus.',
    ),
    (
      title: 'Schlag deinen Bestwert ✦',
      body: 'Dein letzter Quiz-Punktestand wartet. Versuch es {t} noch einmal.',
    ),
    (
      title: 'Setz den Vers wieder zusammen ✦',
      body: 'Die Wörter liegen durcheinander. Bring sie {t} in Ordnung.',
    ),
    (
      title: 'Lernen, dann teilen ✦',
      body: 'Spiel {t} ein Quran-Quiz und schick einem Freund dieselben '
          'Fragen.',
    ),
  ];

  // ---- reels ------------------------------------------------------------

  /// Fifteen ways of asking for one reel, with the angles deliberately
  /// mixed — continuing reward, guiding to good, the feed, the streak,
  /// the speed, plain quiet — because a user who gets the same argument
  /// fifteen times stops hearing any of it.
  static const reelLines = <ReminderLine>[
    (
      title: 'One verse. One minute. ✦',
      body: 'Make a reel {t} and let it keep earning long after you close '
          'the app.',
    ),
    (
      title: 'Sadaqah jariyah, in under a minute ✦',
      body: 'Create one ayah reel {t}. Its reward keeps running long after.',
    ),
    (
      title: 'Someone’s feed needs this ✦',
      body: 'Send one verse {t}. You’ll never know who it reaches.',
    ),
    (
      title: 'Be the reason ✦',
      body: 'Share one ayah {t} and be the reason there’s Quran on '
          'someone’s phone.',
    ),
    (
      title: 'Your streak is waiting ✦',
      body: 'One reel {t} keeps it alive, and it takes less than a minute.',
    ),
    (
      title: 'Whoever guides to good ✦',
      body: '…has the reward of the one who acts on it. Share one ayah {t}.',
    ),
    (
      title: 'A quiet minute with the Quran ✦',
      body: 'Take one {t}: pick a verse, hear it recited, send it on.',
    ),
    (
      title: 'Today’s ayah ✦',
      body: 'Pick a verse that moved you and let it move someone else {t}.',
    ),
    (
      title: 'Deeds that don’t stop ✦',
      body: 'A reel you share {t} can still be earning for you next year.',
    ),
    (
      title: 'Scroll less, send more ✦',
      body: 'One verse from you {t} outweighs an hour of the feed.',
    ),
    (
      title: 'It takes sixty seconds ✦',
      body: 'Choose a reciter, the verses, a scene. Make one {t} and it’s '
          'ready to send.',
    ),
    (
      title: 'Plant one today ✦',
      body: 'Every share is sadaqah jariyah. Plant one {t} and leave it '
          'growing.',
    ),
    (
      title: 'Someone is scrolling right now ✦',
      body: 'Share one verse {t} and give them something worth stopping for.',
    ),
    (
      title: 'Don’t let the day pass ✦',
      body: 'One ayah shared {t} leaves something that lasts.',
    ),
    (
      title: 'Your turn to give ✦',
      body: 'You’ve received a lot of Quran. Send one verse back out {t}.',
    ),
  ];

  static const reelLinesAr = <ReminderLine>[
    (
      title: 'آية واحدة. دقيقة واحدة. ✦',
      body: 'اصنع مقطعًا {t} ودعه يواصل الكسب لك بعد أن تغلق التطبيق.',
    ),
    (
      title: 'صدقة جارية في أقل من دقيقة ✦',
      body: 'أنشئ مقطع آية واحدًا {t}. أجره يجري طويلًا بعده.',
    ),
    (
      title: 'ثمة من يحتاج هذا ✦',
      body: 'أرسل آية واحدة {t}. لن تعرف من ستبلغ.',
    ),
    (
      title: 'كن السبب ✦',
      body: 'شارك آية {t} وكن سببًا في وصول القرآن إلى هاتف أحدهم.',
    ),
    (
      title: 'مواظبتك بانتظارك ✦',
      body: 'مقطع واحد {t} يبقيها حيّة، ولا يستغرق دقيقة.',
    ),
    (
      title: 'من دلّ على خير ✦',
      body: '…فله مثل أجر فاعله. شارك آية {t}.',
    ),
    (
      title: 'دقيقة هادئة مع القرآن ✦',
      body: 'خذها {t}: اختر آية، واستمع لتلاوتها، وأرسلها.',
    ),
    (
      title: 'آية اليوم ✦',
      body: 'اختر {t} آية لامستك، ودعها تلامس غيرك.',
    ),
    (
      title: 'حسنات لا تتوقف ✦',
      body: 'مقطع تشاركه {t} قد يظل يكسب لك حتى العام القادم.',
    ),
    (
      title: 'مرّر أقل، وأرسل أكثر ✦',
      body: 'آية واحدة منك {t} تفوق ساعة من التمرير.',
    ),
    (
      title: 'ستون ثانية تكفي ✦',
      body: 'اختر قارئًا والآيات ومشهدًا. اصنع مقطعًا {t} وسيكون جاهزًا للإرسال.',
    ),
    (
      title: 'ازرع واحدة اليوم ✦',
      body: 'كل مشاركة صدقة جارية. ازرع واحدة {t} ودعها تنمو.',
    ),
    (
      title: 'ثمة من يمرّر الآن ✦',
      body: 'شارك آية {t} وأعطه ما يستحق التوقف عنده.',
    ),
    (
      title: 'لا تدع اليوم يمضي ✦',
      body: 'آية واحدة تشاركها {t} تترك أثرًا لا يزول.',
    ),
    (
      title: 'دورك في العطاء ✦',
      body: 'وصلك من القرآن كثير. أرسل آية واحدة في المقابل {t}.',
    ),
  ];

  static const reelLinesUr = <ReminderLine>[
    (
      title: 'ایک آیت۔ ایک منٹ۔ ✦',
      body: '{t} ایک ریل بنائیں اور اسے ایپ بند کرنے کے بعد بھی کماتے رہنے '
          'دیں۔',
    ),
    (
      title: 'ایک منٹ سے کم میں صدقہ جاریہ ✦',
      body: '{t} ایک آیت کی ریل بنائیں۔ اس کا اجر دیر تک جاری رہتا ہے۔',
    ),
    (
      title: 'کسی کی فیڈ کو اس کی ضرورت ہے ✦',
      body: '{t} ایک آیت بھیجیں۔ آپ کو معلوم نہ ہوگا کہ وہ کس تک پہنچی۔',
    ),
    (
      title: 'سبب بنیں ✦',
      body: '{t} ایک آیت شیئر کریں اور کسی کے فون تک قرآن پہنچنے کا سبب '
          'بنیں۔',
    ),
    (
      title: 'آپ کا تسلسل منتظر ہے ✦',
      body: '{t} ایک ریل اسے زندہ رکھتی ہے، اور اس میں ایک منٹ بھی نہیں لگتا۔',
    ),
    (
      title: 'جو بھلائی کی طرف رہنمائی کرے ✦',
      body: '…اسے کرنے والے جیسا اجر ملتا ہے۔ {t} ایک آیت شیئر کریں۔',
    ),
    (
      title: 'قرآن کے ساتھ ایک پُرسکون منٹ ✦',
      body: '{t} ایک آیت چنیں، اس کی تلاوت سنیں، آگے بھیج دیں۔',
    ),
    (
      title: 'آج کی آیت ✦',
      body: '{t} وہ آیت چنیں جس نے آپ کو چھوا، اور اسے کسی اور کو چھونے دیں۔',
    ),
    (
      title: 'وہ اعمال جو رکتے نہیں ✦',
      body: '{t} شیئر کی گئی ریل اگلے سال بھی آپ کے لیے کما رہی ہو سکتی ہے۔',
    ),
    (
      title: 'کم سکرول، زیادہ ارسال ✦',
      body: '{t} آپ کی ایک آیت فیڈ کے ایک گھنٹے پر بھاری ہے۔',
    ),
    (
      title: 'صرف ساٹھ سیکنڈ ✦',
      body: 'قاری، آیات اور منظر چنیں۔ {t} ریل بنائیں، بھیجنے کے لیے تیار۔',
    ),
    (
      title: 'آج ایک بیج بوئیں ✦',
      body: 'ہر شیئر صدقہ جاریہ ہے۔ {t} ایک بیج بوئیں اور اسے بڑھنے دیں۔',
    ),
    (
      title: 'ابھی کوئی سکرول کر رہا ہے ✦',
      body: '{t} ایک آیت شیئر کریں اور اسے کچھ ایسا دیں جس کے لیے رکنا '
          'بنتا ہو۔',
    ),
    (
      title: 'دن یونہی نہ گزرنے دیں ✦',
      body: '{t} ایک آیت شیئر کریں، اور کچھ ایسا چھوڑ جائیں جو باقی رہے۔',
    ),
    (
      title: 'اب آپ کی دینے کی باری ✦',
      body: 'آپ نے قرآن سے بہت پایا۔ {t} ایک آیت واپس بھیجیں۔',
    ),
  ];

  static const reelLinesId = <ReminderLine>[
    (
      title: 'Satu ayat. Satu menit. ✦',
      body: 'Buat reel {t} dan biarkan ia terus berbuah lama setelah Anda '
          'menutup aplikasi.',
    ),
    (
      title: 'Sedekah jariah, kurang dari semenit ✦',
      body: 'Buat satu reel ayat {t}. Pahalanya terus mengalir lama '
          'setelahnya.',
    ),
    (
      title: 'Ada linimasa yang membutuhkan ini ✦',
      body: 'Kirim satu ayat {t}. Anda takkan tahu siapa yang menerimanya.',
    ),
    (
      title: 'Jadilah sebabnya ✦',
      body: 'Bagikan satu ayat {t} dan jadilah sebab hadirnya Al-Qur’an di '
          'ponsel seseorang.',
    ),
    (
      title: 'Rentetan Anda menunggu ✦',
      body: 'Satu reel {t} menjaganya tetap hidup, dan itu kurang dari '
          'semenit.',
    ),
    (
      title: 'Siapa menunjukkan kebaikan ✦',
      body: '…baginya pahala seperti pelakunya. Bagikan satu ayat {t}.',
    ),
    (
      title: 'Semenit yang tenang bersama Al-Qur’an ✦',
      body: 'Luangkan semenit {t}: pilih satu ayat, dengarkan bacaannya, '
          'kirimkan.',
    ),
    (
      title: 'Ayat hari ini ✦',
      body: 'Pilih ayat yang menyentuh Anda, dan biarkan ia menyentuh orang '
          'lain {t}.',
    ),
    (
      title: 'Amal yang tak berhenti ✦',
      body: 'Reel yang Anda bagikan {t} masih bisa berbuah tahun depan.',
    ),
    (
      title: 'Kurangi gulir, perbanyak kirim ✦',
      body: 'Satu ayat dari Anda {t} lebih berat daripada sejam isi '
          'linimasa.',
    ),
    (
      title: 'Cukup enam puluh detik ✦',
      body: 'Pilih qari, ayat, dan pemandangan. Buat satu {t}, langsung siap '
          'dikirim.',
    ),
    (
      title: 'Tanam satu hari ini ✦',
      body: 'Setiap berbagi adalah sedekah jariah. Tanam satu {t} dan '
          'biarkan tumbuh.',
    ),
    (
      title: 'Seseorang sedang menggulir sekarang ✦',
      body: 'Bagikan satu ayat {t} dan beri dia sesuatu yang layak '
          'dihentikan.',
    ),
    (
      title: 'Jangan biarkan hari ini berlalu ✦',
      body: 'Satu ayat yang dibagikan {t} meninggalkan sesuatu yang '
          'bertahan.',
    ),
    (
      title: 'Kini giliran Anda memberi ✦',
      body: 'Anda telah menerima banyak Al-Qur’an. Kirim kembali satu ayat '
          '{t}.',
    ),
  ];

  static const reelLinesDe = <ReminderLine>[
    (
      title: 'Ein Vers. Eine Minute. ✦',
      body: 'Mach {t} ein Reel und lass es Lohn tragen, lange nachdem du '
          'die App geschlossen hast.',
    ),
    (
      title: 'Sadaqa Dschāriya in einer Minute ✦',
      body: 'Erstell {t} ein Vers-Reel. Sein Lohn läuft noch lange weiter.',
    ),
    (
      title: 'Irgendein Feed braucht das ✦',
      body: 'Sende {t} einen Vers. Du wirst nie erfahren, wen er erreicht.',
    ),
    (
      title: 'Sei der Grund ✦',
      body: 'Teil {t} einen Vers und sei der Grund, warum Quran auf '
          'jemandes Handy ist.',
    ),
    (
      title: 'Deine Serie wartet ✦',
      body: 'Ein Reel {t} hält sie am Leben, und es dauert keine Minute.',
    ),
    (
      title: 'Wer zum Guten weist ✦',
      body: '…dem gebührt der Lohn dessen, der es tut. Teil {t} einen Vers.',
    ),
    (
      title: 'Eine stille Minute mit dem Quran ✦',
      body: 'Nimm sie dir {t}: einen Vers wählen, ihn rezitiert hören, '
          'weiterschicken.',
    ),
    (
      title: 'Der Vers von heute ✦',
      body: 'Wähl {t} einen, der dich bewegt hat, und lass ihn jemand '
          'anderen bewegen.',
    ),
    (
      title: 'Taten, die nicht aufhören ✦',
      body: 'Ein Reel, das du {t} teilst, kann nächstes Jahr noch Lohn '
          'tragen.',
    ),
    (
      title: 'Weniger scrollen, mehr senden ✦',
      body: 'Ein Vers von dir {t} wiegt schwerer als eine Stunde Feed.',
    ),
    (
      title: 'Es dauert sechzig Sekunden ✦',
      body: 'Wähl Rezitator, Verse und Kulisse. Mach {t} eins, und es ist '
          'bereit zum Senden.',
    ),
    (
      title: 'Pflanz heute einen ✦',
      body: 'Jedes Teilen ist Sadaqa Dschāriya. Pflanz {t} einen und lass '
          'ihn wachsen.',
    ),
    (
      title: 'Gerade jetzt scrollt jemand ✦',
      body: 'Teil {t} einen Vers und gib ihm etwas, für das es sich lohnt '
          'anzuhalten.',
    ),
    (
      title: 'Lass den Tag nicht vergehen ✦',
      body: 'Ein Vers, {t} geteilt, hinterlässt etwas, das bleibt.',
    ),
    (
      title: 'Du bist dran zu geben ✦',
      body: 'Du hast viel Quran empfangen. Schick {t} einen Vers zurück.',
    ),
  ];

  /// Every pool, by kind and language. Each language says the same
  /// fifteen things in the same order, so a given day lands on the same
  /// line whichever language the phone is in.
  static const quizPools = <AppLang, List<ReminderLine>>{
    AppLang.en: quizLines,
    AppLang.ar: quizLinesAr,
    AppLang.ur: quizLinesUr,
    AppLang.id: quizLinesId,
    AppLang.de: quizLinesDe,
  };

  static const reelPools = <AppLang, List<ReminderLine>>{
    AppLang.en: reelLines,
    AppLang.ar: reelLinesAr,
    AppLang.ur: reelLinesUr,
    AppLang.id: reelLinesId,
    AppLang.de: reelLinesDe,
  };
}
