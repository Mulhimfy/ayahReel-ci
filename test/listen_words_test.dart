import 'package:flutter_test/flutter_test.dart';
import 'package:ayah_reels/data/listen/listen_words.dart';
import 'package:ayah_reels/data/models.dart';
import 'package:ayah_reels/data/word_align_service.dart';

/// What AyahReel Listen heard in an upload reaches the word light the way a
/// voice's own timing does.
void main() {
  setUp(ListenWords.forgetAll);

  const upload = Reciter(
    id: 'user_x',
    name: 'x',
    arabicName: 'x',
    style: '',
    source: OwnAudio(),
  );

  test('words are placed on the verses windows of the recitation', () {
    ListenWords.register('user_x', 112, {
      1: [1000, 3000, 1, 1000, 1500, 2, 1500, 2100, 3, 2100, 2500, 4, 2500, 3000],
      2: [4000, 5000, 1, 4000, 4600, 2, 4600, 5000],
    }, {
      1: 4,
      2: 2,
    });
    const rec = Recitation(
      reciterId: 'user_x_a1b2c3d4',
      surah: 112,
      audioPath: 'x',
      timings: [AyahTiming(1, 600, 3700), AyahTiming(2, 3700, 5600)],
    );
    final placed = ListenWords.placedFor('user_x', rec)!;
    expect(placed[1]!.count, 4);
    expect(placed[1]!.words.first, (1, 400, 900));
    expect(placed[1]!.words.last, (4, 1900, 2400));
    expect(placed[2]!.words.last, (2, 900, 1300));
  });

  test('a word outside its verse window is left out, a word across it cut', () {
    ListenWords.register('user_x', 112, {
      1: [1000, 3300, 1, 1000, 1500, 2, 2800, 3200, 3, 3100, 3300],
    }, {
      1: 3,
    });
    const rec = Recitation(
      reciterId: 'user_x_1',
      surah: 112,
      audioPath: 'x',
      timings: [AyahTiming(1, 1200, 3000)],
    );
    final words = ListenWords.placedFor('user_x', rec)![1]!.words;
    expect(words, [(1, 0, 300), (2, 1600, 1800)]);
  });

  test('an upload Listen timed is word-timed, in that surah only', () {
    expect(WordAlignService.supports(upload), isFalse);
    ListenWords.register('user_x', 112, {
      1: [0, 100, 1, 0, 100],
    }, {
      1: 4,
    });
    expect(WordAlignService.supports(upload), isTrue);
    expect(WordAlignService.supportsSurah(upload, 112), isTrue);
    expect(WordAlignService.supportsSurah(upload, 113), isFalse);
    ListenWords.forget('user_x');
    expect(WordAlignService.supports(upload), isFalse);
  });
}
