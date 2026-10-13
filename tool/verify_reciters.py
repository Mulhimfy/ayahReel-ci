#!/usr/bin/env python3
"""Verify every reciter the app offers, before it is offered.

A voice that fails halfway through Al-Baqarah, or whose verses change
a second late, is worse than a voice that isn't there. So no reciter
goes into `lib/data/fatiha_data.dart` until it has passed all of this.
The list checked is read from that file itself, so the two can't drift.

Per-ayah voices (EveryAyah, Tarteel, KSU): one mp3 per verse, measured on
the device, so sync is exact by construction. What can go wrong is a
missing file, so:

  1. Every file.   All 6236 verse files answer 200 with a body. Voices
     that shipped before this tool existed are sampled (60 verses
     spread across the mushaf) unless --full is given.
  2. Quality.      Bitrate and sample rate, from 40 real files; the set
     passes on its median file, and any file below MIN_KBPS is named.
  3. Pace.         Measured over a spread of verses, against the model
     in lib/data/reel_duration.dart.

Surah-file voices: one mp3 per surah, plus a published table of where
each verse starts and ends in it — mp3quran.net's `ayat_timing`, or the
Quranic Universal Library's surah segments (Tarteel). The app
fetches only the byte range a reel needs, so it relies on the table,
the file and the byte arithmetic all agreeing. All of it is checked:

  4. Every table.  All 114 tables have exactly the Hafs verse count,
     numbered 1..N, every window positive, starts never going back.
  5. Every file.   All 114 surah files answer a byte range with 206,
     are constant-bitrate MPEG Layer III (a VBR file can't be sliced
     by arithmetic), and are long enough for their own table.
  6. Alignment.    Slices are cut exactly the way the app cuts them
     (the same frame search, the same origin arithmetic), at the start
     of the mushaf, deep inside Al-Baqarah, and at twenty other places,
     and every verse start in them is checked against the audio: there
     has to be a breath — PAUSE_MIN_MS or more of quiet — within the
     reach the app snaps a boundary over (SNAP_MS, or EDGE_MS before a
     verse 1, which only ever opens a reel). A voice passes when
     MIN_ALIGNED_SHARE of its boundaries have one, and when the same
     table moved a second or more either way scores no better than
     MAX_SHIFTED_SHARE: a reciter who leaves long pauses everywhere
     would otherwise pass with any table at all.

     A voice in USER_ACCEPTED was taken though this could not vouch
     for it; its shortfall is recorded as a warning, with why.

     Where a table counts a surah's opening words (the basmala) as verse
     1's, the voice says so with openingMs, and the pause after them is
     checked for in every surah but At-Tawbah. A surah
     a voice can't have (a file gone, a table that doesn't fit) is named
     in its `missing` set; the app doesn't offer it, and it isn't
     checked.

     How this was calibrated: for twelve voices on both EveryAyah and
     mp3quran, every per-ayah file was located inside the mp3quran surah
     file, which gives the true boundaries. Tables built from those
     files (Al-Tablawi, Al-Alaqimy, Neana) put 98-100% of boundaries in
     the breath and score 0.99-1.00 here; shifted, 0.12-0.46.
  7. Quality.      Bitrate >= 64 kbps and sample rate >= 22050 Hz.
  8. Pace.         From all 6236 windows.

Results go to tool/reciters_verified.json; test/reciter_sources_test.dart
refuses a build where a reciter in the app has no passing entry there,
or where the entry was made for a different source.

Run:  python3 tool/verify_reciters.py            # every reciter in the app
      python3 tool/verify_reciters.py --only ID  # one (repeatable)
      python3 tool/verify_reciters.py --survey   # every mp3quran Hafs set
                                                 # with timings, app or not
"""
import argparse
import array
import json
import math
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, 'build', 'verify_reciters')
OUT = os.path.join(ROOT, 'tool', 'reciters_verified.json')
UA = {'User-Agent': 'ayahreel-verify'}

EVERYAYAH = 'https://everyayah.com/data'
TARTEEL = 'https://audio-cdn.tarteel.ai/quran'
KSU = 'https://quran.ksu.edu.sa/ayat/mp3'
AYAH_HOSTS = {'everyAyah': EVERYAYAH, 'tarteel': TARTEEL, 'ksu': KSU}
TIMING_API = 'https://www.mp3quran.net/api/v3/ayat_timing'
QUL_API = 'https://qul.tarteel.ai/api/v1/audio/surah_segments'

# The app snaps each verse boundary to the quietest 10 ms within this
# many milliseconds of where the table puts it, and looks this far
# outwards for a reel's own two ends (SurahSlice.snapMs / edgeMs).
SNAP_MS = 350
EDGE_MS = 800
# A breath: this long or longer at the bottom PAUSE_REL of the slice's
# range, from its silence floor to its speech level (both measured on
# the 100 ms envelope, digital silence left out of the floor).
PAUSE_REL = 0.35
PAUSE_MIN_MS = 200
# See 6. in the docstring.
MIN_ALIGNED_SHARE = 0.85
MAX_SHIFTED_SHARE = 0.50
SHIFTS = (-2700, -1900, -1100, 1100, 1900, 2700)

