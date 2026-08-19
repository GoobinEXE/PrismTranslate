# Sensitive data handling

Internal security notes for Prism Translate (private repository).

## Retention surfaces

| Surface | What is held | Mitigation |
|---------|--------------|------------|
| Translation LRU cache | Up to 64 recent phrase pairs | TTL 5 min, max 512 chars/entry, clear on background, opt-out toggle |
| Result panel session | Original + translated text | Cleared on dismiss |
| Pasteboard backup | User clipboard text types only | 60 s timeout, wipe after restore |
| API keys | Keychain + ephemeral `SensitiveData` | `WhenUnlockedThisDeviceOnly`, not iCloud-synced |
| Custom HTTP headers | Keychain | Migrated from UserDefaults |
| Logs (`app.log`, OSLog) | Metadata by default | Opt-in text previews; redaction; export warning |

## Settings › Logs › Privacy

- **Include text previews in logs** (default off): when off, logs show `(N caracteres)` instead of content.
- **Cache recent translations in memory** (default on): when off, no LRU retention between requests.

## Before sharing logs

1. Confirm text previews are off unless you intend to include snippets.
2. Use export warning — do not attach logs with private chat/email content.
3. Redaction masks Bearer tokens, query `key=`, and common JSON fields — not a guarantee.

## Accepted risks (SEC-01)

- **App Sandbox is off** (`Prism.entitlements`: `com.apple.security.app-sandbox = false`) — required for Accessibility API and global hotkeys (CGEvent tap). Full sandbox is incompatible with in-place translation in arbitrary apps.
- **Compensation:** Developer ID signing, notarization, and Hardened Runtime in release builds (`scripts/release.sh`). Do not enable `com.apple.security.cs.allow-unsigned-executable-memory` in entitlements.
- Cloud translation engines still send text to third-party APIs by design — separate from local memory retention.

## Limitations

Swift `String` cannot be reliably zeroed after use. `SensitiveData` wipes `Data` buffers on deinit (best effort). macOS swap and crash dumps remain out of app control.

## Secrets in repo

- `Secrets.xcconfig` must stay in `.gitignore` (SEC-08).
- Never commit API keys, Team ID, or exported logs with user content.
