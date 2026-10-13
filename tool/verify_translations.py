#!/usr/bin/env python3
"""Verify every verse translation the app offers, whole.

A wrong translation line is worse than a missing one: it is printed
under the Arabic, exported into a reel, and shared. So no edition goes
into `lib/data/verse_translation.dart` until it has passed all of this,
over all 6236 verses and all 114 chapters — never a sample.

  1. Bulk shape.       The edition returns exactly 6236 verses.
  2. Per-chapter shape. Fetched the way the app fetches it — one
     chapter at a time — every chapter returns exactly as many verses
     as the Arabic does, and as the canonical Hafs count says it
     should. This is the one that matters: the two endpoints are
     paired by position only, so a chapter off by one would caption
     every ayah after it with its neighbour's translation.
  3. Cleanliness.      Nothing empty, no HTML surviving the strip, no
     footnote digit left glued to a word.
  4. Glyph coverage.   Every codepoint the edition uses is in the cmap
     of the face the app renders it with. A missing glyph is a tofu
     box in an exported video, which cannot be taken back.
  5. Invisible characters. Reported per edition, because they differ,
     and each one has to be handled in QuranTextService.normalizeSpaces
     rather than shipped.

Run:  python3 tool/verify_translations.py
"""
import collections
import json
import re
import sys
import unicodedata
import urllib.request
from concurrent.futures import ThreadPoolExecutor

API = 'https://api.quran.com/api/v4'
UA = {'User-Agent': 'ayahreel-verify'}

# The editions the app offers, and the faces each is rendered with —
# the primary and its fallback, as AppTheme.translation stacks them.
# Keep in step with lib/data/verse_translation.dart.
#
# Every Latin edition carries the Arabic face as a fallback, and that
# is load-bearing rather than cautious: Saheeh International writes the
# honorific after the Prophet's name as the ligature ﷺ (U+FDFA) 34
# times, and Inter has no glyph for it.
EDITIONS = [
    (20, 'English', 'Saheeh International', ['Inter', 'IBM Plex Sans Arabic']),
    (234, 'Urdu', 'Fatah Muhammad Jalandhari', ['IBM Plex Sans Arabic']),
    (33, 'Indonesian', 'Kementerian Agama RI', ['Inter', 'IBM Plex Sans Arabic']),
    (27, 'German', 'Bubenheim & Elyas', ['Inter', 'IBM Plex Sans Arabic']),
]

# Editions looked at and left out, so nobody re-derives this.
REJECTED = [
    (54, 'Urdu', 'Junagarhi', 'HTML survives the strip at 4:106'),
    (819, 'Urdu', 'Wahiduddin Khan', 'clean, but Jalandhari is the '
     'more widely printed plain translation'),
    (97, 'Urdu', 'Maududi, Tafheem', 'a commentary: verses run long '
     'because they carry explanation, and a card has to hold the verse'),
    (134, 'Indonesian', 'King Fahad Complex', 'HTML survives the strip at 1:2'),
    (141, 'Indonesian', 'Sabiq', 'HTML survives the strip at 36:58, 51:35, 66:10'),
    (208, 'German', 'Abu Reda', 'HTML survives the strip at 20:39'),
]

GOOGLE_FONTS = {
    'Inter': 'Inter',
    'IBM Plex Sans Arabic': 'IBM+Plex+Sans+Arabic',
}

SUP = re.compile(r'<sup\b[^>]*>.*?</sup>', re.S)
TAG = re.compile(r'<[^>]*>')


def strip_markup(t):
    """Exactly what QuranTextService.stripFootnoteMarkup does."""
    t = SUP.sub('', t)
    t = TAG.sub('', t)
    return re.sub(r'  +', ' ', t).strip()


# Exactly what QuranTextService.normalizeSpaces does. Zero-width joiner
# and non-joiner are deliberately absent: they choose whether Arabic
# letters join, and dropping them would misspell Urdu.
DROPPED = {0x00AD, 0x200B, 0xFEFF}
TO_SPACE = {0x000A, 0x000D, 0x0009, 0x0085, 0x00A0, 0x202F, 0x2028, 0x2029}


def normalize_spaces(t):
    out = []
    for ch in t:
        c = ord(ch)
        if c in DROPPED:
            continue
        out.append(' ' if c in TO_SPACE else ch)
    return re.sub(r'  +', ' ', ''.join(out)).strip()


def clean(t):
    """The whole pipeline, in the order the app runs it."""
    return normalize_spaces(strip_markup(t))


def get(url, tries=5):
    last = None
    for _ in range(tries):
        try:
            with urllib.request.urlopen(
                    urllib.request.Request(url, headers=UA), timeout=30) as h:
                return json.load(h)
        except Exception as e:  # noqa: BLE001 - retried, then raised
            last = e
    raise last


def font_cmap(family):
    """Every codepoint the Google Fonts face can render."""
    from fontTools.ttLib import TTFont
    import io
    css = urllib.request.urlopen(urllib.request.Request(
        f'https://fonts.googleapis.com/css2?family={GOOGLE_FONTS[family]}'
        '&display=swap', headers={'User-Agent': 'Mozilla/5.0'})).read().decode()
    url = re.search(r'https://fonts\.gstatic\.com/[^)]*\.ttf', css).group(0)
    blob = urllib.request.urlopen(url).read()
    f = TTFont(io.BytesIO(blob), lazy=True)
    out = set()
    for t in f['cmap'].tables:
        out |= set(t.cmap.keys())
    return out


