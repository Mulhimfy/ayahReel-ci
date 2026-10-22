import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'debug_log.dart';
import 'models.dart';
import 'qul_words.dart';
import 'recitation_service.dart' show LiveClip;
import 'verse_lines.dart' show VerseText;

/// Word-precise timing data from the quran-align project
/// (github.com/cpfair/quran-align, CC BY 4.0): word timestamps computed
/// against the exact EveryAyah recordings this app plays, with word
/// indices into the same Tanzil Uthmani text it displays. Both the
/// audio files and the text match ours, so the highlight is accurate
/// by construction — no per-reciter guessing.
///
/// Only reciters whose EveryAyah recording has a released alignment
/// file get word highlighting; everyone else keeps the whole-ayah card.
/// Every downloaded file is SHA-1-verified against the release README
/// before it is ever used.
///
/// **What "has a file" means.** The release aligned twelve EveryAyah
/// folders. Nine are folders this app plays as-is. Two more are the
/// *same recording* served at a lower bitrate — `Husary_64kbps` is the
/// murattal Husary this app plays from `Husary_128kbps`, and
/// `Abdul_Basit_Murattal_64kbps` is the `_192kbps` set — which was
/// checked, not assumed: ffprobe over a dozen ayahs spread across the
/// mushaf finds every pair of files a constant 70ms apart (the two
/// encoders' padding), never a different length. Word windows run
/// hundreds of milliseconds and are gap-filled, so a 70ms shift is not
/// visible; a different recording would have been off by seconds. The
/// twelfth, `Husary_Muallim_128kbps`, is a genuinely different reading
/// (Husary's teaching recitation, verse-by-verse with pauses), and its
/// files are up to a minute longer than the murattal ones — so it is
/// not, and must never be, mapped onto the murattal voice.
///
/// **What was not taken.** The Quranic Universal Library publishes
/// word segments for many more reciters, but against its own gapless
/// surah-by-surah recordings, whose verse offsets are not those of the
/// per-ayah files this app assembles. Those timings do not transfer,
/// and highlighting a word a second late is worse than not
/// highlighting it.
abstract final class WordAlignService {
  static const _zipUrl =
      'https://github.com/cpfair/quran-align/releases/download/'
      'release-2016-11-24/quran-align-data-2016-11-24.zip';

  /// Alignment file -> SHA-1 of `<file>.json` inside the release zip
  /// (hashes published in the release README and re-verified locally
  /// before shipping this table). Keyed by the *alignment's* folder,
  /// which for two reciters is not the folder the app plays — see
  /// [_alignFolderFor].
  static const _sha1ByFolder = <String, String>{
    'Alafasy_128kbps': '167bfc53255152aaf8c9a2e5e79c1160134c77a4',
    // Same recordings as the app's Husary_128kbps and
    // Abdul_Basit_Murattal_192kbps; see the class doc for the check.
    'Husary_64kbps': '8e7a24f66f98f176dfddf65b434643a6655c694d',
    'Abdul_Basit_Murattal_64kbps': '029e32d2cdc869e2f33ae86fd21214952d18f33d',
    'Minshawy_Murattal_128kbps': '2a24d42e7f3a018c56600fc4ddd580f214b20a39',
    'Minshawy_Mujawwad_192kbps': 'da6c3850917c6e104e650a07542a6c7341539af5',
    'Abdurrahmaan_As-Sudais_192kbps':
        '4315194bc88db14192201426fb4f6617bffac4ac',
    'Saood_ash-Shuraym_128kbps': '59fd80d144caa6fe79a917a8d1dddf18087b3bcc',
    'Abu_Bakr_Ash-Shaatree_128kbps':
        '8861fadb68bad84ae5189227e0bcdd7a7127e976',
    'Hani_Rifai_192kbps': '22e0cea40ff434848295f8ce959ab885292ebb7b',
    'Mohammad_al_Tablaway_128kbps':
        'dce92289eebd76380d1dae22f2329493a49f06db',
    'Abdul_Basit_Mujawwad_128kbps':
        'd0c5d63917c0a2d59f0d86ce27936251b6d76f90',
  };

  /// The app's folder -> the folder the release aligned, where the two
  /// differ. Only the bitrate differs between each pair; the audio is
  /// the same recording (class doc).
  static const _alignFolderByAppFolder = <String, String>{
    'Husary_128kbps': 'Husary_64kbps',
    'Abdul_Basit_Murattal_192kbps': 'Abdul_Basit_Murattal_64kbps',
  };