# Voices the user chose to have although this tool could not vouch for
# them (2026-09-29), and why. For these, what the tool measures about
# sync (the alignment share, the shifted baseline) and sound (bitrate,
# sample rate) is recorded as a warning instead of a failure. Anything
# broken — a file that isn't there, a table that doesn't fit its audio
# — still fails, unless the surah is in the voice's `missing` set, which
# the app then doesn't offer.
_JOINED = ('most misses have no pause within 2 s at all: verses joined in '
           'one breath, where the app keeps the table\'s time')
_PAUSES = ('pauses so often that even a shifted table lands in them, so '
           'this check cannot tell; in place, nearly every boundary does')
_THIN = 'sound quality below the bar; the user chose to have the voice'
SYNC, SOUND = 'sync', 'sound'
USER_ACCEPTED = {
    'jaleel': ({SYNC}, _JOINED + "; mp3quran's table and Quran.com's "
                       'word-level one agree to a median 50-170 ms in 11 of '
                       '14 sampled surahs, and the user heard it work on the '
                       'phone'),
    'khayyat': ({SYNC}, _JOINED + ' (a clean recording, 41 dB from silence '
                                  'to speech)'),
    'muaiqly_mujawwad': ({SYNC}, _PAUSES), 'bukheet': ({SYNC}, _PAUSES),
    'abdulbari_mohammad': ({SYNC}, _PAUSES),
    'toure': ({SYNC}, _PAUSES + '; ' + _JOINED),
    'rashad': ({SYNC}, _PAUSES + '; ' + _JOINED), 'mousa': ({SYNC}, _JOINED),
    'rayan': ({SYNC}, _JOINED), 'sanankoua': ({SYNC}, _JOINED),
    'dukhain': ({SYNC}, _JOINED), 'sayegh': ({SYNC}, _JOINED),
    'obaikan': ({SYNC}, _JOINED), 'daghistani': ({SYNC}, _JOINED),
    'albanna_mujawwad': ({SYNC}, _PAUSES + '; ' + _JOINED),
    'haneef': ({SYNC}, _JOINED + ', though more misses than most have a '
                                 'pause nearby'),
    'noah': ({SYNC}, _JOINED + ', with some nearby'),
    'qari': ({SYNC}, _JOINED + ', with some nearby'),
    'asiri': ({SYNC}, _JOINED + ', with some nearby'),
    'saber': ({SOUND}, _THIN), 'emad_hafez': ({SOUND}, _THIN),
    'mohana': ({SOUND}, _THIN),
    'mustafa_ismail_mujawwad': ({SYNC, SOUND}, _PAUSES + '; ' + _JOINED +
                                '; ' + _THIN),
    'raad_kurdi': ({SYNC}, _JOINED),
    'akhdar': ({SOUND}, _THIN),
}


MIN_KBPS = 64
MIN_RATE = 22050

# The voices that shipped before this tool existed: all EveryAyah, all
# in users' hands for months. They are sampled (see 1. above) unless
# --full asks for every file; everything added since is checked whole.
SHIPPED_BEFORE = {
    'alafasy', 'husary', 'abdulbasit', 'minshawi', 'sudais', 'shuraym',
    'muaiqly', 'hudhaify', 'dussary', 'shatri', 'ayyub', 'ajmi', 'qatami',
    'qasim', 'juhani', 'budair', 'rifai', 'tablawi', 'jibreel', 'basfar',
    'bukhatir', 'qahtani', 'matrood', 'neana', 'salamah', 'alaqimy', 'suesy',
    'alili', 'abdulkareem', 'sahl_yassin', 'jaber', 'abbad', 'sowaid',
    'tunaiji', 'husary_mujawwad', 'abdulbasit_mujawwad', 'minshawi_mujawwad',
}

# Where alignment is sampled: (surah, first ayah, last ayah). The start
# of the book, deep into its longest surah, and on through to the end.
WINDOWS = [
    (1, 1, 7), (2, 1, 8), (2, 253, 257), (2, 282, 286), (3, 190, 200),
    (7, 1, 12), (12, 1, 10), (18, 1, 10), (18, 107, 110), (19, 1, 15),
    (24, 35, 40), (33, 40, 45), (36, 1, 20), (48, 27, 29), (55, 1, 20),
    (59, 20, 24), (67, 1, 30), (78, 1, 20), (89, 1, 16), (97, 1, 5),
    (112, 1, 4), (114, 1, 6),
]
# Stand-ins, in order, for windows in surahs a voice is missing, until
# as many boundaries are sampled as WINDOWS holds.
EXTRA_WINDOWS = [
    (13, 1, 10), (15, 1, 15), (28, 1, 10), (31, 1, 12), (41, 1, 10),
    (44, 1, 15), (50, 1, 15), (51, 1, 15), (56, 1, 20), (70, 1, 15),
    (71, 1, 10), (74, 1, 20), (86, 1, 17), (91, 1, 15), (100, 1, 11),
]


# ---- the Quran the app displays -------------------------------------

def hafs_counts():
    src = open(os.path.join(ROOT, 'lib/data/surah_index.dart')).read()
    counts = [int(m) for m in re.findall(r'ayahCount: (\d+)', src)]
    assert len(counts) == 114 and sum(counts) == 6236, 'surah_index changed'
    return counts


