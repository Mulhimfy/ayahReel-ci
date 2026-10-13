// Ready-made hashtag blocks for a finished reel.
//
// Every tag in this file is inside the niche: Quran, recitation, the
// deen. Nothing here reaches outside it — no #fyp, no #viral, no
// #explore, no #trending. Those are what get a Quran reel pushed at
// people who did not come for one, and a caption padded with them
// stops being about what the video actually is. A tag earns its place
// here only if someone searching it wants exactly this.
//
// Platform-shaped tags (#quranreels, #deentok, #quranshorts) are still
// niche tags — they name where this kind of reel lives, rather than
// bidding for traffic of any kind — so they stay. The bare format tags
// do not.

/// Which caption box a block is cut for.
enum TagPlatform { instagram, tiktok, youtube, more }

/// One block of hashtags, copied whole.
class HashtagSet {
  /// Names the block: looks its label up in `L10n`, and decides where
  /// the mark falls, so the two can never drift apart.
  final String key;

  /// The tags themselves, each without its '#'.
  ///
  /// The app's own mark is deliberately NOT in here. [text] puts it in,
  /// which is what stops a set added later from ever shipping without
  /// it.
  final List<String> tags;

  /// Arabic blocks read right to left, and lay out wrong in a card
  /// that assumes otherwise.
  final bool rtl;

  const HashtagSet(this.key, this.tags, {this.rtl = false});

  /// The app's signature, carried by every block that leaves here.
  static const mark = 'AyahReel';

  /// Where the mark lands. Mid-block, nudged by the set's own name so
  /// it does not sit at the same offset every time, and kept off both
  /// ends — first and last are the two positions an eye skimming a
  /// wall of tags actually stops on.
  int get _markIndex {
    final mid = tags.length ~/ 2;
    return (mid + key.length % 3 - 1).clamp(1, tags.length - 1);
  }

  /// The tags with the mark in place, in copy order.
  List<String> get resolved => [...tags]..insert(_markIndex, mark);

  /// What a tap on Copy puts on the clipboard.
  String get text => resolved.map((t) => '#$t').join(' ');

  /// How many tags the block carries, the mark counted — it is one of
  /// them, and a count that skipped it would give it away.
  int get count => tags.length + 1;
}

// ---- Arabic ------------------------------------------------------
// One set of tags does the work on every platform here: Arabic Quran
// searches are not split app by app the way the English ones are.

const _arabicCore = [
  'قران',
  'قرآن',
  'تلاوة',
  'القران_الكريم',
  'تلاوة_خاشعة',
  'ايات_قرانية',
  'ترتيل',
  'تدبر',
  'خشوع',
  'اسلاميات',
];

const _arabicInstagram =
    HashtagSet('arabic', [..._arabicCore, 'ذكر_الله'], rtl: true);
const _arabicTikTok =
    HashtagSet('arabic', [..._arabicCore, 'قران_كريم'], rtl: true);
const _arabicYouTube = HashtagSet('arabic', _arabicCore, rtl: true);

// ---- Instagram ---------------------------------------------------

const _instagram = [
  HashtagSet('recitation', [
    'quran',
    'quranrecitation',
    'tilawah',
    'beautifulrecitation',
    'quranreels',
    'holyquran',
    'recitequran',
    'quranvideo',
    'tajweed',
    'quranlover',
    'islamicreels',
  ]),
  _arabicInstagram,
  HashtagSet('reminders', [
    'islamicreminder',
    'quranquotes',
    'quranicverses',
    'islamicquotes',
    'dawah',
    'deenoverdunya',
    'verseoftheday',
    'muslimreminder',
    'reflectonquran',
    'imaan',
  ]),
  HashtagSet('night', [
    'tahajjud',
    'qiyamullayl',
    'quranatnight',
    'soothingrecitation',
    'peacefulquran',
    'nightprayer',
    'sujood',
    'khushu',
    'duaa',
  ]),
];

// ---- TikTok ------------------------------------------------------

