"""Builds guess mode's identity packs (data/identities/<pack>.json) from Wikidata.

Wikidata's data is CC0, so the packs can be committed and shipped. The game never queries
Wikidata itself; run this again to refresh a pack:

    python tools/build_identities.py                # every pack
    python tools/build_identities.py musicians      # one pack

Big SPARQL queries time out, so every pack first lists its item ids (one cheap query
per occupation or type), then reads each property in batches of BATCH items. Raw answers
are cached in .identity_cache/ (git-ignored) so a rerun after a failure is quick; pass
--fresh to ignore the cache. The format is documented in src/core/guess/identity_pack.gd.
"""

from __future__ import annotations

import collections
import hashlib
import json
import math
import pathlib
import re
import ssl
import sys
import time
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "data" / "identities"
CACHE_DIR = ROOT / ".identity_cache"
ENDPOINT = "https://query.wikidata.org/sparql"
USER_AGENT = "KillingForTheMemes-PackBuilder/0.1 (private party game; offline data build)"
BATCH = 150
PAUSE = 0.4  # seconds between requests, to be polite to the public endpoint

try:
    import certifi

    _SSL = ssl.create_default_context(cafile=certifi.where())
except ImportError:  # the system store is fine where it is up to date
    _SSL = ssl.create_default_context()

FRESH = "--fresh" in sys.argv


# --- SPARQL -------------------------------------------------------------------------------

def sparql(query: str) -> list[dict]:
    key = hashlib.sha1(query.encode()).hexdigest()
    cached = CACHE_DIR / f"{key}.json"
    if cached.exists() and not FRESH:
        return json.loads(cached.read_text(encoding="utf-8"))
    body = urllib.parse.urlencode({"query": query, "format": "json"}).encode()
    for attempt in range(4):
        request = urllib.request.Request(ENDPOINT, data=body, headers={
            "User-Agent": USER_AGENT, "Accept": "application/sparql-results+json"})
        try:
            with urllib.request.urlopen(request, timeout=120, context=_SSL) as answer:
                rows = json.load(answer)["results"]["bindings"]
            break
        except Exception as error:  # timeouts and 429/5xx: wait and retry
            print(f"  retry {attempt + 1}: {error}")
            time.sleep(5 * (attempt + 1))
    else:
        raise RuntimeError("Wikidata did not answer")
    CACHE_DIR.mkdir(exist_ok=True)
    (CACHE_DIR / ".gdignore").touch()  # keep Godot from importing thousands of JSON files
    cached.write_text(json.dumps(rows), encoding="utf-8")
    time.sleep(PAUSE)
    return rows


def qid(uri: str) -> str:
    return uri.rsplit("/", 1)[-1]


def items_with(pattern: str, min_sitelinks: int) -> dict[str, int]:
    """Item id -> fame for everything matching a triple pattern on ?item.

    Fame is the geometric mean of Wikipedia sitelinks and external database ids (IMDb,
    MusicBrainz, ...): sitelinks alone overrate items padded with small-wiki stubs."""
    rows = sparql(f"""SELECT ?item ?links ?ids WHERE {{
        {pattern}
        ?item wikibase:sitelinks ?links. FILTER(?links >= {min_sitelinks})
        ?item wikibase:identifiers ?ids.
    }}""")
    return {qid(r["item"]["value"]): round(math.sqrt(int(r["links"]["value"]) * int(r["ids"]["value"])))
            for r in rows}


def batches(ids: list[str]):
    for start in range(0, len(ids), BATCH):
        yield " ".join(f"wd:{i}" for i in ids[start:start + BATCH])


# Wikidata keeps many names only as the language-neutral "mul" label (no "en" copy), so
# every label lookup takes English first, then "mul".
_LABEL = """?{var} rdfs:label ?label. FILTER(LANG(?label) IN ("en", "mul")) BIND(LANG(?label) AS ?lang)"""


def _pick_labels(rows: list[dict], key: str) -> dict[str, str]:
    """Key value -> label, English winning over "mul"."""
    chosen: dict[str, tuple[str, str]] = {}
    for r in rows:
        name, lang = r[key]["value"], r["lang"]["value"]
        if name not in chosen or (lang == "en" and chosen[name][1] != "en"):
            chosen[name] = (r["label"]["value"], lang)
    return {name: label for name, (label, _) in chosen.items()}


