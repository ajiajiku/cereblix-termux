# APK v2.0 analysis

Source artifact: `cereblix-miner-universal-v2.0.apk`

SHA-256:
`ccb4dbdc0fa85fda76f155c33359ab549ccad1d4cfcb19f615b36becae94b228`

## Android manifest

- Package: `com.cereblix.miner`
- Version name: `2.0`
- Version code: `2`
- Compile SDK: `34`
- Target SDK: `34`
- **Minimum SDK: `26` (Android 8.0)**
- `extractNativeLibs=false`
- Main activity: `com.cereblix.miner.MainActivity`
- Mining service: `com.cereblix.miner.MiningService`
- Required permissions include INTERNET, FOREGROUND_SERVICE, FOREGROUND_SERVICE_DATA_SYNC, WAKE_LOCK and POST_NOTIFICATIONS.

## Native payload

The APK contains `libnmminer.so` for:

- `arm64-v8a`
- `armeabi-v7a`
- `x86_64`

All three native libraries report an Android 26/API 26 linker target. The ARM64 library is built with NDK r26b and exports the JNI methods below.

## JNI surface found in `libnmminer.so`

- `NativeMiner.selfTest`
- `NativeMiner.start`
- `NativeMiner.setActive`
- `NativeMiner.coreCount`
- `NativeMiner.bigCoreCount`
- `NativeMiner.setJob`
- `NativeMiner.pollShare`
- `NativeMiner.hashes`
- `NativeMiner.threadHashes`
- `NativeMiner.stop`

## Java/Kotlin components found in DEX

- `com.cereblix.miner.MainActivity`
- `com.cereblix.miner.MiningService`
- `com.cereblix.miner.NativeMiner`
- `com.cereblix.miner.StratumClient`

The APK also contains Kotlin metadata and AndroidX dependencies.

## Stratum/protocol strings recovered from DEX

Observed protocol elements include JSON-RPC methods:

- `login`
- `submit`
- `keepalived`

Observed fields include `login`, `pass`, `agent`, `rigid`, `job_id`, `blob`, `seed_hash`, `target`, `height`, `nonce`, `wallet`, `host`, and `port`.

The Android miner identifies its agent as:

`nmminer-android/2.0`

The DEX also contains the HTTP API base string:

`https://cereblix.com/api`

and strings such as `stratum://`, `nm-stratum`, `nm-submit`, `nmminer`, and `nmminer:mine`.

## Compatibility conclusion

The APK itself declares **minSdk 26**, and its bundled native libraries are built for **Android API 26**. Therefore the original APK/native payload is not a valid Android 7/API 24 target.

For an Android 7 Termux port, the native engine must be rebuilt from compatible source with an API-24-compatible NDK/sysroot, while preserving the observed JNI/native API and Stratum contract. Simply copying `libnmminer.so` from this APK will not solve Android 7 compatibility.