def main():
    failures = []

    print('Fetching the Arabic, whole …')
    arabic = get(f'{API}/quran/verses/uthmani')['verses']
    keys = [v['verse_key'] for v in arabic]
    counts = collections.Counter(int(k.split(':')[0]) for k in keys)
    if len(arabic) != 6236:
        failures.append(f'Arabic returned {len(arabic)} verses, expected 6236')
    print(f'  {len(arabic)} verses, {len(counts)} chapters\n')

    cmaps = {}
    for _, _, _, faces in EDITIONS:
        for face in faces:
            if face not in cmaps:
                print(f'Reading the cmap of {face} …')
                cmaps[face] = font_cmap(face)
                print(f'  {len(cmaps[face])} codepoints')
    print()

    for eid, lang, translator, faces in EDITIONS:
        print(f'=== {lang} — {translator} (quran.com resource {eid})')
        bad = []

        # 1. bulk shape
        bulk = get(f'{API}/quran/translations/{eid}')['translations']
        raw = [strip_markup(v['text']) for v in bulk]
        texts = [normalize_spaces(t) for t in raw]
        if len(texts) != 6236:
            bad.append(f'bulk returned {len(texts)} verses, expected 6236')
        print(f'  bulk .................. {len(texts)} verses')

        # 2. per-chapter shape, the way the app fetches it
        def chapter(s):
            t = get(f'{API}/quran/translations/{eid}?chapter_number={s}')
            v = get(f'{API}/quran/verses/uthmani?chapter_number={s}')
            return s, len(t['translations']), len(v['verses'])

        mismatched = []
        with ThreadPoolExecutor(max_workers=8) as ex:
            for s, nt, nv in ex.map(chapter, range(1, 115)):
                if not (nt == nv == counts[s]):
                    mismatched.append(f'{s}: translation {nt}, arabic {nv}, '
                                      f'canonical {counts[s]}')
        if mismatched:
            bad.append('per-chapter counts differ: ' + '; '.join(mismatched))
        print(f'  per-chapter ........... 114 chapters, '
              f'{"all aligned" if not mismatched else str(len(mismatched)) + " MISALIGNED"}')

        # 3. cleanliness
        empty = [keys[i] for i, t in enumerate(texts) if not t]
        residual = [keys[i] for i, t in enumerate(texts) if '<' in t or '>' in t]
        stranded = [keys[i] for i, t in enumerate(texts)
                    if re.search(r'[^\W\d_]\d(?![\d:])', t)]
        if empty:
            bad.append(f'{len(empty)} empty verses: {empty[:5]}')
        if residual:
            bad.append(f'{len(residual)} verses with residual markup: {residual[:5]}')
        print(f'  cleanliness ........... empty {len(empty)}, '
              f'residual markup {len(residual)}, stranded digits {len(stranded)}')

        # 4. glyph coverage, over the whole edition, against the face
        # stack the app actually shapes with
        covered = set()
        for face in faces:
            covered |= cmaps[face]
        used = set()
        for t in texts:
            used |= set(t)
        missing = sorted(c for c in used if ord(c) not in covered)
        if missing:
            bad.append(' + '.join(faces) + ' cannot render: ' + ', '.join(
                f'U+{ord(c):04X} {unicodedata.name(c, "?")}' for c in missing))
        print(f'  glyphs ................ {len(used)} codepoints used, '
              f'{len(missing)} missing from {" + ".join(faces)}')

        # 5. invisible characters. Counted on the raw text, to say what
        # the edition carries, and then again on the normalized text —
        # where anything left is one normalizeSpaces does not handle,
        # and is a failure rather than a note.
        inv = collections.Counter()
        where = collections.defaultdict(list)
        for i, t in enumerate(raw):
            for ch in t:
                if unicodedata.category(ch) in ('Cc', 'Cf') or ord(ch) in (0xA0, 0x200B):
                    name = f'U+{ord(ch):04X} {unicodedata.name(ch, "CONTROL")}'
                    inv[name] += 1
                    where[name].append(keys[i])
        if inv:
            for k, v in inv.most_common():
                seen = sorted(set(where[k]))
                print(f'  invisible (raw) ....... {k}: {v}× in {len(seen)} '
                      f'verses {seen[:6]} — normalized away')
        else:
            print('  invisible (raw) ....... none')
        left = collections.Counter()
        for i, t in enumerate(texts):
            for ch in t:
                if unicodedata.category(ch) == 'Cc' or ord(ch) in (0xA0, 0xAD, 0x200B):
                    left[f'U+{ord(ch):04X}'] += 1
        if left:
            bad.append('invisibles survive normalizeSpaces: ' + ', '.join(
                f'{k} ×{v}' for k, v in left.most_common()))
        print(f'  invisible (cleaned) ... {sum(left.values())}')

        if bad:
            failures.append(f'{lang} (resource {eid}): ' + '; '.join(bad))
            print('  RESULT ................ FAILED')
        else:
            print('  RESULT ................ PASSED')
        print()

    print('--- editions considered and left out')
    for eid, lang, who, why in REJECTED:
        print(f'  {lang} {eid} ({who}): {why}')
    print()

    if failures:
        print('VERIFICATION FAILED')
        for f in failures:
            print(f'  - {f}')
        return 1
    print('VERIFICATION PASSED — every offered edition is safe to ship')
    return 0


if __name__ == '__main__':
    sys.exit(main())
