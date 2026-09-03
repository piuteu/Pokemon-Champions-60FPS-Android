# FPS-02 — Residual 30Hz Visual-System Audit

This audit covers the extracted Google Play Pokémon Champions Android 1.1.5
reference and the runtime-only ARM64 guest payload. The audit branch is
`experiment/residual-30hz-audit`, based on
`<private-history-not-migrated>`.

## Result summary

The census found nine direct `AnimationClip::get_frameRate` call sites in
`libil2cpp.so`, belonging to seven enclosing managed methods. The only
confirmed visual 30 Hz evaluation-grid bottleneck remains the already proven
`SmartPoint.Components.AnimationPlayer::AdvanceTime` path. Its exact caller
filter and original-function-preserving replacement were retained.

No additional A-class fix was safe to add from the available evidence. In the
follow-up session the Rental camera direct callsite was observed with an
original 60-rate value and was reclassified as session-scoped `B*`; its
authored key-domain equation remains unchanged. The sprite and other custom
visual paths still lack the live evidence needed to leave D-class status, and
none were changed speculatively.

The initial diagnostic launch observed two unique live callers returning an
original `30.0f` frame rate and one unique `SetTime` caller. The follow-up
interactive sweep also exercised the Rental camera getter callsite: its active
clip returned an original `60.0f` for all 32 bounded samples at approximately
60 Hz. The `SetTime` samples after initial graph setup advanced on an
approximately 1/60-second grid; the duplicated 30 Hz pattern was not observed
in that path. The follow-up was user-driven and did not emit scene IDs, so it
does not prove universal gameplay, camera, effect, menu, or result-scene
coverage. Unobserved systems are explicitly marked D below.

## Reference inputs

The canonical extraction was:

```text
<game-extraction-dir>/pokemonchampions_1.1.5
```

The files used for the static census were:

| File | Size | SHA-256 |
| --- | ---: | --- |
| `base\assets\bin\Data\Managed\Metadata\global-metadata.dat` | 14,613,732 | `565C9747771E2436995B1B9EF5DD75E4184ACE2EC42120396C0578A3CBB5D957` |
| `split_config.arm64_v8a\lib\arm64-v8a\libil2cpp.so` | 90,150,888 | `0A927341D12682592AB7056FF3EE526C01073F1EC92CB6C0A67DFC9370DBEF19` |
| `split_config.arm64_v8a\lib\arm64-v8a\libunity.so` | 27,858,008 | `CC6202017E6F45CC85CD9FA840462A7E3CF71852645AFAAE94A26EDBD284241F` |

Both shared libraries are ELF64 AArch64 `ET_DYN` images. The metadata magic is
`0xfab11baf` and its metadata version is 31. No comparison copies such as
`libil2cpp_60fps.so` were used.

An asset bundle scan found 2,540 bundle entries but no decoded
`AnimationClip` objects. All 2,540 entries produced decompression/encryption
parse warnings, so that scan is not evidence about authored clip rates.

## Static `AnimationClip::get_frameRate` census

The wrapper is at `libil2cpp + 0x4BFBBB0`. The table lists every direct AArch64
`BL` to that wrapper found in the reference image. The return RVA is the
normalized caller address observed by the runtime hook: the instruction after
the `BL`.

