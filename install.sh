#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="$HOME/.local/share/cereblix-termux"
BIN="$ROOT/bin"
SRC="$ROOT/upstream"
mkdir -p "$BIN"

command -v getprop >/dev/null 2>&1 || { echo "Jalankan script ini di Termux Android."; exit 1; }
SDK="$(getprop ro.build.version.sdk 2>/dev/null || true)"
ABI="$(getprop ro.product.cpu.abi 2>/dev/null || true)"
MACHINE="$(uname -m 2>/dev/null || true)"
[ "${SDK:-0}" -ge 24 ] || { echo "Android API $SDK terdeteksi. Minimum proyek: API 24 (Android 7.0)."; exit 1; }
case "$ABI:$MACHINE" in
  arm64-v8a:aarch64|arm64-v8a:arm64) CFLAGS="-O3 -march=armv8-a+crypto+simd" ;;
  armeabi-v7a:armv7l|armeabi-v7a:armv8l|armeabi:arm*) CFLAGS="-O3 -mfpu=neon" ;;
  *) echo "Arsitektur tidak didukung: ABI=$ABI CPU=$MACHINE"; exit 1 ;;
esac

printf 'Android API : %s\nABI         : %s\nCPU         : %s\n' "$SDK" "$ABI" "$MACHINE"

echo "Installing build tools..."
pkg update -y
pkg install -y git clang make

if [ ! -d "$SRC/.git" ]; then
  rm -rf "$SRC"
  git clone --depth 1 https://github.com/CereblixCRB/cereblix-miner.git "$SRC"
else
  git -C "$SRC" fetch --depth=1 origin main
  git -C "$SRC" reset --hard FETCH_HEAD
fi

CPP="$SRC/android/app/src/main/cpp"
for f in nm_engine.c nm_engine.h nm_fast.c nm_fast.h nm_neuromorph.c nm_neuromorph.h nm_params.c nm_params.h; do
  [ -f "$CPP/$f" ] || { echo "Missing upstream file: $f"; exit 1; }
done

# The Android engine is pure C. We reuse it directly and replace only the JNI
# layer with the small Termux Stratum frontend in this repository.
clang $CFLAGS -ffp-contract=off -fno-vectorize -fno-slp-vectorize \
  -fno-exceptions -fomit-frame-pointer -funroll-loops -pthread \
  -I"$CPP" \
  "$ROOT/../cereblix-termux/src/cereblix_termux.c" \
  "$CPP/nm_engine.c" "$CPP/nm_fast.c" "$CPP/nm_neuromorph.c" "$CPP/nm_params.c" \
  -o "$BIN/cereblix-termux" -pthread -lm -latomic

chmod 700 "$BIN/cereblix-termux"

if ! "$BIN/cereblix-termux" --help >/dev/null; then
  echo "Binary self-check failed."; exit 1
fi

cat > "$ROOT/start.sh" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT="$HOME/.local/share/cereblix-termux"
BIN="$ROOT/bin/cereblix-termux"
[ -x "$BIN" ] || { echo "Miner belum terpasang. Jalankan install.sh terlebih dahulu."; exit 1; }

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
EOF
chmod 700 "$ROOT/start.sh"

echo
echo "INSTALL OK"
echo "Start with: $ROOT/start.sh"
