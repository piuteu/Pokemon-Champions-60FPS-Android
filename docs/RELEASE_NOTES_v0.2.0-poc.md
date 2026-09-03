# Pokémon Champions Android 60FPS Runtime Research — v0.2.0-poc draft

Status: release-notes draft only. This release has not been published and no
tag or GitHub Release has been created.

## Scope

This milestone prepares the runtime-only research project for public review.
The currently supported game baseline is Pokémon Champions Android `1.1.5` /
`versionCode 3191` in the validated BlueStacks Tiramisu64 environment.

## Highlights

- automatic Frida-free ReZygisk bootstrap;
- x86_64 bootstrap to NativeBridge/Houdini and ARM64 guest payload;
- runtime interception of Unity `Application.set_targetFrameRate`, mapping
  requests `30` and `-1` to effective `60` while calling the original target;
- caller-scoped `AnimationClip.frameRate` correction for the proven
  `AnimationPlayer.AdvanceTime` path;
- normal launch, force-stop/relaunch, and full validated-environment restart
  persistence;
- module disable path that restores stock behavior;
- residual 30 Hz audit, transient-drop profiling, and CODE-01 production
  cleanup documentation.

## Artifact

The preferred distribution artifact is a maintainer-built ReZygisk-compatible
module ZIP containing exactly:

```text
module.prop
zygisk/x86_64.so
payload/libpcfps_runtime.so
```

The artifact must not contain an APK, split APK, proprietary game library,
metadata, game asset, Frida binary, source file, log, or capture.

## Validation highlights

The current production payload was built with direct NDK clang and verified as
ELF64 AArch64; the bootstrap is ELF64 x86_64. In the validated environment,
normal launch and restart flows showed the ARM64 constructor, `JNI_OnLoad`,
both runtime hook installations, initial effective 60 setting, and successful
`Runtime.load0` return without Frida. A disabled-module launch emitted no
project runtime markers and restored stock behavior.

The user-confirmed validation recording showed unique rendered frames at
approximately 60 FPS and smoother trainer/human animation. This result is
environment-specific and is not a guarantee for unverified game versions or
devices.

## Limitations

- only `1.1.5` / `3191` is supported and validated;
- other devices, emulators, root managers, and configurations are untested;
- future versions require a new layout/hash/offset audit and must fail open
  where reasonably possible;
- transient missed-vsync/frame-slot hitches were observed under BlueStacks
  profiling and remain a non-blocking research limitation;
- a genuinely clean fresh-install ZIP gate remains to be run before claiming
  a polished public installer.

## SHA-256 publication process

After the exact maintainer build intended for publication:

```powershell
Get-FileHash .\build\pcfps_zygisk_auto_bootstrap.zip -Algorithm SHA256
```

Record the resulting digest here only for the exact artifact approved for
public release, and publish it beside that artifact. Do not reuse a digest
from a different build. No publication digest is assigned to this private
staging repository.

## License model

The project uses a source-available license, not an OSI-approved
open-source license. The license permits study, personal/non-commercial builds,
private modification, GitHub fork collaboration, issues, citation, and
upstream Pull Requests. It restricts independent mirrors, standalone source
packages, compiled module redistribution, commercial use, and distribution of
third-party game content. The private staging repository remains subject to PM
review before any public visibility decision.
