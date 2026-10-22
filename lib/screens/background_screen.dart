import 'dart:async';
import 'dart:io';

// Prefixed: the plugin exports an `AppSettings` that clashes with the
// app's own settings model elsewhere; keep the naming consistent.
import 'package:app_settings/app_settings.dart' as os_settings;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../data/fatiha_data.dart';
import '../data/models.dart';
import '../data/quran_repository.dart';
import '../data/debug_log.dart';
import '../data/scene_catalog.dart';
import '../data/scene_matcher.dart';
import '../data/settings_service.dart';
import '../data/verse_lines.dart';
import '../l10n/l10n.dart';
import '../render/scene_plan.dart';
import '../render/verse_planner.dart';
import '../state/creation_state.dart';
import '../theme/app_theme.dart';
import '../widgets/a11y.dart';
import '../widgets/app_toast.dart';
import '../widgets/coach_marks.dart';
import '../widgets/glass_tile.dart';
import '../widgets/glow_button.dart';
import '../widgets/how_to_sheet.dart';
import '../widgets/step_dots.dart';
import 'style_screen.dart';

/// Screen 3 of 5. One decision: the scenery.
/// A grid of bundled sceneries plus the user's own photo/video. The
/// verses are NOT shown here — the next screen previews them on top of
/// exactly the scenery chosen.
///
/// One scenery unless the multi-scene pill is on, in which case tiles
/// take a number instead of a tick and the reel runs through them in
/// the order they were tapped.
class BackgroundScreen extends StatefulWidget {
  const BackgroundScreen({super.key});

  @override
  State<BackgroundScreen> createState() => _BackgroundScreenState();
}

class _BackgroundScreenState extends State<BackgroundScreen> {
  final _picker = ImagePicker();
  ReelBackground? _custom;
  late ReelBackground _selected;

  /// Open tab. The library is far too big for one grid, so the rail is
  /// the only navigation — no search, no sort, no folders.
  ///
  /// Opens on the tab this user last browsed, and on the first one —
  /// sky — until they have browsed any. Sky is the scenery a verse is
  /// read against more than any other; landing anywhere else asks the
  /// user to navigate before they can start.
  String _tab = creationState.sceneryTab ?? _openingTab;

  /// The page: the head scrolls away, the rail stays, the grid fills
  /// what is left. Opens where it was left in this reel — see
  /// [CreationState.sceneryOffset].
  late final ScrollController _scroll =
      ScrollController(initialScrollOffset: creationState.sceneryOffset);

  /// The part of the page that scrolls away, measured for where a new
  /// tab's grid starts.
  final _headKey = GlobalKey();

  /// The remembered tab, once the catalogue can vouch for it. A tab can
  /// leave the library between releases, and a saved name that no
  /// longer exists must not strand the picker on an empty grid.
  static String get _openingTab {
    final saved = SettingsService.state.value.sceneTab;
    return saved.isNotEmpty && SceneCatalog.tabOrder.contains(saved)
        ? saved
        : SceneCatalog.tabOrder.first;
  }

  /// Remembers the tab across reels. Fire-and-forget: a tap must not
  /// wait on a file write, and a lost write costs one tab.
  void _rememberTab(String tab) {
    if (SettingsService.state.value.sceneTab == tab) return;
    unawaited(SettingsService.update(
        SettingsService.state.value.copyWith(sceneTab: tab)));
  }

  /// Which shape of scenery the rail and grid are showing. Follows the
  /// frame — the wide card wants 16:9 footage, the full frame upright —
  /// and the toggle above the rail is how you overrule that.
  bool _wideScenes =
      creationState.sceneryWide ?? creationState.layout == ReelLayout.letterbox;

  /// Whether a scenery was already chosen when this screen opened. The
  /// fallback [_selected] stands in for "none picked yet", and standing
  /// in for a choice is not the same as being one — only a real choice
  /// gets to decide which tab opens.
  ///
  /// Read from [CreationState.backgroundChosen] rather than from
  /// `background != null`. This screen seeds the stand-in into the
  /// state on the way in, and `startNewReel` deliberately keeps a
  /// background across reels, so from the second visit on there is
  /// always a non-null one — the null check called that a choice and
  /// sent everybody to Abstract.
  late final bool _hadChoice;

  /// Id of the scene whose tile is selected, so the ring survives the
  /// gap between tapping and the download finishing.
  String? _selectedId;

  /// Picking several sceneries rather than one.
  bool _multi = creationState.multiScene;

  /// How many sceneries this reel can hold — its own length divided
  /// between scenes no shorter than [ScenePlan.minDwellMs], so a short
  /// passage of long verses still takes more than a couple. Measured
  /// off the recitation when it is already on the device (the verses
  /// screen starts fetching it on the way here), estimated from the
  /// verse count when it is not. See [ScenePlan.maxScenes].
  int get _sceneLimit {
    final start = creationState.startAyah;
    final end = creationState.endAyah;
    final r = creationState.reciter;
    final rec = r == null
        ? null
        : QuranRepository.recitationIfCached(r.id, creationState.surah);
    final segMs = rec != null && rec.covers(start, end)
        ? rec.timing(end).endMs - rec.timing(start).startMs
        : null;
    return ScenePlan.maxScenes(_slotCount, segMs: segMs);
  }

  /// What a scene each would be: the verses, or — with long verses shown
  /// line by line and the scenery following the lines — every line of
  /// them, counted from the text as it will be typeset.
  int get _slotCount {
    final s = creationState;
    final ayahs = QuranRepository.ayahsIfCached(s.surah);
    return (ayahs == null ? null : _lineTexts(ayahs))?.length ??
        s.endAyah - s.startAyah + 1;
  }

  /// The text of each line of the selection when its long verses go
  /// line by line and the scenery follows them; null when it is a
  /// scene per verse.
  List<String>? _lineTexts(List<Ayah> ayahs) {
    final s = creationState;
    if (s.verseLines == VerseLines.whole || s.pacing != ScenePacing.perLine) {
      return null;
    }
    final settings = SettingsService.state.value;
    return VersePlanner.estimateLines(
      ayahs,
      s.startAyah,
      s.endAyah,
      s.verseLines,
      VerseLook(
        textScale: s.textScale,
        preset: s.textPreset,
        typography: s.typography,
        edition: settings.translation,
        numbering: settings.verseNumbering,
        showTranslation: !settings.verseTranslationOff,
        ink: s.verseInk,
        surah: s.surah,
      ),
    );
  }

  /// A scene per verse — or per line — : what the blurb suggests, and
  /// what the reel is built around.
  int get _sceneIdeal => ScenePlan.recommended(_slotCount);

  /// This scenery's place in the run, 1-based; 0 when it is not in it.
  int _orderOf(String id) {
    final at = creationState.scenes.indexWhere((s) => s.id == id);
    return at + 1;
  }

  /// Download progress per scene id, 0..1, while one is in flight.
  final Map<String, double> _progress = {};

  /// The scene tap still resolving, if any: a tile is showing its ring
  /// but the file is still coming down. Preview waits on this — opening
  /// the preview mid-download used to land on the *previous* scenery,
  /// and the file arriving a second later had nowhere to go but the
  /// next visit. Completes with whether the scenery actually landed.
  Future<bool>? _selecting;

  /// Scene id [_selecting] belongs to, so a wait can show that scene's
  /// own progress instead of a spinner that says nothing.
  String? _selectingId;

  /// Preview was tapped while [_selecting] was still running.
  bool _waitingForScene = false;

  /// The user has picked a tab or a shape for themselves. The catalog
  /// loads a frame or two after this screen opens and settles both on
  /// the way in; once someone has chosen, it has nothing left to say.
  bool _browsed = false;

  /// See [_endTour]. Set once the catalog is in and the rail has tabs.
  bool _tour = false;