def labels(ids: list[str]) -> dict[str, str]:
    result: dict[str, str] = {}
    for chunk in batches(ids):
        rows = sparql(f"SELECT ?item ?label ?lang WHERE {{ VALUES ?item {{ {chunk} }} {_LABEL.format(var='item')} }}")
        for uri, label in _pick_labels(rows, "item").items():
            result[qid(uri)] = label
    return result


def values(ids: list[str], prop: str, with_label: bool = True) -> dict[str, list[str]]:
    """Item id -> its values of a property (English labels, or raw values)."""
    result: dict[str, list[str]] = collections.defaultdict(list)
    for chunk in batches(ids):
        if with_label:
            rows = sparql(f"""SELECT ?item ?value ?label ?lang WHERE {{ VALUES ?item {{ {chunk} }}
                ?item wdt:{prop} ?value. {_LABEL.format(var='value')} }}""")
            names = _pick_labels(rows, "value")
            pairs = [(r["item"]["value"], names[r["value"]["value"]]) for r in rows]
        else:
            rows = sparql(f"SELECT ?item ?value WHERE {{ VALUES ?item {{ {chunk} }} ?item wdt:{prop} ?value. }}")
            pairs = [(r["item"]["value"], r["value"]["value"]) for r in rows]
        for uri, value in pairs:
            if value not in result[qid(uri)]:
                result[qid(uri)].append(value)
    return result


def descriptions(ids: list[str]) -> dict[str, str]:
    """Item id -> its one-line English description ("American singer and actress")."""
    result: dict[str, str] = {}
    for chunk in batches(ids):
        for r in sparql(f"""SELECT ?item ?d WHERE {{ VALUES ?item {{ {chunk} }}
                ?item schema:description ?d. FILTER(LANG(?d) = "en") }}"""):
            result[qid(r["item"]["value"])] = r["d"]["value"]
    return result


def has(ids: list[str], pattern: str) -> set[str]:
    """Items for which a pattern on ?item holds."""
    found: set[str] = set()
    for chunk in batches(ids):
        for r in sparql(f"SELECT DISTINCT ?item WHERE {{ VALUES ?item {{ {chunk} }} {pattern} }}"):
            found.add(qid(r["item"]["value"]))
    return found


def first_year(dates: list[str]) -> int | None:
    years = []
    for date in dates:
        text = date.split("T", 1)[0]
        sign = -1 if text.startswith("-") else 1
        try:
            years.append(sign * int(text.lstrip("-+").split("-", 1)[0]))
        except ValueError:
            pass
    return min(years) if years else None


def most_common(per_item: dict[str, list[str]]) -> dict[str, str]:
    """Picks one value per item: the one most common across the pack. For citizenship this
    prefers "United Kingdom" over "Kingdom of England" and the like."""
    counts = collections.Counter(v for vs in per_item.values() for v in vs)
    return {item: max(vs, key=lambda v: counts[v]) for item, vs in per_item.items() if vs}


def broad(raw: list[str], groups: dict[str, list[str]]) -> list[str]:
    """Maps Wikidata's fine genres ("contemporary R&B") onto a few broad ones."""
    found = []
    for name, keys in groups.items():
        if any(key in genre.lower() for genre in raw for key in keys):
            found.append(name)
    return found


# --- Packs --------------------------------------------------------------------------------

MUSIC_GENRES = {
    "rock": ["rock"], "pop": ["pop"], "hip hop": ["hip hop", "rap", "trap"],
    "R&B / soul": ["r&b", "rhythm and blues", "soul", "funk"],
    "electronic": ["electronic", "house", "techno", "edm", "dance", "trance", "dubstep"],
    "metal": ["metal"], "punk": ["punk"], "country": ["country"], "jazz": ["jazz"],
    "blues": ["blues"], "folk": ["folk"], "reggae": ["reggae", "ska", "dancehall"],
    "classical": ["classical", "opera"], "latin": ["latin", "reggaeton", "salsa", "bachata"],
    "K-pop": ["k-pop"],
}
# Singer, musician, rapper, composer, singer-songwriter, guitarist, DJ.
MUSIC_OCCUPATIONS = ["Q177220", "Q639669", "Q2252262", "Q36834", "Q488205", "Q855091", "Q130857"]
# Famous mostly for something else (Wikidata lists "composer" for Nietzsche, "singer" for
# Pelé): philosopher, theologian, painter, politician, footballer, physicist, mathematician.
# A musician's English description says so: "Austrian composer", "American rapper".
# Actors who once released a record ("American actress") don't belong in this pack.
MUSIC_WORDS = ["singer", "musician", "rapper", "composer", "songwriter", "band", "dj", "guitarist",
               "pianist", "drummer", "bassist", "violinist", "cellist", "organist", "conductor",
               "vocalist", "music", "record producer", "idol", "tenor", "soprano", "baritone"]