| BL call site | Return RVA | Enclosing method | Timing interpretation | Classification / action |
| ---: | ---: | --- | --- | --- |
| `+0x277B100` | `+0x277B104` | `AnimationPlayer::SetTimeByFrame`, method RVA `+0x277B080`, token `0x06006e07` | Integer frame index is divided by `clip.frameRate` and written as playable time. This is an explicit frame-addressing operation, not a periodic update loop. | C — preserve authored frame addressing; no change. |
| `+0x277BD80` | `+0x277BD84` | `ConnectedPlayableState::.ctor`, method RVA `+0x277BC98`, token `0x06006e2d` | Reads/stores clip frame rate during playable-state construction, alongside clip length and loop state. No visual update quantizer. | B — initialization/authored metadata; no change. |
| `+0x277BF68` | `+0x277BF6C` | `AnimationPlayer::SwitchFrame`, method RVA `+0x277BE90`, token `0x06006e16` | Integer frame argument is converted to playable time and sent through `SetTime` for an intentional frame switch. | C — preserve explicit frame switch semantics; no change. |
| `+0x277D064` | `+0x277D068` | `AnimationPlayer::AdvanceTime`, method RVA `+0x277CD5C`, token `0x06006e21` | Reads the live clip rate inside the per-update path and quantizes current time to a frame grid. | A — existing exact caller-only 30→60 replacement retained. |
| `+0x27C7D6C` | `+0x27C7D70` | `Rental.RentalLotteryAnimation::CameraAnimationUpdateEvent`, method RVA `+0x27C7CD4`, token `0x0600104c` | Uses rate × clip length × normalized time, floors it, and feeds the resulting index to `AnimationCurve::Evaluate`. This may be an authored camera key domain rather than a 30 Hz limiter. | D — camera visual candidate; no change without live and asset-domain proof. |
| `+0x4AE2984` | `+0x4AE2988` | `UnityEngine.Timeline.TrackAsset::GetAnimationClipHash`, method RVA `+0x4AE28FC`, token `0x060001ad` | Uses clip rate while computing a Timeline/authored-data hash. | B — metadata/hash path; no change. |
| `+0x4B05CC0` | `+0x4B05CC4` | `UnityEngine.Timeline.TimeUtility::GetAnimationClipLength`, method RVA `+0x4B05C30`, token `0x0600037d` | Converts length/rate to a frame count, rounds it, then converts back to duration. | B — authored duration utility; no change. |
| `+0x4B05CE4` | `+0x4B05CE8` | `UnityEngine.Timeline.TimeUtility::GetAnimationClipLength`, same method | Second rate read in the same duration calculation. | B — authored duration utility; no change. |
| `+0x4B05D70` | `+0x4B05D74` | `UnityEngine.Timeline.TimeUtility::GetAnimationClipLength`, same method | Third rate read in the same duration calculation. | B — authored duration utility; no change. |

Therefore the static total is **9 direct call sites / 7 enclosing methods**.
An indirect function-pointer use, if any, is not counted as a direct BL site;
the runtime caller census below is the authoritative live observation for the
tested process.

## Playable `SetTime` census

The managed `PlayableHandle::SetTime(System.Double)` wrapper is at
`libil2cpp + 0x4C6588C`, with icall cache entry `+0x5613C70`. The generated
specialized `PlayableExtensions::SetTime` body used by the proven animation
path is at `+0x2C2D9C0`; the open generic runtime method is at `+0x21BB7D0`.

Static direct call sites into the `PlayableHandle::SetTime` wrapper were:

| Direct BL site | Generated/enclosing path |
| ---: | --- |
| `+0x2C2DA40` | specialized body `+0x2C2D9C0` |
| `+0x2C2DAFC` | generated body `+0x2C2DA58` |
| `+0x2C2DC04` | generated body `+0x2C2DB14` |
| `+0x4C06920` | native helper path beginning at `+0x4C06790` |

The specialized body at `+0x2C2D9C0` also has nine direct callers, including
`GaugeAnimation::SetValue`, `GaugeAnimation::Awake`, `UIAnimator::Initialize`,
`UIAnimator::ProcessRequests`, `ConnectedPlayableState::.ctor`,
`AnimationPlayer::SwitchFrame`, and `AnimationPlayer::AdvanceTime`. The
generated bodies pass a `double` to the Unity native icall; they do not impose
the 30 Hz quantizer themselves.

The runtime caller address for the proven path was:

```text
SetTime BL site:  libil2cpp + 0x2C2DA40
return address:  libil2cpp + 0x2C2DA44
```

## Explicit quantizer and timing findings

### `AnimationPlayer::AdvanceTime` — confirmed A

The relevant sequence is equivalent to:

