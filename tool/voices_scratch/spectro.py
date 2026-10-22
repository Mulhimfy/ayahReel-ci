#!/usr/bin/env python3
"""Scratch, runner only: pictures of what is in the Taraweeh 1430 set
where it differs from the studio set — spectrograms of whole verse
windows as a reel of each would cut them, the studio verse beside it."""
import os
import subprocess
import sys

sys.path.insert(0, os.path.join(os.getcwd(), 'tool'))
import verify_reciters as vr  # noqa: E402

APPS = vr.app_reciters()
T = vr.recording('surah https://download.quranicaudio.com/quran/mishaari_california '
                 'SSS qul 95', APPS)
OUT = 'out/spectro'
os.makedirs(OUT, exist_ok=True)


def pic(mp3, name, title):
    p = os.path.join(OUT, name + '.png')
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', mp3, '-lavfi',
                    'showspectrumpic=s=1400x360:mode=combined:color=intensity:'
                    'scale=log:legend=1:start=0:stop=4000', p], check=True)
    print('wrote', p, title, flush=True)


def taraweeh(s, a0, a1, name):
    rows = vr.table_rows(T, s)
    st, en = rows[a0 - 1][0], rows[a1 - 1][1]
    url = vr.surah_url(T, s)
    lay = vr.layout(url)
    b, origin = vr.fetch_slice(url, lay, st - 1500, en + 1500)
    path = os.path.join(OUT, name + '.mp3')
    open(path, 'wb').write(b)
    pic(path, name, f'taraweeh {s}:{a0}-{a1} table {st}-{en} origin {origin:.0f}')
    os.remove(path)


def studio(s, a, name):
    st, _, b = vr._get(f'https://everyayah.com/data/Alafasy_128kbps/{s:03d}{a:03d}.mp3')
    path = os.path.join(OUT, name + '.mp3')
    open(path, 'wb').write(b)
    pic(path, name, f'studio {s}:{a}')
    os.remove(path)


for s, a0, a1 in ((1, 7, 7), (1, 1, 2), (39, 1, 1), (88, 1, 2), (2, 81, 81),
                  (55, 43, 43), (19, 98, 98), (2, 286, 286), (114, 6, 6)):
    taraweeh(s, a0, a1, f't_{s:03d}_{a0:03d}_{a1:03d}')
for s, a in ((1, 7), (39, 1), (88, 1), (2, 81), (55, 43)):
    studio(s, a, f's_{s:03d}_{a:03d}')
