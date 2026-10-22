#!/usr/bin/env python3
"""The curated verse rotation — the home card's verse and the home-screen
widget's — fetched from the source and copied to every place that reads it.

    python3 tool/quran_verses.py fetch   # quran.com -> tool/quran_verses.json
    python3 tool/quran_verses.py gen     # json -> Dart, Android, iOS copies
    python3 tool/quran_verses.py check   # the copies agree with the json

tool/quran_verses.json is the one hand-edited file: the references, in
rotation order, each with a mood tag (neighbours should differ) and an
optional `excerpt` flag for a verse that is beloved but longer than a
card — its opening clause, up to the verse's own first pause mark, is
what the card and the widget show; the reel always carries the whole.

`fetch` fills in the Arabic and the translation from quran.com — the
same QPC Uthmani text and the same Saheeh International translation
QuranTextService serves, run through the same cleaning it applies
(circle marks and mirrored iqlab meems dropped, a leading Basmala
stripped off ayah 1, footnote markup removed) — so what the card and
the widget show is letter for letter what the reel renders. Nothing is
typed by hand.

`gen` writes the three copies the app reads:

    lib/data/quran_verses.g.dart               the Dart const list
    android/app/src/main/assets/quran_verses.json   the Android widget's
    ios/AyahWidget/quran_verses.json           the iOS widget's

The widgets compute their own verse from the date (see VerseSchedule on
each side) and never talk to the app, which is why they need their own
copy. test/quran_verses_sync_test.dart fails the build if any copy
drifts from the json, so the only way to change the list is here.
"""
import json
import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "tool" / "quran_verses.json"
DART_OUT = ROOT / "lib" / "data" / "quran_verses.g.dart"
ANDROID_OUT = ROOT / "android" / "app" / "src" / "main" / "assets" / "quran_verses.json"
IOS_OUT = ROOT / "ios" / "AyahWidget" / "quran_verses.json"
SURAH_INDEX = ROOT / "lib" / "data" / "surah_index.dart"

UTHMANI_ALL = "https://api.quran.com/api/v4/quran/verses/uthmani"
TRANSLATION_ALL = "https://api.quran.com/api/v4/quran/translations/{rid}"

# The editions the card can be shown in — the same list, and the same
# resource ids, as lib/data/verse_translation.dart. Every one of them
# was verified whole by tool/verify_translations.py before it was
# offered; nothing may be added here that has not passed that.
EDITIONS = {"en": 20, "ur": 234, "id": 33, "de": 27}

# The most words a card or a widget line can carry and still be read at
# a glance. Pause marks stand as their own tokens in the source text and
# are not counted.
MAX_WORDS = 14

PAUSE_MARKS = {chr(c) for c in range(0x06D6, 0x06DC)}  # ۖ ۗ ۘ ۙ ۚ ۛ
ARABIC_LETTER = re.compile(r"[ء-يٱ]")


# ---- the same cleaning QuranTextService applies -----------------------

def strip_circle_marks(text: str) -> str:
    out = "".join(c for c in text if ord(c) not in (0x06DD, 0x06DE, 0x06DF, 0x06E0))
    return re.sub(r"  +", " ", out).strip()


def drop_wrong_side_iqlab_meem(text: str) -> str:
    low, high = 0x06ED, 0x06E2
    fathatan, dammatan, kasratan = 0x064B, 0x064C, 0x064D
    out, prev = [], 0
    for ch in text:
        c = ord(ch)
        mirrored = (c == low and prev in (fathatan, dammatan)) or (c == high and prev == kasratan)
        if not mirrored:
            out.append(ch)
        prev = c
    return "".join(out)


def _letters(s: str) -> str:
    b = []
    for ch in s:
        c = ord(ch)
        if 0x064B <= c <= 0x065F:
            continue
        if c in (0x0670, 0x0640, 0x0653):
            continue
        b.append("ا" if c == 0x0671 else ch)
    return "".join(b)


