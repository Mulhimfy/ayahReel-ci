import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/scene_catalog.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import 'a11y.dart';
import 'glass_tile.dart';
import 'scene_poster_image.dart';

/// The scenery library, for a card.
///
/// The same catalog the reels pick from — one catalog, one set of
/// files, one download cache. A scenery added to `catalog.json`
/// appears here and in the reel picker on the same build, because
/// neither side keeps a list of its own; see [SceneCatalog].
///
/// What is different from the reel picker is what a card can use.
/// Everything in the library is offered, wide sceneries included: a
/// card crops the picture rather than letterboxing it, so the shape a
/// scenery was shot in stops being a decision the user has to make
/// and becomes one they can adjust afterwards, by dragging the
/// picture.
Future<String?> showCardSceneSheet(
  BuildContext context, {
  String? selectedId,
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _CardSceneSheet(selectedId: selectedId),
  );
}

class _CardSceneSheet extends StatefulWidget {
  final String? selectedId;
  const _CardSceneSheet({this.selectedId});

  @override
  State<_CardSceneSheet> createState() => _CardSceneSheetState();
}

class _CardSceneSheetState extends State<_CardSceneSheet> {
  String _tab = '';

  /// Whether the catalog is still being read.
  ///
  /// It has to be read here rather than assumed loaded, and that is
  /// the whole of what this state is for: [SceneCatalog] is a lazy
  /// singleton and the reel flow is what used to warm it, so a user
  /// who opened the Cards tab first and asked for scenery got a grid
  /// of nothing — no tabs, no tiles, no error. A sheet that needs the
  /// catalog loads the catalog.
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await SceneCatalog.load();
    if (!mounted) return;
    setState(() {
      _tab = _openingTab;
      _loading = false;
    });
  }

  String get _openingTab {
    final chosen = widget.selectedId == null
        ? null
        : SceneCatalog.byId(widget.selectedId!)?.tab;
    if (chosen != null) return chosen;
    final tabs = SceneCatalog.tabs;
    return tabs.isEmpty ? '' : tabs.first;
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final t = Theme.of(context).textTheme;
    final tabs = SceneCatalog.tabs;
    final scenes = SceneCatalog.inTab(_tab);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.82,
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.stroke,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
            child: Row(
              children: [
                A11yHeader(
                    child: Text(l.cardScenery, style: t.titleMedium)),
                const Spacer(),
              ],
            ),
          ),
          if (_loading)
            const Expanded(
              child: Center(
                child: CircularProgressIndicator(color: AppColors.gold),
              ),
            )
          else if (tabs.isEmpty)
            // [SceneCatalog.load] swallows a failure and marks itself
            // loaded, so without this the spinner resolves into the
            // same nothing it was added to fix — no tabs, no tiles, no
            // error, one frame later.
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    l.sceneCatalogEmpty,
                    textAlign: TextAlign.center,
                    style:
                        t.bodyMedium?.copyWith(color: AppColors.textSecondary),
                  ),
                ),
              ),
            )
          else ...[
            SizedBox(
              height: 46,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                itemCount: tabs.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final selected = tabs[i] == _tab;
                  return Center(
                    child: A11yTap(
                      label: l.sceneTab(tabs[i]),
                      selected: selected,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _tab = tabs[i]);
                      },
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _tab = tabs[i]);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: selected
                                ? AppColors.gold.withValues(alpha: 0.14)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: selected
                                  ? AppColors.gold.withValues(alpha: 0.55)
                                  : AppColors.stroke,
                            ),
                          ),
                          child: Text(
                            l.sceneTab(tabs[i]),
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w500,
                              color: selected
                                  ? AppColors.goldBright
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.72,
                ),
                itemCount: scenes.length,
                itemBuilder: (context, i) => _Tile(
                  scene: scenes[i],
                  selected: scenes[i].id == widget.selectedId,
                  position: i + 1,
                  count: scenes.length,
                  onTap: () => Navigator.of(context).pop(scenes[i].id),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One scenery. Always its bundled poster, whether or not the full
/// file has ever been downloaded — so the grid is complete on a cold
/// install, and the tap that needs a download is the one that starts
/// it.
class _Tile extends StatelessWidget {
  final Scene scene;
  final bool selected;
  final int position;
  final int count;
  final VoidCallback onTap;

  const _Tile({
    required this.scene,
    required this.selected,
    required this.position,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final name = l.sceneName(scene.id, scene.label);
    return A11yTap(
      label: l.a11yNthOf(name, position, count),
      selected: selected,
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        // The same glass as the reel's scenery picker: one library,
        // one way of handling it.
        child: GlassTile(
          key: ValueKey(scene.id),
          radius: 12,
          selected: selected,
          child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              GlassDepth(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(scene.gradientArgb.first),
                            Color(scene.gradientArgb.last),
                          ],
                        ),
                      ),
                    ),
                    // A poster that is missing is a poster: the
                    // gradient under it is measured from the scenery
                    // itself.
                    ScenePosterImage(scene),
                  ],
                ),
              ),
              if (scene.isVideo)
                const PositionedDirectional(
                  top: 6,
                  end: 6,
                  child: Icon(Icons.movie_creation_outlined,
                      size: 13, color: Colors.white70),
                ),
              if (selected)
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.goldBright, width: 2),
                    borderRadius: BorderRadius.circular(12),
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
