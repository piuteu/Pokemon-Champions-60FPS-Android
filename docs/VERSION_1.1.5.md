# Pokémon Champions Android 1.1.5 facts

Compatibility status: supported and validated for Android `1.1.5` /
`versionCode 3191` in the documented BlueStacks Tiramisu64 environment. These
constants are version-specific; a future app version remains unverified until
the update audit and runtime validation pass.

All RVAs below are relative to the corresponding ELF image base. Hashes are
for the extracted reference files used during the research session; those
files are not included in this repository.

## Reference file hashes

| File | SHA-256 |
| --- | --- |
| `libil2cpp.so` | `0A927341D12682592AB7056FF3EE526C01073F1EC92CB6C0A67DFC9370DBEF19` |
| `libunity.so` | `CC6202017E6F45CC85CD9FA840462A7E3CF71852645AFAAE94A26EDBD284241F` |
| `global-metadata.dat` | `565C9747771E2436995B1B9EF5DD75E4184ACE2EC42120396C0578A3CBB5D957` |

The two shared libraries were ELF64 AArch64 images. The metadata file was
metadata version 31.

## `Application.set_targetFrameRate`

Known path:

```text
SmartPoint.AssetAssistant.Sequencer.Awake
  RVA:                         0x27FE770
  MOV W0,#30 instruction:      0x27FE904
  following call site:         0x27FE90C
        |
        v
UnityEngine.Application::set_targetFrameRate(System.Int32)
  IL2CPP wrapper RVA:           libil2cpp + 0x4C0E140
  icall cache:                  libil2cpp + 0x5612250
        |
        v
resolved native target:        libunity + 0x6BBA0C
native effective ABI:          void(int32_t)
```

The managed wrapper ABI used for direct diagnostic invocation is effectively
`void(int32_t, const MethodInfo*)`; the resolved Unity native icall ABI is
`void(int32_t)`. The known targetFrameRate calls examined in this build
converged on the same IL2CPP icall cache/native target path. The source
`MOV W0,#30` remains unchanged in the installed game.

## `AnimationPlayer.AdvanceTime`

Exact managed method:

```text
Namespace:       SmartPoint.Components
Class:           AnimationPlayer
Signature:       System.Void SmartPoint.Components.AnimationPlayer::AdvanceTime(System.Single deltaTime)
Metadata token:  0x06006e21
Method index:    28192
RVA:             libil2cpp + 0x277CD5C
Effective ABI:   void(this, float deltaTime, const MethodInfo*)
```

The method's observed native flow is:

```text
AdvanceTime (+0x277CD5C)
  -> get_frameRate call at +0x277D064
     return-site filter at +0x277D068
  -> current-time/frame-rate quantization
  -> PlayableExtensions.SetTime call at +0x277D194
  -> generated SetTime body at +0x2C2D9C0
  -> PlayableHandle.SetTime
```

The frame-rate getter facts are:

```text
UnityEngine.AnimationClip::get_frameRate
  metadata token: 0x06000017
  method pointer/RVA: libil2cpp + 0x4BFBBB0
  resolved icall: UnityEngine.AnimationClip::get_frameRate_Injected(System.IntPtr)
  icall cache: libil2cpp + 0x5611A78
  effective ABI: float(void* clip)
```

The `PlayableHandle` facts are:

```text
UnityEngine.Playables.PlayableHandle::SetTime(System.Double)
  metadata token: 0x06000D0C
  method pointer/RVA: libil2cpp + 0x4C6588C
  icall cache: libil2cpp + 0x5613C70
  effective ABI: void(void* handle_value, double value)

UnityEngine.Playables.PlayableExtensions::SetTime
  metadata token: 0x06000CC2
  open generic runtime method: libil2cpp + 0x21BB7D0
  specialized generated body: libil2cpp + 0x2C2D9C0
```

The relevant timing logic first scales `deltaTime` by the player time scale,
updates and wraps state time, reads the clip frame rate, and quantizes the
current time using a float32 conversion and round-to-nearest-even behavior.
The resulting value has the observed form:

```text
double(quantized_frame_index) / frameRate + 9.999999747378752e-06
```

The frozen payload calls the original `get_frameRate` first and only changes an
exact `30.0f` result when the normalized return address is exactly
`libil2cpp + 0x277D068`. It returns `60.0f` to that caller and preserves the
original `PlayableHandle.SetTime` call. Other frame-rate callers and values are
not intentionally changed.

No exact broader claim is made about every animation system or every clip in
the game; this document records the proven `AnimationPlayer.AdvanceTime` path.

## FPS-02 residual caller census additions

The direct AArch64 call-site census for this same reference image found nine
`AnimationClip::get_frameRate` `BL` sites in seven enclosing methods. The
normalized return RVAs were:

```text
SetTimeByFrame                         +0x277B104
ConnectedPlayableState::.ctor         +0x277BD84
AnimationPlayer::SwitchFrame           +0x277BF6C
AnimationPlayer::AdvanceTime           +0x277D068
Rental.RentalLotteryAnimation::CameraAnimationUpdateEvent
                                        +0x27C7D70
Timeline::TrackAsset::GetAnimationClipHash
                                        +0x4AE2988
Timeline::TimeUtility::GetAnimationClipLength
                                        +0x4B05CC4, +0x4B05CE8, +0x4B05D74
```

The exact method RVAs newly recorded by the census are:

```text
AnimationPlayer::SetTimeByFrame                 +0x277B080
ConnectedPlayableState::.ctor                   +0x277BC98
AnimationPlayer::SwitchFrame                    +0x277BE90
RentalLotteryAnimation::CameraAnimationUpdateEvent
                                                 +0x27C7CD4
Timeline::TrackAsset::GetAnimationClipHash      +0x4AE28FC
Timeline::TimeUtility::GetAnimationClipLength   +0x4B05C30
```

The `RentalLotteryAnimation::CameraAnimationUpdateEvent` method has no
explicit managed parameters; its native instance ABI is therefore
`void(this, const MethodInfo*)`. Its frame-rate call is at `+0x27C7D6C`, with
normalized return site `+0x27C7D70`.

The bounded runtime census observed two unique original-`30.0f` return sites
in the tested normal launch: `+0x277BD84` and the already proven
`+0x277D068`. The only unique live `SetTime` return site in the bounded sample
was `libil2cpp + 0x2C2DA44`, immediately after the direct call at `+0x2C2DA40`.
These runtime observations are scoped to the tested launch and do not imply
that every game scene was exercised.

## FPS-02 follow-up runtime additions

The targeted interactive session recorded the direct
`AnimationClip::get_frameRate` callsite in
`Rental.RentalLotteryAnimation::CameraAnimationUpdateEvent`:

```text
get_frameRate BL site:  libil2cpp + 0x27C7D6C
return RVA:           libil2cpp + 0x27C7D70
samples:              32
original frameRate:   60.0f for every bounded sample
sample span:          545 ms
inter-sample spacing: 14–22 ms (mean 17.581 ms)
```

The enclosing method remains the no-parameter managed method at
`libil2cpp + 0x27C7CD4`, with effective native instance ABI
`void(this, const MethodInfo*)`. The runtime entry probe for that MethodInfo
slot was not reached in this session; the direct callsite evidence above is
independent of that entry probe.

The same session's bounded `AdvanceTime` samples continued to use the exact
60-rate timing form:

```text
set_time = double(frame_index) / 60.0 + 0.000009999999747378752
```

The sampled frame indices were
`1,2,3,4,5,6,7,9,10,12,13,14,15,16,17,18,19,20,21,22,23,34,35,36`.