  /// While the preview screen is on top, every tile releases its video
  /// decoder. Phones cap simultaneous hardware decoders; if the grid
  /// holds them all, the preview's background video initializes but
  /// stalls on its first frame.
  bool _suspended = false;

  /// Consecutive native picker failures. Backing out of the picker is
  /// not a failure — only the platform actually throwing counts.
  int _pickFails = 0;

  /// Controls the first-run walkthrough points at. Each is measured
  /// through its key, so a control that isn't on screen — the multi
  /// pill on a one-verse reel, the wide-card extras while the full
  /// frame is chosen — simply has its step skipped or redirected.
  final _railKey = GlobalKey();
  final _multiKey = GlobalKey();
  final _frameKey = GlobalKey();

  /// Whether the walkthrough is on screen. Held back until the catalog
  /// has landed: the tab rail is empty — and so has nothing to point
  /// at — for the frame or two before it does.

  /// True once the picker is judged broken for this user — an explicit
  /// permission denial, or two straight native failures. Shows the
  /// banner that hands them to the OS settings screen, the only place
  /// a revoked media permission can be granted back.
  bool _pickBlocked = false;

  /// The verses are being read and their sceneries fetched.
  bool _matching = false;

  /// What the last match chose, for the line that says why. Cleared
  /// the moment the user picks anything by hand: the reason no longer
  /// describes the run.
  List<ScenePick> _matched = const [];

  @override
  void initState() {
    super.initState();
    // Honour a scenery already chosen: the featured template picks one
    // on the user's behalf, and coming back here from the preview
    // should not throw away what they landed on.
    _hadChoice = creationState.backgroundChosen;
    _selected = creationState.background ?? backgrounds[0];
    _selectedId = _selected.id;
    // A device file that isn't a catalog scene is the user's own upload;
    // give the upload tile its thumbnail back rather than an empty
    // invitation next to a selected-but-invisible choice.
    if (_selected.isDeviceFile && _selected.id.startsWith('custom_')) {
      _custom = _selected;
    }
    // Coming back from the preview must not flatten a run that was
    // picked before going there: only a reel with no scenery at all,
    // or one that never branched, is (re)set from the single choice.
    if (creationState.scenes.length <= 1) {
      creationState.seedBackground(_selected);
    } else {
      // The verse range may have been shortened since the run was
      // picked, and a reel cannot hold more scenes than it has verses.
      creationState.trimScenes(_sceneLimit);
    }
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    await SceneCatalog.load();
    if (!mounted) return;
    setState(() {
      _tour = !SettingsService.state.value.sceneryTourDone &&
          SceneCatalog.tabsFor(wide: _wideScenes).isNotEmpty;
      if (_browsed) return;
      // Three answers, in this order:
      //
      // 1. The tab the user last browsed. Tapping a tab is the only
      //    statement anyone makes about where they like to start, and
      //    it outranks a scenery that carried over from the last reel.
      // 2. The tab holding the chosen scenery, so the ring is on
      //    screen rather than four tabs away. Only a scenery the user
      //    actually picked counts — the stand-in background this
      //    screen falls back to is not a choice, and it used to drag
      //    every first-time user to Abstract.
      // 3. Sky, the first tab, which is where a verse is read more
      //    often than anywhere else.
      final saved = SettingsService.state.value.sceneTab;
      final remembered =
          saved.isNotEmpty && SceneCatalog.tabOrder.contains(saved);
      final chosen = _hadChoice ? SceneCatalog.byId(_selected.id) : null;
      // Back here in the same reel — from the verses, from the style
      // step — the screen is where it was left, tab and all. Before any
      // of the three answers below.
      final left = creationState.sceneryTab;
      if (left != null &&
          SceneCatalog.tabsFor(wide: _wideScenes).contains(left)) {
        _tab = left;
        return;
      }
      if (chosen != null && !remembered) _wideScenes = chosen.wide;
      final tabs = SceneCatalog.tabsFor(wide: _wideScenes);
      if (remembered && tabs.contains(saved)) {
        _tab = saved;
      } else if (chosen != null && tabs.contains(chosen.tab)) {
        _tab = chosen.tab;
      } else if (tabs.isNotEmpty && !tabs.contains(_tab)) {
        _tab = tabs.first;
      }
    });
    // The first row of the opening tab is what most people tap, and a
    // still is a few hundred KB — cheap enough to have waiting.
    unawaited(SceneCatalog.prefetch(SceneCatalog.inTab(_tab)));
  }

  /// Switches the rail and grid between the upright and 16:9 families.
  ///
  /// Always rebuilds, even when nothing here moves: the frame pills
  /// call this, and their own selected state has just changed.
  void _showScenes({required bool wide}) {
    final tabs = SceneCatalog.tabsFor(wide: wide);
    final tab = tabs.isNotEmpty && !tabs.contains(_tab) ? tabs.first : _tab;
    final moved = wide != _wideScenes || tab != _tab;
    setState(() {
      _browsed = true;
      _wideScenes = wide;
      _tab = tab;
    });
    creationState
      ..sceneryWide = wide
      ..sceneryTab = tab;
    if (moved) {
      _toGridTop();
      unawaited(SceneCatalog.prefetch(SceneCatalog.inTab(tab)));
    }
  }

  /// Switching the frame, which is a bigger move than switching the
  /// grid: the two frames take different footage. A 16:9 scenery in the
  /// full frame is cropped to its middle third, and an upright one in
  /// the wide card is boxed in on all four sides — so a selection made
  /// for the frame the user just left is not a selection any more. It
  /// goes, and the grid now on screen is where the next one comes from.
  ///
  /// Only sceneries the catalogue can vouch for are dropped. The user's
  /// own photo or video is theirs at whatever shape they filmed it, and
  /// nothing here gets to throw it away.
  void _setFrame(ReelLayout layout) {
    final wide = layout == ReelLayout.letterbox;
    final dropped = creationState.dropScenes((b) {
      final s = SceneCatalog.byId(b.id);
      return s == null || s.wide == wide;
    });
    if (dropped > 0) {
      _selected = creationState.background ?? _selected;
      _selectedId = creationState.background?.id;
    }
    // Rebuilds either way — the frame pills' own selected state has
    // just changed.
    _showScenes(wide: wide);
    if (dropped == 0) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(_toast(
        L10n.of(context).pickForNewFrame,
        duration: const Duration(seconds: 3),
      ));
  }

