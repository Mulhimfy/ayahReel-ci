# The faces a reel is typeset in

Every face here is **bundled rather than fetched**. The app's own
chrome takes its font from `google_fonts`, which resolves over the
network and falls back silently when it cannot — fine for a button,
wrong for a verse: the exporter rasterizes the verse card and burns it
into an mp4 the user cannot take back, and a face that had not landed
yet would be baked in as the fallback. Bundling also means the font
picker can *show* every face on a cold install with no network,
which is the whole of what makes it a picker.

`tool/fetch_fonts.py` writes this directory; `tool/verify_fonts.py`
proves, over all 6236 verses and every translation edition the app
offers, that each face can actually set what it is offered for — and
re-derives the optical numbers in `lib/data/verse_font.dart` from the
files themselves.

## The verse

| File | Family | Source | Licence |
|---|---|---|---|
| `UthmanicHafs.ttf` | KFGQPC Uthmanic Script HAFS | fonts.qurancomplex.gov.sa | free to use and distribute |
| `AmiriQuran.ttf` | Amiri Quran | Google Fonts | SIL OFL 1.1 |
| `ScheherazadeNew.ttf` | Scheherazade New | Google Fonts (SIL) | SIL OFL 1.1 |
| `NotoNaskhArabic.ttf` | Noto Naskh Arabic | Google Fonts | SIL OFL 1.1 |
| `Lateef.ttf` | Lateef | Google Fonts (SIL) | SIL OFL 1.1 |

All five carry every codepoint of the Uthmani text. Faces that do
**not**, and are therefore not offered — checked, not assumed: Reem
Kufi (21 missing), Markazi Text (21), Gulzar (22), Noto Nastaliq Urdu
(18). A Quranic mark a face has no glyph for is a tofu box in a reel
somebody already posted.

## The translation, Arabic script (Urdu)

| File | Family | Source | Licence |
|---|---|---|---|
| `IBMPlexSansArabic.ttf` | IBM Plex Sans Arabic | Google Fonts | SIL OFL 1.1 |
| `NotoNastaliqUrdu.ttf` | Noto Nastaliq Urdu | Google Fonts | SIL OFL 1.1 |

Noto Naskh Arabic and Scheherazade New are offered here too, off the
same files as the verse.

Nastaliq is missing exactly one codepoint of the Jalandhari edition,
U+0674 ARABIC LETTER HIGH HAMZA, in 40 verses of 6236. Its joining
type is U, so the glyph that comes from the fallback stands alone and
breaks no word — the one accepted gap in the whole set, and listed as
such in `tool/verify_fonts.py`.

## The translation, Latin script (English, Indonesian, German)

| File | Family | Source | Licence |
|---|---|---|---|
| `Inter.ttf`, `InterItalic.ttf` | Inter | Google Fonts | SIL OFL 1.1 |
| `SourceSerif4.ttf` | Source Serif 4 | Google Fonts | SIL OFL 1.1 |
| `Spectral.ttf` | Spectral | Google Fonts | SIL OFL 1.1 |
| `CormorantGaramond.ttf` | Cormorant Garamond | Google Fonts | SIL OFL 1.1 |
| `Literata.ttf` | Literata | Google Fonts | SIL OFL 1.1 |

These five are **subsetted** to the Latin ranges a translation can
use — Google Fonts serves subsets itself for the same reason — which
roughly halves them — Inter 317KB to 124, Source Serif 189 to 90,
Spectral 160 to 88, Literata 166 to 92, Cormorant Garamond 283 to 193.
The Arabic faces are shipped whole:
their shaping lives in GSUB/GPOS tables a subset has no business
pruning, and the saving would not pay for the risk.

Faces left out because they cannot set the English edition's
transliteration (ḥ ṣ ṭ ẓ ḍ ʿ ā ī ū — Saheeh International is full of
them): Lora, Playfair Display, Marcellus, Cinzel, Outfit, each missing
9 or 10 of those codepoints.

Every Latin face carries IBM Plex Sans Arabic behind it, and that is
load-bearing rather than cautious: Saheeh International writes the
honorific after the Prophet's name as the single ligature ﷺ (U+FDFA),
34 times, and no Latin face has a glyph for it.


## Eighty families

The list below was the first five; the app now bundles eighty, and
every one of them got in the same way — probed against the real texts
before being named in any enum, and dropped if it could not set what
it would be offered for. `tool/verify_fonts.py` is the gate and it
prints, per face, how many codepoints it leans on the fallback for.

Three tiers, and the tiers are the whole of the quality rule:

* **The verse** (twenty-six faces, out of thirteen families). Must
  cover all 70 codepoints of the Uthmani text out of its own cmap — no
  fallback, no exceptions — and attach its marks through GPOS. This
  is why the list is thirteen families and not fifty: almost no face
  carries the Quran's marks, and the list grew past ten by weight and
  width rather than by lowering the bar. See "The verse, in weights"
  below.
