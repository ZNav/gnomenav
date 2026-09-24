# Central data silo + local AI ("Jarvis")

## Idea
One canonical data pool that every service writes to, and a retrieval layer so the
local LLM can answer from YOUR files (docs, wiki, books, notes, photo metadata).
This is **RAG**, not fine-tuning: the model (Qwen3.5) stays fixed and *retrieves*
relevant chunks at query time. New/changed files are searchable as soon as they're
indexed — no retraining, cheap, always current, and fully local/private.

## The silo (canonical layout under NixOS)
Today data is split across msi-local `/home/znav/nas` and the x220 NFS `/mnt/x220`.
Consolidate to ONE addressable tree (`${DATA_ROOT}`, default `/data`), mounted
identically on every host/container:

```
/data
├── media/{movies,tv,music,books,photos,...}   # existing library
├── docs/            # nextcloud files, Google Takeout, scans
├── knowledge/       # THE CORPUS the AI reads (text-extracted, chunk-ready)
│   ├── nextcloud/  wiki/  books/  notes/  llm-documents/  web-clips/
└── vectors/qdrant/  # embeddings (the AI's long-term memory)
```

Modularity: adding a disk = point a subtree at the new mount; adding a machine =
it mounts `/data` and joins in. Nothing hard-codes raw device paths.

## The Jarvis stack (all local, on msi)
| Layer | Choice | Why |
|---|---|---|
| Generation | llama.cpp Vulkan + **Qwen3.5-9B** | uses the RX 6700M GPU (Ollama today is CPU-only) |
| Embeddings | **nomic-embed-text** / bge-m3 | small, fast, local |
| Vector DB | **Qdrant** | simple, fast, container-native (`ai-silo.nix`) |
| Assistant UI | **Open WebUI Knowledge** (already deployed) and/or **Khoj** | Khoj = notes/docs "second brain" chat; Open WebUI = general chat + RAG |
| Indexing | `scripts/silo-index.sh` nightly timer | aggregates sources → corpus → re-embed |

## Data flow
```
Nextcloud / Wiki / Books / Notes ──► /data/knowledge (silo-index.sh, nightly)
                                          │  embed (nomic-embed-text)
                                          ▼
                                   Qdrant vectors ◄── query ── Open WebUI / Khoj
                                          ▲                         │
                                          └──── Qwen3.5 (llama.cpp) ─┘ answer
```

## Privacy / safety
- 100% local: no data leaves the LAN; the tunnel only exposes the chat UI (behind
  Cloudflare Access).
- Corpus mounted **read-only** into the AI containers; indexing never mutates source.
- Photos: index EXIF/metadata + captions, not raw images, unless you opt in to a
  local vision model.

## Rollout (after the NixOS migration; non-destructive to add before it too)
1. Deploy Qdrant + swap Ollama→llama.cpp/Qwen3.5 (GPU).
2. Point Open WebUI "Knowledge" at `/data/knowledge` + Qdrant; test a query.
3. Add Khoj for the notes/second-brain experience; enable the nightly index timer.
