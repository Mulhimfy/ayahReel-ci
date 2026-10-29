#!/usr/bin/env python3
"""Fetch (and, for the Latin faces, subset) every face the verse card
offers, into assets/fonts/.

The faces a reel is *typeset* with are bundled rather than fetched at
runtime, unlike the app's own chrome. Three reasons, in order:

  1. A reel is burned once. A face that had not finished downloading
     when the exporter rasterized the card would be baked into an mp4
     the user cannot take back — and the app is offline-first by
     design (see the README's cold-install note).
  2. The picker has to *show* the faces. A grid of eleven previews
     that all render in the fallback is not a picker.
  3. Tests can read the metrics off a real file.

Every face here is under the SIL Open Font License, which permits
bundling. Provenance and licences are listed in assets/fonts/README.md.

The Latin faces are subsetted to the Latin ranges a translation can
use — Google Fonts' own woff2 files are subsets for the same reason —
which roughly halves each of them. The run prints what it saved. The Arabic faces are
shipped whole: their shaping lives in GSUB/GPOS tables that a subset
has no business pruning, and the saving would not pay for the risk.

Run:  python3 tool/fetch_fonts.py [File.ttf ...]
Then: python3 tool/verify_fonts.py

Name files to fetch only those — e.g. a face just added — and leave
every other file, and the optical numbers derived from it, alone.
"""
import io
import os
import re
import sys
import urllib.request

UA = {'User-Agent': 'Mozilla/5.0'}
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'fonts')
MARK_OUT = os.path.join(
    os.path.dirname(__file__), '..', 'assets', 'google_fonts')

