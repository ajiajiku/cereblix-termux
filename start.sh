#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT="$HOME/.local/share/cereblix-termux"
BIN="$ROOT/bin/cereblix-termux"
[ -x "$BIN" ] || { echo "Miner belum terpasang. Jalankan ./install.sh terlebih dahulu."; exit 1; }
printf 'CRB wallet address (crb1...): '
read -r WALLET
[ -n "$WALLET" ] || { echo 'Wallet wajib diisi.'; exit 1; }
printf 'Worker name (contoh: HP1): '
read -r WORKER
WORKER="${WORKER:-HP1}"
printf 'Threads (kosong = otomatis): '
read -r THREADS
ARGS=(-o stratum+tcp://stratum.cereblix.com:3333 -u "$WALLET" -w "$WORKER")
[ -n "$THREADS" ] && ARGS+=(-t "$THREADS")
exec "$BIN" "${ARGS[@]}"
