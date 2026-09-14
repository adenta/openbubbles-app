# Linux build readiness

The development fork is https://github.com/adenta/openbubbles-app. The baseline
is upstream application commit `eed1b6332efbb17adbf5ebfa2263ad770169f75e`
(version `1.15.0+227`) on branch `codex/linux-build-proof`. Linux and Android
remain in this app repository. No native dependency fork has been created.

## Current result

**Blocked before native compilation. No custom package has been built or installed.**
The build, launch, upgrade, settings-persistence, and removal acceptance checks
are outstanding. An official prebuilt release is not a substitute for proving
our own source build.

Run `bin/check-linux-build-inputs` from any directory. It exits with status 2
for the known missing native inputs. It neither reads nor prints key contents.
It checks submodule revisions, missing/empty files, and known placeholder code;
passing it would not validate the provenance or authenticity of supplied inputs.

## Verified native blockers

- `rustpush/src/activation.rs` unconditionally includes ten certificate/key
  pairs under `rustpush/certs/fairplay/`: numeric names ending in `193` through
  `201`, and `208`. All 20 files are absent from a recursive public checkout.
  Their common prefix is `4056631661436364584235346952`.
- Upstream's `.github/workflows/build.yml` creates fake FairPlay inputs from
  legacy files. This fork's build proof does not use that workaround.
- The app enables `macos-validation-data`. Its pinned `OpenAbsinthe-Stub`
  dependency explicitly describes itself as a placeholder for closed-source
  functionality. `ValidationCtx::new`, `key_establishment`, and `sign` are
  `todo!()`; `HardwareConfig::from_validation_data` panics.
- The latest official Linux release checked on 2026-09-14 was `v1.15.0+205`,
  not the source's build 227. Neither `OpenBubbles/rustpush` nor
  `OpenBubbles/OpenAbsinthe-Stub` published releases at that check. No supported,
  separately published native artifact matching this source was identified.

The next native-build step requires upstream-supported inputs and validation
implementation, or a documented supported native binary with exact API/Flutter
Rust Bridge compatibility. The bridge is pinned to 2.3.0 on both sides. Do not
mix an older release's native library with newer generated bindings without
verifying compatibility. A user's Mac QR code is runtime hardware identity,
not a replacement for these missing build-time dependencies.

## Reproducing the baseline inspection

```sh
git clone https://github.com/adenta/openbubbles-app.git openbubbles
cd openbubbles
git remote add upstream https://github.com/OpenBubbles/openbubbles-app.git
git switch codex/linux-build-proof
git -c url.https://github.com/.insteadOf=git@github.com: submodule update --init --recursive
bin/check-linux-build-inputs
```

The command-local HTTPS rewrite downloads public submodules without modifying
SSH trust or global Git configuration. The original upstream submodule pins
are retained.

Upstream CI specifies Flutter 3.24.0 (Dart 3.5.0). Install through the existing
Mise manager using `mise install flutter@3.24.0`; no global activation is needed.
The dependency check is:

```sh
mise exec flutter@3.24.0 -- flutter --suppress-analytics pub get --enforce-lockfile
```

Build logs and host-specific receipts belong under ignored `build/maintenance/`.
Private activation inputs, account state, and signing keys must not enter Git
or distributable packages.

## Remaining Linux delivery

After resolving the inputs, establish compatible Flutter/Rust/system toolchain
pins and complete an optimized release build on Grace. Package it as
`openbubbles-dev` with a distinct desktop identity and isolated app data.
Install the identical checksummed Arch package on Grace and XPS. Verify real
desktop launch, shutdown, settings persistence, upgrade to a visibly different
build, and removal without affecting existing installations.

Account activation and messaging require subsequent acceptance. Android work,
public releases, and feature changes remain deferred.

## Validation recorded on 2026-09-14

- Flutter 3.24.0 was installed through Mise on Grace, without changing global
  tool selection. `flutter pub get --enforce-lockfile` succeeded; the tracked
  dependency lockfile remained unchanged.
- The native readiness checker reported all 20 missing FairPlay files and the
  OpenAbsinthe placeholder, exiting with status 2 as expected.
- Shell syntax validation and `git diff --check` passed.
- No native compilation, package installation, or desktop acceptance was
  claimed. No QR code, 1Password item, or phone operation was used.

## Follow-up: contributor routes and official native reuse

[Contributor build-path research](native-build-paths.md) records the maintainer's
relay guidance, the limitations of public contributor builds, and an additional
static compatibility result: the official build-205 native library matches the
release-205 generated bindings, but not this build-227 baseline. A mixed
source/binary Linux build is a concrete next experiment; a full native-source
build remains blocked. No baseline or build policy has been changed yet.
