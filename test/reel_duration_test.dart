import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/fatiha_data.dart';
import 'package:ayah_reels/data/media_aspect.dart';
import 'package:ayah_reels/data/models.dart';
import 'package:ayah_reels/data/reel_duration.dart';
import 'package:ayah_reels/data/reel_limits.dart';

/// The verse picker has to answer "how long will this run?" before a
/// note of the recitation has been downloaded, or the cap goes back to
/// being something the preview does to the user afterwards.
///
/// What is asserted here is what the estimate is actually *for*: the
/// right order of magnitude, the right shape, and a hard cap that
/// lands somewhere sane. It is deliberately not asserted to the
/// millisecond — it is an estimate, and pinning it to a number would
/// only make the constants unmovable.
void main() {
  group('letters are what a reciter pronounces', () {
    test('vowel marks and tatweel are not letters', () {
      // The app's text is fully vocalized; counting the marks would
      // read every verse as several times its own length.
      expect(ReelDuration.lettersIn('ٱلرَّحْمَـٰنِ'), 6);
      expect(ReelDuration.lettersIn('بِسْمِ'), 3);
      // Tatweel is a typographic stretch, silent by definition.
      expect(ReelDuration.lettersIn('بســم'), 3);
    });

    test('nothing to say about nothing', () {
      expect(ReelDuration.lettersIn(''), 0);
      expect(ReelDuration.lettersIn('— 1 —'), 0);
    });
  });

  group('estimating a run', () {
    test('lands within a fifth of the measured Al-Fatiha', () {
      // The bundled timings are exact — built from the ffprobe'd files
      // — so they are the one place the model can be checked against
      // the real thing. Al-Fatiha is recited more deliberately than
      // most of the Quran, so the estimate sitting a little under it
      // is the model working, not failing.
      final alafasy = reciters.firstWhere((r) => r.id == 'alafasy');
      final exact = alafasy.timings!.last.endMs;
      final est = ReelDuration.estimateMs(
        fatiha,
        startAyah: 1,
        endAyah: 7,
        pace: alafasy.pace,
      );
      expect((est - exact).abs() / exact, lessThan(0.2));
    });

    test('grows with the run and never with nothing', () {
      final one = ReelDuration.estimateMs(fatiha, startAyah: 1, endAyah: 1);
      final all = ReelDuration.estimateMs(fatiha, startAyah: 1, endAyah: 7);
      expect(one, greaterThan(0));
      expect(all, greaterThan(one));
      // A run that isn't one.
      expect(ReelDuration.estimateMs(fatiha, startAyah: 3, endAyah: 2), 0);
      expect(ReelDuration.estimateMs(const [], startAyah: 1, endAyah: 7), 0);
    });

    test('a mujawwad voice takes its own time', () {
      // The ornate readings run about twice as long over the same
      // text. An estimate blind to that would wave a two-hour
      // selection through as one — the exact case the cap exists for.
      final murattal =
          ReelDuration.estimateMs(fatiha, startAyah: 1, endAyah: 7);
      final mujawwad = ReelDuration.estimateMs(
        fatiha,
        startAyah: 1,
        endAyah: 7,
        pace: reciters.firstWhere((r) => r.id == 'husary_mujawwad').pace,
      );
      expect(mujawwad, greaterThan(murattal * 1.8));
    });

    test('verses the list does not reach are still charged for', () {
      // A partially loaded surah must not make a selection look
      // shorter than it is — that is the one error direction the cap
      // cannot survive.
      final whole = ReelDuration.estimateMs(fatiha, startAyah: 1, endAyah: 7);
      final beyond =
          ReelDuration.estimateMs(fatiha.sublist(0, 3), startAyah: 1, endAyah: 7);
      expect(beyond, greaterThan(whole * 0.5));
    });

    test('the cap is reached by a plausible number of verses', () {
      // Roughly Al-Baqarah's longer verses, repeated. An hour of
      // recitation is a few hundred of them — not five, and not five
      // thousand.
      final long = [
        for (var i = 1; i <= 400; i++)
          Ayah(
            number: i,
            arabic: 'ٱلْحَمْدُ لِلَّهِ رَبِّ ٱلْعَـٰلَمِينَ ' * 4,
            translation: '',
          ),
      ];
      int fits() {
        var n = 1;
        while (n < long.length &&
            ReelDuration.estimateMs(long, startAyah: 1, endAyah: n + 1) <=
                ReelLimits.maxReelMs) {
          n++;
        }
        return n;
      }

      expect(fits(), greaterThan(100));
      expect(fits(), lessThan(400));
    });
  });

  group('only a clip the user brought in can be too short', () {
    // A catalog scenery is authored to loop seamlessly, so its own
    // length is not a limit on the turn it can be given. Whether it
    // happens to be bundled or downloaded is an accident of install
    // size — and asking [isDeviceFile] made it the difference between
    // a reel that exports and one the app refuses to build.
    const bundled = ReelBackground.still(
      id: 'sky_pexels_01',
      name: 'Sky 1',
      imageAsset: 'assets/backgrounds/sky_pexels_01.jpg',
      gradientArgb: [0xFF000000, 0xFF101010],
    );
    const downloaded = ReelBackground.cached(
      id: 'aerial_coast_pexels_03',
      name: 'Aerial coast',
      filePath: '/tmp/aerial_coast_pexels_03.mp4',
      fileIsImage: false,
      gradientArgb: [0xFF000000, 0xFF101010],
      knownAspect: 1920 / 1080,
    );
    const picked = ReelBackground.deviceFile(
      id: 'custom_1',
      name: 'My clip',
      filePath: '/tmp/whatever.mp4',
      fileIsImage: false,
    );

    test('a downloaded catalog scene has no length worth knowing', () async {
      expect(downloaded.isDeviceFile, isTrue);
      expect(downloaded.isUserFile, isFalse);
      expect(await MediaDuration.of(downloaded), isNull);
      expect(MediaDuration.cached(downloaded), isNull);
    });

    test('nor does a bundled one', () async {
      expect(bundled.isUserFile, isFalse);
      expect(await MediaDuration.of(bundled), isNull);
    });

    test('a picked clip is the one that gets measured', () {
      expect(picked.isUserFile, isTrue);
      // Nothing to probe with off-device, so only the question asked
      // of it is checked — the probe itself is FFmpeg's.
      expect(MediaDuration.cached(picked), isNull);
    });
  });
}
