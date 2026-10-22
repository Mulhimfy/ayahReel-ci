#!/usr/bin/env python3
"""Verify assets/hadith/ — the library the card composer searches.

The same standard `tool/verify_fonts.py` holds the verse to, applied to
the other body of text the app now sets. A card is rasterized to a PNG
and shared; a tofu box in it cannot be taken back, and neither can a
narration the app had no business offering.

Checks, in order of what they would cost if they failed:

  1. Every file is present, parses, and holds exactly as many entries
     as meta.json has rows. The language files are index-aligned with
     the rows — a file one entry short would caption every hadith
     after it with the next one's text.
  2. Every row points at a real collection, and everything out of a
     collection that needs grading carries one. See fetch_hadith.py.
  3. No hadith carries a grading the app would have to hide.
  4. Every codepoint of the Arabic is in the cmap of every face the
     composer can set Arabic in, or in its fallback; same for the Urdu
     against the Arabic-script faces, and the Latin text against the
     Latin ones.
  5. Nothing is left of the markup, the bidi controls or the
     replacement characters the source editions carry.

Run:  python3 tool/verify_hadith.py
"""
import gzip
import json
import os
import re
import sys

from fontTools.ttLib import TTFont

HERE = os.path.dirname(os.path.abspath(__file__))
DIR = os.path.join(HERE, '..', 'assets', 'hadith')
FONTS = os.path.join(HERE, '..', 'assets', 'fonts')

# Keep in step with CardFace in lib/data/card_style.dart: the faces the
# composer can set a hadith in, and the fallback stacked behind each.
ARABIC_FACES = [
    ('HafsUthmani', 'UthmanicHafs.ttf'),
    ('AmiriQuran', 'AmiriQuran.ttf'),
    ('ScheherazadeNew', 'ScheherazadeNew.ttf'),
    ('NotoNaskhArabic', 'NotoNaskhArabic.ttf'),
    ('Lateef', 'Lateef.ttf'),
    ('Amiri', 'Amiri.ttf'),
    ('NotoKufiArabic', 'NotoKufiArabic.ttf'),
    ('IBMPlexSansArabic', 'IBMPlexSansArabic.ttf'),
    ('NotoNastaliqUrdu', 'NotoNastaliqUrdu.ttf'),
    ('MarkaziText', 'MarkaziText.ttf'),
    ('Mada', 'Mada.ttf'),
    ('NotoSansArabic', 'NotoSansArabic.ttf'),
    ('Harmattan', 'Harmattan.ttf'),
    ('Cairo', 'Cairo.ttf'),
    ('Almarai', 'Almarai.ttf'),
    ('Changa', 'Changa.ttf'),
    ('ElMessiri', 'ElMessiri.ttf'),
    ('ReemKufi', 'ReemKufi.ttf'),
    ('ArefRuqaa', 'ArefRuqaa.ttf'),
    ('Qahiri', 'Qahiri.ttf'),
    ('Katibeh', 'Katibeh.ttf'),
    ('Mirza', 'Mirza.ttf'),
    ('Vazirmatn', 'Vazirmatn.ttf'),
]
LATIN_FACES = [
    ('Inter', 'Inter.ttf'),
    ('SourceSerif4', 'SourceSerif4.ttf'),
    ('Spectral', 'Spectral.ttf'),
    ('CormorantGaramond', 'CormorantGaramond.ttf'),
    ('Literata', 'Literata.ttf'),
    ('EBGaramond', 'EBGaramond.ttf'),
    ('LibreBaskerville', 'LibreBaskerville.ttf'),
    ('CrimsonPro', 'CrimsonPro.ttf'),
    ('CrimsonText', 'CrimsonText.ttf'),
    ('Cardo', 'Cardo.ttf'),
    ('Vollkorn', 'Vollkorn.ttf'),
    ('Alegreya', 'Alegreya.ttf'),
    ('Bitter', 'Bitter.ttf'),
    ('Rokkitt', 'Rokkitt.ttf'),
    ('Cormorant', 'Cormorant.ttf'),
    ('Rasa', 'Rasa.ttf'),
    ('Yrsa', 'Yrsa.ttf'),
    ('WorkSans', 'WorkSans.ttf'),
    ('SpaceGrotesk', 'SpaceGrotesk.ttf'),
    ('Mulish', 'Mulish.ttf'),
    ('NunitoSans', 'NunitoSans.ttf'),
    ('Raleway', 'Raleway.ttf'),
    ('Quicksand', 'Quicksand.ttf'),
    ('Montserrat', 'Montserrat.ttf'),
    ('Urbanist', 'Urbanist.ttf'),
    ('PublicSans', 'PublicSans.ttf'),
    ('PlusJakartaSans', 'PlusJakartaSans.ttf'),
    ('Epilogue', 'Epilogue.ttf'),
    ('Domine', 'Domine.ttf'),
    ('Petrona', 'Petrona.ttf'),
    ('PlayfairDisplay', 'PlayfairDisplay.ttf'),
    ('Marcellus', 'Marcellus.ttf'),
    ('Cinzel', 'Cinzel.ttf'),
    ('GildaDisplay', 'GildaDisplay.ttf'),
    ('Italiana', 'Italiana.ttf'),
    ('TenorSans', 'TenorSans.ttf'),
    ('Prata', 'Prata.ttf'),
    ('BodoniModa', 'BodoniModa.ttf'),
    ('DMSerifDisplay', 'DMSerifDisplay.ttf'),
    ('JosefinSans', 'JosefinSans.ttf'),
    ('Jost', 'Jost.ttf'),
    ('Outfit', 'Outfit.ttf'),
]
# What the app stacks behind every face — see CardFace.fallback, which
# this has to match: a text serif for the marks a display face may not
# draw, and the Arabic-capable house face for the ﷺ these editions
# write inline. Noto Naskh stands behind the Arabic ones.
FALLBACK = ['NotoNaskhArabic.ttf', 'IBMPlexSansArabic.ttf',
            'SourceSerif4.ttf']

