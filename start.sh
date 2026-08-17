#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="$HOME/.local/share/cereblix-termux"
BIN="$ROOT/bin/cereblix-miner"
CFG="$ROOT/config/miner.env"

[ -x "$BIN" ] || { echo "Miner belum terpasang. Jalankan ./install.sh terlebih dahulu."; exit 1; }
[ -f "$CFG" ] && . "$CFG"

if [ -z "${CRB_ADDR:-}" ]; then
  printf 'CRB wallet address (crb1...): '
  read -r CRB_ADDR
fi

[ -n "$CRB_ADDR" ] || { echo 'Wallet address wajib diisi.'; exit 1; }

if [ -z "${THREADS:-}" ]; then
  THREADS="$(nproc 2>/dev/null || echo 1)"
fi

NODE="${NODE:-https://cereblix.com/pool/api}"

printf '\nStarting Cereblix miner\n'
printf 'Node    : %s\n' "$NODE"
printf 'Threads : %s\n\n' "$THREADS"

exec "$BIN" -addr "$CRB_ADDR" -node "$NODE" -threads "$THREADS"
