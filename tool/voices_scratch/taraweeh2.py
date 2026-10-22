#!/usr/bin/env python3
"""Scratch, runner only: anything in the Taraweeh 1430 set (QUL 95) a reel
would carry that is not the verse — the congregation's amin after
Al-Fatiha, a takbir where a rak'ah was spliced?

1. Al-Fatiha's file whole: every stretch of sound in it, against its
   table.
2. Each verse's sound in a reel of it alone, against the same verse in
   the app's Alafasy (EveryAyah): the first verse and the last of every
   surah, and every verse of 2:1-100, 18, 36, 55 and 67. A verse whose
   sound runs well past what the overall ratio predicts holds something
   more."""
import json
import os
import sys
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.join(os.getcwd(), 'tool'))
import verify_reciters as vr  # noqa: E402

APPS = vr.app_reciters()
T = vr.recording('surah https://download.quranicaudio.com/quran/mishaari_california '
                 'SSS qul 95', APPS)
E = vr.recording('alafasy', APPS)


def runs(env, thr, gap=300):
    """Stretches of sound: frames over [thr], joined across quiet under
    [gap] ms, as (from, to) ms."""
    out = []
    st = None
    last = None
    for k, x in enumerate(env):
        if x > thr:
            if st is None:
                st = k
            elif last is not None and (k - last) * 10 > gap:
                out.append((st * 10, (last + 1) * 10))
                st = k
            last = k
    if st is not None:
        out.append((st * 10, (last + 1) * 10))
    return out


def fatiha():
    url = vr.surah_url(T, 1)
    st, _, b = vr._get(url, timeout=120)
    pcm = vr.decode_pcm(b)
    env = vr.env_of(pcm)
    floor, speech = vr.levels([float(x) for x in env])
    thr = floor + vr.PAUSE_REL * (speech - floor)
    rows = vr.table_rows(T, 1)
    print('Al-Fatiha table:', rows, 'file ms:', len(env) * 10)
    for a, b_ in runs(env, thr):
        inside = [i + 1 for i, (s0, s1) in enumerate(rows) if a < s1 and b_ > s0]
        print(f'   sound {a}-{b_} ms ({b_ - a} ms) in verses {inside}')


def spans(r, s, a):
    pcm, env, win = vr.clip(r, s, a)
    sp = vr.sound(env, win)
    floor, speech = vr.levels([float(x) for x in env])
    thr = floor + vr.PAUSE_REL * (speech - floor)
    lo, hi = win[0] // 10, win[1] // 10
    bursts = runs(env[lo:hi], thr)
    return sp, bursts


def main():
    fatiha()
    keys = []
    for s in range(1, 115):
        keys += [(s, 1), (s, vr.COUNTS[s - 1])]
    keys += [(2, a) for a in range(2, 101)]
    for s in (18, 36, 55, 67):
        keys += [(s, a) for a in range(2, vr.COUNTS[s - 1])]
    keys = sorted(set(keys))

    def one(k):
        s, a = k
        try:
            (st, bt), (se, be) = spans(T, s, a), spans(E, s, a)
            return k, dict(t=st and st[1] - st[0], e=se and se[1] - se[0],
                           tb=len(bt), eb=len(be), tbursts=bt[:8])
        except Exception as e:  # noqa: BLE001
            return k, dict(error=str(e)[:100])
    with ThreadPoolExecutor(4) as ex:
        res = dict(ex.map(one, keys))
    ratio = 0.962
    flagged = []
    for (s, a), r in sorted(res.items()):
        if 'error' in r or not r['t'] or not r['e']:
            print('  ?', s, a, r)
            continue
        extra = r['t'] - ratio * r['e']
        if extra > max(1200, 0.25 * ratio * r['e']):
            flagged.append((s, a, r))
    print(f'{len(res)} verses compared; {len(flagged)} with more sound than their '
          'Alafasy (EveryAyah) counterpart predicts:')
    for s, a, r in flagged:
        print(f"   {s}:{a} taraweeh {r['t']} ms in {r['tb']} bursts {r['tbursts']}, "
              f"everyayah {r['e']} ms in {r['eb']}")
    os.makedirs('out', exist_ok=True)
    json.dump({f'{s}:{a}': r for (s, a), r in res.items()}, open('out/taraweeh2.json', 'w'),
              indent=0)


if __name__ == '__main__':
    main()
