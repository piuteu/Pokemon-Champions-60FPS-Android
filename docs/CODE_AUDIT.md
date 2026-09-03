# CODE-01 — Production Runtime Audit and Cleanup

Date: 2026-09-03
Branch: `audit/code-01-runtime-cleanup`
Base: `<private-history-not-migrated>`

This audit inventories the runtime-only 60 FPS implementation before
publication. It removes development residue while preserving the proven
runtime path, version guard, fail-open behavior, and ReZygisk/NativeBridge
bootstrap. It does not add a feature or alter APK/game files.

Classification counts below are grouped audit records, not source lines or
individual compiler symbols. An item is counted by its primary purpose even
when it also provides a safety property.

| Class | Count | Meaning |
| --- | ---: | --- |
| P | 7 | Production runtime/build/package records retained |
| S | 5 | Safety, validation, cleanup, and fail-open records retained |
| R | 3 | Deliberate research/documentation records retained outside runtime |
| D removed | 7 | Development residue records removed |
| U retained | 1 | Startup behavior retained because removal was not evidence-supported |

## Scope

Audited tracked files and paths:

- `src/pc_fps_runtime.cpp`
- `bootstrap/pcfps_zygisk_bootstrap.cpp`
- `bootstrap/zygisk.hpp`
- `bootstrap/auto-bootstrap-module.prop`
- superseded `bootstrap/pcfps_zygisk_probe.cpp`,
  `bootstrap/pcfps_zygisk_lifecycle_probe.cpp`, `bootstrap/module.prop`, and
  `bootstrap/lifecycle-module.prop`
- `scripts/build.ps1`, `scripts/build-zygisk-bootstrap.ps1`,
  `scripts/package-zygisk-module.ps1`
- superseded `scripts/build-zygisk-probe.ps1` and
  `scripts/build-zygisk-lifecycle-probe.ps1`
- all `scripts/perf/*` tooling
- `README.md` and all tracked documents under `docs/`
- `.gitignore`

The generated `build/` tree is ignored. It was inspected as build/package and
runtime evidence but is not part of the production module or the commit.

## Baseline

The baseline was built at commit
`<private-history-not-migrated>` before production files were
modified. The local snapshot is:

```text
<repo>/build/audit/code01_before
```

| Artifact | Size | SHA-256 |
| --- | ---: | --- |
| `libpcfps_runtime.so` | 25,816 bytes | `65019ab1291795a287b9d87a7d9571d4530502449c09bddce47f5a389aa688b3` |
| `libpcfps_zygisk_auto_bootstrap_x86_64.so` | 431,080 bytes | `a29c68e56f04fac8d51adfa0e345e03e05688958ee47fffe2806c1775c7f890f` |
| `pcfps_zygisk_auto_bootstrap.zip` | 138,476 bytes | `d13f4a41150ea3d5d11919ee676c7d8ab2b033e0a36d3400c9930b1d0dbf798e` |

Baseline build used the existing direct NDK clang path:

```text
<android-ndk>
clang 18.0.4 / revision 27.3.13750724
```

The baseline normal-launch sample used the vanilla package at version
`1.1.5` / `versionCode=3191`, with 742 total logcat lines, 66 payload-tag
lines, 10 bootstrap-tag lines, and 39 diagnostic/synthetic marker lines.
No fatal exception, ANR, or signal was present in that sample.

## File Inventory

| Path/group | Classification | Decision |
| --- | --- | --- |
| `src/pc_fps_runtime.cpp` | P/S | Retain; clean production hooks and runtime checks. |
| `bootstrap/pcfps_zygisk_bootstrap.cpp` | P/S | Retain; clean automatic staging and loader. |
| `bootstrap/zygisk.hpp` | P | Retain; required public Zygisk ABI header. |
| `bootstrap/auto-bootstrap-module.prop` | P | Retain; only production module metadata. |
| Production build/package scripts | P | Retain; direct NDK build and minimal ZIP packaging. |
| `scripts/perf/*` | R | Retain as research tooling; not packaged or referenced by binaries. |
| Existing research/audit documents and `README.md` | R | Retain as historical evidence and maintenance documentation. |
| Old probe/lifecycle source, metadata, and builders | D | Remove; completely superseded by automatic bootstrap. |
| `.gitignore` | S | Retain; keeps binaries, captures, and game data out of the repository. |

