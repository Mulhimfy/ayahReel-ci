#!/usr/bin/env python3
"""Verse tables made from the audio itself, for surah-file recordings
that publish none, or none that fits.

A surah-file voice is cut by a table of where each verse starts and
ends in each surah's file (lib/data/surah_slice.dart). Most recordings
come with one (mp3quran.net, the Quranic Universal Library); some of the
recordings worth having don't — Mohammed Al-Luhaidan's only complete one
(mp3quran read 107), or other performances of the app's voices whose
tables are off by half a second in places. This makes the table from
the recording, and measures how far it can be trusted.

make  Each surah file is decoded on the app's frame clock (the bare
      MPEG frames, as SurahSlice.fetch cuts them), run through the Quran
      acoustic model of Mulhimfy/ayahreel-words (wav2vec2 XLSR-53 fine-
      tuned on recitation, Apache-2.0, int8 on CPU), and aligned whole
      against the surah's text in one Viterbi search (that repository's
      pipeline/longform.py): the isti'adha and the basmala optional before
      verse 1, sound that is no word of the text allowed between verses,
      repeated words followed. No published table guides it. The search
      is confined to a band of BAND_S either side of where each verse
      would be were the surah recited at an even pace (its letters, and a
      breath a verse) — published tables show that guess off by up to two
      minutes in Al-Baqarah — and a path that comes within GUARD_S of the
      band's edge is searched again in a band twice as wide, so the band
      never decides where a verse is. A verse starts at its first word's
      first frame less 40 ms (ayahreel-words' START_SHIFT: where sound
      returns after a pause) and runs on to where the next starts (the
      last verse of a surah to where its sound ends); verse_rows mends
      the two things the alignment was measured getting wrong (an early
      first letter, a restart). Every verse of every surah is kept: a
      table can't skip a verse.

      Sound before the surah's first words costs the search little
      (LEAD_COST), so that what a file opens with before the surah — a
      later verse recited as a preview, as YouTube uploads do, a jingle —
      is left out of it; and where the search still put verse 1 before
      its own words, inside such a preview or inside the basmala (whose
      letters it borrowed for a الٓمٓ the model hears nothing of), it is
      searched again from where those words are heard (verse_one).

eval  The table against where verses really start: the first word of
      every verse after the first, as the Quranic Universal Library
      times it word by word for recordings it vouches for (ayahreel-
      words' references: Al-Banna on QUL's own files, Al-Ghamdi and
      Al-Salimi on the app's mp3quran files through the offsets
      tool/verify_word_timing.py measured). A method passes at a median
      error of at most 60 ms and a 90th percentile of at most 200 ms over
      every such verse, long surahs included. Against a published table
      too, where there is one, for what it says about that table.

      Measured (2026-10-23, mirror runs 40019665180 and before; surahs 1,
      2, 3, 4, 18, 36, 55, 67, 78 and 112-114 whole, 1013 verse starts a
      voice, the band never binding: the even-pace guess was off by up to
      208 s, the band left at least 31 s):

        Al-Banna, QUL's words on QUL's own files: median 10 ms, p90 30,
          p99 105, the worst 190; none over 300 ms.
        Al-Salimi, QUL's words moved onto mp3quran's files: median 35,
          p90 102, p99 418. Of the 13 over 300 ms, 4 are restarts QUL
          times from the second start, where mp3quran's own table of the
          same file agrees with this one within 130 ms; 8 are in 112-113,
          where both references drift late of the sound's onsets; one,
          4:70, is this table's: 4 s early, the repeat of 4:69's ending
          taken for 4:70's first word.
        Al-Ghamdi, the same way: median 44, p90 140, p99 254. The 9 over
          300 ms are all in 78, where mp3quran's table of the same file
          agrees with this one within 120 ms (the reference's offset for
          that surah is off); and in Al-Baqarah the reference drifts 30
          ppm against both (detrended: median 21, p90 51, worst 128).
        Alafasy's Taraweeh of 1430, a live recording, against QUL 95's
          table (no words; its own convention taken out): median 45,
          p90 144, worst 353.

      verse_rows' two fixes fired 17 times in these four voices' tables, each
      checked against the references: before them Al-Banna had four
      verses 1.1-1.7 s early, Al-Ghamdi's 3:83 was 5 s late, Al-Salimi's
      67:26 6.4 s late, Alafasy's 55:43 8 s late. A first version of the
      early-letter rule also fired on voiceless first letters (four
      verses 0.4 s late) and on الٓمٓ (9 s late); both are excluded now.

A table that passes is still checked like any published one before a
voice ships with it: tool/verify_reciters.py, every file, breaths at
the verse starts against the same table shifted (6. there).

Run on a runner, with a checkout of Mulhimfy/ayahreel-words at --words:
Mulhimfy/ayahreel-words-ci's tables.yml, dispatched with this
repository's public mirror ref and the job sets' names, which seals
every table and log it makes with the project's key (timing work stays
private); or .github/workflows/verse-tables.yml on the mirror, which
seals the same way and won't run until the mirror has WORDS_ENC_KEY.

  python3 tool/verse_table.py make --words W --id luhaidan \\
      --base https://cdn.mp3quran.net/audio/muhammad-luhaidan/r1 \\
      --surahs 1-114 --out out
  python3 tool/verse_table.py make ... --urls '{"17": "https://..."}'
                                    # files not at --base (elsewhere)
  python3 tool/verse_table.py speaker --job job.json
                                    # his voice at all? (job sets'
                                    # "speaker" entries; torch, speechbrain)
  python3 tool/verse_table.py eval --words W --tables out/ghamdi_own \\
      --truth ghamdi --published "mp3quran 30"
  python3 tool/verse_table.py rows --words W --tables out/luhaidan
                                    # verse_rows again, no model, no audio
  OWN_TABLES=../ayahreel-words/data/own_tables.json \
  python3 tool/verse_table.py pack --write luhaidan=out/luhaidan
                                    # -> $OWN_TABLES, and its digest
                                    #    -> lib/data/verse_tables.dart
  python3 tool/verse_table.py screen --ref ayyub \
      --cand https://cdn.mp3quran.net/audio/muhammad-ayyub/r2
                                    # worth a table at all?

Job sets for the workflow, the made and the not yet made (husary_2,
ayyub_2, luhaidan_2, minshawi_2, muaiqly_2), are in
tool/verse_table_jobs.json.
"""
import argparse
import base64
import glob
import hashlib
import json
import math
import os
import re
import sys
import time
import types

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
JOBS = os.path.join(ROOT, 'tool', 'verse_table_jobs.json')
DART = os.path.join(ROOT, 'lib', 'data', 'verse_tables.dart')
# Our tables' home since 2026-10-24: the private Mulhimfy/ayahreel-words
# repository's data/own_tables.json (key -> the text `encode` writes). The
# app keeps only each one's sha256 and fetches the table from the host.
OWN = os.environ.get('OWN_TABLES', '')

BAND_S = 240.0     # see make, above
# What a frame of sound before the surah's first words costs the search,
# where sound between verses and after the last costs GARBAGE (3.0):
# little, so that what a file opens with before the surah is left out
# rather than hidden in the blanks of the opening's or verse 1's tokens.
# See verse_one.
LEAD_COST = 0.2
GUARD_S = 20.0
MAX_BAND_S = 960.0
MAX_CELLS = 7.0e9  # the search's backpointers, a byte a cell
PAUSE_LETTERS = 8  # a breath, in letters of an even pace
START_SHIFT = -40  # ms, ayahreel-words' run_voice.START_SHIFT
MODEL = 'rabah8'

# The bar a method must meet (see eval, above), and what is counted.
MAX_MEDIAN_MS = 60
MAX_P90_MS = 200

W = types.SimpleNamespace()


