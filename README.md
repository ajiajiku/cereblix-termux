# Cereblix Termux — APK v2.0-derived

This project ports the native mining engine and Stratum contract used by the Cereblix Android miner v2.0 into a standalone Termux program.

## Direct APK analysis

The supplied `cereblix-miner-universal-v2.0.apk` was inspected directly. The extracted evidence is stored under `analysis/`.

Key findings:

- Package: `com.cereblix.miner`
- Version: `2.0` / version code `2`
- Compile/target SDK: `34`
- **APK minimum SDK: `26` (Android 8.0)**
- Native payload: `libnmminer.so` for ARM64, ARMv7 and x86_64
- Native libraries report an Android API 26 linker target
- JNI class: `com.cereblix.miner.NativeMiner`
- Kotlin components include `MiningService` and `StratumClient`
- Stratum methods observed: `login`, `submit`, `keepalived`
- Agent observed: `nmminer-android/2.0`

**Important Android 7 finding:** the original APK and its bundled native binaries cannot simply be copied to Android 7/API 24. The Termux version therefore needs a compatible local native rebuild rather than reusing the APK's API-26 binary.

See:

- `analysis/APK_ANALYSIS.md`
- `analysis/APK_INVENTORY.txt`
- `analysis/JNI_SYMBOLS.txt`

## Goal

Run the same core mining path on Android 7+ / API 24+:

- compatible native mining engine
- Stratum login/job/submit flow used by the Android client
- custom wallet address
- custom worker/rig name
- configurable CPU threads
- ARM64 and ARMv7 builds
- clean `Ctrl+C` shutdown

## Install

```sh
git clone https://github.com/ajiajiku/cereblix-termux.git
cd cereblix-termux
chmod +x install.sh
./install.sh
```

The installer builds the native program locally for the phone's ARM ABI and creates:

```text
~/.local/share/cereblix-termux/bin/cereblix-termux
~/.local/share/cereblix-termux/start.sh
~/.local/share/cereblix-termux/config
```

## Configure

```sh
nano ~/.local/share/cereblix-termux/config
```

Example:

```sh
CRB_WALLET="crb1..."
CRB_WORKER="HP1"
CRB_THREADS="4"
CRB_POOL_HOST="stratum.cereblix.com"
CRB_POOL_PORT="3333"
```

## Start

```sh
~/.local/share/cereblix-termux/start.sh
```

Press **Ctrl+C** to stop.

## Compatibility

The target for this repository is Android 7/API 24+. The supplied APK itself is Android 8/API 26+, so APK binaries are treated as reference material only. The native engine must be rebuilt against an API-24-compatible Android toolchain for a genuine Android 7 build.

## Source / license

The upstream Android application and native source remain owned/licensed by their original project. This repository contains the Termux bridge, build orchestration, and analysis derived from the supplied APK.
