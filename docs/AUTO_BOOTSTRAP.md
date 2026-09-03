# Automatic ReZygisk bootstrap

This document records the current Frida-free automatic loading path for the
runtime-only research project. The validated baseline is Pokémon Champions
Android `1.1.5` / `versionCode 3191` on BlueStacks Tiramisu64, Android 13/API
33, with an x86_64 application process and ARM64 NativeBridge/Houdini support.

## Proven runtime flow

```text
ordinary Pokémon launcher start
        |
        v
ReZygisk x86_64 module in zygote/app specialization
        |
        +-- exact package filter and payload staging
        +-- bounded version and runtime readiness guard
        |
        v
Runtime.load0(application-loaded Class, app-private payload path)
        |
        v
Android NativeLoader -> NativeBridge / libnb.so -> Houdini
        |
        v
ARM64 runtime payload
        |
        +-- targetFrameRate cache hook: 30/-1 -> 60
        +-- targeted AnimationPlayer frame-rate hook: 30 Hz -> 60 Hz grid
```

The ReZygisk module is x86_64. The staged payload is an unchanged-at-load
ARM64 shared library. The application ClassLoader-associated `Runtime.load0`
call selects the NativeBridge-backed namespace; the payload constructor and
`JNI_OnLoad` execute in the ARM64 guest context.

Frida is not required. Earlier Frida-assisted bootstrap and emulated-realm
experiments are historical research only.

## Module behavior

The module targets only:

```text
jp.pokemon.pokemonchampions
```

For every other process it requests module-library close after specialization
and performs no staging or hook installation.

For the target process, `preAppSpecialize` obtains the module root through the
Zygisk `getModuleDir()` API and reads:

```text
payload/libpcfps_runtime.so
```

The payload is staged atomically into app-private storage. Source and
destination size/SHA-256, ELF64 AArch64 format, ownership, mode, and the
final replacement are checked. A matching destination is safely reused.

After specialization, a bounded worker attaches to the Java VM and requires:

```text
versionName = 1.1.5
versionCode = 3191
libil2cpp.so and libunity.so mapped
initialized targetFrameRate icall cache readable and writable
cached target address inside libunity.so
```

Only then does it invoke the equivalent of:

```text
Runtime.load0(application-loaded-class, absolute-payload-path)
```

Staging, version, readiness, JNI, or load errors are fail-open: the module
leaves the game running and does not modify the installed game files.

## Production module layout

The canonical module ZIP contains exactly:

```text
module.prop
zygisk/x86_64.so
payload/libpcfps_runtime.so
```

It contains no APK, split APK, game library, metadata, asset, log, capture,
Frida artifact, probe, diagnostic binary, or source file. Generated build
products under `build/` are ignored by Git.

## Build and package

Direct NDK clang compilation is used. No Android Studio, Gradle, CMake, Ninja,
APK tooling, signing tool, or application repackaging is required:

```powershell
& .\scripts\build.ps1 -NdkRoot <android-ndk>
& .\scripts\build-zygisk-bootstrap.ps1 -NdkRoot <android-ndk>
& .\scripts\package-zygisk-module.ps1
```

The build scripts also accept `ANDROID_NDK_HOME` or `ANDROID_NDK_ROOT` as
fallbacks. Recursive Windows Mark-of-the-Web removal is opt-in with
`-UnblockNdk` and is scoped to the selected NDK.

## Validation summary

The CODE-01-clean module was tested without Frida through normal launcher
start, force-stop/relaunch, and full BlueStacks restart. The final clean run
reported one each of:

```text
ARM64_GUEST_CONSTRUCTOR
ARM64_GUEST_JNI_ONLOAD
HOOK_INSTALL
ANIMATION_FRAMERATE_HOOK_INSTALLED
HOOK_INITIAL_SET effective=60
RUNTIME_LOAD0_RETURNED
```

No removed diagnostic markers, fatal signal, or ANR was observed. Disabling
the module and rebooting the guest produced a normal stock launch with no
`PCFPS` records; re-enabling restored the automatic path. See
[CODE_AUDIT.md](CODE_AUDIT.md) for the session details.

This is not a fresh-install gate: a clean supported BlueStacks environment
without pre-existing project state still needs PM-approved validation before
the ZIP is described as a polished public installer.

## Version and safety guard

The bootstrap requires both package version fields to match `1.1.5`/`3191`.
The payload performs independent library-base, resolver, target-library,
cache-mapping, original-cache, and animation-cache checks. Unsupported or
unverified versions remain stock wherever the guard can make that decision.

## Disable, revert, and troubleshooting

Disable or remove the `PCFPS Zygisk Auto Bootstrap` module through the supported
manager and restart the existing environment. The game should launch with
stock behavior; reinstalling the game is not part of the revert workflow.

Useful fail-open markers are:

```text
PCFPS-ZB: STAGE_FAILED
PCFPS-ZB: UNSUPPORTED_VERSION
PCFPS-ZB: TARGET_ICALL_TIMEOUT
PCFPS-ZB: RUNTIME_LOAD0_EXCEPTION
PCFPS: HOOK_NOT_INSTALLED
```

These indicate that the project did not install the dependent hook. They do
not justify changing game files or bypassing normal installation/licensing.

## References

- [Official Zygisk module API/sample](https://github.com/topjohnwu/zygisk-module-sample)
- [Magisk developer guide](https://topjohnwu.github.io/Magisk/guides.html)
- [AOSP NativeBridge API](https://android.googlesource.com/platform/art/+/refs/heads/master/libnativebridge/include/nativebridge/native_bridge.h)
- [Architecture](ARCHITECTURE.md)
- [Version 1.1.5 runtime facts](VERSION_1.1.5.md)
