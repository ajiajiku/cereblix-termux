#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

APP_NAME="cereblix-termux"
ROOT="$HOME/.local/share/$APP_NAME"
BIN="$ROOT/bin"
CONFIG="$ROOT/config"

log() { printf '[%s] %s\n' "$1" "$2"; }
fail() { log ERROR "$1"; exit 1; }

command -v getprop >/dev/null 2>&1 || fail "getprop tidak ditemukan. Jalankan script ini di Android/Termux."
SDK="$(getprop ro.build.version.sdk 2>/dev/null || true)"
ABI="$(getprop ro.product.cpu.abi 2>/dev/null || true)"
ABI_LIST="$(getprop ro.product.cpu.abilist 2>/dev/null || true)"
[ -n "$SDK" ] || fail "Tidak dapat membaca Android API level."
[ "$SDK" -ge 24 ] || fail "Android API $SDK terdeteksi. Minimum yang didukung adalah API 24 (Android 7.0)."
case "$ABI" in
  arm64-v8a|armeabi-v7a|armeabi) : ;;
  *) fail "ABI utama '$ABI' belum didukung. ABI list: $ABI_LIST" ;;
esac
[ -n "${PREFIX:-}" ] && [ -d "$PREFIX" ] || fail "Environment Termux tidak terdeteksi."

log INFO "Android API : $SDK"
log INFO "ABI utama   : $ABI"
log INFO "ABI list    : ${ABI_LIST:-unknown}"
log INFO "Termux      : $PREFIX"

mkdir -p "$BIN" "$CONFIG"

if ! command -v git >/dev/null 2>&1 || ! command -v go >/dev/null 2>&1; then
  log INFO "Installing build dependencies (git + golang)..."
  pkg update -y
  pkg install -y git golang
fi
command -v git >/dev/null 2>&1 || fail "git belum tersedia setelah instalasi."
command -v go >/dev/null 2>&1 || fail "Go belum tersedia setelah instalasi."

GO_VERSION="$(go version 2>/dev/null || true)"
log INFO "Go          : ${GO_VERSION:-unknown}"
GO_MAJOR="$(printf '%s\n' "$GO_VERSION" | sed -n 's/.*go\([0-9][0-9]*\)\.\([0-9][0-9]*\).*/\1/p')"
GO_MINOR="$(printf '%s\n' "$GO_VERSION" | sed -n 's/.*go\([0-9][0-9]*\)\.\([0-9][0-9]*\).*/\2/p')"
if [ -z "$GO_MAJOR" ] || [ "$GO_MAJOR" -lt 1 ] || { [ "$GO_MAJOR" -eq 1 ] && [ "$GO_MINOR" -lt 21 ]; }; then
  fail "Go 1.21+ diperlukan oleh source upstream. Ditemukan: $GO_VERSION"
fi

SRC="$ROOT/source"
if [ -d "$SRC/.git" ]; then
  log INFO "Updating upstream source..."
  git -C "$SRC" fetch --depth=1 origin xmrig
  git -C "$SRC" checkout -q xmrig
  git -C "$SRC" reset --hard -q origin/xmrig
else
  log INFO "Cloning upstream Cereblix source..."
  rm -rf "$SRC"
  git clone --depth=1 --branch xmrig https://github.com/CereblixCRB/cereblix.git "$SRC"
fi

cd "$SRC"
OUT="$BIN/cereblix-miner"
log INFO "Building upstream cereblix-miner for the current Termux architecture..."
CGO_ENABLED=0 go build -trimpath -ldflags='-s -w' -o "$OUT" ./cmd/cereblix-miner
chmod 700 "$OUT"

# Do not overwrite an existing wallet/configuration on reinstall.
if [ ! -f "$CONFIG/miner.env" ]; then
  cat > "$CONFIG/miner.env" <<'EOF'
# Cereblix Termux configuration
# Keep this file private if it contains a wallet address.
CRB_ADDR=""
NODE="https://cereblix.com/pool/api"
THREADS=""
EOF
fi

cat > "$ROOT/start.sh" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT="$HOME/.local/share/cereblix-termux"
BIN="$ROOT/bin/cereblix-miner"
CFG="$ROOT/config/miner.env"
[ -x "$BIN" ] || { echo "Miner belum terpasang. Jalankan install.sh lagi."; exit 1; }
[ -f "$CFG" ] && . "$CFG"
if [ -z "${CRB_ADDR:-}" ]; then
  printf 'CRB wallet address (crb1...): '
  read -r CRB_ADDR
fi
[ -n "$CRB_ADDR" ] || { echo 'Wallet address wajib diisi.'; exit 1; }
if [ -z "${THREADS:-}" ]; then THREADS="$(nproc 2>/dev/null || echo 1)"; fi
NODE="${NODE:-https://cereblix.com/pool/api}"
printf '\nStarting Cereblix miner\nNode    : %s\nThreads : %s\n\n' "$NODE" "$THREADS"
exec "$BIN" -addr "$CRB_ADDR" -node "$NODE" -threads "$THREADS"
EOF
chmod 700 "$ROOT/start.sh"

log OK "Installation complete."
log INFO "Run: $ROOT/start.sh"
