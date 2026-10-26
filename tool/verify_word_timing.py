#!/usr/bin/env python3
"""Can the word timings the Quranic Universal Library publishes be put
on the audio the app plays — voice by voice, and how precisely?

QUL (qul.tarteel.ai, by Tarteel) publishes where every word of a verse
starts and ends: for surah recitations against its own whole-surah
recordings (`surah_segments`), and for one ayah recitation against
per-verse files (`ayah_segments`). The app plays other files: per-ayah
sets (EveryAyah, KSU, Tarteel) and mp3quran or quranicaudio surah files
(see verify_reciters.py). A QUL timing is only worth anything on our
audio where QUL's recording *is* our recording and where the two
timelines meet. This tool measures both, per voice in CANDIDATES, and
writes tool/word_timing_verified.json.

1. Words at all.   Many QUL recitations listed with has_segments carry
   verse windows only, every word list empty. All 114 surahs are read;
   a voice with none is `no_words`.
2. The same file.  A surah voice whose files are QUL's own (the same
   size, the same first and last 64 KB, in all 114 surahs) is `exact`:
   QUL's times are the file's times. So is an ayah recitation that
   names our own file for every verse (Nufais, QUL ayah recitation 42).
3. The same recording.  A sample of 31 verses in 11 runs over 10 surahs
   (RUNS: short surahs first; 2:254-256, 2:282, 3:7-8 and 18:110 for
   length; seven verse 1s, where the basmala is). Our verse audio, cut
   exactly as the app cuts it (the per-ayah file; or the mp3quran slice
   and SurahSlice.plan's snapped window, mirrored here), is looked for in
   QUL's audio near QUL's own window: normalised cross-correlation of
   the waveforms at 8 kHz, for 1.5 s stretches from the verse's start
   to its end (`locate`). The same recording peaks at 0.93-1.00, every
   stretch at one offset (within 9 ms over a two-minute verse: no
   drift); another recording peaks at 0.1-0.3. That offset is the
   ground truth: the QUL time of our window's t=0. A voice nothing
   matches in after EARLY verses is `different` and let go.
   QUL's audio comes as byte ranges cut by verify_reciters.fetch_slice
   (constant-bitrate files). Such a slice decodes 1105 samples late
   against the whole file when the file opens with a LAME header —
   ffmpeg skips the encoder and decoder delay at the start of a file,
   never inside a slice — and not at all when it doesn't: measured on
   every file the sample sliced (slice_bias: 86 files, 46 with the
   header at -1105/rate exactly, 40 without at 0 to within 0.05 ms),
   used as lame_bias in the survey. The app's own
   surah slices carry the same offset against their tables (-25 ms at
   44.1 kHz in a LAME file), which is below what a highlight can show.
4. Every surah.    A recording can be ours in one surah and another in
   the next (QUL 161's Al-Fatiha and Ibrahim, 170's Al-Kahf), which no
   sample can rule out. For a voice that passes 3, verses 1 and 2 of all
   114 surahs are located the same way (`survey`): which surahs to leave
   out, how verse 1 behaves in each, and for a surah-file voice where
   QUL's time is in our file's, surah by surah.
5. The mapping the app can run with no QUL audio, only our window's
   loudness (SurahSlice.envelopeOf, mirrored by app_envelope) and QUL's
   numbers, judged word by word against the ground truth (`mapped`):
   shift, t = o + (s - F) + bias, where o is our onset — the first 10 ms
   frame above SurahSlice.quietBelow(the window's envelope) that stays
   above it MAP_RUN frames — and F is QUL's first word start; and, for
   comparison, affine (scaled to our offset f and QUL's last word end
   E), end-anchored (t = f - (E - s)), and table (t = s - time_from).
   The span check as first proposed, |(f - o) - (E - F)| <= max(150 ms,
   3%), is scored on same-recording verses, on verses that are another
   recording, and on our audio against another reciter's words — it
   throws away half the good verses and keeps a fifth of the wrong
   ones, because E is not where the sound ends. What a runtime check
   can do is catch an onset that is not the verse's (a file opening on
   the end of the verse before; a verse 1 whose QUL words hold the
   basmala): max(GROSS_MS, GROSS_REL) is the one recommended (gross_ok).
   Telling recordings apart is the survey's job; nothing at runtime can.
6. The text.       QUL's word positions per verse against the app's
   words (QPC text as QuranTextService shows it, split on spaces, letter
   tokens only), for every recitation with words, all 6236 verses.
7. An estimate from the text alone, for voices with no word data: the
   verse's pauses, its words cut into breath groups, and a tajweed
   length model fitted by least squares on half the same-recording
   voices and tested on the other half (`estimate_starts`).

What it found (2026-10-21; tool/word_timing_verified.json has it all):
  exact     albanna and toure play QUL's own files (129, 172; all 114
            identical); nufais plays the files QUL ayah recitation 42
            times (all 6236 named, 61 sizes identical).
  offset    ghamdi (13) and salimi (179): the same recording in all 114
            surahs, at one offset per surah (verse 1 and 2 agree to
            6 ms; ghamdi drifts -13 ppm across a surah).
  shift     tunaiji (161), husary_mujawwad (164), abdulkareem (70),
            ajmi (19, which QUL times in surahs 1-26 only), dussary
            (174): over 50-138 verses each, after the check, a median
            of 12-27 ms, p90 36-111 ms. QUL has another recording in
            some surahs (161: 1, 10, 13, 14, 72; 164: 17, 62; 174: 9).
  off       abbad (14: QUL's first words don't start at the sound; p90
            283 ms), jaleel (170: another recording in Al-Fatiha 2-4
            and Al-Kahf, and its Aal-Imran 33 s off its own audio),
            muaiqly (65 and 159 are other recordings), and fifteen
            voices whose QUL recitations have no words at all.
  text      QUL's words are the app's but in two verses' worth of joins:
            most recitations count 37:130's إِلْ يَاسِينَ as one word; 14,
            159, 170 and 172 count 2:181, 8:6 and 13:37's بَعْدَ مَا as one
            (Nufais' 42: 13:37 only); 179 has three words short in 22:5.
  estimate  from the text alone, held out by voice: a median of 382 ms,
            26% of word starts within 150 ms. Not enough to light words.

What QUL's numbers are (measured, all recitations sampled): a verse's
time_from is the previous verse's time_to plus 200 ms in most of them,
not a sound; time_to is its last word's end, 0.3-0.5 s past the end of
the sound, wandering a few hundred ms (and the file's end for a
surah's last verse); the first word's start is where the sound starts,
to tens of ms, in most recitations, but not in 14, 170 or 175 (there it
is often time_from itself). Verse 1's first word always starts at
time_from: where QUL's file opens with the isti'adha or the basmala,
that word holds them (14, 19, 129; Al-Fatiha in 70, 164, 179). Words
are gap-filled, and a reciter going back over words shows as positions
falling back (5-30% of verses).

How the thresholds were set: a same-recording stretch peaks at 0.77
or more (nearly all above 0.93), the best stretch of a same-recording
verse at 0.90 or more; another recording's at 0.1-0.47, but a few
other takes reach 0.62-0.69 in one stretch, at offsets that wander up
to 80 ms inside a verse. Hence SAME_PEAK 0.6 for a stretch, AGREE_MS
20 between stretches, and STRONG_PEAK 0.8 for the best. MAP_REL and
MAP_RUN are quietBelow's own pauseRel and a 50 ms hold: over the
window, that rule's p90 is within 20 ms of the best rule tried for
every voice, where each other rule fails one badly (quietBelow at 0.2:
3.8 s for Husary mujawwad's long silences; at 0.5: 170-190 ms worst
cases; 20 or 30 dB under the speech level: p90 140-270 ms for three).

Run:  python3 tool/verify_word_timing.py            # everything
      python3 tool/verify_word_timing.py --only ID  # one voice (repeatable)
Heavy (downloads and decodes ~1 GB; an hour or more from a cold cache):
run it as `flock /tmp/heavy.lock nice -n 15 python3 -I tool/...`.
Cache: build/verify_word_timing (gitignored); delete it to measure
afresh. Audio is deleted as each voice is done.
"""
import argparse
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import verify_reciters as vr  # noqa: E402

ROOT = vr.ROOT
CACHE = os.path.join(ROOT, 'build', 'verify_word_timing')
vr.CACHE = CACHE  # verify_reciters' helpers (layout, cached_json) cache here
OUT = os.path.join(ROOT, 'tool', 'word_timing_verified.json')
QUL = 'https://qul.tarteel.ai/api/v1/audio'
TEXT_API = 'https://api.quran.com/api/v4/quran/verses/uthmani'
COUNTS = vr.COUNTS

# Our voice -> QUL recitations that may be the same reciter, alternates
# in order ('ayah:N' is an ayah recitation). Matched by name in QUL's
# surah_recitations and ayah_recitations lists (2026-10-21). Muhammad
# AbdulKareem's 70 is listed has_segments false, yet has words for 6235
# verses. The twelve voices quran-align already times (alafasy, husary,
# ...) have QUL recitations too and are left alone; every other voice's
# namesake in QUL (Ayyub 22, Haneef 40/125, Khayyat 72, Al-Yamani 130,
# As-Sayegh 23, Al-Akhdar 103, Nabil Ar-Rifai 165, Al-Qahtani 166,
# Al-Hudhaify 167) has no segments at all.
CANDIDATES = {
    'muaiqly': [65, 159], 'dussary': [97, 174], 'ajmi': [19],
    'qatami': [104], 'juhani': [162], 'budair': [43], 'jibreel': [169],
    'basfar': [163], 'bukhatir': [18], 'matrood': [124], 'neana': [126],
    'alaqimy': [127], 'suesy': [128], 'alili': [44], 'sahl_yassin': [17],
    'jaber': [158], 'abbad': [14], 'tunaiji': [161],
    'husary_mujawwad': [164], 'mustafa_ismail': [88],
    'nufais': ['ayah:42', 175], 'albanna': [129], 'toure': [172],
    'jaleel': [170], 'ghamdi': [13], 'balilah': [160], 'salimi': [179],
    'abdulkareem': [70],
}
STYLES = {'husary_mujawwad': 'mujawwad'}  # the rest are murattal


# ---- the text the app displays ----------------------------------------

def is_letter_token(tok):
    """WordAlignService._isLetterToken, exactly."""
    return any(0x0621 <= ord(c) <= 0x064A or 0x066E <= ord(c) <= 0x06D3 or
               ord(c) == 0x06D5 for c in tok)


