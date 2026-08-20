#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT="$HOME/.local/share/cereblix-termux"
BIN="$ROOT/bin/cereblix-termux"
CFG="$ROOT/config"
[ -x "$BIN" ] || { echo "Belum terpasang. Jalankan ./install.sh terlebih dahulu."; exit 1; }
[ -f "$CFG" ] && . "$CFG"
if [ -z "${CRB_WALLET:-}" ]; then
  printf 'CRB wallet address (crb1...): '
  read -r CRB_WALLET
fi
[ -n "$CRB_WALLET" ] || { echo 'Wallet wajib diisi.'; exit 1; }
CRB_WORKER="${CRB_WORKER:-HP1}"
CRB_THREADS="${CRB_THREADS:-0}"
CRB_POOL_HOST="${CRB_POOL_HOST:-stratum.cereblix.com}"
CRB_POOL_PORT="${CRB_POOL_PORT:-3333}"
export CRB_WALLET CRB_WORKER CRB_THREADS CRB_POOL_HOST CRB_POOL_PORT
exec "$BIN" "$CRB_WALLET" "$CRB_WORKER" "$CRB_THREADS"
