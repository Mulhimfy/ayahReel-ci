#!/usr/bin/env python3
"""Build assets/hadith.json — the offline hadith library the card
composer searches.

WHY A CURATED LIBRARY RATHER THAN THE WHOLE SHELF

The nine collections behind hadith-api come to roughly 34,000 hadith,
and a single one of them is bigger than every other asset in the app
put together: Sahih al-Bukhari alone is 9.4 MB of Arabic and 4.8 MB of
English, before Urdu and Indonesian. Bundling all of it in four
languages is about 40 MB of app — a download most of this app's users
pay for by the megabyte — to carry text that no card will ever hold.

So this keeps what a card can actually use, and says so in the app:

  * The two classical forties whole — an-Nawawi's forty (42) and the
    forty hadith qudsi (40). They are curated collections already,
    memorised and quoted as units.
  * From the two Sahihs and the four Sunan, every hadith whose matn is
    short enough to be read at a glance on a phone screen (see
    MAX_AR). A long hadith is not a card; it is a page.

That is about seven thousand hadith, which is a real library rather
than a token one, and it is laid out so a phone only ever pays for the
part it reads. The text is split one file per language and gzipped:
the app loads the Arabic and the single translation the reader has
chosen, never the other two, and the row index is what ties them
together. Gzip because these are 13 MB of text and about 3.5 MB of
archive — `dart:io`'s codec is zlib, so inflating one is milliseconds,
and it happens once, in a background isolate, the first time somebody
opens the hadith finder.

Everything here is therefore from a named collection with its own
number, which the app shows under every result — a hadith on a card
that nobody can look up is worth nothing.

AND NOTHING WEAK

A card is published. Somebody reads it as a saying of the Prophet ﷺ
with nothing around it — no chain, no grader, no page to turn — so a
da'if narration that slipped into this file would go out into the
world as if it were sound, over and over, from every phone that found
it. The two Sahihs answer for themselves and the two forties are
classical curated collections; everything out of the four Sunan and
the Muwatta has to carry a grade of sahih or hasan from one of the
graders these editions record, and none of weak (see GRADE_OK and
GRADE_BAD). What survives is shown with that grading, by name.

WHAT IS CLEANED, AND WHAT IS NOT

The Arabic in these editions carries the full isnad: "حدثنا آدم قال
حدثنا شعبة قال حدثني ابن الأصبهاني..." — six men's names before the
Prophet ﷺ is even reached. Nobody puts that on a card, and a search
result that leads with it is unreadable. So the transmission chain is
stripped from the *front* of the Arabic, conservatively: only leading
clauses that begin with a transmission verb (حدثنا / أخبرنا / أنبأنا
and their variants) are removed, one comma-delimited clause at a time,
and the moment a clause starts with anything else the stripping stops.
The narrator the hadith is actually attributed to — "عن أبي هريرة
قال..." — is left where it is, because that is part of what a person
is quoting.

The translations are left as their translators wrote them, beyond
whitespace and stray markup. Muhsin Khan's "Narrated Abu Sa`id
Al-Khudri:" is already the clean form.

SOURCES AND CREDIT

Text from fawazahmed0/hadith-api (a mirror of the sunnah.com corpus),
which the app credits by collection and by translator in the hadith
sheet itself. Run this and commit the asset; the app never fetches
hadith at runtime.

Run:  python3 tool/fetch_hadith.py
Then: python3 tool/verify_hadith.py
"""
import gzip
import io
import json
import os
import re
import sys
import urllib.request

BASE = 'https://cdn.jsdelivr.net/gh/fawazahmed0/hadith-api@1/editions'
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'assets', 'hadith')
CACHE = os.environ.get('HADITH_CACHE', os.path.join(HERE, '.hadith-cache'))

# Longest Arabic matn, in characters, that still reads as a quotation
# rather than as a page. Measured after the isnad is stripped: 220
# characters of vowelled Arabic is about thirty-five words, which sets
# to four or five lines on a card at a size anybody can read across a
# room — and anything longer is still reachable, because the finder
# lets a card take a piece of a hadith rather than all of it.
#
# The knob is really a memory budget rather than a taste one. Dart
# holds a string as UTF-16, and each language is held twice over — once
# as it reads and once normalised for matching — so every hundred
# characters of allowance here is about 4 MB of phone. 240 lands the
# whole library at ~2 MB of app and ~16 MB of memory while the finder
# is open; 320 doubles both for hadith almost nobody would quote whole.
MAX_AR = 240
MIN_AR = 40

