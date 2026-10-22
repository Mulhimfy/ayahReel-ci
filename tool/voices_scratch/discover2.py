#!/usr/bin/env python3
"""Scratch, runner only: the second look — Al-Luhaidan anywhere, tables
mp3quran doesn't list, QUL recitations its list leaves out, and whether
the old mp3quran server URLs still answer."""
import json
import os
import re
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

OUT = os.path.join(os.getcwd(), 'out', 'discovery2')
UA = {'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) ayahreel-discover'}


def get(url, tries=3, timeout=40, headers=None):
    last = None
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers={**UA, **(headers or {})})
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.status, {k.lower(): v for k, v in r.headers.items()}, r.read()
        except urllib.error.HTTPError as e:
            if e.code in (400, 401, 403, 404, 410, 416, 422, 500, 503):
                try:
                    body = e.read()
                except Exception:  # noqa: BLE001
                    body = b''
                return e.code, {k.lower(): v for k, v in (e.headers or {}).items()}, body
            last = e
        except Exception as e:  # noqa: BLE001
            last = e
        time.sleep(1.0 * (i + 1))
    return None, {}, repr(last).encode()


def jget(url, **kw):
    st, hdr, b = get(url, **kw)
    try:
        return st, json.loads(b)
    except Exception:  # noqa: BLE001
        return st, {'_raw': b[:2000].decode('utf8', 'replace')}


def head(url):
    st, hdr, b = get(url, headers={'Range': 'bytes=0-3'}, tries=2)
    return dict(status=st, range=hdr.get('content-range'), type=hdr.get('content-type'),
                loc=hdr.get('location'), head=b[:4].hex() if st in (200, 206) else
                b[:120].decode('utf8', 'replace'))


def save(name, obj):
    os.makedirs(OUT, exist_ok=True)
    p = os.path.join(OUT, name + '.json')
    with open(p, 'w', encoding='utf8') as f:
        json.dump(obj, f, ensure_ascii=False, indent=0)
    print(f'saved {name}: {os.path.getsize(p)} bytes', flush=True)


def mp3quran_tables():
    """ayat_timing for moshafs the reads list leaves out."""
    ids = [107, 102, 103, 111, 152, 125, 121, 113, 114, 10924, 10912, 320, 286,
           10922, 21201, 1, 30]
    out = {}

    def one(i):
        return i, {s: jget(f'https://www.mp3quran.net/api/v3/ayat_timing?surah={s}&read={i}')
                   for s in (1, 2, 112)}
    with ThreadPoolExecutor(4) as ex:
        out = dict(ex.map(one, ids))
    for i, v in out.items():
        print('mp3quran timing', i, {s: (st, (len(b) if isinstance(b, list) else str(b)[:80]))
                                     for s, (st, b) in v.items()}, flush=True)
    save('mp3quran_tables', out)


def qul_hidden():
    base = 'https://qul.tarteel.ai/api/v1/audio'
    out = {}

    def one(rid):
        st, d = jget(f'{base}/surah_segments/{rid}?surah=112&from=1&to=4&per_page=4')
        au = d.get('audio') if isinstance(d, dict) else None
        seg = d.get('segments') if isinstance(d, dict) else None
        return rid, dict(status=st, audio=au, nseg=len(seg) if isinstance(seg, dict) else None,
                         keys=list(d.keys())[:12] if isinstance(d, dict) else None,
                         raw=None if au else str(d)[:300])
    with ThreadPoolExecutor(8) as ex:
        out = dict(ex.map(one, range(1, 421)))
    found = {k: v for k, v in out.items() if v['status'] == 200 and v.get('audio')}
    print('qul surah ids answering:', len(found), sorted(found), flush=True)
    for k, v in sorted(found.items()):
        print('  qul', k, v['nseg'], (v['audio'] or {}).get('url') if isinstance(v['audio'], dict)
              else v['audio'], flush=True)
    aout = {}

    def aone(rid):
        st, d = jget(f'{base}/ayah_segments/{rid}?surah=112&per_page=4')
        return rid, dict(status=st, raw=str(d)[:600])
    with ThreadPoolExecutor(8) as ex:
        aout = dict(ex.map(aone, range(1, 121)))
    afound = {k: v for k, v in aout.items() if v['status'] == 200 and 'audio_url' in v['raw']}
    print('qul ayah ids answering:', sorted(afound), flush=True)
    for k, v in sorted(afound.items()):
        m = re.search(r"audio_url': '([^']+)'", v['raw'])
        print('  qul ayah', k, m.group(1) if m else v['raw'][:200], flush=True)
    save('qul_hidden', dict(surah=out, ayah=aout))


