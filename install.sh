#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

APP_NAME="cereblix-termux"
ROOT="$HOME/.local/share/$APP_NAME"
BIN="$ROOT/bin"
CONFIG="$ROOT/config"

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
  aarch64|arm64) GOARCH="arm64"; ARM_TARGET="8" ;;
  armv7l|armv8l|arm) GOARCH="arm"; ARM_TARGET="7" ;;
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
pkg install -y git golang clang cmake make libuv

command -v git >/dev/null 2>&1 || fail "git belum tersedia."
command -v go >/dev/null 2>&1 || fail "Go belum tersedia."
command -v clang >/dev/null 2>&1 || fail "clang belum tersedia."
command -v cmake >/dev/null 2>&1 || fail "cmake belum tersedia."

GO_VERSION="$(go version 2>/dev/null || true)"
log INFO "Go          : ${GO_VERSION:-unknown}"

SRC="$ROOT/source"
if [ -d "$SRC/.git" ]; then
  log INFO "Updating upstream Cereblix xmrig source..."
  git -C "$SRC" fetch --depth=1 origin tag xmrig
  git -C "$SRC" checkout -q -f tags/xmrig
else
  log INFO "Cloning upstream Cereblix xmrig source..."
  rm -rf "$SRC"
  git clone --depth=1 --branch xmrig https://github.com/CereblixCRB/cereblix.git "$SRC"
fi

cd "$SRC"

# Keep the working Android-native HTTP miner as a fallback.
HTTP_OUT="$BIN/cereblix-miner"
log INFO "Building Android ARM miner fallback ($GOARCH)..."
CGO_ENABLED=0 GOOS=android GOARCH="$GOARCH" GOTOOLCHAIN=local \
  go build -trimpath -ldflags='-s -w' -o "$HTTP_OUT" ./cmd/cereblix-miner
chmod 700 "$HTTP_OUT"

# Build the Cereblix XMRig fork for Stratum. Termux's clang targets Android,
# and the fork supports ARMv8. TLS/OpenCL/CUDA/HWLOC are disabled to keep the
# Android build small and avoid desktop-only dependencies.
STRATUM_OUT="$BIN/cereblix-stratum-miner"
BUILD="$SRC/.termux-build"
rm -rf "$BUILD"
mkdir -p "$BUILD"
log INFO "Building ARM$ARM_TARGET Stratum miner..."
if cmake -S "$SRC" -B "$BUILD" \
    -DCMAKE_BUILD_TYPE=Release \
    -DARM_TARGET="$ARM_TARGET" \
    -DWITH_HWLOC=OFF \
    -DWITH_OPENCL=OFF \
    -DWITH_CUDA=OFF \
    -DWITH_TLS=OFF \
    -DWITH_HTTP=OFF \
    -DWITH_MSR=OFF \
    -DWITH_DMI=OFF \
    -DWITH_ASM=OFF \
    -DWITH_SSE4_1=OFF \
    -DWITH_AVX2=OFF; then
  if cmake --build "$BUILD" --parallel "$(nproc 2>/dev/null || echo 2)"; then
    if [ -x "$BUILD/xmrig" ]; then
      cp "$BUILD/xmrig" "$STRATUM_OUT"
      chmod 700 "$STRATUM_OUT"
      log OK "ARM Stratum miner built successfully."
    else
      warn "CMake selesai tetapi binary xmrig tidak ditemukan; HTTP miner tetap tersedia."
    fi
  else
    warn "Stratum build gagal pada perangkat ini; HTTP miner tetap tersedia."
  fi
else
  warn "CMake konfigurasi Stratum gagal; HTTP miner tetap tersedia."
fi

if [ ! -f "$CONFIG/miner.env" ]; then
  cat > "$CONFIG/miner.env" <<'EOF'
# Cereblix Termux configuration
# Keep this file private if it contains a wallet address.
CRB_ADDR=""
STRATUM_NODE="stratum.cereblix.com:3333"
NODE="https://cereblix.com/pool/api"
THREADS=""
EOF
  chmod 600 "$CONFIG/miner.env"
fi

cat > "$ROOT/start.sh" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT="$HOME/.local/share/cereblix-termux"
STRATUM_BIN="$ROOT/bin/cereblix-stratum-miner"
HTTP_BIN="$ROOT/bin/cereblix-miner"
CFG="$ROOT/config/miner.env"
[ -f "$CFG" ] && . "$CFG"
if [ -z "${CRB_ADDR:-}" ]; then
  printf 'CRB wallet address (crb1...): '
  read -r CRB_ADDR
fi
[ -n "$CRB_ADDR" ] || { echo 'Wallet address wajib diisi.'; exit 1; }
if [ -z "${THREADS:-}" ]; then THREADS="$(nproc 2>/dev/null || echo 1)"; fi

if [ -x "$STRATUM_BIN" ]; then
  NODE="${STRATUM_NODE:-stratum.cereblix.com:3333}"
  printf '\nStarting Cereblix Stratum miner\nPool    : %s\nThreads : %s\n\n' "$NODE" "$THREADS"
  exec "$STRATUM_BIN" -a nm/1 -o "$NODE" -u "$CRB_ADDR" -p x -t "$THREADS" -k
fi

[ -x "$HTTP_BIN" ] || { echo 'Miner belum terpasang. Jalankan install.sh lagi.'; exit 1; }
NODE="${NODE:-https://cereblix.com/pool/api}"
printf '\nStarting Cereblix HTTP miner (fallback)\nNode    : %s\nThreads : %s\n\n' "$NODE" "$THREADS"
exec "$HTTP_BIN" -addr "$CRB_ADDR" -node "$NODE" -threads "$THREADS"
EOF
chmod 700 "$ROOT/start.sh"

log OK "Installation complete."
if [ -x "$STRATUM_OUT" ]; then
  log OK "Stratum ARM miner is ready."
else
  log WARN "Using HTTP fallback because Stratum ARM build was not produced."
fi
log INFO "Run: $ROOT/start.sh"
