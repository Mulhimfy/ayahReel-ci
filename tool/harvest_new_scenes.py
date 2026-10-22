"""Harvest NEW sceneries beyond the current library, on a CI runner.

    python tool/harvest_new_scenes.py probe                 what each source answers
    python tool/harvest_new_scenes.py discover <tab> <site> one site's candidates for a tab
    python tool/harvest_new_scenes.py score <tab>           fetch, frame, score, face-check
    python tool/harvest_new_scenes.py vet <tab>             person detector + CLIP
    python tool/harvest_new_scenes.py pool                  every tab into one review pool

<site> is pexels, pixabay or open (Mixkit, Openverse and Wikimedia
Commons). Everything lands under scenes_out/ (SCENES_OUT moves it).

This runs on a GitHub Actions runner of the public CI mirror, through
.github/workflows/scenes-harvest.yml: the machine these tools are
written on reaches GitHub and nothing else. Pexels and Pixabay stop any
client that is not a browser at Cloudflare's door, so those two are
read with a real (headless) Chromium; the rest answer plain requests.

The library's own judgement is reused, not re-implemented:
curate_scenes.cover/measure/FLOOR frame and score every candidate
exactly as the existing 769 were, and its Haar cascade still checks for
faces. Two things are added that the first harvest did not have:

  * a person detector (YOLO), because a figure seen from behind, a
    silhouette on a dune or a hiker on a ridge has no face to find;
  * CLIP image embeddings, scored later against written prompts, for
    what no detector names: a church filed under sacred, a painting or
    an AI render passed off as a photo, a watermark, a bottle of wine.

Nothing is decided here that a person might want to revisit. Every
measurement is kept, and tool/select_new_scenes.py makes the choice from
the pool -- anywhere, with numpy and Pillow, in seconds -- and writes
the review page.
"""

import concurrent.futures as futures
import html as htmlmod
import json
import os
import random
import re
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.environ.get("SCENES_OUT", os.path.join(ROOT, "scenes_out"))
sys.path.insert(0, os.path.join(ROOT, "tool"))

# A smoke test: only the first N queries of each category.
QUERY_LIMIT = int(os.environ.get("SCENES_QUERY_LIMIT", "0") or 0)

UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36")
HDRS = {
    "User-Agent": UA,
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
}
# Wikimedia asks bulk clients to name themselves and a way to reach them;
# the repository is that contact.
WIKI_UA = ("AyahReelsSceneHarvester/2.0 "
           "(https://github.com/Mulhimfy/ayahReel-ci; scenery harvest)")

TAB_BUCKET = {t: ("horizontal" if t in ("aerial", "cinematic") else "vertical")
              for t in ("sky", "mountains", "desert", "water", "forest", "road",
                        "sacred", "abstract", "aerial", "cinematic")}
TAB_CATS = {
    "sky": ["sky", "clouds", "aurora"],
    "mountains": ["mountains", "snow", "rock"],
    "desert": ["desert"],
    "water": ["ocean", "water", "rain"],
    "forest": ["forest", "field"],
    "road": ["road"],
    "sacred": ["sacred"],
    "abstract": ["abstract"],
    "aerial": ["aerial_mountain", "aerial_coast", "aerial_forest",
               "aerial_desert", "aerial_water", "aerial_land"],
    "cinematic": ["cinematic"],
}

LICENSES = {
    "pexels": ("Pexels License", "https://www.pexels.com/license/"),
    "pixabay": ("Pixabay Content License", "https://pixabay.com/service/license-summary/"),
    "mixkit": ("Mixkit Stock Video Free License", "https://mixkit.co/license/#videoFree"),
    "cc0": ("CC0 1.0 (public domain dedication)",
            "https://creativecommons.org/publicdomain/zero/1.0/"),
    "pdm": ("Public Domain Mark 1.0", "https://creativecommons.org/publicdomain/mark/1.0/"),
    "pd": ("Public domain", "https://commons.wikimedia.org/wiki/Commons:Licensing#Public_domain"),
}


def log(*a):
    print(*a, flush=True)


def tab_dir(tab):
    d = os.path.join(OUT, tab)
    os.makedirs(d, exist_ok=True)
    return d


# ── what to look for ────────────────────────────────────────────────────
# The first harvest's queries found the library that exists; these go
# wider and deeper so the same famous frames are not all that comes back.
# Over-specified toward dark, empty, person-free frames for the portrait
# tabs -- the verse is drawn ON those -- and toward drone footage for the
# wide ones, which the verse sits under.

QUERIES = {
    "sky": [
        "milky way", "milky way night sky", "starry night sky", "night sky stars",
        "stars over mountains", "star trails", "moon night sky", "full moon",
        "crescent moon", "moon clouds night", "moonlight", "night clouds",
        "dramatic sky", "dark sky", "twilight sky", "blue hour sky", "dusk sky",
        "night sky silhouette", "galaxy night sky", "meteor shower",
        "lightning storm", "thunderstorm night", "sky at dawn", "moonrise",
        "night sky trees", "starry sky lake", "venus evening sky", "comet night sky",
    ],
    "clouds": [
        "dark clouds", "storm clouds", "cloudscape", "sea of clouds", "above the clouds",
        "clouds sunset", "moody clouds", "clouds at night", "cumulonimbus",
        "mammatus clouds", "rain clouds", "clouds dusk", "sun rays clouds",
        "god rays", "overcast sky", "fog clouds mountains", "storm front",
        "shelf cloud", "clouds moonlight", "golden clouds",
    ],
    "aurora": [
        "aurora borealis", "northern lights", "aurora night sky", "aurora mountains",
        "aurora lake", "aurora reflection", "green aurora", "aurora iceland",
        "aurora norway", "aurora snow", "aurora stars", "polar lights",
    ],
    "mountains": [
        "mountains night", "mountain silhouette", "misty mountains", "foggy mountains",
        "mountain peak", "mountain range dusk", "dark mountains", "mountain lake night",
        "mountains stars", "mountains moon", "mountain clouds", "mountain sunset",
        "mountain sunrise", "dolomites", "alps", "himalaya", "patagonia", "volcano",
        "mountain valley fog", "moody mountains", "mountain ridge", "mountains blue hour",
        "rocky mountains", "matterhorn", "mountain milky way",
    ],
    "snow": [
        "snowy mountains", "snow mountain night", "winter night", "snowfall",
        "snowy forest", "winter landscape", "glacier", "iceberg", "frozen lake",
        "snow peaks", "winter mountains", "ice cave", "arctic", "snow storm",
        "winter fog", "snowy pine trees", "frost",
    ],
    "rock": [
        "canyon", "rock formation", "cliffs", "sandstone", "desert rocks", "cave",
        "basalt columns", "rock arch", "wadi rum", "grand canyon", "rocks night sky",
        "antelope canyon", "rocky landscape", "rock cliff fog", "monument valley",
    ],
    "desert": [
        "desert night", "desert dunes", "sand dunes", "dunes night", "desert stars",
        "desert milky way", "desert sunset", "desert dusk", "sahara", "desert moon",
        "desert silhouette", "minimal desert", "dune shadows", "empty desert",
        "desert landscape", "sand texture", "dune ridge", "desert tree", "desert sunrise",
        "arabian desert", "namib desert", "oasis", "palm trees silhouette", "dubai desert",
        "sandstorm", "desert night sky", "sand ripples", "death valley", "white sands",
        "sossusvlei", "desert mountains", "empty quarter", "desert valley",
    ],
    "ocean": [
        "dark ocean", "ocean night", "ocean waves", "sea dusk", "moonlight sea",
        "stormy sea", "ocean long exposure", "sea horizon", "ocean sunset",
        "waves crashing", "moody sea", "underwater", "deep sea", "sea fog",
        "lighthouse night", "calm sea", "seascape", "ocean blue hour", "beach night",
        "waves rocks", "sea cliff", "ocean storm", "sea at dawn", "ocean surface",
    ],
    "water": [
        "lake night", "lake reflection", "still water", "misty lake", "river night",
        "waterfall", "waterfall long exposure", "water drops", "water surface",
        "water ripples", "pond", "forest stream", "lake stars", "mountain lake",
        "lake sunset", "lake fog", "river fog", "water reflection night", "calm water",
        "lake dusk", "creek",
    ],
    "rain": [
        "rain window", "raindrops", "rain on glass", "rainy night", "rain drops dark",
        "rain puddle", "rain leaves", "rain storm", "wet glass", "rain on water",
        "rainy window", "rain bokeh", "droplets", "monsoon", "drizzle",
    ],
    "forest": [
        "dark forest", "misty forest", "foggy forest", "forest night", "pine forest",
        "moody forest", "forest moonlight", "forest path", "rainforest", "autumn forest",
        "birch forest", "jungle", "forest canopy", "tree silhouette", "lone tree",
        "forest sunbeams", "dense forest", "woods", "forest fog morning", "redwood forest",
        "bamboo forest", "trees fog", "forest dusk", "winter forest",
    ],
    "field": [
        "wheat field", "grass field", "meadow fog", "field night", "lavender field",
        "tall grass", "rice field", "tea plantation", "field tree", "sunflower field",
        "green hills", "prairie", "field sunset", "farmland", "hills fog", "grassland",
        "savanna", "countryside dusk", "barley field", "olive grove", "olive tree",
        "date palm trees", "palm grove", "fig tree", "orchard",
    ],
    "road": [
        "empty road", "road night", "lonely road", "foggy road", "highway night",
        "mountain road", "desert road", "forest road", "winding road", "street lights",
        "light trails", "road rain", "road stars", "road dusk", "country road",
        "road through forest", "tunnel", "bridge night", "railway tracks", "path fog",
        "road sunset", "dirt road", "snowy road", "road aerial", "empty street night",
        "alley night", "pathway", "trail", "highway", "road fog night",
    ],
    "sacred": [
        "mosque", "mosque night", "mosque dome", "minaret", "minaret night",
        "mosque silhouette", "mosque sunset", "mosque interior", "islamic architecture",
        "islamic pattern", "islamic art", "arabic lantern", "ramadan lantern", "ramadan",
        "crescent moon mosque", "sheikh zayed mosque", "blue mosque", "hagia sophia",
        "masjid", "mecca", "kaaba", "medina", "al aqsa", "dome of the rock",
        "moroccan lantern", "mosque arches", "eid", "islamic geometric", "mosque courtyard",
        "mosque lights", "mihrab", "mosque chandelier", "alhambra", "mosque ceiling",
        "istanbul mosque", "suleymaniye mosque", "hassan ii mosque", "sultan qaboos mosque",
        "badshahi mosque", "putra mosque", "faisal mosque", "masjid nabawi",
        "islamic lamp", "arabesque", "islamic tiles", "moroccan architecture",
        "ottoman architecture", "isfahan mosque", "mosque reflection", "minaret moon",
        "mosque fog", "arabic architecture",
    ],
    "abstract": [
        "dark texture", "black texture", "dark gradient", "gold bokeh", "bokeh lights",
        "smoke", "ink in water", "silk", "dark fabric", "candle", "candle flame",
        "candlelight", "lantern", "oil lamp", "embers", "sparks", "dark marble",
        "gold texture", "light rays", "dust particles light", "dark water texture",
        "glitter", "dark paper texture", "abstract dark blue", "light leak", "dark wood",
        "fog dark background", "night bokeh", "fire flames dark", "incense smoke",
        "water drops macro", "frost texture", "starry bokeh", "abstract waves dark",
        "liquid gold", "golden light dark", "smoke colorful", "dark abstract",
    ],
    "aerial_mountain": [
        "aerial mountains", "drone mountains", "aerial alps", "mountain range aerial",
        "aerial snowy mountains", "aerial volcano", "aerial mountain lake",
        "aerial dolomites", "drone mountain clouds", "aerial mountain sunset",
        "drone highlands", "aerial mountain fog", "aerial mountain peaks",
        "drone norway mountains", "aerial iceland",
    ],
    "aerial_coast": [
        "aerial coastline", "drone beach", "aerial ocean waves", "drone cliffs",
        "aerial island", "aerial turquoise sea", "drone waves", "aerial lagoon",
        "drone coast", "aerial sea", "aerial beach waves", "drone ocean",
        "aerial cliffs ocean", "aerial sea rocks",
    ],
    "aerial_forest": [
        "aerial forest", "drone forest", "aerial autumn forest", "drone jungle",
        "aerial pine forest", "drone forest fog", "aerial rainforest", "drone trees",
        "aerial forest river", "aerial snowy forest", "drone forest sunset",
        "aerial green forest", "aerial tree tops",
    ],
    "aerial_desert": [
        "aerial desert", "drone desert", "aerial sand dunes", "drone dunes",
        "aerial sahara", "drone canyon", "aerial desert road", "aerial oasis",
        "drone salt flats", "aerial badlands", "aerial desert mountains", "drone wadi",
    ],
    "aerial_water": [
        "aerial waterfall", "drone river", "aerial lake", "drone waterfall",
        "aerial river delta", "aerial glacier", "drone lake", "aerial river bend",
        "aerial fjord", "drone iceland river", "aerial lake mountains", "aerial stream",
        "aerial wetland", "drone river forest",
    ],
    "aerial_land": [
        "aerial countryside", "drone fields", "aerial farmland", "drone hills",
        "aerial rice terraces", "aerial tea plantation", "drone green hills",
        "aerial road", "drone winding road", "aerial patchwork fields", "aerial highway",
        "drone landscape", "aerial meadow", "aerial plains", "aerial palm plantation",
    ],
    "cinematic": [
        "cinematic landscape", "landscape timelapse", "clouds timelapse",
        "sunrise mountains", "sunset landscape", "nature landscape", "mountain lake",
        "waterfall nature", "ocean sunset", "forest sunlight", "golden hour landscape",
        "misty valley", "epic landscape", "starry sky timelapse", "milky way timelapse",
        "storm timelapse", "northern lights timelapse", "rolling hills", "meadow",
        "river landscape", "seascape", "lake sunrise", "desert landscape",
        "snow landscape", "autumn landscape", "waves slow motion", "clouds moving",
        "sunset clouds", "nature scenery", "mountain scenery", "fog valley",
        "sunrise fog", "wind grass", "lightning", "beach sunset", "moon timelapse",
        "sun rays forest", "wheat field wind", "waterfall slow motion",
    ],
}

