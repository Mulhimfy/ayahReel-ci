import '../models.dart';
import '../qul_words.dart';

/// Word timing AyahReel Listen found in an upload, kept for the reel
/// being built: what the lit word, the unveil, the lines and the light
/// follow on the user's own recording, as they follow an app voice's.
///
/// In memory only, like the upload's verse timing
/// (`UserAudioService.register`): it belongs to this run, not the file.
abstract final class ListenWords {
  /// '<upload id>_<surah>' -> ayah -> [from, to, p, s, e, ...] in ms on
  /// the upload's own clock (the compact form, `QulWords.decodeCompact`).
  static final _timing = <String, Map<int, List<int>>>{};

  /// '<upload id>_<surah>' -> ayah -> the verse's word count (the app's).
  static final _counts = <String, Map<int, int>>{};

  static String _key(String uploadId, int surah) => '${uploadId}_$surah';

  /// Files what Listen heard for [surah] in the upload [uploadId].
  /// [counts]: each verse's word count, as the engine counted the app's
  /// text (what `WordAlignService.fromMushafWords` checks against).
  static void register(String uploadId, int surah, Map<int, List<int>> timing,
      Map<int, int> counts) {
    _timing[_key(uploadId, surah)] = {
      for (final e in timing.entries) e.key: List<int>.unmodifiable(e.value),
    };
    _counts[_key(uploadId, surah)] = Map.unmodifiable(counts);
  }

  /// Drops every surah of [uploadId] (a different file came in).
  static void forget(String uploadId) {
    _timing.removeWhere((k, _) => k.startsWith('${uploadId}_'));
    _counts.removeWhere((k, _) => k.startsWith('${uploadId}_'));
  }

  static void forgetAll() {
    _timing.clear();
    _counts.clear();
  }

  static bool has(String uploadId, int surah) =>
      _timing.containsKey(_key(uploadId, surah));

  /// Whether an upload has any Listen timing at all.
  static bool hasAny(String uploadId) =>
      _timing.keys.any((k) => k.startsWith('${uploadId}_'));

  /// The upload's words for the verses of [rec], placed as
  /// `QulWords.forRecitation` places a voice's: (position, start, end)
  /// in ms from each verse's window in [rec]. Only words inside the
  /// window. Null when Listen timed none of them.
  static Map<int, Placed>? placedFor(String uploadId, Recitation rec) {
    final t = _timing[_key(uploadId, rec.surah)];
    final counts = _counts[_key(uploadId, rec.surah)];
    if (t == null || counts == null) return null;
    final out = <int, Placed>{};
    for (final w in rec.timings) {
      final v = t[w.ayah];
      if (v == null || v.length < 5) continue;
      final count = counts[w.ayah];
      if (count == null) continue;
      final words = <(int, int, int)>[];
      for (var i = 2; i + 2 < v.length; i += 3) {
        final p = v[i];
        final s = v[i + 1] - w.startMs, e = v[i + 2] - w.startMs;
        final len = w.endMs - w.startMs;
        if (e <= 0 || s >= len) continue;
        words.add((p, s < 0 ? 0 : s, e > len ? len : e));
      }
      if (words.isNotEmpty) out[w.ayah] = (count: count, words: words);
    }
    return out.isEmpty ? null : out;
  }
}
