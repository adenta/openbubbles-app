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