  /// Lets the verses choose.
  ///
  /// Reads the selection, picks one scenery per verse — or per line,
  /// when long verses go line by line — as many as the reel holds,
  /// fewer for a short reel with long verses — fetches the files, and
  /// only then replaces the run: a run half swapped for one
  /// that never arrived is worse than the run the user had. Several
  /// sceneries put the picker into multi-scene mode on their own; one
  /// verse gets one, and the mode stays as it was.
  Future<void> _matchScenes() async {
    if (_matching) return;
    HapticFeedback.selectionClick();
    final l = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _matching = true);
    try {
      await SceneCatalog.load();
      final surah = creationState.surah;
      final ayahs = QuranRepository.ayahsIfCached(surah) ??
          await QuranRepository.ayahsOf(surah);
      if (!mounted) return;
      final start = creationState.startAyah;
      final end = creationState.endAyah;
      final limit = _sceneLimit;
      // With long verses going line by line and the scenery following
      // them, every line chooses its own scenery from its own words.
      final lines = _lineTexts(ayahs);
      final source = lines == null
          ? ayahs
          : [
              for (var i = 0; i < lines.length; i++)
                Ayah(number: i + 1, arabic: lines[i], translation: ''),
            ];
      final from = lines == null ? start : 1;
      final to = lines == null ? end : lines.length;
      final count = (to - from + 1).clamp(1, limit);
      final wide = creationState.layout == ReelLayout.letterbox;
      final ready = <String>{
        for (final s in SceneCatalog.all)
          if (SceneCatalog.isReadySync(s)) s.id,
      };
      final picks = SceneMatcher.match(
        ayahs: source,
        startAyah: from,
        endAyah: to,
        count: count,
        wide: wide,
        catalog: SceneCatalog.all,
        ready: ready,
      );
      rlog('match: ${picks.length} picks for $surah:$start-$end — '
          '${picks.map((p) => "${p.scene.id}(${p.motif})").join(", ")}');
      if (picks.isEmpty) {
        messenger.showSnackBar(_toast(l.matchedNothing, tone: ToastTone.problem));
        return;
      }

      // Fetch everything first, together; the tiles show each file
      // arriving exactly as a tapped one does.
      final files = await Future.wait([
        for (final p in picks) _fileFor(p.scene),
      ]);
      if (!mounted) return;
      final resolved = <ReelBackground>[];
      final kept = <ScenePick>[];
      for (var i = 0; i < picks.length; i++) {
        final scene = picks[i].scene;
        if (scene.bundled) {
          resolved.add(SceneCatalog.background(scene));
          kept.add(picks[i]);
        } else if (files[i] != null) {
          resolved.add(SceneCatalog.background(scene, file: files[i]));
          kept.add(picks[i]);
        }
      }
      if (resolved.isEmpty) {
        messenger.showSnackBar(_toast(l.matchedNothing, tone: ToastTone.problem));
        return;
      }

      if (wide && creationState.layout != ReelLayout.letterbox) {
        creationState.setLayout(ReelLayout.letterbox);
      }
      creationState.dropScenes((_) => false);
      if (resolved.length > 1) {
        creationState.setMultiScene(true);
        for (final b in resolved) {
          creationState.toggleScene(b, limit: resolved.length);
        }
      } else {
        creationState.selectBackground(resolved.first);
      }
      setState(() {
        _multi = creationState.multiScene;
        _matched = kept;
        _selected = creationState.background ?? resolved.first;
        _selectedId = _selected.id;
        _browsed = true;
        _wideScenes = wide;
        // Open on the first scenery's tab, so the run is visible from
        // its start rather than somewhere in the middle of it.
        final tabs = SceneCatalog.tabsFor(wide: wide);
        if (tabs.contains(kept.first.scene.tab)) _tab = kept.first.scene.tab;
      });
      HapticFeedback.mediumImpact();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(_toast(
          l.scenesMatched(resolved.length),
          tone: ToastTone.done,
          duration: const Duration(seconds: 2),
        ));
    } catch (e, st) {
      rlogError('scene match', e, st);
      if (mounted) {
        messenger.showSnackBar(_toast(l.matchedNothing, tone: ToastTone.problem));
      }
    } finally {
      if (mounted) setState(() => _matching = false);
    }
  }

  /// What the match chose and why, for the advice line: how many, and
  /// the motifs that decided, in reel order, each once.
  String _matchedLine(L10n l) {
    final reasons = <String>[];
    for (final p in _matched) {
      final name = l.motifName(p.motif);
      if (!reasons.contains(name)) reasons.add(name);
    }
    return '${l.scenesMatched(_matched.length)} · ${reasons.join(' · ')}';
  }

  /// How far a notice on this screen rises off the foot: over the
  /// button there, which a toast at the usual height covered — "three
  /// sceneries chosen" sat on "Style my reel" and took its taps.
  static const _overButton = 72.0;

  /// The app's toast, lifted over the button at the foot of this screen.
  SnackBar _toast(
    String message, {
    ToastTone tone = ToastTone.info,
    Duration duration = const Duration(seconds: 4),
  }) =>
      toast(message, tone: tone, duration: duration, above: _overButton);

  /// Every scenery chosen for this reel let go: the run emptied, the
  /// verses' own choice forgotten, the ring off every tile. Several
  /// sceneries stays on if it was on, so picking again starts counting
  /// from one; the button at the foot waits until something is picked.
  void _resetScenes() {
    HapticFeedback.mediumImpact();
    // A download still coming in was picked before the reset, and must
    // not put its scenery back when it lands.
    _resets++;
    creationState.dropScenes((_) => false);
    setState(() {
      _matched = const [];
      _selectedId = null;
      _selecting = null;
      _selectingId = null;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(_toast(
        L10n.of(context).sceneryCleared,
        duration: const Duration(seconds: 2),
      ));
  }

  /// The file behind a catalog scene: the cached one, or a download
  /// shown on the tile. Null for a bundled scene (which needs none)
  /// and for a fetch that failed.
  Future<File?> _fileFor(Scene s) async {
    if (s.bundled) return null;
    final have = await SceneCatalog.cachedFile(s);
    if (have != null) return have;
    if (mounted) setState(() => _progress[s.id] = 0);
    final file = await SceneCatalog.download(
      s,
      onProgress: (p) {
        if (mounted) setState(() => _progress[s.id] = p);
      },
    );
    if (mounted) setState(() => _progress.remove(s.id));
    return file;
  }

  void _select(ReelBackground b) {
    if (_matched.isNotEmpty) _matched = const [];
    if (_multi) {
      if (!creationState.toggleScene(b, limit: _sceneLimit)) {
        HapticFeedback.lightImpact();
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(_toast(
            L10n.of(context).sceneLimit(_sceneLimit),
            duration: const Duration(seconds: 2),
          ));
        return;
      }
      HapticFeedback.selectionClick();
      setState(() {
        _selected = creationState.background ?? b;
        _selectedId = _selected.id;
      });
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _selected = b;
      _selectedId = b.id;
    });
    creationState.selectBackground(b);
  }

  /// Turning multi-scene on or off. Off collapses the run back to the
  /// scenery the reel opens on — the one already under the ring — so
  /// nothing about the reel changes except that it stops branching.
  void _setMulti(bool on) {
    HapticFeedback.selectionClick();
    creationState.setMultiScene(on);
    setState(() {
      _multi = on;
      _selected = creationState.background ?? _selected;
      // A run emptied of every scenery collapses to none, and the ring
      // goes with it: a tick on a tile the reel doesn't have would sit
      // over a door that stays shut.
      _selectedId = creationState.background?.id;
    });
  }

  /// Bumped by every tap. A download that lands after a newer tap is
  /// stale, and must not take the selection back from it.
  int _tapTicket = 0;

  /// Bumped by the reset: every download in flight then is stale, in
  /// several-sceneries mode too.
  int _resets = 0;

  /// Tapping a scene tile. The work is tracked in [_selecting] so the
  /// Preview button can wait for a download rather than open the screen
  /// on the scenery the user just replaced.
  void _tapScene(Scene s) {
    // A tile still downloading is already on its way into the run; a
    // second tap would take it out again the moment it lands.
    if (_multi && _progress.containsKey(s.id)) return;
    final job = _selectScene(s);
    setState(() {
      _selecting = job;
      _selectingId = s.id;
    });
    job.whenComplete(() {
      if (mounted && identical(_selecting, job)) {
        setState(() {
          _selecting = null;
          _selectingId = null;
        });
      }
    });
  }

  /// Choosing a scene: bundled ones are immediate, the rest are fetched
  /// once and then behave identically. The tile keeps showing its
  /// poster throughout, so nothing blanks out while bytes move.
  ///
  /// Answers whether the scenery is now the selected one — false when
  /// the fetch failed and the selection stayed where it was, which is
  /// what stops Preview opening on a scenery the user did not pick.
  Future<bool> _selectScene(Scene s) async {
    final ticket = ++_tapTicket;
    final epoch = _resets;
    // Picking one scenery, only the latest tap counts. Several are
    // each their own pick, so every download lands — unless the reset
    // came in between.
    bool stale() => epoch != _resets || (!_multi && ticket != _tapTicket);
    // A wide scenery only reads as intended inside the letterbox card —
    // full-frame would crop a 16:9 shot down to its middle third — so
    // picking one sets the format rather than leaving it to be
    // discovered.
    if (s.wide && creationState.layout != ReelLayout.letterbox) {
      creationState.setLayout(ReelLayout.letterbox);
    }

    if (s.bundled) {
      _select(SceneCatalog.background(s));
      return true;
    }
    final have = await SceneCatalog.cachedFile(s);
    if (have != null) {
      if (!mounted || stale()) return false;
      _select(SceneCatalog.background(s, file: have));
      return true;
    }

    HapticFeedback.selectionClick();
    setState(() {
      _selectedId = s.id;
      _progress[s.id] = 0;
    });
    final file = await SceneCatalog.download(
      s,
      onProgress: (p) {
        if (mounted) setState(() => _progress[s.id] = p);
      },
    );
    if (!mounted) {
      // Left while it was still coming down — back to the verses, say.
      // The tap still counts: the pick lands in the reel exactly as it
      // would have here, so the next visit finds it chosen rather than
      // the scenery before it.
      if (file != null && !stale()) {
        final b = SceneCatalog.background(s, file: file);
        if (_multi) {
          if (!creationState.scenes.any((x) => x.id == b.id)) {
            creationState.toggleScene(b, limit: _sceneLimit);
          }
        } else {
          creationState.selectBackground(b);
        }
      }
      return false;
    }
    setState(() => _progress.remove(s.id));
    if (stale()) return false;
    if (file == null) {
      // Selection stays where it was; say so once and move on.
      setState(() => _selectedId = _selected.id);
      ScaffoldMessenger.of(context).showSnackBar(
        _toast(
          L10n.of(context).sceneDownloadFailed,
          tone: ToastTone.problem,
        ),
      );
      return false;
    }
    _select(SceneCatalog.background(s, file: file));
    return true;
  }

  void _openTab(String tab) {
    HapticFeedback.selectionClick();
    final moved = tab != _tab;
    setState(() {
      _browsed = true;
      _tab = tab;
    });
    creationState.sceneryTab = tab;
    _rememberTab(tab);
    if (moved) _toGridTop();
    unawaited(SceneCatalog.prefetch(SceneCatalog.inTab(tab)));
  }

  /// A new tab's grid starts at its top: with the head scrolled away
  /// it stays away — the rail pinned, the first row under it — and a
  /// page still at its head is left where it is.
  void _toGridTop() {
    if (!_scroll.hasClients) return;
    final head = _headKey.currentContext?.findRenderObject();
    final h = head is RenderBox && head.hasSize ? head.size.height : 0.0;
    if (_scroll.offset > h) _scroll.jumpTo(h);
  }

  @override
  void dispose() {
    // Kept for the way back, within this reel.
    if (_scroll.hasClients) creationState.sceneryOffset = _scroll.offset;
    creationState
      ..sceneryTab = _tab
      ..sceneryWide = _wideScenes;
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _pickCustom() async {
    final isImage = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surfaceRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        final l = L10n.of(ctx);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              ListTile(
                leading:
                    const Icon(Icons.photo_outlined, color: AppColors.gold),
                title: Text(l.chooseAPhoto),
                onTap: () => Navigator.of(ctx).pop(true),
              ),
              ListTile(
                leading:
                    const Icon(Icons.videocam_outlined, color: AppColors.gold),
                title: Text(l.chooseAVideo),
                onTap: () => Navigator.of(ctx).pop(false),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (isImage == null) return;

    final XFile? file;
    try {
      file = isImage
          ? await _picker.pickImage(source: ImageSource.gallery)
          : await _picker.pickVideo(source: ImageSource.gallery);
    } on PlatformException catch (e) {
      // iOS reports a revoked Photos permission as *_access_denied.
      // (The modern pickers on both platforms need no permission, so
      // this path is old-OS / managed-device territory.)
      _pickFailed(denied: e.code.contains('access_denied'));
      return;
    } catch (_) {
      _pickFailed();
      return;
    }
    if (file == null || !mounted) return; // backed out: nothing to note

    // A successful pick proves the picker works; retire the banner.
    _pickFails = 0;
    if (_pickBlocked) setState(() => _pickBlocked = false);

    final bg = ReelBackground.deviceFile(
      // Unique per picked file so the render cache never serves a stale
      // reel after the user swaps their upload.
      id: 'custom_${file.path.hashCode.toRadixString(16)}',
      // Display name is derived from fileIsImage at build time so it
      // follows the app language; this stored one is a fallback only.
      name: isImage ? 'Your photo' : 'Your video',
      filePath: file.path,
      fileIsImage: isImage,
    );
    setState(() => _custom = bg);
    _select(bg);
  }

  /// One failure gets a quiet retry snack; a denial, or a second
  /// failure in a row, raises the settings banner instead — retrying a
  /// picker the OS has blocked would just fail forever.
  void _pickFailed({bool denied = false}) {
    if (!mounted) return;
    _pickFails++;
    if (denied || _pickFails >= 2) {
      setState(() => _pickBlocked = true);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      _toast(L10n.of(context).galleryPickFailed, tone: ToastTone.problem),
    );
  }

  Future<void> _openAppSettings() async {
    HapticFeedback.selectionClick();
    try {
      // The app's own settings page: media/photos permissions live
      // there on both platforms.
      await os_settings.AppSettings.openAppSettings(
          type: os_settings.AppSettingsType.settings);
    } catch (_) {/* nothing useful to say if the OS refuses */}
  }

  Future<void> _create() async {
    // A scenery still downloading is the one the user just chose, so the
    // preview waits for it. Without this the preview opens on the old
    // background, and the download lands behind it with nothing left to
    // apply it to — the reason a fresh scenery only ever showed up on
    // the second visit.
    final pending = _selecting;
    if (pending != null) {
      setState(() => _waitingForScene = true);
      // Bounded, even though the fetch underneath it is bounded too:
      // this wait is the one thing on the screen with no way out of it,
      // and a button that can sit spinning forever is worse than one
      // that gives up and says why.
      var timedOut = false;
      final landed = await pending.timeout(
        const Duration(seconds: 90),
        onTimeout: () {
          timedOut = true;
          return false;
        },
      );
      if (!mounted) return;
      setState(() => _waitingForScene = false);
      if (!landed) {
        // The scenery they tapped never arrived. Opening the preview on
        // the one before it is exactly the confusion this wait was
        // added to remove, so stay here — the tile still holds their
        // choice and tapping it again retries. A fetch that failed on
        // its own has already said so; a wait that ran out has not.
        if (timedOut) {
          ScaffoldMessenger.of(context).showSnackBar(
            _toast(
              L10n.of(context).sceneDownloadFailed,
              tone: ToastTone.problem,
            ),
          );
        }
        return;
      }
    }
    setState(() => _suspended = true);
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const StyleScreen()),
    );
    if (mounted) setState(() => _suspended = false);
  }

  /// The walkthrough is shown once and never again, whether it was
  /// walked to the end or skipped on the first card.
  void _endTour() {
    setState(() => _tour = false);
    SettingsService.update(
        SettingsService.state.value.copyWith(sceneryTourDone: true));
  }

  /// What the first-run walkthrough says, in the order it says it.
  List<CoachStep> _tourSteps(L10n l) => [
        CoachStep(
          target: _railKey,
          title: l.tourThemesTitle,
          body: l.tourThemesBody,
        ),
        CoachStep(
          target: _multiKey,
          title: l.tourMultiTitle,
          body: l.tourMultiBody,
        ),
        CoachStep(
          target: _frameKey,
          title: l.tourFrameTitle,
          body: l.tourFrameBody,
        ),
        // What the wide card opens up is set on the next screen; this
        // says so, standing by the pills that open it.
        CoachStep(
          target: _frameKey,
          title: l.tourFinishTitle,
          body: l.tourFinishBody,
        ),
      ];

  /// The scenery grid for the open tab, as the page's last sliver.
  ///
  /// Posters are bundled for every scene, so this draws instantly and
  /// completely offline no matter how much of the library has been
  /// downloaded. Wide scenes get two columns because a 16:9 card shown
  /// three-up is too small to judge; portrait scenes get three, which
  /// is what makes a forty-scene tab browsable in two thumb-flicks.
  Widget _grid() {
    final scenes = SceneCatalog.inTab(_tab);
    if (scenes.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.only(top: 40),
          child: Center(
            child: SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }
    final wide = scenes.first.wide;
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: wide ? 2 : 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: wide ? 16 / 9 : 9 / 16,
        ),
        // The user's own photo leads every tab: it is the most personal
        // choice, not something to find behind four hundred others.
        delegate: SliverChildBuilderDelegate(
          childCount: scenes.length + 1,
          (_, i) {
            if (i == 0) {
              return _UploadTile(
                custom: _custom,
                order: _custom == null ? 0 : _orderOf(_custom!.id),
                multi: _multi,
                selected: _custom != null &&
                    (_multi
                        ? _orderOf(_custom!.id) > 0
                        : _selectedId == _custom!.id),
                suspended: _suspended,
                compact: true,
                onTap: _custom == null
                    ? _pickCustom
                    : () => _select(_custom!),
                onReplace: _pickCustom,
              );
            }
            final s = scenes[i - 1];
            final order = _orderOf(s.id);
            return _SceneTile(
              scene: s,
              position: i,
              count: scenes.length,
              selected: _multi ? order > 0 : _selectedId == s.id,
              order: _multi ? order : 0,
              progress: _progress[s.id],
              onTap: () => _tapScene(s),
            );
          },
        ),
      ),
    );
  }

  /// The screen's "?": the whole of how it works, in five lines.
  void _howTo() {
    final l = L10n.of(context);
    showHowTo(
      context,
      title: l.sceneryHowToTitle,
      steps: [
        (
          const Icon(Icons.crop_16_9_rounded,
              size: 17, color: AppColors.goldBright),
          l.sceneryHowToFrame(l.frameFull, l.frameLetterbox),
        ),
        (
          const Icon(Icons.touch_app_rounded,
              size: 17, color: AppColors.goldBright),
          l.sceneryHowToTap,
        ),
        (
          const Icon(Icons.filter_none_rounded,
              size: 16, color: AppColors.goldBright),
          l.sceneryHowToSeveral(l.multipleScenes),
        ),
        (
          const Icon(Icons.auto_awesome_rounded,
              size: 16, color: AppColors.goldBright),
          l.sceneryHowToMatch(l.matchScenesToVerses),
        ),
        (
          const Icon(Icons.add_photo_alternate_outlined,
              size: 17, color: AppColors.goldBright),
          l.sceneryHowToOwn,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    // What scrolls away: the title, anything the screen has to say,
    // and the frame. The rail and the grid are what stay.
    final head = Padding(
      key: _headKey,
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          A11yHeader(
            child: Text(l.chooseTheScenery,
                style: t.titleMedium?.copyWith(fontSize: 20)),
          ),
          if (_pickBlocked) ...[
            const SizedBox(height: 10),
            A11yLive(child: _GalleryBlockedBanner(onOpen: _openAppSettings)),
          ],
          // How many sceneries this reel actually wants is advice, so
          // it stands on its own line in gold, right above the frame.
          // Live, so a reader hears what the match chose and why.
          if (_matched.isNotEmpty) ...[
            const SizedBox(height: 8),
            A11yLive(child: _SceneAdvice(text: _matchedLine(l))),
          ] else if (_multi) ...[
            const SizedBox(height: 8),
            A11yLive(
                child: _SceneAdvice(
                    text: _sceneIdeal >
                            creationState.endAyah - creationState.startAyah + 1
                        ? l.sceneryFillsLines(_sceneIdeal)
                        : l.sceneryFills(_sceneIdeal))),
          ],
          const SizedBox(height: 12),
          // The frame decision comes before the scenery because it
          // changes what a good scenery is: the wide card wants a
          // horizontal video, the full frame an upright one.
          _FormatPanel(
            pillsKey: _frameKey,
            onLayout: _setFrame,
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
    final rail = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            height: 30,
            child: Row(
              children: [
                _ShapeToggle(
                  wide: _wideScenes,
                  onTap: (w) {
                    HapticFeedback.selectionClick();
                    _showScenes(wide: w);
                  },
                ),
                const Spacer(),
                // Only while something is chosen: there is nothing to
                // let go of before that.
                if (creationState.backgroundChosen &&
                    creationState.scenes.isNotEmpty) ...[
                  _ResetPill(onTap: _resetScenes),
                  const SizedBox(width: 8),
                ],
                // A one-verse reel has room for one scenery, so there is
                // nothing here to offer and no pill for it.
                if (_sceneLimit > 1)
                  _MultiScenePill(
                    key: _multiKey,
                    on: _multi,
                    chosen: creationState.scenes.length,
                    limit: _sceneLimit,
                    onTap: () => _setMulti(!_multi),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        _TabRail(
          key: _railKey,
          tabs: SceneCatalog.tabsFor(wide: _wideScenes),
          current: _tab,
          onTap: _openTab,
          // The verses' own choice leads the rail: one more pill, at the
          // head of the row, that reads the selection and picks a
          // scenery per verse.
          leading: _MatchPill(
            busy: _matching,
            matched: _matched,
            onTap: _matchScenes,
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
    final scaffold = Scaffold(
      appBar: AppBar(
        leading: const BackButton(color: AppColors.textSecondary),
        title: StepDots(current: WizardSteps.scenery, total: WizardSteps.total),
        actions: [
          HowToButton(label: l.sceneryHowToTitle, onTap: _howTo),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: CustomScrollView(
                controller: _scroll,
                slivers: [
                  SliverToBoxAdapter(child: head),
                  // Scrolling the grid pushes the head up and away; the
                  // rail stays, so the tabs are always one tap off.
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _PinnedRail(child: rail, extent: _PinnedRail.height),
                  ),
                  _grid(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
              child: GlowButton(
                label: l.styleMyReel,
                icon: Icons.brush_rounded,
                height: 52,
                busy: _waitingForScene,
                // A four megabyte clip takes long enough that a bare
                // spinner reads as a frozen button. This is the same
                // fraction the tile's own ring is filling.
                busyProgress:
                    _selectingId == null ? null : _progress[_selectingId],
                // Untick every scenery and there is no reel to preview.
                // The button shuts rather than the last tile refusing to
                // untick: a tick the user cannot take back reads as a
                // stuck app, where a greyed button reads as a step still
                // to do.
                onPressed: creationState.scenes.isEmpty ? null : _create,
              ),
            ),
          ],
        ),
      ),
    );
    if (!_tour) return scaffold;
    // Over the whole screen, app bar included: the walkthrough dims
    // everything it is not pointing at.
    return Stack(
      children: [
        scaffold,
        Positioned.fill(
          child: CoachMarks(steps: _tourSteps(l), onFinished: _endTour),
        ),
      ],
    );
  }
}

/// The rail, pinned: the shape switch with the several-scenes pill,
/// and the tabs. Opaque, so the grid passes under it cleanly, with a
/// hairline under it once something is underneath.
class _PinnedRail extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double extent;

  _PinnedRail({required this.child, required this.extent});

  /// 6 + 30 + 8 + 38 + 6: the two rows and the air around them.
  static const height = 88.0;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(
            color: overlapsContent || shrinkOffset > 0
                ? AppColors.stroke
                : Colors.transparent,
          ),
        ),
      ),
      child: SizedBox(height: extent, child: child),
    );
  }

  @override
  bool shouldRebuild(_PinnedRail old) => true;
}

/// The pill at the head of the tab rail that lets the verses pick.
///
/// Small and plain: a hairline of gold around a spark and a word,
/// shorter than the tabs beside it so it reads as an aside to the
/// rail, not the first tab of it. While it works the spark spins;
/// once it has chosen the hairline fills in and the word becomes the
/// count, and a second tap chooses again. The reasons go on the
/// advice line above the frame, which is where this screen already
/// says what to aim at.
class _MatchPill extends StatelessWidget {
  final bool busy;
  final List<ScenePick> matched;
  final VoidCallback onTap;

  const _MatchPill({
    required this.busy,
    required this.matched,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final on = matched.isNotEmpty;
    return A11yTap(
      enabled: !busy,
      hint: l.a11yMatchesScenes,
      child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: busy ? null : onTap,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.gold.withValues(alpha: on ? 0.16 : 0.07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.gold.withValues(alpha: on ? 0.9 : 0.45),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 11,
                height: 11,
                child: busy
                    ? const CircularProgressIndicator(
                        strokeWidth: 1.6, color: AppColors.goldBright)
                    : const Icon(Icons.auto_awesome_rounded,
                        size: 11, color: AppColors.goldBright),
              ),
              const SizedBox(width: 4),
              Text(
                busy
                    ? l.matchingScenes
                    : on
                        ? l.scenesChosen(matched.length, matched.length)
                        : l.matchScenesToVerses,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      height: 1.2,
                      color: AppColors.goldBright,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

/// The one piece of navigation in a four-hundred-scene library.
///
/// A rail of tabs and nothing else: no search field, no sort, no
/// folders. Each tab holds roughly thirty to fifty sceneries, which is
/// two thumb-flicks — small enough to look through, big enough that
/// opening one never feels like a dead end.
class _TabRail extends StatelessWidget {
  final List<String> tabs;
  final String current;
  final ValueChanged<String> onTap;

  /// A pill that stands before the tabs — the verse match. Same
  /// height as a tab, so the rail stays one row.
  final Widget? leading;

  const _TabRail({
    super.key,
    required this.tabs,
    required this.current,
    required this.onTap,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    if (tabs.isEmpty) return const SizedBox(height: 0);
    final l = L10n.of(context);
    final lead = leading == null ? 0 : 1;
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: tabs.length + lead,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          if (lead == 1 && i == 0) return leading!;
          final tab = tabs[i - lead];
          final on = tab == current;
          // A tab to a reader too: its name, and whether it is open.
          return A11yTap(
            selected: on,
            child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onTap(tab),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 15),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on
                    ? AppColors.gold.withValues(alpha: 0.13)
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(19),
                border: Border.all(
                  color: on ? AppColors.gold : AppColors.stroke,
                  width: on ? 1.5 : 1,
                ),
              ),
              child: Text(
                l.sceneTab(tab),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color:
                          on ? AppColors.textPrimary : AppColors.textSecondary,
                      fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                    ),
              ),
            ),
            ),
          );
        },
      ),
    );
  }
}

/// Turns the grid from one choice into several.
///
/// Off it is the quietest control on the screen — a reel has one
/// scenery unless somebody says otherwise, and this is not a decision
/// anyone has to make. On it stops being a label and becomes a count,
/// because from that moment the only thing worth knowing is how many
/// more the reel will take.
class _MultiScenePill extends StatefulWidget {
  final bool on;
  final int chosen;
  final int limit;
  final VoidCallback onTap;

  const _MultiScenePill({
    super.key,
    required this.on,
    required this.chosen,
    required this.limit,
    required this.onTap,
  });

  @override
  State<_MultiScenePill> createState() => _MultiScenePillState();
}

class _MultiScenePillState extends State<_MultiScenePill>
    with SingleTickerProviderStateMixin {
  /// One controller, two lives: off it drives the sheen's travel, on
  /// it drives the halo's breath. Slow either way — this control sits
  /// above a grid of moving scenery and must never compete with it.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4200),
  )..repeat();

  /// True when the platform asks for reduced motion: the pill is then
  /// shown at rest and the ticker parked.
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still == _still) return;
    _still = still;
    if (still) {
      _c.stop();
    } else {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// A light that crosses the pill once a cycle and then leaves it
  /// alone: the sweep takes the first third, the rest is dark. A
  /// steady glint would read as a loading state; one pass with a long
  /// pause after reads as an invitation.
  ///
  /// Painted as a band laid over the pill rather than as a `ShaderMask`:
  /// a mask has to blend with what it covers, and the blend modes that
  /// would do it are the ones Impeller is worst at — a pill that goes
  /// blank on Android is not worth a nicer-looking two lines. A plain
  /// gradient in a `Stack` is the same light with nothing to support.
  ///
  /// The band is moved by its own alignment rather than by gradient
  /// stops, so its three stops stay 0/0.5/1 and can never collapse
  /// into each other at the ends of the sweep.
  Widget _sheen(Widget child) {
    final t = (_c.value / 0.34).clamp(0.0, 1.0);
    if (t == 0 || t == 1) return child;
    final x = -1.8 + 3.6 * Curves.easeInOut.transform(t);
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment(x - 0.6, 0),
                    end: Alignment(x + 0.6, 0),
                    colors: [
                      AppColors.gold.withValues(alpha: 0),
                      AppColors.gold.withValues(alpha: 0.22),
                      AppColors.gold.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final on = widget.on;
    // A switch to a reader: named for what it does whether it is on
    // or off, with the count as its value once it is on.
    return A11yTap(
      label: l.multipleScenes,
      value: on ? l.scenesChosen(widget.chosen, widget.limit) : null,
      toggled: on,
      hint: l.a11yMultiSceneHint,
      onTap: widget.onTap,
      child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      // The pill animates every frame; the rail of scenery under it
      // must not repaint with it.
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, child) {
            // Off, the light travels across the pill. On, it stops
            // travelling and settles into a breath around it — the
            // control has been answered, so it stops asking.
            final breath = Curves.easeInOut.transform((_c.value * 2 - 1).abs());
            final lit = AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 11),
              decoration: BoxDecoration(
                color: on
                    ? AppColors.gold.withValues(alpha: 0.14)
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: on ? AppColors.gold : AppColors.stroke,
                  width: on ? 1.5 : 1,
                ),
                boxShadow: [
                  if (on && !_still)
                    BoxShadow(
                      color: AppColors.gold
                          .withValues(alpha: 0.10 + 0.22 * breath),
                      blurRadius: 10 + 10 * breath,
                    ),
                ],
              ),
              child: child,
            );
            if (on || _still) return lit;
            return _sheen(lit);
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                on ? Icons.filter_none_rounded : Icons.filter_none_outlined,
                size: 14,
                color: on ? AppColors.gold : AppColors.textSecondary,
              ),
              const SizedBox(width: 7),
              // Each new count arrives from below and the old one
              // leaves upward, so the number reads as counting rather
              // than as a label being swapped out.
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween(
                      begin: const Offset(0, 0.45),
                      end: Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                ),
                child: Text(
                  on
                      ? l.scenesChosen(widget.chosen, widget.limit)
                      : l.multipleScenes,
                  key: ValueKey(
                      on ? 'on-${widget.chosen}-${widget.limit}' : 'off'),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 12.5,
                        color: on
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                        fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

/// Lets go of every scenery chosen for the reel: a small round control
/// beside the several-sceneries pill, its height, the reset glyph alone.
/// The rail has no room for another word on a small phone, in German
/// least of all; a reader hears what it does.
class _ResetPill extends StatelessWidget {
  final VoidCallback onTap;

  const _ResetPill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return A11yTap(
      label: l.resetScenery,
      hint: l.a11yResetSceneryHint,
      onTap: onTap,
      child: Tooltip(
        message: l.resetScenery,
        excludeFromSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.stroke),
            ),
            child: const Icon(Icons.refresh_rounded,
                size: 16, color: AppColors.textSecondary),
          ),
        ),
      ),
    );
  }
}

