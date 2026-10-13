#!/usr/bin/env bash
# Aggregate knowledge sources into the central corpus, then trigger re-index.
# Sources -> /data/knowledge/<source>/ ; the AI (Khoj/Open WebUI) reads /data/knowledge.
set -euo pipefail
DATA=${DATA_ROOT:-/data}
K="$DATA/knowledge"
mkdir -p "$K"/{nextcloud,wiki,books,notes,llm-documents,web-clips}

# Pull text-bearing files from each source (read-only mirrors, additive).
rsync -a --include='*/' \
  --include='*.md' --include='*.txt' --include='*.pdf' --include='*.epub' \
  --include='*.docx' --include='*.html' --exclude='*' \
  "$DATA/docs/nextcloud/" "$K/nextcloud/" 2>/dev/null || true
rsync -a "$DATA/media/books/" "$K/books/" \
  --include='*/' --include='*.epub' --include='*.pdf' --include='*.txt' --exclude='*' 2>/dev/null || true
# wiki.js + notes + llm-documents exports land here via their own hooks.

# Trigger re-index (Khoj API). Open WebUI Knowledge can also watch this dir.
curl -fsS -X POST http://localhost:42110/api/update?force=true 2>/dev/null || \
  echo "[silo-index] Khoj not reachable yet; corpus staged at $K"
echo "[silo-index] done $(date -Is)"
