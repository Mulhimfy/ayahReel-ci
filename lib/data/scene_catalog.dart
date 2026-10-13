import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'debug_log.dart';
import 'models.dart';

/// One scenery in the library.
///
/// Every scene ships a poster inside the app; only the full-size file
/// may have to travel. That is what lets the picker show all of them at
/// once, offline, on a cold install.
class Scene {
  final String id;

  /// Picker tab this belongs to — `sky`, `sacred`, `aerial`, …
  final String tab;

  /// Wide (1920x1080) rather than portrait. Wide scenes are letterboxed
  /// into the reel with the verse below them instead of over them.
  final bool wide;

  final bool isVideo;
  final String ext;
  final int bytes;

  /// Measured top/bottom average of the scene itself. Shown under the
  /// poster while it decodes, behind a download, and as the reel's
  /// thumbnail in My Reels.
  final List<int> gradientArgb;

  /// Shipped inside the app: usable with no network, ever.
  final bool bundled;

  const Scene({
    required this.id,
    required this.tab,
    required this.wide,
    required this.isVideo,
    required this.ext,
    required this.bytes,
    required this.gradientArgb,
    required this.bundled,
  });

  factory Scene.fromJson(Map<String, dynamic> j) => Scene(
        id: j['id'] as String,
        tab: j['tab'] as String,
        wide: j['wide'] as bool? ?? false,
        isVideo: j['video'] as bool? ?? false,
        ext: j['ext'] as String? ?? 'jpg',
        bytes: j['bytes'] as int? ?? 0,
        gradientArgb: (j['grad'] as List).cast<int>(),
        bundled: j['bundled'] as bool? ?? false,
      );

  String get thumbAsset => 'assets/scene_thumbs/$id.jpg';
  String get bundledAsset => 'assets/backgrounds/$id.$ext';
  String get fileName => '$id.$ext';

  double get aspect => wide ? 1920 / 1080 : 1080 / 1920;

  /// Prettified id: `aerial_coast_pexels_03` -> `Aerial coast`. The
  /// source and index are provenance, not something to read on a tile.
  String get label {
    final parts = id.split('_');
    final end = parts.lastIndexWhere(
        (p) => !RegExp(r'^\d+$').hasMatch(p) && !_sources.contains(p));
    final words = parts.sublist(0, end < 0 ? parts.length : end + 1);
    if (words.isEmpty) return id;
    final s = words.join(' ');
    return s[0].toUpperCase() + s.substring(1);
  }

  /// The id without its provenance: `aerial_coast_pexels_03` ->
  /// `aerial_coast`, `sky_pixabay_01` -> `sky`. What the picture is of,
  /// which is what the verse matcher chooses by.
  String get family {
    final parts = id.split('_');
    final end = parts.lastIndexWhere(
        (p) => !RegExp(r'^\d+$').hasMatch(p) && !_sources.contains(p));
    return end < 0 ? id : parts.sublist(0, end + 1).join('_');
  }

  static const _sources = {
    'pexels', 'pixabay', 'commons', 'openverse', 'wallhaven', 'mixkit',
    'pinterest',
  };
}

/// The scenery library: a bundled catalog of every scene, the files for
/// a starter set, and on-demand fetching for the rest.
///
/// Downloads land in the app support directory and stay there, so a
/// scene is fetched at most once per install. Nothing here ever throws
/// at the UI: a failed download leaves the scene un-downloaded and the
/// caller shows the poster it was already showing.
abstract final class SceneCatalog {
  static List<Scene> _all = const [];
  static String _baseUrl = '';
  static final Map<String, List<Scene>> _byTab = {};
  static bool _loaded = false;

  /// Tabs in the order the picker shows them. Portrait tabs first — the
  /// verse-on-top format is the default one — then the wide ones.
  static const tabOrder = <String>[
    'sky', 'mountains', 'desert', 'water', 'forest', 'road', 'sacred',
    'abstract', 'aerial', 'cinematic',
  ];

