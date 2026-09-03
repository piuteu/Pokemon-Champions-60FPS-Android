# Research notes

All sections below are historical research context. They describe failed or
development-only approaches and are not requirements or instructions for the
production runtime module.

## Modified APK failure

Modified or repacked application attempts encountered combinations of:

- wrong installer behavior;
- Source Stamp issues;
- PairIP licensing-flow failures; and
- Play or asset-pack failures.

Conclusion: runtime-only implementation is mandatory for this target. The
successful milestone leaves the Google Play APK and splits untouched.

## Frida emulated-realm failure

The normal Frida realm worked for the Java bootstrap. Frida's emulated realm
reported:

```text
Failed to attach: process is not using emulation
```

This occurred even though ARM64 `libil2cpp` and `libunity` mappings were
visible under Houdini. Conclusion: do not depend on Frida's emulated realm for
this workflow.

## Raw ARM instruction runtime patch

The ARM64 source bytes for the original `MOV W0,#30` instruction could be
changed in mapped memory to the equivalent `MOV W0,#60` bytes, but the runtime
continued to behave as 30 FPS. The likely cause is Houdini's translated-code
cache. This explanation is likely, not fully proven, and the repository does
not rely on the raw instruction patch.

## Successful bootstrap

The working load path was:

```text
Runtime.load0(Activity.class, ARM64 .so path)
```

Calling `System.load(path)` directly from the Frida context produced a
caller-class/null-related failure. The class-associated `Runtime.load0` path
allowed Android's normal native loader to pass the library through
NativeBridge/Houdini and produced both the ARM64 constructor and `JNI_OnLoad`
proof markers.

## Hooking observations

The targetFrameRate wrapper and the animation icall caches were writable in the
running process. Cache replacement allowed the payload to preserve each
original function and alter only the requested/effective frame-rate values
needed by this PoC. The animation replacement was further restricted to the
`AnimationPlayer.AdvanceTime` frame-rate call return site, leaving unrelated
`AnimationClip.get_frameRate` users unchanged.
