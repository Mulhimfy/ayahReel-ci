import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/fatiha_data.dart';
import 'package:ayah_reels/data/models.dart';
import 'package:ayah_reels/data/own_words.dart';
import 'package:ayah_reels/data/qul_words.dart';
import 'package:ayah_reels/data/word_align_service.dart';

/// The app's own word timing: which voices it covers comes from the
/// index published beside the timing, read at launch, so a voice timed
/// later lights up in a build already installed — and nothing it can't
/// vouch for gets in.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('own_words');
    OwnWords.debugReset();
    OwnWords.debugDir = dir;
    QulWords.debugDir = dir;
    QulWords.debugReset();
  });
  tearDown(() {
    OwnWords.debugReset();
    OwnWords.debugDir = null;
    QulWords.debugDir = null;
    QulWords.debugReset();
    dir.deleteSync(recursive: true);
  });

  /// A voice nothing else times: neither quran-align nor QUL.
  final untimed = reciters.firstWhere((r) =>
      !WordAlignService.alignedByQuranAlign(r) &&
      !QulWords.sources.containsKey(r.id) &&
      !r.isUserAudio);
  final qul = reciters.firstWhere((r) => QulWords.sources.containsKey(r.id));

  Map<String, dynamic> entry({
    String fit = 'ayahFiles',
    List<int> surahs = const [1, 2],
    num median = 30,
    num p90 = 90,
  }) =>
      {'fit': fit, 'surahs': surahs, 'medianMs': median, 'p90Ms': p90};

  test('a voice the index names, that passed, is timed in the surahs it '
      'covers and no others', () {
    final s = OwnWords.parseIndex({
      'v': 1,
      'voices': {untimed.id: entry(surahs: [1, 112])},
    });
    final src = s[untimed.id]!;
    expect(src.own, untimed.id);
    expect(src.fit, QulFit.ayahFiles);
    expect(src.skip.contains(1), isFalse);
    expect(src.skip.contains(112), isFalse);
    expect(src.skip.contains(2), isTrue);
    expect(src.skip, hasLength(112));
  });

  test('what it cannot vouch for is left out, and the rest stands', () {
    final s = OwnWords.parseIndex({
      'v': 1,
      'voices': {
        untimed.id: entry(fit: 'surahFile'),
        'nobody_we_have': entry(),
        qul.id: entry(),
      },
    });
    expect(s.keys, [untimed.id]);
    expect(s[untimed.id]!.fit, QulFit.surahFile);
    // A fit it does not know.
    expect(
        OwnWords.parseIndex({
          'v': 1,
          'voices': {untimed.id: entry(fit: 'sideways')},
        }),
        isEmpty);
    // Over the bar, at the median or the tail: not used.
    expect(
        OwnWords.parseIndex({
          'v': 1,
          'voices': {untimed.id: entry(median: 80)},
        }),
        isEmpty);
    expect(
        OwnWords.parseIndex({
          'v': 1,
          'voices': {untimed.id: entry(p90: 200)},
        }),
        isEmpty);
    // A layout it does not know.
    expect(OwnWords.parseIndex({'v': 2, 'voices': {}}), isEmpty);
    expect(OwnWords.parseIndex('nonsense'), isEmpty);
  });

  test('a voice the index times is a voice with word timing', () {
    expect(WordAlignService.supports(untimed), isFalse);
    OwnWords.debugSet(OwnWords.parseIndex({
      'v': 1,
      'voices': {untimed.id: entry()},
    }));
    expect(WordAlignService.supports(untimed), isTrue);
    expect(QulWords.sourceOf(untimed)!.own, untimed.id);
  });

  test('the kept index is read at launch', () async {
    File('${dir.path}/own_words_index.json').writeAsStringSync(jsonEncode({
      'v': 1,
      'voices': {untimed.id: entry()},
    }));
    await OwnWords.init();
    expect(OwnWords.sources.keys, [untimed.id]);
  });

  test('the verses a voice\'s timing reaches are known before its audio',
      () async {
    OwnWords.debugSet(OwnWords.parseIndex({
      'v': 1,
      'voices': {untimed.id: entry(surahs: [112])},
    }));
    File('${dir.path}/o${untimed.id}_112.json')
        .writeAsStringSync(jsonEncode(QulWords.encodeCompact({
      1: const QulVerse(300, 2200, [(1, 300, 700), (2, 700, 1200),
          (3, 1200, 1700), (4, 1700, 2200)]),
      3: const QulVerse(0, 900, [(1, 0, 400), (2, 400, 900)]),
    })));
    // The picker marks verse 2 and 4 as having no word timing.
    expect(await WordAlignService.timedVerses(untimed, 112), {1, 3});
    // A surah the index doesn't name: not one of its verses.
    expect(await WordAlignService.timedVerses(untimed, 113), isEmpty);
  });

  test('a voice nothing times has no timed verse', () async {
    expect(await WordAlignService.timedVerses(untimed, 112), isEmpty);
  });

  test('a kept index is asked for again when this build has other voices',
      () {
    // Asked for an hour ago by this very build: kept.
    expect(
        OwnWords.keptIsCurrent(
            age: const Duration(hours: 1), askedFor: OwnWords.voicesKey),
        isTrue);
    // A day old: asked again.
    expect(
        OwnWords.keptIsCurrent(
            age: const Duration(hours: 21), askedFor: OwnWords.voicesKey),
        isFalse);
    // An hour old, but asked for by a build without the newest voice, or
    // by one from before the voices were kept beside it: asked again.
    final older = OwnWords.voicesKey.split(',')..removeLast();
    expect(
        OwnWords.keptIsCurrent(
            age: const Duration(hours: 1), askedFor: older.join(',')),
        isFalse);
    expect(OwnWords.keptIsCurrent(age: const Duration(hours: 1)), isFalse);
    // An hour old, with every voice, but asked for before a publish this
    // build was made for: asked again.
    final ids = OwnWords.voicesKey.split(':').last;
    expect(
        OwnWords.keptIsCurrent(
            age: const Duration(hours: 1),
            askedFor: '${OwnWords.timingEpoch - 1}:$ids'),
        isFalse);
    expect(
        OwnWords.keptIsCurrent(age: const Duration(hours: 1), askedFor: ids),
        isFalse);
  });

  test('its words are placed on the voice\'s own per-ayah files as they '
      'are', () async {
    OwnWords.debugSet(OwnWords.parseIndex({
      'v': 1,
      'voices': {untimed.id: entry(surahs: [112])},
    }));
    // What the host serves for the surah, kept on the phone already.
    File('${dir.path}/o${untimed.id}_112.json')
        .writeAsStringSync(jsonEncode(QulWords.encodeCompact({
      1: const QulVerse(300, 2200, [(1, 300, 700), (2, 700, 1200),
          (3, 1200, 1700), (4, 1700, 2200)]),
    })));
    const rec = Recitation(
      reciterId: 'x',
      surah: 112,
      audioPath: 'unused.mp3',
      timings: [AyahTiming(1, 0, 2600)],
    );
    final placed = await QulWords.forRecitation(untimed, rec);
    expect(placed![1]!.count, 4);
    expect(placed[1]!.words.first, (1, 300, 700));
    final spans = WordAlignService.fromMushafWords(
        'قُلْ هُوَ ٱللَّهُ أَحَدٌ', placed[1]!);
    expect(spans, hasLength(4));
  });

  test('a file kept from before the voice was published again is not '
      'read: the index\'s revision names the one that is', () async {
    final s = OwnWords.parseIndex({
      'v': 1,
      'voices': {
        untimed.id: {...entry(surahs: [112]), 'rev': '3f9a0c1b2d'},
      },
    });
    expect(s[untimed.id]!.ownRev, '3f9a0c1b2d');
    // Nothing that could not be part of a file name.
    expect(
        OwnWords.parseIndex({
          'v': 1,
          'voices': {
            untimed.id: {...entry(), 'rev': '../x'},
          },
        })[untimed.id]!
            .ownRev,
        isNull);
    OwnWords.debugSet(s);
    String verse(int startMs) => jsonEncode(QulWords.encodeCompact({
          1: QulVerse(startMs, startMs + 1900, [
            (1, startMs, startMs + 400),
            (2, startMs + 400, startMs + 900),
            (3, startMs + 900, startMs + 1400),
            (4, startMs + 1400, startMs + 1900),
          ]),
        }));
    // The copy from before, and the one the index names.
    File('${dir.path}/o${untimed.id}_112.json').writeAsStringSync(verse(900));
    File('${dir.path}/o${untimed.id}.3f9a0c1b2d_112.json')
        .writeAsStringSync(verse(300));
    const rec = Recitation(
      reciterId: 'x',
      surah: 112,
      audioPath: 'unused.mp3',
      timings: [AyahTiming(1, 0, 2600)],
    );
    final placed = await QulWords.forRecitation(untimed, rec);
    expect(placed![1]!.words.first, (1, 300, 700));
  });

  test('the near tier: verses the timing did not vouch for, placed for '
      'the light and the thread, apart from the word timing', () async {
    OwnWords.debugSet(OwnWords.parseIndex({
      'v': 1,
      'voices': {
        untimed.id: {
          ...entry(surahs: [1]),
          'rev': 'ab12',
          'near': [112, 999, 'x'],
        },
      },
    }));
    final src = OwnWords.sources[untimed.id]!;
    expect(src.near, {112});
    expect(src.tables, isEmpty);
    // A verse table of our own, for the surahs the index names.
    expect(
        OwnWords.parseIndex({
          'v': 1,
          'voices': {
            untimed.id: {
              ...entry(surahs: [1]),
              'tables': [2, 36, 0, 115, 'x'],
            },
          },
        })[untimed.id]!
            .tables,
        {2, 36});
    // 112 has no trusted verse: the voice is not word-timed there, and
    // nothing that says a voice is word-timed may be lit by its near
    // tier.
    expect(WordAlignService.supportsSurah(untimed, 112), isFalse);
    // Its near tier, kept on the phone under its own name.
    File('${dir.path}/n${untimed.id}.ab12_112.json')
        .writeAsStringSync(jsonEncode(QulWords.encodeCompact({
      1: const QulVerse(300, 2200, [(1, 300, 700), (2, 700, 1200),
          (3, 1200, 1700), (4, 1700, 2200)]),
    })));
    const rec = Recitation(
      reciterId: 'x',
      surah: 112,
      audioPath: 'unused.mp3',
      timings: [AyahTiming(1, 0, 2600)],
    );
    final near = await WordAlignService.loadNear(untimed,
        recitation: rec,
        ayahs: const [
          Ayah(number: 1, arabic: 'قُلْ هُوَ ٱللَّهُ أَحَدٌ', translation: ''),
        ]);
    expect(near![1], hasLength(4));
    expect(near[1]!.first.startMs, 300);
    // A surah the index names no near tier for is not asked for.
    const other = Recitation(
      reciterId: 'x',
      surah: 113,
      audioPath: 'unused.mp3',
      timings: [AyahTiming(1, 0, 2600)],
    );
    expect(await QulWords.nearOf(untimed, other), isNull);
  });
}
