# Desktop CardDAV contacts

Desktop contact refresh applies network deltas to the complete local address
book, then matches every saved messaging handle against that book. Unchanged
server responses still repair missing links. Refreshes run serially through
checkpoint persistence; contacts and handle links commit in one database
transaction before any sync checkpoint is saved.

Imported IDs are `carddav:` followed by the resolved, normalized resource URL.
Updates retain ObjectBox IDs; resource deletions affect only that imported ID.
Ordinary address-book matches take precedence over shared iMessage profiles,
with valid existing matches retained within that preference. Contact views,
conversation titles, open conversations and avatars react to completed changes.
Contact-sync diagnostics contain counts and sanitized errors, not contact cards.

The application has no legacy-ID migration, automatic repair, or repair button.
Existing empty-ID imports require a one-time operator repair after installing
the corrected build: preserve the affected local records, links and iCloud
checkpoints; reset only those checkpoints; verify a successful fresh import;
then remove the identified legacy records and let normal matching rebuild links.
Cloud contacts and messages are outside that operation. Retain the scoped
recovery record until verification completes, then remove it.

Regression tests use synthetic contacts and a disposable ObjectBox database:

```sh
LD_LIBRARY_PATH=/opt/openbubbles-dev/lib mise exec flutter@3.24.0 -- \
  flutter test --no-pub test/contact_sync_test.dart
```

The native library path above uses the existing installed ObjectBox library;
the tests do not open the installed application's profile. Tests cover first
import, unchanged sync, new message handles, stable-ID updates, scoped deletion,
shared profiles, transaction/checkpoint failures, retries, overlapping refreshes,
cached conversation objects, live picker/avatar updates and HTTP failures.

Collection responses are excluded from vCard downloads, including iCloud's
response for the address book with its trailing slash omitted. Failed real
card downloads retain the previous checkpoint. Sanitized failure categories
and HTTP status codes identify failures without exposing resource URLs.

## Release 9 acceptance — 2026-09-14

- Built source: `80c8982df`, including HEIC and the desktop-close fixes.
- Package: `openbubbles-dev-1.15.0.r205-9-x86_64.pkg.tar.zst`.
- SHA256: `f6207cd67fd094f3bb5f171acbca97a99ef53e2539faec883480157dc638ca58`.
- Receipt: `build/receipts/205-dev.9-80c8982d-20260914T213632Z/`.
- 23 contact regression tests passed, including the actual Cupertino and
  Material conversation title widgets. Release validation also passed 17
  HEIC/service tests, three close-lifecycle tests and five engine checks.
- The packaged application opened successfully on Grace with a disposable
  profile. Grace's existing installed app remained on release 8.
- The identical validated package was installed on XPS. Fresh import saved
  390 contacts with stable IDs before its checkpoint was committed. Only then
  were the 390 backed-up, unchanged legacy empty-ID records manually removed.
- An unchanged sync rebuilt five valid links, including all four originally
  matchable addresses. A further unchanged sync reported 390 contacts and zero
  inserts, updates, deletions or relinks. There were no duplicate stable IDs or
  dangling links. Two original addresses still had no matching contact details.
- The actual XPS sidebar and open-conversation header displayed contact names.
  Picker search preservation, empty results and live updates passed widget
  regression tests.
- The scoped recovery procedure and restoration were tested against a
  disposable synthetic profile. Temporary recovery material, authentication
  copies used by the diagnostic, and verification screenshots were removed
  after acceptance. No cloud contacts, messages or sign-in configuration were
  changed by the repair.

The release-8 rollback package remains in the canonical checkout's
`build/arch/`, with SHA256
`b5a002843aee695ea55e0340e01d094ea600d71edf4f8688203d0f9e36d6861a`.
No repair utility or migration is included in the application package.