```text
scaled_time = update_and_wrap(deltaTime * timeScale)
frame_rate = clip.get_frameRate()
frame_value = float32(scaled_time * frame_rate)
quantized_frame = round_to_nearest_even(frame_value)
set_time(double(quantized_frame) / frame_rate + 0.000009999999747378752)
```

The exact getter return-site filter is `libil2cpp + 0x277D068`. The existing
payload calls the original getter first and changes only an exact original
`30.0f` result at that return site to `60.0f`. It then preserves the original
`SetTime` call. Time scale, wrapping, duration, events, and transitions are
not suppressed or globally rewritten.

### `RentalLotteryAnimation::CameraAnimationUpdateEvent` — possible visual D

The native sequence is equivalent to:

```text
frame_key = floor(clip.frameRate * clip.length * normalizedTime)
curve_value = cameraCurve.Evaluate(frame_key)
camera.focusDistance = curve_value
```

The floor operation is at approximately `+0x27C7FF8` after the
`get_frameRate` call. This is a real discrete camera-key lookup, but changing
30 to 60 could make a curve authored for 30 keys receive 60-key coordinates,
changing camera behavior or duration. The caller did not appear in the
tested launch's live frame-rate table. It remains D.

### `AnimationPlayer::SetTimeByFrame` — intentional C

The relevant logic is:

```text
frame_time = float(frame_index) / clip.frameRate
state.time = double(frame_time)
PlayableExtensions.SetTime(handle, state.time)
```

This method is called by an explicit frame-index API. Replacing its rate would
change the meaning of a requested authored frame, so it is not a safe way to
raise a periodic visual update rate.

### `AnimationPlayer::SwitchFrame` — intentional C

The method similarly converts an integer frame selection to time, then sends
the result through generated `SetTime` paths at `+0x277BF94` and
`+0x277C020`. It is a frame jump/switch operation, not evidence of a duplicated
30 Hz update loop. It remains unchanged.

### `Timeline.TimeUtility::GetAnimationClipLength` — authored B

The stock Timeline utility reads `length` and `frameRate`, computes an
integer-like frame count using round-to-nearest-even branches, and divides by
the rate again. This preserves authored clip duration and is not a render
tick. It remains unchanged to protect the two-second-duration invariant.

### Other explicit timing math

The following code patterns were inspected:

| System/method | Exact native location | Observed/static equation | Classification / action |
| --- | ---: | --- | --- |
| `.SpriteAnimationController::Update` | `+0x2289350` | Reads `Time.deltaTime`, multiplies by `_primarySpeed`/secondary speed, and floors a texture-sheet frame index. No fixed 30 literal or proven 30-valued speed was found. | D — texture-sheet candidate; no change. |
| `.UIAnimator::OnAfterUpdate` | `+0x247540C` | Wraps a continuously accumulated time by a duration/interval using division, floor, multiplication, and subtraction. No `get_frameRate` or fixed 30 operand was found. | D — UI timing candidate; no change. |
| `PKBUI.PokeIconAnimation::IconAnimationUpdate` | `+0x233E358` | Continuous add/divide time and RectTransform updates; no round/floor frame grid was found. | B — no 30 Hz quantizer; no change. |
| `PKBUI.TweenAnimationPlayer::OnUpdateGlobalTime` / `OnUpdateLocalTime` | `+0x2369F70` / `+0x236A04C` | Uses `Time.time`, property evaluation, and continuous additions. | B — continuous tween path; no change. |
| `Effect.ParticleSystemController::OnUpdate` / `SetSpeed` | `+0x2589AE4` / `+0x2589670` | Reads Animator state/normalized time; speed setter multiplies and assigns `Animator.speed`. No fixed 30 grid. | B — Animator/effect path has no proven residual 30 Hz; no change. |
| `PKB.EventScript.EventScriptCamera::UpdateMove` / `UpdateFocusDistanceChange` | `+0x25E3F94` / `+0x25E41A4` | Delegates camera motion/focus updates to helpers; no direct fixed-rate quantizer in the inspected bodies. | D — camera helper coverage incomplete; no change. |
| `PKB.Battle.UserInterface.BattleUIAnimSequencerModule::AnimationUpdate` | `+0x26C1290` | Calls Animator play and animation-finished checks; no explicit 30 Hz arithmetic. | B — no quantizer found; no change. |
| `PKB.Battle.Sequence.RuntimePlayAnimationData::onUpdate` | `+0x26C6400` | Reads character animation state/name and completion state, then advances a float. No explicit frame-rate quantizer. | C — sequence/event state must remain stock; no change. |
| `PKB.Battle.Sequence.BattleCameraPlayer::UpdateTrack` / `LateUpdateTrack` | `+0x26D8958` / `+0x26D8970` | No relevant fixed-rate FP arithmetic in the inspected bodies. | D — camera scene coverage incomplete; no change. |
| `EventKeyEx::Evaluate` overloads | `+0x227AAC8`, `+0x227AC48`, `+0x227ADE8`, `+0x227B028` | Interpolation/event-key math includes rounding in one overload, but no fixed 30 operand was established. | C — preserve event timing; no change. |
| `UIAnimator::Initialize` / `ProcessRequests` and `GaugeAnimation` SetTime callers | `+0x2474640`, `+0x2474C8C`, `+0x23509A8`, `+0x23510D8` | Call generated Playable `SetTime`, but no frame-rate read or 30 Hz quantization was found. | D — call paths observed statically only; no change. |

