#!/usr/bin/env python3
"""prowlarr-autosort: route manual Prowlarr grabs into the right *arr.

The arrs only import downloads they started themselves. Anything grabbed by
hand from Prowlarr's search UI lands in qBittorrent under the 'prowlarr'
category and would sit in /data/downloads forever. This service:

  1. finds completed qbit torrents in that category (not yet tagged),
  2. classifies them (guessit + file-extension vote),
  3. adds the series/movie/artist to the matching arr UNMONITORED (import
     works, nothing starts auto-grabbing),
  4. fires the arr's Downloaded*Scan with importMode=Copy — copyUsingHardlinks
     is on and /data is one filesystem, so imports hardlink and seeding
     continues untouched,
  5. tags the torrent 'autosorted' (or 'unsorted' when classification fails —
     never guess, leave those for a human).

Also: --adopt <path> runs steps 2-4 on any pre-existing folder/file under
/data (e.g. legacy downloads from the compose era).

Runs on the host as root: reads arr API keys from their config.xml, resolves
container IPs via podman, gets qbit credentials from the sops-provided
environment (QBIT_USER/QBIT_PASS).
"""
import argparse, json, os, re, subprocess, sys, time, xml.etree.ElementTree as ET
import requests
from guessit import guessit

APPDATA = "/var/lib/appdata"
CATEGORY = "prowlarr"
TAG_DONE, TAG_FAIL = "autosorted", "unsorted"
VIDEO_EXT = {".mkv", ".mp4", ".avi", ".m4v", ".ts", ".wmv"}
AUDIO_EXT = {".flac", ".mp3", ".m4a", ".opus", ".ogg", ".wav", ".ape"}
ARR = {
    "sonarr": dict(port=8989, api="v3", scan="DownloadedEpisodesScan"),
    "radarr": dict(port=7878, api="v3", scan="DownloadedMoviesScan"),
    "lidarr": dict(port=8686, api="v1", scan="DownloadedAlbumsScan"),
}

def log(msg):
    print(msg, flush=True)

def container_ip(name):
    out = subprocess.check_output(
        ["podman", "inspect", name, "--format",
         "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}"], text=True).strip()
    if not out:
        raise RuntimeError(f"no IP for container {name}")
    return out

def arr_base(app):
    ip = container_ip(app if app != "qbit" else "vpn")
    return f"http://{ip}:{ARR[app]['port']}/api/{ARR[app]['api']}"

def arr_key(app):
    return ET.parse(f"{APPDATA}/{app}/config.xml").findtext(".//ApiKey")

def arr(app, method, path, **kw):
    r = requests.request(method, arr_base(app) + path,
                         headers={"X-Api-Key": arr_key(app)}, timeout=60, **kw)
    r.raise_for_status()
    return r.json() if r.text else None