  /// Scenes withdrawn from the library, by id.
  ///
  /// `catalog.json` is an asset, and assets never travel in a Shorebird
  /// patch — editing one needs a store build and the review wait that
  /// comes with it. This filter is Dart, so a scene that has to go can go
  /// over the air, on the launch after the patch lands, and the real
  /// deletion follows in the next store build.
  ///
  /// **Ids stay here after their assets are deleted.** Once the entry is
  /// gone from `catalog.json` this looks like dead code, and for anyone
  /// on that build it is. But a patch carries only Dart: one cut against
  /// an older release lands on devices whose bundled catalog still lists
  /// the scene, and with the id gone from this set that patch would put
  /// it back — on exactly the users who never got the store build. One
  /// string is cheap next to a resurrection nobody would think to test
  /// for. Only drop an id once no release still listing it can be
  /// patched.
  ///
  /// - `sacred_pexels_15`: filed under sacred but it is a street scene —
  ///   traffic, parked cars, and a woman walking across the foreground.
  ///   Wrong backdrop for a verse. Hidden by patch on 2026-08-11, assets
  ///   deleted in the build after it.
  /// - `sacred_pixabay_03`: the lit minaret at night. The lower quarter of
  ///   the photo is solid black — it is in the source file, not anything
  ///   the app draws — so the verse sits over a dark blank slab. Withdrawn
  ///   and its assets deleted on 2026-09-04.
  /// - `cinematic_pixabay_24`: a rainbow fantasy valley with glowing
  ///   spires and figures walking into it. Plainly AI-generated, and it
  ///   looks it next to the photographs around it. Withdrawn and its
  ///   assets deleted on 2026-09-28.
  static const withdrawn = <String>{
    'sacred_pexels_15',
    'sacred_pixabay_03',
    'cinematic_pixabay_24',
  };

  static List<Scene> get all => _all;

  static List<String> get tabs =>
      tabOrder.where((t) => (_byTab[t] ?? const []).isNotEmpty).toList();

  /// The tabs holding one shape of scenery. Every tab is authored at a
  /// single shape — a tab of mixed ones would break the grid, which
  /// lays out two-up or three-up on the same answer — so the first
  /// scene speaks for all of them.
  ///
  /// The picker shows one family at a time: a 16:9 scenery only reads
  /// as intended inside the letterbox card, and an upright one only
  /// outside it, so the frame the user chose decides which family they
  /// are looking at.
  static List<String> tabsFor({required bool wide}) => tabs
      .where((t) => _byTab[t]!.first.wide == wide)
      .toList();

  static List<Scene> inTab(String tab) => _byTab[tab] ?? const [];

