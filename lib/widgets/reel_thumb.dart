import 'dart:io';

import 'package:flutter/material.dart';
import '../data/reel_library.dart';
import '../render/reel_poster.dart';

/// A frame from the reel itself, faded in over the card's background
/// gradient once it has been extracted. Until then — and if extraction
/// fails — the gradient is what shows, so a card is never blank.
///
/// Meant to sit as the first child of a card's Stack, under the play
/// glyph and the title scrim.
class ReelThumb extends StatefulWidget {
  final SavedReel reel;
  const ReelThumb({super.key, required this.reel});

  @override
  State<ReelThumb> createState() => _ReelThumbState();
}

class _ReelThumbState extends State<ReelThumb> {
  /// Held in state, not built in `build`: a FutureBuilder fed a future
  /// created inline restarts the extraction on every rebuild, and
  /// these cards rebuild on every scroll.
  ///
  /// Re-resolved when the reel changes, though, and that is not the
  /// same thing. The library is newest-first, so exporting a reel does
  /// not give it a new card — it takes over the card at index 0, and
  /// this State comes with it. Held as `late final`, the poster stayed
  /// the one belonging to whoever sat here before: the newest reel wore
  /// the previous reel's frame and the whole column shifted by one.
  /// The list itself was always right, which is why tearing every card
  /// down — a hot reload, or leaving the tab and coming back — looked
  /// like a fix.
  late Future<File?> _poster;

  @override
  void initState() {
    super.initState();
    _poster = ReelPoster.ensure(widget.reel);
  }

  @override
  void didUpdateWidget(covariant ReelThumb old) {
    super.didUpdateWidget(old);
    if (widget.reel.id != old.reel.id) {
      _poster = ReelPoster.ensure(widget.reel);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File?>(
      future: _poster,
      builder: (context, snap) {
        final file = snap.data;
        return AnimatedOpacity(
          opacity: file == null ? 0 : 1,
          duration: const Duration(milliseconds: 220),
          child: file == null
              ? const SizedBox.expand()
              : Image.file(
                  file,
                  fit: BoxFit.cover,
                  // The card it sits in names the reel; a nameless
                  // "image" under it would be read as a second thing.
                  excludeFromSemantics: true,
                  // Cards are 9:16 like the reel, so cover crops
                  // nothing; gaplessPlayback keeps the fade smooth.
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => const SizedBox.expand(),
                ),
        );
      },
    );
  }
}