# Mixkit is organised by topic pages rather than free-text search; each
# category gets the topics that picture it.
MIXKIT_TOPICS = {
    "sky": ["night-sky", "stars", "moon", "sky", "sunset", "milky-way", "storm", "lightning"],
    "clouds": ["clouds", "storm-clouds", "fog"],
    "aurora": ["aurora", "northern-lights"],
    "mountains": ["mountain", "mountains"],
    "snow": ["snow", "winter", "ice"],
    "rock": ["canyon", "rocks", "cliff"],
    "desert": ["desert", "sand", "dunes"],
    "ocean": ["ocean", "sea", "waves", "underwater"],
    "water": ["water", "lake", "river", "waterfall"],
    "rain": ["rain", "raindrops"],
    "forest": ["forest", "trees", "jungle"],
    "field": ["field", "grass", "meadow"],
    "road": ["road", "highway", "street", "tunnel"],
    "sacred": ["mosque", "islamic", "ramadan", "lantern"],
    "abstract": ["abstract", "smoke", "bokeh", "candle", "fire", "particles", "ink"],
    "aerial_mountain": ["aerial-mountains", "drone-mountains"],
    "aerial_coast": ["aerial-beach", "aerial-ocean", "drone-beach"],
    "aerial_forest": ["aerial-forest", "drone-forest"],
    "aerial_desert": ["aerial-desert", "drone-desert"],
    "aerial_water": ["aerial-river", "aerial-lake", "aerial-waterfall"],
    "aerial_land": ["aerial", "drone", "aerial-landscape", "aerial-fields"],
    "cinematic": ["nature", "landscape", "timelapse", "sunrise", "time-lapse", "scenery"],
}


def queries_for(cat):
    qs = QUERIES.get(cat, [])
    return qs[:QUERY_LIMIT] if QUERY_LIMIT else qs


# ── words that rule a candidate out before a byte of it is fetched ──────
# Matched against the title, description, alt text, tags and URL slug the
# source itself publishes. Pexels' alt text is a sentence written about
# the picture ("Silhouette of Man Standing on Rock Formation"), Pixabay's
# slug is its tag list, Mixkit's is its title: a person, a church or a
# wine glass named there is in the picture.

_W = r"(?<![a-z0-9])(?:{})(?![a-z0-9])"
BLOCK = {
    "people": re.compile(_W.format("|".join([
        r"persons?", r"people", r"m[ae]n(?!-made)", r"wom[ae]n", r"girls?", r"boys?",
        r"child(?:ren)?", r"kids?", r"bab(?:y|ies)", r"toddlers?", r"couples?",
        r"family", r"crowds?", r"crowded", r"tourists?", r"hikers?", r"hiking",
        r"travell?ers?", r"photographers?", r"models?", r"selfie", r"(?<!rock )(?<!cliff )"
        r"(?<!north )(?<!south )(?<!east )(?<!west )(?<!mountain )faces?", r"portraits?",
        r"hands?", r"feet", r"foot", r"legs?", r"body(?! of water)", r"lady", r"guy",
        r"gentleman", r"brides?", r"grooms?", r"wedding", r"dancers?", r"dancing",
        r"riders?", r"riding", r"cyclists?", r"bikers?", r"surfers?", r"surfing",
        r"swimmers?", r"swimming", r"divers?", r"skiers?", r"skiing", r"snowboard\w*",
        r"climbers?", r"climbing", r"runners?", r"jogg\w+", r"fisherm[ae]n", r"workers?",
        r"farmers?", r"soldiers?", r"police", r"monks?", r"nuns?", r"priests?", r"imams?",
        r"pilgrims?", r"worshipp?ers?", r"praying", r"pray", r"hijab", r"niqab",
        r"burqa", r"abaya", r"students?", r"players?", r"athletes?", r"human",
        r"humans", r"someone", r"somebody", r"pedestrians?", r"commuters?",
        r"passengers?", r"drivers?", r"silhouette of a", r"teen\w*", r"youth",
        r"elderly", r"senior", r"backpackers?", r"explorers?", r"vendors?",
        r"sellers?", r"shepherds?", r"nomads?", r"bedouins?",
    ]))),
    "religion": re.compile(_W.format("|".join([
        r"church\w*", r"cathedral", r"chapel", r"basilica", r"abbey", r"monastery",
        r"convent", r"cross(?:es)?", r"crucifix\w*", r"jesus", r"christ", r"christian\w*",
        r"christmas", r"xmas", r"santa", r"nativity", r"angels?", r"saints?",
        r"madonna", r"virgin mary", r"bible", r"easter", r"temples?", r"buddh\w*",
        r"hindu\w*", r"shiva", r"ganesh\w*", r"krishna", r"pagodas?", r"stupa",
        r"shrines?", r"torii", r"shinto", r"idols?", r"statues?", r"sculptures?",
        r"synagogue", r"menorah", r"hanukkah", r"diwali", r"halloween", r"pumpkins?",
        r"jack-o-lantern", r"skulls?", r"skeleton", r"devil", r"demons?", r"witch\w*",
        r"ghosts?", r"zombies?", r"zodiac", r"horoscope", r"tarot", r"occult",
        r"pentagram", r"gravestones?", r"tombstones?", r"cemetery", r"graveyard",
        r"graves?", r"coffin", r"totem", r"gargoyles?", r"tombs?", r"mausoleum",
        r"tajmahal", r"taj mahal", r"deity", r"gods?", r"goddess",
    ]))),
    "vice": re.compile(_W.format("|".join([
        r"wines?", r"vineyards?", r"winery", r"beers?", r"brewery", r"whiske?y",
        r"vodka", r"champagne", r"cocktails?", r"alcohol\w*", r"liquor", r"booze",
        r"pubs?", r"bars?", r"nightclub", r"clubbing", r"party", r"parties",
        r"casino", r"gambling", r"poker", r"cigarettes?", r"cigars?", r"smoking",
        r"smoker", r"tobacco", r"hookah", r"shisha", r"vap(?:e|ing)", r"drugs?",
        r"cannabis", r"marijuana", r"pork", r"pigs?", r"bacon", r"valentines?",
        r"kiss", r"kissing", r"lovers", r"honeymoon", r"fireworks?",
    ]))),
    "music": re.compile(_W.format("|".join([
        r"guitars?", r"pianos?", r"violins?", r"cello", r"drums?", r"drummer",
        r"trumpet", r"saxophone", r"flute", r"harp", r"ukulele", r"music\w*",
        r"concerts?", r"festival", r"dj", r"disco", r"orchestra", r"singers?",
        r"singing", r"microphone", r"headphones", r"vinyl", r"karaoke", r"rave",
    ]))),
    "nudity": re.compile(_W.format("|".join([
        r"nudes?", r"naked", r"nudity", r"sexy", r"sex", r"erotic", r"sensual",
        r"bikinis?", r"lingerie", r"underwear", r"topless", r"shirtless",
        r"swimsuit", r"swimwear", r"bra", r"seductive", r"boudoir", r"breasts?",
        r"butt", r"buttocks", r"cleavage",
    ]))),
    "art": re.compile(_W.format("|".join([
        r"ai", r"ai-generated", r"generated", r"generative", r"midjourney",
        r"stable diffusion", r"dall-?e", r"neural", r"digital art", r"digital painting",
        r"artwork", r"illustrat\w+", r"render", r"rendering", r"rendered", r"3d", r"cgi",
        r"blender", r"octane", r"unreal", r"fantasy", r"fairy\w*", r"dragons?",
        r"unicorns?", r"elf", r"elves", r"wizard", r"anime", r"manga", r"cartoon",
        r"comic", r"drawing", r"drawn", r"sketch", r"painting", r"watercolou?r",
        r"vector", r"clip ?art", r"concept art", r"surreal\w*", r"sci-?fi",
        r"science fiction", r"aliens?", r"ufo", r"spaceship", r"planets?",
        r"futuristic", r"cyberpunk", r"steampunk", r"apocalyp\w+", r"dystopi\w+",
        r"matte painting", r"photomontage", r"manipulation", r"collage", r"mockup",
        r"mock-up", r"template", r"pattern background", r"seamless",
    ]))),
    "text": re.compile(_W.format("|".join([
        r"text", r"texts", r"quotes?", r"quotation", r"typography", r"lettering",
        r"letters?", r"calligraph\w+", r"fonts?", r"words?", r"signs?", r"signage",
        r"signboard", r"billboard", r"logos?", r"banners?", r"posters?", r"flyer",
        r"cards?", r"greetings?", r"kareem", r"mubarak", r"label", r"caption",
        r"headline", r"newspaper", r"magazine", r"books?", r"quran", r"koran",
        r"mushaf", r"document", r"screenshot", r"qr", r"barcode", r"meme",
        r"infographic", r"charts?", r"graph", r"maps?", r"flags?", r"emoji",
        r"icons?", r"stickers?", r"invitation", r"brochure", r"newsletter",
    ]))),
    "animal": re.compile(_W.format("|".join([
        r"dogs?", r"pupp(?:y|ies)", r"cats?", r"kittens?", r"horses?", r"pony",
        r"cows?", r"cattle", r"bulls?", r"sheep", r"lambs?", r"goats?", r"deer",
        r"elk", r"moose", r"bears?", r"wol(?:f|ves)", r"fox(?:es)?", r"lions?",
        r"tigers?", r"leopards?", r"cheetahs?", r"elephants?", r"giraffes?",
        r"zebras?", r"monkeys?", r"apes?", r"gorillas?", r"squirrels?", r"rabbits?",
        r"bunn(?:y|ies)", r"hares?", r"mouse", r"mice", r"rats?", r"insects?",
        r"butterfl(?:y|ies)", r"bees?", r"wasps?", r"ants?", r"spiders?", r"snakes?",
        r"lizards?", r"frogs?", r"toads?", r"turtles?", r"tortoises?", r"owls?",
        r"parrots?", r"peacocks?", r"swans?", r"ducks?", r"geese", r"goose",
        r"chickens?", r"hens?", r"roosters?", r"flamingos?", r"penguins?", r"seals?",
        r"whales?", r"dolphins?", r"sharks?", r"jellyfish", r"fish", r"octopus",
        r"crabs?", r"snails?", r"beetles?", r"dragonfl(?:y|ies)", r"ladybugs?",
        r"pets?", r"animals?", r"zoo", r"safari", r"camel rider",
    ]))),
    "vehicle": re.compile(_W.format("|".join([
        r"cars?", r"trucks?", r"vehicles?", r"motorcycles?", r"motorbikes?",
        r"bikes?", r"bicycles?", r"bus", r"buses", r"vans?", r"jeeps?", r"suv",
        r"taxi", r"airplane", r"aeroplane", r"helicopter", r"drone shot of a car",
    ]))),
}