  /// The alignment file that matches [r]'s recording, or null when the
  /// release has none for it.
  static String? _alignFolderFor(Reciter r) {
    final app = r.everyAyahFolder;
    if (app == null) return null;
    final f = _alignFolderByAppFolder[app] ?? app;
    return _sha1ByFolder.containsKey(f) ? f : null;
  }

  /// Whether [r] has word timing: quran-align's, or the Quranic
  /// Universal Library's for a voice verified to be its recording (see
  /// [QulWords]).
  static bool supports(Reciter r) =>
      _alignFolderFor(r) != null || QulWords.supports(r);

  /// Whether quran-align's own release times [r]: tests keep it apart
  /// from the voices QUL times, and the offline download fetches its one
  /// file for such a voice.
  static bool alignedByQuranAlign(Reciter r) => _alignFolderFor(r) != null;

  /// The release's file that times [r], or null — for tests, which hold
  /// every recording of a voice to its own timing.
  @visibleForTesting
  static String? alignFolderOf(Reciter r) => _alignFolderFor(r);

  /// How many of [all] carry word timings — for tests, which pin the
  /// count so a table edit cannot silently drop a voice.
  static int supportedCount(Iterable<Reciter> all) =>
      all.where(supports).length;

  /// One reciter's parsed data kept in memory (users rarely switch
  /// voices mid-session; a second reciter just re-parses its file).
  static String? _loadedFolder;
  static Map<int, Map<int, List<WordSpan>>>? _loadedData;

  static Future<void>? _fetchInFlight;

  /// Word spans for one surah of one reciter, keyed by ayah number and
  /// relative to each ayah's start in the recording. Null when the
  /// reciter has no alignment data or it couldn't be fetched — callers
  /// fall back to the whole-ayah card, never an error.
  ///
  /// A voice timed by QUL is timed against QUL's files, and its words are
  /// placed on the app's own recording: [recitation] is that recording,
  /// and [ayahs] the surah's text the words are counted in. Without both
  /// such a voice has none; with them, only the verses of [recitation]
  /// whose words could be placed are in the answer.
  static Future<Map<int, List<WordSpan>>?> load(Reciter reciter, int surah,
      {Recitation? recitation, List<Ayah>? ayahs}) async {
    if (QulWords.supports(reciter)) {
      if (recitation == null || ayahs == null) return null;
      try {
        final placed = await QulWords.forRecitation(reciter, recitation);
        if (placed == null) return null;
        final out = <int, List<WordSpan>>{};
        for (final e in placed.entries) {
          if (e.key < 1 || e.key > ayahs.length) continue;
          final spans = fromMushafWords(ayahs[e.key - 1].arabic, e.value);
          if (spans != null && spans.isNotEmpty) out[e.key] = spans;
        }
        rlog('align: ${reciter.id} words placed on ${out.length} of '
            '${recitation.timings.length} verses');
        return out.isEmpty ? null : out;
      } catch (e) {
        rlog('align: qul words for ${reciter.id} failed ($e)');
        return null;
      }
    }
    final folder = _alignFolderFor(reciter);
    if (folder == null) return null;
    try {
      if (_loadedFolder != folder) {
        final file = await _ensureFile(folder);
        if (file == null) return null;
        // Read and parsed off the UI isolate: an alignment file is
        // megabytes of JSON, and decoding it on the main thread froze
        // the preview for the better part of a second right as it was
        // starting to play.
        final path = file.path;
        final Map<int, Map<int, List<WordSpan>>> parsed;
        try {
          parsed = await Isolate.run(
              () => parseAlignJson(File(path).readAsStringSync()));
        } on FormatException {
          // A file cut short (an older build wrote it in place) fails
          // here on every launch: drop it so the next load fetches it
          // again.
          try {
            file.deleteSync();
          } catch (_) {}
          rethrow;
        }
        _loadedFolder = folder;
        _loadedData = parsed;
      }
      return _loadedData![surah];
    } catch (e) {
      rlog('align: load failed for $folder ($e)');
      return null;
    }
  }

  /// surah -> ayah -> spans, sorted by start time.
  ///
  /// The canonical release files carry two quirks (SHA-1-verified, so
  /// this is how they shipped in 2016): the Sudais file has the align
  /// tool's crash log dumped BEFORE the JSON array, and a couple of
  /// files have entries with `"segments": null` where an ayah failed to
  /// segment. Both are tolerated — a bad entry costs one ayah its
  /// highlight, never the whole reciter.
  @visibleForTesting
  static Map<int, Map<int, List<WordSpan>>> parseAlignJson(String json) {
    final arrayStart = json.indexOf('[{');
    if (arrayStart < 0) throw const FormatException('no JSON array found');
    final raw = jsonDecode(json.substring(arrayStart)) as List;
    final out = <int, Map<int, List<WordSpan>>>{};
    for (final e in raw.cast<Map<String, dynamic>>()) {
      final segsRaw = e['segments'] as List?;
      if (segsRaw == null) continue;
      final segs = segsRaw
          .cast<List>()
          .map((s) => WordSpan(
              s[0] as int, s[1] as int, s[2] as int, s[3] as int))
          .toList()
        ..sort((a, b) => a.startMs.compareTo(b.startMs));
      if (segs.isEmpty) continue;
      out.putIfAbsent(e['surah'] as int, () => {})[e['ayah'] as int] = segs;
    }
    return out;
  }

