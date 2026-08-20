# Cereblix Termux — APK v2.0-derived

This project ports the **native NeuroMorph mining engine and Stratum contract used by the Cereblix Android miner v2.0** into a standalone Termux program. It is not the old HTTP/getwork experiment and it does not use the Linux-amd64 miner updater.

## Goal

Run the same core mining path on Android 7+ / API 24+:

- NeuroMorph native C engine from the Android miner source
- Stratum login/job/submit flow used by `StratumClient.kt`
- Custom wallet address
- Custom worker/rig name
- Configurable CPU threads
- ARM64 and ARMv7 builds
- Clean `Ctrl+C` shutdown

The upstream Android project declares a higher Android app `minSdk`, so this repository deliberately removes the Android UI/Service/JNI layer and keeps the native engine + Stratum protocol for Termux.

## Source alignment

The native sources are fetched from the Cereblix Android miner commit:

`9a05f8968be0507798561930c795bce80d4e8d8a`

The Termux network bridge follows the Android app's `StratumClient` contract: `login`, server `job`, `keepalived`, and `submit`. The native engine API mirrors the APK's `nm_engine` interface.

## Requirements

- Android 7.0 / API 24 or newer
- A Termux build that itself supports the target Android version
- ARM64 (`arm64-v8a`) or ARMv7 (`armeabi-v7a`)
- Working network connection
- Sufficient free RAM; NeuroMorph uses a large dataset/scratch memory footprint

## Install

```sh
git clone https://github.com/ajiajiku/cereblix-termux.git
cd cereblix-termux
chmod +x install.sh
./install.sh
```

The installer downloads the matching native sources, compiles them with Termux Clang for the phone's ARM ABI, and creates:

```text
~/.local/share/cereblix-termux/bin/cereblix-termux
~/.local/share/cereblix-termux/start.sh
~/.local/share/cereblix-termux/config
```

Re-running `./install.sh` rebuilds the native program but **preserves the existing configuration**.

## Configure worker name

Edit:

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

`CRB_WORKER` can be any worker name accepted by the pool. It is sent as the Stratum `rigid` value, matching the Android v2.0 client.

## Start

```sh
~/.local/share/cereblix-termux/start.sh
```

Or provide the values directly:

```sh
~/.local/share/cereblix-termux/bin/cereblix-termux "crb1..." "HP1" 4
```

Press **Ctrl+C** to stop. The launcher forwards the termination signal to the miner and waits for it to exit cleanly.

## Validation

The program runs the native engine self-test before mining. A successful run should show the self-test, a Stratum connection, jobs, a live hash counter, and pool-accepted shares.

The current development test on an **Android 13 / arm64-v8a Termux device** produced repeated pool-accepted shares (19 accepted in the observed run) and then stopped cleanly with `Ctrl+C`; `ps -ef | grep '[c]ereblix'` returned no remaining process.

**Important:** this proves the current build works on the tested Android 13 ARM64 device. It does **not** by itself prove runtime testing on Android 7. The installer enforces API 24+ and the native program is compiled locally for the device ABI, but an actual Android 7 device test is still the final compatibility check.

**Do not treat a displayed hashrate alone as proof of correctness.** A pool-accepted share is the useful network validation.

## Architecture note

Do not use a `linux-amd64` release binary on an ARM Android phone. This project compiles the native C engine locally for the phone's ARM ABI.

The repository no longer depends on the earlier experimental HTTP/Go miner or the old Cereblix Linux-amd64 miner updater. The installer fetches the pinned APK-derived native engine and builds the Termux bridge locally.

## Status

**Functional on the tested Android 13 / ARM64 device.** The tested path has verified native self-test, Stratum jobs, pool-accepted shares, and clean Ctrl+C shutdown. Android 7 remains a compatibility target that should be validated on real API 24 hardware before being called fully verified.

## License / source

The upstream source remains owned/licensed by its original project. This repository contains the Termux bridge and build orchestration; the installer fetches the upstream native sources at a pinned commit.