# Pexels tags a person-free photo "No People"; that is the opposite of a
# hit, so phrases saying nobody is there are taken out before matching.
_NOBODY = re.compile(r"(?<![a-z])(?:no|without|zero|0) (?:people|persons?|humans?|one)(?![a-z])"
                     r"|(?<![a-z])(?:nobody|unpeopled|people-free|person-free)(?![a-z])")
# Light trails are traffic, and a road or a drone shot over farmland has a
# car or two in it; the person detector judges those by size instead.
_VEHICLE_OK = {"road", "aerial_land"}


def blocked_by_text(c):
    """The first rule a candidate's own published words break, or None."""
    text = " ".join(str(x) for x in (
        c.get("title"), c.get("alt"), c.get("desc"), " ".join(c.get("tags") or []),
        re.sub(r"[-_/]+", " ", c.get("slug") or ""))).lower()
    text = _NOBODY.sub(" ", text)
    for reason, rx in BLOCK.items():
        if reason == "vehicle" and c.get("category") in _VEHICLE_OK:
            continue
        if rx.search(text):
            return reason
    return None


# ── plain HTTP ──────────────────────────────────────────────────────────

class Pace:
    """At most one request per `gap` seconds to each host, across threads."""

    def __init__(self):
        self.lock = threading.Lock()
        self.next = {}

    def wait(self, host, gap):
        with self.lock:
            now = time.time()
            t = max(now, self.next.get(host, 0.0))
            self.next[host] = t + gap
        if t > now:
            time.sleep(t - now)


PACE = Pace()
GAPS = {"api.openverse.org": 3.3, "commons.wikimedia.org": 0.6, "mixkit.co": 1.0,
        "upload.wikimedia.org": 0.15, "thumb.wikimedia.org": 0.15}


def http(url, hdrs=None, timeout=45, method="GET", rng=None, tries=3):
    """(status, headers, body). Retries throttling and server errors."""
    host = urllib.parse.urlsplit(url).hostname or ""
    h = dict(hdrs or {"User-Agent": UA, "Accept": "*/*"})
    if "wikimedia.org" in host or "wikipedia.org" in host:
        h["User-Agent"] = WIKI_UA
    if rng:
        h["Range"] = rng
    last = (-1, {}, b"")
    for attempt in range(tries):
        PACE.wait(host, GAPS.get(host, 0.0))
        try:
            req = urllib.request.Request(url, headers=h, method=method)
            with urllib.request.urlopen(req, timeout=timeout) as r:
                body = b"" if method == "HEAD" else r.read()
                return r.status, dict(r.headers), body
        except urllib.error.HTTPError as e:
            last = (e.code, dict(e.headers or {}), b"")
            if e.code in (429, 500, 502, 503, 504):
                wait = float((e.headers or {}).get("Retry-After") or 0) or (4 * (attempt + 1))
                time.sleep(min(wait, 60))
                continue
            return last
        except Exception as e:
            last = (-1, {}, str(e).encode())
            time.sleep(2 * (attempt + 1))
    return last


def get_json(url, hdrs=None):
    s, _, body = http(url, hdrs or {"User-Agent": UA, "Accept": "application/json"})
    if s != 200:
        return None, s
    try:
        return json.loads(body.decode("utf-8", "replace")), s
    except Exception:
        return None, s


def head_ok(url, hdrs=None, min_bytes=20000):
    """True when `url` answers 200/206 with a body bigger than a placeholder."""
    s, h, _ = http(url, hdrs, method="HEAD", tries=2)
    if s not in (200, 206):
        # Some CDNs refuse HEAD; a one-byte range answers the same question.
        s, h, _ = http(url, hdrs, rng="bytes=0-0", tries=2)
        if s not in (200, 206):
            return False
        cr = h.get("Content-Range") or h.get("content-range") or ""
        m = re.search(r"/(\d+)$", cr)
        return bool(m) and int(m.group(1)) >= min_bytes
    n = int(h.get("Content-Length") or h.get("content-length") or 0)
    return n == 0 or n >= min_bytes


# ── a real browser, for the two sites that stop anything else ───────────

class Browser:
    """One browser page, used sequentially. Cloudflare answers the first
    visit (and now and then a later one) with an interstitial that a real
    browser clears by itself in a few seconds; get() waits it out.

    engine: "playwright" (stock Chromium), "patchright" (Playwright with
    the automation tells removed, driving the runner's own Google Chrome)
    or "camoufox" (a Firefox built to look like an ordinary one). Headed
    runs need a display: the workflow wraps them in xvfb-run."""

    def __init__(self, engine=None, headed=None):
        self.engine = engine or os.environ.get("SCENES_BROWSER", "playwright")
        self.headed = (os.environ.get("SCENES_HEADED") == "1") if headed is None else headed
        self.captured = []
        self.pw = self.browser = self.ctx = self._cm = None
        if self.engine == "camoufox":
            from camoufox.sync_api import Camoufox
            self._cm = Camoufox(headless=not self.headed, locale="en-US")
            self.browser = self._cm.__enter__()
        elif self.engine == "patchright":
            from patchright.sync_api import sync_playwright
            self.pw = sync_playwright().start()
        else:
            from playwright.sync_api import sync_playwright
            self.pw = sync_playwright().start()
            self.browser = self.pw.chromium.launch(
                headless=not self.headed,
                args=["--disable-blink-features=AutomationControlled"])
            major = (self.browser.version or "130").split(".")[0]
            self.ua = ("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) "
                       f"Chrome/{major}.0.0.0 Safari/537.36")
        self._new_context()

    def _new_context(self):
        try:
            if self.ctx:
                self.ctx.close()
        except Exception:
            pass
        if self.engine == "patchright":
            # Patchright's own advice: a persistent profile, the real Chrome,
            # and no user agent or header overrides.
            import shutil
            import tempfile
            prof = tempfile.mkdtemp(prefix="scenes-chrome-")
            kw = {"user_data_dir": prof, "headless": not self.headed, "no_viewport": True}
            if shutil.which("google-chrome") or shutil.which("google-chrome-stable"):
                kw["channel"] = "chrome"
            self.ctx = self.pw.chromium.launch_persistent_context(**kw)
            self.page = self.ctx.pages[0] if self.ctx.pages else self.ctx.new_page()
        elif self.engine == "camoufox":
            self.ctx = self.browser.new_context()
            self.page = self.ctx.new_page()
        else:
            self.ctx = self.browser.new_context(
                user_agent=self.ua, locale="en-US", viewport={"width": 1440, "height": 1000})
            self.ctx.add_init_script(
                "Object.defineProperty(navigator,'webdriver',{get:()=>undefined})")

            # The pictures are fetched later, at the size we need; the page
            # only has to tell us what exists. Challenge assets still load.
            def route(r):
                u = r.request.url
                if r.request.resource_type in ("image", "media", "font") and any(
                        s in u for s in ("images.pexels.com", "videos.pexels.com",
                                         "cdn.pixabay.com", "static.pexels.com")):
                    return r.abort()
                return r.continue_()
            self.ctx.route("**/*", route)
            self.page = self.ctx.new_page()

        def on_response(resp):
            u = resp.url
            if "/bootstrap/" in u or "/api/v3/" in u:
                try:
                    self.captured.append((u, resp.text()))
                except Exception:
                    pass
        self.page.on("response", on_response)

    def scroll(self, times=3, pause=1.6):
        """Scroll to the bottom a few times: an infinite-scroll page fetches
        its next pages as XHR, which Cloudflare lets through on a cleared
        session where a fresh navigation would be challenged again."""
        for _ in range(times):
            try:
                self.page.mouse.wheel(0, 24000)
            except Exception:
                try:
                    self.page.evaluate("window.scrollTo(0, document.body.scrollHeight)")
                except Exception:
                    pass
            time.sleep(pause)

    def get(self, url, ready, tries=3, settle=0.8):
        """HTML of `url` once `ready` (a regex) appears in it, or ''."""
        for attempt in range(tries):
            self.captured = []
            try:
                self.page.goto(url, wait_until="domcontentloaded", timeout=60000)
            except Exception as e:
                log(f"    browser {url[:90]}: {str(e)[:120]}")
                time.sleep(3)
                continue
            deadline = time.time() + 35
            html = ""
            while time.time() < deadline:
                try:
                    html = self.page.content()
                except Exception:
                    html = ""
                if re.search(ready, html):
                    time.sleep(settle)
                    try:
                        html = self.page.content()
                    except Exception:
                        pass
                    return html
                if ("No results" in html or "We couldn't find" in html
                        or re.search(r"<title>[^<]*Download 0\+", html)):
                    return html
                time.sleep(1.0)
            title = re.findall(r"<title>(.*?)</title>", html or "")[:1]
            log(f"    browser not ready ({title}) {url[:100]} attempt {attempt + 1}")
            if attempt == 1:
                self._new_context()
            time.sleep(4 + 4 * attempt)
        return ""

    def close(self):
        for f in (lambda: self.ctx and self.ctx.close(),
                  lambda: self.browser and self.engine != "camoufox" and self.browser.close(),
                  lambda: self._cm and self._cm.__exit__(None, None, None),
                  lambda: self.pw and self.pw.stop()):
            try:
                f()
            except Exception:
                pass