def sounds_musical(description: str) -> bool:
    text = description.lower()
    words = set(re.findall(r"[a-z]+", text))
    return any((word in text) if " " in word else (word in words) for word in MUSIC_WORDS)


NOT_MUSICIANS ="wd:Q4964182 wd:Q1234713 wd:Q1028181 wd:Q82955 wd:Q937857 wd:Q169470 wd:Q170790"


# Bands have far fewer authority-database ids than people on Wikidata, so by fame alone
# only 14 bands made the 300 best known (the deal pool). This brings them to about a
# quarter, roughly what people expect ("Am I a band?" is a fair first question).
BAND_FAME_BOOST = 1.5


def build_musicians() -> dict:
    people: dict[str, int] = {}
    for occupation in MUSIC_OCCUPATIONS:
        people.update(items_with(f"?item wdt:P106 wd:{occupation}; wdt:P31 wd:Q5.", 55))
    bands = items_with("?item wdt:P31/wdt:P279* wd:Q215380.", 35)
    for band in bands:
        people.pop(band, None)
    # A musician has a record label, an instrument or a voice type on Wikidata.
    music = has(sorted(people), "{ ?item wdt:P264 ?x. } UNION { ?item wdt:P1303 ?x. } UNION { ?item wdt:P412 ?x. }")
    other = has(sorted(people), f"VALUES ?occ {{ {NOT_MUSICIANS} }} ?item wdt:P106 ?occ.")
    said = descriptions(sorted(people))
    people = {i: fame for i, fame in people.items()
              if i in music and i not in other and sounds_musical(said.get(i, ""))}
    ids = sorted(set(people) | set(bands))
    print(f"musicians: {len(people)} people, {len(bands)} bands")
    names = labels(ids)
    person_ids = [i for i in ids if i in people]
    band_ids = [i for i in ids if i in bands]
    gender = values(person_ids, "P21")
    born = values(person_ids, "P569", with_label=False)
    formed = values(band_ids, "P571", with_label=False)
    dead = has(person_ids, "?item wdt:P570 ?d.")
    split = has(band_ids, "?item wdt:P576 ?d.")
    country = most_common({**values(person_ids, "P27"), **values(band_ids, "P495")})
    genres = values(ids, "P136")
    images = values(ids, "P18", with_label=False)

    entries = []
    for item in ids:
        if item not in names or names[item] == item:
            continue
        is_band = item in bands
        fields: dict = {"kind": "band" if is_band else "solo artist"}
        if not is_band and gender.get(item):
            fields["gender"] = {"male": "man", "female": "woman"}.get(gender[item][0], "non-binary")
        year = first_year((formed if is_band else born).get(item, []))
        if year is not None:
            fields["born"] = year
        fields["alive"] = item not in (split if is_band else dead)
        if item in country:
            fields["country"] = country[item]
        tags = broad(genres.get(item, []), MUSIC_GENRES)
        if tags:
            fields["genres"] = tags
        fame = round(bands[item] * BAND_FAME_BOOST) if is_band else people[item]
        entries.append(_entry(item, names[item], fame, fields, images.get(item)))
    return {
        "id": "musicians", "name": "Musicians",
        "fields": [
            {"id": "kind", "name": "Kind", "type": "enum"},
            {"id": "gender", "name": "Gender", "type": "enum"},
            {"id": "born", "name": "Born / formed", "type": "year"},
            {"id": "alive", "name": "Alive / still active", "type": "bool"},
            {"id": "country", "name": "Country", "type": "enum"},
            {"id": "genres", "name": "Genres", "type": "tags"},
        ],
        "questions": [
            _q("Am I a band?", "kind", "is", "band"),
            _q("Am I a woman?", "gender", "is", "woman"),
            _q("Am I a man?", "gender", "is", "man"),
            _q("Was I born (or formed) before 1970?", "born", "before", 1970),
            _q("Was I born (or formed) before 1990?", "born", "before", 1990),
            _q("Was I born (or formed) in 2000 or later?", "born", "from", 2000),
            _q("Am I still alive (or still together)?", "alive", "is", True),
            _q("Am I from the United States?", "country", "is", "United States"),
            _q("Am I from the United Kingdom?", "country", "is", "United Kingdom"),
            *[_q(f"Do I make {genre}?", "genres", "has", genre) for genre in
              ["rock", "pop", "hip hop", "R&B / soul", "electronic", "metal", "country", "jazz", "latin", "K-pop"]],
        ],
        "entries": entries,
    }