# family -> (Google Fonts query, file name, weight, italic, subset?)
#
# A weight is its own static file, fetched by asking css2 for that one
# weight (`:wght@700`) of the family: Google instances a variable
# family server-side and serves a plain ttf. Each is registered in
# pubspec.yaml as a family of its own (NotoKufiArabicBold, …), so a
# weight is chosen the way a face is — by name — and verified the way
# a face is: its cmap is a different file's cmap.
#
# KFGQPC Uthmanic Hafs (UthmanicHafs.ttf), the default verse face, is
# not on Google Fonts and is not fetched here; see the README.
FACES = [
    # --- the verse: Arabic faces, shipped whole -------------------
    ('Amiri Quran', 'Amiri+Quran', 'AmiriQuran.ttf', '400', False, False),
    ('Scheherazade New', 'Scheherazade+New', 'ScheherazadeNew.ttf',
     '400', False, False),
    ('Noto Naskh Arabic', 'Noto+Naskh+Arabic', 'NotoNaskhArabic.ttf',
     '400', False, False),
    ('Lateef', 'Lateef', 'Lateef.ttf', '400', False, False),
    # Amiri's text cut, beside the Quran cut above it: the same hand
    # with ordinary marks, which is a different page.
    ('Amiri', 'Amiri', 'Amiri.ttf', '400', False, False),
    # A kufi, and the one face here that is not a naskh at all.
    ('Noto Kufi Arabic', 'Noto+Kufi+Arabic', 'NotoKufiArabic.ttf',
     '400', False, False),
    ('Mada', 'Mada', 'Mada.ttf', '400', False, False),
    ('Noto Sans Arabic', 'Noto+Sans+Arabic', 'NotoSansArabic.ttf',
     '400', False, False),
    ('Harmattan', 'Harmattan', 'Harmattan.ttf', '400', False, False),
    # Weights of the faces above, and the faces that joined with them.
    # IBM Plex Sans Arabic sets the verse too, off the Urdu file below.
    ('Noto Naskh Arabic Bold', 'Noto+Naskh+Arabic', 'NotoNaskhArabicBold.ttf',
     '700', False, False),
    ('Amiri Bold', 'Amiri', 'AmiriBold.ttf', '700', False, False),
    ('Lateef Bold', 'Lateef', 'LateefBold.ttf', '700', False, False),
    ('Harmattan Bold', 'Harmattan', 'HarmattanBold.ttf', '700', False, False),
    ('Noto Kufi Arabic Thin', 'Noto+Kufi+Arabic', 'NotoKufiArabicThin.ttf',
     '100', False, False),
    ('Noto Kufi Arabic Bold', 'Noto+Kufi+Arabic', 'NotoKufiArabicBold.ttf',
     '700', False, False),
    ('Noto Sans Arabic ExtraLight', 'Noto+Sans+Arabic',
     'NotoSansArabicExtraLight.ttf', '200', False, False),
    ('Noto Sans Arabic Black', 'Noto+Sans+Arabic', 'NotoSansArabicBlack.ttf',
     '900', False, False),
    # The width axis, pinned at its narrowest (62.5, ExtraCondensed).
    ('Noto Sans Arabic ExtraCondensed', 'Noto+Sans+Arabic:wdth,wght@62.5,400',
     'NotoSansArabicExtraCondensed.ttf', None, False, False),
    ('Noto Sans Arabic ExtraCondensed Bold',
     'Noto+Sans+Arabic:wdth,wght@62.5,700',
     'NotoSansArabicExtraCondensedBold.ttf', None, False, False),
    ('IBM Plex Sans Arabic Bold', 'IBM+Plex+Sans+Arabic',
     'IBMPlexSansArabicBold.ttf', '700', False, False),
    ('Mada Light', 'Mada', 'MadaLight.ttf', '300', False, False),
    ('Estedad', 'Estedad', 'Estedad.ttf', '400', False, False),
    ('Estedad Black', 'Estedad', 'EstedadBlack.ttf', '900', False, False),
    ('Jomhuria', 'Jomhuria', 'Jomhuria.ttf', '400', False, False),
    # --- the translation: Arabic script (Urdu) --------------------
    ('IBM Plex Sans Arabic', 'IBM+Plex+Sans+Arabic',
     'IBMPlexSansArabic.ttf', '400', False, False),
    ('Noto Nastaliq Urdu', 'Noto+Nastaliq+Urdu', 'NotoNastaliqUrdu.ttf',
     '400', False, False),
    # Markazi Text — the Amiri author's text face, cut for Persian and
    # Urdu as much as for Arabic.
    ('Markazi Text', 'Markazi+Text', 'MarkaziText.ttf', '400', False, False),
    ('Katibeh', 'Katibeh', 'Katibeh.ttf', '400', False, False),
    ('Mirza', 'Mirza', 'Mirza.ttf', '400', False, False),
    # --- the card: Arabic display faces, shipped whole -----------
    ('Cairo', 'Cairo', 'Cairo.ttf', '400', False, False),
    ('Almarai', 'Almarai', 'Almarai.ttf', '400', False, False),
    ('Changa', 'Changa', 'Changa.ttf', '400', False, False),
    ('El Messiri', 'El+Messiri', 'ElMessiri.ttf', '400', False, False),
    ('Reem Kufi', 'Reem+Kufi', 'ReemKufi.ttf', '400', False, False),
    ('Aref Ruqaa', 'Aref+Ruqaa', 'ArefRuqaa.ttf', '400', False, False),
    ('Qahiri', 'Qahiri', 'Qahiri.ttf', '400', False, False),
    ('Vazirmatn', 'Vazirmatn', 'Vazirmatn.ttf', '400', False, False),
    # --- the translation: Latin script, subsetted -----------------
    ('Inter', 'Inter', 'Inter.ttf', '400', False, True),
    ('Inter Italic', 'Inter:ital,wght@1,400', 'InterItalic.ttf',
     None, True, True),
    ('Source Serif 4', 'Source+Serif+4', 'SourceSerif4.ttf',
     '400', False, True),
    ('Spectral', 'Spectral', 'Spectral.ttf', '400', False, True),
    ('Cormorant Garamond', 'Cormorant+Garamond', 'CormorantGaramond.ttf',
     '400', False, True),
    ('Literata', 'Literata', 'Literata.ttf', '400', False, True),
    ('EB Garamond', 'EB+Garamond', 'EBGaramond.ttf', '400', False, True),
    ('Libre Baskerville', 'Libre+Baskerville', 'LibreBaskerville.ttf',
     '400', False, True),
    ('Crimson Pro', 'Crimson+Pro', 'CrimsonPro.ttf', '400', False, True),
    ('Crimson Text', 'Crimson+Text', 'CrimsonText.ttf', '400', False, True),
    ('Cardo', 'Cardo', 'Cardo.ttf', '400', False, True),
    ('Vollkorn', 'Vollkorn', 'Vollkorn.ttf', '400', False, True),
    ('Alegreya', 'Alegreya', 'Alegreya.ttf', '400', False, True),
    ('Bitter', 'Bitter', 'Bitter.ttf', '400', False, True),
    ('Rokkitt', 'Rokkitt', 'Rokkitt.ttf', '400', False, True),
    ('Cormorant', 'Cormorant', 'Cormorant.ttf', '400', False, True),
    ('Rasa', 'Rasa', 'Rasa.ttf', '400', False, True),
    ('Yrsa', 'Yrsa', 'Yrsa.ttf', '400', False, True),
    ('Work Sans', 'Work+Sans', 'WorkSans.ttf', '400', False, True),
    ('Space Grotesk', 'Space+Grotesk', 'SpaceGrotesk.ttf', '400', False, True),
    ('Mulish', 'Mulish', 'Mulish.ttf', '400', False, True),
    ('Nunito Sans', 'Nunito+Sans', 'NunitoSans.ttf', '400', False, True),
    ('Raleway', 'Raleway', 'Raleway.ttf', '400', False, True),
    ('Quicksand', 'Quicksand', 'Quicksand.ttf', '400', False, True),
    ('Montserrat', 'Montserrat', 'Montserrat.ttf', '400', False, True),
    ('Urbanist', 'Urbanist', 'Urbanist.ttf', '400', False, True),
    ('Public Sans', 'Public+Sans', 'PublicSans.ttf', '400', False, True),
    ('Plus Jakarta Sans', 'Plus+Jakarta+Sans', 'PlusJakartaSans.ttf',
     '400', False, True),
    ('Epilogue', 'Epilogue', 'Epilogue.ttf', '400', False, True),
    ('Domine', 'Domine', 'Domine.ttf', '400', False, True),
    ('Petrona', 'Petrona', 'Petrona.ttf', '400', False, True),
    # --- the card: Latin display faces, subsetted -----------------
    ('Playfair Display', 'Playfair+Display', 'PlayfairDisplay.ttf',
     '400', False, True),
    ('Marcellus', 'Marcellus', 'Marcellus.ttf', '400', False, True),
    ('Cinzel', 'Cinzel', 'Cinzel.ttf', '400', False, True),
    ('Gilda Display', 'Gilda+Display', 'GildaDisplay.ttf', '400', False, True),
    ('Italiana', 'Italiana', 'Italiana.ttf', '400', False, True),
    ('Tenor Sans', 'Tenor+Sans', 'TenorSans.ttf', '400', False, True),
    ('Prata', 'Prata', 'Prata.ttf', '400', False, True),
    ('Bodoni Moda', 'Bodoni+Moda', 'BodoniModa.ttf', '400', False, True),
    ('DM Serif Display', 'DM+Serif+Display', 'DMSerifDisplay.ttf',
     '400', False, True),
    ('Josefin Sans', 'Josefin+Sans', 'JosefinSans.ttf', '400', False, True),
    ('Jost', 'Jost', 'Jost.ttf', '400', False, True),
    ('Outfit', 'Outfit', 'Outfit.ttf', '400', False, True),
]

