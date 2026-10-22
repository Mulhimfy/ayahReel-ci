#!/usr/bin/env python3
"""Scratch, runner only: where verse 1 starts in every surah of a surah-
file set, against its sound — the check 6. makes in the sampled windows,
made in all 114, with what is heard either side: a table whose verse 1
opens inside the basmala gives a verse-1 reel a piece of it."""
import json
import os
import sys
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.join(os.getcwd(), 'tool'))
import verify_reciters as vr  # noqa: E402

APPS = vr.app_reciters()


def scan(spec):
    r = vr.recording(spec, APPS)

    def one(s):
        try:
            rows = vr.table_rows(r, s)
            st = rows[0][0]
            url = vr.surah_url(r, s)
            lay = vr.layout(url)
            b, origin = vr.fetch_slice(url, lay, st - 9000, st + 5000)
            pcm = vr.decode_pcm(b)
            env = vr.env_of(pcm)
            runs = vr.breaths([float(x) for x in env])
            at = st - origin
            ok = vr.breath_within(runs, at, vr.EDGE_MS, vr.SNAP_MS)
            cut = vr.snap(env, at, vr.EDGE_MS, vr.SNAP_MS)
            floor, speech = vr.levels([float(x) for x in env])
            thr = floor + vr.PAUSE_REL * (speech - floor)
            # Sound from the cut to the first breath after it, and from the
            # breath before the table's start to it.
            nxt = next(((a, b_) for a, b_ in runs if a >= cut), None)
            prv = [(a, b_) for a, b_ in runs if b_ <= at]
            before = at - prv[-1][1] if prv else at
            after = (nxt[0] - cut) if nxt else None
            loud_at_cut = float(env[min(len(env) - 1, cut // 10)]) > thr
            return s, dict(start=st, in_breath=ok, cut_in_sound=loud_at_cut,
                           sound_before_ms=before, sound_after_cut_ms=after,
                           v1_ms=rows[0][1] - rows[0][0])
        except Exception as e:  # noqa: BLE001
            return s, dict(error=str(e)[:120])
    with ThreadPoolExecutor(4) as ex:
        res = dict(ex.map(one, range(1, 115)))
    bad = {s: v for s, v in res.items() if v.get('error') or not v['in_breath'] or v['cut_in_sound']}
    print(f'{spec}: verse 1 start out of a breath, or cut in sound, in {len(bad)} of 114')
    for s, v in sorted(bad.items()):
        print('   ', s, v)
    return res


def main():
    out = {}
    for spec in sys.argv[1:]:
        out[spec] = scan(spec)
    os.makedirs('out', exist_ok=True)
    json.dump(out, open('out/verse1.json', 'w'), indent=0)


if __name__ == '__main__':
    main()
