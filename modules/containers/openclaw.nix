# OpenClaw — Telegram (and other channels) ↔ Claude gateway ("Jarvis in your pocket").
# Off by default: flip gnomenav.openclaw.enable once the secrets are real
# (telegram_bot_token from @BotFather, anthropic_api_key) — see docs/TELEGRAM-OPENCLAW.md.
# Security posture: DMs are untrusted input. Keep dmPolicy=pairing + allowFrom
# pinned to Zander's Telegram user id in the openclaw.json config volume.
{ config, lib, pkgs, ... }:
let
  c = config.gnomenav;
  cfg = config.gnomenav.openclaw;
in
{
  options.gnomenav.openclaw.enable = lib.mkEnableOption "OpenClaw Telegram↔Claude gateway";

  config = lib.mkIf (cfg.enable && c.role == "compute") {
    sops.secrets.telegram_bot_token = {};
    sops.secrets.anthropic_api_key = {};

    virtualisation.oci-containers.containers.openclaw = {
      image = "ghcr.io/openclaw/openclaw:latest";
      autoStart = true;
      extraOptions = [ "--network=proxy" ];
      # Gateway config lives in the volume (openclaw.json: model, channels,
      # dmPolicy/allowFrom). Secrets come in as env vars, never baked into config.
      environmentFiles = [
        config.sops.secrets.telegram_bot_token.path
        config.sops.secrets.anthropic_api_key.path
      ];
      volumes = [ "${c.configRoot}/openclaw:/home/node/.openclaw" ];
    };
  };
}