# The faces google_fonts is asked for *by name* inside a picture the
# app exports, bundled where google_fonts itself will find them.
#
# Everything the app draws as chrome takes its face from google_fonts,
# which resolves over the network and falls back silently when it
# cannot. That is fine for a button and wrong for the AyahReel mark:
# the mark is burned into every exported reel and every exported card,
# and a face that had not landed yet is baked in as the fallback — on
# exactly the phones this app is built for, which are the ones with no
# connection.
#
# google_fonts looks in the asset manifest before it looks at the
# network (see _findFamilyWithVariantAssetPath): any bundled asset
# whose name ends in `<Family>-<Variant>.ttf` is used as that face. So
# the one variant the mark is set in ships as an asset under the name
# google_fonts asks for, and the mark resolves offline, synchronously,
# at the weight it was designed at.
#
# (family, query, api filename, weight)
MARK_FACES = [
    ('Inter Medium', 'Inter', 'Inter-Medium.ttf', '500'),
]

# What a Latin translation may use, generously: ASCII, Latin-1, Latin
# Extended-A and -B, the spacing modifiers and combining marks a
# transliteration needs, Latin Extended Additional (ḥ ṣ ṭ ẓ ḍ — Saheeh
# International is full of them), and general punctuation. Four
# editions use 81 codepoints between them; this keeps ~700, so a fifth
# edition does not need a new subset.
UNICODES = (
    '0020-007E,00A0-00FF,0100-017F,0180-024F,02B0-02FF,0300-036F,'
    '1E00-1EFF,2000-206F,20A0-20BF,2122,FB01-FB02'
)