  /// Downloads the release zip once, extracts every supported reciter's
  /// file, and verifies each SHA-1. Returns null (not throws) when the
  /// file can't be produced — highlighting just stays off.
  static Future<File?> _ensureFile(String folder) async {
    final dir = Directory(
        '${(await getApplicationSupportDirectory()).path}/word_align');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final target = File('${dir.path}/$folder.json');
    if (target.existsSync() && target.lengthSync() > 0) return target;

    // One download serves all reciters; coalesce concurrent callers.
    final fetch = _fetchInFlight ??= _fetchAndExtract(dir);
    try {
      await fetch;
    } finally {
      _fetchInFlight = null;
    }
    return target.existsSync() && target.lengthSync() > 0 ? target : null;
  }

  static Future<void> _fetchAndExtract(Directory dir) async {
    rlog('align: downloading timing data');
    final res = await http
        .get(Uri.parse(_zipUrl))
        .timeout(const Duration(minutes: 3));
    if (res.statusCode != 200 || res.bodyBytes.isEmpty) {
      throw Exception('align data download failed (HTTP ${res.statusCode})');
    }
    // Inflated and hashed on a worker isolate. The release zip is tens
    // of megabytes and every verified file is hashed in full; done on
    // the UI isolate that was several seconds with no frame drawn —
    // long enough for Android to offer to kill the app — on the first
    // preview of any voice that has word timings.
    final bytes = res.bodyBytes;
    final dirPath = dir.path;
    final result = await Isolate.run(() => _extractVerified(bytes, dirPath));
    for (final name in result.rejected) {
      // Never use unverified timing data — a corrupt or tampered
      // file would silently desync the highlight.
      rlog('align: SHA-1 MISMATCH for $name — skipped');
    }
    rlog('align: extracted ${result.extracted} verified files');
  }

  /// Runs on a worker isolate: pure computation and file writes only.
  static ({int extracted, List<String> rejected}) _extractVerified(
      Uint8List zip, String dirPath) {
    final archive = ZipDecoder().decodeBytes(zip);
    var extracted = 0;
    final rejected = <String>[];
    for (final entry in archive.files) {
      if (!entry.isFile) continue;
      final folder = entry.name.endsWith('.json')
          ? entry.name.substring(0, entry.name.length - 5)
          : '';
      final expected = _sha1ByFolder[folder];
      if (expected == null) continue;
      final bytes = entry.content as List<int>;
      final digest = sha1.convert(bytes).toString();
      if (digest != expected) {
        rejected.add(entry.name);
        continue;
      }
      // Beside the real name, then renamed: a kill mid-write must not
      // leave a partial file that [_ensureFile] trusts from then on.
      final tmp = File('$dirPath/${entry.name}.tmp')
        ..writeAsBytesSync(bytes, flush: true);
      tmp.renameSync('$dirPath/${entry.name}');
      extracted++;
    }
    return (extracted: extracted, rejected: rejected);
  }

  // ---- text mapping -----------------------------------------------------

  /// Whether a space-split token carries at least one Arabic letter.
  /// alquran.cloud's Uthmani text serves waqf (pause) marks as their own
  /// space-separated tokens; quran-align's word indices do not count
  /// them, so they must be skipped when mapping indices to the display
  /// text (a mark rides along with the word before it).
  static bool _isLetterToken(String token) {
    for (final r in token.runes) {
      if ((r >= 0x0621 && r <= 0x064A) ||
          (r >= 0x066E && r <= 0x06D3) ||
          r == 0x06D5) {
        return true;
      }
    }
    return false;
  }

  /// The one place the displayed text splits a word that quran-align
  /// counts as one.
  ///
  /// The alignment indices were computed against Tanzil, which writes
  /// `بَعْدَمَا` joined; the mushaf writes it `بَعْدَ مَا`. It happens in three
  /// ayahs — 2:181, 8:6 and 13:37 — and left alone it would not fail
  /// the fit check below, it would quietly light the word *after* the
  /// intended one for the rest of the verse. So the pair is counted as
  /// the single align word it is.
  ///
  /// Matched exactly, on the fatha: `بَعْدِ مَا` is a different phrase that
  /// stands as two words 27 times over and must not be merged.
  static const _badaFatha = 'بَعْدَ';
  static const _maa = 'مَا';

