# Pokémon Champions Android 60FPS Runtime Research

An independent runtime-only 60 FPS research project for the Android version
of Pokémon Champions. The current validated baseline is Pokémon Champions
Android `1.1.5` / `versionCode 3191`; future app versions require a fresh
compatibility audit before they can be marked supported.

## Overview

The project changes frame pacing at runtime while leaving the legitimate
Google Play installation intact. It does not repackage, patch, re-sign, or
redistribute the game. The preferred user-facing artifact is a maintainer-built
ReZygisk-compatible module ZIP; source builds remain available for research,
verification, and contributors.

## Project Status

The current production baseline has passed the CODE-01 runtime audit and the
automatic, Frida-free bootstrap gate in the validated BlueStacks environment.
The user-confirmed validation recording showed unique rendered frames at
approximately 60 FPS and smoother trainer/human animation. This is a research
result for the stated environment, not a broad device-compatibility claim.

## Features

- runtime-only interception of Unity's `Application.set_targetFrameRate`
- requests of `30` and `-1` forwarded to the original setter as effective `60`
- caller-scoped `AnimationClip.frameRate` interception for the proven
  `AnimationPlayer.AdvanceTime` path, changing an original `30.0f` result to
  `60.0f` while preserving the original time, duration, event, and playback
  logic
- Frida-free automatic ReZygisk bootstrap
- x86_64 bootstrap → NativeBridge/Houdini → ARM64 guest payload
- normal launcher start, force-stop/relaunch, and full BlueStacks restart
  persistence
- module disable restores stock behavior; the uninstall path is documented but
  has not been independently tested
- residual 30 Hz audit and transient frame-drop profiling retained as
  research documentation

## Version Support

| Game | versionCode | Status |
| --- | ---: | --- |
| Pokémon Champions Android 1.1.5 | 3191 | Supported / validated |
| Future versions | — | Unverified; fail open where reasonably possible |

An unlisted version must remain stock until its Unity/IL2CPP layout, relevant
hashes/signatures, offsets, runtime hooks, animation behavior, and 60 FPS
result have been validated.

## How It Works

```text
Pokémon Champions normal launch
        ↓
x86_64 ReZygisk bootstrap
        ↓
package + version guard
        ↓
payload staging and integrity verification
        ↓
application ClassLoader
        ↓
Runtime.load0
        ↓
NativeBridge / Houdini
        ↓
ARM64 payload
        ↓
Unity runtime hooks
        ↓
60 FPS + targeted animation timing correction
```

The payload preserves the original Unity functions and changes only the
validated frame-rate inputs. It does not patch the game's `MOV W0,#30`
instruction, suppress unrelated initialization, or call `Surface.setFrameRate`
as a substitute for game rendering.

## Why Runtime-Only

Modified APKs and extracted game libraries can break normal installation,
licensing, asset, or update behavior. This project deliberately keeps the
Google Play app, splits, manifest, and proprietary native libraries unchanged;
the runtime hook is loaded only after the app starts normally.

## Requirements

The only environment validated by this project is:

- a legitimate Google Play installation of Pokémon Champions Android 1.1.5 /
  3191
- BlueStacks Tiramisu64, Android 13 / API 33, x86_64 with ARM64
  NativeBridge/Houdini
- a rooted, ReZygisk-compatible setup
- a maintainer-provided module ZIP, installed through the supported module
  manager

Frida is not required for normal use. Other physical devices, emulators, root
managers, and configurations are untested.

## Installation

1. Install or use your own legitimate Google Play copy of Pokémon Champions.
2. Ensure the validated rooted BlueStacks/ReZygisk environment is ready.
3. Install the maintainer-provided module ZIP through the supported manager;
   do not manually copy payloads into the app.
4. Restart as required by the manager.
5. Launch Pokémon Champions normally.
6. Verify the expected 60 FPS behavior and trainer/human animation result.

The repository does not distribute the APK, split APKs, game assets, metadata,
`libil2cpp.so`, or `libunity.so`.

## Disabling / Uninstalling

Disable the `PCFPS Zygisk Auto Bootstrap` module in the supported manager and
restart. The game should launch with stock behavior. The uninstall path is
documented by the supported manager but was not independently tested in the
validation run. Reinstalling the game is not part of the normal revert workflow.

## Building from Source

