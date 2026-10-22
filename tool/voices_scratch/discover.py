#!/usr/bin/env python3
"""Scratch, runner only: dump every listing a recording could come from.

Writes out/discovery/*.json (one file per source) for offline analysis.
"""
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

OUT = os.path.join(os.getcwd(), 'out', 'discovery')
UA = {'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) ayahreel-discover'}


def get(url, tries=4, timeout=60, headers=None):
    last = None
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers={**UA, **(headers or {})})
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.status, dict(r.headers.items()), r.read()
        except urllib.error.HTTPError as e:
            if e.code in (400, 401, 403, 404, 410, 416, 422):
                try:
                    body = e.read()
                except Exception:  # noqa: BLE001
                    body = b''
                return e.code, dict(e.headers.items()) if e.headers else {}, body
            last = e
        except Exception as e:  # noqa: BLE001
            last = e
        time.sleep(1.0 * (i + 1))
    return None, {}, repr(last).encode()


def text(b):
    try:
        return b.decode('utf8')
    except Exception:  # noqa: BLE001
        return b.decode('latin1')


def jget(url, **kw):
    st, hdr, b = get(url, **kw)
    try:
        return st, json.loads(b)
    except Exception:  # noqa: BLE001
        return st, {'_raw': text(b)[:4000]}


def save(name, obj):
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, name + '.json'), 'w', encoding='utf8') as f:
        json.dump(obj, f, ensure_ascii=False, indent=0)
    print(f'saved {name}: {os.path.getsize(os.path.join(OUT, name + ".json"))} bytes',
          flush=True)


def mp3quran():
    out = {}
    for lang in ('eng', 'ar'):
        out[f'reciters_{lang}'] = jget(
            f'https://www.mp3quran.net/api/v3/reciters?language={lang}')
    out['moshaf_eng'] = jget('https://www.mp3quran.net/api/v3/moshaf?language=eng')
    out['moshaf_ar'] = jget('https://www.mp3quran.net/api/v3/moshaf?language=ar')
    out['riwayat_eng'] = jget('https://www.mp3quran.net/api/v3/riwayat?language=eng')
    out['reads'] = jget('https://www.mp3quran.net/api/v3/ayat_timing/reads')
    out['reads_ar'] = jget('https://www.mp3quran.net/api/v3/ayat_timing/reads?language=ar')
    out['reads_eng'] = jget('https://www.mp3quran.net/api/v3/ayat_timing/reads?language=eng')
    # Which surahs each read has a table for.
    reads = out['reads'][1] if isinstance(out['reads'][1], list) else []

    def soar(rd):
        return rd['id'], jget(f"https://www.mp3quran.net/api/v3/ayat_timing/soar?read={rd['id']}")
    with ThreadPoolExecutor(6) as ex:
        out['soar'] = dict(ex.map(soar, reads))
    save('mp3quran', out)


def qul():
    out = {}
    base = 'https://qul.tarteel.ai/api/v1/audio'
    for kind in ('surah_recitations', 'ayah_recitations'):
        pages = []
        for page in range(1, 30):
            st, d = jget(f'{base}/{kind}?page={page}&per_page=100')
            pages.append((st, d))
            if st != 200:
                break
            items = None
            if isinstance(d, dict):
                for k in ('recitations', 'data', 'items', 'results'):
                    if isinstance(d.get(k), list):
                        items = d[k]
                if items is None:
                    # Unknown shape: keep one page.
                    break
                if len(items) < 100:
                    break
            elif isinstance(d, list):
                if len(d) < 100:
                    break
            else:
                break
        out[kind] = pages
        # And unpaged, in case paging is ignored.
        out[kind + '_plain'] = jget(f'{base}/{kind}')
    save('qul_lists', out)

    # Every surah recitation's Al-Fatiha and Al-Ikhlas: where its audio
    # lives, and whether it has segments.
    ids = set()
    for kind in ('surah_recitations',):
        for st, d in out[kind] + [out[kind + '_plain']]:
            for m in re.finditer(r'"id":\s*(\d+)', json.dumps(d)):
                ids.add(int(m.group(1)))
    ids = sorted(i for i in ids if i < 2000)
    print('qul surah recitation ids:', len(ids), ids[:400], flush=True)

    def one(rid):
        return rid, {
            '1': jget(f'{base}/surah_segments/{rid}?surah=1&from=1&to=7&per_page=7'),
            '112': jget(f'{base}/surah_segments/{rid}?surah=112&from=1&to=4&per_page=4'),
        }
    with ThreadPoolExecutor(6) as ex:
        segs = dict(ex.map(one, ids))
    save('qul_surah_samples', segs)

    aids = set()
    for st, d in out['ayah_recitations'] + [out['ayah_recitations_plain']]:
        for m in re.finditer(r'"id":\s*(\d+)', json.dumps(d)):
            aids.add(int(m.group(1)))
    aids = sorted(i for i in aids if i < 2000)
    print('qul ayah recitation ids:', len(aids), aids[:400], flush=True)

    def aone(rid):
        return rid, {
            'rec': jget(f'{base}/ayah_recitations/{rid}?surah=112'),
            'seg': jget(f'{base}/ayah_segments/{rid}?surah=112&per_page=4'),
        }
    with ThreadPoolExecutor(6) as ex:
        asegs = dict(ex.map(aone, aids))
    save('qul_ayah_samples', asegs)


