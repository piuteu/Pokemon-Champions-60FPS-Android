# Fresh Install Validation

Status: Gate 1B blocked; the fresh Play Store version gate passed, but
root/ReZygisk setup is not yet reproducible on this instance.

Date: 2026-09-03

Branch: `release/release-01-fresh-install-validation`

The canonical repository remains private. This document contains generic
validation evidence only; it does not record account information, emulator
serials, process IDs, host paths, hostnames, private addresses, tokens, or
private logs.

## Gate 1A — build and clean-install preparation

- Repository and branch selection: PASS.
- Repository-local privacy setup: PASS.
- Direct NDK clang build: PASS.
- Build target: Android API 33, ARM64 guest payload and x86_64 bootstrap.
- ARM64 payload: ELF64 AArch64.
- ReZygisk bootstrap: ELF64 x86_64.
- Module ZIP contents: exactly `module.prop`, `zygisk/x86_64.so`, and
  `payload/libpcfps_runtime.so`.
- Gate 1A module ZIP SHA-256:
  `0be5756c81f8b05428e61ef408665a46f1d0f42bb47f2f1340c0679aabb5d67b`
- Gate 1A payload SHA-256:
  `b52ffbff0a514792dbf037af31cd4b64d1338f4277fe526534218b0ab5a72c47`
- Gate 1A bootstrap SHA-256:
  `dc10e56bda8d5e7054ccff25db781b09c92dc206499ad587ea2639e9a031aa3e`
- APK, split APKs, game libraries, and game assets: not modified by this
  checkpoint.
- Frida: not used for this build checkpoint.

## Fresh environment baseline

- Genuinely new supported instance, not a clone of the validated instance:
  PASS.
- BlueStacks family: BlueStacks 5, Android 13 / API 33.
- Guest ABI: x86_64.
- NativeBridge capability: present.
- Pre-PCFPS game package check: PASS; no Pokémon Champions-related package was
  present before Play Store installation.
- Pre-PCFPS root check: PASS; the shell was non-root.
- Pre-PCFPS module check: PASS; no accessible module directory was present.
- A non-game BlueStacks UI component displayed a repeated-stop dialog during
  home-screen setup. No PCFPS payload, game package, or game file was involved
  in that observation; it remains an environment note only.
- The same non-game BlueStacks component was still reported as repeatedly
  stopping during the fresh-instance session.

## Fresh-install validation status

- Genuinely new supported BlueStacks Android 13 / Tiramisu64-class instance:
  PASS.
- Generic BlueStacks version, Android API, ABI, and NativeBridge capability:
  PASS.
- Google Play installation from the Play Store: PASS.
- Game versionName/versionCode confirmation before PCFPS installation: PASS;
  versionName 1.1.5 / versionCode 3191.
- Root/ReZygisk bootstrap: BLOCKED before PCFPS installation. The ordinary
  shell remained non-root, no module directory was visible, and a root proof
  could not be obtained while the BlueStacks component was repeatedly
  stopping. No bypass or manual payload copy was attempted.
- PCFPS module installation and enablement: NOT STARTED.
- Frida-free automatic bootstrap validation: NOT STARTED.

The current checkpoint must stop before module installation because the
supported root/ReZygisk setup has not been independently verified. If a
future Play Store installation provides a game version other than the
validated 1.1.5 / versionCode 3191, the current version-specific runtime
hook must not be applied.

## Known limitations

Gate 1A proves only the sanitized branch build and package shape. It does not
prove fresh-install licensing, PairIP, Play Asset Delivery, ReZygisk loading,
runtime hook installation, restart persistence, or stock behavior after module
disable.