def ttf_url(query, weight):
    url = f'https://fonts.googleapis.com/css2?family={query}'
    if weight and ':' not in query:
        url += f':wght@{weight}'
    url += '&display=swap'
    css = urllib.request.urlopen(
        urllib.request.Request(url, headers=UA), timeout=60).read().decode()
    m = re.search(r'https://fonts\.gstatic\.com/[^)]*\.ttf', css)
    if not m:
        raise SystemExit(f'no ttf in the css for {query}')
    return m.group(0)


def subset_latin(blob):
    from fontTools import subset as ss
    from fontTools.ttLib import TTFont
    font = TTFont(io.BytesIO(blob))
    opts = ss.Options()
    opts.layout_features = ['*']   # keep kerning, ligatures, all of it
    opts.name_IDs = ['*']
    opts.notdef_outline = True
    opts.recalc_bounds = False     # the metrics must not move
    sub = ss.Subsetter(options=opts)
    sub.populate(unicodes=ss.parse_unicodes(UNICODES))
    sub.subset(font)
    buf = io.BytesIO()
    font.save(buf)
    return buf.getvalue()


def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(MARK_OUT, exist_ok=True)
    only = set(sys.argv[1:])
    total = 0
    for family, query, name, weight in MARK_FACES:
        if only and name not in only:
            continue
        blob = urllib.request.urlopen(
            urllib.request.Request(ttf_url(query, weight), headers=UA),
            timeout=180).read()
        before = len(blob)
        blob = subset_latin(blob)
        with open(os.path.join(MARK_OUT, name), 'wb') as f:
            f.write(blob)
        total += len(blob)
        print(f'{family:24s} -> google_fonts/{name:11s} '
              f'{len(blob) // 1024:4d}KB  (subset from {before // 1024}KB)')
    for family, query, name, weight, italic, subset in FACES:
        if only and name not in only:
            continue
        url = ttf_url(query, weight)
        blob = urllib.request.urlopen(
            urllib.request.Request(url, headers=UA), timeout=180).read()
        before = len(blob)
        if subset:
            blob = subset_latin(blob)
        path = os.path.join(OUT, name)
        with open(path, 'wb') as f:
            f.write(blob)
        total += len(blob)
        note = f'  (subset from {before // 1024}KB)' if subset else ''
        print(f'{family:24s} -> {name:24s} {len(blob) // 1024:4d}KB{note}')
    print(f'\n{total // 1024}KB of faces written to assets/fonts/')


if __name__ == '__main__':
    sys.exit(main())