def strip_leading_basmala(surah: int, ayah: int, text: str) -> str:
    if ayah != 1 or surah in (1, 9):
        return text
    words = text.split(" ")
    if len(words) < 5:
        return text
    if _letters(" ".join(words[:4])) != "بسم الله الرحمن الرحيم":
        return text
    return " ".join(words[4:])


def strip_footnote_markup(text: str) -> str:
    text = re.sub(r"<sup\b[^>]*>.*?</sup>", "", text, flags=re.S)
    text = re.sub(r"<[^>]*>", "", text)
    return re.sub(r"  +", " ", text).strip()


# Mirrors QuranTextService.normalizeSpaces, which exists because the
# non-English editions carry invisibles the English one does not: soft
# hyphens in the Indonesian, a hard line break in the German, no-break
# spaces in the Urdu. See that method for what each one does to a card.
DROPPED = {0x00AD, 0x200B, 0xFEFF}
TO_SPACE = {0x000A, 0x000D, 0x0009, 0x0085, 0x00A0, 0x202F, 0x2028, 0x2029}


def normalize_spaces(text: str) -> str:
    out = []
    for ch in text:
        c = ord(ch)
        if c in DROPPED:
            continue
        out.append(" " if c in TO_SPACE else ch)
    return re.sub(r"  +", " ", "".join(out)).strip()


def clean_arabic(surah: int, ayah: int, text: str) -> str:
    return strip_leading_basmala(surah, ayah, strip_circle_marks(drop_wrong_side_iqlab_meem(text.strip())))


# ---- helpers ----------------------------------------------------------

def parse_ref(ref: str):
    surah, rng = ref.split(":")
    if "-" in rng:
        a, b = rng.split("-")
    else:
        a = b = rng
    return int(surah), int(a), int(b)


def words(text: str) -> int:
    return sum(1 for t in text.split(" ") if ARABIC_LETTER.search(t))


def excerpt_of(text: str) -> str:
    """The opening clause: everything before the verse's first pause mark."""
    tokens = text.split(" ")
    for i, t in enumerate(tokens):
        if t in PAUSE_MARKS:
            return " ".join(tokens[:i])
    raise SystemExit(f"no pause mark to cut an excerpt at in: {text}")


