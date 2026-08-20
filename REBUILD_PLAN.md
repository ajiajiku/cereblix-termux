# Cereblix Termux — rebuild from APK v2

This branch is the clean rebuild based on the official Cereblix mobile miner architecture.

## Direction

The old HTTP/getwork launcher and the local `cereblix-stratum` bridge are not used by this rebuild.

The target architecture is:

```text
Termux
  -> Cereblix Stratum client
  -> NeuroMorph native engine
  -> Cereblix pool
```

The worker name is supplied separately as `rigid` so it can be changed by the user.

## Important compatibility note

The original Android v2 APK declares Android API 26. This project is **not** trying to run that APK on Android 7. Instead, it reuses the open-source native engine/protocol design and builds a Termux-native executable for the device architecture.

## Next implementation stages

1. Import the required native NeuroMorph sources from the official `CereblixCRB/cereblix-miner` repository.
2. Build the native engine as a standalone Termux library/executable rather than through JNI.
3. Implement the Stratum JSON-RPC client using the protocol used by the Android client (`login`, `submit`, `keepalived`, and job handling).
4. Expose wallet, worker (`rigid`), and thread count through a simple configuration/start command.
5. Add an architecture check for ARMv7/ARM64 and a self-test before mining.
6. Test pool connection and accepted shares before adding convenience features.

## Source

Official source: https://github.com/CereblixCRB/cereblix-miner
