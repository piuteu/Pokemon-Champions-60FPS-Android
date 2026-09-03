# Fresh Install Validation

Status: Gate 1C PASS in an isolated fresh environment on a separate physical
Windows host.

Date: 2026-09-03

Branch: `release/release-01-fresh-install-validation`

The canonical repository remains private. This document contains generic
validation evidence only; it does not record account information, emulator
serials, process IDs, host paths, hostnames, private addresses, tokens, or
private logs.

## Gate 1A — artifact and clean-install preparation

- Repository, branch selection, and repository-local privacy setup: PASS.
- Canonical source build with the validated NDK r27d / Android API 33 path:
  PASS.
- Build target: Android API 33, ARM64 guest payload and x86_64 bootstrap.
- ARM64 payload: ELF64 AArch64.
- ReZygisk bootstrap: ELF64 x86_64.
- Module ZIP contents: exactly `module.prop`, `zygisk/x86_64.so`, and
  `payload/libpcfps_runtime.so`.
- Canonical module ZIP SHA-256:
  `8fc831682ce68d66505ff8c7dfff706b8ad484c49a438d4318162f4f59573344`.
- ARM64 payload SHA-256:
  `b52ffbff0a514792dbf037af31cd4b64d1338f4277fe526534218b0ab5a72c47`.
- x86_64 bootstrap SHA-256:
  `dc10e56bda8d5e7054ccff25db781b09c92dc206499ad587ea2639e9a031aa3e`.
- APK, split APKs, game libraries, and game assets: not modified.
- Frida: not used in the final validation path.

## Fresh environment baseline

- Isolated separate physical Windows host: PASS.
- Fresh BlueStacks Android 13 / Tiramisu64-class environment: PASS.
- Guest ABI: x86_64.
- NativeBridge capability: present.
- Manager/Kyubi root: PASS.
- ReZygisk active: PASS.
- Google Play installation of Pokémon Champions: PASS.
- Game versionName/versionCode confirmation before PCFPS installation: PASS;
  versionName 1.1.5 / versionCode 3191.
- Stock game files and package contents were not modified.

## Gate 1B — root and ReZygisk

- Magisk-managed Manager/Kyubi root: PASS.
- `su -c id` root proof: PASS.
- ReZygisk installation and active bootstrap: PASS.
- Built-in Magisk Zygisk remained disabled for the ReZygisk path.
- Stock Pokémon Champions launch after root/ReZygisk setup: PASS.
- Play licensing and normal game startup remained intact before PCFPS
  installation.

## Gate 1C — Frida-free runtime validation

- Fresh canonical module ZIP installation: PASS.
- Kyubi UI module list did not enumerate PCFPS, but the module directory was
  present and the expected runtime behavior/log evidence proved installation
  and operation.
- Normal launcher icon launch: PASS.
- Automatic x86_64 bootstrap: PASS.
- ARM64 guest constructor: PASS.
- ARM64 guest `JNI_OnLoad`: PASS.
- `VERSION_GUARD_OK`: PASS.
- FPS hook installation: PASS.
- Animation framerate hook installation: PASS.
- Effective 60 FPS: PASS.
- Force-stop followed by normal relaunch and 60 FPS: PASS.
- Full BlueStacks restart followed by normal relaunch and 60 FPS: PASS.
- Module disable followed by stock 30 FPS: PASS.
- Module re-enable followed by restart and 60 FPS recovery: PASS.
- No PCFPS-attributable fatal error or ANR was observed during validation.
- Frida was not used.
- Pokémon Champions APK/splits/assets remained unmodified.

## Known limitations

The Kyubi UI module list is not treated as the authoritative PCFPS
installation indicator for this environment. The installation was established
by the module directory and the expected automatic bootstrap, ARM64 payload,
version guard, FPS-hook, and animation-hook runtime evidence.

The result is specific to the validated Pokémon Champions 1.1.5 /
versionCode 3191 build and the isolated BlueStacks Android 13 environment.
Future game versions and other environments require separate validation.
