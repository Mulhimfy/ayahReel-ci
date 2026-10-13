import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/hashtag_sets.dart';
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
          reason: '${s.key} must carry #AyahReel exactly once');
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

  test('the mark does not sit at the same offset in every block', () {
    final offsets = {
      for (final s in everySet()) s.resolved.indexOf(HashtagSet.mark),
    };
    expect(offsets.length, greaterThan(1));
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

  test('no block repeats a tag, and none is too thin to be worth a tap', () {
    for (final s in everySet()) {
      final tags = s.resolved.map((t) => t.toLowerCase()).toList();
      expect(tags.toSet().length, tags.length,
          reason: '${s.key} repeats a tag');
      expect(tags.length, greaterThanOrEqualTo(7),
          reason: '${s.key} is too short to be worth copying');
      // Instagram takes thirty; every platform here takes fewer than
      // that badly, so no block goes near the ceiling.
      expect(tags.length, lessThanOrEqualTo(20));
    }
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
      expect(clipboard, contains('#AyahReel'));
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
      expect(clipboard, contains('#AyahReel'));
    });
  });
}
