#!/usr/bin/env python3
"""Scratch, runner only: is anything in Alafasy's Taraweeh 1430 files
(QUL 95) that is not the verse — a takbir, the congregation's amin — and
would a reel's cut take it in? Per verse, QUL's window against QUL's own
words: sound before the first word or after the last one, inside the
window or within the app's reach past its ends."""
import json
import os
import sys
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.join(os.getcwd(), 'tool'))
import verify_reciters as vr  # noqa: E402

R = vr.recording('surah https://download.quranicaudio.com/quran/mishaari_california '
                 'SSS qul 95', [])
QUL = 'https://qul.tarteel.ai/api/v1/audio/surah_segments'


def seg(s):
    n = vr.COUNTS[s - 1]
    return vr.cached_json(f'{QUL}/95?surah={s}&from=1&to={n}&per_page={n}',
                          f'qul_95_{s:03d}.json')


def words(v):
    return [tuple(int(x) for x in w[:3]) for w in (v.get('segments') or []) if len(w) >= 3]


def main():
    out = {}
    odd = []
    for s in range(1, 115):
        d = seg(s)
        sg = d.get('segments') or {}
        for a in range(1, vr.COUNTS[s - 1] + 1):
            v = sg.get(f'{s}:{a}') or {}
            w = words(v)
            if not w:
                odd.append((s, a, 'no words'))
                continue
            tf, tt = v['time_from'], v['time_to']
            head = w[0][1] - tf
            tail = tt - max(e for _, _, e in w)
            if head > 1500 or tail > 1500:
                odd.append((s, a, head, tail, tf, tt))
    print(f'{len(odd)} verses whose window has more than 1.5 s beyond its words:')
    for o in odd[:200]:
        print('  ', o)
    # The sound in those stretches: the loudness of what lies before the
    # first word and after the last, against the verse's own speech.
    def look(o):
        if len(o) < 6:
            return o, None
        s, a, head, tail, tf, tt = o
        try:
            url = vr.surah_url(R, s)
            lay = vr.layout(url)
            b, origin = vr.fetch_slice(url, lay, tf - 1000, tt + 1500)
            pcm = vr.decode_pcm(b)
            env = vr.env_of(pcm)
            floor, speech = vr.levels([float(x) for x in env])
            thr = floor + vr.PAUSE_REL * (speech - floor)
            w = words(seg(s)['segments'][f'{s}:{a}'])
            w0, w1 = w[0][1] - origin, max(e for _, _, e in w) - origin
            pre = [float(x) for x in env[max(0, int((tf - origin) // 10)):int(w0 // 10)]]
            post = [float(x) for x in env[int(w1 // 10):int((tt - origin + 800) // 10)]]
            loud = lambda xs: round(sum(x > thr for x in xs) * 10)  # noqa: E731
            return o, dict(sound_before_ms=loud(pre), sound_after_ms=loud(post))
        except Exception as e:  # noqa: BLE001
            return o, dict(error=str(e)[:100])
    with ThreadPoolExecutor(4) as ex:
        res = list(ex.map(look, odd[:120]))
    for o, r in res:
        print('  look', o[:4], r)
    out['odd'] = [list(o) for o in odd]
    out['look'] = [[list(o), r] for o, r in res]
    os.makedirs('out', exist_ok=True)
    json.dump(out, open('out/taraweeh.json', 'w'), indent=1)


if __name__ == '__main__':
    main()