FILM_GENRES = {
    "action": ["action", "martial arts", "superhero"], "adventure": ["adventure"],
    "comedy": ["comedy", "parody", "satir"], "drama": ["drama"], "horror": ["horror", "slasher", "zombie"],
    "thriller": ["thriller", "suspense"], "crime": ["crime", "gangster", "heist", "noir"],
    "science fiction": ["science fiction", "cyberpunk", "space opera"], "fantasy": ["fantasy"],
    "romance": ["romance", "romantic"], "war": ["war"], "western": ["western"],
    "musical": ["musical"], "family": ["family", "children"], "documentary": ["documentary"],
    "animation": ["anima"], "mystery": ["mystery", "detective"],
}
# Film, animated feature film, animated film.
FILM_TYPES = ["Q11424", "Q29168811", "Q202866"]


def build_movies() -> dict:
    films: dict[str, int] = {}
    for film_type in FILM_TYPES:
        films.update(items_with(f"?item wdt:P31 wd:{film_type}.", 38))
    ids = sorted(films)
    print(f"movies: {len(ids)} films")
    names = labels(ids)
    released = values(ids, "P577", with_label=False)
    country = most_common(values(ids, "P495"))
    genres = values(ids, "P136")
    directors = values(ids, "P57")
    animated = has(ids, "VALUES ?t { wd:Q29168811 wd:Q202866 } ?item wdt:P31 ?t.")
    franchise = has(ids, "{ ?item wdt:P179 ?s. } UNION { ?item wdt:P8345 ?s. } UNION { ?item wdt:P155 ?s. } UNION { ?item wdt:P156 ?s. }")
    oscar = has(ids, "?item wdt:P166 ?award. ?award wdt:P31 wd:Q19020.")

    entries = []
    for item in ids:
        if item not in names or names[item] == item:
            continue
        tags = broad(genres.get(item, []), FILM_GENRES)
        if item in animated and "animation" not in tags:
            tags.append("animation")
        fields: dict = {"animated": "animation" in tags, "franchise": item in franchise, "oscar": item in oscar}
        year = first_year(released.get(item, []))
        if year is not None:
            fields["released"] = year
        if item in country:
            fields["country"] = country[item]
        if tags:
            fields["genres"] = tags
        if directors.get(item):
            fields["director"] = directors[item][0]
        entries.append(_entry(item, names[item], films[item], fields, None))
    return {
        "id": "movies", "name": "Movies",
        "fields": [
            {"id": "released", "name": "Released", "type": "year"},
            {"id": "genres", "name": "Genres", "type": "tags"},
            {"id": "animated", "name": "Animated", "type": "bool"},
            {"id": "franchise", "name": "Part of a series", "type": "bool"},
            {"id": "oscar", "name": "Won an Oscar", "type": "bool"},
            {"id": "country", "name": "Country", "type": "enum"},
            {"id": "director", "name": "Director", "type": "enum"},
        ],
        "questions": [
            _q("Am I animated?", "animated", "is", True),
            _q("Was I released before 1980?", "released", "before", 1980),
            _q("Was I released before 2000?", "released", "before", 2000),
            _q("Was I released in 2010 or later?", "released", "from", 2010),
            _q("Am I part of a series or sequel?", "franchise", "is", True),
            _q("Did I win an Oscar?", "oscar", "is", True),
            _q("Am I from the United States?", "country", "is", "United States"),
            *[_q(f"Am I {'an' if genre[0] in 'aeiou' else 'a'} {genre} movie?", "genres", "has", genre) for genre in
              ["comedy", "horror", "action", "science fiction", "fantasy", "romance", "drama", "crime", "war"]],
        ],
        "entries": entries,
    }


def _person_basics(ids: list[str]) -> tuple[dict, dict, set, dict, dict]:
    """Gender, birth dates, the dead, citizenship and pictures for a list of people."""
    return (values(ids, "P21"), values(ids, "P569", with_label=False), has(ids, "?item wdt:P570 ?d."),
            most_common(values(ids, "P27")), values(ids, "P18", with_label=False))


