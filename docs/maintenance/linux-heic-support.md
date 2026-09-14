# Linux HEIC viewing

Linux displays HEIC/HEIF attachments through a disposable PNG beside the original
(`original.heic.png`). Conversation bubbles, gallery cards and fullscreen viewing
use the attachment service. Saving, sharing and messaging continue to use the
original bytes and filename. MIME types are not rewritten. Android's existing
decoder is unchanged.

The bundled `openbubbles-heic-decode` helper uses system libheif >= 1.23, libde265
and libpng. It decodes only the primary still, with geometric transformations,
full dimensions and alpha. Output is 8-bit SDR; HDR presentation, auxiliary/depth
images and sequence playback are not implemented. The native messaging engine
and its generated interface are unchanged.

The Dart adapter runs one conversion at a time, coalesces requests for the same
source, kills the helper after 30 seconds, and validates PNG output off the UI
isolate. Original and PNG SHA-256 hashes are stored in a versioned
`.png.heic-cache` receipt. Invalid or pre-existing unverified caches regenerate
lazily. A temporary directory beside the attachment is removed after success or
failure; a complete PNG is published by rename. No migration is needed.

Redownload waits for prior conversion, clears derived files and image caches,
and reloads viewers after the original download is written. Failure shows a
retry action and cannot stop the next item in the conversation image queue.

## Validation

Run from a worktree prepared by `bin/setup-worktree`:

```sh
bin/test-linux-heic
node --test bin/official-engine.test.mjs
bin/build-linux-dev PACKAGE_RELEASE
```

The HEIC suite generates synthetic quadrant images locally using the system
HEVC encoder: ordinary, rotated, mirrored, 10-bit, alpha and multiple-primary-item
selection. Fixtures and compiled test helpers remain under ignored
`build/heic-tests/`; the generator is the redistributable source. Tests cover
native decoding, literal filenames, cache corruption, replacement with preserved
timestamps, concurrent requests, invalidation, failed/empty input, missing helper,
timeout recovery, image-queue continuation and ordinary-format regressions.

For workstation acceptance, open a received HEIC in a conversation, its gallery,
and fullscreen; retry/redownload; close and reopen the conversation. Check a
JPEG/PNG in the same conversation. Confirm orientation, zoom detail, responsive
scrolling and successful later images after a failed attachment. Inspect private
attachments in place only, and record counts/results rather than images, paths,
names or message bodies.

Keep the previous package archive for rollback. Reinstall it to roll back code;
the original attachments and account state require no restore.

## Release 8 acceptance — 2026-09-14

- Built source: `b14e1d0d3` (HEIC plus the two integrated desktop-close fixes).
- Package: `openbubbles-dev-1.15.0.r205-8-x86_64.pkg.tar.zst`.
- Package SHA-256: `b5a002843aee695ea55e0340e01d094ea600d71edf4f8688203d0f9e36d6861a`.
- Receipt: `build/receipts/205-dev.8-b14e1d0d-20260914T205249Z/`.
- Seventeen HEIC/service tests, three desktop-lifecycle tests and five existing
  engine-integrity checks passed. Dart analysis found no errors; existing lint
  warnings in the surrounding application remain.
- The identical package was installed on Grace and XPS. Both retain the pinned
  official messaging engine hash. Grace displayed its restored 842×586 window
  with no unhandled startup exceptions in the smoke-test journal. Its installed
  helper decoded the rotation fixture to 32×64.
- XPS attachment storage initially contained two HEIC files and no PNGs. Both
  originals decoded in place through the installed helper (3024×4032 and
  1179×2556); their hashes were unchanged. Temporary verification outputs were
  removed. The application independently created PNG display caches for both.
  Its smoke-test journal had zero `Invalid image data` or HEIC conversion errors.
- XPS logged an unhandled exception at the unchanged FaceTime header widget,
  `FaceTimeBtnState.initState`, and its smoke-test service was subsequently
  inactive. This does not establish a HEIC-related shutdown. No additional
  restart was performed. Physical fullscreen zoom, gallery comparison and retry
  interaction remain to be confirmed with the user.
- No manual contact cache or sync-marker changes were made. Release 9 is
  reserved for the coordinating contacts task.

The shared repository added explicit deployment-approval instructions while
this rollout was underway. They were discovered after installation and are now
included in this worktree. Further live restarts, upgrades or data changes need
the direct user approval described in `AGENTS.md`. The attempted shared-branch
fast-forward made no changes; consumers should merge this task's branch into
their own worktree. Later policy/documentation commits do not change release-8
application code.
