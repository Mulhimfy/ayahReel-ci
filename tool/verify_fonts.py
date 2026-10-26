#!/usr/bin/env python3
"""Verify every face the verse card offers, against everything it will
ever have to set.

A missing glyph is a tofu box burned into an exported reel, which
cannot be taken back — the same standard `tool/verify_translations.py`
holds the translations to, applied to the other half of the pair. So
no face goes into `lib/data/verse_font.dart` until:

  1. Every codepoint of the Uthmani Quran — all 6236 verses, never a
     sample — is in the cmap of every face offered for the verse, and
     that face positions marks itself: a GPOS 'mark' feature for
     Arabic, so a vowel lands on its letter and not beside it.
  2. Every codepoint of each translation edition is in the cmap of
     every face offered for that edition's script, or in the cmap of
     the fallback the app stacks behind it.
  3. The optical numbers in `verse_font.dart` still match the files:
     a face is sized and leaded off its own metrics, and a font
     updated in place without those being re-derived would set the
     verse at the wrong size or run its lines into each other.

Run:  python3 tool/verify_fonts.py
"""
import collections
import json
import os
import re
import sys
import unicodedata
import urllib.request

from fontTools.ttLib import TTFont
from fontTools.pens.boundsPen import BoundsPen

API = 'https://api.quran.com/api/v4'
UA = {'User-Agent': 'ayahreel-verify'}
FONTS = os.path.join(os.path.dirname(__file__), '..', 'assets', 'fonts')
DART = os.path.join(os.path.dirname(__file__), '..', 'lib', 'data',
                    'verse_font.dart')

# The faces offered for the verse itself. Keep in step with
# VerseFace in lib/data/verse_font.dart.
ARABIC_FACES = [
    ('HafsUthmani', 'UthmanicHafs.ttf'),
    ('AmiriQuran', 'AmiriQuran.ttf'),
    ('ScheherazadeNew', 'ScheherazadeNew.ttf'),
    ('NotoNaskhArabic', 'NotoNaskhArabic.ttf'),
    ('Lateef', 'Lateef.ttf'),
    ('Amiri', 'Amiri.ttf'),
    ('NotoKufiArabic', 'NotoKufiArabic.ttf'),
    ('Mada', 'Mada.ttf'),
    ('NotoSansArabic', 'NotoSansArabic.ttf'),
    ('Harmattan', 'Harmattan.ttf'),
    # Weights of the faces above, each a static file of its own — a
    # different file, so checked on its own — and the faces that
    # joined the list with them.
    ('NotoNaskhArabicBold', 'NotoNaskhArabicBold.ttf'),
    ('AmiriBold', 'AmiriBold.ttf'),
    ('LateefBold', 'LateefBold.ttf'),
    ('HarmattanBold', 'HarmattanBold.ttf'),
    ('NotoKufiArabicThin', 'NotoKufiArabicThin.ttf'),
    ('NotoKufiArabicBold', 'NotoKufiArabicBold.ttf'),
    ('NotoSansArabicExtraLight', 'NotoSansArabicExtraLight.ttf'),
    ('NotoSansArabicBlack', 'NotoSansArabicBlack.ttf'),
    ('NotoSansArabicExtraCondensed', 'NotoSansArabicExtraCondensed.ttf'),
    ('NotoSansArabicExtraCondensedBold',
     'NotoSansArabicExtraCondensedBold.ttf'),
    ('IBMPlexSansArabic', 'IBMPlexSansArabic.ttf'),
    ('IBMPlexSansArabicBold', 'IBMPlexSansArabicBold.ttf'),
    ('MadaLight', 'MadaLight.ttf'),
    ('Estedad', 'Estedad.ttf'),
    ('EstedadBlack', 'EstedadBlack.ttf'),
    ('Jomhuria', 'Jomhuria.ttf'),
]