def _gender(raw: list[str]) -> str | None:
    if not raw:
        return None
    return {"male": "man", "female": "woman"}.get(raw[0], "non-binary")


def _described_as(said: dict[str, str], words: list[str]):
    """A check on English descriptions: True if any of the words appears."""
    def check(item: str) -> bool:
        text = said.get(item, "").lower()
        found = set(re.findall(r"[a-z]+", text))
        return any((w in text) if " " in w else (w in found) for w in words)
    return check


# Actor, film actor, television actor, voice actor, stage actor.
ACTOR_OCCUPATIONS = ["Q33999", "Q10800557", "Q10798782", "Q2405480", "Q2259451"]
# What else an actor does, by occupation: singer, film director, comedian, film producer,
# screenwriter or writer, model.
ACTOR_SIDELINES = {"singer": ["Q177220", "Q488205"], "director": ["Q2526255"], "comedian": ["Q245068"],
                   "producer": ["Q3282637"], "writer": ["Q28389", "Q36180"], "model": ["Q4610556"]}


# The first role word in a description says what someone is famous for: "American actress
# and singer" is an actor, "American singer and actress" (Madonna) a musician, "American
# politician and actor" (Reagan) a politician.
ACTING_WORDS = {"actor", "actress", "comedian", "comedienne"}
OTHER_ROLE_WORDS = {"singer", "rapper", "musician", "songwriter", "politician", "president", "filmmaker",
                    "director", "producer", "writer", "playwright", "poet", "model", "dancer", "animator",
                    "businessman", "businesswoman", "entrepreneur", "presenter", "host", "wrestler",
                    "footballer", "boxer", "athlete", "youtuber", "socialite", "composer", "dj", "artist",
                    "screenwriter", "journalist", "personality", "monarch", "activist", "magician"}


def first_role_is_acting(description: str) -> bool:
    for word in re.findall(r"[a-z]+", description.lower()):
        if word in ACTING_WORDS:
            return True
        if word in OTHER_ROLE_WORDS:
            return False
    return False


def build_actors() -> dict:
    people: dict[str, int] = {}
    for occupation in ACTOR_OCCUPATIONS:
        people.update(items_with(f"?item wdt:P106 wd:{occupation}; wdt:P31 wd:Q5.", 60))
    said = descriptions(sorted(people))
    ids = sorted(i for i in people if first_role_is_acting(said.get(i, "")))
    print(f"actors: {len(ids)} people")
    names = labels(ids)
    gender, born, dead, country, images = _person_basics(ids)
    oscar = has(ids, "?item wdt:P166 ?award. ?award wdt:P31 wd:Q19020.")
    sidelines = {name: has(ids, "VALUES ?occ { %s } ?item wdt:P106 ?occ." % " ".join("wd:" + q for q in qs))
                 for name, qs in ACTOR_SIDELINES.items()}

    entries = []
    for item in ids:
        if item not in names or names[item] == item:
            continue
        fields: dict = {"alive": item not in dead, "oscar": item in oscar}
        if _gender(gender.get(item, [])):
            fields["gender"] = _gender(gender[item])
        year = first_year(born.get(item, []))
        if year is not None:
            fields["born"] = year
        if item in country:
            fields["country"] = country[item]
        also = [name for name, who in sidelines.items() if item in who]
        if also:
            fields["also"] = also
        entries.append(_entry(item, names[item], people[item], fields, images.get(item)))
    return {
        "id": "actors", "name": "Actors",
        "fields": [
            {"id": "gender", "name": "Gender", "type": "enum"},
            {"id": "born", "name": "Born", "type": "year"},
            {"id": "alive", "name": "Alive", "type": "bool"},
            {"id": "country", "name": "Country", "type": "enum"},
            {"id": "oscar", "name": "Won an Oscar", "type": "bool"},
            {"id": "also", "name": "Also a", "type": "tags"},
        ],
        "questions": [
            _q("Am I a woman?", "gender", "is", "woman"),
            _q("Am I a man?", "gender", "is", "man"),
            _q("Was I born before 1950?", "born", "before", 1950),
            _q("Was I born before 1970?", "born", "before", 1970),
            _q("Was I born in 1985 or later?", "born", "from", 1985),
            _q("Am I still alive?", "alive", "is", True),
            _q("Am I from the United States?", "country", "is", "United States"),
            _q("Am I from the United Kingdom?", "country", "is", "United Kingdom"),
            _q("Have I won an Oscar?", "oscar", "is", True),
            _q("Do I sing too?", "also", "has", "singer"),
            _q("Have I directed films?", "also", "has", "director"),
            _q("Am I a comedian?", "also", "has", "comedian"),
            _q("Have I worked as a model?", "also", "has", "model"),
        ],
        "entries": entries,
    }