# ── discovery ───────────────────────────────────────────────────────────

def _cand(**kw):
    c = {"title": "", "alt": "", "desc": "", "tags": [], "slug": "",
         "author": None, "author_url": None, "w": 0, "h": 0, "dur": 0.0,
         "ai": False}
    c.update(kw)
    return c


def _shape_ok(bucket, w, h):
    """Portrait wants a frame at least as tall as wide, wide one clearly
    landscape; unknown sizes pass and are judged once fetched."""
    if not w or not h:
        return True
    return h >= w * 1.05 if bucket == "vertical" else w >= h * 1.3


def _next_data(html):
    m = re.search(r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>', html, re.S)
    if not m:
        return None
    try:
        return json.loads(m.group(1))
    except Exception:
        return None


PEXELS_VID_RX = re.compile(
    r"https://videos\.pexels\.com/video-files/(\d+)/[\w.-]+?"
    r"(?:(sd|hd|uhd)_(\d+)_(\d+)_(\d+)fps)?\.mp4")


def pexels_items(html, kind, bucket, cat, query, sample_dir=None):
    d = _next_data(html)
    if not d:
        return [], None
    try:
        pp = d["props"]["pageProps"]
        items = pp["initialData"]["data"]
        filters = pp.get("filters")
    except Exception:
        return [], None
    return pexels_parse(items, kind, bucket, cat, query), filters


def pexels_api_items(captured, kind, bucket, cat, query, offset=0):
    """Items from the search API pages the site fetched while scrolling."""
    out = []
    for url, body in captured:
        if "/api/v3/" not in url or "search" not in url:
            continue
        try:
            items = json.loads(body).get("data") or []
        except Exception:
            continue
        out += pexels_parse(items, kind, bucket, cat, query, offset + len(out))
    return out


def pexels_parse(items, kind, bucket, cat, query, offset=0):
    out = []
    for rank, it in enumerate(items, offset):
        a = it.get("attributes") or {}
        if it.get("type") != ("photo" if kind == "image" else "video"):
            continue
        pid = a.get("id") or it.get("id")
        if not pid:
            continue
        u = a.get("user") or {}
        author = " ".join(x for x in (u.get("first_name"), u.get("last_name")) if x).strip() \
            or u.get("username")
        slug = a.get("slug") or ""
        c = _cand(
            key=f"pexels_{pid}", src_id=str(pid), source="pexels", kind=kind,
            bucket=bucket, category=cat, query=query, rank=rank,
            title=a.get("title") or "", alt=a.get("alt") or "",
            desc=a.get("description") or "", slug=slug,
            tags=[t.get("name", "") for t in (a.get("tags") or []) if isinstance(t, dict)],
            author=author or None,
            author_url=f"https://www.pexels.com/@{u.get('slug') or u.get('username')}"
            if (u.get("slug") or u.get("username")) else None,
            w=int(a.get("width") or 0), h=int(a.get("height") or 0),
            license_raw=a.get("license"),
            page=f"https://www.pexels.com/{'photo' if kind == 'image' else 'video'}/"
                 f"{slug + '-' if slug else ''}{pid}/")
        if kind == "image":
            long_edge = "h=2400" if bucket == "vertical" else "w=2400"
            c["media"] = (f"https://images.pexels.com/photos/{pid}/pexels-photo-{pid}.jpeg"
                          f"?auto=compress&cs=tinysrgb&{long_edge}")
            score_edge = "h=1600" if bucket == "vertical" else "w=1600"
            c["score_url"] = (f"https://images.pexels.com/photos/{pid}/pexels-photo-{pid}.jpeg"
                              f"?auto=compress&cs=tinysrgb&{score_edge}")
        else:
            c["dur"] = float(a.get("duration") or 0)
            files = {}
            for m in PEXELS_VID_RX.finditer(json.dumps(it)):
                if m.group(1) != str(pid):
                    continue
                files[m.group(0)] = (m.group(2), int(m.group(3) or 0), int(m.group(4) or 0),
                                     int(m.group(5) or 0))
            c["pexels_files"] = files
        out.append(c)
    return out


def discover_pexels(tab):
    """Pexels search pages, read from the data the page embeds.

    Measured on a runner (`probe`): a headless browser is challenged on
    most navigations and gets through about half; the same Chromium
    headed, under Xvfb, read six pages out of six in 25 s. The workflow
    therefore runs discovery under xvfb-run with SCENES_HEADED=1.
    `people_count=0` is Pexels' own "no people" filter; the page echoes
    it back in its filters, which the first log line shows."""
    bucket = TAB_BUCKET[tab]
    orient = "portrait" if bucket == "vertical" else "landscape"
    # Wide tabs are mostly footage, portrait tabs mostly stills.
    pages = {"image": (1, 2) if bucket == "vertical" else (1,),
             "video": (1,) if bucket == "vertical" else (1, 2)}
    # SCENES_ONLY=pexels-video: a supplementary pass for Pexels' clips alone.
    kinds = ("video",) if os.environ.get("SCENES_ONLY") == "pexels-video" else ("image", "video")
    br = Browser()
    out, n_nav, n_ok, sample_saved = [], 0, 0, False
    misses = run_of_misses = 0
    try:
        for cat in TAB_CATS[tab]:
            for q in queries_for(cat):
                qq = urllib.parse.quote(q)
                for kind in kinds:
                    path = "search" if kind == "image" else "search/videos"
                    for pg in pages[kind]:
                        url = (f"https://www.pexels.com/{path}/{qq}/?orientation={orient}"
                               f"&people_count=0" + (f"&page={pg}" if pg > 1 else ""))
                        html = br.get(url, r'id="__NEXT_DATA__"', tries=2)
                        n_nav += 1
                        items, filters = pexels_items(html, kind, bucket, cat, q)
                        if items:
                            n_ok += 1
                            misses = run_of_misses = 0
                            for c in items:
                                c["rank"] += (pg - 1) * 24
                        else:
                            misses += 1
                            run_of_misses += 1
                            # A run of refusals: start over with a fresh
                            # profile, which Cloudflare treats as a first visit.
                            if misses >= 2:
                                br._new_context()
                                misses = 0
                        if not sample_saved and kind == "video" and items:
                            with open(os.path.join(tab_dir(tab), "sample_pexels_video.html"),
                                      "w", encoding="utf-8") as f:
                                f.write(html)
                            sample_saved = True
                        if n_nav <= 2 or n_nav % 20 == 0:
                            log(f"  pexels #{n_nav} ({n_ok} ok) {kind} {q!r} p{pg}: "
                                f"{len(items)} items, filters={filters}")
                        out += items
                        time.sleep(random.uniform(0.5, 1.2))
                        if len(items) < 12:
                            break
                    if run_of_misses >= 12:
                        log("  pexels: twelve refusals in a row; giving up on this runner")
                        raise StopIteration
    except StopIteration:
        pass
    finally:
        br.close()
    log(f"pexels: {len(out)} raw from {n_ok}/{n_nav} pages")
    return out


def pixabay_items(html, kind, bucket, cat, query):
    out = []
    cells = re.split(r'<div class="cell--', html)[1:]
    for rank, cell in enumerate(cells):
        if kind == "image":
            m = re.search(r'href="/photos/([a-z0-9-]+)-(\d+)/"', cell)
        else:
            m = re.search(r'href="/videos/([a-z0-9-]+)-(\d+)/"', cell)
        if not m:
            continue
        slug, pid = m.group(1), m.group(2)
        mw = re.search(r"max-width:\s*(\d+)px;\s*max-height:\s*(\d+)px", cell)
        w, h = (int(mw.group(1)), int(mw.group(2))) if mw else (0, 0)
        alt = htmlmod.unescape((re.search(r'<img alt="([^"]*)"', cell) or [None, ""])[1])
        ai = 'aria-label="AI"' in cell or "ai-generated" in slug or "AI-generated" in alt
        c = _cand(source="pixabay", kind=kind, bucket=bucket, category=cat, query=query,
                  rank=rank, slug=slug, alt=alt, w=w, h=h, ai=ai, src_id=pid,
                  page=f"https://pixabay.com/{'photos' if kind == 'image' else 'videos'}/"
                       f"{slug}-{pid}/")
        if kind == "image":
            src = re.search(r"https://cdn\.pixabay\.com/photo/[\d/]+/([\w-]+?)_(?:1280|640)\.jpg",
                            cell)
            if not src:
                continue
            stem = src.group(1)
            base = src.group(0).rsplit("_", 1)[0]
            c.update(key=f"pixabay_{stem}", media=base + "_1280.jpg",
                     score_url=base + "_1280.jpg", media_alt=base + "_1920.jpg")
        else:
            src = re.search(r"https://cdn\.pixabay\.com/video/[\d/]+/([\w-]+?)_tiny\.(?:mp4|jpg)",
                            cell)
            if not src:
                continue
            stem = src.group(1)
            base = src.group(0).rsplit("_", 1)[0]
            c.update(key=f"pixabay_{stem}", pixabay_base=base)
            dm = re.search(r">(\d+):(\d\d)<", cell)
            if dm:
                c["dur"] = float(int(dm.group(1)) * 60 + int(dm.group(2)))
        out.append(c)
    return out


def discover_pixabay(tab):
    bucket = TAB_BUCKET[tab]
    orient = "vertical" if bucket == "vertical" else "horizontal"
    br = Browser()
    out, n_req, saved = [], 0, False
    try:
        for cat in TAB_CATS[tab]:
            for q in queries_for(cat):
                qq = urllib.parse.quote(q)
                # A page is a hundred results; the wide tabs, which are mostly
                # drone footage, read a second page of clips.
                plan = [("image", 1), ("video", 1)]
                if bucket == "horizontal":
                    plan.append(("video", 2))
                for kind, pg in plan:
                    more = f"&pagi={pg}" if pg > 1 else ""
                    if kind == "image":
                        url = f"https://pixabay.com/photos/search/{qq}/?orientation={orient}{more}"
                        ready = r'href="/photos/[a-z0-9-]+-\d+/"'
                    else:
                        url = f"https://pixabay.com/videos/search/{qq}/?orientation={orient}{more}"
                        ready = r'href="/videos/[a-z0-9-]+-\d+/"'
                    html = br.get(url, ready, settle=1.5)
                    n_req += 1
                    items = pixabay_items(html, kind, bucket, cat, q)
                    for c in items:
                        c["rank"] += (pg - 1) * 100
                    if not saved and br.captured:
                        with open(os.path.join(tab_dir(tab), "sample_pixabay_bootstrap.json"),
                                  "w", encoding="utf-8") as f:
                            f.write(br.captured[0][1][:3_000_000])
                        saved = True
                    if n_req <= 2 or n_req % 25 == 0:
                        log(f"  pixabay #{n_req} {kind} {q!r} p{pg}: {len(items)} items "
                            f"({sum(1 for i in items if i['ai'])} AI)")
                    out += items
                    time.sleep(random.uniform(0.6, 1.4))
                    if len(items) < 50 and kind == "video":
                        break
    finally:
        br.close()
    log(f"pixabay: {len(out)} raw from {n_req} pages")
    return out


def mixkit_items(html, bucket, cat, query, page_url):
    out = []
    seen = set()
    for m in re.finditer(r'href="/free-stock-video/([a-z0-9-]+)-(\d+)/"', html):
        slug, vid = m.group(1), m.group(2)
        if vid in seen:
            continue
        seen.add(vid)
        # The card around the link: thumb size gives the shape.
        lo = html.rfind("item-grid-card", 0, m.start())
        chunk = html[lo if lo >= 0 else max(0, m.start() - 4000): m.end() + 200]
        ts = re.search(r'alt="([^"]*)" width="(\d+)" height="(\d+)"', chunk)
        tw, th = (int(ts.group(2)), int(ts.group(3))) if ts else (0, 0)
        prev = re.search(r'<video src="(https://assets\.mixkit\.co/[^"]+\.mp4)"', chunk)
        desc = re.search(r'overlay-video-description">\s*(.*?)\s*</span>', chunk, re.S)
        out.append(_cand(
            key=f"mixkit_{vid}", src_id=vid, source="mixkit", kind="video", bucket=bucket,
            category=cat, query=query, rank=len(out), slug=slug,
            title=htmlmod.unescape(ts.group(1)) if ts else slug.replace("-", " "),
            desc=htmlmod.unescape(desc.group(1)) if desc else "",
            w=tw, h=th, preview=prev.group(1) if prev else None,
            page=f"https://mixkit.co/free-stock-video/{slug}-{vid}/"))
    return out


def discover_mixkit(tab):
    bucket = TAB_BUCKET[tab]
    out = []
    for cat in TAB_CATS[tab]:
        topics = MIXKIT_TOPICS.get(cat, [])
        if QUERY_LIMIT:
            topics = topics[:1]
        for topic in topics:
            for pg in (1, 2, 3):
                url = (f"https://mixkit.co/free-stock-video/discover/{topic}/"
                       + (f"?page={pg}" if pg > 1 else ""))
                s, _, body = http(url, HDRS)
                if s != 200:
                    break
                items = mixkit_items(body.decode("utf-8", "replace"), bucket, cat, topic, url)
                out += items
                if len(items) < 10:
                    break
    log(f"mixkit: {len(out)} raw")
    return out


def discover_openverse(tab, budget):
    bucket = TAB_BUCKET[tab]
    aspect = "tall" if bucket == "vertical" else "wide"
    out, used = [], 0
    for cat in TAB_CATS[tab]:
        for q in queries_for(cat)[:12]:
            for pg in (1, 2):
                if used >= budget:
                    break
                url = ("https://api.openverse.org/v1/images/?" + urllib.parse.urlencode({
                    "q": q, "license": "cc0,pdm", "aspect_ratio": aspect, "size": "large",
                    "page_size": 20, "page": pg, "mature": "false"}))
                d, s = get_json(url)
                used += 1
                if not d:
                    if s == 429:
                        log("  openverse: rate limited, stopping")
                        return out
                    break
                res = d.get("results") or []
                for rank, r in enumerate(res):
                    lic = (r.get("license") or "").lower()
                    if lic not in ("cc0", "pdm"):
                        continue
                    out.append(_cand(
                        key=f"openverse_{(r.get('id') or '')[:12]}", src_id=r.get("id"),
                        source="openverse", kind="image", bucket=bucket, category=cat,
                        query=q, rank=rank, title=r.get("title") or "",
                        tags=[t.get("name", "") for t in (r.get("tags") or [])][:40],
                        author=r.get("creator"), author_url=r.get("creator_url"),
                        w=int(r.get("width") or 0), h=int(r.get("height") or 0),
                        lic=lic, license_url=r.get("license_url"),
                        provider=r.get("source") or r.get("provider"),
                        page=r.get("foreign_landing_url"), media=r.get("url"),
                        score_url=r.get("url")))
                if len(res) < 20:
                    break
    log(f"openverse: {len(out)} raw from {used} requests")
    return out


def _strip_tags(s):
    return htmlmod.unescape(re.sub(r"<[^>]+>", "", s or "")).strip()


def discover_commons(tab):
    bucket = TAB_BUCKET[tab]
    size_kw = "fileh:>1800" if bucket == "vertical" else "filew:>1800"
    # Wikimedia serves thumbnails at a fixed ladder of widths now; 1920 is
    # on it and covers both frames without upscaling.
    width = 1920
    out = []
    for cat in TAB_CATS[tab]:
        for q in queries_for(cat)[:16]:
            for lic_kw in ("hastemplate:Cc-zero", "hastemplate:PD-self", "hastemplate:PD-USGov"):
                url = ("https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode({
                    "action": "query", "format": "json", "generator": "search",
                    "gsrsearch": f"{q} filetype:bitmap {size_kw} {lic_kw}",
                    "gsrnamespace": 6, "gsrlimit": 30, "prop": "imageinfo",
                    "iiprop": "url|size|extmetadata", "iiurlwidth": width}))
                d, s = get_json(url, {"User-Agent": WIKI_UA, "Accept": "application/json"})
                if not d:
                    continue
                pages = (d.get("query") or {}).get("pages") or {}
                for pid, p in pages.items():
                    ii = (p.get("imageinfo") or [{}])[0]
                    em = ii.get("extmetadata") or {}
                    val = lambda k: (em.get(k) or {}).get("value") or ""
                    lic = val("License").lower()
                    short = val("LicenseShortName")
                    if lic in ("cc0",) or short.upper().startswith("CC0"):
                        lic = "cc0"
                    elif lic.startswith("pd") or short.lower().startswith("public domain"):
                        lic = "pd"
                    else:
                        continue
                    restr = val("Restrictions").lower()
                    if "personality" in restr or "trademark" in restr:
                        continue
                    w, h = int(ii.get("width") or 0), int(ii.get("height") or 0)
                    title = (p.get("title") or "").replace("File:", "")
                    out.append(_cand(
                        key=f"commons_{pid}", src_id=pid, source="commons", kind="image",
                        bucket=bucket, category=cat, query=q, rank=int(p.get("index") or 0),
                        title=title.rsplit(".", 1)[0], desc=_strip_tags(val("ImageDescription"))[:400],
                        tags=[x for x in val("Categories").split("|") if x][:30],
                        author=_strip_tags(val("Artist"))[:120] or None,
                        w=w, h=h, lic=lic, license_url=val("LicenseUrl") or None,
                        license_name=short or None,
                        page=f"https://commons.wikimedia.org/?curid={pid}",
                        media=(ii.get("url") or "").split("?")[0],
                        score_url=(ii.get("thumburl") or ii.get("url") or "").split("?")[0]))
    log(f"commons: {len(out)} raw")
    return out


