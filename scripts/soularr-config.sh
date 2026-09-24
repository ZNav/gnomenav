#!/usr/bin/env bash
# Generate /var/lib/appdata/soularr/config.ini ON msi (run with sudo).
# Both API keys are read from on-host files and never leave the machine —
# this file is safe for git precisely because the secrets are not in it.
set -euo pipefail

LIDARR_KEY=$(sed -n 's:.*<ApiKey>\(.*\)</ApiKey>.*:\1:p' /var/lib/appdata/lidarr/config.xml)
# slskd_yml sops secret: take the key under api_keys -> soularr
SLSKD_KEY=$(awk '/api_keys:/{f=1} f && /key:/{gsub(/[ '\'']/,"",$2); print $2; exit}' /run/secrets/slskd_yml)
[ -n "$LIDARR_KEY" ] && [ -n "$SLSKD_KEY" ] || { echo "missing key(s)" >&2; exit 1; }

install -d -m 0750 -o z -g media /var/lib/appdata/soularr
cat > /var/lib/appdata/soularr/config.ini <<EOF
[Lidarr]
api_key = $LIDARR_KEY
host_url = http://lidarr:8686
download_dir = /data/downloads/slskd/complete
disable_sync = False

[Slskd]
api_key = $SLSKD_KEY
host_url = http://vpn:5030
url_base = /
# soularr's local view of slskd's complete dir (host /data/downloads/slskd/complete)
download_dir = /downloads
delete_searches = False
stalled_timeout = 3600
remote_queue_timeout = 300

[Release Settings]
use_selected_lidarr_release = False
use_most_common_tracknum = True
allow_multi_disc = True
accepted_countries = Europe,Japan,United Kingdom,United States,[Worldwide],Australia,Canada
skip_region_check = False
accepted_formats = CD,Digital Media,Vinyl

[Search Settings]
search_timeout = 5000
maximum_peer_queue = 50
minimum_peer_upload_speed = 0
minimum_filename_match_ratio = 0.8
minimum_search_interval = 5
# 16/44.1 first — 24/192 masters are 3-5x the disk for nothing on this setup
# (lesson of 2026-08-02: hi-res-first ate 185G in five days and filled the fs)
allowed_filetypes = flac 16/44.1,flac,mp3 320
ignored_users =
album_prepend_artist = False
search_type = incrementing_page
number_of_albums_to_grab = 5
title_blacklist =
search_blacklist =
# valid: missing | cutoff_unmet. Start on missing (liked-songs gaps); flip to
# cutoff_unmet once the missing queue drains to hunt FLAC upgrades of owned mp3s.
search_source = missing
failed_import_denylist = True

[Download Settings]
download_filtering = True
use_extension_whitelist = False
extensions_whitelist = lrc,nfo,txt

[Logging]
level = INFO
format = [%(levelname)s|%(module)s|L%(lineno)d] %(asctime)s: %(message)s
datefmt = %Y-%m-%dT%H:%M:%S%z
log_to_file = True
log_file = soularr.log
max_bytes = 1048576
backup_count = 3
EOF
chown z:media /var/lib/appdata/soularr/config.ini
chmod 0640 /var/lib/appdata/soularr/config.ini
echo "wrote /var/lib/appdata/soularr/config.ini"
