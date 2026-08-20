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

The upstream Android project currently declares a higher Android app `minSdk`, so this repository deliberately removes the Android UI/Service/JNI layer and keeps the native engine + Stratum protocol for Termux.

## Source alignment

The native sources are fetched from the Cereblix Android miner commit:

`9a05f8968be0507798561930c795bce80d4e8d8a`

The Termux network bridge follows the Android app's `StratumClient` contract: `login`, server `job`, `keepalived`, and `submit`. The native engine API mirrors the APK's `nm_engine` interface.

## Requirements

- Android 7.0 / API 24 or newer
- Termux
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

The installer downloads the matching native sources, compiles them with Termux Clang for the phone's ABI, and creates:

```text
~/.local/share/cereblix-termux/bin/cereblix-termux
~/.local/share/cereblix-termux/start.sh
~/.local/share/cereblix-termux/config
```

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

## Validation

The program runs the native engine self-test before mining. A successful run must show the self-test passing, a Stratum connection, a job, and then a live hash counter. A pool-accepted share is the final network validation.

**Do not treat a displayed hashrate alone as proof of correctness.**

## Architecture note

Do not use a `linux-amd64` release binary on an ARM Android phone. This project compiles the native C engine locally for the phone's ARM ABI.

## Status

The repository has been reset from the earlier experimental HTTP/Go approach. The remaining validation step is to compile and run this exact source on the target Android 7/ARM device and confirm a pool-accepted share.

## License / source

The upstream source remains owned/licensed by its original project. This repository contains only the Termux bridge and build orchestration; the installer fetches the upstream native sources at a pinned commit.