## Function / Path Classification

### Production Required (P)

- `hook_target_frame_rate`: preserves the original Unity icall and changes
  only requested values `30` and `-1` to effective `60`. Other values pass
  through unchanged.
- `hook_animation_get_frame_rate`: calls the original getter and changes an
  exact `30.0f` result only when the return address is the proven
  `AnimationPlayer.AdvanceTime` caller site at
  `libil2cpp + 0x277D068`. Unrelated callers and non-30 values are unchanged.
- `resolve_and_install_hook`: resolves the known icall resolver and installs
  the two production cache hooks without patching game instructions.
- The ARM64 constructor and `JNI_OnLoad` entry points are required for the
  staged payload to execute through `Runtime.load0` and NativeBridge/Houdini.
- The x86_64 Zygisk module filters the exact package, stages the unchanged
  ARM64 payload, and starts the post-specialization worker.
- The direct NDK build and package scripts produce the only supported module
  layout.

### Safety Required (S)

- `/proc/self/maps` parsing and library/mapping identity checks protect all
  hardcoded cache accesses.
- Both target and animation cache locations are required to be readable and
  writable; original/cache target consistency and post-write verification are
  required before a hook is considered installed.
- The bootstrap verifies source hashing, non-empty ELF64 AArch64 format,
  destination size/hash, atomic temporary-file replacement, ownership, mode,
  and final hash.
- The bootstrap requires package `jp.pokemon.pokemonchampions`, version name
  `1.1.5`, and version code `3191` before loading the payload. Readiness waits
  for `libil2cpp.so`, `libunity.so`, and the initialized target icall cache.
- JNI exception clearing, local-reference cleanup, VM attach/detach, bounded
  polling, `Runtime.load0` exception handling, and non-target
  `DLCLOSE_MODULE_LIBRARY` behavior remain in place.
- All failure branches leave the game running without applying stale hooks and
  emit a concise operational reason where applicable.

### Research Retained (R)

- `scripts/perf/*` remains available for transient FPS investigations. No
  production source or package path references it, and the packaging script
  copies only `module.prop`, `zygisk/x86_64.so`, and
  `payload/libpcfps_runtime.so`.
- Existing documents preserve extraction facts, hook research, validation
  history, and PERF-01 evidence. Their historical marker names do not execute
  in the cleaned runtime.
- Local files under `build/audit/` and `build/perf/` are evidence only and are
  ignored by Git.

### Development Residue Removed (D)

The following had no product-correctness or safety role after the paths were
proven:

- `log_probe`, float/double/pointer formatting helpers, and repeated pointer or
  register logging.
- `AnimationDiagnosticContext`, TLS state, diagnostic counters, sample limits,
  ARM64 register reads, SetTime sampling, and delta/time estimation.
- The `PlayableHandle.SetTime` cache hook. The game continues to call Unity's
  original SetTime implementation; the required animation behavior is the
  caller-scoped frame-rate return replacement.
- IL2CPP assembly/class/method reflection enumeration and parameter/token/RVA
  dumps.
- Synthetic managed calls for requested `30` and `-1`.
- Per-call targetFrameRate logging and PoC/probe naming that existed only to
  prove behavior during development.
- Historical x86_64 probe and lifecycle source files, module metadata, and
  builder scripts.

### Uncertain / Retained (U)

`g_original_target_frame_rate(60)` immediately after the target hook is
installed remains as `HOOK_INITIAL_SET effective=60`. The loader deliberately
waits for the initialized icall cache, and the initial call may stabilize the
runtime before the first ordinary managed request. There was no evidence that
it was redundant, so it was not removed during a cleanup audit.

## Fallback Inventory