# The faces offered for the translation line, by the script the
# edition is set in, each with the fallback the app stacks behind it.
# Keep in step with TranslationFace in lib/data/verse_font.dart.
LATIN_FACES = [
    ('Inter', ['Inter.ttf', 'InterItalic.ttf']),
    ('SourceSerif4', ['SourceSerif4.ttf']),
    ('Spectral', ['Spectral.ttf']),
    ('CormorantGaramond', ['CormorantGaramond.ttf']),
    ('Literata', ['Literata.ttf']),
    ('EBGaramond', ['EBGaramond.ttf']),
    ('LibreBaskerville', ['LibreBaskerville.ttf']),
    ('CrimsonPro', ['CrimsonPro.ttf']),
    ('CrimsonText', ['CrimsonText.ttf']),
    ('Cardo', ['Cardo.ttf']),
    ('Vollkorn', ['Vollkorn.ttf']),
    ('Alegreya', ['Alegreya.ttf']),
    ('Bitter', ['Bitter.ttf']),
    ('Rokkitt', ['Rokkitt.ttf']),
    ('Cormorant', ['Cormorant.ttf']),
    ('Rasa', ['Rasa.ttf']),
    ('Yrsa', ['Yrsa.ttf']),
    ('WorkSans', ['WorkSans.ttf']),
    ('SpaceGrotesk', ['SpaceGrotesk.ttf']),
    ('Mulish', ['Mulish.ttf']),
    ('NunitoSans', ['NunitoSans.ttf']),
    ('Raleway', ['Raleway.ttf']),
    ('Quicksand', ['Quicksand.ttf']),
    ('Montserrat', ['Montserrat.ttf']),
    ('Urbanist', ['Urbanist.ttf']),
    ('PublicSans', ['PublicSans.ttf']),
    ('PlusJakartaSans', ['PlusJakartaSans.ttf']),
    ('Epilogue', ['Epilogue.ttf']),
    ('Domine', ['Domine.ttf']),
    ('Petrona', ['Petrona.ttf']),
]
ARABIC_SCRIPT_FACES = [
    ('IBMPlexSansArabic', ['IBMPlexSansArabic.ttf']),
    ('NotoNastaliqUrdu', ['NotoNastaliqUrdu.ttf']),
    ('NotoNaskhArabic', ['NotoNaskhArabic.ttf']),
    ('ScheherazadeNew', ['ScheherazadeNew.ttf']),
    ('Amiri', ['Amiri.ttf']),
    ('MarkaziText', ['MarkaziText.ttf']),
    ('NotoKufiArabic', ['NotoKufiArabic.ttf']),
    ('Katibeh', ['Katibeh.ttf']),
    ('Mirza', ['Mirza.ttf']),
]
# Every Latin face carries this behind it, for the ﷺ ligature Saheeh
# International writes 34 times — see AppTheme.translation.
# What the app stacks behind a Latin face, in order — see
# TranslationFace.fallback, which this has to match exactly. Source
# Serif carries the transliteration marks Saheeh International sets
# its names in and several display faces do not draw; IBM Plex Sans
# Arabic carries the ﷺ ligature no Latin face has.
LATIN_FALLBACK = ['SourceSerif4.ttf', 'IBMPlexSansArabic.ttf']

# resource id, code, script of each edition the app offers. Keep in
# step with lib/data/verse_translation.dart.
EDITIONS = [
    (20, 'English', 'latin'),
    (234, 'Urdu', 'arabic'),
    (33, 'Indonesian', 'latin'),
    (27, 'German', 'latin'),
]

