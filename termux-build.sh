#!/data/data/com.termux/files/usr/bin/bash
set -e

ROOT="$HOME/cereblix-termux"
SRC="$ROOT/upstream-cereblix-miner"
OUT="$ROOT/bin"
mkdir -p "$ROOT" "$OUT"

if ! command -v clang >/dev/null 2>&1; then
  pkg update -y
  pkg install -y clang git
fi

if [ ! -d "$SRC/.git" ]; then
  rm -rf "$SRC"
  git clone --depth 1 https://github.com/CereblixCRB/cereblix-miner.git "$SRC"
else
  git -C "$SRC" pull --ff-only
fi

ARCH="$(uname -m)"
case "$ARCH" in
  aarch64|arm64)
    CPUFLAGS="-march=armv8-a+crypto"
    ;;
  armv7l|armv8l)
    CPUFLAGS="-march=armv7-a"
    ;;
  x86_64)
    CPUFLAGS="-march=x86-64-v3 -maes -mavx2"
    ;;
  *)
    echo "Unsupported Termux architecture: $ARCH" >&2
    exit 1
    ;;
esac

CFLAGS="-O3 $CPUFLAGS -funroll-loops -fno-tree-vectorize -ffp-contract=off -pthread"

# The upstream Makefile is intentionally x86-oriented. Build the same consensus
# core directly with Termux clang so ARM Android can use the upstream Stratum miner.
clang $CFLAGS \
  -I"$SRC" \
  -o "$OUT/cereblix-miner" \
  "$SRC/nmminer.c" "$SRC/nm_fast.c" "$SRC/nm_params.c" \
  -pthread -lm

chmod 755 "$OUT/cereblix-miner"

"$OUT/cereblix-miner" -h | head -n 8

echo
echo "Build complete: $OUT/cereblix-miner"
echo "This build uses the upstream NeuroMorph core and its native Stratum client."
