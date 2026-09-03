# Public release checklist

This checklist is a publication draft for PM review. The repository must
remain private until the owner approves the legal, privacy, installation, and
release gates. No public visibility change, release tag, or GitHub Release has
been performed in this private canonical repository.

## Repository and code

- [ ] Repository visibility remains private until PM approval.
- [x] The audited production working tree was exported without migrating
  legacy research history.
- [x] CODE-01 runtime freeze is maintained; no diagnostic or probe material
  was restored.
- [x] Current-tree audit completed: no tracked APK, split, game binary,
  extracted asset, generated module binary, log, dump, capture, or credential
  file.
- [x] Full reachable-history path/object audit completed: no proprietary game
  binary, extracted asset, Frida server, emulator image, archive, or
  credential/private-key path found.
- [x] Secret scan passed for the current tree and reachable history.
- [x] Fresh Git history contains one sanitized root lineage; legacy research
  history was not migrated.
- [x] Reachable commit author and committer metadata use only the sanitized
  project identity; no legacy identity is present.
- [x] Privacy and author-metadata gates passed and received PM privacy review;
  public visibility remains subject to the outstanding legal and publication
  approvals.
- [x] Copyrighted/proprietary file audit passed for the current tree and
  reachable history.

## Public documentation and legal draft

- [x] README describes the independent runtime-only project and current
  validated version without presenting it as a 1.1.5-only product.
- [ ] `LICENSE` source-available license and third-party carve-out reviewed
  and approved by the project owner.
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
- [x] Fresh-install ZIP gate: **PASS** in an isolated fresh BlueStacks
  Android 13 / Tiramisu64-class environment on a separate physical Windows
  host. Google Play version 1.1.5 / versionCode 3191, root/ReZygisk,
  Frida-free automatic bootstrap, normal launch, force-stop/relaunch, full
  restart, stock revert after module disable, and re-enable recovery passed.
  No PCFPS-attributable fatal error or ANR was observed.

## Publication metadata and release process

- [x] Recommended repository description is recorded below.
- [x] Recommended GitHub topics are recorded below.
- [x] No legacy tag was migrated into this canonical repository; no tag or
  release has been created here.
- [ ] First public release tag is PM-approved; no public tag has been created.
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
