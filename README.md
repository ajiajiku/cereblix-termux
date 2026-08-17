# cereblix-termux

Termux tooling for running the open-source Cereblix CPU miner on Android devices supported by Termux.

## Project goal

Target **Android 7.0 / API 24 and newer**, with automatic detection of the device ABI. The first development target is ARM64; ARMv7 support will be added and tested separately.

This repository contains the Termux installer, launcher, configuration and build automation. It does **not** redistribute the original Cereblix APK or its `libnmminer.so`.

The upstream Cereblix source is available at:

- https://github.com/CereblixCRB/cereblix

The upstream project documents a Go 1.21+ build and the standalone miner command `cereblix-miner`. We will build/test the Android/Termux package from source rather than modifying the APK.

## Current status

- [x] Repository initialized
- [x] Android API/ABI detection
- [x] Termux environment checks
- [x] Installer skeleton
- [x] Launcher/configuration skeleton
- [ ] ARM64 native build validation on Android 7
- [ ] ARMv7 build validation on Android 7
- [ ] Release artifacts
- [ ] Automated update channel

## Install from a cloned checkout

```sh
git clone https://github.com/ajiajiku/cereblix-termux.git
cd cereblix-termux
chmod +x install.sh
./install.sh
```

The installer will refuse unsupported Android versions and will report the detected ABI before installing/building anything.

## Safety

Only use this software on devices you own or are authorized to operate. Mining can produce substantial CPU load, heat and battery drain.

Never put wallet seed phrases, passwords or API tokens into this repository.