No modification was made to `Time.fixedDeltaTime`, physics, gameplay timing,
networking, input, timers, or any global `30 → 60` value.

## Runtime caller census

The payload was rebuilt with bounded diagnostics. It records at most 32 unique
frame-rate callers, rate-limits frame-rate log events to 128, and records at
most 96 `SetTime` samples. During the census, only the already proven
`+0x277D068` caller was allowed to receive `60.0f`; every other original value
was returned unchanged.

Runtime environment:

```text
ADB serial:       <offline-emulator-serial> (state=device; <offline-emulator-serial> was offline)
Android API:      33 / Tiramisu
process:          normal Pokémon Champions launch, PID <pid>
ABI list:         x86_64,x86,arm64-v8a,armeabi-v7a,armeabi
NativeBridge:     libnb.so (Houdini path)
payload ABI:      AArch64 guest, sizeof(void*)=8
```

### Observed `30.0f` callers

| Return RVA | Runtime hits observed | Resolved method | Original value | Classification |
| ---: | ---: | --- | ---: | --- |
| `libil2cpp + 0x277BD84` | 1 | `ConnectedPlayableState::.ctor` | 30.0 | B — state initialization |
| `libil2cpp + 0x277D068` | at least 2,752 in the rate-limited log | `AnimationPlayer::AdvanceTime` | 30.0 | A — effective value replaced with 60.0 |

The total number of unique live `30.0f` caller sites in this session was
**2**. No `+0x27C7D70` camera caller was observed during this normal-launch
exercise. The process was force-stopped after the bounded run, so Android did
not emit the library destructor's final table; the `AdvanceTime` count above is
therefore a logged lower bound, while the unique-caller result is based on all
`NEW` records in the bounded session.

### Observed `SetTime` sequence

The only unique live caller in the bounded sample was:

```text
return RVA: libil2cpp + 0x2C2DA44
```

The first samples were graph-initialization zeros. After startup, the values
included:

```text
0.016676666666414045
0.033343333333080712
0.050009999999747382
0.066676666666414044
...
0.95000999999974733
```

This is a continuous approximately 1/60-second sequence, not the duplicated
`0.000, 0.000, 0.0333, 0.0333` pattern. This observation supports the
existing `AdvanceTime` A-class fix but does not establish coverage for every
scene or every custom visual system.

## FPS-02 follow-up — targeted interactive runtime sweep

Session ID: `fps02_interactive_sweep_20260903_001049`

The raw, unfiltered logcat dump is retained locally at:

