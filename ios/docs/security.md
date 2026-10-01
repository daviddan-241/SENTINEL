# Security model

Sentinel is a **read-only** wallet tool. It derives addresses and reads chains. It has no
signing code, no transaction builder and no way to move funds, which is the single biggest
risk reduction available to software like this.

## What is stored, and where

```
vault.json          password → PBKDF2-HMAC-SHA512 (600,000 rounds, 32-byte salt) → KEK
                    KEK → AES-256-GCM → wrapped master key
                    master key → AES-256-GCM → each item (phrase, key, passphrase, note)
scans.json          the last portfolio plus a summary of the last 30 scans — public
                    addresses and balances only, never key material
UserDefaults        the three settings toggles
```

Every layer is bound with additional authenticated data: the wrap is bound to
`"SentinelVault-v1" ‖ iterations ‖ salt` and each item to `"SentinelVaultItem-v1" ‖ id`, so a
tampered header or a swapped item fails to open rather than silently decrypting to something
else.

Files are written atomically with `FileProtectionType.completeFileProtection` and live in the
app's Application Support directory. The vault is not readable while the device is locked.

## Passwords and lockout

* The password is never stored, and there is no recovery path — that is the point.
* Wrong passwords feed `LockoutPolicy`: three free attempts, then a wait that doubles from
  5 seconds to a 15-minute cap.
* Changing the password re-wraps the master key with a new salt and nonce. Items are not
  touched, which is why a re-wrap cannot corrupt them.
* The header stores `iterations`, so a future build can raise the count and still open old
  vaults.

## What the app does about the things around the secret

| Risk | Mitigation |
|---|---|
| Phrase left on the clipboard | Copied secrets are wiped after 90 seconds, and only if the clipboard still holds what the app put there |
| Phrase visible in the app switcher | The whole UI is covered when the scene is not active |
| Phrase read back later by a stranger with the phone | Reveal re-checks the password, and optionally Face ID, every single time |
| Phrase in memory after use | The reveal screen clears its state when it disappears; locking the vault drops the master key |
| Junk-token phishing | Airdrop lures are flagged, hidden and excluded from totals (see `SpamFilter`) |
| Wrong number shown as fact | Two providers must agree, otherwise the address says "verification required" |

## What this does **not** protect against

* **A compromised device.** Malware with the right entitlements, or a jailbroken phone, can
  read an unlocked vault. Nothing here changes that.
* **Shoulder surfing and screenshots.** The app never shows a phrase without a password, but a
  person looking at the screen while it is open sees what you see.
* **A weak password.** PBKDF2 with 600,000 rounds makes guessing expensive, not impossible.
  A four-word passphrase beats a short complicated password.
* **The network seeing what you look up.** Providers learn which addresses this device reads,
  which is exactly what any block explorer learns. There is no mixing, no proxy and no
  padding of requests.
* **Junk you cannot see.** The spam filter is pattern-based plus explorer reputation. A
  worthless token with an ordinary name is not flagged — the tests document that case rather
  than pretending the filter is complete.

## Dependency surface

The core is Foundation, CryptoKit (Apple) or swift-crypto (Linux) and nothing else. There is no
analytics SDK, no crash reporter, no networking library, and no third-party UI code. The only
network calls are the documented blockchain providers in [networks.md](networks.md).