COUNTS = hafs_counts()


def letters(arabic):
    """ReelDuration.lettersIn, exactly."""
    n = 0
    for ch in arabic:
        c = ord(ch)
        if c == 0x0640:
            continue
        if (0x0621 <= c <= 0x063A or 0x0641 <= c <= 0x064A or
                0x066E <= c <= 0x066F or 0x0671 <= c <= 0x06D3):
            n += 1
    return n


def model_ms():
    """ReelDuration's estimate for every verse, pace 1.0."""
    text = json.load(open(os.path.join(ROOT, 'assets/quran_search.json'),
                          encoding='utf8'))
    out = {}
    for s in range(1, 115):
        verses = text[str(s)]
        assert len(verses) == COUNTS[s - 1], f'text of surah {s}'
        for a, v in enumerate(verses, 1):
            out[(s, a)] = 1200 + 230 * letters(v)
    return out


# ---- the reciters the app offers ------------------------------------

def app_reciters():
    """Every Reciter entry in fatiha_data.dart: id, names and source."""
    src = open(os.path.join(ROOT, 'lib/data/fatiha_data.dart'),
               encoding='utf8').read()
    body = src[src.index('const reciters = <Reciter>['):]
    body = body[:body.index('\n];')]
    out = []
    for block in re.split(r'\n  Reciter\(', body)[1:]:
        rid = re.search(r"id: '([^']+)'", block).group(1)
        name = re.search(r"\bname: '([^']+)'", block).group(1)
        ar = re.search(r"arabicName: '([^']+)'", block).group(1)
        m = re.search(r"source: AyahFiles\.(everyAyah|tarteel|ksu)\("
                      r"\s*'([^']+)',?\s*\)", block)
        if m:
            host = AYAH_HOSTS[m.group(1)]
            out.append(dict(id=rid, name=name, ar=ar, kind='ayah',
                            base=f'{host}/{m.group(2)}',
                            bundled='audioAsset:' in block))
            continue
        m = re.search(r"source: SurahFiles\(\s*'([^']+)',", block)
        assert m, f'{rid}: no source this tool understands'
        rest = block[m.end():]
        t = re.search(r'timing: (Mp3QuranTiming|QulTiming)\((\d+)\)', rest)
        assert t, f'{rid}: no timing this tool understands'
        o = re.search(r'openingMs: (\d+)', rest)
        gone = re.search(r'missing: \{([\d,\s]*)\}', rest)
        out.append(dict(id=rid, name=name, ar=ar, kind='surah',
                        base=m.group(1),
                        padded='padded: false' not in rest,
                        opening=int(o.group(1)) if o else None,
                        missing=sorted(int(x) for x in re.findall(
                            r'\d+', gone.group(1))) if gone else [],
                        timing=('mp3quran' if t.group(1) == 'Mp3QuranTiming'
                                else 'qul', int(t.group(2)))))
    return out


def source_key(r):
    """How a voice's source is written in reciters_verified.json, and
    so what test/reciter_sources_test.dart compares the app against."""
    if r['kind'] == 'ayah':
        return f"ayah {r['base']}"
    kind, key = r['timing']
    return (f"surah {r['base']} {'SSS' if r.get('padded', True) else 'S'} "
            f"{kind} {key}"
            + (f" opening {r['opening']}" if r.get('opening') else '')
            + (f" missing {','.join(map(str, r['missing']))}"
               if r.get('missing') else ''))


# ---- HTTP ------------------------------------------------------------

def _get(url, headers=None, tries=4, timeout=40):
    last = None
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers={**UA, **(headers or {})})
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.status, {k.lower(): v for k, v in r.headers.items()}, \
                    r.read()
        except urllib.error.HTTPError as e:
            if e.code in (404, 403, 410, 416):
                return e.code, {}, b''
            last = e
        except Exception as e:  # noqa: BLE001 - network flake, retried
            last = e
        time.sleep(0.6 * (i + 1))
    raise RuntimeError(f'{url}: {last}')


def cached_json(url, key):
    path = os.path.join(CACHE, 'json', key)
    if os.path.exists(path):
        return json.load(open(path, encoding='utf8'))
    status, _, body = _get(url)
    if status != 200:
        raise RuntimeError(f'{url}: HTTP {status}')
    data = json.loads(body)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    json.dump(data, open(path, 'w', encoding='utf8'))
    return data


# ---- MPEG audio layout (mirrors RecitationService._Mp3Layout) --------

_BR = {  # kbps by bitrate index, Layer III
    1: [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320],
    2: [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160],
}
_SR = {3: [44100, 48000, 32000], 2: [22050, 24000, 16000],
       0: [11025, 12000, 8000]}


def parse_header(b, i):
    """(version, kbps, rate, samples/frame, length) of a Layer III frame
    header at b[i], or None."""
    if i + 4 > len(b) or b[i] != 0xFF or (b[i + 1] & 0xE0) != 0xE0:
        return None
    ver = (b[i + 1] >> 3) & 3
    layer = (b[i + 1] >> 1) & 3
    bri = b[i + 2] >> 4
    sri = (b[i + 2] >> 2) & 3
    pad = (b[i + 2] >> 1) & 1
    if ver == 1 or layer != 1 or bri in (0, 15) or sri == 3:
        return None
    kbps = _BR[1 if ver == 3 else 2][bri]
    rate = _SR[ver][sri]
    spf = 1152 if ver == 3 else 576
    coef = 144 if ver == 3 else 72
    return ver, kbps, rate, spf, coef * kbps * 1000 // rate + pad


