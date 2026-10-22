"""Merge the published new scenes into AyahReel's catalog and posters.

python3 -I merge_scenes.py <repo> <manifest new_scenes.json> <built.json> <posters dir>
"""
import json
import os
import shutil
import sys

from PIL import Image

repo, manifest, built_p, posters = sys.argv[1:5]
BASE = 'https://github.com/Mulhimfy/ayah-reels-scenes/releases/download'


def dhash(path):
    im = Image.open(path).convert('L').resize((9, 8), Image.LANCZOS)
    px = list(im.get_flattened_data()) if hasattr(im, "get_flattened_data") else list(im.getdata())
    return sum(1 << i for i in range(64)
               if px[(i // 8) * 9 + i % 8] > px[(i // 8) * 9 + i % 8 + 1])


def dist(a, b):
    return bin(a ^ b).count('1')


cat_p = os.path.join(repo, 'assets/catalog.json')
cat = json.load(open(cat_p))
old_ids = {s['id'] for s in cat['scenes']}
thumbs = os.path.join(repo, 'assets/scene_thumbs')
old_hash = {}
for s in cat['scenes']:
    old_hash[s['id']] = (dhash(os.path.join(thumbs, s['id'] + '.jpg')), s['wide'])

man = json.load(open(manifest))
built = json.load(open(built_p))
score = {}
new, failed, dups = [], [], []
kept_hash = {}
for m in man:
    sid = m['id']
    b = built.get(sid)
    p = os.path.join(posters, sid + '.webp')
    if not b or 'bytes' not in b or not os.path.exists(p) or sid in old_ids:
        failed.append((sid, (b or {}).get('error', 'not built')))
        continue
    h = dhash(p)
    near = [k for k, (oh, ow) in old_hash.items() if ow == m['wide'] and dist(h, oh) <= 4]
    near += [k for k, (kh, kw) in kept_hash.items() if kw == m['wide'] and dist(h, kh) <= 4]
    if near:
        dups.append((sid, near[:3]))
        continue
    kept_hash[sid] = (h, m['wide'])
    new.append(dict(id=sid, tab=m['tab'], wide=m['wide'], video=m['video'],
                    ext='mp4' if m['video'] else 'jpg', bytes=b['bytes'],
                    grad=m['grad'], bundled=False,
                    release='v3' if m['video'] else 'v2', poster='webp'))

for n in new:
    shutil.copyfile(os.path.join(posters, n['id'] + '.webp'),
                    os.path.join(thumbs, n['id'] + '.webp'))
cat['releases'] = {'v2': f'{BASE}/v2', 'v3': f'{BASE}/v3'}
# Keep the keys in the order the app's loader reads them.
cat = {'version': cat['version'], 'baseUrl': cat['baseUrl'],
       'releases': cat['releases'], 'scenes': cat['scenes'] + new}
with open(cat_p, 'w') as f:
    json.dump(cat, f, separators=(',', ':'))
print(f'added {len(new)} ({sum(n["video"] for n in new)} clips); '
      f'not built {len(failed)}; near-duplicates left out {len(dups)}')
for d in dups[:40]:
    print('dup', d)
for f in failed[:40]:
    print('failed', f)
json.dump({'failed': failed, 'dups': dups},
          open(os.path.join(os.path.dirname(built_p), 'merge_report.json'), 'w'), indent=0)
