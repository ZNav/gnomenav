# Telegram ↔ Claude via OpenClaw ("Jarvis in your pocket")

OpenClaw (ghcr.io/openclaw/openclaw) is the gateway daemon that bridges
messaging channels — Telegram first — to a Claude-backed agent. Declarative
module: `modules/containers/openclaw.nix`, **opt-in** via
`gnomenav.openclaw.enable = true;` in `hosts/msi/default.nix`.

Chosen over TinyClaw: OpenClaw is the mature project (native Telegram channel,
pairing-based DM security, allowlists, sandboxing); TinyClaw is a much smaller
experiment.

## What Zander must provide (blockers)

1. **Telegram bot token** — DONE 2026-07-14: bot is **@archduke33_bot**, token
   lives in `secrets/secrets.yaml` (`telegram_bot_token`, sops-encrypted).
2. **Anthropic API key** — console.anthropic.com → API keys. (Alternative:
   OpenClaw supports other providers/auth modes; API key is the simplest.)
   Still pending.
3. **Telegram user id** — DONE 2026-07-14: Zander is `8215731066`
   (@archduke_33); use for `allowFrom`.

Then put the real values in (from repo root, on the Mac):

```bash
sops secrets/secrets.yaml
# telegram_bot_token: TELEGRAM_BOT_TOKEN=<token>
# anthropic_api_key:  ANTHROPIC_API_KEY=<key>
```

## Enable

```nix
# hosts/msi/default.nix
gnomenav.openclaw.enable = true;
```

First start: put `openclaw.json` in `${configRoot}/openclaw/` with at minimum
the model and the Telegram channel; **keep the security defaults**:

- `dmPolicy: "allowlist"` — only senders in `allowFrom` reach the agent at all
  (strictest; "pairing" would hand unknown senders a pairing code instead).
- `allowFrom: [<your telegram user id>]` — only you.
- Treat inbound DMs as untrusted input; don't grant the agent broad shell on
  day one. Read https://docs.openclaw.ai/gateway/security before widening
  anything.

## Known-good config (LIVE 2026-07-19, reconstructed post-migration)

The original config volume was a docker named-volume casualty of the NixOS
migration. This reconstruction is what runs now at
`${configRoot}/openclaw/openclaw.json` (JSON5; secrets stay in sops env vars):

```json5
{
  gateway: {
    mode: "local",       // REQUIRED — gateway refuses to start without it
    bind: "loopback",    // container binds 0.0.0.0 otherwise and refuses to
                         // start without a gateway auth token; Telegram is
                         // outbound-only so loopback is correct here
  },
  agents: {
    defaults: {
      workspace: "~/.openclaw/workspace",
      model: { primary: "anthropic/claude-opus-4-8" },
    },
  },
  channels: {
    telegram: {
      enabled: true,
      botToken: "${TELEGRAM_BOT_TOKEN}",   // env substitution from sops
      dmPolicy: "allowlist",
      allowFrom: ["8215731066"],           // Zander only
    },
  },
}
```

Gotchas banked from the 2026-07-19 recovery:

- The image runs as `node` (uid 1000). A root-owned config dir crash-loops the
  gateway with `EACCES … mkdir /home/node/.openclaw/state` — `users.nix`
  tmpfiles now pins `${configRoot}/openclaw` to `z:media` (1000:1000).
- Exit `status=78/CONFIG` in the journal = config validation refusal; the
  container is removed on death, so `podman logs` is empty — read
  `journalctl -u podman-openclaw.service` instead.

## Workspace content (stage at first start)

Copy `/Users/znav/ytchannel/` (from the Mac) into `${configRoot}/openclaw/workspace/`
when the container first comes up. It holds `GNOME-SLEEP-PIPELINE.md` — the
one-command system file for the gnome/Minecraft sleep-music YouTube channel —
so the same `give me a sleep-loop pipeline for <theme>` command that works in
Claude Code on the Mac works from Telegram on day one.

## Interim (pre-NixOS) run on Arch msi

**SKIPPED per Zander (2026-07-14)** — OpenClaw goes live with the NixOS
install; no pre-migration container. Kept for reference:

Same container, hand-run (matches the module shape so the switch is clean):

```bash
docker run -d --name openclaw --network nas_nas_media-lan \
  --env-file <(sops -d secrets/secrets.yaml | grep -E 'TELEGRAM|ANTHROPIC' ) \
  -v /var/lib/appdata/openclaw:/home/node/.openclaw \
  ghcr.io/openclaw/openclaw:latest
```

## Later

- Point OpenClaw's model at the local llama.cpp/Qwen endpoint once the GPU
  stack lands (`modules/containers/llm.nix`) for a fully local Jarvis path.
- Consider wiring it to the vault (RAG) via the ai-silo Qdrant instance.