def id3_size(head):
    if head[:3] != b'ID3':
        return 0
    size = ((head[6] & 127) << 21 | (head[7] & 127) << 14 |
            (head[8] & 127) << 7 | (head[9] & 127))
    footer = 10 if head[5] & 0x10 else 0
    return 10 + size + footer


def layout(url):
    """Where the audio starts in [url], and what its frames look like.
    Kept in the cache like everything else here: delete
    build/verify_reciters to check the files afresh."""
    key = re.sub(r'[^A-Za-z0-9]+', '_', url)
    path = os.path.join(CACHE, 'layout', key + '.json')
    if os.path.exists(path):
        return json.load(open(path))
    res = _layout(url)
    if res.get('ok'):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        json.dump(res, open(path, 'w'))
    return res


def _layout(url):
    status, hdr, head = _get(url, {'Range': 'bytes=0-9'})
    if status != 206:
        return dict(ok=False, why=f'range request answered {status}')
    total = int(hdr.get('content-range', '/0').split('/')[-1])
    start = id3_size(head)
    status, _, b = _get(url, {'Range': f'bytes={start}-{start + 8191}'})
    if status != 206:
        return dict(ok=False, why=f'range request answered {status}')
    # Tolerate a few junk bytes after the tag, as players do.
    i = next((k for k in range(min(len(b) - 4, 2048))
              if parse_header(b, k) and
              parse_header(b, k + parse_header(b, k)[4])), None)
    if i is None:
        return dict(ok=False, why='no MPEG Layer III frame at the start')
    ver, kbps, rate, spf, flen = parse_header(b, i)
    first = b[i:i + flen]
    vbr = b'Xing' in first or b'VBRI' in first
    info = b'Info' in first
    data = start + i
    avg = (144 if ver == 3 else 72) * kbps * 1000 / rate
    return dict(ok=True, total=total, data=data, kbps=kbps, rate=rate,
                spf=spf, avg=avg, vbr=vbr, info=info, ver=ver,
                audio_ms=(total - data) / (kbps / 8) - (
                    spf * 1000 / rate if info else 0))