def load_words(path):
    """The ayahreel-words pipeline, from a checkout at [path]."""
    sys.path.insert(0, os.path.abspath(path))
    from pipeline import align, audio, ctc, longform, tables, text  # noqa
    W.align, W.audio, W.ctc, W.longform = align, audio, ctc, longform
    W.tables, W.text = tables, text


def parse_surahs(spec):
    out = []
    for part in str(spec).split(','):
        part = part.strip()
        if '-' in part:
            a, b = part.split('-')
            out += list(range(int(a), int(b) + 1))
        elif part:
            out.append(int(part))
    return out


def surah_url(base, s, padded=True):
    return f"{base.rstrip('/')}/" + (f'{s:03d}' if padded else f'{s}') + '.mp3'


# ---- make --------------------------------------------------------------

def letters(word):
    return sum(1 for c in word if W.text.is_letter(c))


def even_pace(env, surah):
    """Where each verse would be, were [surah] recited at an even pace
    from the first sound of its file to the last: (ayah -> (start, end)
    ms, the opening's (start, end) ms)."""
    q = W.audio.quiet_below(env)
    import numpy as np
    loud = np.nonzero(env > q)[0]
    if not len(loud):
        raise ValueError('no sound in the file')
    t0, t1 = int(loud[0]) * 10, (int(loud[-1]) + 1) * 10
    n = W.text.COUNTS[surah - 1]
    op = (W.text.ISTIADHA if surah in (1, 9) else
          W.text.ISTIADHA + ' ' + W.text.BASMALA).split(' ')
    w_op = sum(letters(w) for w in op) + 2 * PAUSE_LETTERS
    w = [sum(letters(x) for x in W.text.words(surah, a)) for a in
         range(1, n + 1)]
    k = (t1 - t0) / (w_op + sum(w) + PAUSE_LETTERS * n)
    opening = (t0, t0 + w_op * k)
    table, cur = {}, opening[1]
    for a, x in enumerate(w, 1):
        table[a] = (cur, cur + x * k)
        cur += (x + PAUSE_LETTERS) * k
    return table, opening


def search(model, logp, surah, guess, opening, band_s, floor_ms=None):
    """pipeline/longform.align_surah, with the band's edges watched: the
    alignment, and what the search cost and how near the path came to
    the band's edge (slack_s; None when it never could). Sound before the
    surah's first words costs LEAD_COST a frame, sound between verses and
    after the last GARBAGE. [floor_ms]: verse 1 begins no earlier."""
    import numpy as np
    L = W.longform
    fm = model.frame_ms
    total = logp.shape[0]
    verses = sorted(guess)
    tf = {a: (int(s / fm), int(max(s + 1, e) / fm)) for a, (s, e) in
          guess.items()}
    of = (int(opening[0] / fm), int(opening[1] / fm))
    c, words = L.build(model, surah, verses, tf, of, total)
    if model.delimiter is not None:
        for s, t in enumerate(c.tok):
            if t == model.delimiter:
                c.word[s] = -1
    tok, ptr, src, w, init, final = L.compile_chain(c)
    S = len(c.tok)
    exp = np.maximum.accumulate(np.asarray(c.exp, np.int64))
    band = int(band_s * 1000 / fm)
    frames = np.arange(total)
    lo = np.searchsorted(exp, frames - band, 'left').astype(np.int64)
    hi = (np.searchsorted(exp, frames + band, 'right') - 1).astype(np.int64)
    hi = np.maximum(hi, lo)
    lo[0] = 0
    hi[-1] = S - 1
    lo = np.minimum.accumulate(lo[::-1])[::-1]
    hi = np.maximum.accumulate(hi)
    band_lo, band_hi = lo.copy(), hi.copy()
    if floor_ms is not None and verses[0] == 1:
        # Before the floor, no state of verse 1 or after: the opening,
        # and the sound outside the surah and after the opening, only.
        k = next(i for i, wi in enumerate(c.word)
                 if wi >= 0 and words[wi][0] == 1)
        f = min(total, max(0, int(floor_ms / fm)))
        hi[:f] = np.minimum(hi[:f], k - 1)
        lo = np.minimum(lo, hi)
    cells = int((hi - lo + 1).sum())
    info = dict(band_s=band_s, cells=cells)
    if cells > MAX_CELLS:
        return None, dict(info, why='band too wide for memory')
    # Every garbage state but the one before the surah's first words
    # (state 0) costs GAP_GARBAGE: between verses, and after the last.
    isgap = np.zeros(S, np.bool_)
    for s, t_ in enumerate(c.tok):
        if t_ == -1 and s != 0:
            isgap[s] = True
    score, path = L._banded(np.ascontiguousarray(logp, np.float32), tok, ptr,
                            src, w, init, final, np.float32(LEAD_COST),
                            np.float32(L.GAP_GARBAGE), isgap, lo, hi)
    if path[0] < 0:
        return None, dict(info, why='no path')
    # How near the edges the path came: the lowest state the band allowed
    # at each frame (none below state 0) and the highest (none above the
    # last), in the frames where the table expects them. A floor is no
    # edge of the band.
    e = exp[path]
    lo_gap = np.where(band_lo == 0, np.iinfo(np.int64).max // 4,
                      e - exp[band_lo])
    hi_gap = np.where(band_hi == S - 1, np.iinfo(np.int64).max // 4,
                      exp[band_hi] - e)
    slack = int(min(lo_gap.min(), hi_gap.min()))
    info['slack_s'] = None if slack > 10 ** 12 else round(slack * fm / 1000, 1)
    rows = np.arange(total)
    pt = tok[path]
    forced = np.where(pt >= 0, logp[rows, np.maximum(pt, 0)], -L.GARBAGE)
    gap = forced - logp.max(axis=1)
    occ = L._occurrences(c.word, path)
    out, opening_frames, first = {}, None, {}
    for wi, f0, f1 in occ:
        a, p = words[wi]
        if a == 0:
            opening_frames = (opening_frames[0] if opening_frames else f0, f1)
            continue
        if a not in out:
            # The frames the verse's first word spends on its letters,
            # not on the blanks between them (see verse_rows).
            first[a] = [int(t) for t in range(f0, f1)
                        if c.word[path[t]] == wi][:400]
        out.setdefault(a, []).append((p, f0, f1, float(gap[f0:f1].mean())))
    res = {}
    for a, oc in out.items():
        n = W.text.word_count(surah, a)
        if {p for p, _, _, _ in oc} != set(range(1, n + 1)):
            continue
        v0, v1 = oc[0][1], max(f1 for _, _, f1, _ in oc)
        res[a] = dict(occ=oc, conf=float(gap[v0:v1].mean()),
                      conf_min=min(x[3] for x in oc),
                      jumps=sum(1 for x, y in zip(oc, oc[1:]) if y[0] <= x[0]),
                      frames=(v0, v1), first_tokens=first[a],
                      ignored=W.ctc.ignored(logp, pt, model.blank,
                                            model.delimiter, v0, v1))
    info['score'] = float(score)
    return dict(verses=res, opening=opening_frames), info


# ---- verse 1, where its words are ---------------------------------------

HEARD_S = 150.0         # how far into a file verse 1's words are looked for
HEARD_LETTERS = 48      # how much of the surah's text, from verse 1
HEARD_GAP_MS = 3000     # a run of heard letters breaks at a silence this long
PAUSE_BEFORE_MS = 300   # the pause a reciter takes before verse 1, at least
V1_EARLY_MS = 1000      # how far before that pause verse 1 may be put
V1_QUIET_MS = 1000      # a quiet stretch verse 1 can't begin inside
FLOOR_SLACK_MS = 200    # how far before the pause's end its first token may be