# Known, accepted gaps: a codepoint a face does not carry, that the
# fallback behind it does, where the substitution cannot be seen to be
# one. Anything not listed here fails the run.
ACCEPTED = {
    ('NotoNastaliqUrdu', 'Urdu'): {
        0x0674: 'ARABIC LETTER HIGH HAMZA — joining type U, so the '
                'fallback glyph stands alone and breaks no word; 40 '
                'verses of 6236',
    },
    # Markazi Text is a text face and leaves the honorific signs to the
    # fallback. All four are non-joining marks or a standalone
    # ligature: the fallback glyph stands on its own and no word is
    # broken by it, which is the same reason Nastaliq's high hamza is
    # accepted above.
    # Katibeh and Mirza are Persian display hands and leave the
    # standalone honorific and the high hamza to the fallback. Both are
    # non-joining: the substituted glyph stands on its own and no word
    # is broken by it, which is the same reason Nastaliq's high hamza
    # is accepted above. A *combining* mark is a different matter and
    # is not accepted from any face — a face that cannot draw one is
    # offered for cards instead of for a translation.
    ('Katibeh', 'Urdu'): {
        0x0674: 'ARABIC LETTER HIGH HAMZA — joining type U',
        0xFDFA: 'ARABIC LIGATURE SALLALLAHOU ALAYHE WASALLAM — one '
                'standalone glyph',
    },
    ('Mirza', 'Urdu'): {
        0x0674: 'ARABIC LETTER HIGH HAMZA — joining type U',
        0xFDFA: 'ARABIC LIGATURE SALLALLAHOU ALAYHE WASALLAM — one '
                'standalone glyph',
    },
    ('MarkaziText', 'Urdu'): {
        0x0611: 'ARABIC SIGN ALAYHE ASSALLAM — a combining honorific, '
                'drawn by IBM Plex Sans Arabic behind it',
        0x0613: 'ARABIC SIGN RADI ALLAHOU ANHU — likewise',
        0x0674: 'ARABIC LETTER HIGH HAMZA — joining type U, so the '
                'fallback glyph stands alone and breaks no word',
        0xFDFA: 'ARABIC LIGATURE SALLALLAHOU ALAYHE WASALLAM — one '
                'standalone glyph, drawn by the fallback',
    },
}

SUP = re.compile(r'<sup\b[^>]*>.*?</sup>', re.S)
TAG = re.compile(r'<[^>]*>')
DROPPED = {0x00AD, 0x200B, 0xFEFF}
TO_SPACE = {0x000A, 0x000D, 0x0009, 0x0085, 0x00A0, 0x202F, 0x2028, 0x2029}

# The glyphs a face's optical size is normalised on — see
# VerseFace.sizeFactor. Arabic on five letters that carry the script's
# height, Latin on the x-height.
ARABIC_SAMPLE = 'الم بس'.replace(' ', '')
LATIN_SAMPLE = 'x'


def clean(t):
    t = SUP.sub('', t)
    t = TAG.sub('', t)
    t = re.sub(r'  +', ' ', t).strip()
    out = []
    for ch in t:
        c = ord(ch)
        if c in DROPPED:
            continue
        out.append(' ' if c in TO_SPACE else ch)
    return re.sub(r'  +', ' ', ''.join(out)).strip()


def get(url, tries=5):
    last = None
    for _ in range(tries):
        try:
            with urllib.request.urlopen(
                    urllib.request.Request(url, headers=UA), timeout=60) as h:
                return json.load(h)
        except Exception as e:  # noqa: BLE001 - retried, then raised
            last = e
    raise last


def cmap(path):
    f = TTFont(path, lazy=True)
    out = set()
    for t in f['cmap'].tables:
        out |= set(t.cmap.keys())
    return out


def mark_features(path):
    """Which of GPOS 'mark' and 'mkmk' the face registers for Arabic.

    A face that has the Quran's marks in its cmap but no 'mark'
    feature draws each one at a fixed place over the origin, not over
    the letter it belongs to — a fatha adrift from its letter is as
    wrong as a tofu box, only harder to see. 'mkmk' stacks one mark on
    another (a sukun on a shadda); a face without it is reported but
    not failed."""
    f = TTFont(path, lazy=True)
    if 'GPOS' not in f:
        return set()
    g = f['GPOS'].table
    out = set()
    for sr in (g.ScriptList.ScriptRecord if g.ScriptList else []):
        if sr.ScriptTag not in ('arab', 'DFLT'):
            continue
        systems = [sr.Script.DefaultLangSys] + [
            r.LangSys for r in sr.Script.LangSysRecord]
        for ls in systems:
            if ls is None:
                continue
            for i in ls.FeatureIndex:
                out.add(g.FeatureList.FeatureRecord[i].FeatureTag)
    return out & {'mark', 'mkmk'}


