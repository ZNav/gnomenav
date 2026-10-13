#!/usr/bin/env bash
# Usage: wg-conf-to-sops.sh <mullvad-wg.conf>
# Parse a standard WireGuard .conf (e.g. downloaded from mullvad.net) into the
# sops `wireguard_env` secret in gluetun format. Values never printed.
# After running: rsync repo to msi + `nixos-rebuild switch`, then shred the .conf.
set -euo pipefail
CONF=${1:?usage: wg-conf-to-sops.sh <wg.conf>}
REPO="$(cd "$(dirname "$0")/.." && pwd)"

# NB: base64 keys end in '='; split on the FIRST '=' only (awk -F'=' eats it).
get() { sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$CONF" | head -1; }
PRIV=$(get PrivateKey); ADDR=$(get Address); PUB=$(get PublicKey); EP=$(get Endpoint)
[[ -n $PRIV && -n $ADDR && -n $PUB && -n $EP ]] || { echo "missing fields in $CONF" >&2; exit 1; }
HOST=${EP%:*}; PORT=${EP##*:}
if [[ ! $HOST =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  HOST=$(dig +short "$HOST" | grep -m1 -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
  [[ -n $HOST ]] || { echo "could not resolve endpoint host" >&2; exit 1; }
fi

BLOB=$(printf 'WIREGUARD_PRIVATE_KEY=%s\nWIREGUARD_PUBLIC_KEY=%s\nWIREGUARD_ADDRESSES=%s\nVPN_ENDPOINT_IP=%s\nVPN_ENDPOINT_PORT=%s\n' \
  "$PRIV" "$PUB" "$ADDR" "$HOST" "$PORT")
sops set "$REPO/secrets/secrets.yaml" '["wireguard_env"]' \
  "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$BLOB")"
echo "wireguard_env updated from $CONF (endpoint $HOST:$PORT)."
echo "Next: rsync -rc --exclude=.git $REPO/ z@10.0.0.171:nixos-homelab/ && ssh z@10.0.0.171 sudo nixos-rebuild switch --flake '~/nixos-homelab#msi'"
echo "Then: rm -P $CONF"
