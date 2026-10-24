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
///
/// Five tags a block, the mark among them: Instagram and TikTok take
/// five hashtags on a post and drop the rest, so a longer block pasted
/// whole lost whatever came after the fifth — the mark too, when it sat
/// in the middle of ten. Five is also what keeps a YouTube block short
/// enough to ride in a Short's title (see [youtubeTitleMax]).
class HashtagSet {
  /// Names the block: looks its label up in `L10n`.
  final String key;

  /// The tags themselves, each without its '#': [perBlock] less one,
  /// since the mark takes the fifth place.
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

  /// The most hashtags a post on Instagram or TikTok keeps. Every block
  /// holds exactly this many, the mark counted.
  static const perBlock = 5;

  /// A YouTube Short's title holds this many characters, and a caption
  /// copied for one goes in that box.
  static const youtubeTitleMax = 100;

  /// [tags] with the mark in their middle: never first or last, the two
  /// places an eye skimming tags stops on, and inside the first five
  /// wherever a platform cuts.
  static List<String> withMark(List<String> tags) =>
      [...tags]..insert(tags.length ~/ 2, mark);

  /// The tags with the mark in place, in copy order.
  List<String> get resolved => withMark(tags);

  /// What a tap on Copy puts on the clipboard.
  String get text => resolved.map((t) => '#$t').join(' ');

  /// How many tags the block carries, the mark counted — it is one of
  /// them, and a count that skipped it would give it away.
  int get count => tags.length + 1;
}

// ---- Arabic ------------------------------------------------------
// The same few Arabic tags lead on every platform: Arabic Quran
// searches are not split app by app the way the English ones are.

const _arabicInstagram =
    HashtagSet('arabic', ['قرآن', 'تلاوة', 'القران_الكريم', 'ذكر_الله'],
        rtl: true);
const _arabicTikTok =
    HashtagSet('arabic', ['قرآن', 'تلاوة', 'القران_الكريم', 'قران_كريم'],
        rtl: true);
const _arabicYouTube =
    HashtagSet('arabic', ['قرآن', 'تلاوة', 'ترتيل', 'تلاوة_خاشعة'],
        rtl: true);

// ---- Instagram ---------------------------------------------------

const _instagram = [
  HashtagSet('recitation',
      ['quran', 'quranrecitation', 'quranreels', 'tilawah']),
  _arabicInstagram,
  HashtagSet('reminders',
      ['islamicreminder', 'quranquotes', 'dawah', 'verseoftheday']),
  HashtagSet('night',
      ['tahajjud', 'quranatnight', 'peacefulquran', 'qiyamullayl']),
];

// ---- TikTok ------------------------------------------------------

const _tiktok = [
  HashtagSet('recitation',
      ['quran', 'qurantok', 'quranrecitation', 'islamictiktok']),
  _arabicTikTok,
  HashtagSet('reminders',
      ['islamicreminder', 'deentok', 'quranquotes', 'muslimtiktok']),
  HashtagSet('night',
      ['tahajjud', 'quranatnight', 'deentok', 'peacefulquran']),
];

// ---- YouTube -----------------------------------------------------
// Short tags: a block has to leave room for the title it follows.

const _youtube = [
  HashtagSet('recitation', ['quran', 'quranshorts', 'tilawah', 'tajweed']),
  _arabicYouTube,
  HashtagSet('reminders', ['islamicshorts', 'quranquotes', 'dawah', 'imaan']),
  HashtagSet('night', ['tahajjud', 'quranatnight', 'islamicshorts', 'khushu']),
];

// ---- the curated rest --------------------------------------------

const _more = [
  HashtagSet('hifz', ['hifz', 'quranmemorization', 'hafiz', 'learnquran']),
  HashtagSet('ramadan', ['ramadan', 'ramadankareem', 'taraweeh', 'laylatulqadr']),
  HashtagSet('dhikr', ['dhikr', 'azkar', 'istighfar', 'subhanallah']),
  HashtagSet('dawah', ['dawah', 'islamicdawah', 'learnislam', 'deen']),
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
        HashtagSet('surah', ['Surah$s', 'quran', 'quranrecitation', 'tilawah']),
        ..._more,
      ];
  }
}