_FOLD = {'أ': 'ا', 'إ': 'ا', 'آ': 'ا', 'ٱ': 'ا', 'ة': 'ه', 'ى': 'ي',
         'ؤ': 'و', 'ئ': 'ي'}
# A letter of the muqatta'at as recited, by its name, in the letters of
# an ordinary word it lasts as long as (ayahreel-words' text._SPOKEN).
_SPOKEN = {'ا': 3, 'ح': 3, 'ي': 3, 'ط': 3, 'ه': 3, 'ر': 3,
           'ن': 8, 'ق': 8, 'ص': 8, 'ع': 8, 'س': 8, 'ل': 8, 'ك': 8, 'م': 8}


def _bare(text):
    """Arabic letters only, one form each: what a model's best guess and
    the text are compared by."""
    out = []
    for ch in text:
        ch = _FOLD.get(ch, ch)
        if 'ء' <= ch <= 'ي' and ch != 'ـ':
            out.append(ch)
    return ''.join(out)


def _spoken(word):
    """[word]'s length in letters as recited: one of the muqatta'at (the
    words written with no vowel marks) by its letters' names."""
    if any('ً' <= ch <= 'ْ' for ch in word):
        return len(_bare(word))
    return sum(_SPOKEN.get(ch, 3) for ch in _bare(word))


def heard(model, logp, frames):
    """What the model hears in the first [frames]: its likeliest token at
    each frame, repeats and blanks dropped (CTC's best path), as
    (letter, frame) for each letter."""
    inv = {i: c for c, i in model.vocab.items()}
    out, prev = [], None
    for f, t in enumerate(logp[:frames].argmax(1)):
        t = int(t)
        if t != prev and t != model.blank and t != model.delimiter:
            ch = _bare(inv.get(t, ''))
            if ch:
                out.append((ch, f))
        prev = t
    return out


def find_text(letters, target, max_gap):
    """Where [target] (bare letters) best matches in [letters], a run of
    (letter, frame): Smith-Waterman, +2 a letter matched, -1 a letter
    wrong, missed or extra, and a run of heard letters broken where
    [max_gap] frames pass between two of them. (score, index of the first
    heard letter matched, index of the target letter it matched), or
    None."""
    n, m = len(letters), len(target)
    if not n or not m:
        return None
    prev, pst = [0] * (m + 1), [None] * (m + 1)
    best = (0, None)
    for i in range(1, n + 1):
        cur, cst = [0] * (m + 1), [None] * (m + 1)
        li, fi = letters[i - 1]
        joined = i == 1 or fi - letters[i - 2][1] <= max_gap
        for j in range(1, m + 1):
            opts = []
            if joined and prev[j - 1] > 0:
                opts.append((prev[j - 1] + (2 if li == target[j - 1] else -1),
                             pst[j - 1]))
            elif li == target[j - 1]:
                opts.append((2, (i - 1, j - 1)))
            if joined and prev[j] > 0:
                opts.append((prev[j] - 1, pst[j]))
            if cur[j - 1] > 0:
                opts.append((cur[j - 1] - 1, cst[j - 1]))
            if not opts:
                continue
            sc, st = max(opts, key=lambda x: x[0])
            if sc > 0:
                cur[j], cst[j] = sc, st
                if sc > best[0]:
                    best = (sc, st)
        prev, pst = cur, cst
    if best[1] is None:
        return None
    return best[0], best[1][0], best[1][1]


def letter_ms(env, surah):
    """How long a letter lasts in this file, recited at an even pace (as
    even_pace lays the surah out)."""
    import numpy as np
    q = W.audio.quiet_below(env)
    loud = np.nonzero(env > q)[0]
    t0, t1 = int(loud[0]) * 10, (int(loud[-1]) + 1) * 10
    n = W.text.COUNTS[surah - 1]
    op = (W.text.ISTIADHA if surah in (1, 9) else
          W.text.ISTIADHA + ' ' + W.text.BASMALA).split(' ')
    w_op = sum(letters(w) for w in op) + 2 * PAUSE_LETTERS
    w = sum(letters(x) for a in range(1, n + 1) for x in W.text.words(surah, a))
    return (t1 - t0) / (w_op + w + PAUSE_LETTERS * n)


