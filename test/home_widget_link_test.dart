import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/home_widget_service.dart';
import 'package:ayah_reels/data/quran_verses.dart';

/// The link a tapped widget opens the app with. Both native sides
/// build it by hand, so the shape is pinned here and the parser has to
/// take every verse in the list and nothing else.
void main() {
  test('every verse round-trips through its link', () {
    for (final v in [jumuahVerse, ...quranVerses]) {
      final link = HomeWidgetService.linkFor(v);
      expect(link, startsWith('ayahreel://verse/'));
      final back = HomeWidgetService.parseLink(link);
      expect(back, isNotNull, reason: link);
      expect(back!.reference, v.reference, reason: link);
    }
  });

  test('the shape the native sides build', () {
    expect(
        HomeWidgetService.linkFor(quranVerses.first), 'ayahreel://verse/2/152');
    // A range carries both ends.
    final range = quranVerses.firstWhere((v) => v.endAyah != v.startAyah);
    expect(HomeWidgetService.linkFor(range),
        'ayahreel://verse/${range.surah}/${range.startAyah}/${range.endAyah}');
    expect(HomeWidgetService.parseLink('ayahreel://verse/2/152')?.reference,
        '2:152');
  });

  test('anything else is ignored, never thrown at', () {
    for (final bad in [
      null,
      '',
      'https://example.com/verse/2/152',
      'ayahreel://reel/2/152',
      'ayahreel://verse/2',
      'ayahreel://verse/two/152',
      'ayahreel://verse/2/1', // a real verse, but not one in the list
      'ayahreel://verse/999/1',
      '::not a url::',
    ]) {
      expect(HomeWidgetService.parseLink(bad), isNull, reason: '$bad');
    }
  });
}