  /// One verse's word spans in a clip of the verse picker's listen,
  /// counted from the verse's window in the clip's file — for a voice
  /// timed by QUL, whose words are placed clip by clip as the listen
  /// fetches them. Null for any other voice, which [load] answers for a
  /// whole surah at once.
  static Future<List<WordSpan>?> loadClip(
      Reciter reciter, int surah, LiveClip clip, List<Ayah> ayahs) async {
    if (!QulWords.supports(reciter) || clip.ayah > ayahs.length) return null;
    try {
      final placed = await QulWords.forClip(reciter, surah, clip);
      if (placed == null) return null;
      return fromMushafWords(ayahs[clip.ayah - 1].arabic, placed);
    } catch (e) {
      rlog('align: qul words for ${reciter.id} $surah:${clip.ayah} '
          'failed ($e)');
      return null;
    }
  }

  /// For each letter-bearing token of [arabic], in order, the alignment
  /// word it is part of: its own, but for the مَا that rides with
  /// بَعْدَ (see [_badaFatha]). What a word count of the mushaf's own —
  /// QUL's, which prints بَعْدَ مَا as two — is turned into before
  /// [displayRange] reads it.
  static List<int> alignWords(String arabic) {
    final tokens = arabic.split(' ');
    final out = <int>[];
    var w = 0;
    for (var i = 0; i < tokens.length; i++) {
      if (!_isLetterToken(tokens[i])) continue;
      out.add(w);
      if (tokens[i] == _badaFatha &&
          i + 1 < tokens.length &&
          tokens[i + 1] == _maa) {
        out.add(w);
        i++;
      }
      w++;
    }
    return out;
  }

  /// A verse's words as QUL counts them — [placed]'s (position from 1,
  /// start, end), out of its count of them — as the alignment spans the
  /// rest of the app reads.
  ///
  /// QUL counts the words as the mushaf prints them, so one of its words
  /// is one of the text's — except where a recitation counts a pair the
  /// text keeps apart as one: بَعْدَ مَا (2:181, 8:6, 13:37, in some) or
  /// إِلْ يَاسِينَ (37:130, in most). A count one short, with such a pair
  /// in the verse, is read that way. Any other count means QUL timed
  /// another text, and no word of it can be trusted to light the right
  /// one: null.
  static List<WordSpan>? fromMushafWords(String arabic, Placed placed) {
    final tokens = arabic.split(' ');
    final letters = [
      for (var i = 0; i < tokens.length; i++)
        if (_isLetterToken(tokens[i])) i,
    ];
    final align = alignWords(arabic);
    // Each QUL position: the letter-bearing tokens it is, [from, to).
    final List<(int, int)> byPosition;
    if (placed.count == letters.length) {
      byPosition = [for (var k = 0; k < letters.length; k++) (k, k + 1)];
    } else if (placed.count == letters.length - 1) {
      final j = _joinedPair(tokens, letters);
      if (j == null) return null;
      byPosition = [
        for (var k = 0; k < letters.length; k++)
          if (k != j + 1) (k, k == j ? k + 2 : k + 1),
      ];
    } else {
      return null;
    }
    final out = <WordSpan>[];
    for (final (p, s, e) in placed.words) {
      if (p < 1 || p > byPosition.length) return null;
      final (k0, k1) = byPosition[p - 1];
      final a0 = align[k0];
      final a1 = align[k1 - 1] + 1;
      if (out.isNotEmpty &&
          out.last.startWord == a0 &&
          out.last.endWord == a1) {
        // The second half of one alignment word: its end is the word's.
        final last = out.removeLast();
        out.add(WordSpan(a0, a1, last.startMs, e));
      } else {
        out.add(WordSpan(a0, a1, s, e));
      }
    }
    return out;
  }

  /// Where in [letters] (the letter-bearing tokens' indices) a pair
  /// begins that a recitation may count as one word, or null.
  static int? _joinedPair(List<String> tokens, List<int> letters) {
    for (var k = 0; k + 1 < letters.length; k++) {
      final a = tokens[letters[k]];
      final b = tokens[letters[k + 1]];
      if (letters[k + 1] != letters[k] + 1) continue;
      if (a == _badaFatha && b == _maa) return k;
      if (VerseText.bare(a) == 'ال' && VerseText.bare(b) == 'ياسين') {
        return k;
      }
    }
    return null;
  }

