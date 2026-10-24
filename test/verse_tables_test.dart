import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/verse_tables.dart';

/// tool/verse_table.py's `encode`, for a table made up here.
String encode(Map<int, List<(int, int)>> tables) {
  final out = <int>[];
  void varint(int n) {
    while (true) {
      final b = n & 0x7f;
      n >>= 7;
      if (n == 0) {
        out.add(b);
        return;
      }
      out.add(b | 0x80);
    }
  }

  for (var s = 1; s <= 114; s++) {
    final rows = tables[s] ?? const <(int, int)>[];
    varint(rows.length);
    var prev = 0;
    for (final (start, end) in rows) {
      varint(start ~/ 10 - prev);
      varint(end ~/ 10 - start ~/ 10);
      prev = end ~/ 10;
    }
  }
  return base64.encode(out);
}

/// Our own verse tables are served, not carried: fetched once, checked
/// against the digest the build trusts, kept on the phone.
void main() {
  late Directory dir;
  const rows = [(3880, 6560), (6560, 8480), (8480, 11120), (11120, 15480)];
  final text = encode({112: rows});
  final digest = VerseTables.digestOf(text);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('verse_tables');
    VerseTables.debugReset();
    VerseTables.debugDir = dir;
    VerseTables.debugDigests = {'t': digest};
  });
  tearDown(() {
    VerseTables.debugReset();
    VerseTables.debugDir = null;
    VerseTables.debugDigests = null;
    dir.deleteSync(recursive: true);
  });

  void keep(String body) =>
      File('${dir.path}/verse_table_t_${digest.substring(0, 12)}.txt')
          .writeAsStringSync(body);

  test('a table reads back as it was written', () {
    final t = VerseTables.decode(text);
    expect(t.keys, [112]);
    expect([for (final w in t[112]!) (w.ayah, w.startMs, w.endMs)], [
      for (var i = 0; i < rows.length; i++) (i + 1, rows[i].$1, rows[i].$2),
    ]);
  });

  test('the kept copy is read when it is the table the build trusts, '
      'with nothing fetched', () async {
    keep(text);
    final t = await VerseTables.surah('t', 112);
    expect(t.length, 4);
    expect(t.first.startMs, 3880);
    expect(t.last.endMs, 15480);
  });

  test('a damaged kept copy is not used, and a build without the key '
      'asks nobody', () async {
    keep(text.substring(4));
    await expectLater(VerseTables.surah('t', 112), throwsFormatException);
  });

  test('a surah the table lacks, or a table there is none of, is refused',
      () async {
    keep(text);
    await expectLater(VerseTables.surah('t', 1), throwsFormatException);
    await expectLater(VerseTables.surah('none', 112), throwsFormatException);
  });

  test('Al-Luhaidan\'s table is trusted by the digest it was verified '
      'under', () {
    // tool/reciters_verified.json names it by these first 12.
    expect(VerseTables.digests['luhaidan'], startsWith('afdef534ccfe'));
  });
}