# The forties are kept whole even when a hadith runs long — they are
# quoted as units, and the two longest (Jibril's, and the hadith of
# the forty days) are among the best known in the corpus.
MAX_AR_FORTIES = 2000

MIN_EN = 30
MAX_EN = 900

# Gradings that let a hadith out of the Sunan and the Muwatta, and the
# ones that keep it in. Matched case-folded against the grade strings
# these editions carry ("Sahih", "Hasan Sahih", "Isnaad Sahih",
# "Sahih - Agreed Upon", "Daif", "Da'if", …). A single bad grade is
# disqualifying even when another grader passed it: this is a card, and
# the disagreement cannot travel with it.
GRADE_OK = ('sahih', 'hasan', 'sahih-agreed', 'agreed upon')
GRADE_BAD = ('daif', "da'if", 'weak', 'munkar', 'mawdu', 'batil',
             'matruk', 'fabricat', 'shadh')

# The forties again: their English runs long where the Arabic does not,
# and a canonical forty missing two of its hadith is not the forty.
MAX_EN_FORTIES = 2600

# The narrations that are not hadith so much as bookkeeping: an
# edition noting that the previous hadith came down a second chain, or
# "a similar report", with no matn of their own. They are a real part
# of the corpus and no use at all on a card.
CHAIN_ONLY_AR = ['بهذا الإسناد', 'مثله', 'نحوه', 'بمثل', 'بنحو',
                 'بهذا الحديث', 'مثل حديث', 'نحو حديث']
CHAIN_ONLY_EN = ['same chain', 'similar report', 'similar hadith',
                 'a hadith like it', 'as mentioned above',
                 'similar to it', 'with a different chain',
                 'through a different chain', 'similar tradition']

# collection id -> (English name, Arabic name, whole?)
COLLECTIONS = [
    ('nawawi',   "An-Nawawi's Forty",   'الأربعون النووية',   True),
    ('qudsi',    'Forty Hadith Qudsi',  'الأربعون القدسية',   True),
    ('bukhari',  'Sahih al-Bukhari',    'صحيح البخاري',       False),
    ('muslim',   'Sahih Muslim',        'صحيح مسلم',          False),
    ('tirmidhi', 'Jami at-Tirmidhi',    'جامع الترمذي',       False),
    ('abudawud', 'Sunan Abu Dawud',     'سنن أبي داود',       False),
    ('nasai',    "Sunan an-Nasa'i",     'سنن النسائي',        False),
    ('ibnmajah', 'Sunan Ibn Majah',     'سنن ابن ماجه',       False),
    ('malik',    'Muwatta Malik',       'موطأ مالك',          False),
]

# Who translated what, shown under the results in the app: a
# translation nobody is named for is one nobody can weigh.
EDITION_CREDITS = {
    'en': 'Muhsin Khan · Abdul Hamid Siddiqui · sunnah.com',
    'ur': 'sunnah.com Urdu editions',
    'id': 'sunnah.com Indonesian editions',
}

# app language code -> edition prefix. German is not published for any
# collection, so a German reader is shown the English edition; the
# sheet names the edition it is showing.
LANGS = [('en', 'eng'), ('ur', 'urd'), ('id', 'ind')]

HARAKAT = 'ً-ْٰـ'
TASHKEEL = re.compile(f'[{HARAKAT}]')


def ar(word):
    """A pattern matching [word] however it happens to be vowelled."""
    return ''.join(f'{c}[{HARAKAT}]*' for c in word)


# One clause of a transmission chain, at the very front of the text.
ISNAD_VERBS = ['حدثنا', 'حدثني', 'أخبرنا', 'أخبرني', 'أنبأنا', 'أنبأني',
               'وحدثنا', 'وحدثني', 'وأخبرنا', 'ثنا', 'نا']
ISNAD = re.compile(
    r'^\s*(?:' + ar('قال') + r'\s+)?(?:' +
    '|'.join(ar(v) for v in ISNAD_VERBS) + r')\b[^،.]*[،.]\s*')

# Markup and editorial furniture that rides along in some editions.
TAGS = re.compile(r'<[^>]*>')
BIDI = re.compile('[​-‏‪-‮﻿]')
BRACKETS = re.compile(r'\[[^\]]*\]')
SPACES = re.compile(r'\s+')


