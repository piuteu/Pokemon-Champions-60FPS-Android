# PERF-01 — Transient FPS Drop Audit

Date: 2026-09-03 (JST)
Branch: `experiment/perf01-transient-fps-drops`
Scope: diagnosis only. No runtime optimization, APK change, or game-binary change was made.

## Result

The corrected production capture shows a predominantly 60 Hz present cadence with intermittent missed 60 Hz slots. The observed drops are quantized to the display cadence rather than a sustained 40 FPS or 30 FPS mode:

- 23,852 unique SurfaceFlinger present timestamps / 23,851 intervals
- 16.6667 ms refresh period
- 23,274 intervals at 16.6667 ms
- 527 intervals at 33.3333 ms (one missed 60 Hz slot)
- 50 intervals of at least 40 ms
- 16 intervals of at least 80 ms
- worst interval: 333.333 ms (one 3.0 FPS-equivalent interval)
- present-timeline average: approximately 58.263 FPS
- 711 missed 60 Hz slots when the intervals are normalized to a 16.6667 ms baseline

The 577 intervals below 55, 50, 45, and 40 FPS are the same 577 quantized hitch intervals. They must not be interpreted as 577 continuous sub-40-FPS samples. The common event is a single missed slot at 33.3333 ms; the longer stalls are less frequent.

## Capture and safety boundary

The primary capture is:

```text
<repo>/build/perf/perf01_20260903_010215
```

It used the existing vanilla installation and the already-proven runtime baseline:

- package: `jp.pokemon.pokemonchampions`
- ADB serial selected dynamically: `<emulator-serial>`
- PID at start and stop: `<pid>`
- exact Unity BLAST surface: `SurfaceView[jp.pokemon.pokemonchampions/com.unity3d.player.UnityPlayerActivity](BLAST)#114`
- BlueStacks Tiramisu64, Android 13 / API 33
- guest ABI: x86_64 with ARM64 NativeBridge support (`libnb.so`)
- root remained available at stop
- no Frida was used
- no APK, split, `libil2cpp.so`, `libunity.so`, or gameplay source was modified

The capture ran for approximately 409.4 seconds of the SurfaceFlinger present timeline. SurfaceFlinger reported a 16,666,666 ns refresh period. Host UTC timestamps were recorded by every sampler for correlation.

The first long capture attempt is retained separately at:

```text
<repo>/build/perf/perf01_20260903_005308
```

It is not used as evidence because an early version of the host sampler mishandled a scalar PowerShell result. The corrected short test and the primary capture completed with zero sampler errors. The primary capture is the authoritative dataset.

## Frame interval distribution

| Present interval | Count | Interpretation |
| ---: | ---: | --- |
| 16.6667 ms | 23,274 | normal 60 Hz cadence |
| 33.3333 ms | 527 | one missed 60 Hz slot / instantaneous 30 Hz cadence |
| 50.0000 ms | 27 | two missed slots |
| 66.6667 ms | 7 | three missed slots |
| 83.3333 ms | 6 | four missed slots |
| 100.0000 ms | 1 | five missed slots |
| 116.6667 ms | 1 | six missed slots |
| 133.3333 ms | 4 | seven missed slots |
| 150.0000 ms | 1 | eight missed slots |
| 166.6667 ms | 1 | nine missed slots |
| 183.3333 ms | 1 | ten missed slots |
| 333.3333 ms | 1 | nineteen missed slots; worst observed interval |

Hitches were distributed across the session rather than confined to one short interval. Counts by local minute were 24, 141, 170, 48, 104, 35, 48, and 7 from 01:02 through 01:09 JST. The user did not provide timestamp markers for individual scene transitions or camera-motion actions, so those minute buckets cannot be assigned to a specific action.

## Correlated observations

### Guest CPU and main-thread signal

The guest sampler collected 17,600 per-thread rows from 275 top snapshots. The reported per-thread CPU value was integer-granular and capped by the selected top output; all visible thread names were the package name. Values were 0–3%, with an overall average of 1.452%.

Nearest-sample comparisons did not show a saturation signature:

- all 577 hitch intervals: top-row CPU sum average 91.71, median 91, maximum 108
- distributed good intervals: average 93.31, median 92, maximum 122
- intervals of at least 40 ms: average 90.3, median 90, maximum 106
- the sparse main-thread (`TID == PID`) observations were 0–3%; no high main-thread sample was captured

This does not prove that a short main-thread stall never occurred. The one-second/top-snapshot granularity and limited top-thread set are insufficient to resolve a 16.7 ms event.

### Host GPU

NVIDIA sampling produced 1,655 rows. GPU utilization was 7–54% (average 18.617%), and memory-controller utilization was 3–7% (average 5.005%). The nearest GPU sample to hitch intervals averaged 21.1%; only 19 hitches had a nearest sample at or above 30%, and none reached 60%.

There is no GPU saturation or draw-bound signature in this capture. Camera-motion drops therefore cannot be classified as a pure GPU bottleneck from this evidence.

### Host CPU and emulator load

