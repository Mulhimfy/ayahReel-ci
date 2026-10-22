import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// The film grain the exporter lays over every frame, drawn over the
/// preview so the effect is something you can see before you spend an
/// encode on it.
///
/// An honest approximation rather than a copy, and the one place in
/// this app where the preview is not the file. FFmpeg's `noise` filter
/// draws a fresh field of luma noise on *every frame*; this is one
/// field, tiled and still. Same texture, same strength, no motion —
/// which is the part a still preview could not show whatever it drew.
///
/// The tile is generated once per process and shared by every widget
/// that asks for it: a 96x96 field of grey, which at 1:1 over a
/// quarter-size preview frame is the same grain size the export lays
/// over the full one.
class FilmGrain extends StatefulWidget {
  /// 0..1, the same number the exporter turns into a noise strength.
  final double strength;

  const FilmGrain({super.key, required this.strength});

  /// Side of the generated tile, in pixels.
  static const _tile = 96;

  static ui.Image? _image;
  static Future<ui.Image>? _pending;

  /// Generates the tile if it has not been generated, and completes
  /// when it is in hand.
  ///
  /// On screen a missing tile costs one frame — the widget draws
  /// nothing and rebuilds when it lands. Off screen there is no second
  /// frame: a card rasterized before the tile exists is a card with no
  /// grain on it, exported and shared. So the card exporter waits on
  /// this first, once.
  static Future<void> warm() => _grain();

  /// One field of grey noise, decoded once and kept for the life of
  /// the process. Deterministic: a fixed seed, so two previews of the
  /// same reel are the same picture.
  static Future<ui.Image> _grain() => _pending ??= () async {
        final rnd = math.Random(0x5EED);
        final px = Uint8List(_tile * _tile * 4);
        for (var i = 0; i < _tile * _tile; i++) {
          // Centred on mid-grey: `overlay` leaves mid-grey alone, so
          // the tile darkens and lightens by the same amount instead
          // of only ever brightening.
          final v = (128 + (rnd.nextDouble() - 0.5) * 255).round().clamp(0, 255);
          px[i * 4] = v;
          px[i * 4 + 1] = v;
          px[i * 4 + 2] = v;
          px[i * 4 + 3] = 255;
        }
        final buffer = await ui.ImmutableBuffer.fromUint8List(px);
        final desc = ui.ImageDescriptor.raw(
          buffer,
          width: _tile,
          height: _tile,
          pixelFormat: ui.PixelFormat.rgba8888,
        );
        final codec = await desc.instantiateCodec();
        final frame = await codec.getNextFrame();
        _image = frame.image;
        return frame.image;
      }();

  @override
  State<FilmGrain> createState() => _FilmGrainState();
}

class _FilmGrainState extends State<FilmGrain> {
  ui.Image? _img = FilmGrain._image;

  @override
  void initState() {
    super.initState();
    if (_img != null) return;
    FilmGrain._grain().then((i) {
      if (mounted) setState(() => _img = i);
    });
  }

  @override
  Widget build(BuildContext context) {
    final img = _img;
    if (img == null || widget.strength <= 0) return const SizedBox.shrink();
    return IgnorePointer(
      child: CustomPaint(
        painter: _GrainPainter(img, widget.strength),
        size: Size.infinite,
      ),
    );
  }
}

class _GrainPainter extends CustomPainter {
  final ui.Image tile;
  final double strength;

  const _GrainPainter(this.tile, this.strength);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ImageShader(
          tile,
          TileMode.repeated,
          TileMode.repeated,
          Matrix4.identity().storage,
        )
        ..blendMode = BlendMode.overlay
        // The export's noise runs from a barely-there dither to a
        // coarse grain; this is the same span in opacity, and the
        // ceiling is where grain stops being texture and starts being
        // dirt on the lens.
        ..color = Colors.white.withValues(alpha: 0.10 + 0.22 * strength),
    );
  }

  @override
  bool shouldRepaint(covariant _GrainPainter old) =>
      old.tile != tile || old.strength != strength;
}