def fetch(name):
    path = os.path.join(CACHE, f'{name}.json')
    if os.path.exists(path):
        with open(path, encoding='utf-8') as f:
            return json.load(f)
    os.makedirs(CACHE, exist_ok=True)
    url = f'{BASE}/{name}.min.json'
    print(f'  fetching {name} …', flush=True)
    try:
        with urllib.request.urlopen(url, timeout=180) as r:
            raw = r.read().decode('utf-8')
    except Exception as e:                                # noqa: BLE001
        print(f'  !! {name}: {e}')
        return None
    with open(path, 'w', encoding='utf-8') as f:
        f.write(raw)
    return json.loads(raw)


def clean_common(text):
    text = TAGS.sub(' ', text or '')
    text = BIDI.sub('', text)
    # A replacement character is a byte these editions lost upstream;
    # it would be a black diamond on somebody's card.
    text = text.replace('\ufffd', '')
    return SPACES.sub(' ', text).strip()


def clean_arabic(text):
    text = clean_common(text)
    # Trailing "رواه البخاري [رقم:13]" style attributions: the app
    # prints the collection and number itself.
    text = BRACKETS.sub(' ', text)
    prev = None
    while prev != text:                       # one clause at a time
        prev = text
        text = ISNAD.sub('', text)
    text = SPACES.sub(' ', text).strip()
    # A chain that ended mid-sentence can leave a dangling connector.
    text = re.sub(r'^(?:' + ar('قال') + r')\s*[:،]?\s*$', '', text)
    return text.strip(' ،.')


def clean_translation(text):
    text = clean_common(text)
    # Brackets stay: in a translation they are the translator's own
    # clarification — "None of you [truly] believes" — and cutting them
    # out changes the sentence. Only a trailing run of references goes.
    text = re.sub(r'(?:\s*\[[^\]]*\])+\s*$', '', text)
    # "Narrated Abu Sa`id Al-Khudri:Some women requested…", "the
    # Messenger of Allah (ﷺ)came to…" — this edition very often loses
    # the space after a colon or a closing bracket.
    text = re.sub(r'(?<=[:)])(?=[A-Za-z\u0600-\u06FF])', ' ', text)
    return SPACES.sub(' ', text).strip()


# What a hadith is *about*, for browsing rather than searching. Matched
# on the English text, lowercased; a hadith may carry several, and one
# carrying none is still searchable.
TOPICS = {
    'mercy':        ['mercy', 'merciful', 'compassion'],
    'prayer':       ['prayer', 'prays', 'salat', 'prostrat', 'mosque'],
    'charity':      ['charity', 'sadaqa', 'zakat', 'gives in', 'alms'],
    'knowledge':    ['knowledge', 'learn', 'teach', 'scholar'],
    'patience':     ['patience', 'patient', 'endure', 'affliction',
                     'calamity'],
    'parents':      ['mother', 'father', 'parents'],
    'kindness':     ['kind', 'gentle', 'smile', 'good to', 'neighbour',
                     'neighbor'],
    'gratitude':    ['grateful', 'thank', 'blessing'],
    'dhikr':        ['remember', 'remembrance', 'glorif', 'subhan',
                     'praise'],
    'quran':        ['quran', "qur'an", 'recite'],
    'forgiveness':  ['forgive', 'pardon', 'repent'],
    'brotherhood':  ['brother', 'muslim', 'believers'],
    'character':    ['character', 'manners', 'honest', 'truthful',
                     'lie', 'anger', 'modesty', 'trust'],
    'paradise':     ['paradise', 'jannah', 'garden'],
    'faith':        ['faith', 'belief', 'believe'],
    'dua':          ['supplicat', 'invoke', 'asks allah', 'du`a', 'dua'],
    'time':         ['night', 'morning', 'friday', 'ramadan', 'fast'],
    'hardship':     ['hardship', 'ease', 'difficult', 'burden', 'poor',
                     'orphan'],
}


def topic_bits(english):
    """The topics of [english] as a bitmask over TOPICS' order."""
    low = english.lower()
    bits = 0
    for i, words in enumerate(TOPICS.values()):
        if any(w in low for w in words):
            bits |= 1 << i
    return bits


def graded(hadith, whole):
    """The grade to show, or None when this hadith may not be shown.

    An empty string is "no grading needed": the two Sahihs and the two
    forties, which the collection itself vouches for.
    """
    if whole or hadith.get('_sahih'):
        return ''
    best = ''
    for g in hadith.get('grades') or []:
        grade = (g.get('grade') or '').strip()
        low = grade.lower()
        if any(b in low for b in GRADE_BAD):
            return None
        if not best and any(ok in low for ok in GRADE_OK):
            best = f'{grade} · {g.get("name", "").strip()}'.strip(' ·')
    return best or None


