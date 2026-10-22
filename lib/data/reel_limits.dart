/// How long a reel is allowed to be, in one place.
///
/// The verse picker, the preview's post-download trim and the strings
/// that explain the cap all read these — a cap enforced in three
/// places with three numbers would eventually be three caps.
abstract final class ReelLimits {
  /// The hard ceiling: one hour of recitation.
  ///
  /// Nothing in the pipeline is bounded by the reel's length any more
  /// — the exporter cuts a long reel into passes and joins them, so
  /// the filter graph stays the same size whether the reel runs one
  /// minute or sixty. What is still bounded is the *device*: an hour
  /// at 1080x1920 takes real minutes to encode and the best part of a
  /// gigabyte to hold, three times over between the render, the
  /// library copy and the gallery. An hour is where that stops being
  /// something we should let happen by accident.
  static const maxReelMs = 60 * 60 * 1000;

  /// Fallback bound before the recitation's timings are known: no
  /// surah has more ayahs than this (Al-Baqarah, 286), so it never
  /// refuses a selection the clock would have allowed — it only keeps
  /// a selection made against unknown timings finite.
  static const maxReelAyahs = 300;

  /// Longest reel still pre-rendered in the background while the user
  /// watches the preview.
  ///
  /// The eager render exists to make Share feel instant, and it is
  /// worth the battery only while the encode is short. Past this the
  /// export is done on demand, behind the progress bar the user is
  /// already looking at, rather than silently for minutes on end.
  static const eagerRenderMaxMs = 3 * 60 * 1000;

  /// Whole minutes in the cap, for the strings that quote it.
  static int get maxReelMinutes => maxReelMs ~/ 60000;
}
