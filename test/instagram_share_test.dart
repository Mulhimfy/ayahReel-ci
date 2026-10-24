import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/instagram_share.dart';
import 'package:ayah_reels/data/settings_service.dart';
import 'package:ayah_reels/l10n/l10n.dart';

/// The straight-to-Instagram-Reels hand-off.
///
/// The thing worth pinning is what it does *not* require: Meta asks for
/// an App ID and it buys the attribution line on the finished reel, but
/// Instagram opens its composer without one. An earlier cut of this
/// refused to show the button until an id was compiled in, which made
/// the whole feature invisible in every build that had none.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('ayahreel/instagram');
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');

  /// The staging step asks for the cache dir before it asks the
  /// platform for anything else.
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            pathProvider, (_) async => Directory.systemTemp.path);
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(pathProvider, null));

  /// Stands in for the platform, and keeps what it was handed.
  List<Map<dynamic, dynamic>> mockPlatform({required bool accepts}) {
    final calls = <Map<dynamic, dynamic>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (c) async {
      calls.add(c.arguments as Map);
      return accepts;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    return calls;
  }

  test('the call carries the Meta App ID every build ships with',
      () async {
    expect(InstagramShare.metaAppId, '989696730806980',
        reason: 'iOS Instagram refuses a share without a Meta App ID, '
            'so the id is a default, not a --dart-define');
    final calls = mockPlatform(accepts: true);
    final video = File('${Directory.systemTemp.path}/ig_test.mp4')
      ..writeAsBytesSync(const [0, 1, 2]);
    addTearDown(() => video.deleteSync());

    expect(await InstagramShare.shareReel(video), isTrue);
    expect(calls, hasLength(1));
    expect(calls.single['appId'], InstagramShare.metaAppId);
    expect(calls.single['path'], isNotEmpty);
  });

  test('a platform that cannot hand off says so, and never throws',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'share_failed', message: 'nope');
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final video = File('${Directory.systemTemp.path}/ig_test2.mp4')
      ..writeAsBytesSync(const [0, 1, 2]);
    addTearDown(() => video.deleteSync());

    // False is the caller's cue to open the normal share sheet.
    expect(await InstagramShare.shareReel(video), isFalse);
  });

  test('a reel goes to the story composer by a call of its own', () async {
    final names = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (c) async {
      names.add(c.method);
      expect((c.arguments as Map)['appId'], InstagramShare.metaAppId);
      return true;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final video = File('${Directory.systemTemp.path}/ig_story.mp4')
      ..writeAsBytesSync(const [0, 1, 2]);
    addTearDown(() => video.deleteSync());

    expect(await InstagramShare.shareStoryVideo(video), isTrue);
    expect(names, ['shareStoryVideo'],
        reason: 'not shareStory: that one hands over a picture');
  });

  test('a build whose native side predates the story call says no',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (c) async {
      throw MissingPluginException('no ${c.method} here');
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final video = File('${Directory.systemTemp.path}/ig_story2.mp4')
      ..writeAsBytesSync(const [0, 1, 2]);
    addTearDown(() => video.deleteSync());

    // False opens the share sheet, whose Instagram rows include Stories.
    expect(await InstagramShare.shareStoryVideo(video), isFalse);
  });

  test('the toggle is on for anyone who has never seen it', () {
    // A settings file written before this release has no such key.
    final old = AppSettings.fromJson({'whatsappDirectShare': false});
    expect(old.instagramDirectShare, isTrue);
    expect(old.whatsappDirectShare, isFalse);

    // And an explicit no survives the round trip.
    final off = AppSettings.defaults.copyWith(instagramDirectShare: false);
    expect(AppSettings.fromJson(off.toJson()).instagramDirectShare, isFalse);
  });

  test('both languages name the destination', () {
    const en = L10n(AppLang.en);
    const ar = L10n(AppLang.ar);
    // The destination by the name people actually call it. The button
    // used to promise the composer ("Make an Instagram Reel"); it now
    // names where the reel is going and lets the composer speak for
    // itself.
    // The whole word. "Share to Insta" read like a placeholder
    // somebody had not finished typing.
    expect(en.sendToInstagram, contains('Instagram'));
    expect(ar.sendToInstagram, contains('إنستغرام'));
    expect(ar.straightToInstagram, isNot(en.straightToInstagram));
    expect(ar.straightToInstagramSubtitle,
        isNot(en.straightToInstagramSubtitle));
    expect(ar.instagramUnavailable, isNot(en.instagramUnavailable));
  });
}
