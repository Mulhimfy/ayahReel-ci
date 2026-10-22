import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../data/card_deck.dart';
import '../data/card_images.dart';
import '../data/card_style.dart';
import '../data/card_compose.dart';
import '../data/debug_log.dart';
import '../l10n/l10n.dart';
import '../widgets/card_canvas.dart';
import '../widgets/film_grain.dart';
import 'ayah_rasterizer.dart';

/// Turns a deck into files.
///
/// The exporter rasterizes the very widget the composer draws — see
/// [CardCanvas] — at 1080 across, so what is saved is what was on
/// screen. Nothing is re-implemented here: no second opinion about
/// where the type goes, what the frame looks like or where the mark
/// hangs, because a second opinion is a bug that only ever shows up
/// after the picture has been shared.
///
/// It is pure Flutter. A reel needs FFmpeg because it is a video; a
/// card is one frame, and one frame is something the framework that
/// drew it can hand back directly.
abstract final class CardExporter {
  /// PNG rather than JPEG. A card is flat colour and type — exactly
  /// what JPEG's ringing shows up on worst — and at 1080 a card is a
  /// few hundred KB either way.
  static const _ext = 'png';

  /// One file per card, in order, written to the temporary directory.
  ///
  /// [onProgress] reports 0..1 across the deck: a single card is done
  /// before anything could show it, ten of them is a real wait.
  ///
  /// Every background is decoded before the first capture, not during
  /// it: a capture is synchronous once it starts, so a picture that
  /// has not landed by then would be exported as an empty card.
  /// [asStory] re-cuts the deck to 9:16 on the way out.
  ///
  /// A card is 4:5 and a story is 9:16; handed over as it is, it is
  /// cropped or boxed by whatever it is dropped into. Re-cutting costs
  /// nothing — every position on a card is a fraction, see
  /// [CardCompose.reshape] — and the strip it opens up at the foot is
  /// where the mark climbs to clear Instagram's own bar.
  static Future<List<File>> render(
    CardDeck deck, {
    bool asStory = false,
    void Function(double)? onProgress,
  }) async {
    deck = prepare(deck, asStory: asStory);
    final images = <String, ui.Image>{};
    for (final slide in deck.slides) {
      final image = await CardImages.resolve(slide.background);
      if (image != null) images[slide.id] = image;
    }
    // The grain tile and the one font the mark is set in. Both are
    // asynchronous and neither gets a second frame off screen.
    await FilmGrain.warm();
    // Written here rather than stored on the deck: the wording belongs
    // to the language the app is in, so a deck dedicated in English
    // and exported after switching to Arabic exports in Arabic.
    final line = deck.dedication.isEmpty
        ? ''
        : L10n.current
            .dedicationLine(deck.dedication.kind, deck.dedication.name);

    // One directory, emptied on the way in rather than a fresh one per
    // export: a deck exported five times while it is being tuned would
    // otherwise leave five sets of PNGs behind, and nothing deletes
    // them until the OS decides the temporary directory is too big.
    final dir = Directory('${(await getTemporaryDirectory()).path}/cards');
    if (dir.existsSync()) {
      for (final f in dir.listSync().whereType<File>()) {
        try {
          f.deleteSync();
        } catch (_) {/* a file being shared right now; leave it */}
      }
    } else {
      dir.createSync(recursive: true);
    }
    final out = <File>[];
    for (var i = 0; i < deck.slides.length; i++) {
      final slide = deck.slides[i];
      final bytes = await AyahRasterizer.widgetToPng(
        MediaQuery(
          data: MediaQueryData(
            size: Size(CardFormat.exportWidth, deck.format.exportHeight),
            devicePixelRatio: 1,
          ),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: CardCanvas(
              slide: slide,
              format: deck.format,
              width: CardFormat.exportWidth,
              picture: images[slide.id],
              dedication: line,
            ),
          ),
        ),
      );
      final file = File('${dir.path}/${name(deck, i)}.$_ext');
      await file.writeAsBytes(bytes, flush: true);
      out.add(file);
      onProgress?.call((i + 1) / deck.slides.length);
    }
    rlog('cards: exported ${out.length} at ${CardFormat.exportWidth.toInt()}'
        'x${deck.format.exportHeight.round()}');
    return out;
  }

  /// The deck as it will actually be exported: re-cut for a story if
  /// it is going to one.
  ///
  /// Public because the composer shows the user what this returns.
  ///
  /// Nothing is added on the end any more. The app used to sign a deck
  /// with one more card carrying the maker's name and its own — an
  /// invitation, removable, and still a card the person who made the
  /// deck did not write. What they send is now only what they made.
  static CardDeck prepare(CardDeck deck, {bool asStory = false}) {
    final format = asStory ? CardFormat.story : deck.format;
    var slides = deck.slides;
    if (asStory && format != deck.format) {
      slides = [
        for (final s in slides) CardCompose.reshape(s, deck.format, format),
      ];
    }
    return deck.copyWith(format: format, slides: slides);
  }

  /// A small picture of one card, for the library's shelf.
  ///
  /// The same widget again, at a fraction of the size — so a cover
  /// cannot drift from the card it is a cover of, and a deck whose
  /// scenery has since been deleted still shows what it looked like.
  /// 360 across is two columns on a large phone at 2x.
  static Future<List<int>> cover({
    required CardDeck deck,
    required CardSlide slide,
    ui.Image? picture,
  }) async {
    await FilmGrain.warm();
    const width = 360.0;
    return AyahRasterizer.widgetToPng(
      MediaQuery(
        data: MediaQueryData(
          size: Size(width, width / deck.format.aspect),
          devicePixelRatio: 1,
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: CardCanvas(
            slide: slide,
            format: deck.format,
            width: width,
            picture: picture,
            dedication: deck.dedication.isEmpty
                ? ''
                : L10n.current.dedicationLine(
                    deck.dedication.kind, deck.dedication.name),
          ),
        ),
      ),
    );
  }

  /// What the file is called in the user's gallery: the app, the date,
  /// and the card's place in its deck. A carousel saved out of order
  /// is a carousel posted out of order.
  static String name(CardDeck deck, int index) {
    final d = deck.createdAt;
    final stamp = '${d.year}${_pad(d.month)}${_pad(d.day)}_'
        '${_pad(d.hour)}${_pad(d.minute)}';
    return deck.slides.length > 1
        ? 'AyahReel_${stamp}_${_pad(index + 1)}'
        : 'AyahReel_$stamp';
  }

  static String _pad(int v) => v.toString().padLeft(2, '0');
}
