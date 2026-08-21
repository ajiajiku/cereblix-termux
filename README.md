# Cereblix Termux

Standalone Termux miner based on the Cereblix Android v2.0 native-engine/Stratum behavior.

> **Target:** Android 7.0+ (API 24+) on ARM64 (`arm64-v8a`) or ARMv7 (`armeabi-v7a`).
>
> The installer checks the Android API and CPU ABI before building. The Android 7 target is a compatibility target; it is not a claim that every Android 7 device has been individually tested.

## What it does

- Builds the native engine locally inside Termux.
- Connects to `stratum.cereblix.com:3333`.
- Supports a custom CRB wallet and worker name.
- Supports configurable CPU threads (`0` = automatic).
- Saves the wallet locally so it is **not requested every time**.
- Keeps the configuration when the miner is reinstalled/upgraded.
- Handles `Ctrl+C`/`SIGTERM` cleanly.
- Reports accepted and rejected shares.
- Supports optional **autostart when a Termux shell is opened**.

## Quick install

If Termux is already installed, start here:

```sh
pkg update -y
pkg install -y git
git clone https://github.com/ajiajiku/cereblix-termux.git
cd cereblix-termux
chmod +x install.sh
./install.sh
```

The installer then builds the miner and prepares the local configuration.

## First-time setup

After `./install.sh`, the installer may ask for:

```text
CRB wallet address (crb1...):
```

Enter your CRB wallet address beginning with `crb1`.

Then start the miner:

```sh
~/.local/share/cereblix-termux/start.sh
```

A successful run looks like:

```text
Cereblix Termux — APK v2.0 native engine
Pool: stratum.cereblix.com:3333
Worker: hp1
Threads: 8
share accepted: 1
hashes=... accepted=1 rejected=0
```

If `accepted` keeps increasing and `rejected=0`, the miner is communicating with the pool successfully.

## Optional: start mining automatically when Termux opens

After wallet/worker/threads are configured, enable autostart once:

```sh
echo 'if [ -z "$CEREBLIX_AUTOSTART" ]; then export CEREBLIX_AUTOSTART=1; ~/.local/share/cereblix-termux/start.sh; fi' >> ~/.bashrc
```

Then close the Termux session and open Termux again. The miner will start automatically using the saved wallet, worker and thread settings.

Important:

- Do not open multiple Termux shells if each shell has autostart enabled, or multiple miner processes may run.
- Autostart runs when the Termux shell starts; it does **not** guarantee that Android will keep the process alive after the OS kills Termux.
- To disable autostart, edit `~/.bashrc` and remove the line containing `CEREBLIX_AUTOSTART`.
- Manual start remains available with `~/.local/share/cereblix-termux/start.sh`.

For the complete beginner guide, including autostart and troubleshooting, see [docs/INSTALL.md](docs/INSTALL.md).

## Change wallet, worker or threads

Run:

```sh
~/.local/share/cereblix-termux/start.sh --setup
```

It asks for the wallet, worker name and CPU thread count.

Examples:

- Worker: `hp1`
- Threads: `8`
- Threads: `0` for automatic CPU detection

The pool remains:

```text
stratum.cereblix.com:3333
```

## Where configuration is stored

The installer creates:

```text
~/.local/share/cereblix-termux/
├── bin/cereblix-termux   # compiled miner
├── source/               # downloaded native source used for the build
├── config                # wallet/worker/thread/pool settings
└── start.sh              # launcher
```

The configuration file is:

```text
~/.local/share/cereblix-termux/config
```

It is created with permission `600` and should **never be uploaded to GitHub**, because it contains the wallet address.

## Reinstall / update

From the repository directory:

```sh
git pull
./install.sh
```

The installer preserves the existing wallet and configuration when rebuilding. After installation, start normally with:

```sh
~/.local/share/cereblix-termux/start.sh
```

If autostart was already enabled in `~/.bashrc`, it remains enabled.

## Stop the miner

Press:

```text
Ctrl+C
```

The launcher forwards the termination signal to the native miner and exits cleanly.

## Troubleshooting

### `No mirror or mirror group selected`

This message from Termux is normally a mirror-selection notice, not a miner error. If package installation continues and ends successfully, you can proceed. If package downloads fail, run:

```sh
termux-change-repo
```

and select a working Termux mirror.

### Wallet is requested again

Run:

```sh
cat ~/.local/share/cereblix-termux/config
```

There should be a line beginning with:

```text
CRB_WALLET="crb1..."
```

If the wallet is present, `start.sh` should use it automatically.

### `accepted=0` for a while

Keep the miner running for several minutes. Hashrate and share timing can vary. A connection is confirmed when accepted shares begin increasing.

### `rejected` is increasing

Stop with `Ctrl+C` and check the wallet, worker name, pool host and port. Do not repeatedly change working configuration while the miner is actively submitting shares.

### Unsupported device

The installer requires:

- Android API 24 or newer (Android 7.0+)
- `arm64-v8a` or `armeabi-v7a`
- Termux with a working package repository

## Full installation guide

For a beginner-friendly guide starting with a fresh Android device and a fresh Termux installation, see:

**[docs/INSTALL.md](docs/INSTALL.md)**

## Security notes

- Never paste your wallet into a public GitHub file, issue, pull request or screenshot.
- The local config is intended to stay on the device.
- Only install Termux from a trusted source. The project documentation recommends the F-Droid distribution for Termux.

## Project structure

```text
cereblix-termux/
├── README.md
├── docs/
│   └── INSTALL.md
├── install.sh
├── start.sh
├── src/
└── analysis/
```

## Source / license

The upstream Android application and native source remain owned/licensed by their original project. This repository contains the Termux bridge, build orchestration, and analysis derived from the supplied APK/source material.
