#!/usr/bin/env python3
"""Scratch, runner only: the candidates that are not their voice's own
recording — compared with each other and with the voice's other style,
in full against the voice, and checked as voices of their own.

  python3 tool/voices_scratch/stage2.py pairs|full|check <shard> <of>
"""
import json
import os
import sys
import time
import traceback
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.join(os.getcwd(), 'tool'))
import verify_reciters as vr  # noqa: E402

OUT = os.path.join(os.getcwd(), 'out')
QUICK = [(s, 2) for s in (1, 2, 3, 6, 10, 12, 18, 19, 20, 24, 33, 36, 40, 50,
                          55, 56, 67, 71, 78, 89, 100, 112)]
MQ = 'https://cdn.mp3quran.net/audio'
QA = 'https://download.quranicaudio.com/quran'
QS = 'https://audio-cdn.tarteel.ai/quran/surah'
KSU = 'https://quran.ksu.edu.sa/ayat/mp3'

C = {
    'alafasy_173': f'surah https://download.quranicaudio.com/qdc/mishari_al_afasy/streaming/mp3 S qul 173',
    'alafasy_95': f'surah {QA}/mishaari_california SSS qul 95',
    'basfar_mq60': f'surah {MQ}/abdullah-basfar/r1 SSS mp3quran 60',
    'basfar_163': f'surah {QA}/abdullaah_basfar SSS qul 163',
    'budair_mq43': f'surah {MQ}/salah-budair/r1 SSS mp3quran 43',
    'husary_qasr': f'ayah {KSU}/husary_qasr_64kbps',
    'husary_122': f'surah {QA}/mahmood_khaleel_al-husaree_iza3a SSS qul 122',
    'matrood_mq59': f'surah {MQ}/abdullah-matrood/r1 SSS mp3quran 59',
    'muaiqly_159': f'surah {QA}/maher_almu3aiqly/year1440 SSS qul 159',
    'muaiqly_65': f'surah {QS}/maherAlMuaiqly/murattal/mp3 SSS qul 65',
    'sudais_mq54': f'surah {MQ}/abdulrahman-sudais/r1 SSS mp3quran 54',
    'hudhaify_mq74': f'surah {MQ}/ali-hudhaifi/r1 SSS mp3quran 74',
    'ayyub_mq109': f'surah {MQ}/muhammad-ayyub/r1 SSS mp3quran 109',
    'mustafa_88': f'surah {QA}/mostafa_ismaeel SSS qul 88',
}
VOICE = {'alafasy_173': 'alafasy', 'alafasy_95': 'alafasy', 'basfar_mq60': 'basfar',
         'basfar_163': 'basfar', 'budair_mq43': 'budair', 'husary_qasr': 'husary',
         'husary_122': 'husary', 'matrood_mq59': 'matrood', 'muaiqly_159': 'muaiqly',
         'muaiqly_65': 'muaiqly', 'sudais_mq54': 'sudais', 'hudhaify_mq74': 'hudhaify',
         'ayyub_mq109': 'ayyub', 'mustafa_88': 'mustafa_ismail'}
PAIRS = [
    ('alafasy_173', 'alafasy_95'), ('basfar_mq60', 'basfar_163'),
    ('husary_qasr', 'husary_122'), ('husary_qasr', 'husary_mujawwad'),
    ('husary_122', 'husary_mujawwad'), ('muaiqly_159', 'muaiqly_65'),
    ('muaiqly_159', 'muaiqly_mujawwad'), ('muaiqly_65', 'muaiqly_mujawwad'),
    ('sudais_mq54', 'sudais'), ('hudhaify_mq74', 'hudhaify'),
]


def spec(k, apps):
    return vr.recording(C.get(k, k), apps)


def detail(ra, rb, sample):
    """compare(), verse by verse."""
    sr = vr.XRATE // 1000
    rows = []

    def one(sa_):
        s, a = sa_
        try:
            pa, ea, wa = vr.clip(ra, s, a)
            pb, eb, wb = vr.clip(rb, s, a)
        except Exception as e:  # noqa: BLE001
            return dict(key=f'{s}:{a}', error=str(e)[:120])
        sa, sb = vr.sound(ea, wa), vr.sound(eb, wb)
        if not sa or not sb:
            return dict(key=f'{s}:{a}', error='no sound')
        found = vr.wave_match(pa[sa[0] * sr:sa[1] * sr], pb)
        return dict(key=f'{s}:{a}', da=sa[1] - sa[0], db=sb[1] - sb[0],
                    peaks=[round(x, 3) for x in found],
                    env=round(vr.env_corr(ea, sa, eb, sb) or 0, 3))
    with ThreadPoolExecutor(4) as ex:
        rows = list(ex.map(one, sample))
    return rows