/// A scenery's place in the run, in the corner its tick would take.
/// The number is the whole explanation of multi-scene picking: tiles
/// are numbered in the order they were tapped, and the reel plays them
/// that way.
class _OrderBadge extends StatelessWidget {
  final int order;
  const _OrderBadge(this.order);

  @override
  Widget build(BuildContext context) {
    // A pill rather than a circle: a reel can run through a hundred
    // sceneries, and three digits do not fit in a nineteen-pixel disc.
    // At one or two digits it is still round, which is all it ever
    // was.
    return Container(
      constraints: const BoxConstraints(minWidth: 19),
      height: 19,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: AppColors.gold,
        borderRadius: BorderRadius.circular(9.5),
      ),
      child: Text(
        '$order',
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: Color(0xFF14100A),
          height: 1,
        ),
      ),
    );
  }
}

/// The one line of advice on this screen: how many sceneries the
/// chosen verses actually want. Gold, and on its own, because it is
/// the only thing here that tells the user what to do next — inside
/// the blurb it read as more description of the screen.
class _SceneAdvice extends StatelessWidget {
  final String text;

  const _SceneAdvice({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(Icons.auto_awesome_rounded,
              size: 13, color: AppColors.gold),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 12.5,
                  height: 1.45,
                  color: AppColors.gold.withValues(alpha: 0.92),
                ),
          ),
        ),
      ],
    );
  }
}

