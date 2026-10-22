#!/usr/bin/env python3
"""Scratch, runner only: what Al-Luhaidan's complete sets are — every file
there, their sound, and whether the hosts serve one recording or several.
None has a verse table (mp3quran's ayat_timing is empty for his moshaf
107; QUL, quran.com, EveryAyah, KSU and Tarteel have nothing of his)."""
import json
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.join(os.getcwd(), 'tool'))
import verify_reciters as vr  # noqa: E402

OUT = os.path.join(os.getcwd(), 'out')
HOSTS = {
    'mp3quran': ('https://cdn.mp3quran.net/audio/muhammad-luhaidan/r1', True),
    'mp3quran_old': ('https://server8.mp3quran.net/lhdan', True),
    'quranicaudio': ('https://download.quranicaudio.com/quran/muhammad_alhaidan', True),
    'islamicnetwork': ('https://cdn.islamic.network/quran/audio-surah/128/ar.muhammadalluhaidan', False),
}


def url(h, s):
    base, pad = HOSTS[h]
    return f'{base}/{s:03d}.mp3' if pad else f'{base}/{s}.mp3'


def files(h):
    def one(s):
        lay = vr.layout(url(h, s))
        return s, {k: lay.get(k) for k in ('ok', 'why', 'kbps', 'rate', 'vbr', 'audio_ms', 'total')}
    with ThreadPoolExecutor(6) as ex:
        return dict(ex.map(one, range(1, 115)))


def whole(h, s):
    st, _, b = vr._get(url(h, s), timeout=300)
    if st != 200:
        raise RuntimeError(f'{url(h, s)}: {st}')
    p = subprocess.run(['ffmpeg', '-v', 'error', '-i', '-', '-ac', '1', '-ar', '8000',
                        '-f', 's16le', '-'], input=b, capture_output=True, check=True)
    import numpy as np
    return np.frombuffer(p.stdout[:len(p.stdout) // 2 * 2], dtype='<i2')


def main():
    out = {}
    for h in HOSTS:
        out[h] = files(h)
        f = out[h]
        bad = [s for s, v in f.items() if not v['ok']]
        kinds = sorted({(v['kbps'], v['rate'], v['vbr']) for v in f.values() if v['ok']})
        print(f"{h}: {114 - len(bad)}/114 files, bad={bad[:10]} formats={kinds}", flush=True)
    # Same recording? Durations of every surah, host against host, and the
    # waveforms of three short surahs.
    hs = list(HOSTS)
    for i in range(len(hs)):
        for j in range(i + 1, len(hs)):
            a, b = hs[i], hs[j]
            d = [(s, out[a][s]['audio_ms'], out[b][s]['audio_ms']) for s in range(1, 115)
                 if out[a][s]['ok'] and out[b][s]['ok']]
            diffs = sorted(abs(x - y) for _, x, y in d)
            print(f'{a} vs {b}: duration diff median {diffs[len(diffs) // 2]:.0f} ms, '
                  f'max {diffs[-1]:.0f} ms over {len(d)} surahs; '
                  f'worst {sorted(d, key=lambda t: -abs(t[1] - t[2]))[:4]}', flush=True)
            for s in (1, 108, 112):
                try:
                    xa, xb = whole(a, s), whole(b, s)
                    sr = 8
                    mid = len(xa) // 2
                    peaks = []
                    for c0 in (mid // 3, mid, mid + mid // 2):
                        x = xa[c0:c0 + 1500 * sr]
                        r = vr.ncc(x, xb)
                        peaks.append(round(float(abs(r).max()), 3) if r is not None else None)
                    print(f'   {s}: waveform peaks {peaks} lengths {len(xa) // 8} / {len(xb) // 8} ms',
                          flush=True)
                except Exception as e:  # noqa: BLE001
                    print(f'   {s}: {e!r}', flush=True)
    os.makedirs(OUT, exist_ok=True)
    json.dump(out, open(os.path.join(OUT, 'luhaidan_files.json'), 'w'), indent=1)


if __name__ == '__main__':
    main()