def discover(tab, site):
    t0 = time.time()
    if site == "pexels":
        cands = discover_pexels(tab)
    elif site == "pixabay":
        cands = discover_pixabay(tab)
    elif site == "open":
        budget = int(os.environ.get("SCENES_OPENVERSE_BUDGET", "150"))
        with futures.ThreadPoolExecutor(max_workers=3) as ex:
            f1 = ex.submit(discover_mixkit, tab)
            f2 = ex.submit(discover_openverse, tab, budget)
            f3 = ex.submit(discover_commons, tab)
            cands = []
            for f in (f1, f2, f3):
                try:
                    cands += f.result()
                except Exception as e:
                    log(f"  open source failed: {e}")
    else:
        raise SystemExit(f"unknown site {site}")
    for c in cands:
        c["tab"] = tab
    with open(os.path.join(tab_dir(tab), f"disc_{site}.json"), "w", encoding="utf-8") as f:
        json.dump(cands, f)
    log(f"discover {tab}/{site}: {len(cands)} in {time.time() - t0:.0f}s")


# ── fetch, frame and score ──────────────────────────────────────────────

_LIB = None


def library():
    """dHash of every scene already in the app, from its bundled poster."""
    global _LIB
    if _LIB is None:
        import curate_scenes as cs
        from PIL import Image
        cat = json.load(open(os.path.join(ROOT, "assets", "catalog.json"), encoding="utf-8"))
        lib = []
        for s in cat["scenes"]:
            p = os.path.join(ROOT, "assets", "scene_thumbs", s["id"] + ".jpg")
            if os.path.exists(p):
                lib.append((s["id"], cs.dhash(Image.open(p).convert("RGB"))))
        _LIB = lib
    return _LIB


def lib_nearest(h):
    import curate_scenes as cs
    best = (99, None)
    for sid, lh in library():
        d = cs.hamming(h, lh)
        if d < best[0]:
            best = (d, sid)
    return best