| Fallback/guard | Trigger | Protection and failure behavior | Decision |
| --- | --- | --- | --- |
| Exact package filter | Zygisk specialization is not the target package | Requests module close and performs no staging or logging for non-target processes. | Retain. |
| JNI input/application lookup | Missing `JNIEnv`, application, or pending exception | Clears the exception where possible and returns without loading the payload. | Retain. |
| Module source validation | Missing module FD/path, hash failure, zero size, or non-ARM64 ELF | Stops staging and leaves the app stock. | Retain. |
| Existing destination reuse | Destination size and SHA match source | Reuses it after restoring owner/mode; avoids unnecessary copying. | Retain. |
| Atomic replacement | Destination is absent or hash differs | Copies to a private temporary file, verifies hash, renames, then verifies again. | Retain. |
| Version lookup polling | Application/package metadata is not ready immediately | Retries for a bounded period; unsupported/error/timeout detaches and does not load. | Retain. |
| Library readiness polling | `libil2cpp.so` or `libunity.so` is not mapped | Retries for a bounded period; timeout is fail-open. | Retain. |
| icall cache readiness polling | Target cache is not mapped, writable, or initialized | Retries for a bounded period; timeout is fail-open. | Retain. |
| Runtime caller-class fallback | Unity activity class cannot be loaded from the application ClassLoader | Uses the application class for `Runtime.load0`, preserving the proven app-loaded loader path where available. | Retain; compatibility fallback. |
| Runtime/load0 exception handling | `Runtime.load0` or JNI call throws | Logs the concise failure, describes/clears the pending exception, releases references, and leaves the game running. | Retain. |
| Hook target/cache mismatch | Resolver result, mapped library, cache value, or write-back check disagrees | Does not apply the affected hook; target-frame-rate and animation hooks fail independently where safe. | Retain. |

Successful runs exercised the normal path; failure branches were not removed
merely because this machine did not need them.

## Logging Changes

The cleaned payload has only startup, successful-install, and failure logging.
It emits no per-frame, per-call, pointer-dump, reflection, SetTime, or
synthetic proof messages.

| Normal launch sample | Total lines | Bootstrap lines | Payload lines | Diagnostic/synthetic lines | Fatal/ANR lines |
| --- | ---: | ---: | ---: | ---: | ---: |
| Before cleanup | 742 | 10 | 66 | 39 | 0 |
| After cleanup | 849 | 9 | 7 | 0 | 0 |

The total logcat counts are not directly comparable because the samples were
collected across different emulator boot/noise windows. The production-tag
counts are comparable: payload logging dropped from 66 to 7 lines and all
diagnostic/synthetic markers disappeared.

Expected clean markers include:

```text
PCFPS-ZB: VERSION_GUARD_OK
PCFPS-ZB: TARGET_ICALL_READY
PCFPS-ZB: RUNTIME_LOAD0_RETURNED
PCFPS: ARM64_GUEST_CONSTRUCTOR
PCFPS: ARM64_GUEST_JNI_ONLOAD
PCFPS: HOOK_INSTALL
PCFPS: ANIMATION_FRAMERATE_HOOK_INSTALLED
PCFPS: HOOK_INITIAL_SET effective=60
```

Static `llvm-strings` verification found no forbidden diagnostic/probe/POC/
synthetic/debug/sample/Frida/PERF01 strings in the cleaned ARM64 payload.
The only matching bootstrap string was
`SyntheticTemplateParamName` from the statically linked NDK C++ demangler,
not from project source or a runtime marker.

## Before / After Binary Size

Post-cleanup artifacts are recorded under:

```text
<repo>/build/audit/code01_after
```

| Artifact | Before | After | After SHA-256 |
| --- | ---: | ---: | --- |
| ARM64 `libpcfps_runtime.so` | 25,816 bytes | 12,096 bytes | `b52ffbff0a514792dbf037af31cd4b64d1338f4277fe526534218b0ab5a72c47` |
| x86_64 bootstrap | 431,080 bytes | 430,736 bytes | `dc10e56bda8d5e7054ccff25db781b09c92dc206499ad587ea2639e9a031aa3e` |
| module ZIP | 138,476 bytes | 131,977 bytes | `8a9dd6d8e34d126f4051dc6ac76ef84c81ed01aea04f03b8e0f175e13625922d` |

The production ZIP contains exactly:

```text
module.prop
zygisk/x86_64.so
payload/libpcfps_runtime.so
```

It contains no probe/lifecycle binary, source, debug log, PERF-01 capture,
Frida artifact, APK, split, or game library.

