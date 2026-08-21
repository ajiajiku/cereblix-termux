# Cereblix Termux — APK v2.0-derived

This project ports the native mining engine and Stratum contract used by the Cereblix Android miner v2.0 into a standalone Termux program.

## Android 7 target

The original APK requires Android 8/API 26+, so it cannot simply be installed on Android 7/API 24. This repository rebuilds the native engine locally for the phone's ARM ABI instead.

Target:

- Android 7/API 24+
- ARM64 (`arm64-v8a`) and ARMv7 (`armeabi-v7a`)
- Stratum login/job/submit/keepalive flow
- custom wallet and worker name
- configurable CPU threads
- clean Ctrl+C shutdown

## Install

```sh
git clone https://github.com/ajiajiku/cereblix-termux.git
cd cereblix-termux
chmod +x install.sh
./install.sh
```

The installer builds the native program locally and creates:

```text
~/.local/share/cereblix-termux/bin/cereblix-termux
~/.local/share/cereblix-termux/start.sh
~/.local/share/cereblix-termux/config
```

On a new installation, `install.sh` asks for the wallet once and saves it in the private config file. Reinstalling does not overwrite an existing wallet.

## Start

```sh
~/.local/share/cereblix-termux/start.sh
```

If a wallet is already saved, **the miner will not ask for it again**. That is intentional.

To change the wallet, worker name, or CPU thread count:

```sh
~/.local/share/cereblix-termux/start.sh --setup
```

Then answer the three prompts. The wallet is stored locally in:

```text
~/.local/share/cereblix-termux/config
```

The config is created with restrictive permissions (`600`). Do not upload it to GitHub because it contains your wallet address.

## Configuration example

```sh
CRB_WALLET="crb1..."
CRB_WORKER="nmminer-termux"
CRB_THREADS="0"
CRB_POOL_HOST="stratum.cereblix.com"
CRB_POOL_PORT="3333"
```

`CRB_THREADS="0"` means automatic CPU core detection.

## Accepted shares

A successful connection should show lines such as:

```text
share accepted: 1
hashes=... accepted=1 rejected=0
```

Keepalive responses such as `status: KEEPALIVED` are normal pool traffic and are **not** counted as rejected shares.

## Source / license

The upstream Android application and native source remain owned/licensed by their original project. This repository contains the Termux bridge, build orchestration, and analysis derived from the supplied APK.
