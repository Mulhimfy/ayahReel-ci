#!/usr/bin/env python3
"""Scratch, runner only: a first look at every candidate recording of a
voice the app has — is it the voice's own recording again, or another
performance? — and the calibration pairs in full.

  python3 tool/voices_scratch/screen.py calib
  python3 tool/voices_scratch/screen.py screen <shard> <of>
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
# Verse 2 of 22 surahs spread over the mushaf.
QUICK = [(s, 2) for s in (1, 2, 3, 6, 10, 12, 18, 19, 20, 24, 33, 36, 40, 50,
                          55, 56, 67, 71, 78, 89, 100, 112)]

EA = 'https://everyayah.com/data'
KSU = 'https://quran.ksu.edu.sa/ayat/mp3'
TA = 'https://audio-cdn.tarteel.ai/quran'
QC = 'https://audio.qurancdn.com'
MQ = 'https://cdn.mp3quran.net/audio'
QA = 'https://download.quranicaudio.com/quran'
QS = 'https://audio-cdn.tarteel.ai/quran/surah'


def ayah(base):
    return f'ayah {base}'


def mq(path, read):
    return f'surah {MQ}/{path} SSS mp3quran {read}'


def qul(base, rid, pad='SSS'):
    return f'surah {base} {pad} qul {rid}'


# (voice, candidate, label)
CANDS = [
    # EveryAyah folders the app doesn't play.
    ('alafasy', ayah(f'{EA}/Alafasy_64kbps'), 'EA Alafasy_64kbps'),
    ('abdulbasit', ayah(f'{EA}/AbdulSamad_64kbps_QuranExplorer.Com'), 'EA AbdulSamad QE'),
    ('abdulbasit_mujawwad', ayah(f'{EA}/AbdulSamad_64kbps_QuranExplorer.Com'), 'EA AbdulSamad QE'),
    ('basfar', ayah(f'{EA}/Abdullah_Basfar_64kbps'), 'EA Basfar_64'),
    ('sudais', ayah(f'{EA}/Abdurrahmaan_As-Sudais_64kbps'), 'EA Sudais_64'),
    ('shatri', ayah(f'{EA}/Abu_Bakr_Ash-Shaatree_64kbps'), 'EA Shaatree_64'),
    ('ajmi', ayah(f'{EA}/Ahmed_ibn_Ali_al-Ajamy_64kbps_QuranExplorer.Com'), 'EA Ajamy QE 64'),
    ('ajmi', ayah(f'{EA}/Ahmed_ibn_Ali_al-Ajamy_128kbps_ketaballah.net'), 'EA Ajamy ketaballah 128'),
    ('rifai', ayah(f'{EA}/Hani_Rifai_64kbps'), 'EA Hani_Rifai_64'),
    ('husary_mujawwad', ayah(f'{EA}/Husary_Mujawwad_64kbps'), 'EA Husary_Mujawwad_64'),
    ('hudhaify', ayah(f'{EA}/Hudhaify_64kbps'), 'EA Hudhaify_64'),
    ('akhdar', ayah(f'{EA}/Ibrahim_Akhdar_64kbps'), 'EA Ibrahim_Akhdar_64'),
    ('muaiqly', ayah(f'{EA}/Maher_AlMuaiqly_64kbps'), 'EA Maher_64'),
    ('minshawi_mujawwad', ayah(f'{EA}/Minshawy_Mujawwad_64kbps'), 'EA Minshawy_Mujawwad_64'),
    ('tablawi', ayah(f'{EA}/Mohammad_al_Tablaway_64kbps'), 'EA Tablaway_64'),
    ('ayyub', ayah(f'{EA}/Muhammad_Ayyoub_64kbps'), 'EA Ayyoub_64'),
    ('jibreel', ayah(f'{EA}/Muhammad_Jibreel_64kbps'), 'EA Jibreel_64'),
    ('shuraym', ayah(f'{EA}/Saood_ash-Shuraym_64kbps'), 'EA Shuraym_64'),
    ('husary', ayah(f'{EA}/Husary_Muallim_128kbps'), 'EA Husary_Muallim'),
    # King Saud University.
    ('husary', ayah(f'{KSU}/husary_qasr_64kbps'), 'KSU husary_qasr'),
    ('abdulbasit_mujawwad', ayah(f'{KSU}/AbdulSamad_64kbps'), 'KSU AbdulSamad_64'),
    ('abdulbasit', ayah(f'{KSU}/AbdulSamad_64kbps'), 'KSU AbdulSamad_64'),
    ('tunaiji', ayah(f'{KSU}/tunaiji_64kbps'), 'KSU tunaiji_64'),
    ('tunaiji', ayah(f'{KSU}/khaleefa_128kbps'), 'KSU khaleefa_128'),
    ('tunaiji', ayah(f'{KSU}/khaleefa_96kbps'), 'KSU khaleefa_96'),
    ('minshawi', ayah(f'{KSU}/Minshawy_Teacher_128kbps'), 'KSU Minshawy_Teacher'),
    ('ajmi', ayah(f'{KSU}/Ahmed_ibn_Ali_al-Ajamy_64kbps'), 'KSU Ajamy_64'),
    ('muaiqly', ayah(f'{KSU}/Maher_AlMuaiqly_64kbps'), 'KSU Maher_64'),
    ('salamah', ayah(f'{KSU}/Yaser_Salamah_128kbps'), 'KSU Salamah_128'),
    ('dussary', ayah(f'{KSU}/Yasser_Ad-Dussary_128kbps'), 'KSU Dussary_128'),
    ('qatami', ayah(f'{KSU}/Nasser_Alqatami_128kbps'), 'KSU Qatami_128'),
    ('abdulkareem', ayah(f'{KSU}/Muhammad_AbdulKareem_128kbps'), 'KSU AbdulKareem_128'),
    ('qasim', ayah(f'{KSU}/Muhsin_Al_Qasim_192kbps'), 'KSU Qasim_192'),
    ('juhani', ayah(f'{KSU}/Abdullaah_3awwaad_Al-Juhaynee_128kbps'), 'KSU Juhani_128'),
    ('minshawi', ayah(f'{KSU}/Minshawy_Murattal_128kbps'), 'KSU Minshawy_128'),
    ('rifai', ayah(f'{KSU}/Hani_Rifai_192kbps'), 'KSU Rifai_192'),
    # Tarteel's per-ayah sets.
    ('muaiqly', ayah(f'{TA}/maherAlMuaiqly'), 'TA maherAlMuaiqly'),
    ('abdulbasit_mujawwad', ayah(f'{TA}/abdulBasitMujawwad'), 'TA abdulBasitMujawwad'),
    ('abdulbasit', ayah(f'{TA}/abdulBasitMurattal'), 'TA abdulBasitMurattal'),
    ('sudais', ayah(f'{TA}/abdulrahmanAlSudais'), 'TA abdulrahmanAlSudais'),
    ('shatri', ayah(f'{TA}/abuBakrAlShatri'), 'TA abuBakrAlShatri'),
    ('alafasy', ayah(f'{TA}/alafasy'), 'TA alafasy'),
    ('ghamdi', ayah(f'{TA}/ghamadi'), 'TA ghamadi'),
    ('husary', ayah(f'{TA}/husary'), 'TA husary'),
    ('husary_mujawwad', ayah(f'{TA}/husaryMujawwad'), 'TA husaryMujawwad'),
    ('tunaiji', ayah(f'{TA}/khalifaAlTunaiji'), 'TA khalifaAlTunaiji'),
    ('minshawi', ayah(f'{TA}/minshawyMurattal'), 'TA minshawyMurattal'),
    ('shuraym', ayah(f'{TA}/saudAlShuraim'), 'TA saudAlShuraim'),
    ('dussary', ayah(f'{TA}/yasserAlDosari'), 'TA yasserAlDosari'),
    # quran.com's per-ayah sets.
    ('sudais', ayah(f'{QC}/Sudais/mp3'), 'QC Sudais'),
    ('rifai', ayah(f'{QC}/Rifai/mp3'), 'QC Rifai'),
    ('shuraym', ayah(f'{QC}/Shuraym/mp3'), 'QC Shuraym'),
    ('shatri', ayah(f'{QC}/Shatri/mp3'), 'QC Shatri'),
    ('alafasy', ayah(f'{QC}/Alafasy/mp3'), 'QC Alafasy'),
    ('abdulbasit', ayah(f'{QC}/AbdulBaset/Murattal/mp3'), 'QC AbdulBaset Murattal'),
    ('abdulbasit_mujawwad', ayah(f'{QC}/AbdulBaset/Mujawwad/mp3'), 'QC AbdulBaset Mujawwad'),
    ('minshawi', ayah(f'{QC}/Minshawi/Murattal/mp3'), 'QC Minshawi Murattal'),
    ('minshawi_mujawwad', ayah(f'{QC}/Minshawi/Mujawwad/mp3'), 'QC Minshawi Mujawwad'),
    # mp3quran, with its tables.
    ('alafasy', mq('mishary-alafasy/r1', 123), 'MQ 123'),
    ('husary', mq('mahmoud-husary/r1', 118), 'MQ 118'),
    ('husary_mujawwad', mq('mahmoud-husary/r2', 119), 'MQ 119'),
    ('abdulbasit', mq('abdulbasit-abdulsamad/r3', 53), 'MQ 53'),
    ('abdulbasit_mujawwad', mq('abdulbasit-abdulsamad/r1', 51), 'MQ 51'),
    ('minshawi', mq('muhammad-minshawi/r1', 112), 'MQ 112'),
    ('sudais', mq('abdulrahman-sudais/r1', 54), 'MQ 54'),
    ('shuraym', mq('saud-shuraim/r1', 31), 'MQ 31'),
    ('hudhaify', mq('ali-hudhaifi/r1', 74), 'MQ 74'),
    ('dussary', mq('yasser-dosari/r1', 92), 'MQ 92'),
    ('shatri', mq('abubakr-shatri/r1', 4), 'MQ 4'),
    ('ayyub', mq('muhammad-ayyub/r1', 109), 'MQ 109'),
    ('ajmi', mq('ahmad-ajmi/r1', 5), 'MQ 5'),
    ('qatami', mq('nasser-qatami/r1', 86), 'MQ 86'),
    ('qasim', mq('abdulmohsen-qasim/r1', 67), 'MQ 67'),
    ('juhani', mq('abdullah-juhani/r1', 62), 'MQ 62'),
    ('budair', mq('salah-budair/r1', 43), 'MQ 43'),
    ('rifai', mq('hani-rifai/r1', 89), 'MQ 89'),
    ('tablawi', mq('muhammad-tablawi/r1', 106), 'MQ 106'),
    ('basfar', mq('abdullah-basfar/r1', 60), 'MQ 60'),
    ('bukhatir', mq('salah-bukhatir/r1', 46), 'MQ 46'),
    ('qahtani', mq('khalid-qahtani/r1', 21), 'MQ 21'),
    ('matrood', mq('abdullah-matrood/r1', 59), 'MQ 59'),
    ('neana', mq('ahmad-naina/r1', 9), 'MQ 9'),
    ('alaqimy', mq('akram-alaqmi/r1', 10), 'MQ 10'),
    ('suesy', mq('ali-souissi/r1', 77), 'MQ 77'),
    ('abdulkareem', mq('muhammad-abdulkareem/r1', 115), 'MQ 115'),
    ('sahl_yassin', mq('sahl-yassin/r1', 32), 'MQ 32'),
    ('jaber', mq('ali-jaber/r1', 76), 'MQ 76'),
    ('abbad', mq('fares-abbad/r1', 81), 'MQ 81'),
    ('tunaiji', mq('khalifa-tunaiji/r1', 24), 'MQ 24'),
    ('nufais', mq('ahmad-nufais/r1', 259), 'MQ 259'),
    # QUL's surah recitations with tables.
    ('abdulbasit_mujawwad', qul(f'{QS}/abdulBasit/mujawwad/mp3', 1), 'QUL 1'),
    ('abdulbasit', qul(f'{QS}/abdulBasit/murattal/mp3', 2), 'QUL 2'),
    ('sudais', qul(f'{QS}/abdulrahmanAlSudais/murattal/mp3', 3), 'QUL 3'),
    ('shatri', qul(f'{QS}/abuBakrAlShatri/murattal/mp3', 4), 'QUL 4'),
    ('rifai', qul(f'{QS}/haniarRifai/murattal/mp3', 5), 'QUL 5'),
    ('husary', qul(f'{QS}/husary/murattal/mp3', 6), 'QUL 6'),
    ('alafasy', qul(f'{QS}/alafasy/murattal/mp3', 7), 'QUL 7'),
    ('minshawi_mujawwad', qul(f'{QS}/minshawy/mujawwad/mp3', 8), 'QUL 8'),
    ('minshawi', qul(f'{QS}/minshawy/murattal/mp3', 9), 'QUL 9'),
    ('shuraym', qul(f'{QS}/saudAlShuraim/murattal/mp3', 10), 'QUL 10'),
    ('qasim', qul(f'{QA}/abdul_muhsin_alqasim', 11), 'QUL 11'),
    ('husary', qul(f'{QA}/mahmood_khaleel_al-husaree_iza3a', 122), 'QUL 122'),
    ('sahl_yassin', qul(f'{QA}/sahl_yaaseen', 17), 'QUL 17'),
    ('bukhatir', qul(f'{QA}/salaah_bukhaatir', 18), 'QUL 18'),
    ('ajmi', qul(f'{QA}/ahmed_ibn_3ali_al-3ajamy', 19), 'QUL 19'),
    ('budair', qul(f'{QA}/salahbudair', 43), 'QUL 43'),
    ('alili', qul(f'{QA}/aziz_alili', 44), 'QUL 44'),
    ('muaiqly', qul(f'{QS}/maherAlMuaiqly/murattal/mp3', 65), 'QUL 65'),
    ('muaiqly', qul(f'{QA}/maher_almu3aiqly/year1440', 159), 'QUL 159'),
    ('mustafa_ismail', qul(f'{QA}/mostafa_ismaeel', 88), 'QUL 88'),
    ('tablawi', qul(f'{QA}/mohammad_altablawi', 91), 'QUL 91'),
    ('alafasy', qul(f'{QA}/mishaari_california', 95), 'QUL 95'),
    ('dussary', qul(f'{QA}/yasser_ad-dussary', 97), 'QUL 97'),
    ('qatami', qul(f'{QA}/nasser_bin_ali_alqatami', 104), 'QUL 104'),
    ('matrood', qul(f'{QA}/abdullah_matroud', 124), 'QUL 124'),
    ('neana', qul(f'{QA}/ahmad_nauina', 126), 'QUL 126'),
    ('alaqimy', qul(f'{QA}/akram_al_alaqmi', 127), 'QUL 127'),
    ('suesy', qul(f'{QA}/ali_hajjaj_alsouasi', 128), 'QUL 128'),
    ('jaber', qul(f'{QA}/ali_jaber', 158), 'QUL 158'),
    ('balilah', qul(f'{QA}/bandar_baleela/complete', 160), 'QUL 160'),
    ('juhani', qul(f'{QA}/abdullaah_3awwaad_al-juhaynee', 162), 'QUL 162'),
    ('basfar', qul(f'{QA}/abdullaah_basfar', 163), 'QUL 163'),
    ('jibreel', qul(f'{QA}/muhammad_jibreel/complete', 169), 'QUL 169'),
    ('jaleel', qul('https://download.quranicaudio.com/qdc/khalid_jalil/murattal/mp3', 170, 'S'), 'QUL 170'),
    ('alafasy', qul('https://download.quranicaudio.com/qdc/mishari_al_afasy/streaming/mp3', 173, 'S'), 'QUL 173'),
    ('nufais', qul(f'{QS}/alnufais/murattal/mp3', 175), 'QUL 175'),
]


def fmt(r):
    """The candidate's sound: kbps and rate of a file, and whether it is
    constant-bitrate (surah files must be)."""
    try:
        if r['kind'] == 'surah':
            lay = vr.layout(vr.surah_url(r, 2))
            return dict(kbps=lay.get('kbps'), rate=lay.get('rate'),
                        vbr=lay.get('vbr'), ok=lay.get('ok'), why=lay.get('why'))
        st, hdr, b = vr._get(f"{r['base']}/002255.mp3", timeout=60)
        info = vr.probe(b) if st == 200 else {}
        s = (info.get('streams') or [{}])[0]
        return dict(status=st, kbps=int(s.get('bit_rate', 0) or 0) // 1000,
                    rate=s.get('sample_rate'))
    except Exception as e:  # noqa: BLE001
        return dict(error=str(e)[:200])


def screen(shard, of):
    model = vr.model_ms()
    apps = vr.app_reciters()
    by = {r['id']: r for r in apps}
    cands = [c for i, c in enumerate(CANDS) if i % of == shard]
    out = []

    def one(c):
        vid, spec, label = c
        t0 = time.time()
        try:
            ra = vr.recording(spec, apps)
            res = vr.compare(ra, by[vid], model, sample=QUICK)
            res['format'] = fmt(ra)
        except Exception as e:  # noqa: BLE001
            res = dict(error=f'{e!r}', tb=traceback.format_exc()[-800:])
        res.update(voice=vid, spec=spec, label=label, secs=round(time.time() - t0))
        print(f"{vid:<20} {label:<26} n={res.get('verses')} wave="
              f"{res.get('wave_median')}/{res.get('wave_max')} same={res.get('wave_same')}"
              f" dur={res.get('dur_ratio')}±{res.get('dur_spread')} close={res.get('dur_close')}"
              f" env={res.get('env_corr')} fail={res.get('failed')} fmt={res.get('format')}"
              f" {res.get('error', '')[:200]} ({res['secs']}s)", flush=True)
        return res
    with ThreadPoolExecutor(3) as ex:
        out = list(ex.map(one, cands))
    os.makedirs(OUT, exist_ok=True)
    json.dump(out, open(os.path.join(OUT, f'screen_{shard}.json'), 'w'),
              ensure_ascii=False, indent=1)


def calib():
    model = vr.model_ms()
    res = vr.calibrate(model)
    os.makedirs(OUT, exist_ok=True)
    json.dump(res, open(os.path.join(OUT, 'calibration.json'), 'w'),
              ensure_ascii=False, indent=1)


if __name__ == '__main__':
    if sys.argv[1] == 'calib':
        calib()
    else:
        screen(int(sys.argv[2]), int(sys.argv[3]))