## Regression Validation

### Build and static gates

- `scripts/build.ps1`: PASS with `-Wall -Wextra -Wpedantic`; no compiler
  warnings from project code.
- `scripts/build-zygisk-bootstrap.ps1`: PASS with the same warning visibility;
  no compiler warnings from project code.
- `scripts/package-zygisk-module.ps1`: PASS.
- `llvm-readelf`: payload is ELF64 AArch64; bootstrap is ELF64 x86_64.
- `llvm-nm`/`llvm-objdump`: constructor, `JNI_OnLoad`, target hook, and
  caller-scoped animation hook are present; removed diagnostic functions and
  SetTime hook are absent.
- Source search and static strings search: forbidden runtime residue absent.
- `src/pc_fps_runtime.cpp` still contains no APK/game-library dependency.

### Automated clean-module gate

The cleaned module was installed through the existing Magisk/ReZygisk module
flow, without Frida and without changing the APK. The device reported:

```text
serial: emulator-5554
root: uid=0(root) gid=0(root) groups=0(root)
package: jp.pokemon.pokemonchampions
versionName: 1.1.5
versionCode: 3191
```

After a full restart of the existing Tiramisu64 BlueStacks instance, a normal
launcher start produced a new target PID and one each of constructor,
`JNI_OnLoad`, target hook installation, animation hook installation, and
initial 60 set. `Runtime.load0` returned successfully. A force-stop/relaunch
produced the same set of clean markers under a new PID.

Both samples had:

- no `frida-server` process;
- no synthetic or removed diagnostic markers;
- no target crash/ANR/fatal signal in the captured logcat;
- no module staging, version, readiness, or hook-install failure marker.

The clean payload's functional 60 FPS and trainer/human 60 Hz behavior were
user-confirmed during the completed interactive validation gate. The result is
environment-specific and does not replace validation on a new device or game
version.

### Post-interactive and restore gates

- User reported `操作完了` after operating the clean module. The captured
  interactive log had the expected clean bootstrap/payload sequence, no
  removed diagnostic markers, and no fatal/ANR line. This is a completed user
  interaction gate; it is not a replacement for a numeric frame-counter
  measurement.
- Post-interactive state: `emulator-5554`, target PID `4292`, Android 13/API
  33, x86_64 with `libnb.so`, root present, and no `frida-server` process.
- Stock-revert gate: after a guest reboot with the module disable marker
  active, the vanilla package launched at PID `3355` with zero `PCFPS` lines,
  zero fatal/ANR lines, and no Frida process. Package version remained
  `1.1.5` / `3191`.
- Re-enable gate: after removing only the disable marker and restarting the
  existing Tiramisu64 instance, the clean module launched at PID `3352` with
  one each of constructor, `JNI_OnLoad`, target hook installation, animation
  hook installation, initial 60 set, and successful `Runtime.load0` return.
  No forbidden diagnostic marker, fatal/ANR line, or Frida process was seen.
- Final module state is enabled and its installed hashes match the cleaned
  artifacts recorded above. The game package and APK/split files were not
  modified.
- Unsupported-version/fail-open behavior was verified by static review: the
  exact package/version guard and bounded readiness checks return before
  `Runtime.load0` on mismatch/error/timeout, while the payload requires the
  expected library mappings, resolver target, and cache checks before writing
  either hook.
- Tombstone review found no new tombstone from the clean launch, stock launch,
  or final restored launch.

## Remaining Technical Debt

- The implementation remains version-specific: hardcoded version `1.1.5` /
  `3191`, icall cache offsets, animation cache offset, and the proven
  `AdvanceTime` caller RVA require a new audit for future game versions.
- The initial 60 set is intentionally retained as U/S behavior and should be
  revisited only with a controlled startup experiment.
- The direct build scripts now accept an explicit NDK root, environment
  fallbacks, and common local-install discovery. Recursive `Unblock-File` is
  opt-in with `-UnblockNdk`.
- PERF-01 found intermittent missed-vsync intervals, but CODE-01 does not
  attempt hitch optimization or add runtime telemetry.
- A future diagnostic build may be useful, but it must remain separate from
  the production module and must not restore the removed normal-launch
  instrumentation.