def run(job, shard, of):
    model = vr.model_ms()
    apps = vr.app_reciters()
    os.makedirs(OUT, exist_ok=True)
    if job == 'pairs':
        todo = [p for i, p in enumerate(PAIRS) if i % of == shard]

        def one(p):
            a, b = p
            ra, rb = spec(a, apps), spec(b, apps)
            res = vr.compare(ra, rb, model)
            res['pair'] = p
            res['rows'] = detail(ra, rb, vr.distinct_sample(set(), model)) \
                if p[0] in ('sudais_mq54', 'hudhaify_mq74') else None
            print(f"{a:<14} {b:<16} n={res.get('verses')} fail={res.get('failed')} wave="
                  f"{res.get('wave_median')}/{res.get('wave_p90')}/{res.get('wave_max')} same={res.get('wave_same')}"
                  f" doubt={res.get('wave_doubt')} dur={res.get('dur_ratio')}±{res.get('dur_spread')}"
                  f" close={res.get('dur_close')} env={res.get('env_corr')} ok={res.get('ok')}"
                  f" why={res.get('why')}", flush=True)
            return res
        with ThreadPoolExecutor(2) as ex:
            out = list(ex.map(one, todo))
        json.dump(out, open(os.path.join(OUT, f'pairs_{shard}.json'), 'w'),
                  ensure_ascii=False, indent=1)
    elif job == 'full':
        keys = [k for i, k in enumerate(sorted(C)) if i % of == shard]

        def one(k):
            ra, rb = spec(k, apps), spec(VOICE[k], apps)
            t0 = time.time()
            try:
                res = vr.compare(ra, rb, model)
            except Exception as e:  # noqa: BLE001
                res = dict(error=repr(e), tb=traceback.format_exc()[-600:])
            res['key'] = k
            print(f"{k:<14} vs {VOICE[k]:<14} n={res.get('verses')} fail={res.get('failed')} wave="
                  f"{res.get('wave_median')}/{res.get('wave_p90')}/{res.get('wave_max')} same={res.get('wave_same')}"
                  f" doubt={res.get('wave_doubt')} dur={res.get('dur_ratio')}±{res.get('dur_spread')}"
                  f" close={res.get('dur_close')} env={res.get('env_corr')} ok={res.get('ok')}"
                  f" why={res.get('why')} ({round(time.time() - t0)}s)", flush=True)
            return res
        with ThreadPoolExecutor(2) as ex:
            out = list(ex.map(one, keys))
        json.dump(out, open(os.path.join(OUT, f'full_{shard}.json'), 'w'),
                  ensure_ascii=False, indent=1)
    else:
        keys = [k for i, k in enumerate(sorted(C)) if i % of == shard]
        out = {}
        for k in keys:
            r = spec(k, apps)
            r['id'] = k
            t0 = time.time()
            try:
                if r['kind'] == 'surah':
                    res = vr.check_surah_voice(r, model, print)
                else:
                    res = vr.check_ayah_voice(r, model, True, print)
            except Exception as e:  # noqa: BLE001
                res = dict(error=repr(e), tb=traceback.format_exc()[-600:])
            out[k] = res
            print(f"{k:<14} {'PASS' if not res.get('problems') and not res.get('error') else 'FAIL'}"
                  f" {res.get('kbps')}k/{res.get('rate')} pace={res.get('pace')}"
                  f" aligned={res.get('aligned_share')} shifted={res.get('shifted_share')}"
                  f" basmala1={res.get('basmala_in_verse1')} broken={res.get('broken')}"
                  f" problems={(res.get('problems') or [])[:4]} {res.get('error', '')}"
                  f" ({round(time.time() - t0)}s)", flush=True)
        json.dump(out, open(os.path.join(OUT, f'check_{shard}.json'), 'w'),
                  ensure_ascii=False, indent=1)


if __name__ == '__main__':
    run(sys.argv[1], int(sys.argv[2]), int(sys.argv[3]))
