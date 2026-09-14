# How contributors handle the missing native components

Research date: 2026-09-14. This updates the initial build-readiness assessment;
no application baseline, native library, or installation was changed.

## Direct answer

No documented public process was found by which ordinary OpenBubbles
contributors obtain the real FairPlay input set or the closed OpenAbsinthe
implementation. The evidence shows several different approaches, not a shared
file-download step.

### Maintainer-supported public-source route: relay and remote anisette

On January 5, 2026, maintainer TaeHagen explained that public repositories ship
stubs, with an iOS relay replacing Absinthe and an anisette v3 server replacing
the private anisette component. The same comment recommends recursively
initializing submodules and creating an empty `.env` file.

Source: [maintainer's explanation](https://github.com/OpenBubbles/openbubbles-app/issues/164#issuecomment-3708949768).

The source supports the distinction: `RelayConfig::generate_validation_data`
requests data from a relay rather than calling `ValidationCtx`. But at the
pinned revision `APSConnection` still calls the common `activation::activate`
when no push keypair exists. That function unconditionally embeds the ten
FairPlay pairs. Therefore, the relay advice explains how to avoid one private
runtime component, but is not proof of a complete fresh-install path using
this exact source and placeholder FairPlay inputs. A remote anisette server
also does not replace every kind of Apple activation/validation.

The public workflow copies legacy assets into the missing FairPlay filenames.
An earlier contributor proposed a `dummy-fairplay` feature specifically because
they did not have a real certificate. That makes source compile; it does not
establish successful Apple activation with those inputs.

Source: [rustpush PR 10](https://github.com/OpenBubbles/rustpush/pull/10).

### Some contributors modify or reuse official binaries

In the same public discussion, contributor justin025 reported patching the
Android APK's smali files after failing to obtain a working source build.
This is a reported personal workaround, not a Linux development recipe.

Source: [contributor's account](https://github.com/OpenBubbles/openbubbles-app/issues/164#issuecomment-3695488152).

Linux distribution packages can also wrap the official prebuilt bundle.
Such packaging does not establish that the underlying engine can be rebuilt
from public source.

### The recent successful Android fork does not publish the missing pieces

PR 231 reports a successful profile APK and testing on an existing Pixel
installation. Inspection of its public build wrapper and native submodule found:

- App head: `ae273e9e655d3529ddba769c7059f8963f407e56`.
- Native head: `e5e76919ceb9bf6e2fc05c8ad641430ffcfeb588` in Xare123/rustpush.
- It still pins OpenAbsinthe-Stub at `1f8dc73a311e7b4d94a868972a6816c8a2c14e44`.
- Its native tree has no published `certs/fairplay/` files.
- The wrapper invokes Flutter and verifies that the APK contains the Flutter,
  Dart, and Rust libraries. It does not provide the missing inputs or explain
  which validation backend or existing registration state the live test used.

It would be speculation to infer private access, fresh activation success,
or a complete reproducible public-native build from that APK report.

Sources: [PR 231](https://github.com/OpenBubbles/openbubbles-app/pull/231),
[build wrapper](https://github.com/Xare123/openbubbles-app/blob/ae273e9e655d3529ddba769c7059f8963f407e56/tooling/android/build_verified_alpha.ps1),
[native submodules](https://github.com/Xare123/rustpush/blob/e5e76919ceb9bf6e2fc05c8ad641430ffcfeb588/.gitmodules).

### A real Mac can perform validation using Apple's installed framework

Corten-Matrix is a separate project using rustpush. Its public source implements
Mac-native validation through `AAAbsintheContext` in AppleAccount.framework,
instead of the closed portable OpenAbsinthe implementation. Its current source
supports that path on macOS; its Linux distribution relies on prebuilt binaries.
The implementation inspected was at `64f9d732db77b052a1d12817368c76ed84244f66`.

This demonstrates an alternative architecture, not a way to copy the maintainer's
missing source off a Mac. That implementation reads the host Mac's own hardware
identity, and requires macOS code execution for validation. It does not provide
a portable replacement library for a source-built Linux app. No Mac helper or
relay was installed or executed as part of this research.

Sources: [project's build/distribution explanation](https://github.com/lrhodin/corten-matrix/blob/64f9d732db77b052a1d12817368c76ed84244f66/README.md),
[native implementation](https://github.com/lrhodin/corten-matrix/blob/64f9d732db77b052a1d12817368c76ed84244f66/nac-validation/src/validation_data.m),
[public wrapper](https://github.com/lrhodin/corten-matrix/blob/64f9d732db77b052a1d12817368c76ed84244f66/rustpush/open-absinthe/src/nac.rs).

## Concrete Linux candidate: official engine with matching app source

The official build-205 bundle contains `librust_lib_bluebubbles.so`.
Static disassembly of its exported `frb_get_rust_content_hash` returned the
constant `0xf396704e`, which is signed decimal `-208244658`.

| Component | Generated bridge content hash |
| --- | --- |
| Official Linux build-205 Rust library | `-208244658` |
| Dart and Rust bindings at tag `v1.15.0+205` | `-208244658` |
| Dart and Rust bindings at baseline `eed1b6332` (build 227) | `-1267927268` |

Both source revisions use Flutter Rust Bridge 2.3.0. The different content
hashes show why the bridge package's version alone is insufficient.

This passes an initial static compatibility check for the **build-205 source
and build-205 binary pair**, and rules out simply dropping that library into
the build-227 baseline. It does not prove every symbol, runtime dependency,
startup path, or state schema works. No downloaded library was executed during
this inspection.

A bounded next experiment can use a separate branch rooted at the release-205
source, retaining the exact official native engine and generated bindings while
rebuilding Dart/UI and Linux shell code. CMake already exposes a list of bundled
native libraries; that build path can deliberately supply the pinned official
library instead of invoking Cargo for it. The artifact must record the native
source/binary distinction and checksum. Do not suppress bridge hash checks.

This approach can support interface, window, tray, packaging, and Dart-side
fixes. It cannot rebuild or change the closed engine internals, and it starts
from older app source. Porting later fixes would require reviewing their native
API dependencies. Treat it as a mixed source/binary development build, never
as reproduction of the complete native source.

Sources: [official release](https://github.com/OpenBubbles/openbubbles-app/releases/tag/v1.15.0%2B205),
[release bindings](https://github.com/OpenBubbles/openbubbles-app/blob/v1.15.0%2B205/lib/src/rust/frb_generated.dart),
[current baseline bindings](https://github.com/OpenBubbles/openbubbles-app/blob/eed1b6332efbb17adbf5ebfa2263ad770169f75e/lib/src/rust/frb_generated.dart).

## Remaining questions for upstream

These are prepared questions, not messages sent to anyone:

1. Is a versioned native Linux library with matching generated bindings the
   supported way to develop the desktop UI without private inputs?
2. Can maintainers publish such an artifact for the current public app revision?
3. What exact FairPlay setup is supported for a fresh relay-based build, and
   does that path work with a clean registration rather than existing state?
4. For PR 231, was validation supplied by a relay, private native replacement,
   or preserved client state? Which prerequisites make its result reproducible?

The practical next Linux experiment is the matched release-205 source/binary
pair. A fully source-built current engine still requires resolving the native
inputs or deliberately implementing a different validation architecture.