def everyayah():
    out = {}
    for u in ('https://everyayah.com/data/recitations.js',
              'https://everyayah.com/data/',
              'https://everyayah.com/recitations_ayat.html',
              'https://everyayah.com/recitations_pages.html',
              'https://everyayah.com/'):
        st, hdr, b = get(u)
        out[u] = [st, text(b)[:400000]]
    save('everyayah', out)


def ksu():
    out = {}
    for u in ('https://quran.ksu.edu.sa/ayat/',
              'https://quran.ksu.edu.sa/ayat/mp3/',
              'https://quran.ksu.edu.sa/ayat/?l=en',
              'https://quran.ksu.edu.sa/ayat/?pg=mp3',
              'https://quran.ksu.edu.sa/'):
        st, hdr, b = get(u)
        out[u] = [st, text(b)[:400000]]
    # Scripts the page loads, which may hold the reciter list.
    page = out['https://quran.ksu.edu.sa/ayat/'][1]
    for src in sorted(set(re.findall(r'src="([^"]+\.js[^"]*)"', page)))[:40]:
        u = src if src.startswith('http') else \
            'https://quran.ksu.edu.sa/ayat/' + src.lstrip('./')
        st, hdr, b = get(u)
        out[u] = [st, text(b)[:600000]]
    save('ksu', out)


def qurancom():
    out = {}
    out['qdc_reciters'] = jget('https://api.qurancdn.com/api/qdc/audio/reciters?locale=en')
    out['qdc_reciters_ar'] = jget('https://api.qurancdn.com/api/qdc/audio/reciters?locale=ar')
    out['v4_recitations'] = jget('https://api.quran.com/api/v4/resources/recitations?language=en')
    out['v4_chapter_reciters'] = jget('https://api.quran.com/api/v4/resources/chapter_reciters?language=en')
    ids = set()
    d = out['qdc_reciters'][1]
    for m in re.finditer(r'"id":\s*(\d+)', json.dumps(d)):
        ids.add(int(m.group(1)))
    d = out['v4_chapter_reciters'][1]
    for m in re.finditer(r'"id":\s*(\d+)', json.dumps(d)):
        ids.add(int(m.group(1)))
    ids = sorted(i for i in ids if i < 2000)

    def one(rid):
        return rid, jget(f'https://api.qurancdn.com/api/qdc/audio/reciters/{rid}'
                         f'/audio_files?chapter=112&segments=true')
    with ThreadPoolExecutor(6) as ex:
        out['qdc_112'] = dict(ex.map(one, ids))
    # v4 per-ayah recitations: a verse each, to see the host and path.
    rids = set()
    d = out['v4_recitations'][1]
    for m in re.finditer(r'"id":\s*(\d+)', json.dumps(d)):
        rids.add(int(m.group(1)))

    def vone(rid):
        return rid, jget(f'https://api.quran.com/api/v4/recitations/{rid}'
                         f'/by_chapter/112?per_page=4')
    with ThreadPoolExecutor(6) as ex:
        out['v4_112'] = dict(ex.map(vone, sorted(rids)))
    save('qurancom', out)


def quranicaudio():
    out = {}
    out['qaris'] = jget('https://quranicaudio.com/api/qaris')
    out['sections'] = jget('https://quranicaudio.com/api/sections')
    save('quranicaudio', out)


def alqurancloud():
    out = {}
    out['audio'] = jget('https://api.alquran.cloud/v1/edition?format=audio')
    save('alqurancloud', out)


def main():
    jobs = [mp3quran, qul, everyayah, ksu, qurancom, quranicaudio, alqurancloud]
    for j in jobs:
        try:
            j()
        except Exception as e:  # noqa: BLE001
            print(f'{j.__name__} failed: {e!r}', flush=True)
    # Al-Luhaidan anywhere.
    pat = re.compile(r'luhaidan|lohaidan|lehaidan|luhaydan|lhdan|lhidan|'
                     r'اللحيدان|لحيدان', re.I)
    for name in sorted(os.listdir(OUT)):
        s = open(os.path.join(OUT, name), encoding='utf8').read()
        for m in pat.finditer(s):
            print(f'LUHAIDAN {name}: ...{s[max(0, m.start() - 300):m.end() + 300]!r}...')


if __name__ == '__main__':
    main()
