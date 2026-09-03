# Validation record

This document records the successful Pokémon Champions Android 1.1.5 research
session and the later CODE-01 production validation. Snippets explicitly
marked historical contain development diagnostics; those markers are not in
the production payload.

## Historical repository-freeze build

The copied source was byte-for-byte identical to the successful working-tree
source:

```text
src/pc_fps_runtime.cpp SHA-256
4D07DF13BF365CD86F90D34B86E1E8CF88193E0F8EB7297025903A6D69CF2136
```

The direct build used the existing NDK r27d ARM64 API 33 compiler configured
by `scripts/build.ps1`. The ignored output was verified with
`llvm-readelf`:

```text
build/libpcfps_runtime.so
ELF64, Machine: AArch64
```

Fresh build output SHA-256:

```text
65019AB1291795A287B9D87A7D9571D4530502449C09BDDCE47F5A389AA688B3
```

The payload's recorded dynamic dependencies are `liblog.so`, `libdl.so`,
`libm.so`, and `libc.so`. The newly built payload was not deployed during this
freeze task.

## Bootstrap evidence — proven

The ARM64 payload was loaded into the normal Pokémon Champions process through
the `UnityPlayerActivity`/`Activity` class load path. The payload emitted:

```text
ARM64_GUEST_CONSTRUCTOR ... compile_arch=aarch64 sizeof_ptr=8
ARM64_GUEST_JNI_ONLOAD  ... compile_arch=aarch64 sizeof_ptr=8
```

This proves execution of the ARM64 guest payload in the vanilla app process
through the NativeBridge/Houdini boundary used by the test environment.

## Runtime frame-rate hook — proven

Representative payload logs:

```text
HOOK_INITIAL_SET requested=60
HOOK_REQUEST requested=30 effective=60
HOOK_REQUEST requested=-1 effective=60
```

The replacement preserved the original targetFrameRate function and forwarded
the effective value to it. The game image's original `MOV W0,#30` instruction
was not modified.

## Animation timing hook — proven (historical diagnostic evidence)

Representative logs included:

```text
ANIM_POC_FRAMERATE_REPLACED
ANIM_DIAG_FRAMERATE_ORIGINAL=30
ANIM_DIAG_FRAMERATE_EFFECTIVE=60
```

The downstream `PlayableHandle.SetTime` hook also observed the resulting time
values, including approximately 1/60-second steps. The original getter and
`SetTime` functions were called rather than suppressed.

The `ANIM_POC_*` and `ANIM_DIAG_*` names in this section belong to the
development build used for the original proof. CODE-01 removed those
diagnostic paths and retained only the caller-scoped original-result
replacement for `AnimationPlayer.AdvanceTime`; the production payload does
not replace `PlayableHandle.SetTime`.

## Presentation timing — proven at the display/presentation level

The valid presentation-history record set contained 127 records. The observed
intervals were:

| Condition | Interval | Equivalent rate |
| --- | ---: | ---: |
| Baseline | 33.3333 ms | approximately 30 FPS |
| Hook active | 16.6667 ms | approximately 60 FPS |

An additional final-process SurfaceFlinger latency inspection showed a
16.666666 ms median interval, with a small number of 33.333332 ms gaps. The
display surface itself was already capable of 60 Hz; this measurement is
presentation support, not by itself proof of unique game frames.

`Surface.setFrameRate()` was not used.

## Restart and visual evidence — proven for the PoC

- The payload was reloaded after a game restart and ran under a new process
  PID.
- The trainer/human animation path visibly became smoother with the animation
  hook active.
- 60FPS rendering and the smoother character animation were visually
  confirmed during the successful run.

## Current production validation

The cleaned Frida-free ReZygisk module was rebuilt and exercised through
normal launch, force-stop/relaunch, and full BlueStacks restart. The final
run confirmed the ARM64 constructor, `JNI_OnLoad`, target hook installation,
caller-scoped animation hook installation, initial effective 60 setting, and
successful `Runtime.load0` return. The same module was disabled for a stock
launch and then re-enabled; the stock run emitted no `PCFPS` records.

The user-confirmed validation recording showed unique rendered frames at
approximately 60 FPS and smoother trainer/human animation. The clean payload
SHA-256 was:

```text
b52ffbff0a514792dbf037af31cd4b64d1338f4277fe526534218b0ab5a72c47
```

## Explicit limits

The project does not claim a device-independent or future-version guarantee
from this recording alone. In particular, it does not provide an offline
universal proof of exactly 60 unique frames or exactly 60 unique trainer pose
updates for every scene and display policy.

The milestone claims runtime hook execution, approximately 60 Hz presentation,
and user-confirmed unique-frame 60 FPS/smoother-animation behavior in the
validated environment. New versions and environments require separate
validation.