def verse_one(model, logp, env, surah, res):
    """Whether the search put verse 1 before its words, and where it
    begins then: dict(floor_ms=…) when it did, with what was found.

    A file may open with something before the surah — a later verse
    recited as a preview, as YouTube uploads do (Islam Sobhi's Al-Qari'a
    opens with 101:6-9, his Al-Ankabut with 29:41, his Al-Masad with the
    end of its own verse 1), a channel's jingle — and a verse 1 may open
    with words the model hears nothing of: the muqatta'at (الٓمٓ, نٓ),
    recited as the letters' names, or a لَآ run into the next word. The
    search, free to wait in blanks, may then take verse 1's letters from
    inside the preview, or from the basmala (Al-Baqarah's الٓمٓ from its
    ٱلرَّحْمَـٰنِ), and put verse 1 seconds early. LEAD_COST leaves most
    previews out of the surah; this finds verse 1 by its words for the
    rest:

    - Where its words are heard: the surah's first HEARD_LETTERS letters
      (verse 1, then on) found in what the model hears over the first
      HEARD_S (find_text), by their letters, which a preview of other
      verses, a basmala, a silence can't stand in for; the first heard
      letter matched, and how much of the text before it went unheard.
    - Verse 1 then begins where the reciter's voice returns after a
      pause (PAUSE_BEFORE_MS or more) before it, the last that leaves
      the unheard letters half their even-pace length (letter_ms) at
      least: the pause after a preview or the basmala.
    - Or, where verse 1 was put inside a quiet stretch of V1_QUIET_MS or
      more (the faded end of a preview whose words the model garbles),
      where that stretch ends.

    When verse 1 was put V1_EARLY_MS or more before that, make searches
    again with no state of verse 1 allowed before it (less FLOOR_SLACK_MS:
    a soft onset is heard a little before the loudness says the pause
    ends), and verse_rows starts verse 1 there, or at its first letter if
    that is heard sooner. Measured on Islam Sobhi's 110 files (2026-10-26):
    the first search, at a lead of 3.0, put verse 1 1-14 s early in 17 of
    them (11 previews, 6 unheard first words); LEAD_COST alone mends 8;
    this the other 9 (2, 15, 33, 34, 68, 75, 90, 101, 111), each to the
    pause read by hand off the loudness and what the model hears, and it
    fires on no other (18 and 54 only meet their early-letter fix sooner).
    """
    fm = model.frame_ms
    n = W.text.COUNTS[surah - 1]
    v1 = int(res['verses'][1]['frames'][0] * fm)
    out = dict(searched_ms=v1)
    floors = []
    letters_ = heard(model, logp, int(HEARD_S * 1000 / fm))
    words = []
    a = 1
    while a <= n and sum(len(_bare(w)) for w in words) < HEARD_LETTERS:
        words += W.text.words(surah, a)
        a += 1
    starts, target = [], ''
    for w in words:
        starts.append(len(target))
        target += _bare(w)
    target = target[:HEARD_LETTERS]
    hit = find_text(letters_, target, int(HEARD_GAP_MS / fm))
    # Half a perfect score at least: the most of a preview's words.
    if hit is not None and hit[0] >= len(target):
        score, i0, j0 = hit
        at = int(letters_[i0][1] * fm)
        k = max(i for i, st in enumerate(starts) if st <= j0)
        unheard = sum(_spoken(w) for w in words[:k]) + j0 - starts[k]
        need = 0.5 * unheard * letter_ms(env, surah)
        q = W.audio.quiet_below(env[:at // 10 + 3000])
        pause = None
        for p0, p1 in reversed(quiet_runs(env, q, 0, at + 100)):
            if p1 - p0 >= PAUSE_BEFORE_MS and at - p1 >= need:
                pause = p1
                break
        out.update(heard_ms=at, score=f'{score}/{2 * len(target)}',
                   unheard=unheard, pause_ms=pause)
        if pause is not None and v1 < pause - V1_EARLY_MS:
            floors.append(pause)
    q = W.audio.quiet_below(env[:v1 // 10 + 3000])
    for p0, p1 in quiet_runs(env, q, 0, v1 + 60000):
        if p0 <= v1 < p1 and p1 - p0 >= V1_QUIET_MS and \
                p1 - v1 >= V1_EARLY_MS:
            out['quiet_ms'] = [p0, p1]
            floors.append(p1)
    if floors:
        out['floor_ms'] = max(floors)
    return out


def align(model, logp, env, surah, guess, opening, band, tag=''):
    """The whole search: in a band widened while it binds the path, then
    verse 1 searched again where verse_one finds it put early. Returns
    (res, info, one): one is verse_one's finding, with applied=True when
    the second search was kept."""
    while True:
        res, info = search(model, logp, surah, guess, opening, band)
        slack = info.get('slack_s')
        if res is not None and (slack is None or slack >= GUARD_S):
            break
        if band * 2 > MAX_BAND_S or info['cells'] > MAX_CELLS:
            return res, info, None
        print(f"{tag}band {band:.0f} s: "
              f"{info.get('why') or f'slack {slack} s'}; searching "
              f"again wider", flush=True)
        band *= 2
    if 1 not in res['verses']:
        return res, info, None
    one = verse_one(model, logp, env, surah, res)
    if 'floor_ms' not in one:
        return res, info, one
    res2, info2 = search(model, logp, surah, guess, opening, band,
                         floor_ms=one['floor_ms'] - FLOOR_SLACK_MS)
    slack2 = info2.get('slack_s')
    if res2 is not None and len(res2['verses']) >= len(res['verses']) and \
            (slack2 is None or slack2 >= GUARD_S):
        one['applied'] = True
        return res2, info2, one
    one['refused'] = info2.get('why') or 'fewer verses, or the band bound it'
    return res, info, one


def windows(surah, res, env, fm):
    """Each verse's words as the alignment has them, ready for verse_rows:
    {ayah: dict(words=[(position, start, end)] in recited order, ms, the
    end of a word before a pause where the loudness falls quiet;
    first_tokens=[frames]; and the alignment's diagnostics)}."""
    out = {}
    for a in range(1, W.text.COUNTS[surah - 1] + 1):
        r = res['verses'][a]
        f0, f1 = r['frames']
        lo, hi = int(f0 * fm) - 2000, int(f1 * fm) + 2000
        q = W.audio.quiet_below(env[max(0, lo // 10):max(1, hi // 10)])
        words = W.align.word_times(r, fm, start_shift=START_SHIFT, env=env,
                                   quiet=q)
        out[a] = dict(words=[list(w) for w in words],
                      first_tokens=r['first_tokens'],
                      conf=round(r['conf'], 3), conf_min=round(r['conf_min'], 3),
                      jumps=r['jumps'], ignored=r['ignored'])
    return out


def quiet_runs(env, q, lo_ms, hi_ms):
    """Every run of PAUSE_MIN_MS or more of [env] at or under [q] between
    [lo_ms] and [hi_ms], as (from, to) ms."""
    runs, st = [], None
    lo, hi = max(0, lo_ms // 10), min(len(env), hi_ms // 10)
    for k in range(lo, hi + 1):
        if k < hi and env[k] <= q:
            if st is None:
                st = k
        elif st is not None:
            if (k - st) * 10 >= PAUSE_MIN_MS:
                runs.append((st * 10, k * 10))
            st = None
    return runs


PAUSE_MIN_MS = 200     # a breath, as verify_reciters.py's PAUSE_MIN_MS
MAX_RESTART_MS = 15000  # the most of a restart a verse takes back
EARLY_GAP_MS = 600     # an early first letter: the wait for the rest
EARLY_QUIET_MS = 300   # and the breath in it
EARLY_MAX_RUNS = 2     # the most letters dropped


def found_v1(one):
    """Where verse 1 begins when verse_one found it and the search was
    made again from there, else None."""
    return one['floor_ms'] if one and one.get('applied') else None


def verse_rows(surah, verses, env, fm, v1_at=None):
    """[ayah, start, end, conf, conf_min, jumps, ignored] for every verse,
    in ms of the file's frame clock, whole 10 ms; and the fixes made.
    [v1_at]: where verse_one found verse 1 to begin (the end of the pause
    before it), which it starts at, less START_SHIFT, unless its first
    letter is heard sooner: its first words may be ones the model hears
    nothing of, and their letters set down anywhere after the pause.

    A verse starts at its first word, less START_SHIFT, and ends where its
    last word does. Two things the alignment gets wrong are mended here,
    from the loudness, both measured on the calibration voices (see eval):

    - A first letter set down early. CTC may place a word's first letter
      in the last sound of the verse before, or in the breath after it,
      and then wait in blanks for the rest of the word: Al-Banna's 112:2
      came out 1.3 s early that way, Al-Salimi's 4:70 5 s. No reciter
      breathes inside a word, so up to two leading letters that a breath
      separates from the rest of the word — but in the muqatta'at, whose
      letters are recited by name and may be paused between — (EARLY_GAP_MS or more between
      them, EARLY_QUIET_MS of it quiet: a voiceless first letter can be
      as quiet as a breath for 400 ms) are dropped, and the verse starts
      at the rest of the word.
    - A restart. A reciter who begins a verse, stops and begins it again
      is followed by the alignment only from the second start, the first
      left as sound outside the text: Al-Ghamdi's 3:83 came out 5 s late,
      Al-Salimi's 67:26 6.4 s, where QUL's own words show the first start.
      So where sound follows the breath after the previous verse and
      comes before this verse's first word (at least PAUSE_MIN_MS of it,
      and no more than MAX_RESTART_MS before), the verse takes it.
    """
    n = W.text.COUNTS[surah - 1]
    fixes = []
    starts, ends = {}, {}
    for a in range(1, n + 1):
        v = verses[a]
        ws = v['words']
        s = ws[0][1]
        toks = v['first_tokens']
        # Not the muqatta'at (الٓمٓ, كٓهيعٓصٓ…): letters recited by their
        # names, and a reciter may well pause between them. They are the
        # words written with no vowel marks.
        letters_by_name = not any('\u064b' <= ch <= '\u0652'
                                  for ch in W.text.words(surah, a)[0])
        if len(toks) > 1 and not letters_by_name:
            q = W.audio.quiet_below(env[max(0, int(s) // 10 - 300):
                                        int(ws[-1][2]) // 10 + 300])
            # Token runs (a letter held over several frames is one).
            runs = []
            for t in toks:
                if runs and t - runs[-1][1] <= 1:
                    runs[-1][1] = t
                else:
                    runs.append([t, t])
            drop = 0
            for i in range(min(EARLY_MAX_RUNS, len(runs) - 1)):
                a_ms, b_ms = int(runs[i][1] * fm), int(runs[i + 1][0] * fm)
                # A voiceless first letter (ح, ف, س…) can be as quiet as a
                # breath for a few hundred ms; a breath the word waited
                # out is longer than that.
                if b_ms - a_ms >= EARLY_GAP_MS and any(
                        r1 - r0 >= EARLY_QUIET_MS
                        for r0, r1 in quiet_runs(env, q, a_ms, b_ms)):
                    drop = i + 1
            if drop:
                s2 = int(runs[drop][0] * fm) + START_SHIFT
                fixes.append(dict(ayah=a, fix='early letter', was=int(s),
                                  now=s2))
                s = s2
        starts[a] = int(s)
        ends[a] = int(max(e for _, _, e in ws))
    if v1_at is not None and int(v1_at) + START_SHIFT < starts[1]:
        s1 = int(v1_at) + START_SHIFT
        fixes.append(dict(ayah=1, fix='verse 1 heard', was=starts[1], now=s1))
        starts[1] = s1
    for a in range(2, n + 1):
        pe, s = ends[a - 1], starts[a]
        if s - pe < PAUSE_MIN_MS + 300:
            continue
        q = W.audio.quiet_below(env[max(0, pe // 10 - 300):s // 10 + 300])
        runs = quiet_runs(env, q, pe - 150, s)
        if not runs or runs[0][0] > pe + 300:
            continue
        onset = runs[0][1]           # sound returns after the breath
        loud = sum(1 for k in range(onset // 10, s // 10) if env[k] > q) * 10
        if onset < s - 300 and loud >= PAUSE_MIN_MS and \
                s - onset <= MAX_RESTART_MS:
            fixes.append(dict(ayah=a, fix='restart', was=s,
                              now=onset + START_SHIFT))
            starts[a] = onset + START_SHIFT
    rows = []
    for a in range(1, n + 1):
        v = verses[a]
        rows.append([a, max(0, starts[a]) // 10, -(-ends[a] // 10),
                     v['conf'], v['conf_min'], v['jumps'], v['ignored']])
    # One after another, with nothing between: a verse runs on through
    # the breath after it to where the next starts, as mp3quran's tables
    # have it, so that the windows add up to the recitation (the pace the
    # verse picker estimates a reel's length by, before any audio has
    # come) and a reel's last verse ends in that breath. The last verse
    # of the surah ends where its sound does.
    for i in range(1, len(rows)):
        rows[i][1] = max(rows[i][1], rows[i - 1][1] + 1)
        rows[i - 1][2] = rows[i][1]
    rows[-1][2] = max(rows[-1][2], rows[-1][1] + 1)
    for r_ in rows:
        r_[1] *= 10
        r_[2] *= 10
    return rows, fixes


def final_url(url):
    """Where [url]'s bytes come from, after any redirect: a host may send
    a surah it lacks to another of the reciter's recordings (see 5. in
    verify_reciters.py), and the table would then be that one's."""
    import urllib.request  # noqa: PLC0415
    req = urllib.request.Request(url, headers={
        'User-Agent': 'ayahreel-verify', 'Range': 'bytes=0-0'})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.geturl()


def make(args):
    import numpy as np
    from pipeline import models  # noqa: PLC0415 - torch, only here
    m = models.load(MODEL)
    fm = m.frame_ms
    out = os.path.join(args.out, args.id)
    os.makedirs(out, exist_ok=True)
    os.makedirs(args.work, exist_ok=True)
    ok = True
    # Surahs whose file is elsewhere (SurahFiles.elsewhere): {surah: url}.
    urls = {int(k): v for k, v in json.loads(args.urls or '{}').items()}
    for s in parse_surahs(args.surahs):
        t0 = time.time()
        url = urls.get(s) or surah_url(args.base, s, not args.unpadded)
        path = os.path.join(args.work, f'{s:03d}.mp3')
        try:
            final = final_url(url)
            W.audio.fetch(url, path)
            wave, lay = W.audio.decode_frames(path)
        except Exception as e:  # noqa: BLE001 - reported per surah
            print(f'{args.id} {s}: {e}', flush=True)
            json.dump(dict(surah=s, url=url, error=str(e)[:300]),
                      open(os.path.join(out, f'{s}.json'), 'w'))
            ok = False
            continue
        os.remove(path)
        env = W.audio.envelope(wave)
        t1 = time.time()
        logp = m.logp(wave)
        model_s = time.time() - t1
        audio_ms = len(wave) / 16
        del wave
        guess, opening = even_pace(env, s)
        res, info, one = align(m, logp, env, s, guess, opening, BAND_S,
                               tag=f'{args.id} {s}: ')
        rec = dict(surah=s, url=url, final_url=final, kbps=lay['kbps'],
                   rate=lay['rate'],
                   info_frame=lay['info'],
                   lame_skip_ms=W.audio.lame_skip_ms(lay),
                   audio_ms=int(audio_ms), model=MODEL,
                   model_s=round(model_s, 1), **info, verse_one=one)
        if res is None or (info.get('slack_s') is not None and
                           info['slack_s'] < GUARD_S):
            rec['error'] = info.get('why') or 'the band bound the path'
            ok = False
        elif len(res['verses']) != W.text.COUNTS[s - 1]:
            rec['error'] = (f"{len(res['verses'])} of "
                            f"{W.text.COUNTS[s - 1]} verses aligned")
            ok = False
        else:
            rec['opening'] = None if not res['opening'] else [
                int(res['opening'][0] * fm), int(res['opening'][1] * fm)]
            verses = windows(s, res, env, fm)
            rec['verses'], rec['fixes'] = verse_rows(s, verses, env, fm,
                                                     v1_at=found_v1(one))
            rec['words'] = {str(a): v for a, v in verses.items()}
            rec['guess_off_s'] = round(max(
                abs(v[1] - guess[v[0]][0]) for v in rec['verses']) / 1000, 1)
        # The loudness always (what verse_rows reads: `rows` redoes them
        # from it and the words, with no model and no audio); the model's
        # output when asked (what `realign` aligns again from).
        np.savez_compressed(os.path.join(out, f'env_{s}.npz'),
                            env=env.astype(np.float16))
        if args.keep_logp:
            np.savez_compressed(os.path.join(out, f'logp_{s}.npz'),
                                logp=logp.astype(np.float16))
        del logp
        json.dump(rec, open(os.path.join(out, f'{s}.json'), 'w'),
                  separators=(',', ':'))
        print(f"{args.id} {s}: {rec.get('error') or 'ok'} "
              f"audio {audio_ms / 60000:.1f} min, model {model_s:.0f} s, "
              f"band {rec['band_s']:.0f} s, slack {rec.get('slack_s')} s, "
              f"guess off by {rec.get('guess_off_s')} s, "
              f"{time.time() - t0:.0f} s in all", flush=True)
    return 0 if ok else 1


def rows_again(args):
    """verse_rows over a table directory again, from the words and the
    loudness `make` kept: for changing how rows are made without the
    model or the audio. --realign aligns again from the model output
    kept with --keep-logp first (search and windows, no model)."""
    import numpy as np
    for f in sorted(glob.glob(os.path.join(args.tables, '*.json'))):
        d = json.load(open(f))
        s = d.get('surah')
        if 'verses' not in d:
            continue
        env = np.load(os.path.join(args.tables, f'env_{s}.npz'))['env'] \
            .astype(np.float64)
        if args.realign:
            from pipeline import models  # noqa: PLC0415
            m = models.Spelling(MODEL)
            m.frame_ms = models.Model.frame_ms
            logp = np.load(os.path.join(args.tables, f'logp_{s}.npz'))[
                'logp'].astype(np.float32)
            guess, opening = even_pace(env, s)
            res, info, one = align(m, logp, env, s, guess, opening,
                                   d['band_s'], tag=f'surah {s}: ')
            if res is None or len(res['verses']) != W.text.COUNTS[s - 1]:
                print(f'surah {s}: not aligned again ({info.get("why")})')
                continue
            verses = windows(s, res, env, m.frame_ms)
            d.update(info, verse_one=one)
            d['opening'] = None if not res['opening'] else [
                int(res['opening'][0] * m.frame_ms),
                int(res['opening'][1] * m.frame_ms)]
        else:
            verses = {int(a): v for a, v in d['words'].items()}
        d['verses'], d['fixes'] = verse_rows(
            s, verses, env, models_frame_ms(), v1_at=found_v1(d.get('verse_one')))
        d['words'] = {str(a): v for a, v in verses.items()}
        json.dump(d, open(f, 'w'), separators=(',', ':'))
        print(f"surah {s}: {len(d['fixes'])} fixes "
              f"{[(x['ayah'], x['fix'], x['now'] - x['was']) for x in d['fixes']]}")
    return 0


def models_frame_ms():
    return 320 * 1000 / 16000  # pipeline/models.HOP at SR: 20 ms


# ---- eval --------------------------------------------------------------

def pct(xs, q):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(round(q * (len(xs) - 1))))] if xs else None


def stats(errs):
    a = sorted(abs(x) for x in errs)
    if not a:
        return None
    return dict(n=len(a), median=round(pct(a, 0.5)), p90=round(pct(a, 0.9)),
                p95=round(pct(a, 0.95)), p99=round(pct(a, 0.99)),
                max=round(a[-1]), bias=round(pct(errs, 0.5)),
                over200=round(sum(x > 200 for x in a) / len(a), 4),
                over300=round(sum(x > 300 for x in a) / len(a), 4),
                over1000=round(sum(x > 1000 for x in a) / len(a), 4))


def truth_starts(name, s):
    """ayah -> where its first word starts, on the file's decode clock,
    from ayahreel-words' references (pipeline/evalset.VOICES[name]);
    verse 1 has none (QUL's first word there holds the basmala)."""
    from pipeline import evalset, run_eval  # noqa: PLC0415
    get = run_eval._truth(evalset.VOICES[name])
    out = {}
    for a in range(2, W.text.COUNTS[s - 1] + 1):
        tr = get(s, a)
        if tr and 1 in tr['starts']:
            out[a] = tr['starts'][1]
    return out


def evaluate(args):
    files = sorted(glob.glob(os.path.join(args.tables, '*.json')),
                   key=lambda p: int(re.sub(r'\D', '', os.path.basename(p))
                                     or 0))
    errs, pub, pub1, worst, per = [], [], [], [], {}
    vs_pub, fixes = {}, []
    for f in files:
        d = json.load(open(f))
        s = d['surah']
        if 'verses' not in d:
            print(f"surah {s}: {d.get('error')}")
            continue
        ours = {v[0]: v for v in d['verses']}
        skip = d.get('lame_skip_ms') or 0.0
        fixes += [dict(x, surah=s) for x in d.get('fixes') or []]
        e_s = []
        if args.published:
            kind, key = args.published.split()
            tab, _ = W.tables.table((kind, int(key)), s)
            for a, (st_, _) in tab.items():
                (pub1 if a == 1 else pub).append(ours[a][1] - st_)
                vs_pub[f'{s}:{a}'] = ours[a][1] - st_
        if args.truth:
            for a, t in truth_starts(args.truth, s).items():
                e = ours[a][1] - (t + skip)
                e_s.append(e)
                worst.append((abs(e), f'{s}:{a}', e))
        errs += e_s
        st = stats(e_s)
        per[s] = dict(truth=st, guess_off_s=d.get('guess_off_s'),
                      slack_s=d.get('slack_s'), band_s=d.get('band_s'))
        print(f"surah {s:3d}: {len(ours)} verses, truth {st}, "
              f"band {d.get('band_s')} slack {d.get('slack_s')} "
              f"guess off {d.get('guess_off_s')} s", flush=True)
    # Where the reference and the table part, what the published table
    # says, less its usual distance from ours (its convention): a third
    # opinion on which of the two is off.
    bias = pct(list(vs_pub.values()), 0.5) or 0
    res = dict(tables=args.tables, truth=args.truth,
               against_truth=stats(errs), per_surah=per,
               fixes={k: sum(1 for x in fixes if x['fix'] == k)
                      for k in ('early letter', 'restart')},
               fixes_e_g=[f"{x['surah']}:{x['ayah']} {x['fix']} "
                          f"{x['now'] - x['was']:+d} ms" for x in fixes[:30]],
               worst=[dict(key=k, err=e, published_says=None if k not in
                           vs_pub else round(vs_pub[k] - bias))
                      for _, k, e in sorted(worst, reverse=True)[:40]])
    if args.published:
        res['published'] = args.published
        res['against_published'] = stats(pub)
        # The published table's convention (where in the breath it puts
        # a verse) taken out: how closely the two agree verse by verse.
        res['against_published_centred'] = stats([x - bias for x in pub])
        res['against_published_verse1'] = stats(pub1)
    t = res['against_truth']
    if t:
        res['passes'] = t['median'] <= MAX_MEDIAN_MS and t['p90'] <= MAX_P90_MS
    print(json.dumps({k: v for k, v in res.items() if k != 'per_surah'},
                     indent=1))
    if args.json:
        json.dump(res, open(args.json, 'w'), indent=1)
    return 0


# ---- pack: the table as the app carries it ------------------------------

def varint(n, out):
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            out.append(b | 0x80)
        else:
            out.append(b)
            return


def encode(tables):
    """{surah: [(start, end) ms by verse]} as VerseTables decodes it: for
    each surah 1..114 its verse count (0 for a surah not there), then for
    each verse the gap since the previous verse ended (the first: since
    the file began) and its length, in 10 ms, each a LEB128 varint;
    base64."""
    out = bytearray()
    for s in range(1, 115):
        rows = tables.get(s) or []
        varint(len(rows), out)
        prev = 0
        for st, en in rows:
            assert st % 10 == 0 and en % 10 == 0, (s, st, en)
            st10, en10 = st // 10, en // 10
            assert st10 >= prev and en10 > st10, (s, st, en)
            varint(st10 - prev, out)
            varint(en10 - st10, out)
            prev = en10
    return base64.b64encode(bytes(out)).decode('ascii')


def decode(text):
    b = base64.b64decode(text)
    i = 0

    def rd():
        nonlocal i
        n = sh = 0
        while True:
            x = b[i]
            i += 1
            n |= (x & 0x7F) << sh
            sh += 7
            if not x & 0x80:
                return n
    out = {}
    for s in range(1, 115):
        n = rd()
        prev, rows = 0, []
        for _ in range(n):
            st = prev + rd()
            en = st + rd()
            rows.append((st * 10, en * 10))
            prev = en
        if n:
            out[s] = rows
    assert i == len(b), 'trailing bytes'
    return out


def digest(text):
    """What tool/reciters_verified.json and the test name a table by."""
    return hashlib.sha256(text.encode('ascii')).hexdigest()[:12]


def read_dir(path):
    out = {}
    for f in glob.glob(os.path.join(path, '*.json')):
        d = json.load(open(f))
        if 'verses' in d:
            out[d['surah']] = [(v[1], v[2]) for v in d['verses']]
    return out


def own_tables():
    """key -> encoded table, from $OWN_TABLES (see OWN above); empty when
    it isn't set."""
    if not OWN or not os.path.exists(OWN):
        return {}
    return json.load(open(OWN, encoding='utf8'))


def dart_digests():
    """key -> sha256, as lib/data/verse_tables.dart's VerseTables.digests
    has them: what the app trusts each table by."""
    src = open(DART, encoding='utf8').read()
    return dict(re.findall(r"\n    '([a-z0-9_]+)':\s*'([0-9a-f]{64})',", src))


def dart_entry(key, text, note):
    full = hashlib.sha256(text.encode('ascii')).hexdigest()
    return f"    // {note}\n    '{key}':\n        '{full}',\n"


def pack(args):
    """Each table directory given as `<key>=<dir>`, encoded: printed, or
    with --write put into $OWN_TABLES (then served by the private
    repository's worker/put_tables.py) with its digest put into
    lib/data/verse_tables.dart, in place of any entry of that key."""
    if args.write and not OWN:
        sys.exit('pack --write needs OWN_TABLES: the private ayahreel-words '
                 "repository's data/own_tables.json")
    have = own_tables()
    for spec in args.dirs:
        key, path = spec.split('=', 1)
        tables = read_dir(path)
        text = encode(tables)
        assert decode(text) == {s: r for s, r in tables.items() if r}
        have[key] = text
        print(f'{key}: {len(tables)} surahs, '
              f'{sum(len(r) for r in tables.values())} verses, '
              f'{len(text)} characters, sha256 {digest(text)}')
    if not args.write:
        for key in sorted(have):
            print(dart_entry(key, have[key], f'sha256 {digest(have[key])}'))
        return 0
    json.dump(have, open(OWN, 'w', encoding='utf8'), indent=1, sort_keys=True)
    src = open(DART, encoding='utf8').read()
    head = src.index('  static const digests = <String, String>{')
    tail = src.index('};', head) + 2
    body = ''.join(dart_entry(k, have[k], (
        f'{len(decode(have[k]))} surahs, '
        f'{sum(len(r) for r in decode(have[k]).values())} verses.'))
        for k in sorted(have))
    src = (src[:head] + '  static const digests = <String, String>{\n' + body +
           '  };' + src[tail:])
    open(DART, 'w', encoding='utf8').write(src)
    assert own_tables() == have
    assert dart_digests() == {k: hashlib.sha256(v.encode('ascii')).hexdigest()
                              for k, v in have.items()}
    print('then put them on the host: python3 worker/put_tables.py in the '
          'private repository')
    return 0


# ---- screen: is a recording worth a table? -------------------------------

def screen(args):
    """Before an hour of runner time goes into a table: whether a
    recording with none is plainly the same audio as a recording the app
    has. Every verse of a few short surahs of the app's recording is
    looked for, CHUNK_MS at a time, anywhere in the candidate's surah file
    (verify_reciters.wave_match, 9. there), and judged by 9.'s bars. The
    surahs' lengths are reported beside, for a person: against verse
    files cut with their own silences they say little. A recording that
    passes is still compared verse by verse, as 9. does, once it has its
    table: that is what finds the same performance resampled."""
    import numpy as np
    sys.path.insert(0, os.path.join(ROOT, 'tool'))
    import verify_reciters as V  # noqa: PLC0415
    ref = V.recording(args.ref, V.app_reciters())
    rows, chunks = [], []
    for s in parse_surahs(args.surahs):
        st, _, b = V._get(surah_url(args.cand, s, not args.unpadded),
                          timeout=120)
        if st != 200:
            rows.append(dict(surah=s, error=f'candidate: HTTP {st}'))
            continue
        pc = V.decode_pcm(b)
        ec = V.env_of(pc)
        if ref['kind'] == 'ayah':
            parts = []
            for a in range(1, V.COUNTS[s - 1] + 1):
                st, _, b = V._get(f"{ref['base']}/{s:03d}{a:03d}.mp3",
                                  timeout=120)
                if st != 200:
                    raise RuntimeError(f'{ref["id"]} {s}:{a}: HTTP {st}')
                parts.append(V.decode_pcm(b))
        else:
            st, _, b = V._get(V.surah_url(ref, s), timeout=120)
            whole = V.decode_pcm(b)
            n = 15 * V.XRATE
            parts = [whole[i:i + n] for i in range(0, len(whole), n)]
        found = []
        for x in parts:
            ex = V.env_of(x)
            snd = V.sound(ex, (0, len(ex) * 10))
            if not snd:
                continue
            sr = V.XRATE // 1000
            found += V.wave_match(x[snd[0] * sr:snd[1] * sr], pc)
        chunks += found
        er = np.concatenate([V.env_of(x) for x in parts])
        sc, sr_ = V.sound(ec, (0, len(ec) * 10)), V.sound(er, (0, len(er) * 10))
        rows.append(dict(
            surah=s, chunks=len(found),
            best=round(max(found, default=0), 3),
            median=round(float(np.median(found)), 3) if found else None,
            doubt=sum(V.SAME_PEAK <= f < V.STRONG_PEAK for f in found),
            same=sum(f >= V.STRONG_PEAK for f in found),
            ratio=round((sc[1] - sc[0]) / (sr_[1] - sr_[0]), 4)
            if sc and sr_ else None))
        print(json.dumps(rows[-1]), flush=True)
    ratios = [math.log(r['ratio']) for r in rows if r.get('ratio')]
    mid = sorted(ratios)[len(ratios) // 2] if ratios else 0
    res = dict(ref=args.ref, cand=args.cand, surahs=rows,
               chunks=len(chunks),
               same=sum(f >= V.STRONG_PEAK for f in chunks),
               doubt=sum(V.SAME_PEAK <= f < V.STRONG_PEAK for f in chunks),
               median=round(sorted(chunks)[len(chunks) // 2], 3)
               if chunks else None,
               ratio=round(math.exp(mid), 3),
               ratio_spread=round(sorted(abs(x - mid) for x in ratios)[
                   len(ratios) // 2], 4) if ratios else None)
    # 9.'s bars, on stretches rather than verses: a median over
    # MAX_WAVE_MEDIAN is a performance found again, altered or not.
    res['verdict'] = (
        'same audio' if res['same'] >= 3 or (res['median'] or 0) >= 0.6 else
        'in doubt' if res['same'] or res['doubt'] > 0.05 * len(chunks) or
        (res['median'] or 0) > V.MAX_WAVE_MEDIAN
        else 'looks like another performance')
    print(json.dumps({k: v for k, v in res.items() if k != 'surahs'}))
    if args.json:
        json.dump(res, open(args.json, 'w'), indent=1)
    return 0


# ---- speaker: the reciter at all? -----------------------------------------

SPEAKER_MODEL = 'speechbrain/spkrec-ecapa-voxceleb'
SPEAKER_BYTES = 8_000_000  # of each file: minutes of it, however encoded
SPEAKER_SKIP_S = 30        # past any intro, the isti'adha and the basmala
SPEAKER_SEG_S = 10
SPEAKER_SEGS = 8
SPEAKER_MARGIN = 0.05


def speaker(args):
    """Whether files that come from another host than the rest of a
    voice's are the reciter's at all, for surahs none of his other files
    has, so that no file of his can be found in them (10. in
    verify_reciters.py finds the others that way). Each file is heard by
    a speaker-verification model (ECAPA-TDNN trained on VoxCeleb,
    SpeechBrain, Apache-2.0): SPEAKER_SEGS stretches of SPEAKER_SEG_S
    past its first SPEAKER_SKIP_S, their embeddings averaged. Against the
    mean of his own files (`refs`), each own file left out of it in turn
    says how near his voice comes to itself, other reciters' files
    (`others`) how near another voice comes; a candidate (`cands`) is
    his when it is nearer than the nearest other reciter by
    SPEAKER_MARGIN, and no further than his furthest own file less
    SPEAKER_MARGIN. Where his own and the others' don't part by that
    much, it can't say, and says so."""
    import subprocess  # noqa: PLC0415
    import numpy as np
    import torch  # noqa: PLC0415
    from speechbrain.inference.speaker import EncoderClassifier  # noqa: PLC0415
    sys.path.insert(0, os.path.join(ROOT, 'tool'))
    import verify_reciters as V  # noqa: PLC0415
    job = json.load(open(args.job, encoding='utf8'))
    enc = EncoderClassifier.from_hparams(
        source=SPEAKER_MODEL, savedir=os.path.join(args.work, 'ecapa'),
        run_opts={'device': 'cpu'})

    def embed(url):
        st, _, b = V._get(url, headers={
            'Range': f'bytes=0-{SPEAKER_BYTES - 1}'}, timeout=180)
        if st not in (200, 206):
            raise RuntimeError(f'{url}: HTTP {st}')
        # Whatever it is encoded as (an m4a whole, or an mp3's start), from
        # a file: an m4a may keep its index at the end, past any pipe.
        tmp = os.path.join(args.work, 'speaker_in')
        os.makedirs(args.work, exist_ok=True)
        with open(tmp, 'wb') as f:
            f.write(b)
        pcm = subprocess.run(
            ['ffmpeg', '-v', 'quiet', '-i', tmp, '-ac', '1',
             '-ar', '16000', '-f', 'f32le', '-'],
            capture_output=True).stdout
        os.remove(tmp)
        x = np.frombuffer(pcm[:len(pcm) // 4 * 4], dtype='<f4')
        n = SPEAKER_SEG_S * 16000
        start = min(SPEAKER_SKIP_S * 16000, max(0, len(x) - n))
        segs = [x[i:i + n] for i in range(start, len(x) - n + 1, n)]
        # The voiced ones: a stretch of breath and silence says little.
        segs = sorted(segs, key=lambda v: -float(np.sqrt((v ** 2).mean())))
        segs = segs[:SPEAKER_SEGS]
        if not segs:
            raise RuntimeError(f'{url}: too short')
        with torch.no_grad():
            e = enc.encode_batch(torch.from_numpy(np.stack(segs).copy()))
        e = e.squeeze(1).numpy()
        e /= np.linalg.norm(e, axis=1, keepdims=True)
        m = e.mean(0)
        return m / np.linalg.norm(m), len(segs)

    emb = {}
    for group in ('refs', 'cands', 'others', 'peers'):
        for name, url in (job.get(group) or {}).items():
            emb[(group, name)], k = embed(url)
            print(f'{group} {name}: {k} stretches', flush=True)

    def unit(v):
        return v / np.linalg.norm(v)
    refs = [k for k in emb if k[0] == 'refs']
    mean = unit(sum(emb[k] for k in refs))
    own = {k[1]: float(unit(sum(emb[j] for j in refs if j != k)) @ emb[k])
           for k in refs}
    other = {k[1]: float(mean @ emb[k]) for k in emb if k[0] == 'others'}
    lo_own = min(own.values())
    hi_other = max(other.values(), default=-1.0)
    parted = lo_own - hi_other >= 2 * SPEAKER_MARGIN
    cands = {}
    for k in emb:
        if k[0] != 'cands':
            continue
        sim = float(mean @ emb[k])
        verdict = ('his' if parted and sim >= lo_own - SPEAKER_MARGIN
                   and sim >= hi_other + SPEAKER_MARGIN else
                   'not his' if parted and sim < hi_other + SPEAKER_MARGIN
                   else 'cannot tell')
        cands[k[1]] = dict(sim=round(sim, 3), verdict=verdict)
    # A peer: one file of his from where the candidates come from (the
    # same host, the same encoding), so that what a host's processing
    # does to a voice is in both sides of a comparison with it. Each
    # candidate is put beside how near his own files and the other
    # reciters' come to the peer.
    peers = {}
    for kp in [k for k in emb if k[0] == 'peers']:
        p = emb[kp]
        own_p = [float(p @ emb[k]) for k in refs]
        oth_p = [float(p @ emb[k]) for k in emb if k[0] == 'others']
        peers[kp[1]] = dict(
            own=[round(x, 3) for x in own_p], others=[round(x, 3) for x in oth_p],
            cands={k[1]: round(float(p @ emb[k]), 3) for k in emb
                   if k[0] == 'cands'})
    res = dict(model=SPEAKER_MODEL, own={k: round(v, 3) for k, v in own.items()},
               others={k: round(v, 3) for k, v in other.items()},
               lo_own=round(lo_own, 3), hi_other=round(hi_other, 3),
               parted=parted, cands=cands, peers=peers)
    print(json.dumps(res, indent=1))
    if args.json:
        json.dump(res, open(args.json, 'w'), indent=1)
    # A report, not a gate: a candidate found not his is the check
    # working, and the verdicts are for a person to read (and to record
    # in verify_reciters.SPEAKER_CHECKED), not a failed job.
    return 0


# ---- plan: the workflow's matrix -----------------------------------------

def plan(args):
    msg = os.environ.get(args.message_env, '')
    line = next((ln for ln in msg.splitlines() if '[tables]' in ln), '')
    names = line.split('[tables]', 1)[1].split() if line else []
    sets = json.load(open(JOBS, encoding='utf8'))
    jobs = []
    for n in names:
        for j in sets[n]:
            jobs.append(dict(j, set=n))
    for i, j in enumerate(jobs):
        j['name'] = f"{j['id']}-{i}"
    # A job set may name runs whose tables to take instead of making them
    # ({"id": ..., "base": ..., "runs": [run ids]}): the summary measures
    # and checks them again, whole.
    make_ = [j for j in jobs if not j.get('screen') and not j.get('runs')
             and not j.get('speaker')]
    screens = [j for j in jobs if j.get('screen')]
    speakers = [j for j in jobs if j.get('speaker')]
    summary = {}
    for j in jobs:
        # "summary": false for a job that makes only part of a voice's
        # tables, which the whole-voice check would fail.
        if not j.get('screen') and not j.get('speaker') and \
                j.get('summary', True):
            summary.setdefault(j['id'], {k: j[k] for k in (
                'id', 'base', 'padded', 'truth', 'published', 'urls')
                if k in j})
    runs = sorted({r for j in jobs for r in j.get('runs') or []})
    print('matrix=' + json.dumps(make_, separators=(',', ':')))
    print('screens=' + json.dumps(screens, separators=(',', ':')))
    print('speakers=' + json.dumps(speakers, separators=(',', ':')))
    print('summary=' + json.dumps(list(summary.values()),
                                  separators=(',', ':')))
    print('runs=' + ' '.join(map(str, runs)))
    return 0


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest='cmd', required=True)
    p = sub.add_parser('make')
    p.add_argument('--words', required=True)
    p.add_argument('--id', required=True)
    p.add_argument('--base', required=True)
    p.add_argument('--unpadded', action='store_true')
    p.add_argument('--surahs', default='1-114')
    p.add_argument('--out', default='out')
    p.add_argument('--work', default='work')
    p.add_argument('--keep-logp', action='store_true')
    p.add_argument('--urls', default='',
                   help='JSON {surah: url} for files not at --base')
    p = sub.add_parser('eval')
    p.add_argument('--words', required=True)
    p.add_argument('--tables', required=True)
    p.add_argument('--truth')
    p.add_argument('--published')
    p.add_argument('--json')
    p = sub.add_parser('pack')
    p.add_argument('dirs', nargs='+')
    p.add_argument('--write', action='store_true')
    p = sub.add_parser('rows')
    p.add_argument('--words', required=True)
    p.add_argument('--tables', required=True)
    p.add_argument('--realign', action='store_true')
    p = sub.add_parser('screen')
    p.add_argument('--ref', required=True,
                   help="the app's recording: an id, or a source")
    p.add_argument('--cand', required=True, help='surah files at <base>')
    p.add_argument('--unpadded', action='store_true')
    p.add_argument('--surahs', default='1,93,97,103,108,110,112-114')
    p.add_argument('--json')
    p = sub.add_parser('speaker')
    p.add_argument('--job', required=True, help='{refs, cands, others}: '
                   '{name: url} each')
    p.add_argument('--work', default='work')
    p.add_argument('--json')
    p = sub.add_parser('plan')
    p.add_argument('--message-env', default='MESSAGE')
    args = ap.parse_args()
    if getattr(args, 'words', None):
        load_words(args.words)
    return {'make': make, 'eval': evaluate, 'pack': pack, 'screen': screen,
            'rows': rows_again, 'speaker': speaker,
            'plan': plan}[args.cmd](args)


if __name__ == '__main__':
    sys.exit(main())
