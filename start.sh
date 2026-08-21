#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT="$HOME/.local/share/cereblix-termux"
BIN="$ROOT/bin/cereblix-termux"
CFG="$ROOT/config"
[ -x "$BIN" ] || { echo "Belum terpasang. Jalankan ./install.sh terlebih dahulu."; exit 1; }
[ -f "$CFG" ] && . "$CFG"

# Ask for the wallet only when no wallet has been saved yet.
if [ -z "${CRB_WALLET:-}" ]; then
  printf 'CRB wallet address (crb1...): '
  read -r CRB_WALLET
  if [ -n "$CRB_WALLET" ]; then
    case "$CRB_WALLET" in
      crb1[0-9a-z]*) ;;
      *) echo 'Format wallet tidak valid (harus diawali crb1).'; exit 1 ;;
    esac
    # Save the wallet so the next run does not ask again.
    sed -i "s|^CRB_WALLET=.*$|CRB_WALLET=\"$CRB_WALLET\"|" "$CFG"
  fi
fi
[ -n "$CRB_WALLET" ] || { echo 'Wallet wajib diisi.'; exit 1; }
CRB_WORKER="${CRB_WORKER:-nmminer-termux}"
CRB_THREADS="${CRB_THREADS:-0}"
CRB_POOL_HOST="${CRB_POOL_HOST:-stratum.cereblix.com}"
CRB_POOL_PORT="${CRB_POOL_PORT:-3333}"
export CRB_WALLET CRB_WORKER CRB_THREADS CRB_POOL_HOST CRB_POOL_PORT

# Keep the miner as a child so Ctrl+C/Ctrl+TERM is explicitly forwarded.
"$BIN" "$CRB_WALLET" "$CRB_WORKER" "$CRB_THREADS" &
PID=$!
cleanup() {
  kill -TERM "$PID" 2>/dev/null || true
  wait "$PID" 2>/dev/null || true
  exit 130
}
trap cleanup INT TERM
wait "$PID"
STATUS=$?
trap - INT TERM
exit "$STATUS"
