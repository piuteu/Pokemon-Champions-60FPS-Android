# Runtime architecture

This document describes the current Frida-free production path. Detailed
version-specific addresses and ABI notes are in
[VERSION_1.1.5.md](VERSION_1.1.5.md); cleanup decisions are in
[CODE_AUDIT.md](CODE_AUDIT.md).

## Current automatic path

```text
Pokémon Champions normal launch
        |
        v
x86_64 ReZygisk bootstrap
        |
        +-- exact package and version guard
        +-- source hash / ELF validation and atomic staging
        +-- Unity library and icall readiness checks
        |
        v
application ClassLoader -> Runtime.load0
        |
        v
Android NativeLoader -> NativeBridge / libnb.so -> Houdini
        |
        v
ARM64 guest runtime payload
        |------------------------------|
        v                              v
Unity targetFrameRate hook       AnimationPlayer timing hook
30 / -1 -> 60                    targeted 30 Hz grid -> 60 Hz grid
```

The ReZygisk module executes as x86_64 in the tested BlueStacks Tiramisu64
process. It stages the ARM64 payload into app-private storage and asks the
application's own ClassLoader-associated `Runtime.load0` path to load it.
NativeBridge/Houdini then executes the payload in the ARM64 guest context.
The payload's constructor and `JNI_OnLoad` are the guest-execution proof.

Frida is not required by this path. Earlier Frida-assisted Java bootstrap work
is historical research and is documented in [RESEARCH_NOTES.md](RESEARCH_NOTES.md),
not a production dependency.

## Frame-rate hook

The payload resolves
`UnityEngine.Application::set_targetFrameRate(System.Int32)` through
`il2cpp_resolve_icall`. It preserves the original native target and replaces
the initialized IL2CPP icall cache entry at runtime:

```text
requested == 30 or requested == -1  ->  effective 60
otherwise                            ->  requested
```

The original function is called with the effective value. The game's
`MOV W0,#30` instruction is not patched, and unrelated Unity initialization is
not suppressed. The examined `SmartPoint.AssetAssistant.Sequencer.Awake`
path reaches the same Unity native target through the IL2CPP wrapper.

## Animation timing hook

The payload resolves the original
`AnimationClip::get_frameRate_Injected` icall and calls it before applying the
caller filter. Only the exact proven return site in
`AnimationPlayer.AdvanceTime` changes an original `30.0f` result to `60.0f`.
Other callers and other values pass through unchanged.

`AdvanceTime` retains its time scale, duration, wrapping, event, and playback
logic. Its frame-grid denominator is therefore 60 for the targeted 30 Hz clip
rate while the downstream original `SetTime` behavior remains intact. No
`PlayableHandle.SetTime` replacement is part of the production payload.

## Safety and versioning

The bootstrap refuses unsupported package/version combinations and fails open
on staging, hash, mapping, readiness, loader, or JNI errors. The ARM64 payload
also checks the expected library mappings, resolver target, cache mappings,
original cache values, and write-back results before installing a hook.

The current constants are validated only for Pokémon Champions Android 1.1.5 /
`versionCode 3191`. Future versions must follow the update process documented
in the root [README.md](../README.md); hardcoded offsets must never be reused
without a new audit.