def _bare(s):
    """QuranTextService._letters."""
    out = []
    for c in s:
        o = ord(c)
        if 0x064B <= o <= 0x065F or o in (0x0670, 0x0640, 0x0653):
            continue
        out.append('ا' if o == 0x0671 else c)
    return ''.join(out)


def display_text(surah, ayah, raw):
    """What QuranTextService shows for a verse: text_uthmani trimmed,
    the mirrored iqlab meem dropped, the circles stripped, and a
    leading basmala (verse 1 outside 1 and 9) cut off."""
    t = raw.strip()
    out, prev = [], 0
    for c in t:
        o = ord(c)
        mirrored = (o == 0x06ED and prev in (0x064B, 0x064C)) or \
            (o == 0x06E2 and prev == 0x064D)
        if not mirrored:
            out.append(c)
        prev = o
    t = ''.join(c for c in out if ord(c) not in (0x06DF, 0x06E0, 0x06DE,
                                                 0x06DD))
    t = re.sub(r'  +', ' ', t).strip()
    if ayah == 1 and surah not in (1, 9):
        w = t.split(' ')
        if len(w) >= 5 and _bare(' '.join(w[:4])) == \
                'بسم الله الرحمن الرحيم':
            t = ' '.join(w[4:])
    return t


# The two places QPC's spaces and a recitation's words may disagree:
# Tanzil (and recitations timed on it) writes بعدما as one word, where
# the mushaf writes بَعْدَ مَا (2:181, 8:6, 13:37 — exactly on the fatha:
# بَعْدِ مَا stands as two words 27 times); quran.com's word list counts
# إِلْ يَاسِينَ (37:130) as one word, where its own text has a space.
JOINS = {'bada': ('بَعْدَ', 'مَا'), 'il_yasin': ('إِلْ', 'يَاسِينَ')}


def word_count(text, join=None):
    """Letter tokens of [text] split on single spaces — the app's
    words — with the JOINS pair [join] counted as one word."""
    toks = text.split(' ')
    pair = JOINS.get(join)
    n, i = 0, 0
    while i < len(toks):
        if is_letter_token(toks[i]):
            n += 1
            if pair and toks[i] == pair[0] and i + 1 < len(toks) and \
                    toks[i + 1] == pair[1]:
                i += 1
        i += 1
    return n


def quran_text():
    """surah -> [display text of each verse]."""
    def one(s):
        d = vr.cached_json(f'{TEXT_API}?chapter_number={s}',
                           f'text_{s:03d}.json')
        vs = d['verses']
        assert len(vs) == COUNTS[s - 1], f'text of surah {s}'
        return s, [display_text(s, a, v['text_uthmani'])
                   for a, v in enumerate(vs, 1)]
    with ThreadPoolExecutor(3) as ex:
        return dict(ex.map(one, range(1, 115)))


# ---- QUL ---------------------------------------------------------------

def qul_surah(rid, s):
    n = COUNTS[s - 1]
    return vr.cached_json(f'{QUL}/surah_segments/{rid}?surah={s}&from=1'
                          f'&to={n}&per_page={n}', f'qul_{rid}_{s:03d}.json')


def qul_ayah(rid, s):
    """An ayah recitation's segments for surah [s]: per verse its file
    and its word spans. Paged ten verses at a time unless per_page says
    otherwise."""
    n = COUNTS[s - 1]
    return vr.cached_json(f'{QUL}/ayah_segments/{rid}?surah={s}'
                          f'&per_page={n}', f'qulayah_{rid}_{s:03d}_all.json')


def verse_words(seg):
    """[(position, start, end)] of one QUL verse, in the order given. A
    few recitations add a fourth element to some words ({"waqaf": true}
    where the reciter stops), and a few carry a bare two-number entry;
    the first is left out here, the second dropped."""
    return [tuple(int(x) for x in w[:3]) for w in seg.get('segments') or []
            if len(w) >= 3]


def ayah_spans(v):
    """[(first word, end word, start, end)] of one verse of an ayah
    recitation, as given: word indices 0-based, the end exclusive — the
    layout of quran-align's files, which the app already reads."""
    return [tuple(int(x) for x in w[:4]) for w in v.get('segments') or []
            if len(w) >= 4]


def word_problems(words, tf=None, tt=None):
    """What is odd about one verse's QUL words, by kind: 'repeat' (the
    reciter goes back over words already read: positions fall back),
    'gap' (a position missing), 'zero' (a word with no length), 'order'
    (a word starting before the one before it), 'outside' (a word
    outside the verse's time_from..time_to)."""
    why = set()
    pos = [p for p, _, _ in words]
    if set(pos) != set(range(1, max(pos) + 1)):
        why.add('gap')
    if any(b <= a for a, b in zip(pos, pos[1:])):
        why.add('repeat')
    if any(b <= a for _, a, b in words):
        why.add('zero')
    if any(w[1] < v[1] for v, w in zip(words, words[1:])):
        why.add('order')
    if (tf is not None and words[0][1] < tf - 1) or \
            (tt is not None and max(b for _, _, b in words) > tt + 1):
        why.add('outside')
    return why


def recitation_data(rid):
    """surah -> QUL's segments for it, all 114."""
    with ThreadPoolExecutor(3) as ex:
        return dict(ex.map(lambda s: (s, qul_surah(rid, s)), range(1, 115)))


def _text_verdict(n, text):
    """How QUL's word count [n] for a verse meets the app's words: 'ok',
    the JOINS name that makes them meet, or 'unfit'."""
    if n == word_count(text):
        return 'ok'
    for name in JOINS:
        if n == word_count(text, name):
            return name
    return 'unfit'


def check_words(text, rid):
    """Every verse of surah recitation [rid]: has it words, are they
    sound, and does their count meet the app's words? Verse keys are
    listed where they are few, counted where they are many."""
    data = recitation_data(rid)
    res = dict(verses_with_words=0, surahs_without=[], mismatched={},
               odd={})
    for s in range(1, 115):
        seg = data[s].get('segments') or {}
        have = 0
        for a in range(1, COUNTS[s - 1] + 1):
            v = seg.get(f'{s}:{a}')
            words = verse_words(v) if v else []
            if not words:
                continue
            have += 1
            for k in word_problems(words, v.get('time_from'),
                                   v.get('time_to')):
                res['odd'].setdefault(k, []).append(f'{s}:{a}')
            n = max(p for p, _, _ in words)
            res.setdefault('_counts', {})[f'{s}:{a}'] = n
            how = _text_verdict(n, text[s][a - 1])
            if how != 'ok':
                res['mismatched'][f'{s}:{a}'] = how
        res['verses_with_words'] += have
        if have < COUNTS[s - 1]:
            res['surahs_without'].append(s)
    res['odd'] = {k: (v if len(v) <= 25 else len(v))
                  for k, v in sorted(res['odd'].items())}
    return res


def check_ayah_recitation(text, r, rid):
    """An ayah recitation whose files should be the voice's own: every
    verse's file named (and, for a sample, the same size as ours), its
    spans sound and fitting the text."""
    lst = vr.cached_json(f'{QUL}/ayah_recitations/{rid}?surah=1',
                         f'qulayahrec_{rid}.json')['recitation']['audio_files']
    want = {f'{s}:{a}': f"{r['base']}/{s:03d}{a:03d}.mp3"
            for s in range(1, 115) for a in range(1, COUNTS[s - 1] + 1)}
    not_ours = {k for k in want
                if (lst.get(k) or {}).get('audio_url') != want[k]}
    res = dict(verses_with_words=0, mismatched={}, odd={})
    with ThreadPoolExecutor(3) as ex:
        data = dict(ex.map(lambda s: (s, qul_ayah(rid, s)), range(1, 115)))
    for s in range(1, 115):
        seg = data[s].get('segments') or {}
        for a in range(1, COUNTS[s - 1] + 1):
            key = f'{s}:{a}'
            v = seg.get(key) or {}
            if v.get('audio_url') not in (None, want[key]):
                not_ours.add(key)
            spans = ayah_spans(v)
            if not spans:
                continue
            res['verses_with_words'] += 1
            odd = set()
            if any(t1 <= t0 for _, _, t0, t1 in spans):
                odd.add('zero')
            if any(x[2] < y[2] for y, x in zip(spans, spans[1:])):
                odd.add('order')
            if any(x[0] < y[1] for y, x in zip(spans, spans[1:])):
                odd.add('repeat')
            if spans[0][0] != 0 or any(x[0] > y[1] for y, x in
                                       zip(spans, spans[1:])):
                odd.add('gap')
            for k in odd:
                res['odd'].setdefault(k, []).append(key)
            how = _text_verdict(max(e for _, e, _, _ in spans),
                                text[s][a - 1])
            if how != 'ok':
                res['mismatched'][key] = how
    res['odd'] = {k: (v if len(v) <= 25 else len(v))
                  for k, v in sorted(res['odd'].items())}
    res['not_ours'] = sorted(not_ours)[:25]
    # Our files' sizes against the ones QUL lists, a spread of 60.
    keys = sorted(want)[::len(want) // 60]

    def size(k):
        status, hdr, _ = vr._get(want[k], {'Range': 'bytes=0-0'})
        return k, int(hdr.get('content-range', '/0').split('/')[-1]) \
            if status == 206 else None
    with ThreadPoolExecutor(3) as ex:
        sizes = dict(ex.map(size, keys))
    res['sizes_checked'] = len(keys)
    res['sizes_differ'] = sorted(k for k in keys
                                 if sizes[k] != lst[k].get('file_size'))
    return res


# ---- the same file? -------------------------------------------------------

def _range_md5(url, lo, hi):
    status, hdr, b = vr._get(url, {'Range': f'bytes={lo}-{hi}'}, timeout=60)
    if status != 206:
        return None, None
    total = int(hdr.get('content-range', '/0').split('/')[-1])
    return hashlib.md5(b).hexdigest(), total


def same_file(a, b, probe=65536):
    """Whether [a] and [b] serve the same bytes: the same size, and the
    same first and last [probe] bytes."""
    ha, ta = _range_md5(a, 0, probe - 1)
    hb, tb = _range_md5(b, 0, probe - 1)
    if ha is None or hb is None or ta != tb:
        return False
    return (ha == hb and _range_md5(a, ta - probe, ta - 1)[0] ==
            _range_md5(b, tb - probe, tb - 1)[0])


def same_files(r, rid):
    """Surahs where the voice's own file and the file QUL timed differ."""
    def one(s):
        return s, same_file(vr.surah_url(r, s),
                            qul_surah(rid, s)['audio']['url'])
    with ThreadPoolExecutor(2) as ex:
        return sorted(s for s, ok in ex.map(one, range(1, 115)) if not ok)


# ---- audio -------------------------------------------------------------

AUDIO = os.path.join(CACHE, 'audio')
XRATE = 8000  # what recordings are compared at
ERATE = 4000  # SurahSlice.envRate: what the app measures loudness at
WHOLE_MAX = 8 << 20  # in the sample, a QUL file this small comes whole


def download(url, path):
    if os.path.exists(path) and os.path.getsize(path) > 0:
        return path
    status, _, body = vr._get(url, timeout=180)
    if status != 200 or not body:
        raise RuntimeError(f'{url}: HTTP {status}')
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path + '.part', 'wb') as f:
        f.write(body)
    os.replace(path + '.part', path)
    return path