  /// Maps an align-word range onto display-token indices of [arabic]
  /// (split on spaces). Trailing marks attach to the preceding word.
  /// Null when the align indices don't fit the text — the caller drops
  /// the span rather than highlight the wrong word.
  @visibleForTesting
  static ({int start, int end})? displayRange(
      String arabic, int startWord, int endWord) {
    if (startWord < 0 || endWord <= startWord) return null;
    final tokens = arabic.split(' ');
    final letterAt = <int>[];
    for (var i = 0; i < tokens.length; i++) {
      if (!_isLetterToken(tokens[i])) continue;
      letterAt.add(i);
      if (tokens[i] == _badaFatha &&
          i + 1 < tokens.length &&
          tokens[i + 1] == _maa) {
        i++; // the مَا rides along with بَعْدَ, as one align word
      }
    }
    if (endWord > letterAt.length) return null;
    final start = letterAt[startWord];
    final end = endWord < letterAt.length ? letterAt[endWord] : tokens.length;
    return (start: start, end: end);
  }

  /// Each display token's recited window in [arabic], in ms from the
  /// verse's start, from its raw alignment [spans] — the real end of
  /// each word rather than the gap-filled windows the highlight uses —
  /// and the places inside an aligned group of several words, where a
  /// verse may not be cut: nobody knows where in the group one word
  /// ends. A pause sign takes its word's window.
  static ({List<(int, int)?> times, Set<int> held}) tokenWindows(
      String arabic, List<WordSpan> spans) {
    final n = arabic.split(' ').length;
    final times = List<(int, int)?>.filled(n, null);
    final held = <int>{};
    for (final s in spans) {
      final r = displayRange(arabic, s.startWord, s.endWord);
      if (r == null || s.endMs <= s.startMs) continue;
      // The first time a word is recited: a reciter who takes words
      // again after a breath has already reached them, and the thread,
      // the light and the line's change go by where they were reached.
      for (var k = r.start; k < r.end && k < n; k++) {
        times[k] ??= (s.startMs, s.endMs);
      }
      for (var k = r.start + 1; k < r.end; k++) {
        held.add(k);
      }
    }
    return (times: times, held: held);
  }

  /// Turns raw spans into per-ayah highlight windows for the selected
  /// range, ready for both live preview and export:
  ///  - windows are gap-filled (a word stays lit through pauses) and
  ///    clamped to the ayah's measured duration,
  ///  - word indices are mapped to display tokens, dropping any span
  ///    that doesn't fit the text (fail-safe: never highlight wrongly),
  ///  - returns null when the whole selection has no usable spans or
  ///    would exceed [maxOverlays] FFmpeg inputs (the export and the
  ///    preview must agree, so the cap is decided here, once).
  static Map<int, List<HighlightSpan>>? highlightPlan({
    required Recitation recitation,
    required List<Ayah> ayahs,
    required Map<int, List<WordSpan>> spansByAyah,
    required int startAyah,
    required int endAyah,
    int maxOverlays = 120,
  }) {
    final plan = <int, List<HighlightSpan>>{};
    var overlays = 0;
    for (var a = startAyah; a <= endAyah; a++) {
      overlays++; // the base card
      final raw = spansByAyah[a];
      if (raw == null || raw.isEmpty) continue;
      final ayahMs = recitation.timing(a).durationMs;
      final text = ayahs[a - 1].arabic;
      // The spans that fit the text, first: a dropped one must not leave
      // a hole. The export draws the verse only through its windows, so
      // a gap between two was a stretch of the reel with no verse on it.
      final kept = <(WordSpan, ({int start, int end}))>[];
      for (final s in raw) {
        final range = displayRange(text, s.startWord, s.endWord);
        if (range != null) kept.add((s, range));
      }
      final windows = <HighlightSpan>[];
      for (var i = 0; i < kept.length; i++) {
        final (s, range) = kept[i];
        final start = s.startMs.clamp(0, ayahMs);
        // Fill the gap to the next span: the highlight holds through
        // the reciter's breath instead of flickering off.
        final end = (i + 1 < kept.length ? kept[i + 1].$1.startMs : ayahMs)
            .clamp(0, ayahMs);
        if (end <= start) continue;
        windows.add(HighlightSpan(start, end, range.start, range.end));
      }
      if (windows.isNotEmpty) {
        plan[a] = windows;
        overlays += windows.length;
      }
    }
    if (plan.isEmpty) return null;
    if (overlays > maxOverlays) {
      rlog('align: $overlays overlays exceed cap $maxOverlays — '
          'highlight off for this selection');
      return null;
    }
    return plan;
  }
}