```text
build/logs/fps02_interactive_sweep_20260903_001049.log
```

The host-side dump was taken on 2026-09-03 at 00:10:49 JST without clearing
logcat at the end of the user session. The selected ADB serial was
`<emulator-serial>` (`device`); `<emulator-serial>` was ignored because it was
`offline`. The target process was `jp.pokemon.pokemonchampions`, PID `<pid>`.
The first and last PCFPS records were device timestamps
`09-02 23:58:33.848` and `09-03 00:04:53.429`, a diagnostic event window of
379.581 seconds (approximately 6 minutes 19.6 seconds). The process was still
present after the dump.

### Scene coverage

The application was operated manually after the fresh-process bootstrap. The
requested sweep included the home/menu flow, trainer/human animation, battle,
camera/effect, dialogue/gauge, and result/transition paths, but the runtime
logger did not capture scene names or UI state. Therefore the exact set of
visited scenes cannot be proven from this artifact. The only scene-specific
runtime evidence in this session is the Rental camera getter callsite described
below; this is not a claim of game-wide coverage.

### D-class entry probes and direct-call evidence

The fresh preinteractive validation reported all seven MethodInfo pointer
probes installed. Because the logcat buffer was cleared before the user-driven
part, installation records are not expected in the raw sweep log. During the
interactive window, however, the log contained **zero**
`VISUAL_DIAG_METHOD` records and **zero** `VISUAL_DIAG_SPRITE_STATE` records:

| Candidate | Method RVA | Entry hits in interactive log | Disposition after this sweep |
| --- | ---: | ---: | --- |
| `Rental.RentalLotteryAnimation::CameraAnimationUpdateEvent` | `+0x27C7CD4` | 0 | `B*` — its direct getter return site was live at 60 Hz; MethodInfo entry probe was not reached |
| `.SpriteAnimationController::Update` | `+0x2289350` | 0 | `D` — no live entry or derived sprite state |
| `.UIAnimator::OnAfterUpdate` | `+0x247540C` | 0 | `D` — no live entry or output-state evidence |
| `PKB.EventScript.EventScriptCamera::UpdateMove` | `+0x25E3F94` | 0 | `D` — no live entry evidence |
| `PKB.EventScript.EventScriptCamera::UpdateFocusDistanceChange` | `+0x25E41A4` | 0 | `D` — no live entry evidence |
| `PKB.Battle.Sequence.BattleCameraPlayer::UpdateTrack` | `+0x26D8958` | 0 | `D` — no live entry evidence |
| `PKB.Battle.Sequence.BattleCameraPlayer::LateUpdateTrack` | `+0x26D8970` | 0 | `D` — no live entry evidence |

The zero entry-probe result is not treated as proof that the methods never ran:
the Rental candidate's direct `AnimationClip::get_frameRate` return site was
observed independently. A direct AOT call can bypass the MethodInfo pointer
slot used by the diagnostic entry probe.

The Rental camera return site `libil2cpp + 0x27C7D70` produced 32 consecutive
bounded samples from `00:04:52.884` through `00:04:53.429`. Every sample had
`original=60`; inter-sample intervals were 14–22 ms, mean 17.581 ms, over a
545 ms span. This is live 60-rate camera-key-domain activity, not evidence of
a 30 Hz hold. The `B*` label is session-scoped: it does not guarantee that all
other camera clips are authored at 60 or that the camera method is universally
covered.

### Consecutive animation samples (historical diagnostic evidence)

The bounded caller and `SetTime` records in this section were collected by the
FPS-02 diagnostic build. They remain for research traceability; the production
payload does not emit these records.

The live frame-rate caller table recorded:

```text
+0x277BD84: NEW original=30, hits=1
+0x277D068: NEW original=30, hits=1; 126 bounded UPDATE records,
             hits=64, 128, ..., 8064
```

The existing caller-only replacement emitted 24
`ANIM_POC_FRAMERATE_REPLACED` records for `+0x277D068`, each reporting an
effective rate of `60`. The repeated caller count is not itself a rendered-FPS
measurement; `AdvanceTime` can run for multiple animation states per display
update.

