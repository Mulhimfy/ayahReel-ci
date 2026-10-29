import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' show MockClient;

import 'package:ayah_reels/data/quran_search.dart';

/// Finding a verse by a word of its translation.
///
/// The Arabic text is bundled and searched offline; a translation is
/// another megabyte per edition and is fetched, so this search is a
/// request. What has to hold is the joining: the reference comes from
/// the answer, the Arabic comes from the bundled index, and the markup
/// the API wraps every match in never reaches a list row.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    QuranSearch.loadFrom(await rootBundle.loadString(QuranSearch.asset));
  });

  setUp(() => QuranSearch.resetForTest());

  tearDown(() {
    QuranSearch.clientForTest = null;
    QuranSearch.resetForTest();
  });

  Future<void> reload() async =>
      QuranSearch.loadFrom(await rootBundle.loadString(QuranSearch.asset));

  String canned() => jsonEncode({
        'search': {
          'query': 'mercy',
          'results': [
            {
              'verse_key': '7:151',
              'translations': [
                {
                  'text': '[Moses] said, "My Lord, forgive me and admit us '
                      'into Your <em>mercy</em>."<sup foot_note=1>1</sup>',
                  'resource_id': 20,
                },
              ],
            },
            // A malformed row is skipped rather than thrown over.
            {'verse_key': 'nonsense', 'translations': []},
            // And one past the end of its surah.
            {'verse_key': '1:99', 'translations': []},
          ],
        },
      });

  test('a hit carries the bundled Arabic and the clean translation',
      () async {
    await reload();
    QuranSearch.clientForTest =
        MockClient((_) async => http.Response(canned(), 200));
    final hits = await QuranSearch.searchTranslation('mercy', resourceId: 20);
    expect(hits, hasLength(1), reason: 'the bad rows were not skipped');
    final hit = hits.single;
    expect(hit.surah, 7);
    expect(hit.ayah, 151);
    // The verse as the app renders it, not as the answer spelled it.
    expect(hit.text, (await QuranSearch.surah(7))[150]);
    // No markup, no footnote digit, and the word that matched is there.
    expect(hit.translation, contains('mercy'));
    expect(hit.translation, isNot(contains('<')));
    expect(hit.translation, isNot(contains('foot_note')));
    expect(hit.translation, endsWith('."'));
  });

  test('two letters is not a search, and the answer is remembered',
      () async {
    await reload();
    var calls = 0;
    QuranSearch.clientForTest = MockClient((_) async {
      calls++;
      return http.Response(canned(), 200);
    });
    expect(await QuranSearch.searchTranslation('me', resourceId: 20), isEmpty);
    expect(calls, 0, reason: 'it asked the network for two letters');
    await QuranSearch.searchTranslation('mercy', resourceId: 20);
    await QuranSearch.searchTranslation('MERCY', resourceId: 20);
    expect(calls, 1, reason: 'the same word was fetched twice');
    // Another edition is another answer, not the same one.
    await QuranSearch.searchTranslation('mercy', resourceId: 234);
    expect(calls, 2);
  });

  test('a refusal, a timeout or a changed shape is an empty list',
      () async {
    await reload();
    QuranSearch.clientForTest =
        MockClient((_) async => http.Response('{}', 500));
    expect(
        await QuranSearch.searchTranslation('mercy', resourceId: 20), isEmpty);
    QuranSearch.resetForTest();
    await reload();
    QuranSearch.clientForTest =
        MockClient((_) async => http.Response('not json at all', 200));
    expect(
        await QuranSearch.searchTranslation('given', resourceId: 20), isEmpty);
    QuranSearch.resetForTest();
    await reload();
    QuranSearch.clientForTest = MockClient((_) async => throw 'offline');
    expect(
        await QuranSearch.searchTranslation('mercy', resourceId: 20), isEmpty);
  });

  test('the query and the edition are what it asks for', () async {
    await reload();
    Uri? asked;
    QuranSearch.clientForTest = MockClient((req) async {
      asked = req.url;
      return http.Response(canned(), 200);
    });
    await QuranSearch.searchTranslation('the mercy of', resourceId: 234);
    expect(asked, isNotNull);
    expect(asked!.host, 'api.quran.com');
    expect(asked!.queryParameters['q'], 'the mercy of');
    expect(asked!.queryParameters['translations'], '234');
  });
}