  /// The sceneries a tab opens on, best first, ahead of the rest in the
  /// catalogue's own order.
  ///
  /// The catalogue is in the order its sources were gathered, and in
  /// three tabs that put the weakest pictures on the first screen —
  /// dim auroras and a blank sky at the top of Sky, a railway line and
  /// rooftops at the top of Aerial — with the ones people want buried
  /// a hundred tiles down. Chosen by eye, from the thumbnails, on
  /// 2026-10-11. Dart rather than catalog.json, so a later reorder can
  /// travel in a patch. An id that leaves the catalogue is skipped.
  @visibleForTesting
  static const leaders = <String, List<String>>{
    'sky': [
      'aurora_pixabay_02', 'sky_pexels_55', 'clouds_pexels_10',
      'clouds_openverse_01', 'aurora_pexels_17', 'clouds_pixabay_01',
      'clouds_pixabay_04', 'sky_pexels_21', 'clouds_commons_01',
      'sky_pexels_47', 'clouds_pixabay_02', 'aurora_pexels_16',
      'clouds_pixabay_03', 'sky_pexels_28', 'clouds_pixabay_05',
      'sky_pexels_49', 'aurora_pexels_09', 'sky_pexels_31',
      'clouds_pixabay_06', 'aurora_pexels_13', 'sky_pexels_50',
      'sky_pexels_23', 'clouds_pexels_13', 'clouds_pexels_05',
      'sky_pixabay_02', 'sky_pexels_15', 'sky_pexels_19',
      'clouds_pexels_07', 'clouds_pexels_12', 'aurora_openverse_01',
    ],
    'aerial': [
      'aerial_desert_pixabay_02', 'aerial_mountain_pexels_04', 'aerial_land_pexels_04',
      'aerial_water_pixabay_04', 'aerial_land_pixabay_07', 'aerial_desert_pixabay_03',
      'aerial_land_pixabay_01', 'aerial_coast_pexels_05', 'aerial_forest_pexels_01',
      'aerial_water_pixabay_07', 'aerial_desert_pexels_01', 'aerial_water_pexels_01',
      'aerial_desert_pexels_04', 'aerial_coast_pixabay_01', 'aerial_water_pixabay_05',
      'aerial_coast_pexels_04', 'aerial_land_pixabay_06', 'aerial_land_pixabay_05',
      'aerial_forest_pexels_12', 'aerial_water_pexels_04', 'aerial_water_pixabay_03',
      'aerial_mountain_pexels_06', 'aerial_coast_pexels_02', 'aerial_land_pixabay_10',
      'aerial_mountain_pexels_16', 'aerial_mountain_pixabay_06', 'aerial_mountain_pixabay_05',
      'aerial_forest_pexels_11',
    ],
    'cinematic': [
      'cinematic_pixabay_06', 'cinematic_pixabay_07', 'cinematic_pexels_02',
      'cinematic_commons_06', 'cinematic_pixabay_29', 'cinematic_pixabay_31',
      'cinematic_pixabay_26', 'cinematic_pixabay_14', 'cinematic_pixabay_01',
      'cinematic_pexels_27', 'cinematic_pixabay_19', 'cinematic_pixabay_18',
      'cinematic_pixabay_30', 'cinematic_commons_08', 'cinematic_pexels_16',
      'cinematic_pexels_18', 'cinematic_pexels_14', 'cinematic_pixabay_15',
      'cinematic_pixabay_22', 'cinematic_pexels_09', 'cinematic_pixabay_08',
      'cinematic_pixabay_11', 'cinematic_pexels_23', 'cinematic_pixabay_34',
      'cinematic_commons_05', 'cinematic_mixkit_13', 'cinematic_pexels_28',
      'cinematic_pexels_24', 'cinematic_openverse_02',
    ],
  };

  /// [scenes] with the tab's [leaders] first, in their order.
  @visibleForTesting
  static List<Scene> leadersFirst(String tab, List<Scene> scenes) {
    final lead = leaders[tab];
    if (lead == null) return scenes;
    final byId = {for (final s in scenes) s.id: s};
    final first = [
      for (final id in lead)
        if (byId[id] != null) byId[id]!,
    ];
    final taken = {for (final s in first) s.id};
    return [...first, ...scenes.where((s) => !taken.contains(s.id))];
  }