def name(c):
    try:
        return f'U+{ord(c):04X} {unicodedata.name(c)}'
    except ValueError:
        return f'U+{ord(c):04X}'


def optical(path, sample):
    """Mean ink height of [sample], and the font's own line height,
    both in em. What VerseFace.sizeFactor and .height are derived
    from."""
    f = TTFont(path, lazy=True)
    upem = f['head'].unitsPerEm
    gs = f.getGlyphSet()
    cm = f.getBestCmap()
    hs = []
    for ch in sample:
        gn = cm.get(ord(ch))
        if not gn:
            continue
        bp = BoundsPen(gs)
        try:
            gs[gn].draw(bp)
        except Exception:  # noqa: BLE001 - a face with no outline here
            continue
        if bp.bounds is None:
            continue
        hs.append((bp.bounds[3] - bp.bounds[1]) / upem)
    hh = f['hhea']
    nat = (hh.ascent - hh.descent + hh.lineGap) / upem
    return (sum(hs) / len(hs) if hs else 0.0), nat


def dart_numbers():
    """(sizeFactor, height) per family, per role, out of verse_font.dart.

    Per *role* and not just per family, because two families are on
    both lists — Noto Naskh Arabic and Scheherazade New set a verse and
    a translation — with different numbers for each, normalised against
    different references. Keying on the family alone kept whichever
    came first and silently never checked the other, while still
    printing that everything was in order.

    Both enums declare a face as `_Face('Family', size, height)`, which
    is the one shape this has to know."""
    src = open(DART, encoding='utf-8').read()
    split = src.index('enum TranslationFace')
    pattern = r"_Face\(\s*'([A-Za-z0-9]+)'\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)\s*\)"
    out = {}
    for role, chunk in (('verse', src[:split]), ('translation', src[split:])):
        out[role] = {
            m.group(1): (float(m.group(2)), float(m.group(3)))
            for m in re.finditer(pattern, chunk)
        }
    return out


