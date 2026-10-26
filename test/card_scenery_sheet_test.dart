import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/scene_catalog.dart';
import 'package:ayah_reels/l10n/l10n.dart';
import 'package:ayah_reels/theme/app_theme.dart';
import 'package:ayah_reels/widgets/card_scene_sheet.dart';

/// The card composer's scenery library, opened cold.
///
/// [SceneCatalog] is a lazy singleton and the reel flow is what used
/// to warm it — `background_screen` loads it on the way in. A card
/// never goes through there, so somebody who opened the Cards tab
/// first, made a card and asked for scenery got a sheet with no tabs
/// and no tiles: not an error, not an empty state, just nothing. This
/// test is that user, which is why it must be the only test in its
/// file: a catalog another test has already loaded cannot be cold.
void main() {
  testWidgets('the sheet loads the catalog itself, from cold', (t) async {
    expect(SceneCatalog.all, isEmpty,
        reason: 'something loaded the catalog before this test ran');
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);

    await t.pumpWidget(MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorScheme: const ColorScheme.dark(
            primary: AppColors.gold, surface: AppColors.surface),
      ),
      localizationsDelegates: const [L10n.delegate],
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showCardSceneSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pump();

    // The read is asynchronous, so the sheet says it is working rather
    // than saying there is nothing.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    for (var i = 0; i < 20 && SceneCatalog.all.isEmpty; i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump();
    }
    await t.pumpAndSettle();

    expect(SceneCatalog.all, isNotEmpty, reason: 'the catalog never loaded');
    expect(find.byType(CircularProgressIndicator), findsNothing);
    // The first tab is lit and its sceneries are on screen.
    const l = L10n.en;
    expect(find.text(l.sceneTab(SceneCatalog.tabs.first)), findsOneWidget);
    expect(find.byType(GridView), findsOneWidget);
    final grid = t.widget<GridView>(find.byType(GridView));
    expect((grid.childrenDelegate as SliverChildBuilderDelegate).childCount,
        SceneCatalog.inTab(SceneCatalog.tabs.first).length);
    expect(find.byType(Image), findsWidgets);
  });
}
