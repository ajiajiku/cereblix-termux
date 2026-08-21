#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

APP_NAME="cereblix-termux"
ROOT="$HOME/.local/share/$APP_NAME"
BIN="$ROOT/bin"
SRC="$ROOT/source"
REF="9a05f8968be0507798561930c795bce80d4e8d8a"
BASE="https://raw.githubusercontent.com/CereblixCRB/cereblix-miner/$REF/android/app/src/main/cpp"

fail(){ printf '[ERROR] %s\n' "$1" >&2; exit 1; }
log(){ printf '[%s] %s\n' "$1" "$2"; }

command -v getprop >/dev/null || fail "Jalankan script ini di Termux Android."
SDK="$(getprop ro.build.version.sdk 2>/dev/null || true)"
ABI="$(getprop ro.product.cpu.abi 2>/dev/null || true)"
MACHINE="$(uname -m 2>/dev/null || true)"
[ -n "$SDK" ] || fail "Android API tidak terdeteksi."
[ "$SDK" -ge 24 ] || fail "Android $SDK terdeteksi. Minimum API 24 (Android 7.0)."
case "$ABI" in arm64-v8a|armeabi-v7a) ;; *) fail "ABI $ABI belum didukung. Gunakan ARM64 atau ARMv7.";; esac
[ -n "${PREFIX:-}" ] && [ -d "$PREFIX" ] || fail "Termux tidak terdeteksi."

log INFO "Android API : $SDK"
log INFO "ABI         : $ABI"
log INFO "Machine     : $MACHINE"
log INFO "Source ref  : $REF"

# Stop legacy miner processes from earlier repository versions before rebuilding.
pkill -TERM -f 'cereblix-miner\.old' 2>/dev/null || true
pkill -TERM -f '/cereblix-miner([[:space:]]|$)' 2>/dev/null || true
sleep 1

pkg update -y
pkg install -y clang curl make
mkdir -p "$SRC" "$BIN"

for f in CMakeLists.txt nm_aes.h nm_engine.c nm_engine.h nm_fast.c nm_fast.h nm_jni.c nm_neuromorph.c nm_neuromorph.h nm_params.c nm_params.h nm_sha256.h; do
  curl -fsSL "$BASE/$f" -o "$SRC/$f"
done

curl -fsSL "https://raw.githubusercontent.com/ajiajiku/cereblix-termux/main/src/termux_main.c" -o "$SRC/termux_main.c"

cd "$SRC"
CFLAGS="-O3 -ffp-contract=off -fno-vectorize -fno-slp-vectorize -fno-exceptions -fomit-frame-pointer -funroll-loops -pthread"
if [ "$ABI" = "arm64-v8a" ]; then
  CFLAGS="$CFLAGS -march=armv8-a+crypto+simd"
elif [ "$ABI" = "armeabi-v7a" ]; then
  CFLAGS="$CFLAGS -mfpu=neon"
fi

log INFO "Compiling APK-derived NeuroMorph engine..."
clang $CFLAGS -o "$BIN/cereblix-termux" termux_main.c nm_engine.c nm_fast.c nm_neuromorph.c nm_params.c -lm -pthread
chmod 700 "$BIN/cereblix-termux"

# Preserve the user's existing configuration across reinstalls/upgrades.
if [ -f "$ROOT/config" ]; then
  cp "$ROOT/config" "$ROOT/config.bak"
fi
if [ ! -f "$ROOT/config" ]; then
  cat > "$ROOT/config" <<'EOF'
# Wallet, worker and threads can be changed here.
CRB_WALLET=""
CRB_WORKER="nmminer-termux"
CRB_THREADS=""
CRB_POOL_HOST="stratum.cereblix.com"
CRB_POOL_PORT="3333"
EOF
fi
chmod 600 "$ROOT/config"

# On a fresh installation, ask for the wallet once and save it.
. "$ROOT/config"
if [ -z "${CRB_WALLET:-}" ]; then
  printf 'CRB wallet address (crb1...): '
  read -r CRB_WALLET
  case "$CRB_WALLET" in
    crb1[0-9a-z]*) ;;
    *) fail "Format wallet tidak valid (harus diawali crb1)." ;;
  esac
  sed -i "s|^CRB_WALLET=.*$|CRB_WALLET=\"$CRB_WALLET\"|" "$ROOT/config"
fi

cat > "$ROOT/start.sh" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT="$HOME/.local/share/cereblix-termux"
BIN="$ROOT/bin/cereblix-termux"
CFG="$ROOT/config"
[ -x "$BIN" ] || { echo "Belum terpasang. Jalankan ./install.sh terlebih dahulu."; exit 1; }
[ -f "$CFG" ] && . "$CFG"

if [ "${1:-}" = "--setup" ]; then
  printf 'CRB wallet address (crb1...): '
  read -r CRB_WALLET
  case "$CRB_WALLET" in
    crb1[0-9a-z]*) ;;
    *) echo 'Format wallet tidak valid (harus diawali crb1).'; exit 1 ;;
  esac
  printf 'Worker name [%s]: ' "${CRB_WORKER:-nmminer-termux}"
  read -r new_worker
  CRB_WORKER="${new_worker:-${CRB_WORKER:-nmminer-termux}}"
  printf 'Threads [0 = otomatis, %s]: ' "${CRB_THREADS:-0}"
  read -r new_threads
  CRB_THREADS="${new_threads:-${CRB_THREADS:-0}}"
  {
    printf '# Wallet, worker and threads can be changed here.\n'
    printf 'CRB_WALLET="%s"\n' "$CRB_WALLET"
    printf 'CRB_WORKER="%s"\n' "$CRB_WORKER"
    printf 'CRB_THREADS="%s"\n' "$CRB_THREADS"
    printf 'CRB_POOL_HOST="%s"\n' "${CRB_POOL_HOST:-stratum.cereblix.com}"
    printf 'CRB_POOL_PORT="%s"\n' "${CRB_POOL_PORT:-3333}"
  } > "$CFG"
  chmod 600 "$CFG"
  echo "Konfigurasi tersimpan."
  exit 0
fi

if [ -z "${CRB_WALLET:-}" ]; then
  printf 'CRB wallet address (crb1...): '
  read -r CRB_WALLET
  case "$CRB_WALLET" in
    crb1[0-9a-z]*) ;;
    *) echo 'Format wallet tidak valid (harus diawali crb1).'; exit 1 ;;
  esac
  sed -i "s|^CRB_WALLET=.*$|CRB_WALLET=\"$CRB_WALLET\"|" "$CFG"
fi
[ -n "$CRB_WALLET" ] || { echo 'Wallet wajib diisi.'; exit 1; }
CRB_WORKER="${CRB_WORKER:-nmminer-termux}"
CRB_THREADS="${CRB_THREADS:-0}"
CRB_POOL_HOST="${CRB_POOL_HOST:-stratum.cereblix.com}"
CRB_POOL_PORT="${CRB_POOL_PORT:-3333}"
export CRB_WALLET CRB_WORKER CRB_THREADS CRB_POOL_HOST CRB_POOL_PORT

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
EOF
chmod 700 "$ROOT/start.sh"

log OK "Installed APK-v2.0-derived Termux miner."
log INFO "Start with: $ROOT/start.sh"
log INFO "Change wallet/worker: $ROOT/start.sh --setup"
log INFO "Worker name: edit $ROOT/config"
log INFO "Your config is preserved on reinstall."
