import 'dart:io';

import 'package:ayah_reels/data/listen/listen_model.dart';
import 'package:ayah_reels/data/listen/listen_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

/// AyahReel Listen end to end on a device: the model fetched from the
/// Worker with the app's key, run by the app's own ONNX Runtime (the reduced
/// build) through ListenBridge, the engine in its isolate — on the Al-Fatiha
/// recordings the app bundles. Needs --dart-define=WORDS_KEY.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the phone hears Al-Fatiha and times its words', (tester) async {
    expect(ListenHost.enabled, isTrue, reason: 'build with --dart-define=WORDS_KEY');
    final sw = Stopwatch()..start();
    final model = await ListenModel.ensure();
    // ignore: avoid_print
    print('LISTEN model ${model.path} ${model.lengthSync()} bytes in ${sw.elapsedMilliseconds} ms');
    for (final name in ['alafasy_001', 'husary_001', 'abdulbasit_001']) {
      final data = await rootBundle.load('assets/audio/$name.mp3');
      final tmp = await getTemporaryDirectory();
      final f = File('${tmp.path}/$name.mp3')
        ..writeAsBytesSync(data.buffer.asUint8List(), flush: true);
      sw.reset();
      final out = await ListenService.hearFile(f.path);
      final m = out.main;
      // ignore: avoid_print
      print('LISTEN $name: ${m == null ? 'nothing' : '${m.surah}:${m.first}-${m.last}'} '
          'in ${sw.elapsedMilliseconds} ms (audio ${out.audioMs} ms, model ${out.modelMs} ms, '
          'engine ${out.engineMs} ms) words ${m?.timing.values.fold<int>(0, (n, v) => n + (v.length - 2) ~/ 3)}');
      expect(m, isNotNull);
      expect(m!.surah, 1);
      expect(m.first, lessThanOrEqualTo(2));
      expect(m.last, 7);
      expect(m.timing[7], isNotNull);
    }
  });
}
