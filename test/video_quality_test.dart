import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/settings_service.dart';
import 'package:ayah_reels/render/video_renderer.dart';
import 'package:ayah_reels/screens/settings_screen.dart';
import 'package:ayah_reels/theme/app_theme.dart';

/// High-quality video: a switch in Settings' Customize menu that moves
/// every export up the encoder's bitrate ladder, at the cost of larger
/// files — and so off unless the user turns it on.
void main() {
  tearDown(() => SettingsService.state.value = AppSettings.defaults);

  group('the setting', () {
    test('is off by default, and on an install that predates it', () {
      expect(AppSettings.defaults.highQualityVideo, isFalse);
      expect(AppSettings.fromJson(const {}).highQualityVideo, isFalse);
    });

    test('survives a round trip through the settings file', () {
      for (final on in [true, false]) {
        final back = AppSettings.fromJson(
            AppSettings.defaults.copyWith(highQualityVideo: on).toJson());
        expect(back.highQualityVideo, on);
      }
    });
  });

  group('the encoder', () {
    const minute = 60000;
    String hw(int ms, {bool high = false}) => VideoRenderer.videoCodec(
        hardware: true, reelMs: ms, threads: 4, high: high);
    String x264(int ms, {bool high = false}) => VideoRenderer.videoCodec(
        hardware: false, reelMs: ms, threads: 4, high: high);

    test('standard is the ladder it always was', () {
      expect(hw(minute), contains('-b:v 6M '));
      expect(hw(10 * minute), contains('-b:v 4M '));
      expect(hw(30 * minute), contains('-b:v 3M '));
      expect(hw(60 * minute), contains('-b:v 2M '));
      expect(x264(minute), contains('-crf 20 '));
      expect(x264(60 * minute), contains('-crf 26 '));
    });

    test('lean is only for the smallest phones, and only on x264', () {
      expect(x264(minute), isNot(contains('-x264-params')));
      final lean = VideoRenderer.videoCodec(
          hardware: false, reelMs: minute, threads: 2, lean: true);
      expect(lean, contains('-crf 20 -threads 2 -maxrate:v 12M -bufsize:v 12M '
          '-x264-params rc-lookahead=5:mbtree=1:bframes=0:sync-lookahead=0 '));
      // The tree is what keeps the grain out of every frame: without it
      // a lean reel ran 26 Mbps and phones would not play it.
      expect(lean, isNot(contains('mbtree=0')));
      expect(lean, isNot(contains('rc-lookahead=0')));
      // And faster: the slowest phones run it, on two threads.
      expect(lean, contains('-preset superfast '));
      expect(x264(minute), contains('-preset veryfast '));
      expect(
          VideoRenderer.videoCodec(
              hardware: true, reelMs: minute, threads: 2, lean: true),
          isNot(contains('x264')));
    });

    test('x264 has a ceiling a Level 4.0 decoder can play', () {
      // Twice the hardware rate at each length, over a one-second
      // buffer: under High@4.0's 25 Mbps and its 31.25 Mbit buffer.
      for (final (ms, cap) in [
        (minute, '12M'),
        (10 * minute, '8M'),
        (30 * minute, '6M'),
        (60 * minute, '4M'),
      ]) {
        for (final high in [false, true]) {
          for (final lean in [false, true]) {
            expect(
                VideoRenderer.videoCodec(
                    hardware: false,
                    reelMs: ms,
                    threads: 2,
                    high: high,
                    lean: lean),
                contains('-maxrate:v $cap -bufsize:v $cap '));
          }
        }
      }
      // The hardware encoder has a rate of its own.
      expect(hw(minute), isNot(contains('-maxrate')));
    });

    test('high doubles a short reel and lifts a long one a rung', () {
      expect(hw(minute, high: true), contains('-b:v 12M '));
      expect(hw(10 * minute, high: true), contains('-b:v 6M '));
      expect(hw(30 * minute, high: true), contains('-b:v 4M '));
      expect(hw(60 * minute, high: true), contains('-b:v 3M '));
      expect(x264(minute, high: true), contains('-crf 17 '));
      expect(x264(60 * minute, high: true), contains('-crf 24 '));
    });

    test('changes the rate and nothing else', () {
      expect(hw(minute, high: true).replaceFirst('12M', '6M'), hw(minute));
      expect(x264(minute, high: true).replaceFirst('-crf 17', '-crf 20'),
          x264(minute));
    });
  });

  testWidgets('the switch sits in the Customize menu, and stays open',
      (t) async {
    t.view.physicalSize = const Size(390 * 3, 844 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: SettingsScreen(permissionCheck: () async => true),
      ),
    ));
    await t.pump();

    expect(find.text('High-quality video'), findsNothing);
    await t.scrollUntilVisible(find.text('Customize'), 200);
    await t.tap(find.text('Customize'));
    await t.pumpAndSettle();
    expect(find.text('High-quality video'), findsOneWidget);
    expect(find.text('Sharper, larger files'), findsOneWidget);

    await t.tap(find.text('High-quality video'));
    await t.pumpAndSettle();
    expect(SettingsService.state.value.highQualityVideo, isTrue);
    // Still open, so the switch is seen to move.
    expect(find.text('High-quality video'), findsOneWidget);

    await t.tap(find.text('High-quality video'));
    await t.pumpAndSettle();
    expect(SettingsService.state.value.highQualityVideo, isFalse);
  });
}