def ksu():
    out = {}
    for u in ('https://quran.ksu.edu.sa/index.php?l=en',
              'https://quran.ksu.edu.sa/index.php?l=ar',
              'https://quran.ksu.edu.sa/m.php'):
        st, hdr, b = get(u)
        out[u] = [st, b.decode('utf8', 'replace')[:300000]]
    pages = ' '.join(v[1] for v in out.values())
    for src in sorted(set(re.findall(r'src="([^"]+\.js[^"]*)"', pages)))[:60]:
        u = src if src.startswith('http') else 'https://quran.ksu.edu.sa/' + src.lstrip('./')
        st, hdr, b = get(u)
        out[u] = [st, b.decode('utf8', 'replace')[:800000]]
    for u, (st, body) in out.items():
        hits = re.findall(r'.{80}(?:luhaidan|lohaidan|lhdan|لحيدان).{80}', body, re.I)
        kb = sorted(set(re.findall(r'[A-Za-z0-9_\-]+_\d+kbps', body)))
        print('ksu', u, st, len(body), 'luhaidan:', hits[:3], 'folders:', kb[:200], flush=True)
    save('ksu', out)


def tarteel_guesses():
    slugs = ['muhammadAlLuhaidan', 'mohammedAlLuhaidan', 'mohammadAlLuhaidan',
             'muhammadAlLohaidan', 'mohammedAlLohaidan', 'luhaidan', 'alLuhaidan',
             'muhammad_al_luhaidan', 'mohammed_al_luhaidan', 'muhammad_luhaidan',
             'mohamedAlLuhaidan', 'MuhammadAlLuhaidan', 'muhammadLuhaidan']
    out = {}
    urls = []
    for s in slugs:
        urls.append(f'https://audio-cdn.tarteel.ai/quran/{s}/001001.mp3')
        urls.append(f'https://audio-cdn.tarteel.ai/quran/surah/{s}/murattal/mp3/001.mp3')
    urls += [
        'https://download.quranicaudio.com/quran/muhammad_alhaidan/001.mp3',
        'https://download.quranicaudio.com/quran/muhammad_alhaidan//001.mp3',
        'https://cdn.mp3quran.net/audio/muhammad-luhaidan/r1/001.mp3',
        'https://server8.mp3quran.net/lhdan/001.mp3',
        'https://cdn.islamic.network/quran/audio-surah/128/ar.muhammadalluhaidan/1.mp3',
        'https://cdn.islamic.network/quran/audio/128/ar.muhammadalluhaidan/1.mp3',
        'https://cdn.islamic.network/quran/audio/64/ar.muhammadalluhaidan/1.mp3',
        'https://everyayah.com/data/Muhammad_Al_Luhaidan_128kbps/001001.mp3',
        'https://everyayah.com/data/Mohammed_Al_Luhaidan_128kbps/001001.mp3',
        'https://quran.ksu.edu.sa/ayat/mp3/Muhammad_Al_Luhaidan_128kbps/001001.mp3',
    ]
    with ThreadPoolExecutor(6) as ex:
        out = dict(zip(urls, ex.map(head, urls)))
    for u, v in out.items():
        print('probe', v['status'], v['range'], v['type'], u, flush=True)
    st, d = jget('https://api.alquran.cloud/v1/surah/1/ar.muhammadalluhaidan')
    out['alqurancloud_surah1'] = [st, str(d)[:3000]]
    print('alquran.cloud surah 1:', st, str(d)[:600], flush=True)
    save('luhaidan_probes', out)


def mp3quran_servers():
    """Do the app's old mp3quran URLs still answer, and is it the file
    the API now names?"""
    pairs = [
        ('https://server7.mp3quran.net/s_gmd/001.mp3',
         'https://cdn.mp3quran.net/audio/saad-ghamdi/r1/001.mp3'),
        ('https://server6.mp3quran.net/abkr/002.mp3',
         'https://cdn.mp3quran.net/audio/idrees-abkar/r1/002.mp3'),
        ('https://server16.mp3quran.net/a_turki/Rewayat-Hafs-A-n-Assem/112.mp3',
         'https://cdn.mp3quran.net/audio/abdulaziz-turki/r1/112.mp3'),
        ('https://server12.mp3quran.net/maher/Almusshaf-Al-Mojawwad/001.mp3',
         'https://cdn.mp3quran.net/audio/maher-muaiqly/r3/001.mp3'),
    ]
    out = {}
    for a, b in pairs:
        out[a] = head(a)
        out[b] = head(b)
        print('server', a, out[a], '|', b, out[b], flush=True)
    save('mp3quran_servers', out)


def qurancom():
    out = {}
    out['v4_chapter_reciters'] = jget('https://api.quran.com/api/v4/resources/chapter_reciters?language=en')
    print('v4 chapter reciters', out['v4_chapter_reciters'][0], str(out['v4_chapter_reciters'][1])[:400])
    save('qurancom2', out)


def main():
    for j in (mp3quran_tables, qul_hidden, ksu, tarteel_guesses, mp3quran_servers, qurancom):
        try:
            j()
        except Exception as e:  # noqa: BLE001
            print(f'{j.__name__} failed: {e!r}', flush=True)


if __name__ == '__main__':
    main()
