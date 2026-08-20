#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

APP_NAME="cereblix-termux"
ROOT="$HOME/.local/share/$APP_NAME"
BIN="$ROOT/bin"
CONFIG="$ROOT/config"
SRC="$ROOT/source"

log() { printf '[%s] %s\n' "$1" "$2"; }
fail() { log ERROR "$1"; exit 1; }
warn() { log WARN "$1"; }

command -v getprop >/dev/null 2>&1 || fail "getprop tidak ditemukan. Jalankan script ini di Android/Termux."
command -v uname >/dev/null 2>&1 || fail "uname tidak ditemukan."
SDK="$(getprop ro.build.version.sdk 2>/dev/null || true)"
ABI="$(getprop ro.product.cpu.abi 2>/dev/null || true)"
ABI_LIST="$(getprop ro.product.cpu.abilist 2>/dev/null || true)"
MACHINE="$(uname -m 2>/dev/null || true)"
[ -n "$SDK" ] || fail "Tidak dapat membaca Android API level."
[ "$SDK" -ge 24 ] || fail "Android API $SDK terdeteksi. Minimum yang didukung adalah API 24 (Android 7.0)."

case "$ABI" in
  arm64-v8a|armeabi-v7a|armeabi) : ;;
  *) fail "ABI utama '$ABI' belum didukung. ABI list: ${ABI_LIST:-unknown}" ;;
esac

case "$MACHINE" in
  aarch64|arm64) GOARCH="arm64" ;;
  armv7l|armv8l|arm) GOARCH="arm" ;;
  *) fail "Arsitektur Termux '$MACHINE' belum didukung. Gunakan ARM64 atau ARMv7." ;;
esac

[ -n "${PREFIX:-}" ] && [ -d "$PREFIX" ] || fail "Environment Termux tidak terdeteksi."

log INFO "Android API : $SDK"
log INFO "ABI utama   : $ABI"
log INFO "ABI list    : ${ABI_LIST:-unknown}"
log INFO "CPU         : $MACHINE"
log INFO "Go ARCH     : $GOARCH"
log INFO "Termux      : $PREFIX"

mkdir -p "$BIN" "$CONFIG"

log INFO "Installing build dependencies..."
pkg update -y
pkg install -y git golang clang curl

command -v git >/dev/null 2>&1 || fail "git belum tersedia."
command -v go >/dev/null 2>&1 || fail "Go belum tersedia."
command -v clang >/dev/null 2>&1 || fail "clang belum tersedia."
command -v curl >/dev/null 2>&1 || fail "curl belum tersedia."

GO_VERSION="$(go version 2>/dev/null || true)"
log INFO "Go          : ${GO_VERSION:-unknown}"

# The official Cereblix XMRig builds are Stratum/x86-oriented. The ARM64
# Android path here deliberately uses the upstream Go HTTP/getwork miner,
# which is the supported legacy protocol for ARM phones.
if [ -d "$SRC/.git" ]; then
  log INFO "Updating Cereblix source..."
  git -C "$SRC" fetch --depth=1 origin xmrig
  git -C "$SRC" checkout -q -f FETCH_HEAD
else
  log INFO "Cloning Cereblix source..."
  rm -rf "$SRC"
  git clone --depth=1 --branch xmrig https://github.com/CereblixCRB/cereblix.git "$SRC"
fi

HTTP_OUT="$BIN/cereblix-miner"
cd "$SRC"
log INFO "Building Cereblix HTTP miner for Android/$GOARCH..."
CGO_ENABLED=0 GOOS=android GOARCH="$GOARCH" GOTOOLCHAIN=local \
  go build -trimpath -ldflags='-s -w' -o "$HTTP_OUT" ./cmd/cereblix-miner
chmod 700 "$HTTP_OUT"

[ -x "$HTTP_OUT" ] || fail "Binary cereblix-miner gagal dibuat."
log OK "ARM HTTP miner built successfully."

if [ ! -f "$CONFIG/miner.env" ]; then
  cat > "$CONFIG/miner.env" <<'EOF'
# Cereblix Termux configuration
CRB_ADDR=""
NODE="https://cereblix.com/pool/api"
THREADS=""
EOF
  chmod 600 "$CONFIG/miner.env"
fi

cat > "$ROOT/start.sh" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT="$HOME/.local/share/cereblix-termux"
BIN="$ROOT/bin/cereblix-miner"
CFG="$ROOT/config/miner.env"
[ -f "$CFG" ] && . "$CFG"

if [ -z "${CRB_ADDR:-}" ]; then
  printf 'CRB wallet address (crb1...): '
  read -r CRB_ADDR
fi
[ -n "$CRB_ADDR" ] || { echo 'Wallet address wajib diisi.'; exit 1; }

NODE="${NODE:-https://cereblix.com/pool/api}"
THREADS="${THREADS:-$(nproc 2>/dev/null || echo 1)}"

printf '\nTesting Cereblix pool connection...\n'
TEST_URL="$NODE/getwork?addr=$CRB_ADDR"
HTTP_CODE="$(curl -L -sS --max-time 15 -o /dev/null -w '%{http_code}' "$TEST_URL" || true)"
printf 'Pool HTTP status : %s\n' "${HTTP_CODE:-unknown}"
if [ "${HTTP_CODE:-0}" != "200" ]; then
  echo 'Pool belum memberikan work. Periksa koneksi atau jalankan lagi nanti.'
  exit 1
fi

printf '\nStarting Cereblix ARM HTTP miner\nNode    : %s\nThreads : %s\nAddress : %s\n\n' "$NODE" "$THREADS" "$CRB_ADDR"
exec "$BIN" -addr "$CRB_ADDR" -node "$NODE" -threads "$THREADS"
EOF
chmod 700 "$ROOT/start.sh"

log OK "Installation complete."
log INFO "Run: $ROOT/start.sh"
