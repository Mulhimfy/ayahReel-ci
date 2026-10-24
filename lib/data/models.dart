import 'package:flutter/foundation.dart';

@immutable
class Ayah {
  final int number;
  final String arabic;
  final String translation;
  const Ayah({
    required this.number,
    required this.arabic,
    required this.translation,
  });
}

/// One ayah's window inside a full-surah recording, in milliseconds.
@immutable
class AyahTiming {
  final int ayah;
  final int startMs;
  final int endMs;
  const AyahTiming(this.ayah, this.startMs, this.endMs);

  int get durationMs => endMs - startMs;
}

/// One aligned word group inside a single ayah's audio file, from the
/// quran-align project. Times are milliseconds relative to that ayah's
/// start; [startWord]..[endWord] (exclusive) index the space-split,
/// letter-bearing words of the ayah text.
@immutable
class WordSpan {
  final int startWord;
  final int endWord;
  final int startMs;
  final int endMs;
  const WordSpan(this.startWord, this.endWord, this.startMs, this.endMs);
}

/// A ready-to-show highlight window: [startMs, endMs) relative to the
/// ayah's start in the recording (gaps between spans already filled, so
/// a word stays lit through the reciter's pauses), highlighting display
/// tokens [tokenStart, tokenEnd) of the ayah's Arabic text.
@immutable
class HighlightSpan {
  final int startMs;
  final int endMs;
  final int tokenStart;
  final int tokenEnd;
  const HighlightSpan(this.startMs, this.endMs, this.tokenStart, this.tokenEnd);
}

/// Where a voice's audio comes from, which decides how a recitation of
/// it is put together. See [RecitationService].
@immutable
sealed class AudioSource {
  const AudioSource();
}

/// One mp3 per ayah, at `<host>/<folder>/SSSAAA.mp3`.
///
/// Each file is measured on the device as it lands, so the timing table
/// of anything built from them is exact by construction: the windows
/// are the files.
final class AyahFiles extends AudioSource {
  static const everyAyahHost = 'https://everyayah.com/data';
  static const tarteelHost = 'https://audio-cdn.tarteel.ai/quran';

  /// King Saud University's Ayat project, which keeps per-ayah sets
  /// EveryAyah doesn't have.
  static const ksuHost = 'https://quran.ksu.edu.sa/ayat/mp3';

  final String host;
  final String folder;

  const AyahFiles.everyAyah(this.folder) : host = everyAyahHost;
  const AyahFiles.tarteel(this.folder) : host = tarteelHost;
  const AyahFiles.ksu(this.folder) : host = ksuHost;

  /// Any host: for tests, which serve the files themselves.
  @visibleForTesting
  const AyahFiles.at(this.host, this.folder);

  Uri url(int surah, int ayah) => Uri.parse('$host/$folder/'
      '${surah.toString().padLeft(3, '0')}'
      '${ayah.toString().padLeft(3, '0')}.mp3');
}

/// One mp3 per surah, at `<base>/SSS.mp3` (or `<base>/S.mp3` when not
/// [padded]), and a published table of where each ayah starts and ends
/// inside it — see [SurahTiming].
///
/// Sync here is only as good as that table, which is why no voice of
/// this kind ships until `tool/verify_reciters.py` has checked its
/// tables against its audio, and why the app still snaps every
/// boundary to the reciter's own pause when it cuts.
final class SurahFiles extends AudioSource {
  final String base;
  final bool padded;
  final SurahTiming timing;

  /// Set when the table counts the words every surah opens with — the
  /// basmala, and before Al-Fatiha's the isti'adha — as part of verse 1,
  /// to about how long they run, in milliseconds. The app shows verse 1
  /// without them, so a reel that starts there starts at the breath
  /// after them instead (see [SurahSlice.plan]). At-Tawbah opens with
  /// verse 1 itself and is left alone. tool/verify_reciters.py finds
  /// that breath in every surah before such a voice ships.
  final int? openingMs;