def main():
    failures = []

    print('Fetching the Uthmani Arabic, whole …')
    arabic = get(f'{API}/quran/verses/uthmani')['verses']
    if len(arabic) != 6236:
        failures.append(f'Arabic returned {len(arabic)} verses, expected 6236')
    ar_used = set()
    for v in arabic:
        ar_used |= set(v['text_uthmani'])
    print(f'  {len(arabic)} verses, {len(ar_used)} distinct codepoints\n')

    print('=== the verse')
    for family, file in ARABIC_FACES:
        path = os.path.join(FONTS, file)
        if not os.path.exists(path):
            failures.append(f'{family}: {file} is not in assets/fonts/')
            print(f'  {family:32s} MISSING FILE')
            continue
        cm = cmap(path)
        missing = sorted(c for c in ar_used if ord(c) not in cm)
        kb = os.path.getsize(path) // 1024
        feats = mark_features(path)
        print(f'  {family:32s} {kb:4d}KB  '
              f'{"all 6236 verses" if not missing else str(len(missing)) + " MISSING"}'
              f'  {"+".join(sorted(feats)) or "NO GPOS MARK"}')
        if missing:
            failures.append(f'{family} cannot set the Quran: '
                            + ', '.join(name(c) for c in missing[:8]))
        if 'mark' not in feats:
            failures.append(f'{family} has no GPOS mark attachment for '
                            'Arabic; its marks would not sit on their letters')
    print()

    for eid, lang, script in EDITIONS:
        print(f'=== the translation — {lang}')
        texts = [clean(v['text'])
                 for v in get(f'{API}/quran/translations/{eid}')['translations']]
        used = set()
        for t in texts:
            used |= set(t)
        faces = LATIN_FACES if script == 'latin' else ARABIC_SCRIPT_FACES
        for family, files in faces:
            covered = set()
            for f in files:
                p = os.path.join(FONTS, f)
                if not os.path.exists(p):
                    failures.append(f'{family}: {f} is not in assets/fonts/')
                    continue
                covered |= cmap(p)
            fb = set()
            for f in LATIN_FALLBACK:
                fb |= cmap(os.path.join(FONTS, f))
            missing = sorted(c for c in used if ord(c) not in covered)
            by_fb = [c for c in missing if ord(c) in fb]
            bad = [c for c in missing if ord(c) not in fb]
            ok = ACCEPTED.get((family, lang), {})
            unexcused = [c for c in bad if ord(c) not in ok]
            note = 'complete' if not missing else (
                f'{len(by_fb)} via the fallback'
                + (f', {len(bad)} bare' if bad else ''))
            print(f'  {family:20s} {note}')
            for c in bad:
                why = ok.get(ord(c))
                print(f'      {"accepted" if why else "MISSING "} {name(c)}'
                      + (f'\n          {why}' if why else ''))
            if unexcused:
                failures.append(
                    f'{family} cannot set {lang}: '
                    + ', '.join(name(c) for c in unexcused[:8]))
        print()

    print('=== the optical numbers')
    nums = dart_numbers()
    for ref in ('UthmanicHafs.ttf', 'Inter.ttf', 'IBMPlexSansArabic.ttf'):
        if not os.path.exists(os.path.join(FONTS, ref)):
            failures.append(f'{ref} is missing; it is what every other '
                            'face on its list is measured against')
    if failures:
        print(f'\n{len(failures)} PROBLEM(S)')
        for f in failures:
            print(f'  - {f}')
        return 1
    ref_ar = optical(os.path.join(FONTS, 'UthmanicHafs.ttf'), ARABIC_SAMPLE)[0]
    ref_lat = optical(os.path.join(FONTS, 'Inter.ttf'), LATIN_SAMPLE)[0]
    # The rhythm the app has always set: line advance over ink height.
    ar_rhythm = 1.90 / ref_ar
    lat_rhythm = 1.50 / ref_lat
    ref_ur = optical(
        os.path.join(FONTS, 'IBMPlexSansArabic.ttf'), ARABIC_SAMPLE)[0]
    rows = ([('verse', f, file, ARABIC_SAMPLE, ref_ar, ar_rhythm)
             for f, file in ARABIC_FACES]
            + [('translation', f, files[0], LATIN_SAMPLE, ref_lat, lat_rhythm)
               for f, files in LATIN_FACES]
            + [('translation', f, files[0], ARABIC_SAMPLE, ref_ur,
                1.50 / ref_ur)
               for f, files in ARABIC_SCRIPT_FACES])
    seen = set()
    for role, family, file, sample, ref, rhythm in rows:
        path = os.path.join(FONTS, file)
        if not os.path.exists(path) or (role, family) in seen:
            continue
        seen.add((role, family))
        ink, nat = optical(path, sample)
        want_size = ref / ink if ink else None
        want_h = max(nat, rhythm * ink) if ink else nat
        got = nums[role].get(family)
        if got is None:
            failures.append(f'{family} is offered for the {role} but is '
                            'not named in verse_font.dart')
            print(f'  {family:32s} not named in verse_font.dart')
            continue
        size, height = got
        size_ok = want_size is None or abs(size - want_size) <= 0.06
        # Never below the face's own line height: that is where lines
        # start running into each other.
        h_ok = height >= nat - 0.02 and (want_h is None
                                         or abs(height - want_h) <= 0.16)
        print(f'  {family:32s} {role[:5]:5s} size {size:.2f} (derived '
              f'{want_size if want_size is None else round(want_size, 2)})'
              f'   height {height:.2f} (derived {round(want_h, 2)}, '
              f'font says {nat:.2f})'
              f'  {"ok" if size_ok and h_ok else "OFF"}')
        if not size_ok:
            failures.append(f'{family}: sizeFactor {size} is not the '
                            f'{want_size:.2f} its metrics ask for')
        if not h_ok:
            failures.append(f'{family}: height {height} is wrong for a face '
                            f'whose own line box is {nat:.2f}')

    print()
    if failures:
        print(f'{len(failures)} PROBLEM(S)')
        for f in failures:
            print(f'  - {f}')
        return 1
    print('Every face sets every verse and every edition it is offered for.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
