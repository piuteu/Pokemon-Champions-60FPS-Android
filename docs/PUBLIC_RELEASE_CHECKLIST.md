# Public release checklist

This checklist is a publication draft for PM review. The repository must
remain private until the owner approves the legal, privacy, installation, and
release gates. No public visibility change, release tag, or GitHub Release was
performed by PUBLIC-01.

## Repository and code

- [ ] Repository visibility remains private until PM approval.
- [x] CODE-01 audited baseline is merged at the PUBLIC-01 base.
- [x] CODE-01 runtime freeze is maintained; no diagnostic or probe material
  was restored.
- [x] Current-tree audit completed: no tracked APK, split, game binary,
  extracted asset, generated module binary, log, dump, capture, or credential
  file.
- [x] Full reachable-history path/object audit completed: no proprietary game
  binary, extracted asset, Frida server, emulator image, archive, or
  credential/private-key path found.
- [x] Secret scan passed for the current tree and reachable history.
- [ ] Privacy and author metadata reviewed by PM. The 20 pre-existing reachable
  commits use the same author email; this is a category-C sanitization finding,
  not an automatic history rewrite.
- [x] Copyrighted/proprietary file audit passed for the current tree and
  reachable history.

## Public documentation and legal draft

- [x] README describes the independent runtime-only project and current
  validated version without presenting it as a 1.1.5-only product.
- [ ] `LICENSE` source-available draft reviewed and approved by the project
  owner.
- [x] Source-available wording is used; the project is not described as
  OSI-approved open source.
- [x] Current supported version and future-version policy are documented.
- [x] Unsupported-version fail-open behavior is documented.
- [x] Normal installation and disable/uninstall workflows are documented.
- [x] Architecture, automatic bootstrap, CODE-01, residual-30-Hz, and
  transient-drop documentation are linked and current.
- [x] Unique-frame 60 FPS recording, animation result, and validation limits
  are documented without claiming universal device compatibility.
- [x] Transient missed-vsync hitches are documented as a non-blocking
  BlueStacks limitation.

## Build and artifact

- [x] Direct NDK build remains available without Android Studio, Gradle, CMake,
  Ninja, APK tooling, or repackaging.
- [x] NDK selection supports `-NdkRoot`, `ANDROID_NDK_HOME`,
  `ANDROID_NDK_ROOT`, and local SDK/common install discovery.
- [x] Recursive Windows `Unblock-File` is opt-in with `-UnblockNdk`.
- [x] Clean build scripts pass with warning visibility enabled.
- [x] ARM64 payload and x86_64 bootstrap architectures are verified.
- [x] Canonical ZIP contains only `module.prop`, `zygisk/x86_64.so`, and
  `payload/libpcfps_runtime.so`.
- [x] Game files, Frida, logs, captures, and source are absent from the ZIP.
- [x] Generated binaries and release ZIPs are ignored by Git.
- [x] SHA-256 publication process is documented in the release-notes draft.

## Installation validation

- [x] Existing validated BlueStacks Tiramisu64 environment passed normal
  launch, force-stop/relaunch, full restart, and module disable/stock-revert
  checks.
- [x] Frida-free automatic bootstrap and animation correction were observed in
  the validated environment.
- [ ] Fresh-install ZIP gate: **BLOCKED** until a genuinely clean supported
  BlueStacks environment is available. Do not claim this gate passed based on
  the existing preconfigured/rooted instance.

## Publication metadata and release process

- [x] Recommended repository description is recorded below.
- [x] Recommended GitHub topics are recorded below.
- [ ] First public release tag is PM-approved; PUBLIC-01 has not created a new
  tag (an earlier `v0.1.0-poc` repository tag exists).
- [ ] Release notes are PM-approved; the current file is a draft only.
- [ ] Repository visibility is changed only after PM review of this checklist,
  LICENSE, README, history/privacy findings, and the fresh-install decision.

## Recommended repository metadata

Description:

```text
Runtime-only 60 FPS research and ReZygisk project for Pokémon Champions Android.
```

Suggested topics:

```text
pokemon-champions
android
unity
il2cpp
zygisk
rezygisk
60fps
frame-rate
runtime-hooking
reverse-engineering
bluestacks
```

Recommended first public tag: `v0.2.0-poc`. This reflects the automatic
Frida-free bootstrap, targeted animation correction, residual audit,
transient-drop profiling, and CODE-01 cleanup after the earlier runtime-proof
milestone. Do not create the tag until PM approval.
