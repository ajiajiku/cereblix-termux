# cereblix-termux

Termux tooling for building and running the open-source Cereblix CPU miner on Android devices.

## Status

**ARM64 / aarch64 has been tested on a real Termux device.** The project builds an Android-native HTTP miner and now also attempts to build the Cereblix XMRig fork for the pool's Stratum endpoint.

The launcher prefers the ARM Stratum miner when the build succeeds and automatically falls back to the Android HTTP miner if Stratum cannot be built on the device.

## What this project does

- Detects Android API level and CPU architecture.
- Requires Android API 24 or newer (Android 7.0+).
- Installs Termux build dependencies.
- Clones the upstream Cereblix `xmrig` branch.
- Builds an Android ARM HTTP miner.
- Attempts an ARM Stratum build using CMake/Clang.
- Creates a persistent private configuration file.
- Provides a `start.sh` launcher that prefers Stratum and falls back to HTTP.

This repository does **not** redistribute the original Cereblix APK or `libnmminer.so`.

## Requirements

- Android 7.0 / API 24 or newer.
- Termux with a working package repository.
- ARM64 (`arm64-v8a`) is the primary target.
- ARMv7 (`armeabi-v7a`) is accepted by the architecture check but is not fully validated.
- Go 1.21 or newer.
- For the Stratum build: clang, cmake, make and libuv.

## Install

```sh
git clone https://github.com/ajiajiku/cereblix-termux.git
cd cereblix-termux
chmod +x install.sh
./install.sh
```

After installation:

```sh
~/.local/share/cereblix-termux/start.sh
```

The launcher asks for the CRB wallet address if it has not been configured. If the ARM Stratum binary was built successfully, it uses `stratum.cereblix.com:3333`; otherwise it uses the HTTP pool endpoint.

## Configuration

The private configuration is stored at:

```text
~/.local/share/cereblix-termux/config/miner.env
```

Example:

```sh
CRB_ADDR="crb1..."
STRATUM_NODE="stratum.cereblix.com:3333"
NODE="https://cereblix.com/pool/api"
THREADS="7"
```

`install.sh` will not overwrite an existing `miner.env` during reinstall.

## Important: architecture

Do not download and run the upstream `linux-amd64` binary on an Android ARM phone. The installer builds native Android/ARM binaries locally.

Verify the device architecture with:

```sh
uname -m
```

An ARM64 device should report:

```text
aarch64
```

## Troubleshooting

Check which miners were built:

```sh
ls -l ~/.local/share/cereblix-termux/bin/
```

If `cereblix-stratum-miner` exists and is executable, the launcher will prefer it.

To rebuild:

```sh
cd ~/cereblix-termux
git pull
./install.sh
```

## Safety

Only use this software on devices you own or are authorized to operate. CPU mining can cause substantial heat, battery drain and performance reduction.

Never commit wallet seed phrases, passwords, private keys or API tokens.
