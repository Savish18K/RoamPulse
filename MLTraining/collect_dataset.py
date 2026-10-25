"""Downloads the landmark photos used to train RoamPulse's landmark model.

Sources are openly licensed only:
  - Wikimedia Commons (categories and title searches from landmarks.json)
  - Openverse (CC photos, mostly from Flickr)

Every downloaded photo is written to dataset_log.csv with its source page, author and
licence, so each image can be credited and checked later.

Photos used as cover images inside the app are skipped, so they can be used to try the
model on photos it has never seen.

Usage: python3 collect_dataset.py                       (every class, into Raw/<label>/)
       python3 collect_dataset.py "Gal Vihara" Other    (only the classes named)
       add --no-commons to use Openverse only (Wikimedia's image server sometimes throttles downloads)
Only the standard library is used, and requests are slowed down to respect the APIs.
"""

import csv
import hashlib
import json
import os
import random
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, "Raw")
LOG = os.path.join(HERE, "dataset_log.csv")
USER_AGENT = "RoamPulseCoursework/1.0 (NIBM BSc student project; landmark image dataset)"

# The app's own cover photos (see CREDITS.md), kept out of training
APP_PHOTOS = {
    "File:Nine Arch Bridge, Demodara Ella.jpg",
    "File:A Train Crosses The Nine Arches Bridge (243270425).jpeg",
    "File:Sigiriya Lion Rock Aerial (175658393).jpeg",
    "File:ColomboSkyline - November 2017 (1).jpg",
    "File:NallurKandaswamyKovilGopuram.jpg",
    "File:SL Kandy asv2020-01 img34 Sacred Tooth Temple.jpg",
    "File:Galle Fort lighthouse Leuchtturm (35113214702).jpg",
    "File:Dambulla Cave 1.jpg",
    "File:SL Anuradhapura asv2020-01 img11 Ruwanwelisaya Stupa.jpg",
    "File:Sri Pada(Addams Peak)View from Fishing hut2.jpg",
    "File:Beauty of Coconut Tree Hills.jpg",
    "File:NIBM COL.jpg",
    "File:Gal Viharaya 02.jpg",
    "File:Gangaramaya Temple (Burning Incense).jpg",
    "File:Cascades de Ravana.jpg",
}

# Drawings, maps and documents aren't photos of the place
SKIP_WORDS = ["map", "plan", "drawing", "logo", "stamp", "coin", "banknote", "diagram", "postcard",
              "illustration", "painting of", "engraving", "lithograph", ".pdf", "svg", "poster"]


def get_json(url):
    for attempt in range(6):
        time.sleep(1.0)
        try:
            request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            if error.code == 429:
                time.sleep(15 * (attempt + 1))
                continue
            raise
    raise RuntimeError("Too many requests, try again later: " + url)


def download(url):
    for attempt in range(5):
        time.sleep(0.6)
        try:
            request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(request, timeout=60) as response:
                return response.read()
        except urllib.error.HTTPError as error:
            if error.code == 429:
                time.sleep(15 * (attempt + 1))
                continue
            return None
        except (urllib.error.URLError, TimeoutError):
            time.sleep(5)
    return None