  /// Surahs this voice can't be offered for: a file the host doesn't
  /// have, or a table that doesn't fit its file. tool/verify_reciters.py
  /// names them; the pickers leave them out for this voice, and
  /// [RecitationService] refuses them with [SurahUnavailable].
  final Set<int> missing;

  const SurahFiles(this.base,
      {required this.timing,
      this.padded = true,
      this.openingMs,
      this.missing = const {}});

  Uri url(int surah) => Uri.parse(
      '$base/${padded ? surah.toString().padLeft(3, '0') : '$surah'}.mp3');
}

/// Who publishes the ayah table for a [SurahFiles] voice, and under
/// which key. Both answer one surah per request.
@immutable
sealed class SurahTiming {
  const SurahTiming();

  /// The table for [surah], which has [count] ayahs.
  Uri url(int surah, int count);
}

/// mp3quran.net's `ayat_timing`, keyed by [read]: a list of
/// `{ayah, start_time, end_time}` in milliseconds.
final class Mp3QuranTiming extends SurahTiming {
  static const api = 'https://www.mp3quran.net/api/v3/ayat_timing';

  final int read;

  const Mp3QuranTiming(this.read);

  @override
  Uri url(int surah, int count) => Uri.parse('$api?surah=$surah&read=$read');
}

/// The Quranic Universal Library's surah segments (Tarteel), keyed by
/// [recitation]: `segments` maps `"s:a"` to `{time_from, time_to}` in
/// milliseconds, word by word inside. One page holds the whole surah.
final class QulTiming extends SurahTiming {
  static const api = 'https://qul.tarteel.ai/api/v1/audio/surah_segments';

  final int recitation;

  const QulTiming(this.recitation);

  @override
  Uri url(int surah, int count) => Uri.parse(
      '$api/$recitation?surah=$surah&from=1&to=$count&per_page=$count');
}

/// A table of our own, for a recording that publishes none or none
/// that fits its files: made from the recording by forced alignment,
/// measured against voices whose verse starts are known, and checked
/// against its audio like every published table (tool/verse_table.py,
/// tool/verify_reciters.py). [VerseTables] gets it under [table]: served
/// only to the app, checked against the digest the build trusts, kept.
final class OwnTiming extends SurahTiming {
  final String table;

  const OwnTiming(this.table);

  /// Never asked: [RecitationService] reads [VerseTables] instead.
  @override
  Uri url(int surah, int count) =>
      throw UnsupportedError('table $table comes from VerseTables');
}

/// A recording the user brought in themselves. Nothing to download,
/// nothing to preview from the network. See [UserAudioService].
final class OwnAudio extends AudioSource {
  const OwnAudio();
}

@immutable
class Reciter {
  final String id;
  final String name;
  final String arabicName;
  final String style;

  /// Where every surah beyond the bundled one comes from.
  final AudioSource source;

  /// Full-surah mp3 bundled at assets/audio/<id>_001.mp3 (Al-Fatiha
  /// only — the instant, offline first-run experience). Null for
  /// reciters whose audio is built entirely on demand.
  final String? audioAsset;

  /// Ayah windows for that exact bundled recording. The audio file and
  /// this list always travel together; never mix recordings. Null iff
  /// [audioAsset] is null.
  final List<AyahTiming>? timings;

  /// How slowly this voice recites, relative to a typical murattal
  /// reading. Used for one thing only: estimating how long a selection
  /// will run *before* any of its audio has been measured, so the verse
  /// picker can refuse a reel over the cap instead of leaving the
  /// preview to trim it. Once the recitation is on the device its own
  /// timings are exact and this is never consulted again.
  ///
  /// 1.0 for the original murattal voices — the model is calibrated on
  /// them. The mujawwad readings take roughly twice as long over the
  /// same text, and an estimate that ignored that would let a two-hour
  /// selection through as one. Voices added since carry the pace
  /// `tool/verify_reciters.py` measured: over all 6236 windows for a
  /// surah-file voice, over a spread of verses for a per-ayah one.
  final double pace;