# Who made history: occupations whose famous members are mostly long dead. Monarch,
# politician, military officer, philosopher, scientist, physicist, mathematician, writer,
# poet, painter, explorer, composer, inventor, chemist, astronomer, religious leader,
# sculptor, military leader, saint, pharaoh, emperor.
HISTORY_OCCUPATIONS = ["Q116", "Q82955", "Q189290", "Q4964182", "Q901", "Q169470", "Q170790", "Q36180",
                       "Q49757", "Q1028181", "Q11900058", "Q36834", "Q205375", "Q593644", "Q11063",
                       "Q15995642", "Q1281618", "Q47064", "Q43115", "Q37110", "Q39018"]
# The roles a player can ask about, from the English description ("Roman emperor").
HISTORY_ROLES = {
    "ruler": ["king", "queen", "emperor", "empress", "pharaoh", "monarch", "sultan", "tsar", "czar",
              "shah", "caliph", "khan", "prince", "princess", "duke", "ruler", "consort", "regent"],
    "politician": ["politician", "president", "prime minister", "statesman", "revolutionary",
                   "chancellor", "senator", "founding father", "dictator", "activist"],
    "military": ["general", "military", "admiral", "commander", "soldier", "conqueror", "warrior", "marshal"],
    "scientist": ["scientist", "physicist", "chemist", "mathematician", "astronomer", "biologist",
                  "naturalist", "inventor", "engineer", "physician", "polymath", "geographer"],
    "philosopher": ["philosopher", "thinker", "economist"],
    "writer": ["writer", "poet", "novelist", "playwright", "author", "dramatist", "historian"],
    "artist": ["painter", "sculptor", "artist", "architect"],
    "composer": ["composer", "musician", "pianist"],
    "religious": ["saint", "pope", "prophet", "theologian", "religious", "bishop", "apostle", "monk",
                  "preacher", "reformer", "rabbi"],
    "explorer": ["explorer", "navigator", "aviator", "traveller", "traveler"],
}


def _roles(description: str, groups: dict[str, list[str]]) -> list[str]:
    """Whole-word matches only ("general" is a role, "generally" isn't)."""
    text = description.lower()
    words = set(re.findall(r"[a-z]+", text))
    return [name for name, keys in groups.items()
            if any((k in text) if " " in k else (k in words) for k in keys)]


def build_history() -> dict:
    people: dict[str, int] = {}
    for occupation in HISTORY_OCCUPATIONS:
        people.update(items_with(f"?item wdt:P106 wd:{occupation}; wdt:P31 wd:Q5.", 110))
    ids = sorted(people)
    born = values(ids, "P569", with_label=False)
    # Historical: born before 1900, so everyone in the pack is long gone.
    ids = [i for i in ids if (first_year(born.get(i, [])) or 9999) < 1900]
    said = descriptions(ids)
    roles = {i: _roles(said.get(i, ""), HISTORY_ROLES) for i in ids}
    ids = [i for i in ids if roles[i]]
    print(f"history: {len(ids)} people")
    names = labels(ids)
    gender, born, _dead, country, images = _person_basics(ids)
    # Empires (Rome, Russia...) sit on "Eurasia" or "Afro-Eurasia"; keep real continents only.
    continent = most_common({i: [c for c in cs if "Eurasia" not in c]
                             for i, cs in values(ids, "P27/wdt:P30").items()})

    entries = []
    for item in ids:
        if item not in names or names[item] == item:
            continue
        fields: dict = {"roles": roles[item]}
        if _gender(gender.get(item, [])):
            fields["gender"] = _gender(gender[item])
        year = first_year(born.get(item, []))
        if year is not None:
            fields["born"] = year
        if item in continent:
            fields["continent"] = continent[item]
        if item in country:
            fields["country"] = country[item]
        entries.append(_entry(item, names[item], people[item], fields, images.get(item)))
    return {
        "id": "history", "name": "Historical figures",
        "fields": [
            {"id": "roles", "name": "Known as", "type": "tags"},
            {"id": "gender", "name": "Gender", "type": "enum"},
            {"id": "born", "name": "Born", "type": "year"},
            {"id": "continent", "name": "Continent", "type": "enum"},
            {"id": "country", "name": "Country", "type": "enum"},
        ],
        "questions": [
            _q("Am I a woman?", "gender", "is", "woman"),
            _q("Was I born before year 0 (BC)?", "born", "before", 0),
            _q("Was I born before 1500?", "born", "before", 1500),
            _q("Was I born before 1800?", "born", "before", 1800),
            _q("Am I from Europe?", "continent", "is", "Europe"),
            _q("Am I from Asia?", "continent", "is", "Asia"),
            _q("Am I from North America?", "continent", "is", "North America"),
            _q("Was I a ruler (king, queen, emperor...)?", "roles", "has", "ruler"),
            _q("Was I a politician or statesman?", "roles", "has", "politician"),
            _q("Was I a military leader?", "roles", "has", "military"),
            _q("Was I a scientist or inventor?", "roles", "has", "scientist"),
            _q("Was I a philosopher?", "roles", "has", "philosopher"),
            _q("Was I a writer or poet?", "roles", "has", "writer"),
            _q("Was I an artist?", "roles", "has", "artist"),
            _q("Was I a composer?", "roles", "has", "composer"),
            _q("Was I a religious figure?", "roles", "has", "religious"),
            _q("Was I an explorer?", "roles", "has", "explorer"),
        ],
        "entries": entries,
    }