def commons(**params):
    params.update(format="json", action="query")
    return get_json("https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode(params))


def strip_html(text):
    return re.sub(r"<[^>]+>", "", text or "").strip()


def is_skipped(title):
    lower = title.lower()
    return any(word in lower for word in SKIP_WORDS)


def category_files(category, include_subcategories):
    files, subcategories, more = [], [], {}
    while True:
        result = commons(list="categorymembers", cmtitle=category, cmlimit=500, cmtype="file|subcat", **more)
        for member in result["query"]["categorymembers"]:
            if member["ns"] == 6:
                files.append(member["title"])
            elif member["ns"] == 14:
                subcategories.append(member["title"])
        if "continue" not in result:
            break
        more = result["continue"]
    if include_subcategories:
        for subcategory in subcategories:
            files += category_files(subcategory, include_subcategories=False)
    return files


def search_files(query):
    result = commons(list="search", srnamespace=6, srsearch=query, srlimit=200)
    return [item["title"] for item in result["query"]["search"]]


def commons_candidates(titles):
    """Licence, author and a 960 px download link for each Commons file, 50 at a time."""
    candidates = []
    titles = [t for t in dict.fromkeys(titles) if t.lower().endswith((".jpg", ".jpeg"))]
    for start in range(0, len(titles), 50):
        result = commons(prop="imageinfo", iiprop="url|extmetadata|size", iiurlwidth=960,
                         titles="|".join(titles[start:start + 50]))
        for page in result["query"].get("pages", {}).values():
            info = (page.get("imageinfo") or [{}])[0]
            meta = info.get("extmetadata", {})
            licence = strip_html(meta.get("LicenseShortName", {}).get("value")).lower()
            if not info.get("thumburl") or info.get("width", 0) < 500:
                continue
            candidates.append({
                "title": page["title"],
                "url": info["thumburl"],
                "page": info.get("descriptionurl", ""),
                "author": strip_html(meta.get("Artist", {}).get("value"))[:80] or "Unknown",
                "licence": licence or "unknown",
                "source": "wikimedia",
            })
    return candidates


def openverse_candidates(query, pages=2):
    """Anonymous Openverse requests are limited to 20 results a page."""
    candidates = []
    for page in range(1, pages + 1):
        params = urllib.parse.urlencode({"q": query, "license_type": "commercial,modification", "page_size": 20,
                                         "page": page, "mature": "false"})
        try:
            result = get_json("https://api.openverse.org/v1/images/?" + params)
        except urllib.error.HTTPError as error:
            print(f"  Openverse skipped '{query}' page {page}: {error.code}")
            break
        for item in result.get("results", []):
            # Commons photos are collected directly above, so they'd only be duplicates here
            if item.get("source") == "wikimedia" or (item.get("width") or 0) < 500:
                continue
            candidates.append({
                "title": item.get("title") or item["id"],
                "url": item["url"],
                "page": item.get("foreign_landing_url", ""),
                "author": (item.get("creator") or "Unknown")[:80],
                "licence": f"cc {item.get('license')} {item.get('license_version') or ''}".strip(),
                "source": item.get("source", "openverse"),
                "tags": " ".join(tag.get("name", "") for tag in item.get("tags") or []),
            })
        if page >= result.get("page_count", 1):
            break
    return candidates


def mentions_landmark(candidate, aliases):
    text = (candidate["title"] + " " + candidate.get("tags", "")).lower()
    return any(alias in text for alias in aliases)


def collect(label, candidates, limit, writer, seen_hashes, seen_titles, excluded):
    # Category lists are in name order, which groups one photographer's series together.
    # Shuffling (with a fixed seed so it can be repeated) gives a more varied set
    random.Random(15).shuffle(candidates)
    folder = os.path.join(RAW, label)
    os.makedirs(folder, exist_ok=True)
    # Photos left out during review don't count, so running again tops the class back up
    saved = len([f for f in os.listdir(folder) if f.endswith(".jpg") and f not in excluded])
    for candidate in candidates:
        if saved >= limit:
            break
        if candidate["title"] in APP_PHOTOS or candidate["title"] in seen_titles or is_skipped(candidate["title"]):
            continue
        seen_titles.add(candidate["title"])
        data = download(candidate["url"])
        if not data or data[:3] != b"\xff\xd8\xff":
            continue
        digest = hashlib.sha1(data).hexdigest()[:16]
        if digest in seen_hashes:
            continue
        seen_hashes.add(digest)
        file_name = f"{digest}.jpg"
        with open(os.path.join(folder, file_name), "wb") as file:
            file.write(data)
        writer.writerow([label, file_name, candidate["source"], candidate["title"], candidate["page"],
                         candidate["author"], candidate["licence"]])
        saved += 1
    print(f"{label}: {saved} photos")


def main():
    config = json.load(open(os.path.join(HERE, "landmarks.json")))
    os.makedirs(RAW, exist_ok=True)
    new_log = not os.path.exists(LOG)
    seen_hashes, seen_titles, excluded = set(), set(), set()
    if not new_log:
        with open(LOG) as file:
            for row in csv.DictReader(file):
                seen_hashes.add(row["file"].removesuffix(".jpg"))
                seen_titles.add(row["title"])
    if os.path.exists(os.path.join(HERE, "excluded.csv")):
        with open(os.path.join(HERE, "excluded.csv")) as file:
            excluded = {row["file"] for row in csv.DictReader(file)}

    with open(LOG, "a", newline="") as file:
        writer = csv.writer(file)
        if new_log:
            writer.writerow(["label", "file", "source", "title", "page", "author", "licence"])

        only = {arg for arg in sys.argv[1:] if not arg.startswith("--")}
        use_commons = "--no-commons" not in sys.argv
        all_aliases = []
        for landmark in config["classes"]:
            all_aliases += landmark["aliases"]
            if only and landmark["label"] not in only:
                continue
            titles = []
            for category in landmark.get("commonsCategories", []) if use_commons else []:
                titles += category_files(category, landmark.get("includeSubcategories", False))
            for query in landmark.get("commonsSearches", []) if use_commons else []:
                titles += search_files(query)
            candidates = commons_candidates(titles)
            for query in landmark.get("openverse", []):
                # Openverse matches tags loosely, so keep only photos that name the landmark
                candidates += [c for c in openverse_candidates(query, pages=3) if mentions_landmark(c, landmark["aliases"])]
            collect(landmark["label"], candidates, config["maxPerClass"], writer, seen_hashes, seen_titles, excluded)
            file.flush()

        # "Other": everyday travel photos that must not show any of the landmarks
        other = config["other"]
        if only and other["label"] not in only:
            return
        candidates = []
        for query in other["openverse"]:
            candidates += [c for c in openverse_candidates(query, pages=1) if not mentions_landmark(c, all_aliases)]
        collect(other["label"], candidates, config["otherMax"], writer, seen_hashes, seen_titles, excluded)


if __name__ == "__main__":
    main()
