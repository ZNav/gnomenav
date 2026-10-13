#!/usr/bin/env bash
# One-shot: migrate the old WireGuard creds (msi /home/znav/nas/.env, WG_* vars)
# into sops secrets.yaml as `wireguard_env`, in gluetun custom-provider format.
# Values are held in shell vars only — never printed, never in the vault.
# Needs: the admin age key on this Mac (~/.config/sops/age/keys.txt) + ssh to msi.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"

eval "$(ssh z@10.0.0.171 'grep -E "^WG_(PRIVKEY|PUBKEY|ADDRESS|ENDPOINT)=" /home/znav/nas/.env')"
HOST=${WG_ENDPOINT%:*}; PORT=${WG_ENDPOINT##*:}
# gluetun custom provider wants an IP endpoint; resolve if the old value is a name.
if [[ ! $HOST =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  HOST=$(dig +short "$HOST" | grep -m1 -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
  [[ -n $HOST ]] || { echo "could not resolve WG endpoint host" >&2; exit 1; }
fi

BLOB=$(printf 'WIREGUARD_PRIVATE_KEY=%s\nWIREGUARD_PUBLIC_KEY=%s\nWIREGUARD_ADDRESSES=%s\nVPN_ENDPOINT_IP=%s\nVPN_ENDPOINT_PORT=%s\n' \
  "$WG_PRIVKEY" "$WG_PUBKEY" "$WG_ADDRESS" "$HOST" "$PORT")
sops set "$REPO/secrets/secrets.yaml" '["wireguard_env"]' \
  "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$BLOB")"
echo "wireguard_env written to $REPO/secrets/secrets.yaml (endpoint $HOST:$PORT)"
