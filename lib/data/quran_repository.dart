import 'models.dart';
import 'quran_text_service.dart';
import 'recitation_service.dart';
import 'surah_index.dart';
import 'user_audio_service.dart';

export 'surah_index.dart' show SurahInfo;

/// Single gateway between UI and Quran content. Screens never touch
/// data files or the network directly: text comes from the bundled
/// Fatiha or a cached one-time fetch, audio+timings from the bundled
/// asset, an on-device build from the reciter's source, or the file the
/// user uploaded.
abstract final class QuranRepository {
  /// The whole Quran. Metadata is static, so it's always available.
  static const List<SurahInfo> surahs = surahIndex;

  static SurahInfo surahInfo(int surah) =>
      surahs.firstWhere((s) => s.number == surah);

  /// Instant when bundled or previously loaded; null means [ayahsOf]
  /// will need a network fetch.
  static List<Ayah>? ayahsIfCached(int surah) =>
      QuranTextService.cached(surah);

  static Future<List<Ayah>> ayahsOf(int surah) =>
      QuranTextService.load(surah);

  /// Recitation (audio + exact matching timings) for a reciter and
  /// surah, covering [startAyah]..[endAyah] (whole surah when omitted).
  /// May download and assemble on first use; [onProgress] reports 0..1.
  ///
  /// An uploaded recitation is never fetched or assembled — it is
  /// already one file on disk, and the only thing that ever had to be
  /// worked out about it was where its verses fall. The timing screen
  /// does that and files the result; this hands it straight back.
  static Future<Recitation> recitation(
    Reciter reciter,
    int surah, {
    int? startAyah,
    int? endAyah,
    void Function(double progress)? onProgress,
  }) {
    if (reciter.isUserAudio) {
      final rec = UserAudioService.aligned(reciter.id, surah);
      if (rec == null) {
        return Future.error(
            StateError('No alignment for ${reciter.id} surah $surah'));
      }
      onProgress?.call(1);
      return Future.value(rec);
    }
    return RecitationService.load(reciter, surah,
        startAyah: startAyah, endAyah: endAyah, onProgress: onProgress);
  }

  /// Ready-now recitation, if any — for instant duration labels. May
  /// cover only part of the surah: check [Recitation.covers] first.
  static Recitation? recitationIfCached(String reciterId, int surah) =>
      UserAudioService.aligned(reciterId, surah) ??
      RecitationService.cached(reciterId, surah);

  /// Warm the recitation cache in the background (errors ignored).
  /// Nothing to warm for an upload: its audio is already local.
  static void prefetchRecitation(Reciter reciter, int surah,
      {int? startAyah, int? endAyah}) {
    if (reciter.isUserAudio) return;
    RecitationService.prefetch(reciter, surah,
        startAyah: startAyah, endAyah: endAyah);
  }
}