def arr_cmd(app, payload, wait=120):
    """POST a command and poll it to completion."""
    cid = arr(app, "POST", "/command", json=payload)["id"]
    for _ in range(wait // 5):
        time.sleep(5)
        if arr(app, "GET", f"/command/{cid}")["status"] in ("completed", "failed"):
            break

# ---------- classification ----------

def classify(name, files):
    """-> ('sonarr'|'radarr'|'lidarr'|None, guessit dict)"""
    exts = [os.path.splitext(f)[1].lower() for f in files]
    n_vid = sum(e in VIDEO_EXT for e in exts)
    n_aud = sum(e in AUDIO_EXT for e in exts)
    if n_aud > n_vid and n_aud > 0:
        return "lidarr", guessit(name)
    g = guessit(name)
    if g.get("type") == "episode":
        return "sonarr", g
    if g.get("type") == "movie" and n_vid > 0:
        return "radarr", g
    return None, g

# ---------- per-arr add-if-missing ----------

def first_quality_profile(app):
    return arr(app, "GET", "/qualityprofile")[0]["id"]

def ensure_series(g):
    term = g.get("title", "")
    if g.get("year"): term += f" {g['year']}"
    hits = arr("sonarr", "GET", "/series/lookup", params={"term": term})
    if not hits:
        raise LookupError(f"sonarr lookup empty for {term!r}")
    hit = hits[0]
    for s in arr("sonarr", "GET", "/series"):
        if s["tvdbId"] == hit["tvdbId"]:
            return s["title"], s["id"]
    hit.update(qualityProfileId=first_quality_profile("sonarr"),
               rootFolderPath="/data/media/shows", monitored=False,
               seasonFolder=True,
               addOptions={"searchForMissingEpisodes": False})
    added = arr("sonarr", "POST", "/series", json=hit)
    # the scan is useless until sonarr's refresh has populated the episodes
    for _ in range(24):
        time.sleep(5)
        if arr("sonarr", "GET", "/episode", params={"seriesId": added["id"]}):
            break
    return hit["title"] + " (added unmonitored)", added["id"]

def sonarr_mapped_import(series_id, folder):
    """Fallback for releases without SxxEyy (e.g. '01_Asteroid_Blues_…'):
    sonarr's parser maps every such file to ALL episodes and auto-import skips
    them as ambiguous. Resolve the episode from the leading number (or
    guessit) and fire an explicit ManualImport."""
    epmap = {e["episodeNumber"]: e["id"]
             for e in arr("sonarr", "GET", "/episode", params={"seriesId": series_id})}
    items = arr("sonarr", "GET", "/manualimport",
                params={"folder": folder, "filterExistingFiles": "true"})
    files = []
    for it in items:
        if len(it.get("episodes") or []) == 1:
            continue  # unambiguous — a rerun of the scan will take it
        m = re.match(r"^(\d{1,3})\b", os.path.basename(it["relativePath"]).replace("_", " "))
        num = int(m.group(1)) if m else guessit(it["relativePath"]).get("episode")
        if not isinstance(num, int) or num not in epmap:
            log(f"  mapped-import: no episode for {it['relativePath']!r}, leaving")
            continue
        files.append({"path": it["path"], "seriesId": series_id,
                      "episodeIds": [epmap[num]], "quality": it["quality"],
                      "languages": it["languages"], "indexerFlags": 0,
                      "releaseType": "singleEpisode"})
    if files:
        arr_cmd("sonarr", {"name": "ManualImport", "importMode": "copy", "files": files})
    return len(files)

def ensure_movie(g):
    term = g.get("title", "")
    if g.get("year"): term += f" {g['year']}"
    hits = arr("radarr", "GET", "/movie/lookup", params={"term": term})
    if not hits:
        raise LookupError(f"radarr lookup empty for {term!r}")
    hit = hits[0]
    for m in arr("radarr", "GET", "/movie"):
        if m["tmdbId"] == hit["tmdbId"]:
            return m["title"]
    hit.update(qualityProfileId=first_quality_profile("radarr"),
               rootFolderPath="/data/media/movies", monitored=False,
               addOptions={"searchForMovie": False})
    arr("radarr", "POST", "/movie", json=hit)
    return hit["title"] + " (added unmonitored)"

def ensure_artist(g, name):
    # music release names are 'Artist - Album - ...'; guessit knows nothing of
    # artists, so take the segment before the first ' - ' as the search term.
    term = (name.split(" - ")[0] if " - " in name else g.get("title", name)).strip()
    hits = arr("lidarr", "GET", "/artist/lookup", params={"term": term})
    if not hits:
        raise LookupError(f"lidarr lookup empty for {term!r}")
    hit = hits[0]
    for a in arr("lidarr", "GET", "/artist"):
        if a["foreignArtistId"] == hit["foreignArtistId"]:
            return a["artistName"]
    meta = [p for p in arr("lidarr", "GET", "/metadataprofile") if p["name"] != "None"]
    hit.update(qualityProfileId=first_quality_profile("lidarr"),
               metadataProfileId=meta[0]["id"],
               rootFolderPath="/data/media/music", monitored=False,
               addOptions={"searchForMissingAlbums": False})
    arr("lidarr", "POST", "/artist", json=hit)
    return hit["artistName"] + " (added unmonitored)"

def dispatch(name, path, files):
    """Classify and hand to an arr. -> (app|None, detail)"""
    app, g = classify(name, files)
    if app is None:
        return None, f"unclassifiable (guessit type={g.get('type')})"
    if app == "sonarr":
        added, series_id = ensure_series(g)
    else:
        added = ensure_movie(g) if app == "radarr" else ensure_artist(g, name)
    arr_cmd(app, {"name": ARR[app]["scan"], "path": path, "importMode": "Copy"})
    detail = f"{added}; {ARR[app]['scan']} done on {path}"
    if app == "sonarr" and os.path.isdir(path):
        n = sonarr_mapped_import(series_id, path)
        if n:
            detail += f"; +{n} via mapped ManualImport"
    return app, detail

# ---------- qbit ----------

def qbit_session():
    base = f"http://{container_ip('vpn')}:8080/api/v2"
    s = requests.Session()
    r = s.post(base + "/auth/login", data={"username": os.environ["QBIT_USER"],
                                           "password": os.environ["QBIT_PASS"]}, timeout=30)
    if "QBT_SID" not in "".join(s.cookies.keys()):
        raise RuntimeError(f"qbit login failed: {r.status_code} {r.text[:80]}")
    return base, s

def sweep():
    base, s = qbit_session()
    done = 0
    for t in s.get(base + "/torrents/info", params={"category": CATEGORY}, timeout=30).json():
        tags = {x.strip() for x in t["tags"].split(",")}
        if t["progress"] < 1 or tags & {TAG_DONE, TAG_FAIL}:
            continue
        files = [f["name"] for f in
                 s.get(base + "/torrents/files", params={"hash": t["hash"]}, timeout=30).json()]
        try:
            app, detail = dispatch(t["name"], t["content_path"], files)
        except Exception as e:                      # lookup/API failure -> human
            app, detail = None, f"error: {e}"
        tag = TAG_DONE if app else TAG_FAIL
        s.post(base + "/torrents/addTags", data={"hashes": t["hash"], "tags": tag}, timeout=30)
        log(f"[{tag}] {t['name']} -> {app or '-'}: {detail}")
        done += 1
    log(f"sweep complete, {done} torrent(s) processed")

def adopt(path):
    path = os.path.abspath(path)
    if not os.path.exists(path):
        sys.exit(f"no such path: {path}")
    if not path.startswith("/data/"):
        sys.exit("adopt only handles paths under /data (the arrs can't see anything else)")
    files = ([os.path.join(dp, f) for dp, _, fs in os.walk(path) for f in fs]
             if os.path.isdir(path) else [path])
    app, detail = dispatch(os.path.basename(path), path, files)
    log(f"[adopt] {os.path.basename(path)} -> {app or '-'}: {detail}")
    if app is None:
        sys.exit(1)

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--adopt", metavar="PATH",
                    help="classify + import one existing folder/file under /data")
    a = ap.parse_args()
    adopt(a.adopt) if a.adopt else sweep()
