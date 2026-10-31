#!/usr/bin/env python3
"""Writes the audio mirror's voices.json from the app's own voice list.

Every recording in `reciters` (lib/data/fatiha_data.dart) with the
address of every file the app can ask its host for, and of every
published verse table it reads beside a surah file. The mirror job
(Mulhimfy/ayahreel-audio, mirror.yml) copies exactly these, so the
app can be served the same bytes when a host is down (see
lib/data/audio_mirror.dart).

Only public addresses go in it. Our own timing (OwnTiming tables, the
word timing) is never mirrored: those voices list no table here, and
the app keeps reading ours from the key-gated Worker.

    python3 tool/audio_mirror/manifest.py > voices.json
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA = (ROOT / 'lib/data/fatiha_data.dart').read_text(encoding='utf-8')
MODELS = (ROOT / 'lib/data/models.dart').read_text(encoding='utf-8')
INDEX = (ROOT / 'lib/data/surah_index.dart').read_text(encoding='utf-8')


def const(name):
    m = re.search(r"static const %s = '([^']+)';" % name, MODELS)
    if not m:
        sys.exit(f'models.dart: no {name}')
    return m.group(1)


HOSTS = {
    'everyAyah': const('everyAyahHost'),
    'tarteel': const('tarteelHost'),
    'ksu': const('ksuHost'),
}
MP3QURAN_API = re.search(
    r"class Mp3QuranTiming[\s\S]*?static const api = '([^']+)'", MODELS).group(1)
QUL_API = re.search(
    r"class QulTiming[\s\S]*?static const api = '([^']+)'", MODELS).group(1)

counts = [int(n) for n in re.findall(r'ayahCount: (\d+)', INDEX)]
if len(counts) != 114 or sum(counts) != 6236:
    sys.exit(f'surah_index.dart: {len(counts)} surahs, {sum(counts)} verses')

body = re.search(r'^const reciters = <Reciter>\[\n([\s\S]*?)^\];', DATA, re.M)
if not body:
    sys.exit('fatiha_data.dart: no reciters list')
blocks = re.split(r'^  Reciter\(\n', body.group(1), flags=re.M)[1:]

voices = []
for b in blocks:
    vid = re.search(r"^    id: '([^']+)',", b, re.M).group(1)
    ayah = re.search(r"source: AyahFiles\.(\w+)\('([^']+)'\)", b)
    if ayah:
        kind, folder = ayah.groups()
        voices.append({
            'id': vid,
            'kind': 'ayah',
            'base': f'{HOSTS[kind]}/{folder}',
        })
        continue
    surah = re.search(r"source: SurahFiles\(\s*'([^']+)'", b)
    if not surah:
        if 'OwnAudio' in b:
            continue
        sys.exit(f'{vid}: unknown source')
    base = surah.group(1)
    padded = 'padded: false' not in b
    missing = set()
    m = re.search(r'missing: \{([\d, ]*)\}', b)
    if m:
        missing = {int(x) for x in m.group(1).split(',') if x.strip()}
    elsewhere = {}
    m = re.search(r'elsewhere: \{([\s\S]*?)\n      \},', b)
    if m:
        for s, u in re.findall(r"(\d+): '([^']+)'", m.group(1)):
            elsewhere[int(s)] = u
    files = {}
    for s in range(1, 115):
        if s in missing:
            continue
        name = f'{s:03d}' if padded else f'{s}'
        files[f'{s:03d}'] = elsewhere.get(s, f'{base}/{name}.mp3')
    t = re.search(r'timing: (Mp3QuranTiming|QulTiming|OwnTiming)\(([^)]*)\)', b)
    if not t:
        sys.exit(f'{vid}: no timing')
    timing = None
    tables = {}
    if t.group(1) == 'Mp3QuranTiming':
        read = int(t.group(2))
        timing = {'kind': 'mp3quran', 'read': read}
        for s in range(1, 115):
            if s not in missing:
                tables[f'{s:03d}'] = f'{MP3QURAN_API}?surah={s}&read={read}'
    elif t.group(1) == 'QulTiming':
        rec = int(t.group(2))
        timing = {'kind': 'qul', 'recitation': rec}
        for s in range(1, 115):
            if s not in missing:
                c = counts[s - 1]
                tables[f'{s:03d}'] = (f'{QUL_API}/{rec}?surah={s}'
                                      f'&from=1&to={c}&per_page={c}')
    voices.append({
        'id': vid,
        'kind': 'surah',
        'files': files,
        'timing': timing,
        'tables': tables,
    })

ids = [v['id'] for v in voices]
if len(set(ids)) != len(ids):
    sys.exit('duplicate voice ids')
want = len(re.findall(r'^  Reciter\(\n', body.group(1), flags=re.M))
if len(voices) != want:
    sys.exit(f'{len(voices)} voices parsed of {want}')

json.dump({'v': 1, 'counts': counts, 'voices': voices}, sys.stdout,
          ensure_ascii=False, indent=1)
sys.stdout.write('\n')