def merge_discoveries(tab):
    """Every site's candidates for the tab, deduplicated, judged on their
    own words, licence-checked and capped so the fetch stays bounded."""
    bucket = TAB_BUCKET[tab]
    allc = []
    for site in ("pexels", "pixabay", "open"):
        p = os.path.join(tab_dir(tab), f"disc_{site}.json")
        if os.path.exists(p):
            allc += json.load(open(p, encoding="utf-8"))
    import curate_scenes as cs
    deny_ids, _ = cs._denylist()
    seen, out = {}, []
    drops = {}

    def drop(c, why):
        drops[why] = drops.get(why, 0) + 1
        c["drop"] = why

    for c in allc:
        k = c.get("key")
        if not k:
            continue
        if k in seen:
            # The same item from another query: keep the better rank.
            o = seen[k]
            o["rank"] = min(o.get("rank", 99), c.get("rank", 99))
            o.setdefault("queries", [o["query"]])
            if c["query"] not in o["queries"]:
                o["queries"].append(c["query"])
            continue
        seen[k] = c
        if k in deny_ids or f"{c['source']}_{c.get('src_id')}" in deny_ids:
            drop(c, "denylist")
        elif c.get("ai"):
            drop(c, "ai-labelled")
        elif not _shape_ok(bucket, c.get("w"), c.get("h")):
            drop(c, "shape")
        else:
            why = blocked_by_text(c)
            if why:
                drop(c, "words:" + why)
        out.append(c)
    keep = [c for c in out if not c.get("drop")]
    # Caps: best-ranked first, round-robin over categories so one prolific
    # query cannot eat the budget.
    caps = {"image": int(os.environ.get("SCENES_CAP_IMAGES", "4000")),
            "video": int(os.environ.get("SCENES_CAP_VIDEOS",
                                        "600" if bucket == "vertical" else "1100"))}
    chosen = []
    for kind in ("image", "video"):
        pool = [c for c in keep if c["kind"] == kind]
        by_cat = {}
        for c in sorted(pool, key=lambda c: (c.get("rank", 99), c["source"])):
            by_cat.setdefault(c["category"], []).append(c)
        taken = 0
        while taken < caps[kind] and any(by_cat.values()):
            for cat in sorted(by_cat):
                if by_cat[cat] and taken < caps[kind]:
                    chosen.append(by_cat[cat].pop(0))
                    taken += 1
        for rest in by_cat.values():
            for c in rest:
                drop(c, "cap")
    log(f"merge {tab}: {len(allc)} raw, {len(out)} unique, {len(chosen)} to fetch; "
        f"dropped {drops}")
    return out, chosen, drops


def _img_from_bytes(data):
    from PIL import Image, ImageOps
    import io
    im = Image.open(io.BytesIO(data))
    im = ImageOps.exif_transpose(im)
    return im.convert("RGB")


IMG_HDRS = {"User-Agent": UA, "Accept": "image/jpeg,image/png,image/*;q=0.8,*/*;q=0.5",
            "Referer": "https://www.google.com/"}


def fetch_image(c):
    """The scoring rendition as a PIL image, trying larger editions of
    Flickr/Wikimedia files where the listed one is a small preview."""
    urls = [c.get("score_url")]
    u = c.get("score_url") or ""
    if "staticflickr.com" in u:
        urls = [re.sub(r"_[a-z]\.jpg$", "_k.jpg", u), re.sub(r"_[a-z]\.jpg$", "_h.jpg", u), u]
    elif "upload.wikimedia.org" in u and "/thumb/" not in u and c.get("w", 0) > 1920:
        m = re.match(r"(https://upload\.wikimedia\.org/wikipedia/commons)/(\w)/(\w\w)/(.+)$", u)
        if m:
            urls = [f"{m.group(1)}/thumb/{m.group(2)}/{m.group(3)}/{m.group(4)}/"
                    f"1920px-{m.group(4)}", u]
    elif "images.rawpixel.com/editor_1024" in u:
        urls = [u.replace("editor_1024", "editor_2048"), u]
    for url in urls:
        if not url:
            continue
        s, _, data = http(url, IMG_HDRS, timeout=90)
        if s == 200 and len(data) > 20000:
            try:
                im = _img_from_bytes(data)
            except Exception:
                continue
            if "staticflickr.com" in url or "rawpixel" in url:
                c["media"] = url
            return im
    return None


def ffprobe_url(url, hdrs=""):
    try:
        p = subprocess.run(
            ["ffprobe", "-v", "error", "-user_agent", UA, *(["-headers", hdrs] if hdrs else []),
             "-show_entries", "format=duration:stream=codec_type,width,height,avg_frame_rate",
             "-of", "json", url], capture_output=True, timeout=90)
        d = json.loads(p.stdout.decode() or "{}")
    except Exception:
        return None
    vs = [s for s in d.get("streams", []) if s.get("codec_type") == "video"]
    if not vs:
        return None
    try:
        num, den = (vs[0].get("avg_frame_rate") or "0/1").split("/")
        fps = float(num) / float(den or 1)
    except Exception:
        fps = 0.0
    return {"dur": float((d.get("format") or {}).get("duration") or 0),
            "w": int(vs[0].get("width") or 0), "h": int(vs[0].get("height") or 0),
            "fps": round(fps, 2), "streams": len(d.get("streams", []))}


def frame_at(url, t, out_path, long_edge=960, hdrs=""):
    vf = f"scale='if(gt(iw,ih),{long_edge},-2)':'if(gt(iw,ih),-2,{long_edge})'"
    try:
        r = subprocess.run(
            ["ffmpeg", "-v", "error", "-y", "-user_agent", UA,
             *(["-headers", hdrs] if hdrs else []), "-ss", f"{t:.2f}", "-i", url,
             "-frames:v", "1", "-vf", vf, "-q:v", "3", out_path],
            capture_output=True, timeout=120)
        return r.returncode == 0 and os.path.exists(out_path)
    except Exception:
        return False


def resolve_video(c):
    """(score_url, media_url, media_info) for a clip: a small rendition to
    look at and the best one at least the frame's size to keep."""
    want_short = 1080
    if c["source"] == "pexels":
        files = c.get("pexels_files") or {}         # url -> (tag, w, h, fps)
        fps_seen = sorted({v[3] for v in files.values() if v[3]}) or [30, 25, 24, 60, 50]
        known = sorted(files.items(), key=lambda kv: min(kv[1][1], kv[1][2]) or 9999)
        # Big enough for the person detector to see a figure on a ridge,
        # small enough to seek through quickly.
        small = next((u for u, v in known if v[1] and min(v[1], v[2]) >= 500), None) \
            or next((u for u, v in known if v[1] and min(v[1], v[2]) >= 360), None) \
            or (known[0][0] if known else None)
        pid = c["src_id"]
        big = [u for u, v in sorted(files.items(), key=lambda kv: min(kv[1][1], kv[1][2]))
               if v[1] and min(v[1], v[2]) >= want_short]
        if not big:
            vert = c["bucket"] == "vertical"
            dims = ([(1080, 1920), (2160, 3840), (1440, 2560)] if vert
                    else [(1920, 1080), (3840, 2160), (2560, 1440)])
            for (w, h) in dims:
                for fps in fps_seen:
                    tag = "uhd" if min(w, h) >= 2160 else "hd"
                    u = (f"https://videos.pexels.com/video-files/{pid}/"
                         f"{pid}-{tag}_{w}_{h}_{fps}fps.mp4")
                    if head_ok(u, IMG_HDRS):
                        big = [u]
                        break
                if big:
                    break
        if not small and big:
            small = big[0]
        return small, (big[0] if big else None)
    if c["source"] == "pixabay":
        base = c["pixabay_base"]
        hd = {**IMG_HDRS, "Referer": "https://pixabay.com/"}
        media = next((base + s for s in ("_large.mp4", "_medium.mp4")
                      if head_ok(base + s, hd)), None)
        small = next((base + s for s in ("_small.mp4", "_tiny.mp4") if head_ok(base + s, hd)),
                     None)
        return small or media, media
    if c["source"] == "mixkit":
        vid = c["src_id"]
        prev = c.get("preview") or f"https://assets.mixkit.co/videos/{vid}/{vid}-360.mp4"
        cands = [f"https://assets.mixkit.co/videos/{vid}/{vid}-{q}.mp4" for q in ("1080", "720")]
        if "active_storage" in prev:
            cands = [prev.replace("-360.mp4", f"-{q}.mp4") for q in ("1080", "720")] + cands
        media = next((u for u in cands if head_ok(u, IMG_HDRS)), None)
        small = prev.replace("-360.mp4", "-720.mp4") if head_ok(
            prev.replace("-360.mp4", "-720.mp4"), IMG_HDRS) else prev
        return small, media
    return None, None


def score_one(c):
    """Frame, score and hash one candidate exactly as curate_scenes does,
    plus the extras this pass keeps: the library's nearest poster, the
    frames the vetting models will look at, and a review poster."""
    import curate_scenes as cs
    from PIL import Image
    tab = c["tab"]
    bucket = c["bucket"]
    size = cs.VERT if bucket == "vertical" else cs.HORZ
    fdir = os.path.join(tab_dir(tab), "frames")
    pdir = os.path.join(tab_dir(tab), "posters")
    os.makedirs(fdir, exist_ok=True)
    os.makedirs(pdir, exist_ok=True)
    key = re.sub(r"[^A-Za-z0-9_.-]", "", c["key"])[:90]
    c["file_key"] = key
    try:
        if c["kind"] == "image":
            img = fetch_image(c)
            if img is None:
                c["drop"] = "fetch"
                return c
            c["fetched"] = list(img.size)
            # Pixabay lists a 1280-px edition; a 1920-px one often exists too.
            if c.get("media_alt") and head_ok(c["media_alt"], IMG_HDRS):
                c["media"] = c["media_alt"]
            if min(img.size) < 500:
                c["drop"] = "tiny"
                return c
            framed = cs.cover(img, size)
            frames = [framed]
            score, detail = cs.measure(framed, bucket)
            c["dur"] = 0
        else:
            hdrs = "Referer: https://pixabay.com/\r\n" if c["source"] == "pixabay" else ""
            small, media = resolve_video(c)
            c["score_url"], c["media"] = small, media
            if not small:
                c["drop"] = "fetch"
                return c
            info = ffprobe_url(small, hdrs)
            minfo = ffprobe_url(media, hdrs) if media and media != small else info
            if not info or info["dur"] <= 0:
                c["drop"] = "fetch"
                return c
            c["dur"] = round(info["dur"], 1)
            if minfo:
                c["media_info"] = minfo
            if c["dur"] < 6.0:
                c["drop"] = "short"
                return c
            # Three frames inside the first 2.4 s: the window curate_scenes
            # scores a clip on, so the number means the same thing. Two more
            # further in -- the reel uses the first 12 s, and a walker who
            # enters at second eight is still in the reel.
            span = min(c["dur"], 2.4)
            ts = [max(0.2, span * (i + 1) / 4) for i in range(3)]
            ts += [min(6.0, c["dur"] - 0.6), min(11.0, c["dur"] - 0.6)]
            slots = []
            for i, t in enumerate(ts):
                p = os.path.join(fdir, f"{key}_raw{i}.jpg")
                got = None
                if frame_at(small, t, p, hdrs=hdrs):
                    try:
                        got = cs.cover(Image.open(p).convert("RGB"), size)
                    except Exception:
                        got = None
                    try:
                        os.remove(p)
                    except OSError:
                        pass
                slots.append(got)
            # The first three are the scored window and must all be there;
            # a later one that failed to decode is simply not looked at.
            if any(s is None for s in slots[:3]):
                c["drop"] = "frames"
                return c
            frames = [s for s in slots if s is not None]
            scored = [cs.measure(f, bucket) for f in frames[:3]]
            score = sum(s for s, _ in scored) / len(scored)
            detail = scored[1][1]
            hs = [cs.dhash(f) for f in frames[:3]]
            c["cut"] = max(cs.hamming(hs[0], x) for x in hs[1:]) > 26
            if c["cut"]:
                score -= 12
            # Later frames must hold up too: a clip that brightens past the
            # floor after two seconds is not a portrait background.
            c["late_scores"] = [round(cs.measure(f, bucket)[0], 1) for f in frames[3:]]
        c["score"] = round(float(score), 1)
        c["detail"] = detail
        poster = frames[1] if c["kind"] == "video" else frames[0]
        c["dhash"] = str(cs.dhash(poster))
        c["dhashes"] = [str(cs.dhash(f)) for f in frames]
        c["grad"] = cs.gradient_argb(poster)
        c["face"] = any(cs.has_face(f) for f in frames)
        if cs.denied({"id": c["key"]}, frames):
            c["drop"] = "denylist"
            return c
        d, sid = lib_nearest(int(c["dhash"]))
        c["lib_ham"], c["lib_near"] = d, sid
        if c["kind"] == "video":
            c["lib_ham"] = min([d] + [lib_nearest(int(h))[0] for h in c["dhashes"]])
        if c["score"] < cs.FLOOR[bucket]:
            c["drop"] = "floor"
            return c
        if c["face"]:
            c["drop"] = "face"
            return c
        # Kept for the vetting models and the review page.
        fw, fh = (540, 960) if bucket == "vertical" else (960, 540)
        c["frames"] = []
        for i, f in enumerate(frames):
            p = os.path.join(fdir, f"{key}_{i}.jpg")
            f.resize((fw, fh), Image.LANCZOS).save(p, quality=88)
            c["frames"].append(os.path.relpath(p, tab_dir(tab)))
        pw, ph = (144, 256) if bucket == "vertical" else (256, 144)
        poster.resize((pw, ph), Image.LANCZOS).save(
            os.path.join(pdir, f"{key}.jpg"), quality=82)
        return c
    except Exception as e:
        c["drop"] = "error"
        c["error"] = str(e)[:160]
        return c