def decode(path, rate, fmt=None):
    """[path] decoded the way the app decodes (ffmpeg, mono, s16)."""
    p = subprocess.run(
        ['nice', '-n', '15', 'ffmpeg', '-v', 'error'] +
        (['-f', fmt] if fmt else []) +
        ['-i', path, '-ac', '1', '-ar', str(rate), '-f', 's16le', '-'],
        capture_output=True, check=True)
    return np.frombuffer(p.stdout[:len(p.stdout) // 2 * 2], dtype='<i2')


def app_envelope(pcm):
    """SurahSlice.envelopeOf: mono s16 at ERATE -> dB per 10 ms frame,
    power averaged over the 100 ms (+-5 frames) around it."""
    n = len(pcm) // (ERATE // 100)
    x = pcm[:n * (ERATE // 100)].astype(np.float64).reshape(n, -1)
    power = (x * x).mean(axis=1)
    c = np.concatenate([[0.0], np.cumsum(power)])
    i = np.arange(n)
    lo, hi = np.maximum(0, i - 5), np.minimum(n, i + 6)
    return 10 * np.log10((c[hi] - c[lo]) / (hi - lo) + 1)


def levels(env):
    """(floor, speech) as SurahSlice.quietBelow takes them."""
    live = sorted(e for e in env if e > 10) or sorted(env)
    if not live:
        return 0.0, 0.0
    return live[int(len(live) * 0.05)], live[int(len(live) * 0.9)]


def quiet_below(env, rel=0.35):
    """SurahSlice.quietBelow (at pauseRel [rel])."""
    floor, speech = levels(env)
    return floor + rel * (speech - floor)


def pauses(env, quiet, min_ms=200):
    """SurahSlice.pauses."""
    runs, st = [], None
    for k in range(len(env) + 1):
        if k < len(env) and env[k] <= quiet:
            if st is None:
                st = k
        elif st is not None:
            if (k - st) * 10 >= min_ms:
                runs.append((st * 10, k * 10))
            st = None
    return runs


def dround(x):
    """Dart's num.round(): halves away from zero."""
    return int(math.floor(x + 0.5)) if x >= 0 else -int(math.floor(-x + 0.5))


def snap(env, at_ms, before, after):
    """SurahSlice.snap, exactly."""
    i = dround(at_ms / 10)
    lo = max(0, i - before // 10)
    hi = min(len(env) - 1, i + after // 10)
    if lo > hi:
        return min(max(i, 0), len(env)) * 10
    best = lo
    for k in range(lo + 1, hi + 1):
        if env[k] < env[best] or (env[k] == env[best] and
                                  abs(k - i) < abs(best - i)):
            best = k
    return best * 10


def opening_pause(gaps, v1_at, opening_ms):
    """SurahSlice.openingPause."""
    onset = v1_at
    for a, b in gaps:
        if a <= v1_at < b:
            onset = b
    for a, b in gaps:
        if opening_ms * 0.6 <= a - onset <= opening_ms * 1.6:
            return a, b
    return None


def plan(table, start, last, origin, env, opening=None):
    """SurahSlice.plan, exactly: (cutStart, cutEnd, [(from, to)] verse
    windows in the cut's time). [table]: [(start_ms, end_ms)] by verse."""
    slice_ms = len(env) * 10

    def at(ms):
        return dround(ms - origin)
    frm, to = table[start - 1][0], table[last - 1][1]
    quiet = quiet_below(env)
    gaps = pauses(env, quiet)
    cut_start = snap(env, at(frm), 800, 350)
    if opening is not None:
        p = opening_pause(gaps, at(frm), opening)
        if p is not None:
            cut_start = snap(env, (p[0] + p[1]) // 2, (p[1] - p[0]) // 2,
                             (p[1] - p[0]) // 2)
    bounds = [cut_start]
    for a in range(start + 1, last + 1):
        t = at(table[a - 1][0])
        b = snap(env, t, 350, 350)
        if b // 10 < len(env) and env[b // 10] > quiet:
            b = min(max(t, 0), slice_ms)
        bounds.append(max(b, bounds[-1] + 150))
    cut_end = min(slice_ms, max(snap(env, min(at(to), slice_ms), 350, 800),
                                bounds[-1] + 150))
    if cut_end <= cut_start or bounds[-1] >= cut_end:
        raise ValueError(f'verses {start}-{last} not in the slice')
    bounds.append(cut_end)
    return cut_start, cut_end, [(bounds[i] - cut_start,
                                 bounds[i + 1] - cut_start)
                                for i in range(len(bounds) - 1)]


def ncc(x, y):
    """Normalised correlation of [x] with every stretch of [y] as long
    as it: r[k] for x laid on y[k:k+len(x)]."""
    m, n = len(x), len(y)
    if m < 80 or n < m:
        return None
    x = x.astype(np.float64)
    x = (x - x.mean()).astype(np.float32)
    y32 = y.astype(np.float32)
    size = 1 << int(math.ceil(math.log2(n + m)))
    c = np.fft.irfft(np.fft.rfft(x[::-1], size) * np.fft.rfft(y32, size),
                     size)[m - 1:n]
    y64 = y.astype(np.float64)
    cs = np.concatenate([[0.0], np.cumsum(y64 * y64)])
    e = cs[m:] - cs[:n - m + 1]
    xx = float(np.dot(x.astype(np.float64), x.astype(np.float64)))
    # A stretch of [y] 40 dB under [x] (digital silence, where a file has
    # it) matches nothing: dividing by its energy would only blow up the
    # transform's rounding noise.
    live = e > 1e-4 * xx
    return np.where(live, c / np.sqrt(np.maximum(e * xx, 1e-6)), 0.0)


def best_peak(r, guard):
    """(index, value) of the strongest |r|, and the strongest |r| more
    than [guard] samples from it — how unique the match is."""
    a = np.abs(r)
    k = int(np.argmax(a))
    rest = a.copy()
    rest[max(0, k - guard):k + guard + 1] = 0
    return k, float(r[k]), float(rest.max()) if len(rest) else 0.0


CHUNK_MS = 1500  # the stretch of our audio looked for in QUL's
SAME_PEAK = 0.6  # a stretch whose best match is this good is that audio
AGREE_MS = 20    # and the stretches of one verse agree to this
STRONG_PEAK = 0.8  # and at least one of them is this good


def locate(ours, q, q0):
    """Where [ours] (our window's audio at XRATE, t=0 at its first
    sample) sits in [q] (QUL's audio at XRATE, its first sample at QUL
    time [q0] ms): for stretches of CHUNK_MS spread from its start to
    its end, the QUL time of our t=0 that matches each best, and how
    well (normalised correlation of the waveforms; the runner-up is the
    best match more than 50 ms away). Stretches 20 dB or more under the
    verse's own level are background, and left out."""
    sr = XRATE // 1000
    dur = len(ours) // sr
    if dur <= CHUNK_MS + 500:
        spots, L = [0], dur
    else:
        L = CHUNK_MS
        n = int(min(6, max(2, dur // 1500)))
        spots = [round(i * (dur - L) / (n - 1)) for i in range(n)]
    level = np.sqrt(np.mean(ours.astype(np.float64) ** 2)) if len(ours) else 0
    out = []
    for c0 in spots:
        x = ours[c0 * sr:(c0 + L) * sr]
        rms = np.sqrt(np.mean(x.astype(np.float64) ** 2)) if len(x) else 0
        if rms < 30 or rms < level / 10:
            continue  # near-silence: nothing to match
        r = ncc(x, q)
        if r is None:
            continue
        k, peak, runner = best_peak(r, 50 * sr)
        out.append(dict(at=c0, g=round(q0 + k / sr - c0, 2),
                        peak=round(peak, 4), runner=round(runner, 4)))
    return out


def located(loc):
    """A verse's verdict from its stretches: ('match', g) when every
    stretch matched at one offset, ('partial', g) when the stretches that
    matched agree but some did not match, ('drift', None) when matched
    stretches disagree, ('none', None) when nothing matched — or nothing
    better than STRONG_PEAK: a single stretch of another take can just
    reach SAME_PEAK, never this (seen: 0.62-0.69; the same recording's
    best stretch is 0.90 or more in every verse measured)."""
    good = [l for l in loc if abs(l['peak']) >= SAME_PEAK]
    if not good or max(abs(l['peak']) for l in good) < STRONG_PEAK:
        return 'none', None
    gs = sorted(l['g'] for l in good)
    if gs[-1] - gs[0] > AGREE_MS:
        return 'drift', None
    g = gs[len(gs) // 2]
    return ('match' if len(good) == len(loc) else 'partial'), g


def _key(url):
    return re.sub(r'[^A-Za-z0-9]+', '_', url)


def slice_bias(url, lay, work):
    """How a slice cut the app's way (vr.fetch_slice) decodes against
    the whole file: a moment [t] ms into the decoded slice plays at
    origin + t + bias of the file decoded from its start. Measured, not
    assumed: the first 32 s are fetched whole and laid against a slice
    of them. (lame_bias says the same without the fetch.)"""
    path = os.path.join(CACHE, 'bias', _key(url) + '.json')
    if os.path.exists(path):
        return json.load(open(path))
    frame_ms = lay['spf'] * 1000 / lay['rate']
    end = lay['data'] + int(32000 / frame_ms * lay['avg'])
    status, _, head = vr._get(url, {'Range': f'bytes=0-{end}'}, timeout=120)
    if status != 206:
        raise RuntimeError(f'{url}: prefix answered {status}')
    os.makedirs(work, exist_ok=True)
    p1, p2 = os.path.join(work, 'prefix.mp3'), os.path.join(work, 'cut.mp3')
    with open(p1, 'wb') as f:
        f.write(head)
    b, origin = vr.fetch_slice(url, lay, 12000, 24000)
    with open(p2, 'wb') as f:
        f.write(b)
    try:
        full, part = decode(p1, XRATE), decode(p2, XRATE, 'mp3')
    finally:
        os.remove(p1)
        os.remove(p2)
    sr = XRATE // 1000
    r = ncc(part[1000 * sr:7000 * sr], full)
    k, peak, runner = best_peak(r, 50 * sr)
    res = dict(bias=round(k / sr - (origin + 1000), 3), peak=round(peak, 4),
               info=lay['info'])
    os.makedirs(os.path.dirname(path), exist_ok=True)
    json.dump(res, open(path, 'w'))
    return res


def lame_bias(lay):
    """slice_bias without measuring it: what ffmpeg skips at the start of
    a file with a LAME header (its encoder delay, 576, and the decoder's
    529) and never in a slice."""
    return -1105 * 1000 / lay['rate'] if lay['info'] else 0.0


_whole = {}


def qul_audio(url, t0, t1, work):
    """QUL's recording at [url] from QUL time [t0] to [t1] ms, at XRATE,
    the QUL time its first sample plays at, and how it was got. A small
    file is fetched and decoded whole; from a big one only the slice is
    fetched, as the app fetches it, its decode put on the file's own
    time by slice_bias."""
    lay = vr.layout(url)
    if not lay.get('ok'):
        raise RuntimeError(f'{url}: {lay.get("why")}')
    t0 = max(0, int(t0))
    sr = XRATE // 1000
    if lay['total'] <= WHOLE_MAX:
        if url not in _whole:
            _whole.clear()
            path = download(url, os.path.join(work, 'qul_' + _key(url)[-40:]
                                              + '.mp3'))
            _whole[url] = decode(path, XRATE)
            os.remove(path)
        pcm = _whole[url]
        return pcm[t0 * sr:int(t1) * sr], t0, 'whole'
    if lay['vbr']:
        raise RuntimeError(f'{url}: variable bitrate, too big to fetch whole')
    cal = slice_bias(url, lay, work)
    if cal['peak'] < 0.9:
        raise RuntimeError(f'{url}: slice calibration failed {cal}')
    b, origin = vr.fetch_slice(url, lay, t0, t1)
    path = os.path.join(work, 'qslice.mp3')
    with open(path, 'wb') as f:
        f.write(b)
    try:
        pcm = decode(path, XRATE, 'mp3')
    finally:
        os.remove(path)
    return pcm, origin + cal['bias'], 'slice'


def qul_range(url, from_ms, to_ms, work):
    """QUL's recording from [from_ms] to [to_ms], at XRATE, and the QUL
    time of its first sample: only that byte range, its decode put on
    the file's own time by lame_bias. A variable-bitrate file can't be
    cut by arithmetic, and is fetched whole when it is small."""
    lay = vr.layout(url)
    if not lay.get('ok'):
        raise RuntimeError(f'{url}: {lay.get("why")}')
    if lay['vbr']:
        if lay['total'] > WHOLE_MAX:
            raise RuntimeError(f'{url}: variable bitrate, too big')
        pcm, q0, _ = qul_audio(url, from_ms, to_ms, work)
        return pcm, q0
    b, origin = vr.fetch_slice(url, lay, max(0, from_ms), to_ms)
    path = os.path.join(work, 'qrange.mp3')
    with open(path, 'wb') as f:
        f.write(b)
    try:
        pcm = decode(path, XRATE, 'mp3')
    finally:
        os.remove(path)
    return pcm, origin + lame_bias(lay)


# ---- the sample ----------------------------------------------------------

# (surah, first verse, last verse), run as one reel each. Short surahs
# first, so a voice that is another recording shows it in its first few;
# then the long verses (Ayat al-Kursi, the longest verse, Al-Kahf), and
# seven verse 1s, where the basmala lives.
RUNS = [(112, 1, 4), (114, 1, 3), (67, 1, 3), (1, 1, 4), (36, 1, 5),
        (18, 1, 3), (18, 110, 110), (2, 254, 256), (2, 282, 282), (3, 7, 8),
        (4, 1, 2)]
# Stand-ins, in order, for runs in surahs a recitation has no words for.
EXTRA_RUNS = [(19, 1, 4), (20, 1, 4), (12, 1, 4), (7, 1, 3), (24, 35, 35),
              (10, 1, 3), (16, 1, 2), (13, 1, 2), (17, 1, 2), (21, 1, 3),
              (11, 1, 3), (15, 1, 4)]
EARLY = 8  # verses after which a voice nothing matched in is let go


def sample_runs(rid):
    """RUNS, with each run QUL has no words for (or whose file can only
    be fetched whole, and is big) swapped for the next EXTRA_RUNS one,
    until as many verses are in."""
    want = sum(a1 - a0 + 1 for _, a0, a1 in RUNS)

    def has(run):
        s, a0, a1 = run
        lay = vr.layout(qul_surah(rid, s)['audio']['url'])
        if not lay.get('ok') or (lay['vbr'] and lay['total'] > WHOLE_MAX):
            return False
        seg = qul_surah(rid, s).get('segments') or {}
        return all(verse_words(seg.get(f'{s}:{a}') or {})
                   for a in range(a0, a1 + 1))
    runs = [r for r in RUNS if has(r)]
    for r in EXTRA_RUNS:
        if sum(a1 - a0 + 1 for _, a0, a1 in runs) >= want:
            break
        if has(r):
            runs.append(r)
    return runs


def ayah_records(r, rid, log):
    """For a per-ayah voice: each sampled verse file located in QUL's
    surah recording [rid], and its loudness the app's way."""
    work = os.path.join(AUDIO, r['id'])
    recs = []
    for run, (s, a0, a1) in enumerate(sample_runs(rid)):
        d = qul_surah(rid, s)
        seg, url = d['segments'], d['audio']['url']
        for a in range(a0, a1 + 1):
            v = seg[f'{s}:{a}']
            tf, tt = v['time_from'], v['time_to']
            path = download(f"{r['base']}/{s:03d}{a:03d}.mp3",
                            os.path.join(work, f'{s:03d}{a:03d}.mp3'))
            ours = decode(path, XRATE)
            env = app_envelope(decode(path, ERATE))
            q, q0, _ = qul_audio(url, tf - 9000, tt + 9000, work)
            loc = locate(ours, q, q0)
            state, g = located(loc)
            recs.append(dict(key=f'{s}:{a}', run=run, verse=a,
                             dur=len(ours) // (XRATE // 1000), tf=tf, tt=tt,
                             words=verse_words(v), loc=loc, state=state, g=g,
                             env=[round(float(e), 2) for e in env]))
            log(f"  {r['id']} {s}:{a} {state} g={g} tf={tf} "
                f"peaks={[l['peak'] for l in loc]}")
        if len(recs) >= EARLY and not any(x['state'] in ('match', 'partial')
                                          for x in recs):
            log(f"  {r['id']}: nothing matched in {len(recs)} verses")
            break
    return recs


def our_table(r, s):
    """The voice's own table for surah [s] as SurahSlice.parseTable and
    withFileEnd leave it: [(start, end)] by verse."""
    t = vr.surah_table(r['timing'], s)
    rows = [(int(x['start_time']), int(x['end_time'])) for x in t]
    assert len(rows) == COUNTS[s - 1], f"{r['id']} table {s}"
    if rows[-1][1] <= rows[-1][0]:
        lay = vr.layout(vr.surah_url(r, s))
        rows[-1] = (rows[-1][0], int(lay['audio_ms']))
    return rows


def surah_records(r, rid, log):
    """For a surah-file voice: each sampled run cut the way the app cuts
    it (the slice, the snapped windows), and each verse window located in
    QUL's recording [rid]."""
    work = os.path.join(AUDIO, r['id'])
    os.makedirs(work, exist_ok=True)
    recs = []
    sr = XRATE // 1000
    for run, (s, a0, a1) in enumerate(sample_runs(rid)):
        d = qul_surah(rid, s)
        seg, qurl = d['segments'], d['audio']['url']
        url = vr.surah_url(r, s)
        lay = vr.layout(url)
        table = our_table(r, s)
        frm, to = table[a0 - 1][0], table[a1 - 1][1]
        b, origin = vr.fetch_slice(url, lay, frm - 1800, to + 1800)
        path = os.path.join(work, 'slice.mp3')
        with open(path, 'wb') as f:
            f.write(b)
        env = app_envelope(decode(path, ERATE, 'mp3'))
        ours = decode(path, XRATE, 'mp3')
        os.remove(path)
        opening = r.get('opening') if a0 == 1 and s != 9 else None
        cut0, _, wins = plan(table, a0, a1, origin, env, opening)
        tfs = [seg[f'{s}:{a}']['time_from'] for a in range(a0, a1 + 1)]
        tts = [seg[f'{s}:{a}']['time_to'] for a in range(a0, a1 + 1)]
        reach = 25000
        q, q0, _ = qul_audio(qurl, min(tfs) - reach, max(tts) + reach, work)
        for i, a in enumerate(range(a0, a1 + 1)):
            v = seg[f'{s}:{a}']
            w0, w1 = wins[i]
            x0, x1 = cut0 + w0, cut0 + w1
            # Searched only near where the two tables put the verse.
            lo = max(0, int((v['time_from'] - reach - q0) * sr))
            hi = int((v['time_to'] + reach - q0) * sr)
            loc = locate(ours[x0 * sr:x1 * sr], q[lo:hi], q0 + lo / sr)
            state, g = located(loc)
            recs.append(dict(
                key=f'{s}:{a}', run=run, verse=a, dur=w1 - w0,
                tf=v['time_from'], tt=v['time_to'], words=verse_words(v),
                loc=loc, state=state, g=g,
                env=[round(float(e), 2) for e in env[x0 // 10:x1 // 10]],
                origin=origin, reel=[cut0, None], window=[w0, w1],
                # Where QUL's time is in our file's own time:
                # QUL = ours + file_offset.
                file_offset=None if g is None else
                round(g - (origin + x0 + lame_bias(lay)), 2)))
            log(f"  {r['id']} {s}:{a} {state} g={g} tf={v['time_from']} "
                f"ours={table[a - 1][0]} peaks={[l['peak'] for l in loc]}")
        if len(recs) >= EARLY and not any(x['state'] in ('match', 'partial')
                                          for x in recs):
            log(f"  {r['id']}: nothing matched in {len(recs)} verses")
            break
    return recs


def records(r, rid, log):
    """The sample for voice [r] against QUL recitation [rid], cached."""
    path = os.path.join(CACHE, 'records', f"{r['id']}_{rid}.json")
    if os.path.exists(path):
        recs = json.load(open(path))['recs']
        for x in recs:
            x['state'], x['g'] = located(x['loc'])
            # Kept by an earlier version without the offset for small
            # files: the same arithmetic as surah_records.
            if r['kind'] == 'surah' and x.get('file_offset') is None and \
                    x['g'] is not None and 'origin' in x:
                lay = vr.layout(vr.surah_url(r, int(x['key'].split(':')[0])))
                x['file_offset'] = round(x['g'] - (
                    x['origin'] + x['reel'][0] + x['window'][0] +
                    lame_bias(lay)), 2)
        return recs
    recs = (ayah_records if r['kind'] == 'ayah' else surah_records)(
        r, rid, log)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    json.dump(dict(recs=recs), open(path, 'w'))
    return recs


# ---- every surah, at its start ---------------------------------------------

# The mapping (see the docstring, 5.): QUL's first word start put at our
# onset, by the app's own quiet rule over the verse window.
MAP_REL = 0.35   # quietBelow's own pauseRel
MAP_RUN = 5      # frames (50 ms) the onset must hold


def sound_span(env, thr, min_frames=MAP_RUN):
    """(onset, offset) in ms of [env]: where it first rises above [thr]
    and stays there [min_frames] frames, and where the last such run
    ends. None when it never does."""
    above = np.asarray(env) > thr
    if len(above) < min_frames:
        return None
    c = np.concatenate([[0], np.cumsum(above)])
    run = (c[min_frames:] - c[:-min_frames]) == min_frames
    idx = np.nonzero(run)[0]
    if not len(idx):
        return None
    return int(idx[0]) * 10, int(idx[-1] + min_frames) * 10


def _onset_err(env, words, g):
    """Our onset less QUL's first word start put on our window: the
    shift mapping's error, the same for every word of the verse."""
    span = sound_span(env, quiet_below(env, MAP_REL))
    if span is None or g is None:
        return None
    return round(span[0] - (words[0][1] - g))


def _spans(env, words):
    """[our voiced span, QUL's word span] of a verse, for the checks, and
    whether the window opens in quiet."""
    quiet = quiet_below(env, MAP_REL)
    span = sound_span(env, quiet)
    if span is None or not words:
        return None, None
    return [span[1] - span[0], max(e for _, _, e in words) - words[0][1]], \
        bool(max(env[:MAP_RUN]) <= quiet)


def survey(r, rid, log):
    """Verses 1 and 2 of every surah QUL has words for: whether they are
    the same recording, and for each the mapping's error; for a surah-file
    voice also where QUL's time is in our file's (QUL = ours + offset).
    Cached."""
    path = os.path.join(CACHE, 'survey', f"{r['id']}_{rid}.json")
    if os.path.exists(path):
        return {int(k): v for k, v in json.load(open(path)).items()}
    work = os.path.join(AUDIO, r['id'])
    os.makedirs(work, exist_ok=True)
    out = {}
    sr = XRATE // 1000
    for s in range(1, 115):
        d = qul_surah(rid, s)
        seg, qurl = d.get('segments') or {}, d['audio']['url']
        v1, v2 = seg.get(f'{s}:1'), seg.get(f'{s}:2')
        if not (v1 and v2 and verse_words(v1) and verse_words(v2)):
            out[s] = dict(state='no words')
            continue
        try:
            res = (_survey_ayah if r['kind'] == 'ayah' else _survey_surah)(
                r, s, v1, v2, qurl, work, sr)
        except Exception as e:  # noqa: BLE001 - one surah, not the voice
            res = dict(state='error', why=str(e)[:120])
        out[s] = res
        log(f"  {r['id']} survey {s}: {res}")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    json.dump({str(k): v for k, v in out.items()}, open(path, 'w'))
    return out


def _survey_ayah(r, s, v1, v2, qurl, work, sr):
    q, q0 = qul_range(qurl, 0, v2['time_to'] + 9000, work)
    res = {}
    for a, v in ((1, v1), (2, v2)):
        path = download(f"{r['base']}/{s:03d}{a:03d}.mp3",
                        os.path.join(work, f'{s:03d}{a:03d}.mp3'))
        ours = decode(path, XRATE)
        env = app_envelope(decode(path, ERATE))
        os.remove(path)
        hi = int((v['time_to'] + 9000 - q0) * sr)
        lo = max(0, int((v['time_from'] - 9000 - q0) * sr))
        loc = locate(ours, q[lo:hi], q0 + lo / sr)
        state, g = located(loc)
        spans, quiet = _spans(env, verse_words(v))
        res[f'v{a}'] = dict(state=state, peak=max((abs(l['peak']) for l in loc),
                                                  default=0),
                            g_tf=None if g is None else round(g - v['time_from']),
                            shift_err=_onset_err(env, verse_words(v), g),
                            spans=spans, quiet_start=quiet)
    res['state'] = 'same' if res['v2']['state'] in ('match', 'partial') \
        else 'different'
    return res


def _survey_surah(r, s, v1, v2, qurl, work, sr):
    url = vr.surah_url(r, s)
    lay = vr.layout(url)
    table = our_table(r, s)
    b, origin = vr.fetch_slice(url, lay, table[0][0] - 1800,
                               table[1][1] + 1800)
    path = os.path.join(work, 'slice.mp3')
    with open(path, 'wb') as f:
        f.write(b)
    env = app_envelope(decode(path, ERATE, 'mp3'))
    ours = decode(path, XRATE, 'mp3')
    os.remove(path)
    opening = r.get('opening') if s != 9 else None
    cut0, _, wins = plan(table, 1, 2, origin, env, opening)
    # Where QUL's verse 2 should be, from the two tables.
    est = v2['time_from'] - table[1][0]
    reach = 9000
    q, q0 = qul_range(qurl, min(v1['time_from'], table[0][0] + est)
                      - reach, max(v2['time_to'], table[1][1] + est) + reach,
                      work)
    res = {}
    for a, v in ((1, v1), (2, v2)):
        w0, w1 = wins[a - 1]
        x0, x1 = cut0 + w0, cut0 + w1
        loc = locate(ours[x0 * sr:x1 * sr], q, q0)
        state, g = located(loc)
        wenv = env[x0 // 10:x1 // 10]
        spans, quiet = _spans(wenv, verse_words(v))
        res[f'v{a}'] = dict(
            state=state, peak=max((abs(l['peak']) for l in loc), default=0),
            shift_err=_onset_err(wenv, verse_words(v), g),
            spans=spans, quiet_start=quiet,
            offset=None if g is None else
            round(g - (origin + x0 + lame_bias(lay)), 1))
    res['state'] = 'same' if res['v2']['state'] in ('match', 'partial') \
        else 'different'
    return res


# ---- how the runtime mapping does ---------------------------------------

def pct(xs, q):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(round(q * (len(xs) - 1))))] if xs else None


def err_stats(errs):
    a = sorted(abs(x) for x in errs)
    if not a:
        return None
    return dict(n=len(a), median=round(pct(a, 0.5)), p90=round(pct(a, 0.9)),
                max=round(a[-1]), within_150=round(sum(x <= 150 for x in a)
                                                   / len(a), 3))


def mapped(rec, variant='shift', thr=None):
    """Each QUL word start of [rec] put on our window by [variant] (before
    any bias), the true starts (from where our audio was found in QUL's),
    and the anchors. None when the window has no sound to anchor on."""
    env = rec['env']
    span = sound_span(env, quiet_below(env, MAP_REL) if thr is None else thr)
    if span is None or not rec['words']:
        return None
    o, f = span
    words = rec['words']
    F, tf = words[0][1], rec['tf']
    E = max(e for _, _, e in words)
    if variant == 'shift':
        pred = [o + (s - F) for _, s, _ in words]
    elif variant == 'affine':
        pred = [o + (s - F) * (f - o) / max(1, E - F) for _, s, _ in words]
    elif variant == 'end':
        pred = [f - (E - s) for _, s, _ in words]
    elif variant == 'table':
        pred = [s - tf for _, s, _ in words]
    else:
        raise ValueError(variant)
    true = None if rec['g'] is None else [s - rec['g'] for _, s, _ in words]
    quiet = quiet_below(env, MAP_REL)
    return dict(pred=pred, true=true, o=o, f=f, F=F, E=E, ours=f - o,
                quls=E - F, quiet_start=max(env[:MAP_RUN]) <= quiet)


def span_ok(m, ms=150, rel=0.03):
    """The span check as proposed: our voiced span and QUL's word span
    agree to max([ms], [rel] of QUL's)."""
    return abs(m['ours'] - m['quls']) <= max(ms, rel * m['quls'])


# The check recommended instead. Chosen over the survey's 447 verse 2s of
# four same-recording per-ayah voices: passes 98% of them, and every
# verse it lets through but one is a mapping within 410 ms (the one is
# 174's 33:2, where QUL's own words are 3.6 s off its audio); 1500/10%
# let through files that open on the verse before (+1.5-1.8 s).
GROSS_MS, GROSS_REL = 1000, 0.05
AGREE_SPANS_MS = 500  # spans this close: our onset is the verse's own


def gross_ok(m):
    """The check recommended: the spans agree to max(GROSS_MS, GROSS_REL
    of QUL's). Not to tell recordings apart (nothing at runtime can; the
    survey does), only to catch an onset that is not the verse's: a file
    that opens on the end of the verse before it, the basmala QUL's
    verse 1 holds and ours doesn't."""
    return abs(m['ours'] - m['quls']) <= max(GROSS_MS, GROSS_REL * m['quls'])


def _variant_errors(recs, variant, thr_rule=None):
    """Word-level errors of [variant] over the located verses but verse
    1s, before any bias, and the verses' own (shift: one per verse)."""
    out = []
    for r in recs:
        if r['state'] not in ('match', 'partial') or not r['words'] or \
                r['verse'] == 1:
            continue
        thr = None
        if thr_rule is not None:
            kind, x = thr_rule
            floor, speech = levels(r['env'])
            thr = floor + x * (speech - floor) if kind == 'q' else speech - x
        m = mapped(r, variant, thr)
        if m:
            out.extend(p - t for p, t in zip(m['pred'], m['true']))
    return out


def _biased(errs, step=5):
    """The bias that centres [errs] (to [step] ms) and the stats after."""
    if not errs:
        return None, None
    b = -round(pct(errs, 0.5) / step) * step
    return b, err_stats([e + b for e in errs])


def evaluate(r, recs, others):
    """The sample's verdict for one voice, and how each mapping does on
    it. [others]: {verse key: words} of another reciter, for the check's
    negative control."""
    loc = [x for x in recs if x['state'] in ('match', 'partial')]
    res = dict(verses=len(recs), located=len(loc))
    res['not_located'] = [x['key'] for x in recs if x not in loc]
    if not loc:
        res['verdict'] = 'different'
        res['peak_max'] = round(max((abs(l['peak']) for x in recs
                                     for l in x['loc']), default=0), 3)
        return res
    peaks = [min(abs(l['peak']) for l in x['loc'] if abs(l['peak']) >=
                 SAME_PEAK) for x in loc]
    res['peak_median'] = round(pct(peaks, 0.5), 3)
    res['peak_min'] = round(min(peaks), 3)
    res['agree_max_ms'] = round(max(
        max(l['g'] for l in x['loc'] if abs(l['peak']) >= SAME_PEAK) -
        min(l['g'] for l in x['loc'] if abs(l['peak']) >= SAME_PEAK)
        for x in loc), 1)
    surahs = {}
    for x in recs:
        surahs.setdefault(int(x['key'].split(':')[0]), []).append(x in loc)
    res['surahs_other_recording'] = sorted(s for s, v in surahs.items()
                                           if not any(v))
    res['verdict'] = 'match' if not res['surahs_other_recording'] else 'mixed'
    if r['kind'] == 'surah':
        offs = {}
        for x in loc:
            if x.get('file_offset') is not None:
                offs.setdefault(int(x['key'].split(':')[0]), []).append(
                    x['file_offset'])
        res['file_offset_ms'] = {str(s): [round(min(v)), round(max(v))]
                                 for s, v in sorted(offs.items())}
    # Verses whose window opens in quiet and whose spans agree to
    # AGREE_SPANS_MS, but whose onset is a second or more from QUL's
    # first word put on our audio: QUL's words are that far from QUL's
    # own audio there (see summarise_survey), so the transfer, not the
    # mapping, is wrong. Listed, and left out of the variants.
    mis = []
    for x in loc:
        m = mapped(x)
        if x['verse'] != 1 and m and x['words'] and m['quiet_start'] and \
                abs(m['ours'] - m['quls']) <= AGREE_SPANS_MS and \
                abs(m['o'] - (m['F'] - x['g'])) > 1000:
            mis.append(x['key'])
    res['qul_misplaced'] = mis
    clean = [x for x in recs if x['key'] not in mis]
    # The mapping's variants, each centred by its own best bias.
    var = {}
    for v in ('shift', 'affine', 'end', 'table'):
        b, st = _biased(_variant_errors(clean, v))
        var[v] = dict(bias_ms=b, **(st or {}))
    res['variants'] = var
    thr = {}
    for name, rule in (('quietBelow window 0.35', None),
                       ('quietBelow window 0.2', ('q', 0.2)),
                       ('quietBelow window 0.5', ('q', 0.5)),
                       ('speech - 20 dB', ('d', 20)),
                       ('speech - 30 dB', ('d', 30))):
        b, st = _biased(_variant_errors(clean, 'shift', rule))
        thr[name] = None if st is None else dict(bias_ms=b, p90=st['p90'],
                                                 max=st['max'])
    res['shift_by_threshold'] = thr
    # A window that opens on sound has no onset to find: for a surah file
    # that is two verses run together, the cut not in a breath.
    loud = [x['key'] for x in loc if x['verse'] != 1 and mapped(x) and
            not mapped(x)['quiet_start']]
    res['opens_on_sound'] = loud
    # Verse 1: QUL's first word starts at time_from, which is the file's
    # start or the basmala's, not the word's.
    v1 = [x for x in loc if x['verse'] == 1 and x['words']]
    res['verse1'] = {x['key']: dict(
        shift=_onset_err(x['env'], x['words'], x['g']),
        table=round(x['g'] - x['tf'])) for x in v1}
    # The span check: same recording, another recording, another reciter.
    same = [mapped(x) for x in loc if x['verse'] != 1]
    same = [m for m in same if m]
    other = [mapped(x) for x in recs if x['state'] == 'none' and x['words']]
    other = [m for m in other if m]
    neg = []
    for x in loc:
        words = others.get(x['key'])
        m = mapped(x)
        if words and m and x['verse'] != 1:
            neg.append(dict(m, quls=max(e for _, _, e in words) - words[0][1]))
    res['span_check'] = dict(
        same_recording=_share([span_ok(m) for m in same]),
        other_recording=_share([span_ok(m) for m in other]),
        other_reciter=_share([span_ok(m) for m in neg]))
    v1m = [mapped(x) for x in v1]
    res['gross_check'] = dict(
        same_recording=_share([gross_ok(m) for m in same]),
        same_verse1=_share([gross_ok(m) for m in v1m if m]),
        other_recording=_share([gross_ok(m) for m in other]),
        other_reciter=_share([gross_ok(m) for m in neg]))
    return res


def _share(oks):
    return None if not oks else dict(n=len(oks), pass_rate=round(
        sum(oks) / len(oks), 3))


def summarise_survey(r, sv, sample_errs):
    """What the survey says the app should do with this voice."""
    def ok(v):
        return v['state'] in ('match', 'partial') and v['peak'] >= STRONG_PEAK
    sv = {s: (v if v['state'] in ('no words', 'error') else
              dict(v, state='same' if ok(v['v2']) else 'different'))
          for s, v in sv.items()}
    out = dict(surahs=len(sv))
    out['other_recording'] = sorted(s for s, v in sv.items()
                                    if v['state'] == 'different')
    out['no_words'] = sorted(s for s, v in sv.items()
                             if v['state'] == 'no words')
    out['errors'] = sorted(s for s, v in sv.items() if v['state'] == 'error')
    same = {s: v for s, v in sv.items() if v['state'] == 'same'}
    # Verse 2 of every surah, with the sample's verses: the mapping's
    # error over all of them, after the voice's bias.
    v2 = [v['v2']['shift_err'] for v in same.values()
          if v['v2'].get('shift_err') is not None]
    errs = list(sample_errs) + v2
    b, st = _biased(errs)
    out['shift'] = dict(bias_ms=b, verses=len(errs), **(st or {}))
    out['shift_over_150'] = sorted(
        s for s, v in same.items() if v['v2'].get('shift_err') is not None
        and abs(v['v2']['shift_err'] + b) > 150)

    def gross(x):
        sp = x.get('spans')
        return sp is not None and abs(sp[0] - sp[1]) <= max(
            GROSS_MS, GROSS_REL * sp[1])
    # A verse whose window opens in quiet and whose spans agree (to
    # AGREE_SPANS_MS), but whose onset is a second or more from QUL's
    # first word put on our audio:
    # QUL's own words sit that far from QUL's own audio there (its window
    # is late or early), and our onset, not the transfer, is where the
    # verse starts. (Seen: 174's 33:2, 3.6 s late; 170's Aal-Imran, 33 s.)
    misplaced = sorted(s for s, v in same.items()
                       if v['v2'].get('shift_err') is not None and
                       v['v2'].get('quiet_start') and v['v2'].get('spans') and
                       abs(v['v2']['spans'][0] - v['v2']['spans'][1]) <=
                       AGREE_SPANS_MS and abs(v['v2']['shift_err'] + b) > 1000)
    kept = [v['v2']['shift_err'] for s, v in same.items()
            if v['v2'].get('shift_err') is not None and gross(v['v2']) and
            s not in misplaced]
    out['gross_check'] = dict(
        verse2_pass=_share([gross(v['v2']) for v in same.values()
                            if v['v2'].get('spans')]),
        verse2_over_150_rejected=sorted(
            s for s in out['shift_over_150'] if not gross(same[s]['v2'])),
        shift_after=dict(zip(('bias_ms', 'stats'), _biased(
            list(sample_errs) + kept))))
    out['qul_misplaced'] = misplaced
    if r['kind'] == 'surah':
        loud = [s for s, v in same.items() if v['v2'].get('quiet_start')
                is False]
        out['verse2_opens_on_sound'] = sorted(loud)
    # Verse 1, by the two rules that can anchor it.
    v1 = {s: v['v1'] for s, v in same.items() if ok(v['v1'])}
    out['verse1_other_recording'] = sorted(
        s for s, v in same.items() if not ok(v['v1']))
    rules = {}
    for rule, key in (('shift', 'shift_err'), ('table', 'g_tf')):
        e = [v[key] for v in v1.values() if v.get(key) is not None]
        if not e:
            continue
        rb, rst = _biased(e)
        rules[rule] = dict(bias_ms=rb, **rst, off=sorted(
            s for s, v in v1.items() if v.get(key) is None or
            abs(v[key] + rb) > 150))
    out['verse1'] = rules
    if r['kind'] == 'surah':
        out['offset_ms'] = {str(s): round(v['v2']['offset'])
                            for s, v in sorted(same.items())
                            if v['v2'].get('offset') is not None}
        d = [abs(v['v1']['offset'] - v['v2']['offset'])
             for v in same.values() if v['v1'].get('offset') is not None and
             v['v2'].get('offset') is not None]
        out['offset_v1_v2_max_ms'] = round(max(d), 1) if d else None
    return out


# ---- a word-timing estimate from the text alone --------------------------
#
# For the voices QUL has no words for: what the app could light words by
# with nothing but the verse's audio and its text, measured against the
# verses above whose QUL words were put on our audio exactly.

LETTERS = set(range(0x0621, 0x063B)) | set(range(0x0641, 0x064B)) | {0x0671}
FATHA, DAMMA, KASRA, SUKUN, SHADDA = 0x064E, 0x064F, 0x0650, 0x0652, 0x0651
TANWEEN = {0x064B, 0x064C, 0x064D}
VOWELS = {FATHA, DAMMA, KASRA, SUKUN, SHADDA} | TANWEEN
DAGGER, MADDAH = 0x0670, 0x0653
SMALL_MADD = {0x06E5, 0x06E6, 0x06E7}  # small waw, small yeh, high yeh
# Where the mushaf allows or prefers a stop: sala, qala, meem, jeem,
# the paired dots, saktah. Not U+06D9 (la: do not stop).
WAQF = {0x06D6, 0x06D7, 0x06D8, 0x06DA, 0x06DB, 0x06DC}
FEATURES = ('word', 'letters', 'madd', 'long_madd', 'shadda', 'ghunna',
            'tanween', 'final')
LETTERS_ONLY = (0, 1, 0, 0, 0, 0, 0, 0)
BETA0 = (1, 1, 1, 2, 0.5, 0.5, 0.5, 1)  # where the fit starts
EST_BONUS = 1.0  # segment_words' preference for a cut at a stop mark


def words_of(text):
    """The app's words of a verse (letter tokens), each with whether a
    stop mark follows it."""
    out = []
    for tok in text.split(' '):
        if is_letter_token(tok):
            out.append([tok, False])
        elif out and any(ord(c) in WAQF for c in tok):
            out[-1][1] = True
    return out


def word_features(tok):
    """[1, letters, natural madd, long madd, shadda, ghunna, tanween] of
    one word of the QPC text (the 'final' feature is set per breath
    group). Natural madd: a superscript alif, a small waw/yeh, and a bare
    alif/alif maksura after fatha, waw after damma, yeh after kasra.
    Long madd: the maddah sign, which the mushaf writes only where the
    vowel is held 4-6 counts. Ghunna: a doubled noon or meem."""
    units = []
    for ch in tok:
        o = ord(ch)
        if o in LETTERS:
            units.append((o, set()))
        elif units:
            units[-1][1].add(o)
    madd = long_madd = shadda = ghunna = tanween = 0
    for i, (l, m) in enumerate(units):
        madd += (DAGGER in m) + bool(m & SMALL_MADD)
        long_madd += MADDAH in m
        if SHADDA in m:
            shadda += 1
            ghunna += l in (0x0646, 0x0645)
        tanween += bool(m & TANWEEN)
        if i and not (m & VOWELS) and DAGGER not in m:
            prev = units[i - 1][1]
            madd += ((l in (0x0627, 0x0649) and FATHA in prev) or
                     (l == 0x0648 and DAMMA in prev) or
                     (l == 0x064A and KASRA in prev))
    return [1.0, float(len(units)), float(madd), float(long_madd),
            float(shadda), float(ghunna), float(tanween)]


def segment_words(T, w, waqf, bonus):
    """Cut n words (weights [w], stop marks [waqf] after each) into
    len(T) breath groups, in order, so that each group's weight matches
    its measured length T[k] at one pace for the verse: the least sum of
    (T_k - pace * W_k)^2 / (T_k + 500), less [bonus] (in units of the
    verse's mean group) for every cut at a stop mark. Returns the first
    word of each group after the first."""
    n, G = len(w), len(T)
    pace = sum(T) / sum(w)
    c = np.concatenate([[0.0], np.cumsum(w)])
    INF = float('inf')
    unit = (sum(T) / G) ** 2 / (sum(T) / G + 500)
    best = [[INF] * (n + 1) for _ in range(G + 1)]  # groups <k hold words <j
    back = [[0] * (n + 1) for _ in range(G + 1)]
    best[0][0] = 0.0
    for k in range(1, G + 1):
        Tk = T[k - 1]
        for j in range(k, n - (G - k) + 1):
            bj, bi = INF, 0
            for i in range(k - 1, j):
                prev = best[k - 1][i]
                if prev == INF:
                    continue
                d = Tk - pace * (c[j] - c[i])
                cost = prev + d * d / (Tk + 500)
                if k < G and waqf[j - 1]:
                    cost -= bonus * unit
                if cost < bj:
                    bj, bi = cost, i
            best[k][j], back[k][j] = bj, bi
    cuts, j = [], n
    for k in range(G, 0, -1):
        i = back[k][j]
        if k > 1:
            cuts.append(i)
        j = i
    return sorted(cuts)


def estimate_starts(env, words, beta, use_pauses=True, bonus=EST_BONUS,
                    rel=0.35, min_pause=200):
    """Word starts (ms in the window) for a verse with no word data: the
    voiced span of [env] (first to last sound over quietBelow), cut at
    its pauses (SurahSlice.pauses inside it), the words cut into as many
    breath groups at one pace (segment_words), and each group shared out
    by the length model [beta] over FEATURES, its last word 'final'."""
    quiet = quiet_below(env, rel)
    span = sound_span(env, quiet)
    if span is None or not words:
        return None
    o, f = span
    feats = [word_features(t) for t, _ in words]
    waqf = [x for _, x in words]
    n = len(words)

    def weight(i, final):
        return max(1e-3, float(np.dot(beta, feats[i] + [float(final)])))
    gaps = [(a, b) for a, b in pauses(env, quiet, min_pause)
            if a > o and b < f] if use_pauses else []
    while len(gaps) > n - 1:  # no more groups than words
        gaps.remove(min(gaps, key=lambda g: g[1] - g[0]))
    edges = [o] + [x for g in gaps for x in g] + [f]
    spans = [(edges[2 * k], edges[2 * k + 1]) for k in range(len(gaps) + 1)]
    cuts = segment_words([b - a for a, b in spans],
                         [weight(i, False) for i in range(n)], waqf,
                         bonus) if len(spans) > 1 else []
    firsts = [0] + cuts + [n]
    groups = [(firsts[k], firsts[k + 1], spans[k][0], spans[k][1])
              for k in range(len(spans))]
    starts = [0.0] * n
    for g0, g1, t0, t1 in groups:
        ws = [weight(i, i == g1 - 1) for i in range(g0, g1)]
        acc = t0
        for k, i in enumerate(range(g0, g1)):
            starts[i] = acc
            acc += (t1 - t0) * ws[k] / sum(ws)
    return starts, groups, (o, f)


def estimate_samples(recs_by_voice, text, nufais_spans):
    """Verses with ground truth: our window's loudness, the app's words
    of the verse, and each word's true start. Only verses read straight
    through (no word repeated or skipped) whose word count is the
    app's. Nufais's truth is QUL's ayah recitation, on our own files."""
    out, skipped = [], dict(repeat=0, count=0)
    for vid, recs in recs_by_voice.items():
        for r in recs:
            if r['state'] not in ('match', 'partial') or not r['words']:
                continue
            s, a = map(int, r['key'].split(':'))
            words = words_of(text[s][a - 1])
            if vid == 'nufais':
                spans = nufais_spans.get(r['key']) or []
                if [(b, e) for b, e, _, _ in spans] != \
                        [(i, i + 1) for i in range(len(spans))]:
                    skipped['repeat'] += 1
                    continue
                true = [t0 for _, _, t0, _ in spans]
            else:
                pos = [p for p, _, _ in r['words']]
                if pos != list(range(1, len(pos) + 1)):
                    skipped['repeat'] += 1
                    continue
                true = [st - r['g'] for _, st, _ in r['words']]
            if len(true) != len(words):
                skipped['count'] += 1
                continue
            out.append(dict(voice=vid, style=STYLES.get(vid, 'murattal'),
                            env=r['env'], words=words, true=true))
    return out, skipped


def estimate_errors(samples, beta, use_pauses=True):
    """Errors (predicted - true) of every word start but each verse's
    first, which the app lights from the verse's own start anyway."""
    errs = []
    for smp in samples:
        res = estimate_starts(smp['env'], smp['words'], np.asarray(beta),
                              use_pauses)
        if res is not None:
            errs.extend(p - t for p, t in zip(res[0][1:], smp['true'][1:]))
    return errs


def fit_beta(samples, beta=BETA0, iters=8):
    """Least squares for the length model: within each breath group the
    estimate finds, each word's true length against beta . features
    scaled by the group's own pace; alternated with the pace and the
    grouping. No feature may shorten a word; scaled to one letter."""
    beta = np.asarray(beta, float)
    for _ in range(iters):
        rows, ys = [], []
        for smp in samples:
            res = estimate_starts(smp['env'], smp['words'], beta)
            if res is None:
                continue
            true = smp['true']
            for g0, g1, t0, t1 in res[1]:
                if g1 - g0 < 2:
                    continue
                feats = [word_features(smp['words'][i][0]) +
                         [1.0 if i == g1 - 1 else 0.0] for i in range(g0, g1)]
                rate = (t1 - t0) / sum(max(1e-3, float(np.dot(beta, x)))
                                       for x in feats)
                for k, i in enumerate(range(g0, g1)):
                    d = (true[i + 1] if i + 1 < g1 else t1) - true[i]
                    if d > 0:
                        rows.append([rate * x for x in feats[k]])
                        ys.append(d)
        new, *_ = np.linalg.lstsq(np.asarray(rows), np.asarray(ys),
                                  rcond=None)
        new = np.maximum(new, 0.0)
        beta = new / new[1]
    return beta


def _est_stats(errs):
    a = sorted(abs(x) for x in errs)
    return dict(n=len(a), median=round(pct(a, 0.5)), p75=round(pct(a, 0.75)),
                p90=round(pct(a, 0.9)),
                within_150=round(sum(x <= 150 for x in a) / len(a), 3),
                within_250=round(sum(x <= 250 for x in a) / len(a), 3))


def run_estimate(recs_by_voice, text, log):
    """The estimate, fitted on half the voices and tested on the other
    half, both ways; then fitted on all for the weights to ship."""
    nspans = {}
    for s in range(1, 115):
        for k, v in (qul_ayah(42, s).get('segments') or {}).items():
            nspans[k] = ayah_spans(v)
    samples, skipped = estimate_samples(recs_by_voice, text, nspans)
    voices = sorted({s['voice'] for s in samples})
    halves = (set(voices[0::2]), set(voices[1::2]))
    test = {k: [] for k in ('letters', 'letters_pauses', 'fitted')}
    style = {}
    for train, held in (halves, halves[::-1]):
        beta = fit_beta([s for s in samples if s['voice'] in train])
        for smp in (s for s in samples if s['voice'] in held):
            for k, b, up in (('letters', LETTERS_ONLY, False),
                             ('letters_pauses', LETTERS_ONLY, True),
                             ('fitted', beta, True)):
                e = estimate_errors([smp], b, up)
                test[k].extend(e)
                style.setdefault(f"{k} {smp['style']}", []).extend(e)
                if len(smp['words']) <= 12:
                    style.setdefault(f'{k} verses of 12 words or fewer',
                                     []).extend(e)
    beta = fit_beta(samples)
    # Breath groups alone: how often a group starts at the right word.
    right = tot = 0
    for smp in samples:
        res = estimate_starts(smp['env'], smp['words'], beta)
        for g0, _, t0, _ in (res[1][1:] if res else []):
            tot += 1
            near = min(range(len(smp['true'])),
                       key=lambda i: abs(smp['true'][i] - t0))
            right += near == g0
    out = dict(voices=voices, folds=[sorted(h) for h in halves],
               verses=len(samples), skipped=skipped,
               held_out={k: _est_stats(v) for k, v in test.items()},
               held_out_by_style={k: _est_stats(v)
                                  for k, v in sorted(style.items())},
               weights=dict(zip(FEATURES, [round(float(x), 3)
                                           for x in beta])),
               breath_group_right_word=round(right / tot, 3) if tot else None)
    log(f"estimate: {out['held_out']}")
    return out


# ---- per voice -----------------------------------------------------------

MIN_WORDS = 600  # verses with words a recitation needs to be tried


def _qul_summary(v):
    """What the JSON keeps of a recitation's word check."""
    out = dict(verses_with_words=v['verses_with_words'])
    if v['verses_with_words']:
        out.update(mismatched=v['mismatched'], odd=v['odd'])
        if v.get('surahs_without'):
            out['surahs_without'] = v['surahs_without']
    for k in ('not_ours', 'sizes_checked', 'sizes_differ'):
        if k in v:
            out[k] = v[k]
    return out


def _refs(r):
    return [('ayah', int(x[5:])) if str(x).startswith('ayah:')
            else ('surah', int(x)) for x in CANDIDATES[r['id']]]


def check_voice(r, text, words_by_rid, log):
    """Everything this tool knows about one voice, and what to do."""
    res = dict(name=r['name'], source=vr.source_key(r), kind=r['kind'])
    refs = _refs(r)
    tried = {}
    for kind, rid in refs:
        if kind == 'ayah':
            tried[f'ayah {rid}'] = check_ayah_recitation(text, r, rid)
        else:
            tried[f'surah {rid}'] = words_by_rid[rid]
    res['qul'] = {k: _qul_summary(v) for k, v in tried.items()}
    usable = [(kind, rid) for kind, rid in refs
              if tried[f'{kind} {rid}']['verses_with_words'] >= MIN_WORDS]
    if not usable:
        res.update(verdict='no_words', recommend='off')
        return res
    kind, rid = usable[0]
    if kind == 'ayah':
        t = tried[f'ayah {rid}']
        if not t['not_ours'] and not t['sizes_differ']:
            res.update(verdict='exact', use=f'ayah {rid}', recommend='on',
                       runtime=dict(method='ayah_spans', endpoint=(
                           f'{QUL}/ayah_segments/{rid}?surah={{s}}'
                           f'&per_page={{verses}}')))
    elif r['kind'] == 'surah' and same_file(
            vr.surah_url(r, 1), qul_surah(rid, 1)['audio']['url']):
        differ = same_files(r, rid)
        res['files_differ'] = differ
        if not differ:
            res.update(verdict='exact', use=f'surah {rid}', recommend='on',
                       runtime=dict(method='qul_times'))
    # The sample, for every usable recitation (an exact voice too: it is
    # the pipeline's own check, and the mapping's best case).
    res['sample'] = {}
    for kind, rid in usable:
        if kind == 'ayah':
            continue
        recs = records(r, rid, log)
        others = {}
        other_rid = 13 if rid != 13 else 161
        for x in recs:
            s = int(x['key'].split(':')[0])
            v = qul_surah(other_rid, s)['segments'].get(x['key'])
            if v and verse_words(v):
                others[x['key']] = verse_words(v)
        ev = evaluate(r, recs, others)
        res['sample'][f'surah {rid}'] = ev
        if 'verdict' not in res and ev['verdict'] in ('match', 'mixed'):
            res.update(verdict=ev['verdict'], use=f'surah {rid}')
    if 'verdict' not in res:
        res.update(verdict='different', recommend='off')
        return res
    if res['verdict'] == 'exact':
        return res
    # A same recording is worth the survey when the mapping is close.
    kind, rid = res['use'].split()
    rid = int(rid)
    ev = res['sample'][res['use']]
    shift = ev['variants']['shift']
    if not shift.get('p90') or shift['p90'] > 150:
        res['recommend'] = 'off'
        res['why'] = (f"the shift mapping's p90 is {shift.get('p90')} ms"
                      + (f"; QUL has another recording in surahs "
                         f"{ev['surahs_other_recording']}"
                         if ev['surahs_other_recording'] else ''))
        return res
    recs = records(r, rid, log)
    sample_errs = []
    for x in recs:
        if x['state'] in ('match', 'partial') and x['words'] and \
                x['verse'] != 1 and x['key'] not in ev['qul_misplaced']:
            e = _onset_err(x['env'], x['words'], x['g'])
            if e is not None:
                sample_errs.append(e)
    sv = survey(r, rid, log)
    su = res['survey'] = summarise_survey(r, sv, sample_errs)
    off = sorted(set(su['other_recording']) | set(su['no_words']) |
                 set(su['errors']))
    if su['other_recording']:
        res['verdict'] = 'mixed'  # another recording in some surahs
    after = su['gross_check']['shift_after']['stats'] or {}
    if r['kind'] == 'surah':
        offsets = su.pop('offset_ms')
        # Drift: the sample's verses deep into a surah against the
        # survey's verse 2 of it (parts per million of QUL time).
        ppm = sorted((x['file_offset'] - offsets[str(int(x['key'].split(
            ':')[0]))]) / x['tf'] * 1e6 for x in recs
            if x.get('file_offset') is not None and x['tf'] > 600000 and
            str(int(x['key'].split(':')[0])) in offsets)
        res['runtime'] = dict(method='offset', surahs_off=off,
                              offset_ms=offsets,
                              drift_ppm=round(pct(ppm, 0.5), 1) if ppm
                              else None)
    else:
        rules = su['verse1']
        rule = min(rules, key=lambda k: (rules[k]['p90'], k)) if rules \
            else None
        if rule is not None and rules[rule]['p90'] > 150:
            rule = None  # QUL's verse 1 holds what ours doesn't: unlit
        res['runtime'] = dict(
            method='shift', bias_ms=su['shift']['bias_ms'], surahs_off=off,
            verse1=dict(rule='none') if rule is None else dict(
                rule=rule, bias_ms=rules[rule]['bias_ms'],
                off=sorted(set(rules[rule]['off']) |
                           set(su['verse1_other_recording']))))
    if r['kind'] == 'ayah' and (not after or after['p90'] > 150):
        res['recommend'] = 'off'
        res['why'] = f'over every surah the shift mapping does {after}'
    else:
        res['recommend'] = 'on'
    return res


def _clean(work):
    """Deletes [work], a voice's audio folder, once the voice is done."""
    if os.path.isdir(work) and os.path.commonpath(
            [work, AUDIO]) == AUDIO and work != AUDIO:
        shutil.rmtree(work)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--only', action='append', default=[])
    args = ap.parse_args()
    os.makedirs(CACHE, exist_ok=True)
    old = json.load(open(OUT)) if os.path.exists(OUT) else {}
    reciters = {x['id']: x for x in vr.app_reciters()}
    missing = sorted(set(CANDIDATES) - set(reciters))
    assert not missing, f'not in the app any more: {missing}'
    todo = [v for v in sorted(CANDIDATES) if not args.only or v in args.only]
    text = quran_text()

    # Every surah recitation's words, once: coverage, soundness, text.
    rids = sorted({rid for v in todo for kind, rid in _refs(reciters[v])
                   if kind == 'surah'})
    words_by_rid = {}
    for rid in rids:
        words_by_rid[rid] = check_words(text, rid)
        print(f"qul {rid}: {words_by_rid[rid]['verses_with_words']} verses "
              f"with words, mismatched {words_by_rid[rid]['mismatched']}",
              flush=True)

    voices = old.get('voices', {})
    for v in todo:
        r = reciters[v]
        try:
            voices[v] = check_voice(r, text, words_by_rid, print)
        finally:
            _clean(os.path.join(AUDIO, v))
        e = voices[v]
        print(f"{v:<18} {e['verdict']:<10} {e.get('recommend')}", flush=True)

    out = dict(old, voices=voices)
    out['runtime'] = dict(
        onset=('o = 10*k ms for the first 10 ms frame k of the verse '
               "window's envelope (SurahSlice.envelopeOf) with frames "
               'k..k+MAP_RUN-1 all above quietBelow(that envelope, MAP_REL); '
               'f = 10*(j+1) for the last frame j ending such a run'),
        map_rel=MAP_REL, map_run_frames=MAP_RUN,
        shift='word start = o + (s - F) + bias_ms; F = the first QUL word '
              "start of the verse, s each word's",
        offset='word start = s - offset_ms[surah] - (window start in our '
               "file's time: originMs + cutStart + window start + lame "
               'bias)',
        qul_times='word start = s - (window start in the file\'s time: '
                  'originMs + cutStart + window start + lame bias)',
        lame_bias_ms='-1105000/sampleRate when the file opens with a '
                     'LAME/Info frame, else 0 (what a slice decode lacks '
                     'against the whole file)',
        gross_check=dict(ms=GROSS_MS, rel=GROSS_REL, rule=(
            '|(f - o) - (E - F)| <= max(ms, rel * (E - F)), E = the last '
            "QUL word end; a verse failing it gets no word highlight")),
        text=('n = the largest QUL word position of the verse (largest '
              'end index for ayah spans); the app words if n equals their '
              'count, else the same with one JOINS pair counted as one '
              'word, whichever count is n; else no word highlight'))
    if not args.only:
        # The text, against one recitation in full and the rest besides.
        fam = {}
        ref = words_by_rid.get(13, {}).get('_counts', {})
        for rid, w in sorted(words_by_rid.items()):
            if w['verses_with_words']:
                c = w.get('_counts', {})
                fam[str(rid)] = dict(
                    mismatched=w['mismatched'],
                    verses_with_words=w['verses_with_words'],
                    counts_differ_from_13=sorted(
                        (k for k in c if k in ref and c[k] != ref[k]),
                        key=lambda k: tuple(map(int, k.split(':')))))
        out['text'] = dict(
            joins={k: ' '.join(p) for k, p in JOINS.items()},
            bada_in_text=sorted(f'{s}:{a}' for s in text
                                for a, t in enumerate(text[s], 1)
                                if word_count(t) != word_count(t, 'bada')),
            by_recitation=fam)
        # The estimate, from every same-recording voice's sample.
        recs_by_voice = {}
        for v, e in sorted(voices.items()):
            if e.get('recommend') != 'on':
                continue
            kind, rid = e['use'].split()
            if kind == 'ayah':
                rid = '175'  # Nufais: the sample of its surah recordings
            path = os.path.join(CACHE, 'records', f'{v}_{rid}.json')
            if os.path.exists(path):
                recs_by_voice[v] = json.load(open(path))['recs']
        out['estimate'] = run_estimate(recs_by_voice, text, print)
    json.dump(out, open(OUT, 'w', encoding='utf8'), ensure_ascii=False,
              indent=1, sort_keys=True)
    print(f'-> {OUT}')


if __name__ == '__main__':
    main()
