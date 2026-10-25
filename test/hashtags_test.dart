import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/hashtag_sets.dart';
import 'package:ayah_reels/data/platform_share.dart';
import 'package:ayah_reels/l10n/l10n.dart';
import 'package:ayah_reels/theme/app_theme.dart';
import 'package:ayah_reels/widgets/hashtags_sheet.dart';

/// The hashtag sheet has two promises to keep, and neither of them
/// survives on good intentions once someone adds a fifth set in a
/// hurry: every block stays inside the niche, and every block carries
/// the app's own mark where nobody reads.
void main() {
  const en = L10n(AppLang.en);
  const ar = L10n(AppLang.ar);

  /// Every block the sheet can put in front of anyone.
  List<HashtagSet> everySet() => [
        for (final p in TagPlatform.values)
          ...hashtagSets(p, surahName: 'Al-Kahf'),
      ];

  test('every block carries the mark, once, and never at an end', () {
    for (final s in everySet()) {
      final tags = s.resolved;
      expect(tags.where((t) => t == HashtagSet.mark).length, 1,
          reason: '${s.key} must carry #${HashtagSet.mark} exactly once');
      final at = tags.indexOf(HashtagSet.mark);
      expect(at, greaterThan(0),
          reason: '${s.key} opens on the mark, where it is the first '
              'thing read');
      expect(at, lessThan(tags.length - 1),
          reason: '${s.key} ends on the mark, where it is the last '
              'thing read');
      expect(s.text, contains('#${HashtagSet.mark}'));
      expect(s.count, tags.length,
          reason: 'the count on the card must include the mark, or the '
              'mark is what the count gives away');
    }
  });

  test('the mark sits in the middle of every block, inside the first five',
      () {
    // Instagram and TikTok keep five hashtags and drop the rest: a mark
    // past the fifth is a mark nobody sees.
    for (final s in everySet()) {
      expect(s.resolved.indexOf(HashtagSet.mark), s.resolved.length ~/ 2,
          reason: '${s.key} has the mark off its middle');
      expect(s.resolved.indexOf(HashtagSet.mark),
          lessThan(HashtagSet.perBlock));
    }
  });

  test('a YouTube block leaves room in a Short\'s title', () {
    for (final s in hashtagSets(TagPlatform.youtube)) {
      expect(s.text.length, lessThanOrEqualTo(60),
          reason: '${s.key} takes too much of a 100-character title');
    }
  });

  test('nothing reaches outside the niche', () {
    // The tags that get a Quran reel shown to people who did not come
    // for one. None of them belongs in a caption written here.
    const fluff = {
      'fyp',
      'foryou',
      'foryoupage',
      'viral',
      'viralvideo',
      'trending',
      'explore',
      'explorepage',
      'instagood',
      'love',
      'follow',
      'like4like',
      'shorts',
      'reels',
      'tiktok',
      'youtube',
      'instagram',
      'subscribe',
    };
    for (final s in everySet()) {
      for (final tag in s.resolved) {
        expect(fluff.contains(tag.toLowerCase()), isFalse,
            reason: '#$tag in ${s.key} is reach, not niche');
      }
    }
  });

  test('no block repeats a tag, and every block is five, the mark counted',
      () {
    for (final s in everySet()) {
      final tags = s.resolved.map((t) => t.toLowerCase()).toList();
      expect(tags.toSet().length, tags.length,
          reason: '${s.key} repeats a tag');
      // Instagram and TikTok take five; a sixth is cut, and pasting a
      // block whole must never lose anything.
      expect(tags.length, HashtagSet.perBlock,
          reason: '${s.key} is not five tags');
    }
  });

  group('the caption Share to copies', () {
    List<String> hashtags(String caption) => [
          for (final w in caption.split(RegExp(r'\s+')))
            if (w.startsWith('#')) w.substring(1),
        ];

    const line = '🎧 Surah Al-Kahf · Mishary Rashid Alafasy\n'
        '✨ Made with AyahReel — a Quran reel in a minute, no editing';

    test('five tags at most for Instagram, TikTok and Facebook, the mark '
        'in the middle and the surah among them', () {
      for (final t in [
        ShareTarget.instagramReel,
        ShareTarget.instagramPost,
        ShareTarget.instagramStory,
        ShareTarget.tiktok,
        ShareTarget.facebook,
      ]) {
        final c = PlatformShare.caption(t, line: line, surahName: 'Al-Kahf');
        final tags = hashtags(c);
        expect(tags.length, lessThanOrEqualTo(5), reason: '$t');
        expect(tags.indexOf(HashtagSet.mark), tags.length ~/ 2,
            reason: '$t has the mark off its middle');
        expect(tags, contains('SurahAlKahf'), reason: '$t');
        expect(c, startsWith(line), reason: '$t keeps its line');
      }
    });

    test('YouTube fits a Short\'s title and still carries the mark', () {
      const longest = '🎧 Surah Al-Ankabut · Abdul Rahman Al-Sudais and a '
          'name long enough to run past any title YouTube takes';
      for (final l in [line, longest]) {
        for (final surah in [null, 'Al-Ankabut']) {
          final c = PlatformShare.caption(ShareTarget.youtube,
              line: l, surahName: surah);
          expect(c.length, lessThanOrEqualTo(HashtagSet.youtubeTitleMax),
              reason: c);
          expect(hashtags(c), contains(HashtagSet.mark), reason: c);
          expect(c, isNot(contains('\n')), reason: 'a title is one line');
        }
      }
    });

    test('WhatsApp carries the mark, and only the mark', () {
      final c = PlatformShare.caption(ShareTarget.whatsapp,
          line: line, surahName: 'Al-Kahf');
      expect(hashtags(c), [HashtagSet.mark]);
    });
  });

  test('the curated tab leads with this reel, or drops the block', () {
    final withSurah = hashtagSets(TagPlatform.more, surahName: "Ali 'Imran");
    expect(withSurah.first.key, 'surah');
    // Apostrophes and spaces cannot survive into a hashtag.
    expect(withSurah.first.text, contains('#SurahAliImran'));
    expect(withSurah.first.text, isNot(contains("'")));

    // No surah in hand — the player can be opened on a reel saved
    // before the field existed — and the block is simply absent rather
    // than offering '#Surah'.
    expect(hashtagSets(TagPlatform.more).any((s) => s.key == 'surah'),
        isFalse);
    expect(hashtagSets(TagPlatform.more, surahName: '  ').first.key,
        isNot('surah'));
  });

  test('every block label is written in both languages', () {
    for (final s in everySet()) {
      final e = en.hashtagSetLabel(s.key, surahName: 'Al-Kahf');
      final a = ar.hashtagSetLabel(s.key, surahName: 'Al-Kahf');
      expect(e, isNot(s.key), reason: '${s.key} has no English label');
      expect(a, isNot(e), reason: '${s.key} has no Arabic label');
    }
    expect(en.hashtagSetLabel('surah', surahName: 'Al-Kahf'),
        'Surah Al-Kahf');
    expect(ar.hashtagSetLabel('surah', surahName: 'Al-Kahf'),
        'سورة الكهف');
    // Arabic counts the way Arabic does.
    expect(en.tagCount(12), '12 tags');
    expect(ar.tagCount(9), '9 وسوم');
    expect(ar.tagCount(12), '12 وسمًا');
  });

  group('the sheet', () {
    Widget host() => MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            body: Center(child: HashtagsButton(surahName: 'Al-Kahf')),
          ),
        );

    /// What the last Copy put on the clipboard.
    String? clipboard;

    setUp(() {
      clipboard = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    Future<void> open(WidgetTester t) async {
      await t.pumpWidget(host());
      await t.tap(find.byType(HashtagsButton));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
    }

    testWidgets('opens on the four tabs and the first block', (t) async {
      await open(t);

      expect(find.text('Instagram'), findsOneWidget);
      expect(find.text('TikTok'), findsOneWidget);
      expect(find.text('YouTube'), findsOneWidget);
      expect(find.text('More'), findsOneWidget);
      expect(find.text('Recitation'), findsOneWidget);
      expect(find.text('Copy'), findsWidgets);
    });

    testWidgets('one tap copies the block, mark and all', (t) async {
      await open(t);
      await t.tap(find.text('Copy').first);
      await t.pump();

      final first = hashtagSets(TagPlatform.instagram).first;
      expect(clipboard, first.text);
      expect(clipboard, contains('#AyahReelApp'));
      expect(clipboard, startsWith('#quran '));
    });

    testWidgets('the card says it copied, then stops saying it', (t) async {
      await open(t);
      await t.tap(find.text('Copy').first);
      await t.pump();
      await t.pump(const Duration(milliseconds: 200));
      expect(find.text('Copied'), findsOneWidget);

      // Two pumps: the first lets the timer put the label back, the
      // second lets the outgoing "Copied" finish fading out of the
      // switcher.
      await t.pump(const Duration(seconds: 2));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Copied'), findsNothing);
    });

    testWidgets('turned sideways it gives way rather than overflowing',
        (t) async {
      // Nothing locks the orientation, and landscape leaves less height
      // than the sheet's own parts would like.
      t.view.physicalSize = const Size(844, 390) * 3;
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);

      await open(t);

      expect(t.takeException(), isNull);
      expect(find.text('Copy'), findsWidgets);
    });

    testWidgets('a tab swap changes the blocks on offer', (t) async {
      await open(t);
      expect(find.text('Memorization'), findsNothing);

      await t.tap(find.text('More'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));

      // The curated tab leads with the reel in hand.
      expect(find.text('Surah Al-Kahf'), findsOneWidget);

      await t.tap(find.text('Copy').first);
      await t.pump();
      expect(clipboard, contains('#SurahAlKahf'));
      expect(clipboard, contains('#AyahReelApp'));
    });
  });
}
