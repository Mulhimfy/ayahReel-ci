import 'dart:io';

import 'package:ayah_reels/data/gallery_saver.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Points the temporary directory at a throwaway folder: the saver
/// copies the render there to give it a name the user will recognize.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.tmp);
  final String tmp;

  @override
  Future<String?> getTemporaryPath() async => tmp;
}

/// Two Android users reported the same thing from opposite ends: Save
/// did nothing, and Save produced a file with no video in it. This
/// covers the first half — every way the write itself can be refused.
///
/// The refusals are real ones. An album write goes through legacy
/// external storage on API 29 and below, a stricter path than a plain
/// write, so it fails on its own while the gallery root still accepts
/// the file; and a permission refused for good stops prompting, which
/// is the one case the app has to name rather than retry.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('gal');

  late Directory tmp;
  late List<MethodCall> calls;

  /// What each put read from the path it was handed, at the moment it
  /// was handed it — the stand-in is gone once the save returns.
  late List<String> read;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('gallery_save_test');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    calls = [];
    read = [];
  });

  tearDown(() {
    GallerySaver.linkForTest = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    try {
      try {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      } catch (_) {/* Windows holds the handle; the runner cleans up */}
    } catch (_) {/* Windows holds the handle; the runner cleans up */}
  });

  /// [refuse] decides which writes the platform rejects; [access] is
  /// what the permission request answers.
  void mockGal({
    required bool Function(String? album) refuse,
    bool access = true,
    String code = 'ACCESS_DENIED',
  }) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'hasAccess':
        case 'requestAccess':
          return access;
        case 'putVideo':
          read.add(File(call.arguments['path'] as String).readAsStringSync());
          if (refuse(call.arguments['album'] as String?)) {
            throw PlatformException(
                code: code, message: 'refused by the platform');
          }
          return null;
        default:
          return null;
      }
    });
  }

  File render() =>
      File('${tmp.path}/ayah_reel_v10_husary_dawn_f_50_s1_1_7.mp4')
        ..writeAsStringSync('mp4 bytes');

  List<MethodCall> writes() =>
      calls.where((c) => c.method == 'putVideo').toList();

  test('a refused album write still lands the reel in the gallery',
      () async {
    mockGal(refuse: (album) => album != null);

    final result = await GallerySaver.save(render(), name: 'AyahReel Fatiha');

    expect(result.status, GallerySaveStatus.saved);
    expect(writes().length, greaterThanOrEqualTo(2));
    expect(writes().first.arguments['album'], GallerySaver.albumName);
    expect(writes().last.arguments['album'], isNull,
        reason: 'the fallback write must ask for no album at all');
  });

  test('a permission the OS will not grant is reported as denied',
      () async {
    mockGal(refuse: (_) => true, access: false);

    final result = await GallerySaver.save(render(), name: 'AyahReel Fatiha');

    // Not `failed`: only this status sends the user to the settings
    // screen, which is the sole way back from a permanent refusal.
    expect(result.status, GallerySaveStatus.denied);
  });

  test('a refusal with no access left stops at one write, so the native '
      'prompt can only appear once', () async {
    mockGal(refuse: (_) => true, access: false);

    await GallerySaver.save(render(), name: 'AyahReel Fatiha');

    // Every put asks the platform for access on the way in, so a
    // second attempt is a second system dialog — back to back, which
    // reads as a broken app rather than as a question. Once the answer
    // is no, our own dialog takes over.
    expect(writes(), hasLength(1));
  });

  test('the album is used when the platform allows it', () async {
    mockGal(refuse: (_) => false);

    final result = await GallerySaver.save(render(), name: 'AyahReel Fatiha');

    expect(result.status, GallerySaveStatus.saved);
    expect(writes(), hasLength(1));
    expect(writes().single.arguments['album'], GallerySaver.albumName);
  });

  test('the file handed over is named for the reel, not for its render key',
      () async {
    mockGal(refuse: (_) => false);

    await GallerySaver.save(render(), name: 'AyahReel Al-Fatiha 1-7');

    // The gallery names the entry after the file it is given, and the
    // render is named for the styling key it is cached under.
    final path = writes().single.arguments['path'] as String;
    expect(path, endsWith('AyahReel_Al_Fatiha_1_7.mp4'));
    expect(read.single, 'mp4 bytes');
  });

  /// The bug these exist for: every save left a named copy of the reel
  /// in the cache and never deleted it, so a phone short of room filled
  /// up a reel at a time until every save failed at its last step.
  group('the named stand-in', () {
    List<String> left() => [
          for (final e in tmp.listSync(followLinks: false))
            e.uri.pathSegments.last,
        ];

    test('a copy is deleted once the gallery has the reel', () async {
      GallerySaver.linkForTest = false;
      mockGal(refuse: (_) => false);
      final r = render();

      await GallerySaver.save(r, name: 'AyahReel Al-Fatiha 1-7');

      expect(read.single, 'mp4 bytes');
      expect(left(), [r.uri.pathSegments.last]);
    });

    test('is a link where the platform reads through one, and costs no '
        'second copy', () async {
      GallerySaver.linkForTest = true;
      String? kind;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method != 'putVideo') return true;
        final path = call.arguments['path'] as String;
        kind = FileSystemEntity.typeSync(path, followLinks: false).toString();
        read.add(File(path).readAsStringSync());
        return null;
      });
      final r = render();

      final result = await GallerySaver.save(r, name: 'AyahReel Fatiha');

      expect(result.status, GallerySaveStatus.saved);
      expect(kind, FileSystemEntityType.link.toString());
      expect(read.single, 'mp4 bytes');
      // The link is gone and the render it pointed at is not.
      expect(left(), [r.uri.pathSegments.last]);
      expect(r.readAsStringSync(), 'mp4 bytes');
    });

    test('is deleted after a failed save too', () async {
      GallerySaver.linkForTest = false;
      mockGal(refuse: (_) => true, code: 'UNEXPECTED');
      final r = render();

      final result = await GallerySaver.save(r, name: 'AyahReel Fatiha');

      expect(result.status, GallerySaveStatus.failed);
      expect(left(), [r.uri.pathSegments.last]);
    });

    test('one an older build left behind is replaced, not added to',
        () async {
      GallerySaver.linkForTest = false;
      File('${tmp.path}/AyahReel_Fatiha.mp4').writeAsStringSync('old reel');
      mockGal(refuse: (_) => false);
      final r = render();

      await GallerySaver.save(r, name: 'AyahReel Fatiha');

      expect(read.single, 'mp4 bytes');
      expect(left(), [r.uri.pathSegments.last]);
    });
  });

  test('a full phone is told apart, and not written to a second time',
      () async {
    mockGal(refuse: (_) => true, code: 'NOT_ENOUGH_SPACE');

    final result = await GallerySaver.save(render(), name: 'AyahReel Fatiha');

    expect(result.status, GallerySaveStatus.failed);
    expect(result.outOfSpace, isTrue);
    expect(writes(), hasLength(1),
        reason: 'the gallery root is on the same full disk as the album');
  });

  test('any other failure is not mistaken for a full phone', () async {
    mockGal(refuse: (_) => true, code: 'UNEXPECTED');

    final result = await GallerySaver.save(render(), name: 'AyahReel Fatiha');

    expect(result.status, GallerySaveStatus.failed);
    expect(result.outOfSpace, isFalse);
  });

  test('a render that never made it to disk is a failure, not a save',
      () async {
    mockGal(refuse: (_) => false);

    final result = await GallerySaver.save(File('${tmp.path}/gone.mp4'));

    expect(result.status, GallerySaveStatus.failed);
    expect(writes(), isEmpty);
  });
}
