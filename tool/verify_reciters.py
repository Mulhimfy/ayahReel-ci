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
     by arithmetic), are long enough for their own table, and come
     from where the rest come from: a surah the host redirects to
     another of the reciter's recordings is another performance.
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

A table of our own (OwnTiming, made from the recording by
tool/verse_table.py, for a recording whose host publishes no table that
fits) is checked by 4-8 as a published one is. Since 2026-10-24 it is
not in the app, which keeps its digest (lib/data/verse_tables.dart) and
fetches it: it is read from $OWN_TABLES, the private ayahreel-words
repository's data/own_tables.json. Its source in reciters_verified.json names its
content's sha256, so a table made again is verified again. --check
verifies one before it is in the app (from $VERSE_TABLES_DIR).

Another recording of a voice (Reciter.recordingOf) is checked as all of
the above, as a voice of its own, and then:

  9. Another performance.  It is there so that reels of the same verses
     need not all carry the same sound, and a copy of the same
     performance from another host — re-encoded, cut another way, timed
     by another table — would carry it anyway. So it is compared with
     every other recording of its voice, on verse 2 of every surah both
     have (a surah one host filled from the other recording shows there)
     and SPREAD verses more across the mushaf, 162 in all, each verse cut
     out exactly as the app plays it in a reel of that verse alone:

       - waveforms: each CHUNK_MS stretch of one recording's verse is
         looked for anywhere in the other's (normalised correlation at
         8 kHz, the measure verify_word_timing.py finds our audio inside
         QUL's with). A verse found at STRONG_PEAK or better is the same
         audio, however it was encoded or cut; one at SAME_PEAK or better
         is in doubt.
       - verse lengths: each verse's sound, from where it first rises over
         the breath level to where it last falls under it. The same
         performance keeps its verses' lengths to a few tens of
         milliseconds — and a host that re-timed it would keep their
         ratio — where two performances don't (dur_close: the share
         within 2%, or 60 ms, of the median ratio).
       - loudness contours, their starts laid together (env_corr).

     A pair passes when no verse is the same audio, no more than
     MAX_DOUBT_SHARE of them are in doubt, the median verse is found
     under MAX_WAVE_MEDIAN, no more than MAX_DUR_CLOSE keep the other's
     length, the contours correlate under MAX_ENV_CORR, and nearly every
     verse could be compared. When in doubt it is left out — a
     "different" recording that is really the same one defeats the
     purpose. The metrics and the verdict go into the
     entry's `distinct`, by the other recording's id and with its source;
     test/reciter_sources_test.dart fails an alternate without a passing
     record against each of its voice's other recordings as they are now.

     How this was calibrated (2026-10-22, --calibrate, all 162 verses):
     the same recording from two hosts or cut two ways — EveryAyah's 64
     and 128/192 kbps Husary and Abdul Basit, Ghamdi and Salimi on
     mp3quran and on Tarteel, AbdulKareem and Abbad on EveryAyah and on
     quranicaudio — is found in 160-162 verses, the median verse at
     0.96-1.00, its verse lengths within 2% in 60-99% of verses, its
     contours at 0.96-1.00; a copy with a few surahs from another take
     (QUL's Tunaiji, Husary mujawwad and Dussary) in 155-160. Two
     performances by one reciter (murattal against mujawwad for Husary,
     Abdul Basit, Minshawi, Mustafa Ismail and Al-Muaiqly; Al-Muaiqly
     against QUL 65 and 159) and two reciters: in no verse, the median
     at 0.11-0.17 and the best stretch of all at 0.42-0.65, lengths
     close in 4-17%, contours at 0.02-0.16. What the waveforms alone
     would miss is the same performance altered — resampled or played at
     another speed, as old radio transfers are: mp3quran's Ayyub (read
     109) is found in 15 verses with 46 more in doubt, quranicaudio's
     Mustafa Ismail (QUL 88) in none, 5 in doubt, its median at 0.24 —
     but their verse lengths keep the voice's in 61-74% of verses and
     their contours correlate at 0.86-0.91, where a performance of its
     own, even by a reciter as even as Al-Matrood, keeps 50% and 0.19.

     What was looked at (2026-10-22), for every voice the app has: each
     mp3quran Hafs set with a table, each QUL surah recitation with
     verse windows (QUL lists 119; 1-420 were tried), EveryAyah's and
     KSU's folders, and the per-ayah sets on Tarteel's CDN and
     quran.com's. Nearly all are the voice's own recording again. Taken:
     QUL 95, Alafasy's Taraweeh of 1430 (alafasy_2); and (2026-10-23)
     mp3quran 60, Basfar's mushaf of 2007 (basfar_2), without Al-Baqarah,
     whose table gives 2:149 no length, and mp3quran 107, Mohammed
     Al-Luhaidan's recording of 2019 (a voice of his own, luhaidan), which
     has no table anywhere: the app carries one made from the recording
     (OwnTiming; tool/verse_table.py has how it is made and measured).
     Left out besides:
     mp3quran 54 (Sudais), 62 (Al-Juhani), 115
     (AbdulKareem), 123 (Alafasy) and 259 (Al-Nufais), and QUL 160
     (Balilah) and 173 (Alafasy, "streaming"), which share some surahs
     with the voice's own; mp3quran 109 (Ayyub) and QUL 88 (Mustafa
     Ismail), the voice's own altered; QUL 159 (Al-Muaiqly 1440), which
     is muaiqly_mujawwad's, and KSU's husary_qasr, which is QUL 122's.
     Another performance, but not a voice: mp3quran 43 (Al-Budair 1443:
     a breath at 79% of verse starts with mp3quran's table and at 80%
     with one made from the recording — a reverberant recording whose
     breaths stay above the quiet level wherever a slice reaches a
     surah's start or end, and which repeats verses across their
     boundaries, so no table of one window a verse fits it everywhere),
     59 (Al-Matrood: 16 kHz); QUL 65 (Al-Muaiqly: the basmala in verse 1
     in 13 surahs; quranicaudio's maher_256, which the claim probe found
     claimed on every verse it tried), 122 (Al-Husary's radio
     recitation: its tables overrun its files in 62 surahs) and 163
     (Basfar: tables that don't fit); KSU's husary_qasr (64 verse files
     missing). Teaching sets (Al-Husary's and Al-Minshawi's muallim,
     Al-Tunaiji's), sets with children or a translation, and anything
     under 64 kbps were not taken.

     Sets with no table that fits, screened (2026-10-23, verse_table.py
     screen) for a table of the app's own. Another performance, tables
     not made yet: mp3quran 320 (Ayyub's "featured recitation"), QUL
     122's files (quranicaudio's al-husaree_iza3a), quranicaudio's
     muhammad_alhaidan (Al-Luhaidan, without 2, 6 and 112), and mp3quran
     10924 (Al-Minshawi, 1387 AH), five of whose surahs are redirects to
     his r1 (5. above), one more than a voice may lack. The voice's own
     again: mp3quran 111 (Jibreel), and, altered, 102 (Al-Muaiqly r1,
     its median stretch at 0.37) and 74 (Al-Hudhaify 2020, 0.40).
     Partial: quranicaudio's Al-Muaiqly 1422-1423 and 1424-1425.

 10. Files from elsewhere.  A surah-file voice may take a few surahs from
     another host than its base (SurahFiles.elsewhere): a surah the base
     lacks, has only at a variable bitrate (5.), or has with more than
     the surah in it. Each such file is checked as the rest are, but not
     held to being served from where they are (5.), and has to be the
     reciter's: where the base has the surah too, the same take —
     ELSEWHERE_CHUNKS stretches of the base's file each found in it at
     STRONG_PEAK or better (9.'s measure of the same audio); where the
     base hasn't, his voice, as tool/verse_table.py speaker hears it,
     recorded in SPEAKER_CHECKED. Its source names the files by their
     digest (elsewhere_digest), so a file moved is verified again.

     Islam Sobhi (sobhi, 2026-10-26): mp3quran 253, his one complete
     recording, has 109 surahs and no table; 29 of them only at a variable
     bitrate, and its Al-Qamar holds a second take after the first.
     archive.org's 002_20221103_202211 has those takes at a constant
     bitrate behind a 10-26 s intro, each found in mp3quran's file at a
     median 0.95-0.99, and Way2Quran has Al-Jinn's (from tvQuran, 0.99).
     mp3quran sends the five it lacks to Al-Minshawi's r1. Of what other
     hosts offer under his name for them, Way2Quran's As-Saffat,
     Az-Zumar, Ghafir and Al-Jathiya are another reciter's (0.30-0.54
     against his files), as are the same four in archive.org's
     002_20261005_202610 (24 kbps m4a besides): Ahmed Khedr's, by those
     files' own tags; At-Talaq can't be told (0.64-0.75 against his files,
     at 128 and 320 kbps; 0.48-0.64 against his At-Tawbah on Way2Quran);
     archive.org's Ghafir and Al-Jathiya at 160 kbps, from his own
     YouTube channel, are his (SPEAKER_CHECKED). So he lacks 37, 39 and 65.

Results go to tool/reciters_verified.json; test/reciter_sources_test.dart
refuses a build where a reciter in the app has no passing entry there,
or where the entry was made for a different source.

Run:  python3 tool/verify_reciters.py            # every reciter in the app
      python3 tool/verify_reciters.py --only ID  # one (repeatable)
      python3 tool/verify_reciters.py --survey   # every mp3quran Hafs set
                                                 # with timings, app or not
      python3 tool/verify_reciters.py --compare A B  # two recordings, each
                                     # an id or a source as source_key
                                     # writes it ("ayah <base>", ...)
      python3 tool/verify_reciters.py --calibrate    # 9.'s calibration

9. needs numpy (apt: python3-numpy); the rest needs only python3 and
ffmpeg. On a machine that can't reach the audio hosts, run it on CI:
.github/workflows/voices.yml.
"""
import argparse
import array
import hashlib
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


# 10.: the files from elsewhere that no file of the voice's base can be
# found in (the base hasn't the surah), taken as the reciter's because
# tool/verse_table.py speaker heard his voice in each: {voice: {surahs,
# how}}.
SPEAKER_CHECKED = {
    'sobhi': dict(surahs=[40, 45], how=(
        'tool/verse_table.py speaker, ayahreel-words-ci tables runs '
        '40314478734 and 40349035948 (2026-10-26). Ghafir: 0.742 against '
        'his own files (they come to 0.75-0.93 of one another, eight other '
        "reciters to 0.27-0.64), 0.757 against Way2Quran's At-Tawbah of "
        "his (his files 0.49-0.76 there, the others' 0.23-0.59). "
        'Al-Jathiya: 0.865 against his own files (0.75-0.93; ten others, '
        "Ahmed Khedr's two among them, to 0.27-0.64), 0.812 against the "
        'Ghafir of the same uploader (his files 0.55-0.73 there, the '
        "others' 0.17-0.56)")),
}


MIN_KBPS = 64
MIN_RATE = 22050

# The voices that shipped before this tool existed: all EveryAyah, all
# in users' hands for months. They are sampled (see 1. above) unless
# --full asks for every file; everything added since is checked whole.
SHIPPED_BEFORE = {
    'alafasy', 'husary', 'abdulbasit', 'minshawi', 'sudais', 'shuraym',
    'muaiqly', 'hudhaify', 'dussary', 'shatri', 'ayyub', 'ajmi', 'qatami',
    'qasim', 'budair', 'rifai', 'tablawi', 'jibreel', 'basfar',
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
        # Another recording of the voice with this id (Reciter.recordingOf).
        of = re.search(r"recordingOf: '([^']+)'", block)
        of = of.group(1) if of else None
        m = re.search(r"source: AyahFiles\.(everyAyah|tarteel|ksu)\("
                      r"\s*'([^']+)',?\s*\)", block)
        if m:
            host = AYAH_HOSTS[m.group(1)]
            out.append(dict(id=rid, name=name, ar=ar, kind='ayah',
                            base=f'{host}/{m.group(2)}', of=of,
                            bundled='audioAsset:' in block))
            continue
        m = re.search(r"source: SurahFiles\(\s*'([^']+)',", block)
        assert m, f'{rid}: no source this tool understands'
        rest = block[m.end():]
        t = re.search(r"timing: (Mp3QuranTiming|QulTiming|OwnTiming)\("
                      r"'?([a-z0-9_]+)'?\)", rest)
        assert t, f'{rid}: no timing this tool understands'
        kind = {'Mp3QuranTiming': 'mp3quran', 'QulTiming': 'qul',
                'OwnTiming': 'own'}[t.group(1)]
        o = re.search(r'openingMs: (\d+)', rest)
        gone = re.search(r'missing: \{([\d,\s]*)\}', rest)
        out.append(dict(id=rid, name=name, ar=ar, kind='surah',
                        base=m.group(1), of=of,
                        padded='padded: false' not in rest,
                        opening=int(o.group(1)) if o else None,
                        missing=sorted(int(x) for x in re.findall(
                            r'\d+', gone.group(1))) if gone else [],
                        elsewhere=elsewhere_of(rest),
                        timing=(kind, t.group(2) if kind == 'own'
                                else int(t.group(2)))))
    return out


def elsewhere_of(block):
    """A SurahFiles' `elsewhere` map, {surah: url}, from its Dart."""
    m = re.search(r'elsewhere: \{(.*?)\n\s*\}', block, re.S)
    return {int(k): u for k, u in re.findall(r"(\d+): '([^']+)'",
                                              m.group(1))} if m else {}


def elsewhere_digest(el):
    """What source_key names a voice's `elsewhere` by: the start of the
    sha256 of its lines, `<surah> <url>`, in surah order."""
    text = ''.join(f'{k} {el[k]}\n' for k in sorted(el))
    return hashlib.sha256(text.encode()).hexdigest()[:12]


def source_key(r):
    """How a voice's source is written in reciters_verified.json, and
    so what test/reciter_sources_test.dart compares the app against."""
    if r['kind'] == 'ayah':
        return f"ayah {r['base']}"
    kind, key = r['timing']
    if kind == 'own':
        # A table the app carries is named by its content too: one made
        # again is another table, and has to be verified again.
        key = f'{key} {own_table(key)[1]}'
    return (f"surah {r['base']} {'SSS' if r.get('padded', True) else 'S'} "
            f"{kind} {key}"
            + (f" opening {r['opening']}" if r.get('opening') else '')
            + (f" missing {','.join(map(str, r['missing']))}"
               if r.get('missing') else '')
            + (f" elsewhere {elsewhere_digest(r['elsewhere'])}"
               if r.get('elsewhere') else ''))


def recording(text, reciters):
    """A recording named on the command line: a voice's id, or a source
    written the way source_key writes one — `ayah <base>`, or `surah
    <base> SSS|S mp3quran|qul <key> [opening <ms>] [missing <a,b>]` — so
    a set the app doesn't have can be compared before it is added."""
    for r in reciters:
        if r['id'] == text:
            return r
    p = text.split()
    if p and p[0] == 'ayah' and len(p) == 2:
        return dict(id=text, name=text, ar='', kind='ayah',
                    base=p[1].rstrip('/'))
    if p and p[0] == 'surah' and len(p) >= 5 and p[2] in ('SSS', 'S') and \
            p[3] in ('mp3quran', 'qul', 'own'):
        rest = p[5:]
        if p[3] == 'own' and rest and re.fullmatch(r'[0-9a-f]{12}', rest[0]):
            rest = rest[1:]  # the table's digest, which is worked out
        opening = int(rest[rest.index('opening') + 1]) \
            if 'opening' in rest else None
        missing = [int(x) for x in rest[rest.index('missing') + 1].split(',')] \
            if 'missing' in rest else []
        # A voice's files from elsewhere: a JSON file of {surah: url}
        # (the digest source_key writes can't be read back).
        el = {}
        if 'elsewhere' in rest:
            path = rest[rest.index('elsewhere') + 1]
            if not os.path.exists(path):
                raise SystemExit(f'elsewhere: no file {path!r}')
            el = {int(k): v for k, v in
                  json.load(open(path, encoding='utf8')).items()}
        return dict(id=text, name=text, ar='', kind='surah',
                    base=p[1].rstrip('/'), padded=p[2] == 'SSS',
                    timing=(p[3], p[4] if p[3] == 'own' else int(p[4])),
                    opening=opening, missing=missing, elsewhere=el)
    raise SystemExit(f'not a voice or a source: {text!r}')


# ---- HTTP ------------------------------------------------------------

def _get(url, headers=None, tries=4, timeout=40):
    last = None
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers={**UA, **(headers or {})})
            with urllib.request.urlopen(req, timeout=timeout) as r:
                hdr = {k.lower(): v for k, v in r.headers.items()}
                # Where the bytes really came from, after any redirect.
                hdr['x-final-url'] = r.geturl()
                return r.status, hdr, r.read()
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
    # A file name holds 255 bytes: a long address (archive.org's, in the
    # title's own words) is named by its start and its digest.
    if len(key) > 150:
        key = key[:100] + '_' + hashlib.sha256(url.encode()).hexdigest()[:16]
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
    final = hdr.get('x-final-url') or url
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
                spf=spf, avg=avg, vbr=vbr, info=info, ver=ver, final=final,
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


_OWN = {}


def own_table(key):
    """({surah: [(start, end)]}, digest) of a table of our own ($OWN_TABLES,
    made by tool/verse_table.py), or of one in $VERSE_TABLES_DIR/<key>/ —
    a table just made, not yet served."""
    if key not in _OWN:
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import verse_table as VT  # noqa: PLC0415
        d = os.path.join(os.environ.get('VERSE_TABLES_DIR', '/nonexistent'),
                         key)
        if os.path.isdir(d):
            tables = VT.read_dir(d)
            _OWN[key] = (tables, VT.digest(VT.encode(tables)))
        else:
            text = VT.own_tables().get(key)
            assert text, (f'no table {key}: set OWN_TABLES to the private '
                          "ayahreel-words repository's data/own_tables.json")
            _OWN[key] = (VT.decode(text), VT.digest(text))
    return _OWN[key]


def surah_table(timing, s):
    """The published table for surah [s] as rows of {ayah, start_time,
    end_time}, verse 0 (a separate isti'adha and basmala) left out, or
    whatever came back when it isn't a table at all."""
    kind, key = timing
    count = COUNTS[s - 1]
    if kind == 'own':
        rows = own_table(key)[0].get(s)
        if rows is None:
            return 'no table for this surah'
        return [dict(ayah=a, start_time=st, end_time=en)
                for a, (st, en) in enumerate(rows, 1)]
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


def timing_tag(r):
    """A surah-file voice's table, as the cache names what was measured
    against it."""
    kind, key = r['timing']
    return f'{kind}{key}' + (own_table(key)[1] if kind == 'own' else '')


def surah_url(r, s):
    return (r.get('elsewhere') or {}).get(s) or base_url(r, s)


def base_url(r, s):
    """Surah [s]'s file at the voice's base, elsewhere or not."""
    return f"{r['base'].rstrip('/')}/" + (
        f'{s:03d}' if r.get('padded', True) else f'{s}') + '.mp3'


# ---- the checks ------------------------------------------------------

def check_surah_voice(r, model, log):
    base = r['base'].rstrip('/')
    tag = timing_tag(r)
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
    # A host may redirect a surah it lacks to another recording of the
    # reciter (mp3quran's Minshawi of 1387 AH sends five to his r1): the
    # bytes then belong to another performance than the rest. Moving the
    # whole set to a new address is fine; one surah from elsewhere isn't.
    def served(s_):
        return os.path.dirname(lays[s_].get('final') or surah_url(r, s_))
    # Files the voice names as elsewhere are checked to be his by 10.
    el = r.get('elsewhere') or {}
    homes = {}
    for s, L in lays.items():
        if L.get('ok') and s not in el:
            homes.setdefault(served(s), []).append(s)
    home = max(homes, key=lambda k: len(homes[k])) if homes else None
    for s, L in sorted(lays.items()):
        if not L['ok']:
            broken[s] = f'file {s}: {L["why"]}'
            continue
        if home is not None and served(s) != home and s not in el:
            broken[s] = f'file {s}: served from {L.get("final")}'
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
    # 10. Files from elsewhere.
    if el:
        res['elsewhere'] = {}
        for s in sorted(el):
            if s in missing or s in broken:
                continue
            v = res['elsewhere'][s] = elsewhere_check(r, s)
            if not v['ok']:
                broken[s] = f"file {s}: {v['why']}"
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


ELSEWHERE_BYTES = 3_000_000  # minutes of a file, whatever its bitrate
ELSEWHERE_CHUNKS = 8         # stretches of the base's file looked for


def elsewhere_check(r, s):
    """10. A file from elsewhere is the reciter's. Where the voice's base
    has the surah too (a file that can't be sliced, or holds more than the
    surah), it is the same take: CHUNK_MS stretches of the base's file,
    spread over its first minutes of sound, are each found in the other at
    STRONG_PEAK or better (9.'s measure of the same audio, however encoded
    or cut). Where the base hasn't, nothing of his can be found in it, and
    it is taken only as SPEAKER_CHECKED records: tool/verse_table.py
    speaker heard his voice in it."""
    np = _np()
    out = dict(url=surah_url(r, s))
    st, hdr, b = _get(base_url(r, s), headers={
        'Range': f'bytes=0-{ELSEWHERE_BYTES - 1}'}, timeout=180)
    # A host may send a surah it lacks to another reciter's file
    # (mp3quran sends Islam Sobhi's missing ones to Al-Minshawi's r1):
    # the base hasn't it then either.
    moved = os.path.dirname(hdr.get('x-final-url') or base_url(r, s)) != \
        os.path.dirname(base_url(r, s))
    if st not in (200, 206) or not b or moved:
        # A source checked by --check before the voice is in the app has
        # its source for an id; a table of our own is named for the voice.
        own = r.get('timing') and r['timing'][0] == 'own'
        heard = SPEAKER_CHECKED.get(r['id']) or \
            (SPEAKER_CHECKED.get(r['timing'][1]) if own else None) or {}
        lack = f"sent to {hdr.get('x-final-url')}" if moved else f'HTTP {st}'
        if s in heard.get('surahs', ()):
            return dict(out, ok=True, base=lack, speaker=heard['how'])
        return dict(out, ok=False, base=lack,
                    why='from elsewhere, and no file of his to find it in: '
                        'run tool/verse_table.py speaker (SPEAKER_CHECKED)')
    st2, _, b2 = _get(out['url'], headers={
        'Range': f'bytes=0-{ELSEWHERE_BYTES - 1}'}, timeout=180)
    if st2 not in (200, 206) or not b2:
        return dict(out, ok=False, why=f'HTTP {st2}')
    try:
        xa, xb = decode_pcm(b), decode_pcm(b2)
    except subprocess.CalledProcessError as e:
        return dict(out, ok=False, why='not decodable as mp3: ' + (
            e.stderr or b'').decode('utf8', 'replace').strip()[:160])
    sr = XRATE // 1000
    snd = sound(env_of(xa), (0, len(xa) // sr))
    if not snd:
        return dict(out, ok=False, why='no sound in the base file')
    lo, hi = snd[0] + 3000, min(snd[1], snd[0] + 150_000) - CHUNK_MS
    found = []
    for i in range(ELSEWHERE_CHUNKS):
        c0 = lo + (hi - lo) * i // max(1, ELSEWHERE_CHUNKS - 1)
        x = xa[c0 * sr:(c0 + CHUNK_MS) * sr]
        rms = float(np.sqrt(np.mean(x.astype(np.float64) ** 2))) \
            if len(x) else 0.0
        if rms < 30:
            continue
        c = ncc(x, xb)
        if c is not None and len(c):
            found.append(round(float(np.abs(c).max()), 3))
    med = float(np.median(found)) if found else 0.0
    same = len(found) >= 3 and med >= STRONG_PEAK
    return dict(out, ok=same, base='same take' if same else 'another take',
                found=found, median=round(med, 3),
                **({} if same else {'why': f'not the take at the base '
                                           f'(median {med:.2f})'}))


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
    tag = timing_tag(r)
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


# ---- another recording (see 9. in the docstring) ---------------------

XRATE = 8000      # what two recordings' waveforms are compared at
SPREAD = 48       # verses spread over the mushaf, besides every verse 2
CHUNK_MS = 1500   # a stretch of one recording looked for in the other
SAME_PEAK = 0.6   # a stretch found this well may be the same audio
STRONG_PEAK = 0.8  # and one found this well is
# The verdict on a pair, calibrated (see 9.).
MAX_DOUBT_SHARE = 0.05   # verses whose best stretch is SAME_PEAK or more
MAX_WAVE_MEDIAN = 0.25   # the median verse's best stretch
MAX_DUR_CLOSE = 0.6      # verses as long as the other's, give or take 2%
MAX_ENV_CORR = 0.5       # median loudness-contour correlation


def _np():
    import numpy as np  # noqa: PLC0415 - only the comparison needs it
    return np


def decode_pcm(mp3_bytes):
    """[mp3_bytes] decoded mono at XRATE, as 16-bit samples."""
    np = _np()
    p = subprocess.run(
        ['ffmpeg', '-v', 'error', '-f', 'mp3', '-i', '-', '-ac', '1',
         '-ar', str(XRATE), '-f', 's16le', '-'],
        input=mp3_bytes, capture_output=True, check=True)
    return np.frombuffer(p.stdout[:len(p.stdout) // 2 * 2], dtype='<i2')


def env_of(pcm):
    """smooth(envelope()) of the same audio, from its samples: the 100 ms
    loudness in 10 ms frames, in dB."""
    np = _np()
    n = XRATE // 100
    m = len(pcm) // n
    x = pcm[:m * n].astype(np.float64).reshape(m, n)
    c = np.concatenate([[0.0], np.cumsum((x * x).mean(axis=1) + 1)])
    i = np.arange(m)
    lo, hi = np.maximum(0, i - 5), np.minimum(m, i + 6)
    return 10 * np.log10((c[hi] - c[lo]) / (hi - lo))


def snap(env, at_ms, before, after):
    """SurahSlice.snap: the quietest 10 ms of [env] from [before] ms
    before [at_ms] to [after] ms after it, the nearer of two equals."""
    i = int(math.floor(abs(at_ms) / 10 + 0.5)) * (1 if at_ms >= 0 else -1)
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


def table_rows(r, s):
    """Surah [s]'s table as the app keeps it (SurahSlice.parseTable, then
    withFileEnd): [(start, end)] by verse."""
    t = surah_table(r['timing'], s)
    if not isinstance(t, list) or len(t) != COUNTS[s - 1]:
        raise RuntimeError(f'table {s} unusable')
    rows = [(int(x['start_time']), int(x['end_time'])) for x in t]
    if rows[-1][1] <= rows[-1][0]:
        rows[-1] = (rows[-1][0], int(layout(surah_url(r, s))['audio_ms']))
    return rows


def clip(r, s, a):
    """Verse s:a of recording [r] as the app plays it in a reel of that
    verse alone — the verse's file, or its slice of the surah's file cut
    the way SurahSlice.plan cuts it — as (samples at XRATE, envelope,
    the verse's window in them in ms). Kept in the cache."""
    np = _np()
    key = re.sub(r'[^A-Za-z0-9]+', '_', source_key(r))[-120:]
    path = os.path.join(CACHE, 'clips', key, f'{s:03d}{a:03d}.npz')
    if os.path.exists(path):
        z = np.load(path)
        return z['pcm'], z['env'], (int(z['win'][0]), int(z['win'][1]))
    if r['kind'] == 'ayah':
        url = f"{r['base']}/{s:03d}{a:03d}.mp3"
        for attempt in range(4):
            status, _, b = _get(url, timeout=120)
            if status == 200 and b:
                break
            time.sleep(5 * (attempt + 1))
        else:
            raise RuntimeError(f'{url}: HTTP {status}')
        pcm = decode_pcm(b)
        env = env_of(pcm)
        win = (0, len(env) * 10)
    else:
        st, en = table_rows(r, s)[a - 1]
        url = surah_url(r, s)
        lay = layout(url)
        if not lay.get('ok'):
            raise RuntimeError(f'{url}: {lay.get("why")}')
        b, origin = fetch_slice(url, lay, st - 1500, en + 1500)
        pcm = decode_pcm(b)
        env = env_of(pcm)
        n = len(env) * 10
        a0 = snap(env, st - origin, EDGE_MS, SNAP_MS)
        a1 = min(n, max(snap(env, min(en - origin, n), SNAP_MS, EDGE_MS),
                        a0 + 150))
        win = (a0, a1)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    np.savez_compressed(path, pcm=pcm, env=env.astype(np.float32),
                        win=np.array(win))
    return pcm, env, win


def sound(env, win):
    """Where the verse's sound is in its window [win]: from the start of
    the first 50 ms above the breath level (PAUSE_REL of the way up from
    the clip's silence floor to its speech level) to the end of the last,
    in ms. None when there is none."""
    np = _np()
    floor, speech = levels([float(x) for x in env])
    thr = floor + PAUSE_REL * (speech - floor)
    lo, hi = max(0, win[0] // 10), min(len(env), win[1] // 10)
    above = np.asarray(env[lo:hi]) > thr
    if len(above) < 5:
        return None
    c = np.concatenate([[0], np.cumsum(above)])
    run = np.nonzero((c[5:] - c[:-5]) == 5)[0]
    if not len(run):
        return None
    return (lo + int(run[0])) * 10, (lo + int(run[-1]) + 5) * 10


def ncc(x, y):
    """Normalised correlation of [x] laid on every stretch of [y] as long
    as it, as verify_word_timing.ncc measures it."""
    np = _np()
    m, n = len(x), len(y)
    if m < 80 or n < m:
        return None
    x = x.astype(np.float64)
    x = x - x.mean()
    y = y.astype(np.float64)
    size = 1 << int(math.ceil(math.log2(n + m)))
    c = np.fft.irfft(np.fft.rfft(x[::-1], size) * np.fft.rfft(y, size),
                     size)[m - 1:n]
    cs = np.concatenate([[0.0], np.cumsum(y * y)])
    e = cs[m:] - cs[:n - m + 1]
    xx = float(np.dot(x, x))
    # Digital silence matches nothing: its energy would only blow up the
    # transform's rounding noise.
    return np.where(e > 1e-4 * xx, c / np.sqrt(np.maximum(e * xx, 1e-6)),
                    0.0)


def wave_match(xa, xb):
    """How well a verse's sound [xa] is found in [xb], the other
    recording's clip of the same verse: for each CHUNK_MS stretch of it
    (up to six, from its start to its end) the best |correlation| of the
    waveforms anywhere in [xb]. Stretches of near-silence (a pause inside
    the verse) are left out: there is nothing in them to find."""
    np = _np()
    sr = XRATE // 1000
    dur = len(xa) // sr
    if dur <= CHUNK_MS + 500:
        spots, span = [0], dur
    else:
        span = CHUNK_MS
        k = int(min(6, max(2, dur // CHUNK_MS)))
        spots = [round(i * (dur - span) / (k - 1)) for i in range(k)]
    level = float(np.sqrt(np.mean(xa.astype(np.float64) ** 2))) \
        if len(xa) else 0.0
    out = []
    for c0 in spots:
        x = xa[c0 * sr:(c0 + span) * sr]
        rms = float(np.sqrt(np.mean(x.astype(np.float64) ** 2))) \
            if len(x) else 0.0
        if rms < 30 or rms < level / 10:
            continue
        r = ncc(x, xb)
        if r is not None and len(r):
            out.append(float(np.abs(r).max()))
    return out


def env_corr(ea, sa, eb, sb):
    """Correlation of two verses' loudness contours, their sounds' starts
    laid together, over the shorter of the two."""
    np = _np()
    a = np.asarray(ea[sa[0] // 10:sa[1] // 10], dtype=np.float64)
    b = np.asarray(eb[sb[0] // 10:sb[1] // 10], dtype=np.float64)
    n = min(len(a), len(b))
    if n < 30 or a[:n].std() == 0 or b[:n].std() == 0:
        return None
    return float(np.corrcoef(a[:n], b[:n])[0, 1])


def distinct_sample(missing, model):
    """The verses a pair is compared on: verse 2 of every surah both have
    (a surah one host filled from the other recording shows there), and
    SPREAD more spread over the mushaf, each 3 to 20 s as the model has
    it. No verse 1: hosts differ over whether its file holds the
    basmala."""
    live = [s for s in range(1, 115) if s not in missing]
    every = [(s, 2) for s in live]
    keys = [(s, a) for s in live for a in range(3, COUNTS[s - 1] + 1)
            if 3000 <= model[(s, a)] <= 20000]
    step = len(keys) / SPREAD
    return every + [keys[int(i * step)] for i in range(SPREAD)]


def compare(ra, rb, model, sample=None):
    """Whether [ra] and [rb] are two performances, or one performance
    twice (see 9.): the metrics, and the verdict as `ok`. [sample]
    replaces distinct_sample's verses, for a first look."""
    missing = set(ra.get('missing') or []) | set(rb.get('missing') or [])
    sample = sample or distinct_sample(missing, model)

    def clips(s_a):
        s, a = s_a
        try:
            return s_a, clip(ra, s, a), clip(rb, s, a), None
        except Exception as e:  # noqa: BLE001 - one verse, recorded
            return s_a, None, None, str(e)[:100]
    rows, failed = [], []
    sr = XRATE // 1000
    with ThreadPoolExecutor(4) as ex:
        for (s, a), ca, cb, err in ex.map(clips, sample):
            if err:
                failed.append(f'{s}:{a} {err}')
                continue
            (pa, ea, wa), (pb, eb, wb) = ca, cb
            sa, sb = sound(ea, wa), sound(eb, wb)
            if not sa or not sb:
                failed.append(f'{s}:{a} no sound')
                continue
            found = wave_match(pa[sa[0] * sr:sa[1] * sr], pb)
            rows.append(dict(key=f'{s}:{a}', da=sa[1] - sa[0],
                             db=sb[1] - sb[0], best=max(found, default=0.0),
                             env=env_corr(ea, sa, eb, sb)))
    n = len(rows)
    res = dict(verses=n, surahs=len({x['key'].split(':')[0] for x in rows}),
               failed=len(failed))
    if failed:
        res['failed_e_g'] = failed[:5]
    if not n:
        res.update(ok=False, why='no verse could be compared')
        return res
    best = sorted(x['best'] for x in rows)
    res['wave_median'] = round(best[n // 2], 3)
    res['wave_p90'] = round(best[min(n - 1, int(n * 0.9))], 3)
    res['wave_max'] = round(best[-1], 3)
    same = [x['key'] for x in rows if x['best'] >= STRONG_PEAK]
    res['wave_same'] = len(same)
    if same:
        res['wave_same_e_g'] = same[:8]
    res['wave_doubt'] = sum(SAME_PEAK <= x['best'] < STRONG_PEAK
                            for x in rows)
    q = [math.log(x['da'] / x['db']) for x in rows]
    mid = sorted(q)[n // 2]
    dev = [abs(v - mid) for v in q]
    res['dur_ratio'] = round(math.exp(mid), 3)
    res['dur_spread'] = round(sorted(dev)[n // 2], 4)
    res['dur_close'] = round(sum(
        d <= max(0.02, 60 / x['db']) for d, x in zip(dev, rows)) / n, 3)
    ec = sorted(x['env'] for x in rows if x['env'] is not None)
    res['env_corr'] = round(ec[len(ec) // 2], 3) if ec else None
    why = []
    if n < 40:
        why.append(f'only {n} verses compared')
    if same:
        why.append(f'the same audio in {len(same)} of {n} verses, '
                   f'e.g. {same[:4]}')
    if res['wave_doubt'] > MAX_DOUBT_SHARE * n:
        why.append(f'{res["wave_doubt"]} verses nearly the same audio')
    if res['wave_median'] > MAX_WAVE_MEDIAN:
        why.append(f'waveforms correlate at {res["wave_median"]} in the '
                   f'median verse')
    if res['dur_close'] > MAX_DUR_CLOSE:
        why.append(f'{res["dur_close"]:.0%} of verses as long as each other')
    if res['env_corr'] is not None and res['env_corr'] > MAX_ENV_CORR:
        why.append(f'loudness contours correlate at {res["env_corr"]}')
    if res['failed'] > max(3, 0.05 * len(sample)):
        why.append(f'{res["failed"]} verses could not be compared')
    res['ok'] = not why
    if why:
        res['why'] = '; '.join(why)
    return res


# Pairs the verdict was calibrated on (see 9.): the same recording served
# by two hosts or cut two ways, and two performances by one reciter.
CALIBRATION = [
    ('same', 'husary', 'ayah https://everyayah.com/data/Husary_64kbps'),
    ('same', 'abdulbasit',
     'ayah https://everyayah.com/data/Abdul_Basit_Murattal_64kbps'),
    ('same', 'ghamdi', 'surah https://audio-cdn.tarteel.ai/quran/surah/'
                       'ghamadi/murattal/mp3 SSS qul 13'),
    ('same', 'salimi', 'surah https://audio-cdn.tarteel.ai/quran/surah/'
                       'mansourAlSalimi/murattal/mp3 SSS qul 179'),
    ('same', 'abdulkareem', 'surah https://download.quranicaudio.com/quran/'
                            'muhammad_abdulkareem SSS qul 70'),
    ('same', 'abbad', 'surah https://download.quranicaudio.com/quran/fares '
                      'SSS qul 14'),
    # The same recording but for a few surahs, which the host filled from
    # another take (verify_word_timing.py found them).
    ('mixed', 'tunaiji', 'surah https://audio-cdn.tarteel.ai/quran/surah/'
                         'khalifaAlTunaiji/murattal/mp3 SSS qul 161'),
    ('mixed', 'husary_mujawwad', 'surah https://audio-cdn.tarteel.ai/quran/'
                                 'surah/husary/mujawwad/mp3 SSS qul 164'),
    ('mixed', 'dussary', 'surah https://audio-cdn.tarteel.ai/quran/surah/'
                         'yasserAlDosari/murattal/mp3 SSS qul 174'),
    # The same performance altered: resampled, or played at another
    # speed, so that its waveforms no longer line up with the voice's.
    ('altered', 'ayyub', 'surah https://cdn.mp3quran.net/audio/'
                         'muhammad-ayyub/r1 SSS mp3quran 109'),
    ('altered', 'mustafa_ismail', 'surah https://download.quranicaudio.com/'
                                  'quran/mostafa_ismaeel SSS qul 88'),
    # A performance of its own by a reciter whose pace hardly varies.
    ('different', 'matrood', 'surah https://cdn.mp3quran.net/audio/'
                             'abdullah-matrood/r1 SSS mp3quran 59'),
    ('different', 'husary', 'husary_mujawwad'),
    ('different', 'abdulbasit', 'abdulbasit_mujawwad'),
    ('different', 'minshawi', 'minshawi_mujawwad'),
    ('different', 'mustafa_ismail', 'mustafa_ismail_mujawwad'),
    ('different', 'muaiqly', 'muaiqly_mujawwad'),
    ('different', 'muaiqly', 'surah https://download.quranicaudio.com/quran/'
                             'maher_almu3aiqly/year1440 SSS qul 159'),
    ('different', 'muaiqly', 'surah https://audio-cdn.tarteel.ai/quran/surah/'
                             'maherAlMuaiqly/murattal/mp3 SSS qul 65'),
    ('different', 'alafasy', 'husary'),
]


def calibrate(model, pairs=None):
    """compare() over CALIBRATION, for setting and checking the verdict."""
    reciters = app_reciters()
    out = []
    for expect, a, b in pairs or CALIBRATION:
        try:
            res = compare(recording(a, reciters), recording(b, reciters),
                          model)
        except Exception as e:  # noqa: BLE001
            res = dict(ok=None, why=f'error: {e}')
        out.append(dict(expect=expect, a=a, b=b, **res))
        print(f"{expect:<9} ok={res.get('ok')!s:<5} {a[-34:]:<34} "
              f"{b[-44:]:<44} n={res.get('verses')} "
              f"wave={res.get('wave_median')}/{res.get('wave_p90')}/"
              f"{res.get('wave_max')} same={res.get('wave_same')} "
              f"doubt={res.get('wave_doubt')} "
              f"dur={res.get('dur_ratio')}±{res.get('dur_spread')} "
              f"close={res.get('dur_close')} env={res.get('env_corr')}",
              flush=True)
    path = os.path.join(CACHE, 'calibration.json')
    os.makedirs(CACHE, exist_ok=True)
    json.dump(out, open(path, 'w', encoding='utf8'), ensure_ascii=False,
              indent=1)
    print(f'-> {path}')
    return out


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
    ap.add_argument('--compare', nargs=2, metavar=('A', 'B'),
                    help='are two recordings two performances? Each a '
                         "voice's id or a source as source_key writes it")
    ap.add_argument('--calibrate', action='store_true',
                    help='--compare over the pairs the verdict was set on')
    ap.add_argument('--check', metavar='SOURCE',
                    help='checks 1-8 on a recording the app does not have, '
                         'written as source_key writes it; with '
                         '$VERSE_TABLES_DIR, an own table not yet in the '
                         'app, the surahs it has no table for left out')
    args = ap.parse_args()
    os.makedirs(CACHE, exist_ok=True)
    model = model_ms()
    if args.survey:
        return survey(model)
    if args.calibrate:
        return calibrate(model)
    if args.check:
        r = recording(args.check, app_reciters())
        if r['kind'] == 'surah' and r['timing'][0] == 'own' and \
                not r.get('missing'):
            have = own_table(r['timing'][1])[0]
            r['missing'] = [s for s in range(1, 115) if s not in have]
        res = check_surah_voice(r, model, print) if r['kind'] == 'surah' \
            else check_ayah_voice(r, model, True, print)
        print(json.dumps(res, ensure_ascii=False, indent=1))
        sys.exit(1 if res['problems'] else 0)
    if args.compare:
        all_ = app_reciters()
        res = compare(recording(args.compare[0], all_),
                      recording(args.compare[1], all_), model)
        print(json.dumps(res, ensure_ascii=False, indent=1))
        return

    old = json.load(open(OUT)) if os.path.exists(OUT) else {}
    reciters = app_reciters()
    ids = {r['id'] for r in reciters}
    todo = [r for r in reciters if not args.only or r['id'] in args.only]
    for r in todo:
        r['full'] = args.full or r['id'] not in SHIPPED_BEFORE
        # Another recording is compared with every other recording of its
        # voice: the voice's first, and its other others.
        if r.get('of'):
            r['others'] = [x for x in reciters if x['id'] != r['id'] and
                           r['of'] in (x['id'], x.get('of'))]
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
    # 9. Another performance, not the same one from somewhere else.
    if r.get('of'):
        res['recording_of'] = r['of']
        res['distinct'] = {}
        for o in r.get('others', []):
            try:
                d = compare(r, o, model)
            except Exception as e:  # noqa: BLE001
                d = dict(ok=False, why=f'error: {e}')
            d['source'] = source_key(o)
            res['distinct'][o['id']] = d
            if not d['ok']:
                res['problems'].append(f"not another performance than "
                                       f"{o['id']}: {d.get('why')}")
    res['name'] = r['name']
    res['checked'] = time.strftime('%Y-%m-%d')
    return res


if __name__ == '__main__':
    main()
