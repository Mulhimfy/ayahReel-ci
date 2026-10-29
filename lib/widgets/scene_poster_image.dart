import 'package:flutter/material.dart';

import '../data/scene_catalog.dart';

/// A scenery's poster: the one in the app, or the served one kept on the
/// phone (see [SceneCatalog.posterOf]).
///
/// A served poster seen for the first time fades in over whatever is
/// under it — every caller lays the scenery's measured gradient there —
/// and one that can't be had (no network on a first look) leaves that
/// gradient showing rather than an error.
class ScenePosterImage extends StatelessWidget {
  final Scene scene;
  final BoxFit fit;

  /// Decoded no wider than this, for a poster drawn small.
  final int? cacheWidth;

  const ScenePosterImage(
    this.scene, {
    super.key,
    this.fit = BoxFit.cover,
    this.cacheWidth,
  });

  @override
  Widget build(BuildContext context) {
    final poster = SceneCatalog.posterOf(scene);
    final width = cacheWidth;
    return Image(
      image: width == null ? poster : ResizeImage(poster, width: width),
      fit: fit,
      excludeFromSemantics: true,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
          wasSynchronouslyLoaded
              ? child
              : AnimatedOpacity(
                  opacity: frame == null ? 0 : 1,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  child: child,
                ),
    );
  }
}
