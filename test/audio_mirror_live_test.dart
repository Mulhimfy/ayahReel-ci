@Tags(['network'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:ayah_reels/data/audio_mirror.dart';
import 'package:ayah_reels/data/fatiha_data.dart';
import 'package:ayah_reels/data/models.dart';
import 'package:ayah_reels/data/recitation_service.dart';
import 'package:ayah_reels/data/surah_index.dart';
import 'package:ayah_reels/data/surah_slice.dart';

/// Every voice, from the real mirror, with every host shut out: one file
/// of each through the download the app makes, checked against the
/// mirror's sums and against its host; and every published verse table
/// read the way the app reads it. Off unless MIRROR_LIVE=1:
///
///     MIRROR_LIVE=1 flutter test test/audio_mirror_live_test.dart
void main() {
  final live = Platform.environment['MIRROR_LIVE'] == '1';

  /// Answers every host with a dropped connection; the mirror only.
  final shut = _HostsShut(http.Client());

  for (final r in reciters) {
    final source = r.source;
    if (source is OwnAudio) continue;
    test('${r.id}: a file from the mirror, the host\'s bytes', () async {
      final dir = Directory.systemTemp.createTempSync('mirror_${r.id}');
      addTearDown(() => dir.deleteSync(recursive: true));
      AudioMirrorClient.debugReset();
      final store = MirrorStore(
          base: AudioMirror.base, client: http.Client(), dir: () async => dir);
      final client = AudioMirrorClient(shut, map: AudioMirror.map, store: store);

      // The smallest surah the voice has, Al-Kawthar where it can.
      final Uri url;
      final String key;
      switch (source) {
        case final AyahFiles s:
          url = s.url(108, 1);
          key = '108001';
        case final SurahFiles s:
          final n = [108, 103, 112, 110]
              .firstWhere((n) => !s.missing.contains(n));
          url = s.url(n);
          key = n.toString().padLeft(3, '0');
        case OwnAudio():
          return;
      }
      final f = File('${dir.path}/$key.mp3');
      await RecitationService.debugDownload(client, url, f);
      final got = f.readAsBytesSync();
      expect(AudioMirrorClient.served, 1, reason: 'from the mirror');

      final sums = jsonDecode((await http.get(store.assetUrl(r.id, 'sums.json')))
          .body) as Map<String, dynamic>;
      expect(sha256.convert(got).toString(), sums[key],
          reason: 'as it came from the host when mirrored');
      final host = await http.get(url);
      if (host.statusCode == 200) {
        expect(got, host.bodyBytes, reason: 'as the host sends it today');
      } else {
        // ignore: avoid_print
        print('${r.id}: the host answers ${host.statusCode} for $url — '
            'the mirror is all there is');
      }

      if (source case final SurahFiles s when s.timing is! OwnTiming) {
        // Every surah's table, as the app reads it.
        final timing = s.timing;
        var tables = 0;
        for (final info in surahIndex) {
          if (s.missing.contains(info.number)) continue;
          final res = await client.get(timing.url(info.number, info.ayahCount));
          expect(res.statusCode, 200, reason: 'table ${info.number}');
          final t = SurahSlice.parseTable(
              timing, jsonDecode(res.body), info.number, info.ayahCount);
          expect(t.length, info.ayahCount);
          tables++;
        }
        expect(tables, greaterThan(100));
      }
    }, skip: live ? false : 'MIRROR_LIVE=1 to read the real mirror');
  }
}

/// A network where every host but the mirror's is unreachable.
class _HostsShut extends http.BaseClient {
  final http.Client inner;

  _HostsShut(this.inner);

  static bool _mirror(Uri u) =>
      u.host == 'github.com' || u.host.endsWith('githubusercontent.com');

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!_mirror(request.url)) {
      throw SocketException('shut out', address: InternetAddress.anyIPv4);
    }
    return inner.send(request);
  }
}
