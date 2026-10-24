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
}