  /// The voice this is another recording of, by that voice's id; null
  /// for a voice's first recording (or its only one).
  ///
  /// Another recording is a [Reciter] of its own — its own audio, table,
  /// cache and verification — but the pickers list it under its voice,
  /// not beside it: the same reciter, another performance, so reels of
  /// the same verses need not all carry the same sound.
  /// tool/verify_reciters.py checks that it really is another
  /// performance and not the same one served from somewhere else.
  final String? recordingOf;

  /// What sets this recording apart from the voice's others, in a few
  /// words ("Makkah · 1435"). Null on a voice's first recording.
  final String? recordingNote;

  const Reciter({
    required this.id,
    required this.name,
    required this.arabicName,
    required this.style,
    required this.source,
    this.audioAsset,
    this.timings,
    this.pace = 1.0,
    this.recordingOf,
    this.recordingNote,
  }) : assert((audioAsset == null) == (timings == null));

  bool get hasBundledFatiha => audioAsset != null;

  /// The EveryAyah folder behind this voice, or null when its audio
  /// comes from anywhere else. Word timings are only ever released
  /// against EveryAyah recordings (see [WordAlignService]).
  String? get everyAyahFolder => switch (source) {
        AyahFiles(:final host, :final folder)
            when host == AyahFiles.everyAyahHost =>
          folder,
        _ => null,
      };

  /// True for the stand-in voice that represents a recording the user
  /// brought in themselves: there is nothing to download, nothing to
  /// preview from the network, and no released word alignment that
  /// could match it. Everything that would otherwise reach for the
  /// network asks this first.
  bool get isUserAudio => source is OwnAudio;

  /// Whether this voice has recorded [surah]. Every voice has every
  /// surah but the few a surah-file voice lists as missing.
  bool hasSurah(int surah) => switch (source) {
        SurahFiles(:final missing) => !missing.contains(surah),
        _ => true,
      };

  /// The surahs this voice hasn't recorded, if any.
  Set<int> get missingSurahs => switch (source) {
        SurahFiles(:final missing) => missing,
        _ => const {},
      };
}

/// One reciter's recording of a contiguous ayah range of one surah,
/// resolved to a local file. [timings] are exact for that exact file —
/// the two always travel together, whether bundled, built on-device
/// from per-ayah parts, or cut out of a whole-surah file.
///
/// The file may hold the whole surah or just the range a reel needs;
/// always look windows up by ayah number via [timing], never by list
/// index.
@immutable
class Recitation {
  final String reciterId;
  final int surah;

  /// Absolute path of the audio on device.
  final String audioPath;

  /// Contiguous, ascending by ayah number.
  final List<AyahTiming> timings;

  /// Where this recording's first moment sits in the voice's whole-surah
  /// file, in milliseconds, when it was cut out of one — what puts times
  /// taken against that file (QUL's words) on this recording exactly.
  /// Null for one assembled from per-ayah files, or cut by a build that
  /// did not keep it.
  final int? originMs;

  const Recitation({
    required this.reciterId,
    required this.surah,
    required this.audioPath,
    required this.timings,
    this.originMs,
  });

  int get firstAyah => timings.first.ayah;
  int get lastAyah => timings.last.ayah;

  bool covers(int startAyah, int endAyah) =>
      firstAyah <= startAyah && endAyah <= lastAyah;

  /// Window of [ayah] inside this recording. The list is contiguous,
  /// so this is a direct index — but by ayah number, valid for range
  /// files too.
  AyahTiming timing(int ayah) {
    assert(covers(ayah, ayah), 'ayah $ayah outside $firstAyah..$lastAyah');
    return timings[ayah - firstAyah];
  }