# What a character is, from its "instance of" labels ("fictional hedgehog"), matched as
# whole words, in this order: a cyborg is a robot, "fictional human" beats "anthropomorphic
# fox" (Wikidata says both about some). Franchise labels ("Sonic the Hedgehog character")
# say nothing about the character itself and are skipped.
CHARACTER_KINDS = {
    "robot": ["robot", "android", "cyborg", "artificial intelligence"],
    "human": ["human", "hylian", "gerudo", "elf"],
    "animal": ["animal", "hedgehog", "fox", "cat", "dog", "bird", "dinosaur", "mouse", "rabbit",
               "bear", "monkey", "ape", "gorilla", "pig", "frog", "turtle", "duck", "echidna", "bandicoot",
               "marsupial", "dragon", "lizard", "snake", "wolf", "koopa"],
    "monster": ["monster", "creature", "demon", "alien", "extraterrestrial", "undead", "zombie",
                "ghost", "skeleton", "revenant", "slime", "orc", "vampire", "mob"],
}


def _character_kind(labels_: list[str]) -> str | None:
    words: set[str] = set()
    for label in labels_:
        text = label.lower()
        if text.endswith(" character") or text.endswith(" enemy"):
            continue
        words.update(re.findall(r"[a-zé]+", text))
        if "artificial intelligence" in text:
            words.add("artificial intelligence")
    for kind, keys in CHARACTER_KINDS.items():
        if any(k in words for k in keys):
            return kind
    return None


