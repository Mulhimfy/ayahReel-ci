import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/render/letterbox_layout.dart';

/// The blurred letterbox backdrop is toned by two filters that never
/// meet: a Flutter `ColorFilter.matrix` in the preview and an FFmpeg
/// `colorchannelmixer` in the export. Nothing at runtime compares them.
///
/// It is also the place a whole class of "the blur doesn't work" bugs
/// hides, because the blur is not what fails — the tone is. A fixed
/// subtraction (`eq=brightness=-0.30`, 76 of 255 off every pixel) looks
/// correct on a bright scenery and clips a dark one to solid black, and
/// a black band is indistinguishable from the flat-colour backdrop
/// sitting next to it in the picker. Eleven of the twenty bundled
/// stills went out that way.
///
/// So: pin that the tone only ever scales, and that both filters are
/// the same numbers.
void main() {
  /// The 3x3 the export sends FFmpeg, parsed back out of the argument
  /// string, so the test reads what FFmpeg will actually be given.
  Map<String, double> parseMix(String mix) => {
        for (final pair in mix.split(':'))
          pair.split('=')[0]: double.parse(pair.split('=')[1]),
      };

  group('the tone only scales', () {
    test('no channel carries an offset', () {
      final m = BackdropTone.colorMatrix;
      // Column 5 of each row is the 0..255 translation. Any non-zero
      // value here is a fixed subtraction from a quantity that is not
      // fixed, which is the bug this file exists to stop coming back.
      for (var row = 0; row < 4; row++) {
        expect(m[row * 5 + 4], 0,
            reason: 'row $row has an additive term; the tone must scale');
      }
    });

    test('a dark scenery survives it, where an offset would erase it', () {
      // Roughly what a mosque at dusk blurs down to: dark, but a
      // picture. The old offset took 76 off this and left nothing.
      const dim = 27.0;
      final out = _apply(BackdropTone.colorMatrix, dim, dim, dim);
      expect(out, greaterThan(1),
          reason: 'a dark scenery must still show as a blurred picture');
      expect(out, closeTo(dim * BackdropTone.gain, 0.5));
    });

    test('darkening is proportional, so relative structure is kept', () {
      // Two patches an octave apart stay an octave apart. A subtraction
      // does not have this property — it flattens the dark one onto the
      // floor and leaves the bright one alone.
      final dark = _apply(BackdropTone.colorMatrix, 40, 40, 40);
      final bright = _apply(BackdropTone.colorMatrix, 80, 80, 80);
      expect(bright / dark, closeTo(2.0, 0.01));
    });

    test('a bright scenery is still pulled well down', () {
      // The backdrop is a backdrop: the verse has to read on it.
      final out = _apply(BackdropTone.colorMatrix, 255, 255, 255);
      expect(out, lessThan(160));
    });
  });

  group('preview and export agree', () {
    test('the FFmpeg mixer is the preview matrix, cell for cell', () {
      final mix = parseMix(BackdropTone.ffmpegMix);
      final m = BackdropTone.colorMatrix;
      const names = [
        ['rr', 'rg', 'rb'],
        ['gr', 'gg', 'gb'],
        ['br', 'bg', 'bb'],
      ];
      for (var row = 0; row < 3; row++) {
        for (var col = 0; col < 3; col++) {
          expect(mix[names[row][col]], closeTo(m[row * 5 + col], 0.0001),
              reason: '${names[row][col]} differs between preview and export');
        }
      }
    });

    test('the mixer names all nine channels and nothing else', () {
      final mix = parseMix(BackdropTone.ffmpegMix);
      expect(mix.keys.toSet(), {
        'rr', 'rg', 'rb', //
        'gr', 'gg', 'gb', //
        'br', 'bg', 'bb', //
      });
    });
  });

  group('desaturation', () {
    test('a grey stays grey', () {
      final m = BackdropTone.colorMatrix;
      final r = _channel(m, 0, 90, 90, 90);
      final g = _channel(m, 1, 90, 90, 90);
      final b = _channel(m, 2, 90, 90, 90);
      expect(r, closeTo(g, 0.01));
      expect(g, closeTo(b, 0.01));
    });

    test('a saturated colour is pulled toward its own luma, not past it', () {
      // Each channel's own weight dominates its row: the backdrop is
      // muted, never hue-shifted into something else.
      final m = BackdropTone.colorMatrix;
      for (var row = 0; row < 3; row++) {
        final own = m[row * 5 + row];
        for (var col = 0; col < 3; col++) {
          if (col == row) continue;
          expect(own, greaterThan(m[row * 5 + col]),
              reason: 'row $row is no longer dominated by its own channel');
        }
      }
    });
  });
}

/// One output channel of a `ColorFilter.matrix` for an input colour.
double _channel(List<double> m, int row, double r, double g, double b) =>
    m[row * 5] * r + m[row * 5 + 1] * g + m[row * 5 + 2] * b + m[row * 5 + 4];

/// Rec. 709 luminance of the colour the matrix produces from an input.
double _apply(List<double> m, double r, double g, double b) =>
    0.2126 * _channel(m, 0, r, g, b) +
    0.7152 * _channel(m, 1, r, g, b) +
    0.0722 * _channel(m, 2, r, g, b);
