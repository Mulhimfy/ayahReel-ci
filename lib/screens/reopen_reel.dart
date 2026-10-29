import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/debug_log.dart';
import '../data/fatiha_data.dart';
import '../data/models.dart';
import '../data/quran_repository.dart';
import '../data/reel_library.dart';
import '../data/reel_recipe.dart';
import '../data/scene_catalog.dart';
import '../l10n/l10n.dart';
import '../state/creation_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_toast.dart';
import 'background_screen.dart';
import 'style_screen.dart';

/// Opens a finished reel for editing: puts its recipe back onto the
/// creation state, brings its sceneries back onto the device if they
/// have gone, and lands in the preview with everything as it was.
///
/// The one thing that cannot come back is the exact export — the
/// styling key decides the file, and a reel reopened and left alone
/// produces the same key, so Save on an untouched reel is answered
/// with the copy the library already holds rather than a second one.
abstract final class ReelReopener {
  static Future<void> open(BuildContext context, SavedReel reel) async {
    final l = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final recipe = reel.recipe;
    if (recipe == null) {
      messenger.showSnackBar(toast(l.reelNotEditable, tone: ToastTone.problem));
      return;
    }
    Reciter? reciter;
    for (final r in reciters) {
      if (r.id == recipe.reciterId) reciter = r;
    }
    if (reciter == null) {
      // An upload's stand-in voice is not in the list, and its file
      // may be gone; the reel plays, but it does not reopen.
      messenger.showSnackBar(toast(l.reopenFailed, tone: ToastTone.problem));
      return;
    }
    HapticFeedback.selectionClick();

    // The sceneries may need fetching, which may take a while, so the
    // wait is shown — and not dismissable, because half a reel is not
    // a state anything downstream can be handed.
    final progress = ValueNotifier<String>(l.reopeningReel);
    final navigator = Navigator.of(context);
    // Held as a route, so it is this dialog that is closed afterwards and
    // nothing else: a widget or notification tap meanwhile pops back to
    // Home, and a blind pop would then take whatever it opened.
    final wait = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Center(
          child: Container(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
            decoration: BoxDecoration(
              color: AppColors.surfaceRaised,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.stroke),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.4, color: AppColors.gold),
                ),
                const SizedBox(height: 14),
                // Live: the wait is undismissable, so the reader is
                // told what it is waiting for, and when that changes.
                ValueListenableBuilder<String>(
                  valueListenable: progress,
                  builder: (context, s, _) => Semantics(
                    liveRegion: true,
                    child: Text(
                      s,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.textPrimary),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    unawaited(navigator.push(wait));

    List<(int, ReelBackground)> resolved = const [];
    try {
      resolved = await _resolveScenes(recipe, progress);
    } catch (e, s) {
      rlogError('reopen: scenes', e, s);
    }
    // The dialog: closed by route rather than by a context that may
    // have gone with the screen underneath. Already gone means the app
    // was sent somewhere else meanwhile, and the reopen is dropped.
    if (!wait.isActive) return;
    navigator.removeRoute(wait);
    if (!context.mounted) return;

    recipe.applyStyling(creationState, reciter);
    if (resolved.isEmpty) {
      // The last reel's sceneries would otherwise still be seated, and
      // the picker would open on them with its door already open.
      creationState.dropScenes((_) => false);
    }
    recipe.applyScenes(creationState, [for (final r in resolved) r.$2],
        from: [for (final r in resolved) r.$1]);
    QuranRepository.prefetchRecitation(reciter, recipe.surah,
        startAyah: recipe.startAyah, endAyah: recipe.endAyah);
    rlog('reopen: ${reel.id} -> ${resolved.length}/${recipe.scenes.length} '
        'scenes');
    if (resolved.isEmpty) {
      // Nothing to show the verse on: the scenery step is where that
      // is fixed, and it opens on the reel's own frame and styling.
      messenger.showSnackBar(toast(l.pickForNewFrame));
      await navigator.push(
        MaterialPageRoute(builder: (_) => const BackgroundScreen()),
      );
      return;
    }
    // Into the style step rather than straight to the reel.
    //
    // This is the *edit* door — My Reels and the player both have a
    // separate one for watching a reel again — so it should open on
    // the screen where a reel is changed, with every choice the recipe
    // carried already seated: the faces, the two colours, the grade.
    // Landing on the preview instead left all of that a screen behind
    // a back button that, from here, leaves the flow entirely.
    //
    // The trim is the one thing the style step knows nothing about, so
    // it travels on to the preview from here.
    await navigator.push(
      MaterialPageRoute(
        builder: (_) => StyleScreen(
          initialTrimMs: recipe.trimMs,
          // Straight off the library: there is no scenery picker under
          // this route, and the reel screen's "Add sceneries" has to
          // know that or it unwinds the whole session.
          sceneryBelow: false,
        ),
      ),
    );
  }

  /// Every scenery the recipe names that can still be had, in order:
  /// the user's own files if they still exist, bundled scenes as they
  /// are, and cached or re-downloaded catalog scenes.
  ///
  /// Each comes with its place in the recipe, which is where its weight
  /// is: a scenery that can't be had leaves a gap, not a shift.
  static Future<List<(int, ReelBackground)>> _resolveScenes(
      ReelRecipe recipe, ValueNotifier<String> progress) async {
    await SceneCatalog.load();
    final out = <(int, ReelBackground)>[];
    for (var i = 0; i < recipe.scenes.length; i++) {
      final ref = recipe.scenes[i];
      if (ReelRecipe.isFileRef(ref)) {
        final path = ReelRecipe.filePathOf(ref);
        if (!File(path).existsSync()) continue;
        out.add((
          i,
          ReelBackground.deviceFile(
            id: 'custom_${path.hashCode.toRadixString(16)}',
            name: ReelRecipe.isImageRef(ref) ? 'Your photo' : 'Your video',
            filePath: path,
            fileIsImage: ReelRecipe.isImageRef(ref),
          ),
        ));
        continue;
      }
      final scene = SceneCatalog.byId(ref);
      if (scene == null) continue;
      if (scene.bundled) {
        out.add((i, SceneCatalog.background(scene)));
        continue;
      }
      var file = await SceneCatalog.cachedFile(scene);
      if (file == null) {
        progress.value = L10n.current.reopenFetchingScenes;
        file = await SceneCatalog.download(scene);
      }
      if (file == null) continue;
      out.add((i, SceneCatalog.background(scene, file: file)));
    }
    return out;
  }
}