  static Scene? byId(String id) {
    for (final s in _all) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Completes once [load] has run, however it went. Awaiting this
  /// does not start a load: a widget that wants the catalog if the app
  /// has read it — the opening frame — waits here, and under a test
  /// that never reads it, waits for good without spawning the decode
  /// isolate a dangling [load] would leave behind.
  static Future<void> get ready => _ready.future;
  static final _ready = Completer<void>();

  static Future<void> load() async {
    if (_loaded) {
      if (!_ready.isCompleted) _ready.complete();
      return;
    }
    try {
      final raw = await rootBundle.loadString('assets/catalog.json');
      final j = jsonDecode(raw) as Map<String, dynamic>;
      _baseUrl = j['baseUrl'] as String? ?? '';
      _all = (j['scenes'] as List)
          .map((e) => Scene.fromJson(e as Map<String, dynamic>))
          .where((s) => !withdrawn.contains(s.id))
          .toList(growable: false);
      _byTab.clear();
      for (final s in _all) {
        (_byTab[s.tab] ??= []).add(s);
      }
      for (final tab in leaders.keys) {
        final scenes = _byTab[tab];
        if (scenes != null) _byTab[tab] = leadersFirst(tab, scenes);
      }
      _loaded = true;
      rlog('catalog: ${_all.length} scenes, '
          '${_all.where((s) => s.bundled).length} bundled');
    } catch (e) {
      rlog('catalog: load failed $e');
      _all = const [];
      _loaded = true; // a broken catalog is not worth retrying every build
    }
    if (!_ready.isCompleted) _ready.complete();
  }

  // ── cache ─────────────────────────────────────────────────────────

  static Directory? _dir;

  static Future<Directory> _cacheDir() async {
    final d = _dir ??=
        Directory('${(await getApplicationSupportDirectory()).path}/scenes');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  /// The downloaded file for [s], or null if it has never been fetched.
  /// Bundled scenes return null — they are assets, not cache.
  static Future<File?> cachedFile(Scene s) async {
    if (s.bundled) return null;
    final f = File('${(await _cacheDir()).path}/${s.fileName}');
    return f.existsSync() && f.lengthSync() > 0 ? f : null;
  }

  /// Settles where downloads live, so [isReadySync] also sees the
  /// sceneries fetched in earlier sessions, not only the bundled ones.
  /// Never throws.
  static Future<void> warmCache() async {
    try {
      await _cacheDir();
    } catch (_) {/* no cache dir is no downloads, which isReadySync says */}
  }

  static bool isReadySync(Scene s) =>
      s.bundled || (_dir != null &&
          File('${_dir!.path}/${s.fileName}').existsSync());

  /// In-flight downloads, so two taps on the same tile share one fetch
  /// instead of racing to write the same file.
  static final Map<String, Future<File?>> _inFlight = {};

  /// How long a fetch may go without a single byte arriving before it
  /// is treated as dead.
  ///
  /// Idle rather than total, because a slow download that is still
  /// arriving is not a failed one — a four megabyte clip on a weak
  /// connection is allowed to take its time, a socket that has gone
  /// quiet is not. The only timeout before covered [http.Client.send],
  /// which resolves the moment the response *headers* land; the body
  /// stream underneath it had none at all, so a connection that opened,
  /// answered 200 and then stalled mid-clip waited for good. The
  /// deduplication in [download] hid this for as long as it hid
  /// everything else, and it is the one failure the retry cannot see
  /// coming: nothing about a silent socket ever raises.
  static Duration _idleTimeout = const Duration(seconds: 20);

  /// Tries per download. A stall is almost always the network rather
  /// than the file, and the second attempt usually lands.
  static const _attempts = 2;

  /// Points the catalog at a local server and directory, and shortens
  /// the stall timeout — so "a dead connection still ends" can be
  /// checked in a second rather than in forty. Nothing else can
  /// establish that: a socket that goes quiet is exactly the case no
  /// amount of tapping reproduces on a desk.
  @visibleForTesting
  static void configureForTest({
    required String baseUrl,
    required Directory cacheDir,
    Duration idle = const Duration(milliseconds: 300),
  }) {
    _baseUrl = baseUrl;
    _dir = cacheDir;
    _idleTimeout = idle;
    _inFlight.clear();
  }

  /// Fetch [s] into the cache, reporting 0..1 as it goes. Returns null
  /// if it could not be fetched; callers keep showing the poster.
  ///
  /// Guaranteed to complete: every path out of [_fetchOnce] is bounded,
  /// which is what callers that block on it depend on.
  static Future<File?> download(Scene s, {void Function(double)? onProgress}) {
    return _inFlight[s.id] ??= _download(s, onProgress).whenComplete(() {
      // A block body, and it has to stay one. `whenComplete` awaits
      // whatever its callback returns, and `Map.remove` returns the
      // value it removed — which here is this very future. Written as
      // an arrow, `=> _inFlight.remove(s.id)`, the future waits on
      // itself and no download ever completes: the bytes still land on
      // disk, so the scenery appears on the *next* visit, and anything
      // that awaits the fetch waits for good. That is what left the
      // Preview button spinning with no way out.
      _inFlight.remove(s.id);
    });
  }

  static Future<File?> _download(
      Scene s, void Function(double)? onProgress) async {
    final existing = await cachedFile(s);
    if (existing != null) return existing;
    if (_baseUrl.isEmpty) return null;

    for (var attempt = 1; attempt <= _attempts; attempt++) {
      final file = await _fetchOnce(s, onProgress);
      if (file != null) return file;
      if (attempt < _attempts) {
        onProgress?.call(0); // the ring starts over rather than sticking
        rlog('scene ${s.id}: retrying (attempt ${attempt + 1})');
      }
    }
    return null;
  }

  static Future<File?> _fetchOnce(
      Scene s, void Function(double)? onProgress) async {
    final dest = File('${(await _cacheDir()).path}/${s.fileName}');
    // Written aside and renamed: a download killed halfway must not
    // leave a truncated file that later looks like a complete one.
    final part = File('${dest.path}.part');
    final client = http.Client();
    IOSink? sink;
    try {
      final req = http.Request('GET', Uri.parse('$_baseUrl/${s.fileName}'));
      final res = await client.send(req).timeout(_idleTimeout);
      if (res.statusCode != 200) {
        rlog('scene ${s.id}: HTTP ${res.statusCode}');
        return null;
      }
      final total = res.contentLength ?? s.bytes;
      sink = part.openWrite();
      var got = 0;
      await for (final chunk in res.stream.timeout(_idleTimeout)) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) onProgress?.call((got / total).clamp(0.0, 1.0));
      }
      await sink.close();
      sink = null;
      if (part.lengthSync() < 1024) return null;
      await part.rename(dest.path);
      onProgress?.call(1);
      return dest;
    } catch (e) {
      rlog('scene ${s.id}: download failed $e');
      return null;
    } finally {
      client.close();
      // The sink first: an open handle is enough to make removing the
      // part file fail, and a browsing session that stalls a few
      // downloads would otherwise leave both behind.
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {/* already broken — the delete is what matters */}
      }
      // Gone on the success path, renamed out from under this.
      if (part.existsSync()) {
        try {
          part.deleteSync();
        } catch (_) {/* nothing useful to do */}
      }
    }
  }

  /// Quietly pull a handful of scenes the user is likely to tap next.
  /// Stills only: they are a few hundred KB, where a clip is megabytes
  /// and not worth spending someone's data on speculatively.
  static Future<void> prefetch(Iterable<Scene> scenes, {int limit = 6}) async {
    var n = 0;
    for (final s in scenes) {
      if (n >= limit) break;
      if (s.bundled || s.isVideo) continue;
      if (await cachedFile(s) != null) continue;
      n++;
      unawaited(download(s));
    }
  }

  // ── conversion ────────────────────────────────────────────────────

  /// The [ReelBackground] for a scene, given its file if downloaded.
  /// Bundled scenes point at their asset; cached ones at their path,
  /// which is the same road a user-picked file already travels.
  static ReelBackground background(Scene s, {File? file}) {
    if (s.bundled) {
      return s.isVideo
          ? ReelBackground(
              id: s.id,
              name: s.label,
              videoAsset: s.bundledAsset,
              gradientArgb: s.gradientArgb,
              knownAspect: s.aspect,
            )
          : ReelBackground.still(
              id: s.id,
              name: s.label,
              imageAsset: s.bundledAsset,
              gradientArgb: s.gradientArgb,
              knownAspect: s.aspect,
            );
    }
    return ReelBackground.cached(
      id: s.id,
      name: s.label,
      filePath: file!.path,
      fileIsImage: !s.isVideo,
      gradientArgb: s.gradientArgb,
      knownAspect: s.aspect,
    );
  }

  // ── storage ───────────────────────────────────────────────────────

  static Future<int> cacheBytes() async {
    try {
      final d = await _cacheDir();
      return d
          .listSync()
          .whereType<File>()
          .fold<int>(0, (a, f) => a + f.lengthSync());
    } catch (_) {
      return 0;
    }
  }

  static Future<void> clearCache() async {
    try {
      final d = await _cacheDir();
      for (final f in d.listSync().whereType<File>()) {
        f.deleteSync();
      }
    } catch (_) {/* the storage sheet re-measures either way */}
  }
}
