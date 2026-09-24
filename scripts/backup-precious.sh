#!/usr/bin/env bash
# Back up IRREPLACEABLE data off the target disk with a VERIFIED copy.
# Run BEFORE nixos-anywhere/disko touches a machine.
#
# Usage:
#   BACKUP_DEST=/mnt/external/gnomenav-backup \
#   SRC_DIRS="/data/immich /data/nextcloud /opt/appdata/nextcloud/db /opt/appdata/immich/db" \
#   bash backup-precious.sh
#
# DEST must be on a DIFFERENT physical disk than the machine you're about to wipe
# (external USB SSD, the OTHER machine over the network, or a NAS). NEVER back up
# a disk onto itself.
set -euo pipefail
: "${BACKUP_DEST:?set BACKUP_DEST to a path on a different disk}"
: "${SRC_DIRS:?set SRC_DIRS to space-separated precious paths}"
HOST=$(hostname); STAMP=$(date +%Y%m%d-%H%M%S)
OUT="$BACKUP_DEST/$HOST-$STAMP"
mkdir -p "$OUT"

echo ">> Free space check"
df -h "$BACKUP_DEST"

for src in $SRC_DIRS; do
  [ -e "$src" ] || { echo "SKIP missing: $src"; continue; }
  name=$(echo "$src" | tr '/' '_')
  echo ">> Hashing source: $src"
  find "$src" -type f -print0 | sort -z | xargs -0 sha256sum > "$OUT/${name}.sha256.src"
  echo ">> Copying (rsync, preserves perms): $src"
  rsync -aH --info=progress2 "$src" "$OUT/"
done

echo ">> Verifying copies against source hashes"
FAIL=0
for src in $SRC_DIRS; do
  [ -e "$src" ] || continue
  name=$(echo "$src" | tr '/' '_')
  base=$(basename "$src")
  ( cd "$OUT" && sed "s#$src#$OUT/$base#g" "${name}.sha256.src" | sha256sum -c --quiet ) \
    || { echo "!! VERIFY FAILED for $src"; FAIL=1; }
done

if [ "$FAIL" = 0 ]; then
  echo ">> All verified. Optional single-archive:"
  echo "   tar -C '$OUT' -czf '$BACKUP_DEST/$HOST-$STAMP.tar.gz' ."
  echo ">> SAFE TO PROCEED with install for $HOST."
else
  echo ">> DO NOT WIPE $HOST — backup verification failed."; exit 1
fi
