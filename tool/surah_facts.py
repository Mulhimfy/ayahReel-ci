#!/usr/bin/env python3
"""Generates lib/data/juz_index.dart and lib/data/surah_facts.dart.

Tanafus — the app's quiz arena — asks about the surahs themselves as
well as about their verses: where a surah was revealed, what its name
means, which juz it opens in. None of that is in the app's surah
index, which carries only the two names and the ayah count, so this
fetches the rest from quran.com once and writes it out as Dart
constants. Static forever, like the surah index; run it again only to
add a language.

    python3 tool/surah_facts.py            # fetches, then writes both files
    python3 tool/surah_facts.py --from DIR # reads DIR/juzs.json and
                                           # DIR/chapters_<lang>.json instead

The translated names come from quran.com for English, Urdu and
Indonesian. Its Arabic and German answers are the English name again
for most surahs, so Arabic is left to the Arabic name itself (which is
the meaning — a quiz asking an Arabic reader what البقرة means is not a
quiz) and the German names are written here, from the Bubenheim &
Elyas edition's headings.

Revelation place is quran.com's, and DISPUTED lists the surahs the
classical sources do not agree on, so the arena never asks a question
whose answer depends on which scholar is marking it.
"""
import argparse
import json
import os
import sys
import urllib.request

API = 'https://api.quran.com/api/v4'
LANGS = ['en', 'ur', 'id']

# Bubenheim & Elyas ("Der edle Qur'an") surah headings.
GERMAN = {
    1: 'Die Eröffnung', 2: 'Die Kuh', 3: 'Die Sippe Imrans', 4: 'Die Frauen',
    5: 'Der Tisch', 6: 'Das Vieh', 7: 'Die Höhen', 8: 'Die Beute',
    9: 'Die Reue', 10: 'Jonas', 11: 'Hud', 12: 'Josef', 13: 'Der Donner',
    14: 'Abraham', 15: 'Das Felsengebirge', 16: 'Die Biene',
    17: 'Die Nachtreise', 18: 'Die Höhle', 19: 'Maria', 20: 'Ta-Ha',
    21: 'Die Propheten', 22: 'Die Pilgerfahrt', 23: 'Die Gläubigen',
    24: 'Das Licht', 25: 'Die Unterscheidung', 26: 'Die Dichter',
    27: 'Die Ameisen', 28: 'Die Geschichten', 29: 'Die Spinne',
    30: 'Die Römer', 31: 'Luqman', 32: 'Die Niederwerfung',
    33: 'Die Verbündeten', 34: 'Saba', 35: 'Der Schöpfer', 36: 'Ya-Sin',
    37: 'Die in Reihen Stehenden', 38: 'Sad', 39: 'Die Scharen',
    40: 'Der Vergebende', 41: 'Ausführlich dargelegt', 42: 'Die Beratung',
    43: 'Der Prunk', 44: 'Der Rauch', 45: 'Die Kniende', 46: 'Die Dünen',
    47: 'Muhammad', 48: 'Der Sieg', 49: 'Die Gemächer', 50: 'Qaf',
    51: 'Die Zerstreuenden', 52: 'Der Berg', 53: 'Der Stern', 54: 'Der Mond',
    55: 'Der Allerbarmer', 56: 'Das Ereignis', 57: 'Das Eisen',
    58: 'Der Streit', 59: 'Die Versammlung', 60: 'Die Geprüfte',
    61: 'Die Reihe', 62: 'Der Freitag', 63: 'Die Heuchler',
    64: 'Die Übervorteilung', 65: 'Die Scheidung', 66: 'Das Verbot',
    67: 'Die Herrschaft', 68: 'Das Schreibrohr', 69: 'Die Unabwendbare',
    70: 'Die Aufstiegswege', 71: 'Noah', 72: 'Die Dschinn',
    73: 'Der Eingehüllte', 74: 'Der Zugedeckte', 75: 'Die Auferstehung',
    76: 'Der Mensch', 77: 'Die Gesandten', 78: 'Die Kunde',
    79: 'Die Entreißenden', 80: 'Er runzelte die Stirn', 81: 'Das Umschlingen',
    82: 'Das Zerbrechen', 83: 'Die das Maß Kürzenden', 84: 'Das Zerreißen',
    85: 'Die Türme', 86: 'Der Nächtliche', 87: 'Der Höchste',
    88: 'Die Bedeckende', 89: 'Die Morgendämmerung', 90: 'Die Stadt',
    91: 'Die Sonne', 92: 'Die Nacht', 93: 'Der Vormittag', 94: 'Die Weitung',
    95: 'Die Feige', 96: 'Das Anhängsel', 97: 'Die Bestimmung',
    98: 'Der klare Beweis', 99: 'Das Beben', 100: 'Die Rennenden',
    101: 'Die Pochende', 102: 'Das Wettstreben', 103: 'Die Zeit',
    104: 'Der Stichler', 105: 'Der Elefant', 106: 'Quraisch',
    107: 'Die Hilfeleistung', 108: 'Die Fülle', 109: 'Die Ungläubigen',
    110: 'Die Hilfe', 111: 'Die Palmfasern', 112: 'Die Aufrichtigkeit',
    113: 'Das Morgengrauen', 114: 'Die Menschen',
}

