#!/usr/bin/env python3
"""Scratch, runner only: what a recording's own files say about it — the
ID3 tags (album, title, year, comment, artist) at the front and back of a
few files of each candidate."""
import json
import os
import sys

sys.path.insert(0, os.path.join(os.getcwd(), 'tool'))
import verify_reciters as vr  # noqa: E402


def syncsafe(b):
    return (b[0] & 127) << 21 | (b[1] & 127) << 14 | (b[2] & 127) << 7 | (b[3] & 127)


def text_of(data):
    if not data:
        return ''
    enc, body = data[0], data[1:]
    try:
        if enc == 0:
            s = body.decode('latin1')
        elif enc == 1:
            s = body.decode('utf-16')
        elif enc == 2:
            s = body.decode('utf-16-be')
        else:
            s = body.decode('utf8')
    except Exception:  # noqa: BLE001
        s = body.decode('latin1', 'replace')
    return s.replace('\x00', ' | ').strip(' |')


def id3v2(b):
    if b[:3] != b'ID3':
        return {}
    ver = b[3]
    size = syncsafe(b[6:10])
    out = {}
    i = 10
    end = min(len(b), 10 + size)
    while i + 10 <= end:
        fid = b[i:i + 4].decode('latin1', 'replace')
        if not fid.strip('\x00'):
            break
        fs = syncsafe(b[i + 4:i + 8]) if ver == 4 else int.from_bytes(b[i + 4:i + 8], 'big')
        data = b[i + 10:i + 10 + fs]
        i += 10 + fs
        if fid[0] == 'T' or fid in ('COMM', 'USLT', 'WXXX'):
            if fid == 'COMM' and len(data) > 4:
                data = data[:1] + data[4:]
            out.setdefault(fid, text_of(data)[:200])
    return out


def id3v1(b):
    if len(b) < 128 or b[-128:-125] != b'TAG':
        return {}
    t = b[-128:]
    f = lambda x: x.split(b'\x00')[0].decode('latin1', 'replace').strip()  # noqa: E731
    return dict(title=f(t[3:33]), artist=f(t[33:63]), album=f(t[63:93]),
                year=f(t[93:97]), comment=f(t[97:127]))


def tags(url):
    st, hdr, head = vr._get(url, {'Range': 'bytes=0-131071'})
    total = int(hdr.get('content-range', '/0').split('/')[-1] or 0)
    tail = b''
    if total > 128:
        st2, _, tail = vr._get(url, {'Range': f'bytes={total - 128}-{total - 1}'})
    return dict(status=st, v2=id3v2(head), v1=id3v1(tail))


def main(specs):
    out = {}
    apps = vr.app_reciters()
    for spec in specs:
        r = vr.recording(spec, apps)
        urls = ([vr.surah_url(r, s) for s in (1, 2, 36, 112)] if r['kind'] == 'surah'
                else [f"{r['base']}/{k}.mp3" for k in ('001001', '002255', '036001', '112001')])
        res = {}
        for u in urls:
            try:
                res[u] = tags(u)
            except Exception as e:  # noqa: BLE001
                res[u] = dict(error=str(e)[:200])
        out[spec] = res
        print(spec)
        for u, t in res.items():
            print('   ', u.rsplit('/', 1)[-1], json.dumps(t, ensure_ascii=False)[:600])
    os.makedirs('out', exist_ok=True)
    json.dump(out, open('out/meta.json', 'w'), ensure_ascii=False, indent=1)


if __name__ == '__main__':
    main([l.strip() for l in open(sys.argv[1]) if l.strip() and not l.startswith('#')])
