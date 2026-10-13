#!/usr/bin/env bash
# After both inventory files exist, find precious files present on BOTH machines.
# READ-ONLY: prints a plan, deletes nothing.
#   bash dedupe-plan.sh inventory-x220.txt inventory-msi.txt
# (For a real content-level dedupe we hash precious dirs on each host and diff;
#  this is the first-pass by path/name. Deletion happens manually, post-backup.)
set -euo pipefail
echo "Review both inventories; candidate duplicate roots to reconcile:"
grep -hiE 'photo|immich|nextcloud|document|memories|family' "$@" | sort -u
echo
echo "Next: on each host, hash the precious dirs:"
echo "  find <dir> -type f -exec sha256sum {} + | sort > host.hashes"
echo "Then diff hashes to find true content duplicates. Delete the dup only after"
echo "the survivor is verified-backed-up."