const _tiktok = [
  HashtagSet('recitation', [
    'quran',
    'quranrecitation',
    'tilawah',
    'qurantok',
    'quranedit',
    'recitequran',
    'beautifulrecitation',
    'muslimtiktok',
    'islamictiktok',
    'holyquran',
  ]),
  _arabicTikTok,
  HashtagSet('reminders', [
    'islamicreminder',
    'deentok',
    'quranquotes',
    'islamicquotes',
    'dawah',
    'verseoftheday',
    'deenoverdunya',
    'muslimtiktok',
    'imaan',
  ]),
  HashtagSet('night', [
    'tahajjud',
    'quranatnight',
    'qiyamullayl',
    'soothingrecitation',
    'peacefulquran',
    'sujood',
    'khushu',
    'deentok',
    'duaa',
  ]),
];

// ---- YouTube -----------------------------------------------------

const _youtube = [
  HashtagSet('recitation', [
    'quran',
    'quranrecitation',
    'quranshorts',
    'tilawah',
    'beautifulrecitation',
    'holyquran',
    'recitequran',
    'islamicshorts',
    'quranvideo',
    'tajweed',
  ]),
  _arabicYouTube,
  HashtagSet('reminders', [
    'islamicreminder',
    'quranquotes',
    'quranicverses',
    'islamicshorts',
    'dawah',
    'verseoftheday',
    'islamicquotes',
    'imaan',
  ]),
  HashtagSet('night', [
    'tahajjud',
    'quranatnight',
    'qiyamullayl',
    'soothingrecitation',
    'peacefulquran',
    'islamicshorts',
    'nightprayer',
    'khushu',
  ]),
];

// ---- the curated rest --------------------------------------------

const _more = [
  HashtagSet('hifz', [
    'hifz',
    'quranmemorization',
    'memorizequran',
    'hafiz',
    'learnquran',
    'quranstudy',
    'hifzjourney',
    'tajweed',
    'quranclass',
  ]),
  HashtagSet('ramadan', [
    'ramadan',
    'ramadankareem',
    'taraweeh',
    'laylatulqadr',
    'quraninramadan',
    'ramadanreminder',
    'ramadanquran',
    'ibadah',
    'fasting',
  ]),
  HashtagSet('dhikr', [
    'dhikr',
    'azkar',
    'istighfar',
    'subhanallah',
    'alhamdulillah',
    'allahuakbar',
    'tasbeeh',
    'remembrance',
    'dua',
  ]),
  HashtagSet('dawah', [
    'dawah',
    'islamicdawah',
    'quranexplained',
    'islamicknowledge',
    'learnislam',
    'islamicteaching',
    'newmuslim',
    'calltoislam',
    'deen',
  ]),
];

/// "Ali 'Imran" becomes 'AliImran'. A hashtag carries letters and
/// digits and nothing else, so the apostrophes, hyphens and spaces in
/// the English surah names have to go before one can be tagged.
String? surahTag(String? englishName) {
  if (englishName == null) return null;
  final t = englishName.replaceAll(RegExp('[^A-Za-z0-9]'), '');
  return t.isEmpty ? null : t;
}

/// The blocks on offer for [p].
///
/// [surahName] is the English surah name of the reel in hand. Given
/// one, the curated tab opens on the block that is about this reel
/// rather than about reels in general — what someone looking for
/// exactly this passage would search.
List<HashtagSet> hashtagSets(TagPlatform p, {String? surahName}) {
  switch (p) {
    case TagPlatform.instagram:
      return _instagram;
    case TagPlatform.tiktok:
      return _tiktok;
    case TagPlatform.youtube:
      return _youtube;
    case TagPlatform.more:
      final s = surahTag(surahName);
      if (s == null) return _more;
      return [
        HashtagSet('surah', [
          'Surah$s',
          s,
          'quran',
          'quranrecitation',
          'surahrecitation',
          'tilawah',
          'quranicverses',
          'recitequran',
        ]),
        ..._more,
      ];
  }
}