# Surahs whose place of revelation the classical sources disagree on.
# The table still carries quran.com's answer for them; the arena just
# never makes it a question.
DISPUTED = {1, 13, 22, 55, 61, 64, 76, 83, 98, 99, 112, 113, 114}


def fetch(url):
    with urllib.request.urlopen(url, timeout=30) as r:
        return json.load(r)


def load(src):
    if src:
        juzs = json.load(open(os.path.join(src, 'juzs.json')))
        chapters = {l: json.load(open(os.path.join(src, f'chapters_{l}.json')))
                    for l in LANGS}
    else:
        juzs = fetch(f'{API}/juzs')
        chapters = {l: fetch(f'{API}/chapters?language={l}') for l in LANGS}
    return juzs, chapters


def dart_str(s):
    return "'" + s.replace('\\', '\\\\').replace("'", "\\'") + "'"


def write_juz(juzs, out):
    # The API answers every juz twice under two ids; the mapping is
    # the same both times.
    by_number = {}
    for j in juzs['juzs']:
        by_number.setdefault(j['juz_number'], j['verse_mapping'])
    assert sorted(by_number) == list(range(1, 31))
    starts = []
    for n in range(1, 31):
        m = by_number[n]
        surah = min(int(k) for k in m)
        first = int(m[str(surah)].split('-')[0])
        starts.append((surah, first))
    lines = [
        '/// Where each of the thirty juz begins.',
        '///',
        '/// The juz is the mushaf\'s division of the Quran into thirty',
        '/// roughly equal parts — the unit a month of Ramadan is read in, and',
        '/// the scope most people mean when they say what they are learning.',
        '/// Each entry is the surah and ayah a juz opens on; it runs to the',
        '/// ayah before the next one. Generated from the quran.com API by',
        '/// tool/surah_facts.py; static forever, like the surah index.',
        'library;',
        '',
        '/// (surah, ayah) a juz begins on, index 0 being juz 1.',
        'const List<(int, int)> juzStarts = [',
    ]
    for i, (s, a) in enumerate(starts):
        lines.append(f'  ({s}, {a}), // juz {i + 1}')
    lines.append('];')
    lines.append('')
    open(out, 'w', encoding='utf-8').write('\n'.join(lines))
    print(f'wrote {out}')


def write_facts(chapters, out):
    en = chapters['en']['chapters']
    names = {l: {c['id']: c['translated_name']['name']
                 for c in chapters[l]['chapters']} for l in LANGS}
    for l in LANGS:
        for c in chapters[l]['chapters']:
            lang = c['translated_name']['language_name']
            assert lang != 'english' or l == 'en', (l, c['id'], lang)
    lines = [
        '/// What the arena knows about a surah beyond its name and length.',
        '///',
        '/// Generated from the quran.com API by tool/surah_facts.py — see',
        '/// that file for what each column is and where it came from. The',
        '/// German names are the Bubenheim & Elyas headings, written in the',
        '/// tool by hand; Arabic has no column because the Arabic name is the',
        '/// meaning.',
        'library;',
        '',
        '/// One surah\'s facts.',
        'class SurahFact {',
        '  final int number;',
        '',
        '  /// True for a surah revealed in Makkah, on quran.com\'s reckoning.',
        '  final bool makki;',
        '',
        '  /// Whether the classical sources disagree about [makki]. The arena',
        '  /// never asks where a disputed surah was revealed.',
        '  final bool disputed;',
        '',
        '  /// Where the surah falls in the order of revelation, 1..114.',
        '  final int revelationOrder;',
        '',
        '  /// What the name means, by app language code. Arabic is absent',
        '  /// because the Arabic name is already the meaning.',
        '  final Map<String, String> meanings;',
        '',
        '  const SurahFact(this.number,',
        '      {required this.makki,',
        '      required this.disputed,',
        '      required this.revelationOrder,',
        '      required this.meanings});',
        '',
        '  /// The meaning in [lang], English when the language has none.',
        '  String meaning(String lang) => meanings[lang] ?? meanings[\'en\']!;',
        '}',
        '',
        '/// All 114, index 0 being Al-Fatiha.',
        'const List<SurahFact> surahFacts = [',
    ]
    for c in en:
        n = c['id']
        makki = c['revelation_place'] == 'makkah'
        lines.append(f'  SurahFact({n},')
        lines.append(f'      makki: {str(makki).lower()},')
        lines.append(f'      disputed: {str(n in DISPUTED).lower()},')
        lines.append(f'      revelationOrder: {c["revelation_order"]},')
        lines.append('      meanings: {')
        lines.append(f'        \'en\': {dart_str(names["en"][n])},')
        lines.append(f'        \'ur\': {dart_str(names["ur"][n])},')
        lines.append(f'        \'id\': {dart_str(names["id"][n])},')
        lines.append(f'        \'de\': {dart_str(GERMAN[n])},')
        lines.append('      }),')
    lines.append('];')
    lines.append('')
    open(out, 'w', encoding='utf-8').write('\n'.join(lines))
    print(f'wrote {out}')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--from', dest='src')
    args = ap.parse_args()
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    juzs, chapters = load(args.src)
    write_juz(juzs, os.path.join(root, 'lib', 'data', 'juz_index.dart'))
    write_facts(chapters, os.path.join(root, 'lib', 'data', 'surah_facts.dart'))


if __name__ == '__main__':
    sys.exit(main())