/// Which shape of scenery the rail below is offering.
///
/// The library holds two families — upright and 16:9 — and only one of
/// them fits the frame the user picked, so the picker shows one at a
/// time and follows the frame by default: choosing the wide card opens
/// the 16:9 sceneries it was built for. Kept as small as a control can
/// be and still be found, because it is an override, not a decision
/// anyone has to make.
class _ShapeToggle extends StatelessWidget {
  final bool wide;
  final ValueChanged<bool> onTap;

  const _ShapeToggle({required this.wide, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        height: 30,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: AppColors.stroke),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ShapeSegment(
              icon: Icons.crop_portrait_rounded,
              label: l.sceneShapeVertical,
              selected: !wide,
              onTap: () => onTap(false),
            ),
            _ShapeSegment(
              icon: Icons.crop_16_9_rounded,
              label: l.sceneShapeWide,
              selected: wide,
              onTap: () => onTap(true),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShapeSegment extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ShapeSegment({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return A11yTap(
      selected: selected,
      child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? AppColors.gold.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 13,
                color:
                    selected ? AppColors.goldBright : AppColors.textSecondary),
            const SizedBox(width: 5),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    color: selected
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

/// One scenery in the grid.
///
/// Always draws its bundled poster, whether or not the full file has
/// ever been downloaded — so the grid is complete on a cold install and
/// a tap never leaves an empty square. A scene still on the server
/// carries a small download glyph; while it travels, a ring fills over
/// the poster it is replacing.
class _SceneTile extends StatelessWidget {
  final Scene scene;
  final bool selected;

  /// Place in a multi-scene run, 1-based; 0 when the reel has one
  /// scenery, which is when a tick says everything there is to say.
  final int order;

  /// Where the tile stands in its tab, 1-based, out of [count]. The
  /// tiles of a tab are named after the tab, so this is what tells
  /// a screen reader one "Sky" from the next.
  final int position;
  final int count;

  /// 0..1 while downloading, null otherwise.
  final double? progress;
  final VoidCallback onTap;

  const _SceneTile({
    required this.scene,
    required this.position,
    required this.count,
    required this.selected,
    required this.order,
    required this.progress,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final g = scene.gradientArgb;
    final downloading = progress != null;
    final remote = !scene.bundled && !SceneCatalog.isReadySync(scene);
    // The tile has no words on it at all, so everything the glyphs say
    // is said here: the scenery's name, that it moves, that it still
    // has to be fetched or is being fetched now, and its place in a
    // multi-scene run.
    final spoken = [
      l.a11yNthOf(l.sceneName(scene.id, scene.label), position, count),
      if (scene.isVideo) l.a11yVideo,
      if (downloading)
        l.a11yDownloading(((progress ?? 0) * 100).round())
      else if (remote)
        l.a11yNeedsDownload,
      if (order > 0) l.a11ySceneOrder(order),
    ].join('${l.comma} ');
    return A11yTap(
      label: spoken,
      selected: selected,
      onTap: onTap,
      child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      // Each poster behind a pane of glass that leans to the finger
      // and catches the light; the tap above it is untouched. Keyed by
      // the scenery, so a tab switch hands no tile another's glass.
      child: GlassTile(
        key: ValueKey(scene.id),
        radius: 14,
        selected: selected,
        child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.gold : AppColors.stroke,
            width: selected ? 2 : 1,
          ),
          boxShadow: [
            if (selected)
              BoxShadow(
                color: AppColors.gold.withValues(alpha: 0.14),
                blurRadius: 14,
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: Stack(
            fit: StackFit.expand,
            children: [
              GlassDepth(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // The measured gradient stands in for the poster
                    // for the one frame before it decodes, so tiles
                    // never flash white.
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(g[0]), Color(g[1])],
                        ),
                      ),
                    ),
                    Image.asset(scene.thumbAsset,
                        fit: BoxFit.cover, excludeFromSemantics: true),
                  ],
                ),
              ),
              if (downloading)
                Container(
                  color: Colors.black.withValues(alpha: 0.45),
                  alignment: Alignment.center,
                  child: SizedBox(
                    height: 26,
                    width: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      value: progress! > 0.02 ? progress : null,
                      color: AppColors.goldBright,
                      backgroundColor: Colors.white24,
                    ),
                  ),
                )
              else if (remote)
                const Positioned(
                  right: 5,
                  bottom: 5,
                  child: _Glyph(Icons.arrow_downward_rounded),
                ),
              if (scene.isVideo && !downloading)
                const Positioned(
                  left: 5,
                  bottom: 5,
                  child: _Glyph(Icons.play_arrow_rounded),
                ),
              if (order > 0)
                Positioned(top: 5, left: 5, child: _OrderBadge(order))
              else if (selected)
                const Positioned(
                  top: 5,
                  left: 5,
                  child: Icon(Icons.check_circle_rounded,
                      size: 18, color: AppColors.gold),
                ),
            ],
          ),
        ),
        ),
      ),
      ),
    );
  }
}