def score(tab):
    t0 = time.time()
    allc, chosen, drops = merge_discoveries(tab)
    library()  # load once before the threads start
    log(f"scoring {len(chosen)} candidates for {tab}")
    done = []
    tally = {}
    with futures.ThreadPoolExecutor(max_workers=10) as ex:
        for n, c in enumerate(ex.map(score_one, chosen), 1):
            done.append(c)
            k = c.get("drop") or "kept"
            tally[k] = tally.get(k, 0) + 1
            if n % 200 == 0:
                log(f"  {n}/{len(chosen)} {tally}  {time.time() - t0:.0f}s")
    log(f"score {tab}: {tally} in {time.time() - t0:.0f}s")
    errs = {}
    for c in done:
        if c.get("drop") == "error":
            errs[c.get("error")] = errs.get(c.get("error"), 0) + 1
    for e, n in sorted(errs.items(), key=lambda kv: -kv[1])[:6]:
        log(f"  error x{n}: {e}")
    rest = [c for c in allc if c.get("drop")]
    with open(os.path.join(tab_dir(tab), "scored.json"), "w", encoding="utf-8") as f:
        json.dump({"tab": tab, "scored": done, "dropped_before_fetch": rest,
                   "drops": drops, "tally": tally}, f)


# ── vetting models ──────────────────────────────────────────────────────

CLIP_ARCH = os.environ.get("SCENES_CLIP", "ViT-L-14")
CLIP_WEIGHTS = os.environ.get("SCENES_CLIP_WEIGHTS", "openai")
YOLO_WEIGHTS = os.environ.get("SCENES_YOLO", "yolo11m.pt")


def load_clip():
    import open_clip
    import torch
    torch.set_num_threads(os.cpu_count() or 4)
    model, _, preprocess = open_clip.create_model_and_transforms(
        CLIP_ARCH, pretrained=CLIP_WEIGHTS)
    model.eval()
    tok = open_clip.get_tokenizer(CLIP_ARCH)
    return model, preprocess, tok


def squares(img):
    """Two overlapping squares that between them cover the whole frame:
    CLIP looks at a square, and a portrait frame's top and bottom are
    where a cross or a person would otherwise fall out of view."""
    w, h = img.size
    s = min(w, h)
    if h >= w:
        return [img.crop((0, 0, s, s)), img.crop((0, h - s, s, h))]
    return [img.crop((0, 0, s, s)), img.crop((w - s, 0, w, s))]


def clip_embed(model, preprocess, images, batch=16):
    import numpy as np
    import torch
    out = []
    with torch.no_grad():
        for i in range(0, len(images), batch):
            x = torch.stack([preprocess(im) for im in images[i:i + batch]])
            f = model.encode_image(x)
            f = f / f.norm(dim=-1, keepdim=True)
            out.append(f.cpu().numpy().astype(np.float16))
    return np.concatenate(out) if out else np.zeros((0, 768), np.float16)


