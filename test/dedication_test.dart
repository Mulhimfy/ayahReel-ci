import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/dedication.dart';
import 'package:ayah_reels/data/fatiha_data.dart';
import 'package:ayah_reels/data/reel_library.dart';
import 'package:ayah_reels/data/reel_recipe.dart';
import 'package:ayah_reels/l10n/l10n.dart';
import 'package:ayah_reels/render/ayah_rasterizer.dart';
import 'package:ayah_reels/render/letterbox_layout.dart';
import 'package:ayah_reels/state/creation_state.dart';
import 'package:ayah_reels/theme/app_theme.dart';
import 'package:ayah_reels/widgets/dedicate_sheet.dart';
import 'package:ayah_reels/widgets/reel_watermark.dart';

/// A reel or a card made for somebody.
///
/// Two things here are load-bearing beyond the feature itself. A
/// dedication is *burned into the frame*, so it has to reach the render
/// key — and it has to reach it in a way that leaves every reel nobody
/// dedicated on the key it already has, or the first launch after this
/// update re-encodes everybody's library. And the line is *placed* —
/// along the bottom of a reel, above the mark on a card — by
/// arithmetic the preview and the exporter share, so where it lands
/// is pinned here rather than discovered in somebody's finished file.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final loader = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter.ttf'));
    await loader.load();
  });

  group('the value', () {
    test('a name is one line, trimmed, and capped', () {
      final d = Dedication.none.copyWith(name: '  Umm   Salamah \n ');
      expect(d.name, 'Umm Salamah');
      final long = Dedication.none.copyWith(name: 'x' * 90);
      expect(long.name.length, Dedication.maxName);
      expect(Dedication.none.copyWith(name: '   ').isEmpty, isTrue);
    });

    test('no dedication is no key at all', () {
      // The property the whole library depends on: a reel nobody
      // dedicated keys exactly as it always did.
      expect(Dedication.none.key, isEmpty);
      expect(Dedication.none.copyWith(name: 'Aisha').key, isNotEmpty);
    });

    test('two dedications differ when anything about them differs', () {
      final gift = Dedication.none.copyWith(name: 'Aisha');
      final sadaqah = gift.copyWith(kind: DedicationKind.sadaqah);
      final other = gift.copyWith(name: 'Fatima');
      expect(gift.key, isNot(sadaqah.key));
      expect(gift.key, isNot(other.key));
      expect(gift, isNot(sadaqah));
      expect(gift, gift.copyWith(name: 'Aisha'));
    });

    test('it survives a round trip through the file', () {
      const d = Dedication(kind: DedicationKind.sadaqah, name: 'Fatima');
      final back = Dedication.fromJson(d.toJson());
      expect(back, d);
      // And a file that predates the field opens with none.
      expect(Dedication.fromJson(null), Dedication.none);
      expect(Dedication.fromJson(const {'kind': 'bequest', 'name': 'x'}).kind,
          DedicationKind.gift);
    });
  });

  group('the wording', () {
    test('every language writes both intentions, with the name in them',
        () {
      for (final lang in AppLang.values) {
        final l = L10n(lang);
        for (final kind in DedicationKind.values) {
          final line = l.dedicationLine(kind, 'Maryam');
          expect(line, contains('Maryam'),
              reason: '${lang.code}/${kind.name} lost the name');
          expect(line.length, greaterThan('Maryam'.length + 3));
        }
        // The two are not the same sentence in any language: a gift
        // and a sadaqah jariyah are not the same act.
        expect(l.dedicationLine(DedicationKind.gift, 'Maryam'),
            isNot(l.dedicationLine(DedicationKind.sadaqah, 'Maryam')));
      }
    });

    test('the shared message speaks to the person and carries the links',
        () {
      for (final lang in AppLang.values) {
        final l = L10n(lang);
        for (final kind in DedicationKind.values) {
          final message = l.dedicationShareMessage(kind, 'Maryam');
          expect(message, contains('Maryam'));
          // A gift nobody can answer with one of their own is a gift
          // that stops where it lands.
          expect(message, contains('apps.apple.com'));
          expect(message, contains('play.google.com'));
        }
      }
    });
  });

  group('a card\'s mark carries it', () {
    testWidgets('a dedicated mark is taller, and says the line', (t) async {
      Future<Size> measure(String dedication) async {
        await t.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: Localizations(
            locale: const Locale('en'),
            delegates: const [
              L10n.delegate,
              DefaultWidgetsLocalizations.delegate,
            ],
            child: Center(
              child: ReelWatermarkMark(
                  width: 1080, dedication: dedication),
            ),
          ),
        ));
        await t.pumpAndSettle();
        return t.getSize(find.byType(ReelWatermarkMark));
      }

      final bare = await measure('');
      final dedicated = await measure('A gift for Maryam');
      expect(find.text('A gift for Maryam'), findsOneWidget);
      expect(dedicated.height, greaterThan(bare.height));
      // The constant the geometry is computed from has to describe the
      // widget: preview and export both place the mark from it.
      expect(dedicated.height - bare.height,
          closeTo(ReelWatermarkMark.dedicationBlock, 12));
    });

    testWidgets('a long dedication is ellipsised rather than widened',
        (t) async {
      await t.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: ReelWatermarkMark(
            width: 1080,
            dedication: 'Sadaqah jariyah for ${'Abd ar-Rahman ' * 6}',
          ),
        ),
      ));
      await t.pumpAndSettle();
      // An overlay wider than the video is one FFmpeg silently clips.
      expect(t.getSize(find.byType(ReelWatermarkMark)).width,
          lessThanOrEqualTo(1080));
    });

  });

  // On a reel the line is its own layer along the bottom edge, and the
  // mark is the bare mark wherever the verse was dragged: the
  // dedication used to ride above the mark, which put it wherever the
  // verse happened to be, and a dedication is the last line on the
  // page, not a caption under the verse.
  group('a reel writes it along the bottom', () {
    Widget host(Widget child) => Directionality(
          textDirection: TextDirection.ltr,
          child: Localizations(
            locale: const Locale('en'),
            delegates: const [
              L10n.delegate,
              DefaultWidgetsLocalizations.delegate,
            ],
            child: MediaQuery(
              data: const MediaQueryData(
                  size: Size(1080, 1920), devicePixelRatio: 1.0),
              child: Center(
                child: OverflowBox(
                  minWidth: 0,
                  maxWidth: double.infinity,
                  minHeight: 0,
                  maxHeight: double.infinity,
                  child: SizedBox(width: 1080, height: 1920, child: child),
                ),
              ),
            ),
          ),
        );

    testWidgets('the preview draws it its inset above the edge, centred',
        (t) async {
      await t.pumpWidget(host(const ReelDedication(
          width: 1080, line: 'Sadaqah jariyah for Maryam')));
      await t.pumpAndSettle();
      expect(find.text('Sadaqah jariyah for Maryam'), findsOneWidget);
      final frame = t.getRect(find.byType(ReelDedication));
      final line = t.getRect(find.byType(ReelDedicationLine));
      expect(frame.bottom - line.bottom,
          closeTo(ReelDedication.frameInset, 0.01));
      expect(line.center.dx, closeTo(frame.center.dx, 0.01));
      // The constant the exporter's geometry is computed from has to
      // describe the widget.
      expect(line.height, closeTo(ReelDedication.lineHeight, 8));
    });

    testWidgets('nothing is drawn for a reel nobody dedicated', (t) async {
      await t.pumpWidget(
          host(const ReelDedication(width: 1080, line: '')));
      expect(find.byType(ReelDedicationLine), findsNothing);
    });

    test('the mark no longer moves for it', () {
      // The full-frame mark stands at the floor, and stands there the
      // same with a dedication on the reel as without: the line is
      // somewhere else entirely now.
      const verseBottom = 900.0;
      expect(
        ReelWatermark.insetFor(null, verseBottom: verseBottom),
        ReelWatermark.fullFrameInset,
      );
      expect(ReelWatermark.insetFor(null), ReelWatermark.fullFrameInset);
    });

    test('it clears the verse\'s floor in letterbox', () {
      // The verse may come down as far as the band's bottom padding
      // off the edge. The line, and a verse gap over it, fit inside
      // that margin — or a verse dragged to the floor lands on the
      // name.
      expect(
        ReelDedication.frameInset +
            ReelDedication.lineHeight +
            ReelWatermark.verseGap,
        lessThanOrEqualTo(LetterboxGeometry.bandBottomPadding),
      );
      // And it is the bottom of the reel, not a lower third.
      expect(ReelDedication.frameInset, lessThan(LetterboxGeometry.frameH / 16));
    });

    test('the exporter offsets it by the margin baked into its PNG', () {
      // FFmpeg overlays the *padded* PNG at H-h-dedicationInset, which
      // puts the glyphs at H-frameInset only while these agree.
      expect(
        AyahRasterizer.dedicationInset + ReelWatermarkMark.shadowMargin,
        ReelDedication.frameInset,
      );
    });
  });

  group('the sheet', () {
    testWidgets('starts a new dedication on sadaqah jariyah', (t) async {
      const l = L10n.en;
      late BuildContext ctx;
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: Builder(builder: (c) {
          ctx = c;
          return const Scaffold();
        }),
      ));
      final result = showDedicateSheet(ctx, dedication: Dedication.none);
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'Fatima');
      await t.pumpAndSettle();
      // The name is written as a sadaqah until somebody picks gift.
      expect(find.text(l.dedicationLine(DedicationKind.sadaqah, 'Fatima')),
          findsOneWidget);
      await t.tap(find.text(l.save));
      await t.pumpAndSettle();
      final d = await result;
      expect(d!.kind, DedicationKind.sadaqah);
      expect(d.name, 'Fatima');
      // Not the reel's hint about dragging: this sheet was not asked
      // for a movable line.
      expect(find.text(l.dedicateMoveHint), findsNothing);
    });

    testWidgets('reopens on the intention a dedication was made with',
        (t) async {
      const l = L10n.en;
      late BuildContext ctx;
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: Builder(builder: (c) {
          ctx = c;
          return const Scaffold();
        }),
      ));
      showDedicateSheet(ctx,
          dedication: const Dedication(
              kind: DedicationKind.gift, name: 'Aisha'),
          movable: true);
      await t.pumpAndSettle();
      expect(find.text(l.dedicationLine(DedicationKind.gift, 'Aisha')),
          findsOneWidget);
      expect(find.text(l.dedicateMoveHint), findsOneWidget);
    });
  });

  group('a dragged line', () {
    testWidgets('is centred where it was put, and kept inside the frame',
        (t) async {
      // Smaller than the test window, which would clamp it.
      const w = 300.0, h = 533.0;
      Future<Rect> lineAt(Offset at) async {
        final key = GlobalKey();
        await t.pumpWidget(MaterialApp(
          home: Center(
            child: SizedBox(
              width: w,
              height: h,
              child: Stack(children: [
                ReelDedication(
                  width: w,
                  line: 'Sadaqah jariyah for Maryam',
                  at: at,
                  lineKey: key,
                ),
              ]),
            ),
          ),
        ));
        final frame = t.getRect(find.byType(Stack).last);
        return t.getRect(find.byKey(key)).shift(-frame.topLeft);
      }

      final mid = await lineAt(const Offset(0.5, 0.3));
      expect(mid.center.dx, closeTo(w * 0.5, 0.5));
      expect(mid.center.dy, closeTo(h * 0.3, 0.5));

      // Dragged into a corner, it stops the PNG's margin short of the
      // edges, where the exporter's clamp stops it.
      const margin =
          ReelWatermarkMark.shadowMargin * w / ReelWatermarkMark.referenceWidth;
      final corner = await lineAt(const Offset(0, 1));
      expect(corner.left, closeTo(margin, 0.5));
      expect(corner.bottom, closeTo(h - margin, 0.5));
    });

    test('on a pale band it is dark, on the card it is scenery', () {
      final geo = LetterboxGeometry.of(16 / 9);
      final onCard = Offset(0.5, (geo.cardY + geo.cardH / 2) / 1920);
      expect(
          ReelDedication.onLightAt(onCard,
              onLightGround: true, letterbox: geo),
          isFalse);
      expect(
          ReelDedication.onLightAt(null, onLightGround: true, letterbox: geo),
          isTrue);
      expect(
          ReelDedication.onLightAt(const Offset(0.5, 0.97),
              onLightGround: true, letterbox: geo),
          isTrue);
      expect(
          ReelDedication.onLightAt(onCard,
              onLightGround: false, letterbox: geo),
          isFalse);
    });
  });

  group('it travels with the reel', () {
    test('the recipe keeps it, and puts it back', () {
      creationState
        ..startNewReel()
        ..setDedication(
            const Dedication(kind: DedicationKind.sadaqah, name: 'Fatima'));
      final recipe = ReelRecipe.capture(creationState);
      expect(recipe.dedication.name, 'Fatima');
      final back = ReelRecipe.fromJson(recipe.toJson());
      expect(back.dedication, recipe.dedication);

      // A new reel is nobody's until it is said to be: a name carried
      // over would put a stranger's grandmother on somebody else's
      // verse.
      creationState.startNewReel();
      expect(creationState.dedication, Dedication.none);

      back.applyStyling(creationState, reciters.first);
      expect(creationState.dedication.name, 'Fatima');
      expect(creationState.dedication.kind, DedicationKind.sadaqah);
      creationState.startNewReel();
    });

    test('a saved reel is shared with the message its dedication asks '
        'for', () {
      const l = L10n.en;
      SavedReel reel({Dedication dedication = Dedication.none}) => SavedReel(
            id: '1',
            fileName: 'reel_1.mp4',
            reciterName: 'Alafasy',
            surahName: 'Al-Kahf',
            startAyah: 1,
            endAyah: 5,
            gradientArgb: const [0xFF000000, 0xFF111111],
            createdAt: DateTime(2026),
            recipe: ReelRecipe.fromJson({
              ...ReelRecipe.capture(creationState).toJson(),
              if (dedication.isNotEmpty) 'dedication': dedication.toJson(),
            }),
          );
      expect(reel().shareCaption(l), contains('Al-Kahf'));
      expect(reel().shareCaption(l), isNot(contains('apps.apple.com')));
      final gifted = reel(
          dedication: const Dedication(name: 'Aisha')).shareCaption(l);
      expect(gifted, contains('Aisha'));
      expect(gifted, contains('apps.apple.com'));
      // A reel from before the field existed still shares as it did.
      expect(
        SavedReel(
          id: '2',
          fileName: 'reel_2.mp4',
          reciterName: 'Alafasy',
          surahName: 'Al-Kahf',
          startAyah: 1,
          endAyah: 5,
          gradientArgb: const [0xFF000000, 0xFF111111],
          createdAt: DateTime(2026),
        ).shareCaption(l),
        contains('Al-Kahf'),
      );
    });
  });
}