* **The translation** (thirty Latin, nine Arabic-script). Must set
  every edition, out of its own cmap or out of the chain stacked
  behind it — Source Serif for the transliteration marks, IBM Plex
  Sans Arabic for the ﷺ ligature. What a face may borrow from the
  chain is limited to glyphs that *stand alone*: a standalone ligature
  or a non-joining letter. A face that cannot draw a **combining**
  mark is not offered here, because a mark drawn by one face over
  another's letters is not something to print under a verse.
* **The card** (twenty). Everything else worth having. A card is typed
  by the person holding it, so the rule is only that nothing they can
  type ends in a tofu box — which the same chain guarantees.

## The first faces added since



Five more, fetched and verified the same way — `tool/fetch_fonts.py`
writes them, `tool/verify_fonts.py` proves each one sets every verse
and every edition it is offered for, and `tool/verify_hadith.py` does
the same against the hadith library the cards search. All five are
under the SIL Open Font Licence, from Google Fonts.

| Face | Set in | Why it is here |
| --- | --- | --- |
| **Amiri** | the verse, and Urdu | Amiri Quran's own letters without the spacing a mushaf's raised marks need: the same hand, a tighter page |
| **Noto Kufi Arabic** | the verse, and Urdu | the only face here that is not a naskh — kufi is the hand of an inscription, and on a card it reads as architecture |
| **Markazi Text** | Urdu | by Amiri's designer, cut for Persian and Urdu; sets a long translation in fewer lines than anything else here. Four honorific signs are drawn by the fallback behind it, each a non-joining mark — see ACCEPTED in `tool/verify_fonts.py` |
| **EB Garamond** | the translation | a digital cut of Claude Garamont's own types; the most printed-looking line on the list |
| **Libre Baskerville** | the translation | Baskerville for screens: a large eye and enough weight to hold up over a photograph, where the finer serifs give way first |

## The verse, in weights

The translation row offered thirty faces and the verse row ten, and
the verse is the line a reel is for. Every family on Google Fonts
with an Arabic subset — fifty-seven of them — was fetched the way
`tool/fetch_fonts.py` fetches and held to the verse's rule: all 70
codepoints of the Uthmani text out of its own cmap, and a GPOS `mark`
feature for Arabic, so a vowel is attached to its letter rather than
parked near it. Twelve families pass: nine were already verse faces,
IBM Plex Sans Arabic was bundled for Urdu and turns out complete, and
Estedad and Jomhuria are new. With KFGQPC Hafs, which is not on
Google Fonts, that is thirteen.

So the list grew the way a type specimen does: by weight and width
within the families that can set the Quran. Each weight is its own
static file — css2 asked for that one weight, Google instances the
variable family and serves a plain ttf — and its own family in
`pubspec.yaml`, and it was checked on its own, because it is a
different file. `tool/verify_fonts.py` now names all twenty-six and
derives each one's optical numbers from its file.

| File | Family | KB | Source | Licence |
|---|---|---|---|---|
| `NotoNaskhArabicBold.ttf` | NotoNaskhArabicBold | 192 | Google Fonts (Noto Naskh Arabic 700) | SIL OFL 1.1 |
| `AmiriBold.ttf` | AmiriBold | 359 | Google Fonts (Amiri 700) | SIL OFL 1.1 |
| `LateefBold.ttf` | LateefBold | 219 | Google Fonts (SIL; Lateef 700) | SIL OFL 1.1 |
| `HarmattanBold.ttf` | HarmattanBold | 506 | Google Fonts (SIL; Harmattan 700) | SIL OFL 1.1 |
| `NotoKufiArabicThin.ttf` | NotoKufiArabicThin | 174 | Google Fonts (Noto Kufi Arabic 100) | SIL OFL 1.1 |
| `NotoKufiArabicBold.ttf` | NotoKufiArabicBold | 174 | Google Fonts (Noto Kufi Arabic 700) | SIL OFL 1.1 |
| `NotoSansArabicExtraLight.ttf` | NotoSansArabicExtraLight | 188 | Google Fonts (Noto Sans Arabic 200) | SIL OFL 1.1 |
| `NotoSansArabicBlack.ttf` | NotoSansArabicBlack | 187 | Google Fonts (Noto Sans Arabic 900) | SIL OFL 1.1 |
| `NotoSansArabicExtraCondensed.ttf` | NotoSansArabicExtraCondensed | 187 | Google Fonts (Noto Sans Arabic, wdth 62.5, 400) | SIL OFL 1.1 |
| `NotoSansArabicExtraCondensedBold.ttf` | NotoSansArabicExtraCondensedBold | 187 | Google Fonts (Noto Sans Arabic, wdth 62.5, 700) | SIL OFL 1.1 |
| `IBMPlexSansArabic.ttf` | IBMPlexSansArabic | — | already bundled for Urdu; now a verse face too | SIL OFL 1.1 |
| `IBMPlexSansArabicBold.ttf` | IBMPlexSansArabicBold | 223 | Google Fonts (IBM Plex Sans Arabic 700) | SIL OFL 1.1 |
| `MadaLight.ttf` | MadaLight | 94 | Google Fonts (Mada 300) | SIL OFL 1.1 |
| `Estedad.ttf` | Estedad | 129 | Google Fonts (Estedad 400) | SIL OFL 1.1 |
| `EstedadBlack.ttf` | EstedadBlack | 129 | Google Fonts (Estedad 900) | SIL OFL 1.1 |
| `Jomhuria.ttf` | Jomhuria | 155 | Google Fonts (KB-Studio) | SIL OFL 1.1 |

