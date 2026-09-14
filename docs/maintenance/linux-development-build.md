# Linux development build

This fork compiles the release-205 Flutter interface and Linux desktop plugins,
and bundles OpenBubbles' official release-205 messaging engine. It does not
compile the private messaging backend. No Apple identity or activation material
is needed to build or open the setup screen; messaging needs separate acceptance.

## Source and toolchain

The base is `v1.15.0+205`, commit
`852c9910f456492f7f840ac4ff2a8bad7a1ee8c8`, on
`codex/linux-official-engine`. The original research remains on
`codex/linux-build-proof`. Work in `/home/agent/workspaces/openbubbles`.
The old workspace path is a temporary symlink for the existing task; retire it
once the desktop project has been repointed and no active task uses that path.

Use the existing Mise installation of Flutter **3.24.0** (Dart **3.5.0**).
The build invokes that version explicitly and never changes global selections.
The release's lockfile is retained with two necessary repairs:

* `flutter_isolate`'s unavailable Git repository is replaced with pub.dev 2.1.0.
* The maintainer's absolute `telephony_plus` path becomes a pinned submodule.
  This resolves the shared package graph; Android builds remain deferred.

On Arch, build tools and libraries are installed with:

```sh
sudo -n pacman -S --needed base-devel clang cmake ninja nodejs curl \
  gtk3 libayatana-appindicator webkit2gtk-4.1 libsecret mpv libnotify
```

Reuse a managed Node installation instead of installing `nodejs` when one is
already available. CMake's compatibility minimum is locally set to 3.5 for the
old pinned plugins on CMake 4. The two tray targets retain warnings for the API
deprecated by Ayatana 0.6, without treating that deprecation as a build error.
The messaging-engine CMake file invokes no Cargo.
Other Flutter plugins retain their own upstream build/download mechanisms.
The release's dotenv loader rejects a zero-byte file. The build copies the
checked-in `packaging/linux/public.env`, with optional integration keys blank,
and refuses to overwrite or package any other nonempty `.env`.
Linux skips unsupported Mixpanel initialization, and Android billing is created
only when used; Linux does not query Google Play purchases. The unsupported
native privacy-overlay unlock call is disabled on Linux, while the existing
authentication checks remain in place. These are desktop startup fixes, without
native API changes. The tray gets a stable development ID, and Linux resize
events save the window size after a short debounce.

## Build

```sh
cd /home/agent/workspaces/openbubbles
git switch codex/linux-official-engine
bin/build-linux-dev 1
node --test bin/official-engine.test.mjs
```

Choose an increasing integer for each package release. The resulting package is
`build/arch/openbubbles-dev-1.15.0.r205-1-x86_64.pkg.tar.zst`.
This is an optimized Flutter release build, with a visible development ID.
A dirty source tree is explicitly identified in that ID; use committed source
for installations you intend to retain.

`packaging/linux/engine.json` pins the official download URL, archive SHA-256,
engine SHA-256, source revision, bridge version, native signature, and interface
file checksums. Downloads are cached in ignored `build/engine-cache/`.
Only the engine member is extracted, into ignored `build/official-engine/`.
The archive, extracted engine, and source interface are checked before compiling;
CMake independently checks the engine/interface again. The generated bridge's
normal runtime signature check remains enabled. A corrupt cache fails instead
of silently being replaced; remove the named archive and rerun to download again.
Engine updates require an explicit matching source-and-binary manifest update.

Build logs, Flutter versions, source status, submodule revisions, engine and
lockfile checksums, compiler versions, and package SHA-256 are recorded under
`build/receipts/`. The installed bundle includes `build-info.txt`,
`flutter-toolchain.json`, and `engine-manifest.json`.
Checksums establish byte identity with the pinned download; they are not a
separate publisher signature or a claim of bit-for-bit reproducible compilation.

## Install and upgrade

Build once on Grace and use that exact package on both machines:

```sh
package=build/arch/openbubbles-dev-1.15.0.r205-1-x86_64.pkg.tar.zst
sha256sum "$package"
sudo -n pacman -U --noconfirm "$package"
scp "$package" xps:/tmp/
ssh xps 'sha256sum /tmp/openbubbles-dev-1.15.0.r205-1-x86_64.pkg.tar.zst'
ssh xps 'sudo -n pacman -U --noconfirm /tmp/openbubbles-dev-1.15.0.r205-1-x86_64.pkg.tar.zst'
```

Launch **OpenBubbles Dev** from the desktop menu, or run `openbubbles-dev` in the
desktop user's terminal. For a second build, use `bin/build-linux-dev 2` and repeat
the same copy/install commands with release 2. Quit the running development app
before upgrading, then reopen it to load the new code.

The package owns `/opt/openbubbles-dev`, `/usr/bin/openbubbles-dev`, and the
`app.openbubbles.Dev` desktop entry and icon. It declares no conflicts/replaces
against an existing OpenBubbles package. Its launcher scopes the user's XDG
configuration, data, cache, and state roots to an `openbubbles-dev` subdirectory.
The GTK application ID is also distinct. The launcher preserves HOME for desktop
services. Existing app data is neither imported nor modified.

Automatic startup defaults to disabled. If enabled through settings, the entry
is `~/.config/autostart/openbubbles-dev.desktop` and executes our isolated launcher.
The inherited startup plugin uses this HOME-relative location.

## Remove

Quit the development app, then:

```sh
sudo -n pacman -R --noconfirm openbubbles-dev
ssh xps 'sudo -n pacman -R --noconfirm openbubbles-dev'
```

Removal only deletes package-owned files. Development preferences survive for
reinstallation, and existing OpenBubbles packages and data remain intact. If you
previously enabled automatic startup, disable it before removal (or remove only
`~/.config/autostart/openbubbles-dev.desktop`). Do not delete the parent XDG
configuration/data directories. No removal hook runs in a user's home directory.

## Acceptance record

See `linux-build-acceptance.md` for actual tested builds and results. A successful
build or setup-screen launch alone does not establish Apple sign-in or messaging.