/// Small round marker over a poster: needs downloading, or moves.
class _Glyph extends StatelessWidget {
  final IconData icon;
  const _Glyph(this.icon);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 13, color: Colors.white),
    );
  }
}

/// How the scenery sits in the frame: full, or as a wide card.
///
/// Only the frame is chosen here. What the wide card opens up — its
/// corners, and what fills the band above and below it — is set on the
/// style step, against the verse it frames; until then the band is the
/// scenery itself, blurred.
///
/// Deliberately one small panel rather than a fifth wizard step: this
/// is a look, not a decision worth a screen of its own, and it belongs
/// next to the scenery it reshapes.
class _FormatPanel extends StatelessWidget {
  /// Fired by the two frame pills: the frame also decides which family
  /// of sceneries the grid should be showing.
  final ValueChanged<ReelLayout> onLayout;

  /// The first-run walkthrough's handle on the two frame pills.
  final GlobalKey? pillsKey;

  const _FormatPanel({
    required this.onLayout,
    this.pillsKey,
  });

  void _setLayout(ReelLayout l) {
    HapticFeedback.selectionClick();
    creationState.setLayout(l);
    onLayout(l);
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final wide = creationState.layout == ReelLayout.letterbox;
    // The two frames as two whole buttons, side by side: the one chosen
    // is gold to its edges. A reader hears the pair as the frame, and
    // each by its own name.
    return Semantics(
      container: true,
      header: true,
      label: l.frameFormat,
      child: Row(
        key: pillsKey,
        children: [
          Expanded(
            child: _FormatPill(
              icon: Icons.crop_portrait_rounded,
              label: l.frameFull,
              selected: !wide,
              onTap: () => _setLayout(ReelLayout.fullFrame),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _FormatPill(
              icon: Icons.crop_16_9_rounded,
              label: l.frameLetterbox,
              selected: wide,
              onTap: () => _setLayout(ReelLayout.letterbox),
            ),
          ),
        ],
      ),
    );
  }
}

/// One of the two frame choices.
class _FormatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FormatPill({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return A11yTap(
      label: label,
      selected: selected,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.gold.withValues(alpha: 0.14)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.gold : AppColors.stroke,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 18,
                  color: selected
                      ? AppColors.goldBright
                      : AppColors.textSecondary),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: selected
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Raised when the OS keeps refusing the gallery picker: says what is
/// blocked and hands the user to the one screen that can unblock it.
/// Same voice as the notifications banner in Settings — a promise the
/// app can't keep, not an error to apologise for.
class _GalleryBlockedBanner extends StatelessWidget {
  final VoidCallback onOpen;
  const _GalleryBlockedBanner({required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.38)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.no_photography_outlined,
              size: 21, color: AppColors.goldBright),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.galleryBlockedTitle,
                    style: t.bodyMedium?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(
                  l.galleryBlockedBody,
                  style: t.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.45),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 38,
                  child: OutlinedButton.icon(
                    onPressed: onOpen,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.goldBright,
                      side: BorderSide(
                          color: AppColors.gold.withValues(alpha: 0.55)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: Text(l.openSettings),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Last tile in the grid: "use your own" affordance, which becomes a
/// thumbnail of the picked photo/video once one is chosen.
class _UploadTile extends StatefulWidget {
  final ReelBackground? custom;
  final bool selected;
  final bool suspended;
  final VoidCallback onTap;
  final VoidCallback onReplace;

  /// Place in a multi-scene run, 1-based; 0 when it is not in it.
  final int order;

  /// Whether the grid is picking several sceneries — which is what
  /// turns the replace button into the way to add another of your own,
  /// since this tile only ever shows the last one picked.
  final bool multi;

  /// Set in the scenery grid, where the tile is one of three across
  /// and has no room for the full invitation.
  final bool compact;

  const _UploadTile({
    required this.custom,
    required this.selected,
    required this.suspended,
    required this.onTap,
    required this.onReplace,
    this.order = 0,
    this.multi = false,
    this.compact = false,
  });

  @override
  State<_UploadTile> createState() => _UploadTileState();
}

class _UploadTileState extends State<_UploadTile> {
  VideoPlayerController? _video;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  @override
  void didUpdateWidget(covariant _UploadTile old) {
    super.didUpdateWidget(old);
    if (widget.suspended != old.suspended) {
      if (widget.suspended) {
        _video?.dispose();
        _video = null;
        setState(() {});
      } else {
        _initVideo();
      }
      return;
    }
    if (widget.custom?.filePath != old.custom?.filePath) {
      _video?.dispose();
      _video = null;
      _initVideo();
    }
    if (widget.selected != old.selected) {
      widget.selected ? _video?.play() : _video?.pause();
    }
  }

  Future<void> _initVideo() async {
    final c0 = widget.custom;
    if (c0 == null || c0.fileIsImage || widget.suspended) return;
    VideoPlayerController? c;
    try {
      c = VideoPlayerController.file(File(c0.filePath!));
      await c.initialize().timeout(const Duration(seconds: 10));
      // The world may have moved while the decoder came up: the tile
      // suspended for the preview, the upload swapped for another, or a
      // second open of the same file already seated. Any of those and
      // this controller is one nobody will ever dispose — and a
      // hardware decoder the phone never gets back.
      if (!mounted ||
          widget.suspended ||
          widget.custom?.filePath != c0.filePath ||
          _video != null) {
        c.dispose();
        return;
      }
      c
        ..setLooping(true)
        ..setVolume(0);
      if (widget.selected) c.play();
      setState(() => _video = c);
    } catch (_) {
      c?.dispose();
      /* keep placeholder */
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    final custom = widget.custom;
    return _TileFrame(
      selected: widget.selected,
      order: widget.order,
      onTap: widget.onTap,
      // Before a photo is chosen the tile is a plain panel with a
      // glyph on it, which takes the glass's light in full; a photo
      // keeps the light low, like every poster beside it.
      surface: custom == null ? GlassSurface.flat : GlassSurface.picture,
      label: custom == null
          ? l.useYourOwn
          : (custom.fileIsImage ? l.yourPhoto : l.yourVideo),
      trailing: custom == null
          ? null
          : _CornerButton(
              // Picking several, this is how another of your own joins
              // the run rather than replaces what is in it.
              icon: widget.multi ? Icons.add_rounded : Icons.sync_rounded,
              tooltip: widget.multi ? l.addScenes : l.replace,
              onTap: widget.onReplace,
            ),
      child: custom == null
          // The frame's own strip already says "Use your own": a small
          // tile shows only the picture of it, a large one says where
          // it comes from.
          ? ExcludeSemantics(
              child: Container(
              color: AppColors.surface,
              padding: const EdgeInsets.all(6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_photo_alternate_outlined,
                      size: widget.compact ? 26 : 34,
                      color: AppColors.gold.withValues(alpha: 0.8)),
                  if (!widget.compact) ...[
                    const SizedBox(height: 8),
                    Text(
                      l.photoOrVideoFromGallery,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodySmall
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ],
              ),
              ),
            )
          : custom.fileIsImage
              ? Image.file(File(custom.filePath!),
                  fit: BoxFit.cover, excludeFromSemantics: true)
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(color: Colors.black),
                    if (_video != null)
                      FittedBox(
                        fit: BoxFit.cover,
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox(
                          width: _video!.value.size.width,
                          height: _video!.value.size.height,
                          child: VideoPlayer(_video!),
                        ),
                      ),
                  ],
                ),
    );
  }
}

/// Shared card chrome: rounded clip, gold selection ring, name strip,
/// all of it under the same glass as the posters beside it.
class _TileFrame extends StatelessWidget {
  final bool selected;

  /// Place in a multi-scene run, 1-based; 0 for a tick instead.
  final int order;
  final VoidCallback onTap;
  final String label;
  final Widget child;
  final Widget? trailing;

  /// What the glass is over: a photo, or the bare panel.
  final GlassSurface surface;

  const _TileFrame({
    required this.selected,
    required this.onTap,
    required this.label,
    required this.child,
    this.order = 0,
    this.trailing,
    this.surface = GlassSurface.picture,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    // The tile's own strip names it; the reader also gets its place
    // in a run, and what a tap does before a photo has been chosen.
    // The corner button stays a control of its own inside it.
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      value: order > 0 ? l.a11ySceneOrder(order) : null,
      hint: trailing == null ? l.a11yOpensGallery : null,
      child: GlassTile(
        radius: 20,
        selected: selected,
        surface: surface,
        child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? AppColors.gold : AppColors.stroke,
          width: selected ? 2 : 1,
        ),
        boxShadow: [
          if (selected)
            BoxShadow(
              color: AppColors.gold.withValues(alpha: 0.14),
              blurRadius: 18,
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(19),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              GlassDepth(child: child),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 18, 10, 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.6),
                      ],
                    ),
                  ),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.white),
                  ),
                ),
              ),
              if (order > 0)
                Positioned(top: 8, left: 8, child: _OrderBadge(order))
              else if (selected)
                const Positioned(
                  top: 8,
                  left: 8,
                  child: Icon(Icons.check_circle_rounded,
                      size: 20, color: AppColors.gold),
                ),
              if (trailing != null)
                Positioned(top: -2, right: -2, child: trailing!),
            ],
          ),
        ),
      ),
        ),
      ),
    );
  }
}

class _CornerButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _CornerButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // The tooltip is for a long press by eye; the reader gets the same
    // words as the button's name. The finger gets a target the size a
    // finger needs, around a glyph that stays small.
    return A11yTap(
      label: tooltip,
      onTap: onTap,
      child: Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 16, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