BAD = re.compile('[<>�​-‏‪-‮﻿]')
GRADE_BAD = ('daif', "da'if", 'weak', 'munkar', 'mawdu', 'batil',
             'matruk', 'fabricat', 'shadh')
SELF_VOUCHING = {'bukhari', 'muslim', 'nawawi', 'qudsi'}


def read(name):
    path = os.path.join(DIR, name)
    if os.path.exists(path):
        with open(path, encoding='utf-8') as f:
            return json.load(f)
    with gzip.open(path + '.gz', 'rt', encoding='utf-8') as f:
        return json.load(f)


def cmap(path):
    f = TTFont(path, fontNumber=0, lazy=True)
    out = set()
    for t in f['cmap'].tables:
        out |= set(t.cmap.keys())
    return out


def main():
    fails = []

    def fail(msg):
        print(f'FAIL: {msg}')
        fails.append(msg)

    meta = read('meta.json')
    rows = meta['rows']
    n = len(rows)
    print(f'{n} hadith')

    texts = {'ar': read('ar.json')}
    for code in ('en', 'ur', 'id'):
        texts[code] = read(f'{code}.json')
    for code, body in texts.items():
        if len(body) != n:
            fail(f'{code}: {len(body)} entries for {n} rows')

    ids = [c['id'] for c in meta['collections']]
    topics = meta['topics']
    for i, r in enumerate(rows):
        if not 0 <= r[0] < len(ids):
            fail(f'row {i}: no collection {r[0]}')
            continue
        if r[2] >> len(topics):
            fail(f'row {i}: topic bit outside {len(topics)} topics')
        grade = (r[3] or '').lower()
        if any(b in grade for b in GRADE_BAD):
            fail(f'row {i}: graded "{r[3]}"')
        if not grade and ids[r[0]] not in SELF_VOUCHING:
            fail(f'row {i}: {ids[r[0]]} {r[1]} carries no grading')

    for code, body in texts.items():
        empty = sum(1 for t in body if not t)
        marked = [i for i, t in enumerate(body) if BAD.search(t)]
        if marked:
            fail(f'{code}: markup or bidi controls left in '
                 f'{len(marked)} entries, first at row {marked[0]}')
        if code in ('ar', 'en') and empty:
            fail(f'{code}: {empty} entries with no text')
        print(f'  {code}: {n - empty} translated')

    # ---- coverage --------------------------------------------------
    def codepoints(body):
        out = set()
        for t in body:
            out |= {ord(c) for c in t}
        return out

    fb = set()
    for f in FALLBACK:
        fb |= cmap(os.path.join(FONTS, f))

    checks = [
        ('Arabic', codepoints(texts['ar']), ARABIC_FACES),
        ('Urdu', codepoints(texts['ur']), ARABIC_FACES),
        ('English', codepoints(texts['en']), LATIN_FACES),
        ('Indonesian', codepoints(texts['id']), LATIN_FACES),
    ]
    for what, points, faces in checks:
        for family, file in faces:
            covered = cmap(os.path.join(FONTS, file)) | fb
            missing = sorted(points - covered - {0x20})
            if missing:
                shown = ' '.join(f'U+{c:04X}({chr(c)})' for c in missing[:8])
                fail(f'{family} cannot set the {what}: {len(missing)} '
                     f'codepoints missing — {shown}')
        print(f'  {what}: {len(points)} codepoints, '
              f'{len(faces)} faces checked')

    size = sum(os.path.getsize(os.path.join(DIR, f))
               for f in os.listdir(DIR))
    print(f'  shipped: {size / 1e6:.2f} MB')
    print('OK' if not fails else f'{len(fails)} failure(s)')
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