  /// Whether the recording opens on the basmala, before its verse 1: a
  /// window numbered 0 at its head (see `RecitationService.withBasmala`).
  bool get opensWithBasmala => timings.isNotEmpty && timings.first.ayah == 0;

  /// Where a reel of [startAyah] onward starts in this recording: at the
  /// basmala when it opens a surah on verse 1 and the recording carries
  /// one, else at the verse itself.
  int startOf(int startAyah) => startAyah == 1 && opensWithBasmala
      ? timings.first.startMs
      : timing(startAyah).startMs;
}

@immutable
class ReelBackground {
  final String id;
  final String name;

  /// 9:16 looping mp4 bundled at assets/backgrounds/<id>.mp4.
  /// Empty for still-image and user-picked backgrounds.
  final String videoAsset;

  /// 9:16 still bundled at assets/backgrounds/<id>.jpg. Empty for video
  /// and user-picked backgrounds. Stills cost a fraction of a video's
  /// size, so the scenery library can be wide without bloating the app.
  final String imageAsset;

  /// Absolute path of a photo/video the user picked from their device;
  /// null for bundled backgrounds.
  final String? filePath;

  /// Whether [filePath] points at a still image (vs a video).
  final bool fileIsImage;

  /// Poster gradient shown before the asset loads and in picker cards.
  final List<int> gradientArgb;

  const ReelBackground({
    required this.id,
    required this.name,
    required this.videoAsset,
    required this.gradientArgb,
    this.knownAspect = 1080 / 1920,
  })  : imageAsset = '',
        filePath = null,
        fileIsImage = false;

  /// A bundled still photograph.
  const ReelBackground.still({
    required this.id,
    required this.name,
    required this.imageAsset,
    required this.gradientArgb,
    this.knownAspect = 1080 / 1920,
  })  : videoAsset = '',
        filePath = null,
        fileIsImage = false;

  /// A background sourced from the user's gallery.
  const ReelBackground.deviceFile({
    required this.id,
    required this.name,
    required this.filePath,
    required this.fileIsImage,
  })  : videoAsset = '',
        imageAsset = '',
        knownAspect = null,
        gradientArgb = const [0xFF101418, 0xFF2A313B];

  /// A scenery downloaded from the catalog and cached on disk.
  ///
  /// It reads as a file background — the renderer and the preview take
  /// the same path they take for a picked photo — but unlike a picked
  /// file everything about it is already known: its poster gradient was
  /// measured when the library was built, and its shape is fixed by the
  /// bucket it came from, so nothing has to be probed at runtime.
  const ReelBackground.cached({
    required this.id,
    required this.name,
    required this.filePath,
    required this.fileIsImage,
    required this.gradientArgb,
    required this.knownAspect,
  })  : videoAsset = '',
        imageAsset = '';

  /// Displayed width/height when it is known without probing: every
  /// catalog scenery is authored either 1080x1920 or 1920x1080. Null
  /// for user-picked files, which have to be measured.
  final double? knownAspect;

  bool get isDeviceFile => filePath != null;

  /// A file the user brought in themselves, rather than a scenery from
  /// the app's own library.
  ///
  /// The catalog reaches the renderer as a file too once it has been
  /// downloaded, which makes [isDeviceFile] the wrong question for
  /// anything that cares where a scenery came from. Every catalog
  /// scene is authored by the app — fixed shape, seamless loop — and
  /// carries [knownAspect] to prove it; only a photo or clip out of
  /// the user's gallery arrives with nothing known about it.
  bool get isUserFile => isDeviceFile && knownAspect == null;

  /// True when this background is a still (bundled photo or picked
  /// photo) — the renderer loops it as an image, the UI shows it with
  /// no video decoder.
  bool get isImage => isDeviceFile ? fileIsImage : imageAsset.isNotEmpty;

  /// The bundled asset backing this background, whichever kind it is.
  /// Empty for device files.
  String get assetPath => imageAsset.isNotEmpty ? imageAsset : videoAsset;
}