The 24 bounded active `SetTime` samples on the already identified
`libil2cpp + 0x2C2DA44` return path reconstructed the following quantized frame
index sequence:

```text
1, 2, 3, 4, 5, 6, 7, 9, 10, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 34, 35, 36
```

Their values ranged from `0.016676666666414045` through
`0.6000099999997474` and matched the 60-rate form:

```text
set_time = double(frame_index) / 60.0 + 0.000009999999747378752
```

Most consecutive indices advanced by one. The observed gaps of 2 and 11
coincided with sampled scaled deltas of approximately 33.333 ms and
183.333 ms; no duplicated 30 Hz index/hold sequence appeared. These are the
first 24 bounded samples, not a claim that every call during the whole session
was logged.

### Reclassification and implementation result

`AnimationPlayer::AdvanceTime` remains the only A-class path. The Rental
camera candidate is promoted from D to session-scoped `B*` because its direct
callsite was live with an original 60-rate value and approximately 60 Hz
spacing, while its authored key-domain equation remains unchanged. Sprite,
UIAnimator, EventScript camera, Battle camera, and indirect UI/Gauge SetTime
paths remain D because this session supplied no corresponding live entry/state
evidence. No new A-class path was proven, so no new functional fix was added.

No new visible 30 Hz hold was reported during the user-driven sweep, and the
diagnostic `SetTime` sequence did not show the prior duplicated-30 pattern.
This result is limited to the observed process/session and is not a universal
game-wide coverage claim.

## Candidate decision table

The following is the consolidated disposition of all investigated candidates.

| System/method | RVA/callsite | Evidence | Observed update rate | Class | Action | Validation result |
| --- | --- | --- | --- | :---: | --- | --- |
| `AnimationPlayer::AdvanceTime` | `+0x277CD5C`, getter return `+0x277D068` | float32 + round-to-even frame quantization; exact 30 rate observed | SetTime sequence approximately 60 Hz after hook | A | Retain exact caller-only original-result replacement 30→60 | Hook installed; no crash; smooth trainer/human path and approximately 60 Hz presentation retained |
| `ConnectedPlayableState::.ctor` | getter return `+0x277BD84` | stores authored rate/length during construction | one initialization hit | B | None | Observed once; no update-loop change |
| `AnimationPlayer::SetTimeByFrame` | `+0x277B080`, getter return `+0x277B104` | explicit integer frame → time conversion | on-demand frame addressing | C | None | Static semantics preserved |
| `AnimationPlayer::SwitchFrame` | `+0x277BE90`, returns `+0x277BF6C` | explicit integer frame switch → `SetTime` | on-demand frame switching | C | None | Static semantics preserved |
| Rental lottery camera update | `+0x27C7CD4`, getter return `+0x27C7D70` | floor(rate × length × normalizedTime) used as curve key; live active clip returned original 60 | 32 samples, 14–22 ms spacing | B* | None | Direct callsite live at 60; no 30 replacement; MethodInfo entry probe did not hit |
| Timeline `TrackAsset::GetAnimationClipHash` | `+0x4AE28FC`, return `+0x4AE2988` | authored hash calculation | metadata-only | B | None | No playback mutation |
| Timeline `TimeUtility::GetAnimationClipLength` | `+0x4B05C30`, returns `+0x4B05CC4/+0x4B05CE8/+0x4B05D74` | frame-count round-trip preserves duration | utility call | B | None | Duration invariant protected |
| `.SpriteAnimationController::Update` | `+0x2289350` | texture-sheet floor/index math; runtime speed unknown | not observed | D | None | No fixed 30 evidence |
| `.UIAnimator::OnAfterUpdate` | `+0x247540C` | wrap/interpolation arithmetic; no fixed 30 | not observed | D | None | No safe callsite-specific replacement |
| `PokeIconAnimation::IconAnimationUpdate` | `+0x233E358` | continuous time and transform updates | not live-instrumented | B | None | No quantizer found |
| `TweenAnimationPlayer` global/local update | `+0x2369F70/+0x236A04C` | continuous time/property evaluation | not live-instrumented | B | None | No quantizer found |
| `ParticleSystemController` update/speed | `+0x2589AE4/+0x2589670` | Animator normalized time and speed; no 30 grid | not live-instrumented | B | None | No quantizer found |
| Event-script camera helpers | `+0x25E3F94/+0x25E41A4` | helper calls; direct body has no fixed rate | not observed | D | None | Coverage insufficient for a safe change |
| Battle UI animation sequencer | `+0x26C1290` | Animator play/finished checks; no 30 arithmetic | not live-instrumented | B | None | No quantizer found |
| Runtime play-animation sequence state | `+0x26C6400` | animation state/event progression | not observed | C | None | Event/state semantics preserved |
| Battle camera track update | `+0x26D8958/+0x26D8970` | no relevant fixed-rate arithmetic in inspected bodies | not observed | D | None | Coverage insufficient |
| `EventKeyEx::Evaluate` | `+0x227AAC8/+0x227AC48/+0x227ADE8/+0x227B028` | event/interpolation rounding without fixed 30 | not observed | C | None | Event timing preserved |
| UI/Gauge generated `PlayableExtensions.SetTime` callers | `+0x23509A8/+0x23510D8/+0x2474640/+0x2474C8C` | SetTime calls without frame-rate quantizer | one SetTime caller observed in initial scene; other callers not live-hit | D | None | No evidence for safe conversion |

