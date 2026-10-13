#!/usr/bin/env bash
# READ-ONLY. Catalog data on this host + its SSDs so we know what's precious
# BEFORE disko wipes anything. Run on BOTH machines:
#   bash data-inventory.sh > ~/inventory-$(hostname).txt
set -uo pipefail
S(){ printf '\n===== %s =====\n' "$*"; }

S HOST; hostname; date -Is
S DISKS; lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT,MODEL,SERIAL
S MOUNTS; df -h -x tmpfs -x overlay -x squashfs

# Candidate data roots — precious stuff usually lives here.
ROOTS="/data /srv /mnt /media /home /opt/appdata /var/lib/docker/volumes"

S TOP_DIRS
for r in $ROOTS; do [ -d "$r" ] && du -h -d 2 "$r" 2>/dev/null | sort -rh | head -25; done

S PRECIOUS_HINTS  # photos, docs, nextcloud, immich, db dumps — the irreplaceable stuff
for r in $ROOTS; do [ -d "$r" ] && \
  find "$r" -maxdepth 4 -type d \( -iname '*photo*' -o -iname '*immich*' \
    -o -iname '*nextcloud*' -o -iname '*document*' -o -iname '*backup*' \
    -o -iname '*family*' -o -iname '*memories*' \) 2>/dev/null; done

S MEDIA_REPLACEABLE  # movies/tv/music from *arr — re-downloadable, NOT precious
for r in $ROOTS; do [ -d "$r" ] && \
  find "$r" -maxdepth 3 -type d \( -iname '*movies*' -o -iname '*tv*' \
    -o -iname '*torrents*' \) 2>/dev/null; done

S FILE_COUNTS_BY_TYPE
for r in $ROOTS; do [ -d "$r" ] && { echo "--- $r"; \
  find "$r" -type f 2>/dev/null | sed 's/.*\.//' | tr 'A-Z' 'a-z' \
  | sort | uniq -c | sort -rn | head -15; }; done

S DOCKER_VOLUMES
docker volume ls 2>/dev/null
docker ps -a --format '{{.Names}}' 2>/dev/null | while read c; do
  docker inspect "$c" --format '{{.Name}}: {{range .Mounts}}{{.Source}}->{{.Destination}} {{end}}' 2>/dev/null
done

S CHECKSUM_PLAN
echo "Precious dirs above should be hashed before AND after backup (see backup-precious.sh)."
S DONE
