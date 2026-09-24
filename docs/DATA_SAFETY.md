# DATA SAFETY — read before anything else

`disko` **erases the whole target disk** and repartitions it. There is no undo.
So the order is non-negotiable:

```
1. Inventory   -> know exactly what's on each SSD (scripts/data-inventory.sh)
2. Classify    -> precious (irreplaceable) vs replaceable (re-downloadable media)
3. Dedupe      -> keep ONE copy of each precious item across x220+msi
4. Back up     -> verified copy of precious data on a DIFFERENT disk
5. Confirm     -> backup-precious.sh prints "SAFE TO PROCEED"
6. THEN install NixOS
```

## Precious vs replaceable
- **Precious (must survive):** Immich/photo library, Nextcloud files, any DB
  volumes (`immich/db`, `nextcloud/db`), family docs, the homelab repos, ssh keys.
- **Replaceable (fine to lose/re-fetch):** movies, TV, `torrents/`, music that
  spotdl/Lidarr can re-pull, container images. Don't waste backup space on these.

## Dedupe across the two SSDs (keep 1 copy, lose nothing)
After both `inventory-*.txt` come back, I'll diff them and flag anything that
exists on both. We delete the duplicate ONLY after the surviving copy is backed
up and verified. Rule enforced by the scripts: never delete an unbacked-up file.

## Where does the backup go?
It must be a disk we are NOT about to wipe. Options, best first:
1. External USB SSD/HDD big enough for the precious set (usually < 1–2 TB).
2. The *other* machine over the network (back up x220's precious data onto msi
   first, install x220, then reverse) — works if neither is wiped simultaneously.
   This is why "both back to back" (not simultaneous) matters.
3. Cloudflare R2 / Backblaze B2 for an offsite copy (I can add a restic module).

## The gate
`scripts/backup-precious.sh` hashes every source file, copies with rsync, then
re-hashes the copy and refuses to say "SAFE TO PROCEED" unless they match. Do not
run `nixos-anywhere` against a host until you've seen that line for that host.