def get_json(url: str):
    # The edge in front of the API turns away a bare urllib request
    # (403); an ordinary client user agent is all it wants.
    req = urllib.request.Request(
        url, headers={"User-Agent": "ayahreel-tool/1.0", "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def surah_names():
    """(english, arabic, ayahCount) per surah, from the app's own index."""
    src = SURAH_INDEX.read_text(encoding="utf-8")
    names = {}
    for m in re.finditer(
        r"SurahInfo\(number:\s*(\d+),\s*nameArabic:\s*'([^']*)',\s*nameEnglish:\s*(?:'([^']*)'|\"([^\"]*)\"),\s*ayahCount:\s*(\d+)\)",
        src,
    ):
        n = int(m.group(1))
        names[n] = (m.group(3) or m.group(4), m.group(2), int(m.group(5)))
    assert len(names) == 114, f"surah index parsed {len(names)} surahs"
    return names


def load():
    return json.loads(SOURCE.read_text(encoding="utf-8"))


def save(doc):
    SOURCE.write_text(json.dumps(doc, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")


def all_entries(doc):
    return [doc["jumuah"], *doc["verses"]]


# ---- commands ---------------------------------------------------------

def fetch():
    """Fill in the Arabic and every translation from quran.com.

    Fetched whole rather than a verse at a time: the rotation is 91
    entries and there are four editions, which was some 400 requests
    the old way and is five now. The translation endpoints return the
    6236 verses in mushaf order with no keys of their own, so they are
    paired with the Arabic by position — which is only safe because
    every edition here has been checked to return exactly 6236 in that
    order (tool/verify_translations.py). The pairing is re-checked
    below anyway, because a silent shift would mistranslate the card.
    """
    doc = load()
    names = surah_names()

    print("fetching the Arabic, whole …")
    arabic_rows = get_json(UTHMANI_ALL)["verses"]
    keys = [v["verse_key"] for v in arabic_rows]
    if len(arabic_rows) != 6236:
        raise SystemExit(f"Arabic returned {len(arabic_rows)} verses, expected 6236")
    arabic_by_key = {k: v["text_uthmani"] for k, v in zip(keys, arabic_rows)}

    translations_by_key = {}
    for code, rid in EDITIONS.items():
        print(f"fetching the {code} translation (resource {rid}) …")
        rows = get_json(TRANSLATION_ALL.format(rid=rid))["translations"]
        if len(rows) != len(arabic_rows):
            raise SystemExit(
                f"{code}: {len(rows)} translations against {len(arabic_rows)} verses")
        translations_by_key[code] = {k: r["text"] for k, r in zip(keys, rows)}

    for e in all_entries(doc):
        surah, a, b = parse_ref(e["ref"])
        arabic = []
        rendered = {code: [] for code in EDITIONS}
        for ayah in range(a, b + 1):
            key = f"{surah}:{ayah}"
            if key not in arabic_by_key:
                raise SystemExit(f"{key}: not in the source")
            arabic.append(clean_arabic(surah, ayah, arabic_by_key[key]))
            for code in EDITIONS:
                rendered[code].append(
                    normalize_spaces(strip_footnote_markup(translations_by_key[code][key])))
        e["arabic"] = " ".join(arabic)
        e["translations"] = {code: " ".join(rendered[code]) for code in EDITIONS}
        # The English stays where it was: the native widgets read it,
        # and they are not language-aware.
        e["translation"] = e["translations"]["en"]
        if e.get("excerpt"):
            e["shown"] = excerpt_of(e["arabic"])
        else:
            e.pop("shown", None)
        print(f"{e['ref']:>9}  {words(e.get('shown') or e['arabic']):2d} words  {names[surah][0]}")
    save(doc)
    validate(doc)


def validate(doc):
    names = surah_names()
    seen = set()
    problems = []
    for e in all_entries(doc):
        ref = e["ref"]
        surah, a, b = parse_ref(ref)
        if not (1 <= surah <= 114) or a < 1 or b < a or b > names[surah][2]:
            problems.append(f"{ref}: not a real verse")
        if ref in seen:
            problems.append(f"{ref}: listed twice")
        seen.add(ref)
        if not e.get("arabic") or not e.get("translation"):
            problems.append(f"{ref}: not fetched yet")
            continue
        shown = e.get("shown") or e["arabic"]
        if words(shown) > MAX_WORDS:
            problems.append(f"{ref}: {words(shown)} words shown, over {MAX_WORDS}")
        if e.get("excerpt") and not e["arabic"].startswith(e["shown"] + " "):
            problems.append(f"{ref}: excerpt is not the verse's opening")
        for ch in e["arabic"]:
            if ord(ch) in (0x06DD, 0x06DE, 0x06DF, 0x06E0):
                problems.append(f"{ref}: carries a circle mark")
                break
        if "<" in e["translation"]:
            problems.append(f"{ref}: translation carries markup")
        got = e.get("translations") or {}
        for code in EDITIONS:
            if not got.get(code):
                problems.append(f"{ref}: no {code} translation")
            elif "<" in got[code]:
                problems.append(f"{ref}: {code} translation carries markup")
            elif any(ord(c) in DROPPED | TO_SPACE for c in got[code]):
                problems.append(f"{ref}: {code} translation carries an invisible")
        if got.get("en") != e["translation"]:
            problems.append(f"{ref}: the native copy's translation is not the English one")
    rot = doc["verses"]
    if len(rot) != 90:
        problems.append(f"rotation holds {len(rot)} verses, not 90")
    for i in range(len(rot) - 1):
        if rot[i]["mood"] == rot[i + 1]["mood"]:
            print(f"note: {rot[i]['ref']} and {rot[i+1]['ref']} share a mood ({rot[i]['mood']})")
    if problems:
        raise SystemExit("\n".join(problems))
    print(f"ok: {len(rot)} verses in rotation + Jumu'ah, all verified")


def dart_str(s: str) -> str:
    return "'" + s.replace("\\", "\\\\").replace("'", "\\'") + "'"


def render_dart(doc) -> str:
    names = surah_names()

    def entry(e, indent="  "):
        surah, a, b = parse_ref(e["ref"])
        lines = [
            f"{indent}QuranVerse(",
            f"{indent}  surah: {surah},",
            f"{indent}  startAyah: {a},",
            f"{indent}  endAyah: {b},",
            f"{indent}  surahName: {dart_str(names[surah][0])},",
            f"{indent}  arabic:\n{indent}      {dart_str(e['arabic'])},",
        ]
        if e.get("shown"):
            lines.append(f"{indent}  excerpt:\n{indent}      {dart_str(e['shown'])},")
        lines.append(f"{indent}  translations: {{")
        for code in EDITIONS:
            lines.append(f"{indent}    '{code}':\n{indent}        {dart_str(e['translations'][code])},")
        lines.append(f"{indent}  }},")
        lines.append(f"{indent})")
        return "\n".join(lines)

    out = [
        "// GENERATED by tool/quran_verses.py — do not edit by hand.",
        "// Source: tool/quran_verses.json, text from quran.com (QPC Uthmani, and",
        "// every translation the app offers), cleaned exactly as QuranTextService",
        "// cleans it — footnote markup stripped, invisibles normalized.",
        "",
        "part of 'quran_verses.dart';",
        "",
        "/// The Friday verse: the verse of Salawat, Al-Ahzab 56.",
        "const jumuahVerse = " + entry(doc["jumuah"], "") + ";",
        "",
        "/// The rotation, in order. Neighbours differ in mood.",
        "const quranVerses = <QuranVerse>[",
    ]
    for e in doc["verses"]:
        out.append(entry(e) + ",")
    out.append("];")
    return "\n".join(out) + "\n"


def render_native(doc) -> str:
    names = surah_names()

    def entry(e):
        surah, a, b = parse_ref(e["ref"])
        return {
            "surah": surah,
            "start": a,
            "end": b,
            "surahName": names[surah][0],
            "surahNameAr": names[surah][1],
            "arabic": e["arabic"],
            "shown": e.get("shown") or e["arabic"],
            "translation": e["translation"],
        }

    native = {"jumuah": entry(doc["jumuah"]), "verses": [entry(e) for e in doc["verses"]]}
    return json.dumps(native, ensure_ascii=False, indent=1) + "\n"


def gen():
    doc = load()
    validate(doc)
    DART_OUT.write_text(render_dart(doc), encoding="utf-8")
    native = render_native(doc)
    for p in (ANDROID_OUT, IOS_OUT):
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(native, encoding="utf-8")
    print(f"wrote {DART_OUT.relative_to(ROOT)}, {ANDROID_OUT.relative_to(ROOT)}, {IOS_OUT.relative_to(ROOT)}")


def check():
    doc = load()
    validate(doc)
    stale = []
    if DART_OUT.read_text(encoding="utf-8") != render_dart(doc):
        stale.append(DART_OUT)
    native = render_native(doc)
    for p in (ANDROID_OUT, IOS_OUT):
        if not p.exists() or p.read_text(encoding="utf-8") != native:
            stale.append(p)
    if stale:
        raise SystemExit("stale, run `python3 tool/quran_verses.py gen`:\n" + "\n".join(str(p.relative_to(ROOT)) for p in stale))
    print("all copies agree")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    {"fetch": fetch, "gen": gen, "check": check}.get(cmd, lambda: sys.exit(__doc__))()