def fetch_slice(url, lay, from_ms, to_ms):
    """Bytes of [from_ms, to_ms) and the time the first byte starts at —
    the arithmetic RecitationService uses, frame for frame."""
    frame_ms = lay['spf'] * 1000 / lay['rate']
    first_audio = 1 if lay['info'] else 0
    k = int(max(0, from_ms) // frame_ms) + first_audio
    want = lay['data'] + round(k * lay['avg'])
    pad = int(lay['avg'] * 4)
    lo = max(lay['data'], want - pad)
    hi = min(lay['total'] - 1,
             lay['data'] + math.ceil((to_ms / frame_ms + first_audio + 2)
                                     * lay['avg']))
    status, _, b = _get(url, {'Range': f'bytes={lo}-{hi}'}, timeout=120)
    if status != 206:
        raise RuntimeError(f'slice answered {status}')
    # The frame nearest where frame k should start, confirmed by the
    # frame after it.
    best = None
    for i in range(0, min(len(b) - 4, 2 * pad + int(lay['avg']) * 2)):
        h = parse_header(b, i)
        if not h or h[1] != lay['kbps'] or h[2] != lay['rate']:
            continue
        h2 = parse_header(b, i + h[4])
        if not h2 or h2[1] != lay['kbps'] or h2[2] != lay['rate']:
            continue
        if best is None or abs(lo + i - want) < abs(lo + best - want):
            best = i
    if best is None:
        raise RuntimeError('no frame near the slice start')
    pos = lo + best
    k = round((pos - lay['data']) / lay['avg'])
    origin = (k - first_audio) * frame_ms
    return b[best:], origin


# ---- audio analysis (mirrors RecitationService._snap) ----------------

def envelope(mp3_bytes, rate=8000):
    """10 ms RMS frames in dB of the decoded audio."""
    p = subprocess.run(
        ['ffmpeg', '-v', 'error', '-f', 'mp3', '-i', '-', '-ac', '1',
         '-ar', str(rate), '-f', 's16le', '-'],
        input=mp3_bytes, capture_output=True, check=True)
    s = array.array('h')
    s.frombytes(p.stdout[:len(p.stdout) // 2 * 2])
    n = rate // 100
    out = []
    for i in range(0, len(s) - n + 1, n):
        acc = 0
        for x in s[i:i + n]:
            acc += x * x
        out.append(10 * math.log10(acc / n + 1))
    return out


def smooth(env, w=10):
    """[env] averaged over [w] frames (100 ms) in the power domain — long
    enough to ride over the gap inside a stop consonant, short enough
    to keep a breath between verses."""
    c = [0.0]
    for e in env:
        c.append(c[-1] + 10 ** (e / 10))
    out = []
    for i in range(len(env)):
        lo, hi = max(0, i - w // 2), min(len(env), i + w // 2 + 1)
        out.append(10 * math.log10((c[hi] - c[lo]) / (hi - lo)))
    return out


def levels(sm):
    """(silence floor, speech level) of a slice's 100 ms envelope. The
    stretch of digital silence some files open with is left out: it is
    far below any breath, and counting it would put the floor there."""
    live = sorted(x for x in sm if x > 10) or sorted(sm)
    return live[int(len(live) * 0.05)], live[int(len(live) * 0.9)]


def breaths(sm):
    """Every run of PAUSE_MIN_MS or more at the bottom PAUSE_REL of the
    slice's range, as (from ms, to ms) in the slice."""
    floor, speech = levels(sm)
    lim = floor + PAUSE_REL * (speech - floor)
    runs, st = [], None
    for k, x in enumerate(list(sm) + [math.inf]):
        if x <= lim:
            if st is None:
                st = k
        elif st is not None:
            if (k - st) * 10 >= PAUSE_MIN_MS:
                runs.append((st * 10, k * 10))
            st = None
    return runs


def breath_within(runs, t_ms, before, after):
    """Whether a breath reaches into [t_ms - before, t_ms + after]."""
    return any(a <= t_ms + after and b >= t_ms - before for a, b in runs)


def window_envelope(url, lay, key, from_ms, to_ms):
    """Envelope of the slice [from_ms, to_ms) cut the app's way, and the
    time its first frame starts at. Cached, so thresholds can be tuned
    without fetching again."""
    path = os.path.join(CACHE, 'env', key + '.json')
    if os.path.exists(path):
        d = json.load(open(path))
        return d['env'], d['origin']
    data, origin = fetch_slice(url, lay, from_ms, to_ms)
    env = [round(e, 2) for e in envelope(data)]
    os.makedirs(os.path.dirname(path), exist_ok=True)
    json.dump(dict(env=env, origin=origin), open(path, 'w'))
    return env, origin


def surah_table(timing, s):
    """The published table for surah [s] as rows of {ayah, start_time,
    end_time}, verse 0 (a separate isti'adha and basmala) left out, or
    whatever came back when it isn't a table at all."""
    kind, key = timing
    count = COUNTS[s - 1]
    if kind == 'mp3quran':
        t = cached_json(f'{TIMING_API}?surah={s}&read={key}',
                        f'timing_{key}_{s:03d}.json')
        if isinstance(t, list):
            t = [row for row in t if row.get('ayah') != 0]
        return t
    d = cached_json(f'{QUL_API}/{key}?surah={s}&from=1&to={count}'
                    f'&per_page={count}', f'qul_{key}_{s:03d}.json')
    seg = d.get('segments') if isinstance(d, dict) else None
    if not isinstance(seg, dict):
        return d
    return [dict(ayah=a, start_time=seg[f'{s}:{a}'].get('time_from'),
                 end_time=seg[f'{s}:{a}'].get('time_to'))
            for a in range(1, count + 1) if f'{s}:{a}' in seg]


def surah_url(r, s):
    return f"{r['base'].rstrip('/')}/" + (
        f'{s:03d}' if r.get('padded', True) else f'{s}') + '.mp3'


# ---- the checks ------------------------------------------------------

def check_surah_voice(r, model, log):
    base = r['base'].rstrip('/')
    tag = f"{r['timing'][0]}{r['timing'][1]}"
    res = dict(kind='surah', base=base, timing=list(r['timing']),
               source=source_key(r), problems=[])
    prob = res['problems']
    missing = set(r.get('missing') or [])
    kinds_ok, accepted = USER_ACCEPTED.get(r['id'], (set(), None))
    live = [s_ for s_ in range(1, 115) if s_ not in missing]
    # Surahs something structural is wrong with: each is a problem unless
    # the voice lists it as missing. Collected, not stopped at, so one
    # run says which a voice's `missing` set has to name.
    broken = {}

    def soft(why, kind):
        """A measure of [kind] (SYNC or SOUND): a warning for a voice the
        user chose to have regardless of it (USER_ACCEPTED), a failure
        otherwise."""
        if kind in kinds_ok:
            res.setdefault('warnings', []).append(f'{why} — {accepted}')
        else:
            prob.append(why)

    # 4. Every table. A last verse whose end is not after its start is
    # given the end of its file, as the app does (the table is otherwise
    # sound; see SurahSlice.parseTable).
    def table(s):
        return s, surah_table(r['timing'], s)
    with ThreadPoolExecutor(8) as ex:
        tables = dict(ex.map(table, live))
    open_end = set()
    for s in live:
        t = tables[s]
        if not isinstance(t, list) or len(t) != COUNTS[s - 1]:
            broken[s] = (f'table {s}: {len(t) if isinstance(t, list) else t!r}'
                         f' verses, Hafs has {COUNTS[s - 1]}')
            continue
        prev = -1
        for a, row in enumerate(t, 1):
            st, en = row.get('start_time'), row.get('end_time')
            last = a == len(t)
            if row.get('ayah') != a or st is None or en is None or \
                    st < prev or (en <= st and not last):
                broken[s] = f'table {s}:{a} malformed {row}'
                break
            if en <= st:
                open_end.add(s)
            prev = st

    # 5. Every file.
    def lay(s):
        return s, layout(surah_url(r, s))
    with ThreadPoolExecutor(8) as ex:
        lays = dict(ex.map(lay, [s_ for s_ in live if s_ not in broken]))
    kinds = set()
    for s, L in sorted(lays.items()):
        if not L['ok']:
            broken[s] = f'file {s}: {L["why"]}'
            continue
        if L['vbr']:
            broken[s] = f'file {s}: variable bitrate'
            continue
        kinds.add((L['kbps'], L['rate']))
        if s in open_end:
            tables[s][-1] = dict(tables[s][-1], end_time=int(L['audio_ms']))
        # A last verse that ends a little past the audio is clamped by
        # the app to where the file ends; one that starts past it, or
        # a table that overruns by seconds, belongs to another edit of
        # the recording.
        last = tables[s][-1]
        if L['audio_ms'] < last['start_time'] + 1000 or \
                L['audio_ms'] < last['end_time'] - 2500:
            broken[s] = (f'file {s}: audio is {L["audio_ms"]:.0f} ms, its '
                         f'table runs to {last["end_time"]} ms')
    res['broken'] = sorted(broken)
    for s in sorted(broken):
        prob.append(broken[s])
    ok = [s_ for s_ in live if s_ not in broken]
    if res['broken']:
        res['open_end'] = sorted(open_end)
    total_ms = model_total = 0
    for s in ok:
        for a, row in enumerate(tables[s], 1):
            total_ms += row['end_time'] - row['start_time']
            model_total += model[(s, a)]
    if not model_total:
        return res
    res['pace'] = round(total_ms / model_total, 3)
    res['formats'] = sorted(kinds)
    if kinds:
        res['kbps'] = min(k for k, _ in kinds)
        res['rate'] = min(r_ for _, r_ in kinds)
        if res['kbps'] < MIN_KBPS or res['rate'] < MIN_RATE:
            soft(f'quality: {res["kbps"]} kbps at {res["rate"]} Hz', SOUND)

    # Verse 1 has to start after the basmala, as the per-ayah files do:
    # the app shows verse 1 without it, so a table that folds it into
    # verse 1 would play it under the wrong text. Its sign is a verse 1
    # that runs far longer than its letters allow.
    folded = []
    for s_ in ok:
        if s_ in (1, 9):
            continue
        d = tables[s_][0]['end_time'] - tables[s_][0]['start_time']
        if d - res['pace'] * model[(s_, 1)] > 4000 and \
                tables[s_][0]['start_time'] < 1500:
            folded.append(s_)
    res['basmala_in_verse1'] = len(folded)
    if r.get('opening'):
        check_opening(r, tables, lays, ok, res)
    elif len(folded) > 5:
        why = (f'basmala: folded into verse 1 in {len(folded)} surahs, '
               f'e.g. {folded[:6]}')
        res['basmala_folded'] = folded
        if SYNC in kinds_ok:
            # A reel that starts at verse 1 of one of these may open
            # with the basmala; everything else about them is sound.
            res.setdefault('warnings', []).append(
                f'{why} — a verse-1 reel there may open with the basmala')
        else:
            prob.append(why)

    # 6. Alignment, cut the way the app cuts: every verse start in each
    # window, and the same table moved by a second or more either way.
    hits = {sh: [] for sh in (0,) + SHIFTS}
    missed = []
    wanted = sum(a1 - a0 + 1 for _, a0, a1 in WINDOWS)
    wins = [w for w in WINDOWS if w[0] in ok]
    for w in EXTRA_WINDOWS:
        if sum(a1 - a0 + 1 for _, a0, a1 in wins) >= wanted:
            break
        if w[0] in ok:
            wins.append(w)
    for s_, a0, a1 in wins:
        t = tables[s_]
        from_ms = t[a0 - 1]['start_time'] - 5000
        to_ms = t[a1 - 1]['end_time'] + 5000
        env, origin = window_envelope(
            surah_url(r, s_), lays[s_], f'{tag}_{s_}_{a0}_{a1}',
            from_ms, to_ms)
        sm = smooth(env)
        runs = breaths(sm)
        for a in range(a0, a1 + 1):
            before = EDGE_MS if a == 1 else SNAP_MS
            at = t[a - 1]['start_time'] - origin
            for sh, got in hits.items():
                x = at + sh
                if x - before < 0 or x + SNAP_MS > len(sm) * 10:
                    continue
                ok_ = breath_within(runs, x, before, SNAP_MS)
                got.append(ok_)
                if sh == 0 and not ok_:
                    missed.append(f'{s_}:{a}')
    n = len(hits[0])
    res['boundaries'] = n
    if n < 150:
        prob.append(f'alignment: only {n} boundaries could be sampled')
    if not n:
        return res
    res['aligned_share'] = round(sum(hits[0]) / n, 3)
    res['shifted_share'] = round(max(sum(v_) / len(v_)
                                     for k, v_ in hits.items() if k), 3)
    res['missed'] = missed
    if res['aligned_share'] < MIN_ALIGNED_SHARE:
        soft(f'alignment: a breath at {res["aligned_share"]:.0%} of '
             f'{n} boundaries', SYNC)
    if res['shifted_share'] > MAX_SHIFTED_SHARE:
        soft(f'alignment: shifted tables score {res["shifted_share"]:.0%} — '
             f'this audio has pauses everywhere, so its table cannot be '
             f'checked', SYNC)
    return res


def probe(mp3_bytes):
    """ffprobe's reading of [mp3_bytes]. From a file, not a pipe: through
    a pipe ffprobe can't seek, and for a file with no Xing header it then
    reports no duration at all."""
    d = os.path.join(CACHE, 'probe')
    os.makedirs(d, exist_ok=True)
    path = os.path.join(d, f'{os.getpid()}.mp3')
    with open(path, 'wb') as f:
        f.write(mp3_bytes)
    try:
        p = subprocess.run(
            ['ffprobe', '-v', 'error', '-show_entries',
             'format=duration:stream=sample_rate,bit_rate', '-of', 'json',
             path], capture_output=True, text=False)
        return json.loads(p.stdout or b'{}')
    finally:
        os.remove(path)


def opening_pause(runs, v1_at, opening_ms):
    """SurahSlice.openingPause: the pause after the words a surah opens
    with, looked for 0.6-1.6x [opening_ms] into the speech."""
    onset = v1_at
    for a, b in runs:
        if a <= v1_at < b:
            onset = b
    for a, b in runs:
        if opening_ms * 0.6 <= a - onset <= opening_ms * 1.6:
            return a, b
    return None


def check_opening(r, tables, lays, ok, res):
    """For a voice whose tables count the basmala (and, before Al-Fatiha,
    the isti'adha) as verse 1's: the app starts a verse-1 reel at the
    pause after them, so that pause has to be where the app looks for it
    in every surah that has one — cut the way the app cuts a reel of
    verse 1 alone — with some of verse 1 left after it."""
    tag = f"{r['timing'][0]}{r['timing'][1]}"
    found, missing = [], []
    for s in ok:
        if s == 9:
            continue
        v1 = tables[s][0]
        env, origin = window_envelope(
            surah_url(r, s), lays[s], f'{tag}_open_{s}',
            v1['start_time'] - EDGE_MS - 1000, v1['end_time'] + EDGE_MS + 1000)
        runs = breaths(smooth(env))
        p = opening_pause(runs, v1['start_time'] - origin, r['opening'])
        if p is None or v1['end_time'] - origin - p[1] < 300:
            missing.append(s)
        else:
            found.append(p[0] - (v1['start_time'] - origin))
    res['opening_found'] = len(found)
    if found:
        res['opening_ms_range'] = [min(found), max(found)]
    if missing:
        res['problems'].append(f'opening: no pause after it in surahs '
                               f'{missing[:12]}')


def check_ayah_voice(r, model, full, log):
    base = r['base'].rstrip('/')
    res = dict(kind='ayah', base=base, source=source_key(r), problems=[])
    prob = res['problems']
    keys = [(s, a) for s in range(1, 115) for a in range(1, COUNTS[s - 1] + 1)]
    if full:
        want = keys
    else:
        step = len(keys) // 60
        want = keys[::step] + [(2, 286), (114, 6)]
    res['files_checked'] = len(want)

    def head(k):
        s, a = k
        url = f'{base}/{s:03d}{a:03d}.mp3'
        status, hdr, _ = _get(url, {'Range': 'bytes=0-0'})
        return k, status
    with ThreadPoolExecutor(8) as ex:
        missing = [k for k, st in ex.map(head, want) if st not in (200, 206)]
    if missing:
        prob.append(f'{len(missing)} verse files missing, e.g. '
                    f'{missing[:8]}')
        return res

    # Quality and pace from a spread of whole files.
    sample = keys[::len(keys) // 40]
    got = act = 0
    kinds = set()
    per_file = []
    for s, a in sample:
        # A host that has just answered six thousand requests may turn
        # the next few away for a moment; a file it keeps refusing is a
        # problem, not a crash.
        for attempt in range(4):
            status, hdr, b = _get(f'{base}/{s:03d}{a:03d}.mp3')
            info = probe(b)
            if status == 200 and 'duration' in info.get('format', {}):
                break
            time.sleep(10 * (attempt + 1))
        else:
            prob.append(f'{s}:{a}: HTTP {status} {hdr.get("content-type")} '
                        f'{len(b)} bytes, not audio: {b[:60]!r}')
            return res
        dur = float(info['format']['duration']) * 1000
        st = info['streams'][0]
        fmt = (int(st['bit_rate']) // 1000, int(st['sample_rate']))
        kinds.add(fmt)
        per_file.append((fmt, f'{s}:{a}'))
        got += dur
        act += model[(s, a)]
    res['pace'] = round(got / act, 3)
    res['formats'] = sorted(kinds)
    # A per-ayah set is judged by its files as a whole: EveryAyah's
    # 128 kbps folders hold the odd verse re-cut at a lower rate, and one
    # such file is a verse that sounds thinner, not a voice to withdraw.
    # Those files are named in the results all the same.
    rates = sorted(k for (k, _), _ in per_file)
    res['kbps'] = rates[len(rates) // 2]
    res['rate'] = sorted(r_ for (_, r_), _ in per_file)[len(rates) // 2]
    res['low_files'] = [f'{v} at {k} kbps' for (k, _), v in per_file
                        if k < MIN_KBPS]
    if res['kbps'] < MIN_KBPS or res['rate'] < MIN_RATE:
        why = f'quality: {res["kbps"]} kbps at {res["rate"]} Hz'
        # A voice already in users' hands is not withdrawn by a tool:
        # their saved reels name it. It is flagged for a person to
        # decide on, and a new voice like it doesn't get in.
        if r['id'] in SHIPPED_BEFORE:
            res['warnings'] = [why]
        else:
            prob.append(why)
    return res


def _survey_one(rd):
    r = dict(id=f'read{rd["id"]}', name=rd['name'], ar=rd['name'],
             kind='surah', base=rd['folder_url'].rstrip('/'),
             timing=('mp3quran', rd['id']))
    try:
        res = check_surah_voice(r, model_ms(), print)
    except Exception as e:  # noqa: BLE001
        res = dict(problems=[f'error: {e}'])
    res.update(name=rd['name'], rewaya=rd['rewaya'], read=rd['id'],
               base=r['base'])
    return res


def survey(model):
    """Every complete Hafs set mp3quran publishes timings for, whether
    the app has it or not — for deciding what to add next."""
    from concurrent.futures import ProcessPoolExecutor
    reads = cached_json(f'{TIMING_API}/reads', 'reads.json')
    reads = [rd for rd in reads
             if 'حفص' in rd['rewaya'] or 'المجود' in rd['rewaya']]
    rows = []
    # Two at a time: this box is shared, and each worker decodes audio.
    with ProcessPoolExecutor(2) as ex:
        for res in ex.map(_survey_one, reads):
            rows.append(res)
            ok = 'PASS' if not res['problems'] else 'FAIL'
            print(f"{ok} read={res['read']:>5} {res['name']}  "
                  f"{res.get('kbps', '?')}k/{res.get('rate', '?')} "
                  f"pace={res.get('pace', '?')} "
                  f"aligned={res.get('aligned_share', '?')} "
                  f"shifted={res.get('shifted_share', '?')} "
                  f"basmala1={res.get('basmala_in_verse1', '?')} "
                  f"missed={res.get('missed', [])[:6]}"
                  + ('' if ok == 'PASS' else f"  {res['problems'][:2]}"),
                  flush=True)
    path = os.path.join(CACHE, 'survey.json')
    json.dump(rows, open(path, 'w', encoding='utf8'), ensure_ascii=False,
              indent=1)
    print(f'-> {path}')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--only', action='append', default=[])
    ap.add_argument('--full', action='store_true',
                    help='check all 6236 files of every per-ayah voice')
    ap.add_argument('--survey', action='store_true')
    args = ap.parse_args()
    os.makedirs(CACHE, exist_ok=True)
    model = model_ms()
    if args.survey:
        return survey(model)

    old = json.load(open(OUT)) if os.path.exists(OUT) else {}
    reciters = app_reciters()
    ids = {r['id'] for r in reciters}
    todo = [r for r in reciters if not args.only or r['id'] in args.only]
    for r in todo:
        r['full'] = args.full or r['id'] not in SHIPPED_BEFORE
    failed = []

    def report(r, res):
        old[r['id']] = res
        ok = not res['problems']
        if not ok:
            failed.append(r['id'])
        print(f"{'PASS' if ok else 'FAIL'} {r['id']:<22} "
              f"{r['name']:<32} {res.get('kbps', '?')}k "
              f"pace={res.get('pace', '?')} "
              f"aligned={res.get('aligned_share', '-')} "
              f"shifted={res.get('shifted_share', '-')}"
              + ('' if ok else f"  {res['problems'][:3]}"), flush=True)

    # Surah-file voices two at a time: this box is shared, and each one
    # decodes audio (see the machine rules in ~/.claude/CLAUDE.md).
    # Per-ayah voices one at a time, in between: EveryAyah turns away a
    # client that asks for too much at once.
    from concurrent.futures import ProcessPoolExecutor
    surah = [r for r in todo if r['kind'] == 'surah']
    with ProcessPoolExecutor(2) as ex:
        pending = ex.map(check_one, surah)
        for r in todo:
            if r['kind'] == 'ayah':
                report(r, check_one(r))
        for r, res in zip(surah, pending):
            report(r, res)
    # Entries for voices no longer in the app are dropped.
    old = {k: v for k, v in sorted(old.items()) if k in ids}
    json.dump(old, open(OUT, 'w', encoding='utf8'), ensure_ascii=False,
              indent=1, sort_keys=True)
    print(f'{len(todo) - len(failed)}/{len(todo)} passed -> {OUT}')
    sys.exit(1 if failed else 0)


def check_one(r):
    model = model_ms()
    try:
        if r['kind'] == 'surah':
            res = check_surah_voice(r, model, print)
        else:
            res = check_ayah_voice(r, model, r['full'], print)
    except Exception as e:  # noqa: BLE001
        res = dict(kind=r['kind'], base=r['base'], source=source_key(r),
                   problems=[str(e)])
    res['name'] = r['name']
    res['checked'] = time.strftime('%Y-%m-%d')
    return res


if __name__ == '__main__':
    main()
