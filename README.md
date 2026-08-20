# cereblix-termux

Termux tooling for building and running the open-source Cereblix CPU miner on Android devices.

## Status

**ARM64 / aarch64 has been successfully tested on a real Termux device.** The miner connected to `https://cereblix.com/pool/api` and received an accepted share during testing.

The project is still experimental. ARMv7/32-bit validation and release binaries are not yet complete.

## What this project does

- Detects Android API level and CPU architecture.
- Requires Android API 24 or newer (Android 7.0+).
- Installs the required Termux build dependencies.
- Clones the upstream Cereblix `xmrig` branch.
- Builds `cereblix-miner` locally for the device architecture.
- Creates a persistent private configuration file.
- Provides a simple `start.sh` launcher.

This repository does **not** redistribute the original Cereblix APK or `libnmminer.so`.

Upstream source:

- https://github.com/CereblixCRB/cereblix

## Requirements

- Android 7.0 / API 24 or newer.
- Termux with a working package repository.
- ARM64 (`arm64-v8a`) is the primary tested target.
- ARMv7 (`armeabi-v7a`) is accepted by the installer, but is not yet fully validated.
- Go 1.21 or newer.

## Install

```sh
git clone https://github.com/ajiajiku/cereblix-termux.git
cd cereblix-termux
chmod +x install.sh
./install.sh
```

The installer checks Android API, ABI and the Termux CPU architecture. It then builds the miner with `GOOS=android` and the detected `GOARCH`, rather than using an incompatible desktop binary.

After installation:

```sh
~/.local/share/cereblix-termux/start.sh
```

The launcher asks for the CRB wallet address if one has not been configured, then starts the miner using the detected CPU thread count.

## Configuration

The private configuration is stored at:

```text
~/.local/share/cereblix-termux/config/miner.env
```

Example:

```sh
CRB_ADDR="crb1..."
NODE="https://cereblix.com/pool/api"
THREADS="7"
```

`install.sh` will not overwrite an existing `miner.env` during reinstall.

## Important: architecture

Do not download and run the upstream `linux-amd64` binary on an Android ARM phone. This project builds the miner locally as an Android binary so the executable matches the Termux device architecture.

You can verify the device architecture with:

```sh
uname -m
```

For an ARM64 device it should report:

```text
aarch64
```

## Troubleshooting

Check the installed binary:

```sh
file ~/.local/share/cereblix-termux/bin/cereblix-miner
```

Check the launcher configuration:

```sh
cat ~/.local/share/cereblix-termux/config/miner.env
```

If the miner needs to be rebuilt:

```sh
cd cereblix-termux
./install.sh
```

## Safety

Only use this software on devices you own or are authorized to operate. CPU mining can cause substantial heat, battery drain and performance reduction.

Never commit wallet seed phrases, passwords, private keys or API tokens.
