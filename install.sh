#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

APP_NAME="cereblix-termux"
ROOT="$HOME/.local/share/$APP_NAME"
BIN="$ROOT/bin"
CONFIG="$ROOT/config"
SRC="$ROOT/source"
XMRIG_SRC="$ROOT/xmrig-source"

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
pkg install -y git golang clang cmake make curl tar gzip

command -v git >/dev/null 2>&1 || fail "git belum tersedia."
command -v go >/dev/null 2>&1 || fail "Go belum tersedia."
command -v clang >/dev/null 2>&1 || fail "clang belum tersedia."
command -v cmake >/dev/null 2>&1 || fail "cmake belum tersedia."
command -v curl >/dev/null 2>&1 || fail "curl belum tersedia."

GO_VERSION="$(go version 2>/dev/null || true)"
log INFO "Go          : ${GO_VERSION:-unknown}"

if [ -d "$SRC/.git" ]; then
  log INFO "Updating Cereblix source..."
  git -C "$SRC" fetch --depth=1 origin tag xmrig
  git -C "$SRC" checkout -q -f tags/xmrig
else
  log INFO "Cloning Cereblix source..."
  rm -rf "$SRC"
  git clone --depth=1 --branch xmrig https://github.com/CereblixCRB/cereblix.git "$SRC"
fi

HTTP_OUT="$BIN/cereblix-miner"
cd "$SRC"
log INFO "Building Android ARM HTTP miner fallback ($GOARCH)..."
CGO_ENABLED=0 GOOS=android GOARCH="$GOARCH" GOTOOLCHAIN=local \
  go build -trimpath -ldflags='-s -w' -o "$HTTP_OUT" ./cmd/cereblix-miner
chmod 700 "$HTTP_OUT"

STRATUM_OUT="$BIN/cereblix-stratum-miner"
TARBALL="$ROOT/xmrig-cereblix-src.tar.gz"
rm -f "$TARBALL"
rm -rf "$XMRIG_SRC"
mkdir -p "$XMRIG_SRC"

log INFO "Downloading official Cereblix XMRig source..."
if curl -fL --retry 3 --connect-timeout 15 \
    -o "$TARBALL" \
    https://cereblix.com/xmrig-cereblix-src.tar.gz; then
  if tar -xzf "$TARBALL" -C "$XMRIG_SRC"; then
    XROOT="$(find "$XMRIG_SRC" -maxdepth 3 -name CMakeLists.txt -print -quit | sed 's#/CMakeLists.txt$##')"
    if [ -n "$XROOT" ] && [ -f "$XROOT/CMakeLists.txt" ]; then
      BUILD="$XROOT/.termux-build"
      rm -rf "$BUILD"
      log INFO "Building official Cereblix XMRig for Termux/Android ARM..."
      export CC=clang
      export CXX=clang++
      if cmake -S "$XROOT" -B "$BUILD" \
          -DCMAKE_BUILD_TYPE=Release \
          -DCMAKE_C_COMPILER=clang \
          -DCMAKE_CXX_COMPILER=clang++ \
          -DWITH_HWLOC=OFF \
          -DWITH_OPENCL=OFF \
          -DWITH_CUDA=OFF \
          -DWITH_TLS=OFF \
          -DWITH_HTTP=OFF \
          -DWITH_MSR=OFF \
          -DWITH_DMI=OFF \
          -DWITH_BENCHMARK=OFF; then
        if cmake --build "$BUILD" --parallel "$(nproc 2>/dev/null || echo 2)"; then
          if [ -x "$BUILD/xmrig" ]; then
            cp "$BUILD/xmrig" "$STRATUM_OUT"
            chmod 700 "$STRATUM_OUT"
            log OK "Stratum ARM miner built successfully."
          else
            warn "Build selesai tetapi binary xmrig tidak ditemukan. HTTP fallback tetap tersedia."
          fi
        else
          warn "XMRig build gagal pada perangkat ini. HTTP fallback tetap tersedia."
        fi
      else
        warn "XMRig CMake configuration gagal. HTTP fallback tetap tersedia."
      fi
    else
      warn "CMakeLists.txt tidak ditemukan dalam source XMRig. HTTP fallback tetap tersedia."
    fi
  else
    warn "Source archive tidak dapat diekstrak. HTTP fallback tetap tersedia."
  fi
else
  warn "Source XMRig tidak dapat diunduh. HTTP fallback tetap tersedia."
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
  log WARN "Stratum ARM miner was not built; HTTP fallback is ready."
fi
log INFO "Run: $ROOT/start.sh"