## Gate F implementation and invariants

No new A-class path was implemented. The only effective runtime change remains:

```text
original AnimationClip.get_frameRate()
    -> if original == 30.0f and return site == libil2cpp + 0x277D068
    -> report 60.0f to AnimationPlayer::AdvanceTime
    -> preserve original downstream SetTime and all other behavior
```

The FPS-02 source change adds bounded caller diagnostics only. It does not
change the targetFrameRate hook, the existing `AdvanceTime` replacement, the
original icalls, or any APK/library in the extraction. No global frame-rate
hook was introduced.

The diagnostic payload was built directly with the existing NDK ARM64 clang
toolchain. No Android Studio, Gradle, CMake, Ninja, APK repackaging, or signing
step was used.

## Display-side support

`Surface.setFrameRate()` was not added. Display policy is treated as separate
support only; it is not used as evidence that any game-side visual system is
rendering unique frames at 60 Hz.

## Regression and limits

- The ARM64 constructor and `JNI_OnLoad` proof remained present after the
  diagnostic extension.
- Target-frame-rate hook installation and the existing `AdvanceTime` hook
  remained present after a fresh process launch.
- The normal launch produced no observed crash in the bounded run, and the
  payload's original functions continued to execute.
- The interactive log contained Unity warnings for `Invalid Layer Index '-1'`
  and `Animator.GotoState: State could not be found`, but no
  `FATAL EXCEPTION`, SIGSEGV, tombstone, or ANR record. The log alone does not
  establish a causal link between those warnings and the payload.
- The payload was reloaded under a new process PID during the restart check.
- The interactive sweep did not emit scene IDs and did not exercise every
  validation scene in a machine-verifiable way. Sprite, special-effect, menu,
  result-scene, EventScript-camera, and Battle-camera D entries remain
  unproven. The Rental camera result is limited to the observed direct
  callsite/active clip.
- A destructor final-table line is not treated as required evidence because an
  Android force-stop terminates the process before normal shared-library
  teardown. Rate-limited `NEW`/`UPDATE` records and bounded samples were used
  instead.

## Artifacts

At the time of this audit the runtime payload was:

```text
build/libpcfps_runtime.so
SHA-256: 273273dfdacd9edca44fff91c07513f31aefe6dc089aca1f05dbaf117d258b82
```

The same payload hash was verified after staging in the rooted runtime module.
The repository does not contain the extracted game files or a modified APK.
