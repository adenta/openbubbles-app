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
