# Linux build acceptance — 2026-09-14

Final tested package: `openbubbles-dev-1.15.0.r205-7-x86_64.pkg.tar.zst`.

* App source: `b40ecccb7598788b537901c64af0ccf58160dbd7` on
  `codex/linux-official-engine` (later changes only
  clarify comments and documentation).
* Package SHA-256:
  `25f1ab9c189bcad63d3552b62cb0d5d2126d653e1c1fc50bc9f8e61a0d164ca5`.
* Official engine SHA-256:
  `ce260415598b78c0810ae6b917145fbca804f6f19385ca9d34d55921d38210cf`.
* Engine/source base: release `v1.15.0+205`,
  `852c9910f456492f7f840ac4ff2a8bad7a1ee8c8`; bridge 2.3.0, signature
  `-208244658`. The native API and generated bindings have no changes.
* Toolchain: managed Flutter 3.24.0 / Dart 3.5.0, optimized release mode.
  Compiler, CMake, package dependencies, and native-library hashes are retained
  in the build receipt and the package's `.BUILDINFO`.

## Build and integrity

The documented build command succeeded from the recorded source. It bundles
the real official engine and does not compile the private messaging backend.
Five integrity tests passed: valid input, corrupt archive rejection, missing
engine rejection, altered engine rejection, and changed interface rejection.
An independent CMake invocation with no engine supplied also failed as expected.
The packaged and installed engine bytes match the manifest.

The release lockfile changed only for its unavailable `flutter_isolate` Git
reference and the maintainer-specific `telephony_plus` path. The latter is now
an official submodule pinned to `5210e940dd92ae371f8c74eaeb552d0704034244`.
The old research branch and ignored local notes remain preserved.

## Grace desktop checks

Tested in the actual Wayland desktop session, with the desktop user's isolated
development data. A temporary rule floated only `app.openbubbles.Dev` during
geometry checks, so the tiling layout did not impose a different size.

* The app displays **OpenBubbles Dev** and its build identifier, reaches the
  welcome screen, and has no missing runtime libraries or application errors in
  the final startup/restart logs.
* Window movement and resizing work. The app's tray can hide, show, and close it;
  closing through **Close App** terminates the process.
* Resizing the preceding installation to **842×586** saved that harmless local
  preference. Upgrading from package 6 to visibly identified package 7 preserved
  the preference file byte for byte and opened the actual window at **842×586**.
* A complete quit/restart retained both the setting and visible dimensions.
* Removal deleted the development executable, bundle, and desktop entry.
  All **11 development data/cache/config/state files** retained their checksums.
  The list and versions of all other installed packages were unchanged.
* Reinstalling the exact package preserved those files. It launched successfully
  again at **842×586**, with no application errors in that startup log.
* Automatic startup remained disabled.

There was no ordinary OpenBubbles package installed on Grace to exercise a live
side-by-side production installation. Package paths, application ID, launcher,
XDG storage isolation, and unchanged other-package inventory were checked.

The early builds exposed an empty-dotenv startup failure, unsupported mobile
plugin calls, and Linux window restoration problems. The final app includes the
necessary platform guards, a credential-free public configuration, a stable tray
ID, and early GTK size restoration. It starts with the existing custom app frame
instead of adding a second GTK header. The runtime may still print Ayatana's
library-deprecation notice; it does not prevent startup or tray operation.

## XPS status

The first working package reached its welcome screen in the actual XPS session.
Further interactive testing was paused at the operator's request. Package 7 was
then installed from the identical archive checked on Grace. Its package and
installed engine checksums match, all bundle runtime libraries resolve, and
automatic startup is disabled. The app was left closed. The receipt is retained
in `build/acceptance/xps-final-install.log`.

Final-version window interaction, restart/settings, and removal/reinstallation
checks on XPS remain pending the operator's availability. Grace's checks are not
claimed as a substitute for those workstation checks.

## Evidence and limits

The package is retained in `build/arch/`. Its release receipt is in
`build/receipts/205-dev.7-b40ecccb-20260914T192832Z/`.
Private desktop logs, screenshots, package inventories, and checksum checks are
under ignored `build/acceptance/`; they are not committed to the public fork.

No Apple sign-in, QR-code import, activation, message sending/receiving, Android
build, or public binary release was tested. No signing identity, FairPlay input,
1Password access, or relay deployment was used. Those remain separate milestones.
