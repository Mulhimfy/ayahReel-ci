"""Builds assets/quran_search.json: the whole Quran's Uthmani text, one
list of verses per surah, so the surah picker can search by the words
of a verse without the network.

The text is the same QPC Uthmani text QuranTextService serves, fetched
from quran.com a surah at a time and run through the same cleaning it
applies (circle marks dropped, mirrored iqlab meems dropped, the
leading Basmala taken off the first verse of every surah but Al-Fatiha
and At-Tawbah), so what a search shows is letter for letter what a
reel renders.

    python tool/quran_search_index.py

Re-run only when the source text changes; the file is committed.
"""

import json
import sys
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from quran_verses import clean_arabic  # noqa: E402

CHAPTER = "https://api.quran.com/api/v4/quran/verses/uthmani?chapter_number={n}"
OUT = Path(__file__).parent.parent / "assets" / "quran_search.json"


def fetch(url: str) -> dict:
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (AyahReel index builder)"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def main() -> None:
    surahs: dict[str, list[str]] = {}
    total = 0
    for n in range(1, 115):
        verses = fetch(CHAPTER.format(n=n))["verses"]
        out = []
        for v in verses:
            surah, ayah = (int(x) for x in v["verse_key"].split(":"))
            assert surah == n
            out.append(clean_arabic(surah, ayah, v["text_uthmani"]))
        assert [i + 1 for i in range(len(out))] == [int(v["verse_key"].split(":")[1]) for v in verses]
        surahs[str(n)] = out
        total += len(out)
        print(f"surah {n}: {len(out)} verses", file=sys.stderr)
    assert total == 6236, total
    OUT.write_text(json.dumps(surahs, ensure_ascii=False, separators=(",", ":")), encoding="utf-8", newline="\n")
    print(f"wrote {OUT} ({OUT.stat().st_size // 1024} KB, {total} verses)")


if __name__ == "__main__":
    main()