3.0 MB between them, shipped whole like every Arabic face here.

Two families with mark attachment but not an enclosing end-of-ayah
sign — Mada and IBM Plex draw ۝ as an empty rosette beside plain
digits — borrow Noto Sans Arabic's sign; see `ayahEndMark` in
`lib/data/verse_numbering.dart`. Every other face added here was
shaped with ۝ and one, two and three digits, and encloses them.

**Checked and not offered: they cannot set the Quran.** Missing
codepoints of the 70, out of the Google Fonts file and, where it
differs, the `google/fonts` repository's own — the two agree for
every family, so this is the face and not the API's subsetting:
Katibeh 1 (U+06E5 SMALL WAW), Mirza 1 (U+06E5), Cascadia Code 18,
Cascadia Mono 18, Noto Nastaliq Urdu 18, Vazirmatn 18, Rakkas 19,
Alkalami 20, Alyamama 20, Kufam 20, Lalezar 20, Playpen Sans Arabic
20, Ruwudu 20, Zain 20, Alan Sans 21, Alexandria 21, Almarai 21, Aref
Ruqaa 21, Aref Ruqaa Ink 21, Badeen Display 21, Baloo Bhaijaan 2 21,
Beiruti 21, Cairo 21, Cairo Play 21, Changa 21, El Messiri 21, Fustat
21, Handjet 21, Lemonada 21, Marhey 21, Markazi Text 21, Oi 21, Qahiri
21, Readex Pro 21, Reem Kufi 21, Reem Kufi Fun 21, Reem Kufi Ink 21,
Rubik 21, Vibes 21, Gulzar 22, Parastoo 22, Tajawal 22, Blaka 23,
Blaka Hollow 23, Blaka Ink 23. Off Google Fonts, SIL's Awami Nastaliq
3.400 misses 18 and positions its marks with Graphite rather than
GPOS. Alkalami and Ruwudu, SIL's two West African hands, were the
ones most hoped for; both stop at the ordinary harakat, with no small
high marks and no alef wasla, and neither has `mkmk`.

**Checked, complete, and left out on purpose.** Amiri Slanted sets
with Amiri Text's advance widths to the unit — the same line, sheared
— so the picker test that proves a face actually changes the shaping
cannot tell them apart. Scheherazade New Bold (510 KB) is a fine face
whose name does not fit under a card. Noto Kufi Arabic ExtraBold and
Black, and Mada Bold, ExtraBold and Black, set a fifth to a quarter
again as wide as the mushaf face at its ink height — at or past the
edge of what the width test in `test/verse_font_test.dart` allows any
face. Lateef ExtraLight and ExtraBold, Estedad ExtraLight, Light,
SemiBold and Bold, Noto Sans Arabic Light and ExtraBold, the
ExtraCondensed Light, IBM Plex Sans Arabic ExtraLight and Mada
ExtraLight all pass; each is too near a weight already on the list to
look different on a reel.

KFGQPC's Uthman Taha Naskh would be the natural companion to the Hafs
face, under the same licence, but fonts.qurancomplex.gov.sa did not
answer from the machine this was done on, and a copy off a mirror is
not a source. It is not here.

## assets/google_fonts/Inter-Medium.ttf

One face lives outside this folder, under the name google_fonts looks
for. The AyahReel mark is set in Inter Medium through google_fonts,
which resolves over the network and falls back silently when it cannot
— and that mark is burned into every exported reel and every exported
card, where a fallback cannot be taken back. google_fonts checks the
asset manifest before the network and uses any bundled asset whose name
ends in `<Family>-<Variant>.ttf`, so this one file makes the mark
resolve offline, synchronously, at the weight it was drawn at.

Same licence and same source as `Inter.ttf` above (SIL Open Font
Licence, Google Fonts), subsetted to the same Latin ranges.
`tool/fetch_fonts.py` writes it; see `MARK_FACES` there.