def build_game_characters() -> dict:
    # Characters who debuted in a video game: "video game character" alone also covers
    # Mickey Mouse and Darth Vader, who merely appear in games.
    found = items_with("?item wdt:P31/wdt:P279* wd:Q1569167; wdt:P4584 ?debut. "
                       "?debut wdt:P31/wdt:P279* wd:Q7889.", 5)
    ids = sorted(found)
    print(f"game characters: {len(ids)} characters")
    names = labels(ids)
    gender = values(ids, "P21")
    kinds_raw = values(ids, "P31")
    franchise = values(ids, "P8345")
    first_year_raw = values(ids, "P4584/wdt:P577", with_label=False)
    publisher = most_common(values(ids, "P4584/wdt:P123"))
    developer = most_common(values(ids, "P4584/wdt:P178"))
    # No "villain" field: Wikidata marks only a handful, and a missing mark would cross out
    # real villains like Dr. Eggman on a "Yes".
    images = values(ids, "P18", with_label=False)

    entries = []
    for item in ids:
        if item not in names or names[item] == item:
            continue
        fields: dict = {}
        g = _gender(gender.get(item, []))
        if g in ("man", "woman"):
            fields["gender"] = g
        kind = _character_kind(kinds_raw.get(item, []))
        if kind:
            fields["kind"] = kind
        if franchise.get(item):
            fields["series"] = franchise[item][0]
        year = first_year(first_year_raw.get(item, []))
        if year is not None:
            fields["first"] = year
        if item in publisher:
            fields["publisher"] = publisher[item]
        if item in developer:
            fields["developer"] = developer[item]
        entries.append(_entry(item, names[item], found[item], fields, images.get(item)))
    return {
        "id": "game_characters", "name": "Video game characters",
        "fields": [
            {"id": "kind", "name": "Kind", "type": "enum"},
            {"id": "gender", "name": "Gender", "type": "enum"},
            {"id": "series", "name": "Series", "type": "enum"},
            {"id": "first", "name": "First appeared", "type": "year"},
            {"id": "publisher", "name": "Publisher", "type": "enum"},
            {"id": "developer", "name": "Developer", "type": "enum"},
        ],
        "questions": [
            _q("Am I human?", "kind", "is", "human"),
            _q("Am I an animal?", "kind", "is", "animal"),
            _q("Am I a robot?", "kind", "is", "robot"),
            _q("Am I a monster or creature?", "kind", "is", "monster"),
            _q("Am I female?", "gender", "is", "woman"),
            _q("Did I first appear before 1990?", "first", "before", 1990),
            _q("Did I first appear before 2000?", "first", "before", 2000),
            _q("Did I first appear in 2010 or later?", "first", "from", 2010),
            _q("Am I from a Nintendo game?", "publisher", "is", "Nintendo"),
            _q("Am I from a Sega game?", "publisher", "is", "Sega"),
            _q("Am I from a Capcom game?", "publisher", "is", "Capcom"),
            _q("Am I from a Square Enix game?", "publisher", "is", "Square Enix"),
            _q("Am I a Mario character?", "series", "is", "Mario"),
            _q("Am I from The Legend of Zelda?", "series", "is", "The Legend of Zelda"),
        ],
        "entries": entries,
    }


def _entry(item: str, name: str, fame: int, fields: dict, images: list[str] | None) -> dict:
    entry = {"id": item, "name": name, "fame": fame, "fields": fields}
    if images:
        # P18 values are Commons file URLs; keep only the file name.
        entry["image"] = urllib.parse.unquote(images[0].rsplit("/", 1)[-1])
    return entry


def _q(text: str, field: str | None, op: str | None, value) -> dict | None:
    if field is None:
        return None
    return {"text": text, "filter": {"field": field, "op": op, "value": value}}


def finish(pack: dict) -> dict:
    """Drops stock questions no entry can answer "yes" to, sorts entries by fame."""
    pack["entries"].sort(key=lambda e: (-e["fame"], e["name"]))
    known: dict[str, set] = collections.defaultdict(set)
    for entry in pack["entries"]:
        for field, value in entry["fields"].items():
            known[field].update(value if isinstance(value, list) else [value])
    kept = []
    for question in pack["questions"]:
        if question is None:
            continue
        f = question["filter"]
        if f["op"] in ("is", "has") and f["value"] not in known[f["field"]]:
            print(f"  dropping stock question {question['text']!r}: nobody is {f['value']!r}")
            continue
        kept.append(question)
    pack["questions"] = kept
    return {"version": 1, "source": "Wikidata (CC0)", "built": time.strftime("%Y-%m-%d"), **pack}


def write(pack: dict) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUT_DIR / f"{pack['id']}.json"
    head = {k: v for k, v in pack.items() if k != "entries"}
    # One entry per line keeps diffs readable when a pack is rebuilt.
    lines = ",\n".join("\t\t" + json.dumps(e, ensure_ascii=False) for e in pack["entries"])
    text = json.dumps(head, ensure_ascii=False, indent="\t")[:-2] + ',\n\t"entries": [\n' + lines + "\n\t]\n}\n"
    json.loads(text)  # never write a broken pack
    path.write_text(text, encoding="utf-8", newline="\n")
    counts = collections.Counter(f for e in pack["entries"] for f in e["fields"])
    print(f"wrote {path.relative_to(ROOT)}: {len(pack['entries'])} entries, "
          f"{len(pack['questions'])} stock questions, field coverage {dict(counts)}")


BUILDERS = {"musicians": build_musicians, "movies": build_movies, "actors": build_actors,
            "history": build_history, "game_characters": build_game_characters}

if __name__ == "__main__":
    wanted = [a for a in sys.argv[1:] if not a.startswith("--")] or list(BUILDERS)
    for name in wanted:
        write(finish(BUILDERS[name]()))