def chain_only(arabic, english):
    plain = TASHKEEL.sub('', arabic)
    low = english.lower()
    return (any(m in plain for m in CHAIN_ONLY_AR)
            or any(m in low for m in CHAIN_ONLY_EN))


def key_of(arabic):
    """Dedupe key: letters of the first stretch of the matn."""
    plain = TASHKEEL.sub('', arabic)
    plain = re.sub(r'[^ء-ي ]', '', plain)
    return SPACES.sub(' ', plain).strip()[:90]


def main():
    rows, text = [], {code: [] for code, _ in LANGS}
    arabic_out = []
    seen = set()
    counts = {}
    cids = [c[0] for c in COLLECTIONS]
    for cid, en_name, ar_name, whole in COLLECTIONS:
        arabic = fetch(f'ara-{cid}')
        if arabic is None:
            print(f'  !! {cid}: no Arabic edition, skipped')
            continue
        trans = {}
        for code, prefix in LANGS:
            data = fetch(f'{prefix}-{cid}')
            if data is None:
                continue
            trans[code] = {h['hadithnumber']: h['text']
                           for h in data['hadiths']}
        kept = 0
        cap = MAX_AR_FORTIES if whole else MAX_AR
        en_cap = MAX_EN_FORTIES if whole else MAX_EN
        for h in arabic['hadiths']:
            num = h['hadithnumber']
            if not isinstance(num, int):      # a few are "13.1"
                continue
            body = clean_arabic(h['text'])
            if not (MIN_AR <= len(body) <= cap):
                continue
            english = clean_translation(trans.get('en', {}).get(num, ''))
            if not (MIN_EN <= len(english) <= en_cap):
                continue
            if chain_only(body, english):
                continue
            h['_sahih'] = cid in ('bukhari', 'muslim')
            grade = graded(h, whole)
            if grade is None:
                continue
            k = key_of(body)
            if k in seen:
                continue
            seen.add(k)
            rows.append([cids.index(cid), num, topic_bits(english), grade])
            arabic_out.append(body)
            for code, _ in LANGS:
                t = clean_translation(trans.get(code, {}).get(num, ''))
                if code == 'en':
                    t = english
                elif not (MIN_EN <= len(t) <= en_cap * 2):
                    t = ''
                text[code].append(t)
            kept += 1
        counts[cid] = kept
        print(f'  {cid}: kept {kept} of {len(arabic["hadiths"])}')

    os.makedirs(OUT, exist_ok=True)
    meta = {
        'version': 1,
        # Every row is [collection index, hadith number, topic bits,
        # grading] — the grading empty for the collections that answer
        # for themselves.
        'collections': [{'id': cid, 'en': en_name, 'ar': ar_name}
                        for cid, en_name, ar_name, _ in COLLECTIONS],
        # Index-aligned with the bits of the third field.
        'topics': list(TOPICS),
        'editions': EDITION_CREDITS,
        'rows': rows,
    }
    write(os.path.join(OUT, 'meta.json'), meta, gz=False)
    write(os.path.join(OUT, 'ar.json'), arabic_out)
    for code, _ in LANGS:
        write(os.path.join(OUT, f'{code}.json'), text[code])

    total = sum(os.path.getsize(os.path.join(OUT, f))
                for f in os.listdir(OUT))
    print(f'\n{len(rows)} hadith -> {OUT} ({total / 1e6:.2f} MB shipped)')
    if total > 5_000_000:
        print('!! bigger than the budget; lower MAX_AR')
        return 1
    return 0


def write(path, doc, gz=True):
    raw = json.dumps(doc, ensure_ascii=False,
                     separators=(',', ':')).encode('utf-8')
    if not gz:
        with open(path, 'wb') as f:
            f.write(raw)
        print(f'  {os.path.basename(path)}: {len(raw) / 1e6:.2f} MB')
        return
    # mtime=0 so a rebuild that changes nothing produces the same bytes
    # and leaves the repository alone.
    buf = io.BytesIO()
    with gzip.GzipFile(fileobj=buf, mode='wb', compresslevel=9, mtime=0) as f:
        f.write(raw)
    with open(path + '.gz', 'wb') as f:
        f.write(buf.getvalue())
    print(f'  {os.path.basename(path)}.gz: {len(buf.getvalue()) / 1e6:.2f} MB'
          f' ({len(raw) / 1e6:.2f} MB inflated)')


if __name__ == '__main__':
    sys.exit(main())
