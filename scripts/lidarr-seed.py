#!/usr/bin/env python3
"""Seed lidarr from Zander's music data (stdlib only — runs in python:alpine).

  seed     add artists from /seed/artists.txt (monitored, album-monitor: none)
  monitor  mark albums monitored: any album with files on disk (FLAC-upgrade
           path) + any album containing a liked track from /seed/liked.txt
           ("Artist ~ Title" lines)

Lidarr API key is parsed from the mounted lidarr config dir; nothing secret
leaves the host. Idempotent + throttled; safe to re-run.

  podman run --rm --network=proxy \
    -v /var/lib/appdata/lidarr:/lcfg:ro -v /seed:/seed \
    docker.io/library/python:3.12-alpine \
    python /seed/lidarr-seed.py seed
"""
import difflib, json, re, sys, time, unicodedata, urllib.request, urllib.parse

BASE = "http://lidarr:8686/api/v1"
KEY = re.search(r"<ApiKey>(.*?)</ApiKey>", open("/lcfg/config.xml").read()).group(1)
ROOT = "/data/media/music"
PROFILE_NAME = "FLAC Upgrade"


def api(method, path, body=None, q=None):
    url = f"{BASE}/{path}" + (("?" + urllib.parse.urlencode(q)) if q else "")
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method,
                                 headers={"X-Api-Key": KEY, "Content-Type": "application/json"})
    for attempt in range(5):
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                return json.loads(r.read() or "null")
        except urllib.error.HTTPError as e:
            if e.code in (429, 500, 502, 503) and attempt < 4:
                time.sleep(10 * (attempt + 1)); continue
            print(f"  !! {method} {path}: HTTP {e.code} {e.read()[:200]}", flush=True)
            raise
        except Exception as e:
            if attempt < 4:
                time.sleep(10 * (attempt + 1)); continue
            raise


def norm(s):
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode().lower()
    s = re.sub(r"\(.*?\)|\[.*?\]", " ", s)
    s = re.sub(r"\b(feat|ft|with|prod)\b.*", " ", s)
    return " ".join(re.sub(r"[^a-z0-9]+", " ", s).split())


def ensure_profile():
    profiles = api("GET", "qualityprofile")
    for p in profiles:
        if p["name"] == PROFILE_NAME:
            return p["id"]
    base = next((p for p in profiles if p["name"] == "Any"), profiles[0])
    p = json.loads(json.dumps(base)); p.pop("id", None)
    p["name"] = PROFILE_NAME; p["upgradeAllowed"] = True
    cutoff = None
    for item in p["items"]:
        item["allowed"] = True
        names = [item.get("name") or ""] + [i["quality"]["name"] for i in item.get("items", [])]
        if item.get("quality"): names.append(item["quality"]["name"])
        if any(n.upper() == "FLAC" for n in names):
            cutoff = item.get("id") or item["quality"]["id"]
    if cutoff is None:
        sys.exit("no FLAC quality found in base profile")
    p["cutoff"] = cutoff
    created = api("POST", "qualityprofile", p)
    print(f"created profile '{PROFILE_NAME}' id={created['id']} cutoff={cutoff}", flush=True)
    return created["id"]


def seed():
    pid = ensure_profile()
    have = api("GET", "artist")
    seen = {norm(a["artistName"]) for a in have}
    names = [l.strip() for l in open("/seed/artists.txt") if l.strip()]
    added = skipped = failed = 0
    for i, name in enumerate(names, 1):
        if norm(name) in seen:
            skipped += 1; continue
        try:
            hits = api("GET", "artist/lookup", q={"term": name})
        except Exception:
            failed += 1; continue
        time.sleep(1.5)
        if not hits:
            print(f"  no match: {name}", flush=True); failed += 1; continue
        hit = hits[0]
        if difflib.SequenceMatcher(None, norm(name), norm(hit["artistName"])).ratio() < 0.75:
            print(f"  weak match, skipped: {name!r} -> {hit['artistName']!r}", flush=True)
            failed += 1; continue
        body = {**hit, "qualityProfileId": pid, "metadataProfileId": 1,
                "rootFolderPath": ROOT, "monitored": True,
                "addOptions": {"monitor": "none", "searchForMissingAlbums": False}}
        try:
            api("POST", "artist", body)
            seen.add(norm(hit["artistName"])); added += 1
        except Exception:
            failed += 1
        if i % 25 == 0:
            print(f"[{i}/{len(names)}] added={added} skipped={skipped} failed={failed}", flush=True)
    print(f"DONE added={added} skipped={skipped} (already present) failed={failed}", flush=True)


def monitor():
    liked = {}
    for line in open("/seed/liked.txt"):
        if " ~ " in line:
            a, t = line.strip().split(" ~ ", 1)
            liked.setdefault(norm(a), set()).add(norm(t))
    flipped = 0
    for artist in api("GET", "artist"):
        albums = api("GET", "album", q={"artistId": artist["id"]})
        want = {al["id"] for al in albums
                if not al["monitored"] and al.get("statistics", {}).get("trackFileCount", 0) > 0}
        titles = liked.get(norm(artist["artistName"]))
        if titles:
            try:
                tracks = api("GET", "track", q={"artistId": artist["id"]})
                by_album = {}
                for t in tracks:
                    by_album.setdefault(t["albumId"], set()).add(norm(t["title"]))
                for alid, ts in by_album.items():
                    if ts & titles:
                        al = next(a for a in albums if a["id"] == alid)
                        if not al["monitored"]:
                            want.add(alid)
            except Exception:
                pass
        for alid in want:
            al = next(a for a in albums if a["id"] == alid)
            al["monitored"] = True
            api("PUT", f"album/{alid}", al)
            flipped += 1
        time.sleep(0.5)
    print(f"DONE monitored {flipped} albums", flush=True)


def prune():
    """Unmonitor file-less albums that contain no liked track — shrinks the
    'missing' queue to liked material only (2026-08-02 disk-full lesson)."""
    liked = {}
    for line in open("/seed/liked.txt"):
        if " ~ " in line:
            a, t = line.strip().split(" ~ ", 1)
            liked.setdefault(norm(a), set()).add(norm(t))
    off = 0
    for artist in api("GET", "artist"):
        albums = api("GET", "album", q={"artistId": artist["id"]})
        candidates = [al for al in albums if al["monitored"]
                      and al.get("statistics", {}).get("trackFileCount", 0) == 0]
        if not candidates:
            continue
        keep = set()
        titles = liked.get(norm(artist["artistName"]))
        if titles:
            try:
                tracks = api("GET", "track", q={"artistId": artist["id"]})
                for t in tracks:
                    if norm(t["title"]) in titles:
                        keep.add(t["albumId"])
            except Exception:
                keep = {al["id"] for al in candidates}  # can't tell -> keep all
        for al in candidates:
            if al["id"] not in keep:
                al["monitored"] = False
                api("PUT", f"album/{al['id']}", al)
                off += 1
        time.sleep(0.5)
    print(f"DONE unmonitored {off} albums", flush=True)


{"seed": seed, "monitor": monitor, "prune": prune}[sys.argv[1]]()