The project uses direct NDK clang compilation. Android Studio, Gradle, CMake,
Ninja, APK tooling, signing tools, and application repackaging are not
required. Pass an NDK root explicitly, or set `ANDROID_NDK_HOME` or
`ANDROID_NDK_ROOT` for the current PowerShell process:

```powershell
& .\scripts\build.ps1 -NdkRoot <android-ndk>
& .\scripts\build-zygisk-bootstrap.ps1 -NdkRoot <android-ndk>
& .\scripts\package-zygisk-module.ps1
```

The scripts preserve the validated NDK r27d family, Android API 33 targets,
ARM64 payload, and x86_64 bootstrap. `-UnblockNdk` is an optional Windows
troubleshooting switch; it is not run recursively by default:

```powershell
& .\scripts\build.ps1 -NdkRoot <android-ndk> -UnblockNdk
```

The ignored outputs are written under `build/`.

## Verification

The canonical module ZIP contains exactly:

```text
module.prop
zygisk/x86_64.so
payload/libpcfps_runtime.so
```

The clean payload is ELF64 AArch64 and the bootstrap is ELF64 x86_64. Build
logs should show the ARM64 constructor, `JNI_OnLoad`, successful hook
installation, and `Runtime.load0` return. The full validation record and
artifact process are documented in [docs/CODE_AUDIT.md](docs/CODE_AUDIT.md) and
[docs/VALIDATION.md](docs/VALIDATION.md).

## Known Limitations

- only 1.1.5 / 3191 is currently validated;
- the current validation environment is BlueStacks Tiramisu64;
- future versions require re-audit and may fail open without loading a stale
  hook;
- transient missed-vsync/frame-slot hitches were observed under BlueStacks
  profiling and remain a non-blocking research limitation;
- the user-confirmed 60 FPS recording does not guarantee identical results on
  every device, scene, display policy, or future game version.

## Updating for New Game Versions

For each update:

1. detect the new game version and `versionCode`;
2. inspect whether Unity/IL2CPP layouts changed;
3. verify relevant hashes, signatures, and offsets;
4. never reuse stale hardcoded offsets blindly;
5. update version-specific constants only after evidence is available;
6. rebuild the ARM64 payload and x86_64 bootstrap;
7. validate runtime loading and fail-open behavior;
8. validate 60 FPS rendering and animation behavior;
9. mark the version supported only after every required check passes.

## Research Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Automatic bootstrap](docs/AUTO_BOOTSTRAP.md)
- [Version 1.1.5 facts](docs/VERSION_1.1.5.md)
- [Validation](docs/VALIDATION.md)
- [Residual 30 Hz audit](docs/RESIDUAL_30HZ_AUDIT.md)
- [Transient drop audit](docs/PERF_TRANSIENT_DROPS.md)
- [Research notes](docs/RESEARCH_NOTES.md)
- [Production cleanup audit](docs/CODE_AUDIT.md)
- [Public release checklist](docs/PUBLIC_RELEASE_CHECKLIST.md)
- [Release notes draft](docs/RELEASE_NOTES_v0.2.0-poc.md)

Historical diagnostic procedures and captures are research-only. They are not
required by, or packaged into, the production runtime module.

## Contributing

Community members may open Issues, test new game versions, submit logs,
provide legally safe hash/offset findings, use GitHub forks, and submit Pull
Requests. A useful new-version report includes:

```text
game version / versionCode
Android or emulator environment
bootstrap result
60 FPS result
animation result
legally safe hashes or offset findings
relevant logs
regression description
```

Do not upload APKs, split APKs, `libil2cpp.so`, `libunity.so`,
`global-metadata.dat`, extracted assets, or other proprietary game files.

## License

The original project code and documentation are offered under the
source-available license in [LICENSE](LICENSE). It permits study, personal and
non-commercial builds, private modification, GitHub fork collaboration, and
upstream contributions. It does not grant rights to redistribute compiled
modules, rehost source packages, commercially use the project, or distribute
third-party game content. It is not presented as OSI-approved or legally
reviewed.

## Legal Disclaimer

This is an unofficial, independent research project. It is not affiliated
with or endorsed by Nintendo, The Pokémon Company, Game Freak, Creatures,
BlueStacks, or any other third-party rights holder. Pokémon Champions,
Pokémon, Unity, BlueStacks, and related names and content remain the property
of their respective owners. Users must provide and use their own legitimate
game installation. This repository does not distribute the game or its
proprietary files.