The one-second Windows counter reported total host CPU of 0.08–8.16% (average 3.556%). `HD-Player` process CPU was 0–88.44% (average 26.504%). Hitch-adjacent `HD-Player` CPU was sometimes elevated (average 40.53%), but the value was also low for many hitches; for intervals of at least 40 ms the average was 29.2%, with only 5 samples at or above 50%.

This is compatible with emulator/translation or synchronization work contributing to some stalls, but it does not establish a consistent host-CPU cause. The one-second counter cannot line up reliably with an individual display interval.

### GC and memory

The target PID produced 194 `Explicit concurrent copying GC` events. Their total times averaged 5.741 ms, with a maximum of 12.054 ms; most were in the 5–7 ms range.

- 167 of 577 sub-55-FPS intervals were within ±350 ms of a target GC event
- only 14 of the 50 intervals at least 40 ms were within that window

GC can therefore be a secondary contributor to some single-slot misses, but it does not explain most longer hitches.

Guest PSS grew from approximately 545 MB to 1,088 MB and then remained broadly stable. Guest RSS ranged from 692 MB to 1,239 MB. Host available memory remained approximately 39.7–41.1 GB. No host memory-pressure signature was observed.

### Logcat and runtime baseline

The filtered target-PID log contained 693 lines, with no target crash/ANR or graphics-error evidence. The broad loading/asset/shader/texture matcher returned two lines, but manual review found no scene load, Addressables load, shader compilation, decompression, or texture-upload/warm-up event. One line was only a texture wrap-mode warning:

```text
Using mirror once texture wrap mode which is not supported by the platform...
```

One unrelated battle-update warning was observed at 01:07:13.546 JST (`Look rotation viewing vector is zero`, through `SequenceController:LateUpdate`), but there is no timestamp-aligned causal proof that it caused a hitch.

The pre-CODE-01 research runtime emitted the expected `PCFPS` records,
including 24 `ANIM_POC_FRAMERATE_REPLACED` events. Those diagnostic markers
are historical evidence only and are not present in the production payload.
The initial hook-entry burst occurred around 01:02:40; a nearby hitch is
temporal adjacency only and is not evidence that the hook caused the drop. No
later target-frame-rate reset marker was identified.

## Classification

| Class | Assessment | Evidence |
| --- | --- | --- |
| A — CPU / main thread | Not proven; remains unresolved | No per-thread saturation signal; sampling resolution is insufficient to exclude short stalls. |
| B — GPU | Not supported | GPU utilization stayed low near nearly all hitches; no saturation pattern. |
| C — asset / shader warm-up | Not observed; unresolved for action-specific windows | No corresponding load/compile/upload log; cold-vs-warm repetitions were not timestamp-labelled. |
| D — GC / memory | Secondary possible contributor, not primary | 194 regular GCs; only 14/50 long hitches were near a GC; no host memory pressure. |
| E — emulator / NativeBridge / Houdini / synchronization / frame queue | Best tentative overall fit | Cadence is quantized to 60 Hz slots despite low GPU and guest CPU signals. Scheduler/frame-queue evidence was not collected. |
| F — unresolved | Applies to the exact scene/camera root cause | User action markers and a scheduler/frame timeline are still missing. |

For scene transitions, the result is `C/F`: the capture does not show asset/shader warm-up, but it cannot separate cold and warm transition windows. For camera motion, the result is `E/F`: no pure GPU signature was observed, while CPU culling/animation versus emulator/translation/synchronization cannot be separated with the available sampling.

## Limitations and next experiment

No runtime telemetry or FPS optimization was added for PERF-01. The user operated the game during the capture, but no explicit action timestamps were recorded. Consequently, this audit cannot claim that a particular hitch occurred during a particular scene transition, camera movement, cold load, or warm repeat.

A follow-up should require PM approval and add only measurement capability: explicit manual action markers plus a Perfetto/ftrace scheduler and frame-timeline capture (or an equivalent Unity Profiler trace). That would test the tentative E classification and resolve whether the remaining events are CPU scheduling, NativeBridge/Houdini synchronization, frame queue back-pressure, or an action-specific C/A path. No optimization is justified by PERF-01 alone.

## Repository artifacts

Tracked diagnostic tooling is under `scripts/perf/`. Derived captures and reports under `build/perf/` are ignored and remain raw evidence. The primary session contains:

```text
perf01_surface.csv
perf01_surface_intervals.csv
perf01_hitch_windows.csv
perf01_surface_summary.json
perf01_guest_cpu.csv
perf01_guest_top.log
perf01_host_gpu.csv
perf01_host_cpu.csv
perf01_memory.csv
perf01_logcat.log
perf01_logcat_error.log
perf01_surface_final.txt
perf01_status.json
perf01_controller.err.log
perf01_controller.out.log
perf01-sample-guest.ps1.err.log
perf01-sample-guest.ps1.out.log
perf01-sample-host-cpu.ps1.err.log
perf01-sample-host-cpu.ps1.out.log
perf01-sample-host-gpu.ps1.err.log
perf01-sample-host-gpu.ps1.out.log
perf01-sample-memory.ps1.err.log
perf01-sample-memory.ps1.out.log
perf01-sample-surface.ps1.err.log
perf01-sample-surface.ps1.out.log
```
