# Encryption at rest, and exports you can carry

Penny keeps a money ledger on a phone. Today it is a plain JSON string in
`shared_preferences`, which is app-private but leaves three real openings: it
is copied into Google's cloud backup (Android's `allowBackup` default), it is
readable on a rooted or imaged phone, and every export is a plaintext file
sitting wherever it was shared.

This is the last change before investment tracking, so that the holdings that
feature adds are never written in the clear.

## Goals

- The ledger on disk is unreadable without the phone's own Keystore.
- The ledger leaves Android's cloud backup.
- An export can be encrypted with a passphrase the person chooses, per export.
- Data that cannot be read is never silently replaced with empty data.

## Non-goals

- Protecting against an attacker running code as Penny on an unlocked phone.
  A key the app can use automatically is a key that attacker can use too.
- Binding the storage key to biometrics. It would invalidate the key on a
  fingerprint change, and a money app that eats its ledger when someone adds a
  fingerprint is worse than one that does not.
- Encrypting the CSV export. Its purpose is to open in a spreadsheet.
- Hiding the fact that Penny is installed, or that it holds data.

## Threat model

| Exposure | Today | After |
|---|---|---|
| Another app on a non-rooted phone | Cannot read app-private storage | Unchanged |
| Google cloud backup / `adb backup` | Whole ledger readable | Ledger excluded from backup |
| Rooted phone, or an imaged filesystem | Whole ledger readable | Ciphertext; key stays in Keystore |
| Someone holding the unlocked phone | App lock (0.4.2) | Unchanged |
| An exported file in Downloads, chat, Drive | Readable JSON | Readable, or sealed if a passphrase was given |

## Design

### 1. The ledger blob moves into Keystore-backed storage

`load()` reads one key and `_commit()` writes one key, so the change is
contained to those two call sites plus a new file.

`flutter_secure_storage` with `AndroidOptions(encryptedSharedPreferences: true)`
stores values through Jetpack Security's `EncryptedSharedPreferences`:
AES-256-GCM under a key held in the Android Keystore, which never appears in
Penny's own files. Penny writes no crypto of its own for storage — no nonce
discipline, no envelope format, nothing to get subtly wrong.

New `lib/vault.dart`, widget-free, with an injectable backend so tests run
without platform channels (the pattern `lock.dart` already uses for
`askPhone`):

```dart
Future<String?> readLedger();            // null on a fresh install
Future<void> writeLedger(String json);
Future<bool> migrateFromPlaintext();     // one-way, once
```

### 2. Migration

On first launch after the update: if the legacy plaintext `ledger` key exists
in `shared_preferences`, copy it into secure storage, confirm the read back,
then delete the plaintext key. If the copy fails, the plaintext key is left
alone and Penny keeps using it — a failed migration must not lose data.

### 3. Failure is loud

`load()` currently swallows a bad read and starts empty. With ciphertext that
becomes destructive: a Keystore key invalidated by a restore would leave Penny
empty, and the first edit would overwrite the real ciphertext.

New rule: distinguish **absent** (fresh install, start empty as today) from
**present but unreadable**. When the ledger is present and unreadable,
`PennyStore.unreadable` is set, **no write happens at all**, and `main.dart`
shows a recovery screen instead of the shell:

- *Import a backup* — the existing import path, which replaces everything.
- *Start fresh* — explicit, typed-out confirmation, then a new empty ledger.

Until one is chosen, the stored bytes are left untouched, so the data survives
a reinstall-and-restore attempt or a fix in a later build.

### 4. Android backup flags

```xml
android:allowBackup="false"
android:dataExtractionRules="@xml/data_extraction_rules"   <!-- Android 12+ -->
```

with rules excluding shared preferences from both cloud backup and
device-to-device transfer. The trade-off, stated in the README and the release
notes: a new phone does not auto-restore Penny. The export is the migration
path, which is already true in practice.

### 5. Exports with an optional passphrase

The export sheet gains one optional field. Blank writes today's plain JSON.
A passphrase writes an envelope:

```json
{ "penny": 1, "kdf": "pbkdf2-sha256", "iterations": 210000,
  "salt": "<base64>", "nonce": "<base64>", "ct": "<base64>" }
```

- Key: PBKDF2-HMAC-SHA256 over a 16-byte random salt, iteration count stored in
  the file so it can be raised later without breaking old backups. The count is
  tuned on a real phone to about a second; if platform acceleration is missing
  it is lowered rather than left to block the UI, and the ceiling is recorded
  in a `ponytail:` comment.
- Cipher: AES-256-GCM, random 12-byte nonce. GCM authenticates, so a wrong
  passphrase or an edited file fails cleanly.
- Import sniffs the file: a `penny` envelope asks for a passphrase first,
  anything else takes the existing path unchanged.
- A failed open changes nothing. `importJson` already decodes fully before
  adopting, so a partial import is impossible.

Packages: `cryptography` with `cryptography_flutter`, which routes AES-GCM and
PBKDF2 through Android's own implementations instead of pure Dart.

The passphrase is never stored, never defaulted, and never hinted at. Penny
cannot recover a backup whose passphrase is lost, and the export sheet says so
in one line before writing the file.

## Testing

Unit, against an in-memory vault backend:

- Round trip: write, read, identical JSON.
- Migration: plaintext ledger present → secure storage holds it, plaintext key
  gone; a failing write leaves the plaintext key in place.
- Absent vs unreadable: a fresh install starts empty and saves normally; an
  unreadable ledger sets `unreadable`, writes nothing, and leaves stored bytes
  untouched.
- Export: sealed file round trips; wrong passphrase rejected; tampered
  ciphertext rejected; plain backups still import; an envelope with a different
  iteration count opens.

Widget:

- The recovery screen appears instead of the shell when `unreadable`, offers
  both ways out, and "Start fresh" needs an explicit confirmation.

Golden: the export sheet with its passphrase field, light and dark.

## Risks

- **Keystore key loss** (uninstall, some restores) makes the ledger
  unrecoverable. Mitigated by failing loudly, by keeping exports as the real
  backup, and by saying so in the release notes.
- **Forgotten export passphrase** makes that file unrecoverable. Mitigated by
  keeping the passphrase optional and warning at the point of export.
- **Whole-blob re-encryption on every mutation.** Imperceptible at this data
  size; if it is ever felt, debounce the save. `ponytail:` comment, not work.
- **`flutter_secure_storage` behaviour across Android versions.** Verified on a
  real phone before release, not only in tests.

## Rollout

One release, version 0.5.0. Notes state plainly: data is encrypted on this
phone, Android backup is off, exports can take a passphrase, and the export is
now the only way to move to a new phone.