def vet(tab):
    """Person/animal/vehicle detections on every kept frame, and CLIP
    embeddings of the poster frame, for each candidate over the floor."""
    import numpy as np
    from PIL import Image
    t0 = time.time()
    d = json.load(open(os.path.join(tab_dir(tab), "scored.json"), encoding="utf-8"))
    todo = [c for c in d["scored"] if not c.get("drop") and c.get("frames")]
    log(f"vetting {len(todo)} {tab} candidates")
    if not todo:
        np.save(os.path.join(tab_dir(tab), "emb.npy"), np.zeros((0, 2, 768), np.float16))
        with open(os.path.join(tab_dir(tab), "emb_keys.json"), "w") as f:
            json.dump([], f)
        return

    from ultralytics import YOLO
    yolo = YOLO(YOLO_WEIGHTS)
    # A clip's three scored frames sit inside 2.4 s and look alike; the
    # middle one stands for them, beside the two from later in the clip.
    def looked_at(c):
        fr = c["frames"]
        return fr if c["kind"] == "image" or len(fr) <= 3 else [fr[1]] + fr[3:]
    paths = [(c, os.path.join(tab_dir(tab), p)) for c in todo for p in looked_at(c)]
    for c in todo:
        c["det"] = []
    B = 16
    for i in range(0, len(paths), B):
        chunk = paths[i:i + B]
        try:
            res = yolo.predict([p for _, p in chunk], imgsz=960, conf=0.2, verbose=False)
        except Exception as e:
            log(f"  yolo batch failed: {e}")
            continue
        for (c, _), r in zip(chunk, res):
            names = r.names
            for b in r.boxes:
                x, y, w, h = [float(v) for v in b.xywhn[0]]
                c["det"].append([names[int(b.cls[0])], round(float(b.conf[0]), 3),
                                 round(w * h, 5)])
        if (i // B) % 25 == 0:
            log(f"  yolo {i + len(chunk)}/{len(paths)} frames  {time.time() - t0:.0f}s")

    # A person the detector is sure of rules a candidate out whatever CLIP
    # would say, so CLIP's time goes to the rest.
    sure = 0
    for c in todo:
        if any(n == "person" and conf >= 0.5 for n, conf, _ in c["det"]):
            c["drop"] = "person"
            sure += 1
    rest = [c for c in todo if not c.get("drop")]
    log(f"  {sure} with a person for certain; CLIP on {len(rest)}  {time.time() - t0:.0f}s")

    model, preprocess, _ = load_clip()
    owners, chunks = [], []
    for i in range(0, len(rest), 24):
        imgs = []
        for c in rest[i:i + 24]:
            p = c["frames"][1] if c["kind"] == "video" else c["frames"][0]
            im = Image.open(os.path.join(tab_dir(tab), p)).convert("RGB")
            imgs += squares(im)
            owners.append(c["key"])
        chunks.append(clip_embed(model, preprocess, imgs))
        if (i // 24) % 10 == 0:
            log(f"  clip {len(owners)}/{len(rest)}  {time.time() - t0:.0f}s")
    emb = (np.concatenate(chunks) if chunks else np.zeros((0, 768), np.float16))
    emb = emb.reshape(len(owners), 2, -1)
    np.save(os.path.join(tab_dir(tab), "emb.npy"), emb)
    with open(os.path.join(tab_dir(tab), "emb_keys.json"), "w") as f:
        json.dump(owners, f)
    with open(os.path.join(tab_dir(tab), "scored.json"), "w", encoding="utf-8") as f:
        json.dump(d, f)
    # The frames were only for the models; the posters stay.
    for c in todo:
        for p in c["frames"]:
            try:
                os.remove(os.path.join(tab_dir(tab), p))
            except OSError:
                pass
    log(f"vet {tab}: done in {time.time() - t0:.0f}s, emb {emb.shape}")


# ── the pool ────────────────────────────────────────────────────────────

# Written prompts the selection step scores every candidate against.
# Grouped: one group per tab saying what belongs there, and one per thing
# that must not be in a background that carries scripture.
PROMPTS = {
    "tab:sky": ["a night sky full of stars", "the milky way over a landscape",
                "a full moon in the night sky", "a crescent moon in a dark sky",
                "dramatic clouds at dusk", "dark storm clouds", "lightning in a dark sky",
                "a twilight sky over the horizon", "the northern lights in the sky",
                "an aurora over mountains", "clouds seen from above", "star trails"],
    "tab:mountains": ["a mountain range at dusk", "misty mountains", "a snowy mountain peak",
                      "mountains at night under the stars", "a dark mountain silhouette",
                      "a foggy valley between mountains", "a rocky canyon", "a cliff face",
                      "a glacier", "a frozen winter landscape", "a volcano"],
    "tab:desert": ["sand dunes", "a desert at night", "a desert under the stars",
                   "desert dunes at sunset", "a lonely desert landscape",
                   "an oasis with palm trees", "sand ripples in the desert"],
    "tab:water": ["the ocean at night", "dark ocean waves", "a calm sea at dusk",
                  "moonlight reflecting on the sea", "a stormy sea",
                  "a still lake reflecting the sky", "a misty lake", "a waterfall",
                  "a river in a forest", "rain drops on a window", "rain falling on water",
                  "ripples on dark water"],
    "tab:forest": ["a misty forest", "a dark pine forest", "a foggy woodland",
                   "sunbeams through trees", "a forest path", "a lone tree in a field",
                   "a wheat field at dusk", "a grassy meadow in fog", "rolling green hills",
                   "palm trees in a grove"],
    "tab:road": ["an empty road at night", "a lonely highway", "a road through the desert",
                 "a winding mountain road", "a foggy road", "a road through a forest",
                 "street lights along an empty road", "light trails on a road at night",
                 "a country road at dusk", "a railway track"],
    "tab:sacred": ["a mosque", "a mosque at night", "a minaret against the sky",
                   "the dome of a mosque", "islamic architecture", "the interior of a mosque",
                   "an ornate islamic arch", "an arabic lantern", "a ramadan lantern glowing",
                   "a crescent moon over a mosque", "islamic geometric patterns",
                   "a mosque at sunset"],
    "tab:abstract": ["a dark abstract texture", "golden bokeh lights on a dark background",
                     "smoke on a black background", "a candle flame in the dark",
                     "a glowing lantern in the dark", "dark silk fabric",
                     "ink swirling in water", "glowing embers", "light rays in darkness",
                     "a dark marble texture", "dust particles in a beam of light"],
    "tab:aerial": ["an aerial view of mountains", "a drone shot of a coastline",
                   "an aerial view of a forest", "an aerial view of desert dunes",
                   "an aerial view of a river", "an aerial view of a waterfall",
                   "an aerial view of farmland", "an aerial view of a lake",
                   "an aerial view of ocean waves", "an aerial view of rice terraces",
                   "a top-down view of a landscape"],
    "tab:cinematic": ["a beautiful landscape", "a mountain lake at sunrise", "a misty valley",
                      "a waterfall in nature", "sunlight through a forest",
                      "a seascape at sunset", "rolling hills at golden hour",
                      "a cloudy sky", "a starry sky over a landscape", "a snowy landscape",
                      "autumn trees", "a meadow with wildflowers"],
    "bad:people": ["a person", "people", "a man", "a woman", "a child", "a crowd of people",
                   "a silhouette of a person", "a hiker", "human hands", "a human face",
                   "a couple", "a person praying"],
    "bad:religion": ["a church", "a cathedral", "a christian cross", "a crucifix",
                     "a buddhist temple", "a hindu temple", "a pagoda", "a buddha statue",
                     "a statue", "a sculpture", "a religious idol", "a christmas tree",
                     "a torii gate", "a synagogue", "a gravestone", "a tomb",
                     "a christian icon painting", "a mosaic of a saint", "a church interior",
                     "an altar with candles", "buddhist prayer flags"],
    "bad:vice": ["a glass of wine", "a bottle of beer", "alcoholic drinks", "a cocktail",
                 "a bar counter", "cigarettes", "a nightclub", "a casino", "fireworks"],
    "bad:music": ["a guitar", "a piano", "a violin", "a drum kit", "a musical instrument",
                  "a concert stage", "a microphone", "headphones"],
    "bad:nudity": ["nudity", "a woman in a bikini", "lingerie", "a shirtless man"],
    "bad:text": ["a page of text", "a watermark", "a logo", "a sign with writing",
                 "a poster with words", "a screenshot", "a quote written on an image",
                 "arabic calligraphy", "a book", "text overlay", "a road sign with text"],
    "bad:art": ["a digital painting", "an illustration", "a 3d render", "fantasy art",
                "an AI-generated image", "a cartoon", "a drawing", "a video game scene",
                "concept art", "clip art", "a fractal", "a computer generated landscape",
                "a neon graphic"],
    "bad:offtopic": ["a city skyline", "a busy street", "an indoor room", "an office",
                     "food on a plate", "a car", "a computer", "a phone", "an animal",
                     "a dog", "a cat", "a horse", "a bird close-up", "an insect",
                     "a flower close-up", "an amusement park", "a stadium", "a national flag",
                     "a weapon", "graffiti", "a shop", "a construction site", "a camel",
                     "a satellite image", "a scan of a photograph", "a toy", "a clock",
                     "a skull", "garbage", "a mask"],
}


def pool():
    """Every tab's vetted candidates in one place, with what selection needs:
    embeddings, posters, the library's own embeddings and hashes, and the
    prompts' embeddings."""
    import numpy as np
    import shutil
    from PIL import Image
    import curate_scenes as cs
    shards = os.environ.get("SCENES_SHARDS", os.path.join(OUT, "shards"))
    dest = os.path.join(OUT, "pool")
    os.makedirs(os.path.join(dest, "posters"), exist_ok=True)
    cands, embs, stats, seen = [], [], {}, set()
    # Every shard under the folder, however the artifacts unpacked and
    # however many runs they came from (a supplementary run's shards sit
    # beside the main run's).
    found = sorted(dp for dp, _, fs in os.walk(shards) if "scored.json" in fs) \
        if os.path.isdir(shards) else []
    for sd in found:
        d = json.load(open(os.path.join(sd, "scored.json"), encoding="utf-8"))
        t = d["tab"]
        st = stats.setdefault(t, {"shards": 0, "fetched": 0, "vetted": 0,
                                  "drops_before_fetch": {}, "score_tally": {}})
        st["shards"] += 1
        st["fetched"] += len(d["scored"])
        for part in ("drops_before_fetch", "score_tally"):
            for k, v in (d.get("drops" if part == "drops_before_fetch" else "tally") or {}).items():
                st[part][k] = st[part].get(k, 0) + v
        ep = os.path.join(sd, "emb.npy")
        if not os.path.exists(ep):
            log(f"  {sd}: no embeddings")
            continue
        e = np.load(ep)
        keys = json.load(open(os.path.join(sd, "emb_keys.json")))
        idx = {k: i for i, k in enumerate(keys)}
        for c in d["scored"]:
            if c.get("drop") or c["key"] not in idx or c["key"] in seen:
                continue
            seen.add(c["key"])
            c.pop("frames", None)
            c.pop("pexels_files", None)
            c["emb"] = len(embs)
            embs.append(e[idx[c["key"]]])
            src = os.path.join(sd, "posters", c["file_key"] + ".jpg")
            if os.path.exists(src):
                shutil.copyfile(src, os.path.join(dest, "posters", c["file_key"] + ".jpg"))
            cands.append(c)
            st["vetted"] += 1
        log(f"  {sd}: {t} {st}")
    np.save(os.path.join(dest, "emb.npy"), np.stack(embs).astype(np.float16)
            if embs else np.zeros((0, 2, 768), np.float16))
    with open(os.path.join(dest, "candidates.json"), "w", encoding="utf-8") as f:
        json.dump(cands, f)

    model, preprocess, tok = load_clip()
    import torch
    names, texts = [], []
    for g, ps in PROMPTS.items():
        for p in ps:
            names.append(g)
            texts.append(p)
    with torch.no_grad():
        tf = model.encode_text(tok(texts))
        tf = tf / tf.norm(dim=-1, keepdim=True)
    np.save(os.path.join(dest, "prompt_emb.npy"), tf.cpu().numpy().astype(np.float16))
    with open(os.path.join(dest, "prompts.json"), "w") as f:
        json.dump({"groups": names, "texts": texts,
                   "logit_scale": float(model.logit_scale.exp().item())}, f)

    cat = json.load(open(os.path.join(ROOT, "assets", "catalog.json"), encoding="utf-8"))
    lib, imgs = [], []
    for s in cat["scenes"]:
        p = os.path.join(ROOT, "assets", "scene_thumbs", s["id"] + ".jpg")
        if not os.path.exists(p):
            continue
        im = Image.open(p).convert("RGB")
        lib.append({"id": s["id"], "tab": s["tab"], "wide": s["wide"], "video": s["video"],
                    "dhash": str(cs.dhash(im))})
        imgs += squares(im)
    le = clip_embed(model, preprocess, imgs).reshape(len(lib), 2, -1)
    np.save(os.path.join(dest, "library_emb.npy"), le)
    with open(os.path.join(dest, "library.json"), "w") as f:
        json.dump(lib, f)
    with open(os.path.join(dest, "stats.json"), "w") as f:
        json.dump(stats, f, indent=1)
    log(f"pool: {len(cands)} candidates, library {len(lib)}, prompts {len(texts)}")


# ── probe ───────────────────────────────────────────────────────────────

def probe():
    """Which browser gets through to Pexels, page after page. Pexels lets
    a fresh browser through its first interstitial and then challenges
    every navigation again; this measures each engine on the same run of
    pages, and whether scrolling (XHR, not navigation) brings more."""
    d = os.path.join(OUT, "probe")
    os.makedirs(d, exist_ok=True)
    urls = [
        "https://www.pexels.com/search/desert%20night/?orientation=portrait&people_count=0",
        "https://www.pexels.com/search/desert%20night/?orientation=portrait&people_count=0&page=2",
        "https://www.pexels.com/search/videos/desert%20dunes/?orientation=portrait&people_count=0",
        "https://www.pexels.com/search/mosque/?orientation=portrait&people_count=0",
        "https://www.pexels.com/search/videos/drone%20mountains/?orientation=landscape&people_count=0",
        "https://www.pexels.com/search/milky%20way/?orientation=portrait&people_count=0",
    ]
    ready = r'id="__NEXT_DATA__"'
    plan = os.environ.get("SCENES_PROBE",
                          "playwright:0,playwright:1,patchright:1,camoufox:0,camoufox:1")
    results = {}
    for spec in plan.split(","):
        engine, headed = spec.split(":")
        name = f"{engine}-{'headed' if headed == '1' else 'headless'}"
        try:
            br = Browser(engine, headed == "1")
        except Exception as e:
            log(f"{name}: could not start: {str(e)[:300]}")
            results[name] = None
            continue
        ok, t0 = 0, time.time()
        for i, u in enumerate(urls):
            t1 = time.time()
            html = br.get(u, ready, tries=2)
            got = bool(re.search(ready, html or ""))
            ok += got
            extra = ""
            if got and i in (0, 2):
                br.captured = []
                br.scroll(3)
                api = [x for x in br.captured if "/api/v3/" in x[0]]
                n = 0
                for j, (au, body) in enumerate(api):
                    try:
                        n += len(json.loads(body).get("data") or [])
                    except Exception:
                        pass
                    if j == 0:
                        with open(os.path.join(d, f"{name}_api{i}.json"), "w",
                                  encoding="utf-8") as f:
                            f.write(au + "\n" + body[:400000])
                extra = f"  scroll: {len(api)} api responses, {n} items"
            if got and i == 2:
                with open(os.path.join(d, f"{name}_videos.html"), "w", encoding="utf-8") as f:
                    f.write(html)
            log(f"  {name:20} {'OK' if got else '--'} {time.time() - t1:5.1f}s "
                f"{u[22:100]}{extra}")
        log(f"{name}: {ok}/{len(urls)} pages in {time.time() - t0:.0f}s")
        results[name] = ok
        br.close()
    with open(os.path.join(d, "results.json"), "w") as f:
        json.dump(results, f, indent=1)


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "probe"
    if cmd == "discover":
        discover(sys.argv[2], sys.argv[3])
    elif cmd == "score":
        score(sys.argv[2])
    elif cmd == "vet":
        vet(sys.argv[2])
    elif cmd == "pool":
        pool()
    elif cmd == "probe":
        probe()
    else:
        raise SystemExit(__doc__)
