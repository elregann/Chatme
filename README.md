<div align="center">

<img src="docs/design/chatme.svg" alt="Chatme logo" width="120" height="120">

# Chatme

**Decentralized, end-to-end encrypted messenger with voice calls, built with Flutter on the Nostr protocol.**

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Platform: Android](https://img.shields.io/badge/platform-Android-3DDC84.svg)
![Flutter](https://img.shields.io/badge/built%20with-Flutter-02569B.svg)
![Protocol: Nostr](https://img.shields.io/badge/protocol-Nostr-8E44AD.svg)
![Status: beta](https://img.shields.io/badge/status-beta-orange.svg)

</div>

Chatme is an instant messaging app where your identity is a cryptographic key you own: no phone number, no email, and no central server holding your account. Messages and call signaling travel through Nostr relays, encrypted on your device before they leave it.

> **Status:** beta. Android is the primary target.

---

## Features

### Messaging
- Direct messages using **NIP-17 gift wrap** with **NIP-44** encryption (rumor, seal, and gift wrap layers), so relays cannot read the content or easily see who is talking to whom. Legacy NIP-04 messages are still understood.
- Replies, emoji reactions, delivery and read status, and date grouping.
- Offline outbox: messages written without a connection are sent automatically when the network returns.
- Names and profile pictures from standard Nostr profile metadata.

### Voice calls
- Peer-to-peer voice calls with WebRTC.
- Call signaling over Nostr relays, with no dedicated signaling server.
- STUN and TURN support for strict networks such as mobile data.
- Incoming call notifications with Answer and Decline, system ringtone, and caller photo.
- Call history in the Calls tab and in the chat, including declined and missed calls.

### Notifications
- Push notifications while the app is closed, through Firebase Cloud Messaging.
- Conversation-style notifications grouped per contact, with name and photo.
- Reply and Mark as Read directly from the notification.

### Identity and security
- Accounts are secp256k1 keypairs (BIP-340 Schnorr signatures).
- Security Vault to view and export `npub` and `nsec` keys.
- BIP-39 recovery phrase for backup and restore.
- Converter between hexadecimal and NIP-19 Bech32 keys.
- Optional Global ID handle (`username@chatme`).

### Relays
- Simultaneous connections to multiple relays with live status.
- Automatic reconnection with exponential backoff.
- NIP-42 authentication for relays that require it.

---

## Supported NIPs

Status: Yes means fully supported, Partial means only part of the NIP is implemented.

| NIP | Description | Status | Notes |
| --- | --- | --- | --- |
| [01](https://github.com/nostr-protocol/nips/blob/master/01.md) | Basic protocol flow | Yes | Events, `REQ`, `EVENT`, `OK`, BIP-340 Schnorr signatures. Profile metadata (kind `0`) is published and read. |
| [04](https://github.com/nostr-protocol/nips/blob/master/04.md) | Encrypted direct messages (legacy) | Partial | Receive only (kind `4`), so older conversations stay readable. New messages never use it. |
| [05](https://github.com/nostr-protocol/nips/blob/master/05.md) | DNS-based identifiers | Partial | The `nip05` field is published in the profile. The `username@chatme` handle is verified through Chatme's own backend, not a `.well-known/nostr.json` lookup. |
| [17](https://github.com/nostr-protocol/nips/blob/master/17.md) | Private direct messages | Yes | Rumor (kind `14`), seal (kind `13`), gift wrap (kind `1059`). Also publishes the DM relay list (kind `10050`) so other clients such as Amethyst can reach Chatme. |
| [19](https://github.com/nostr-protocol/nips/blob/master/19.md) | bech32 encoded entities | Partial | `npub` and `nsec` (view, export, convert, add contact). Other entities such as `nprofile` and `nevent` are not handled. |
| [25](https://github.com/nostr-protocol/nips/blob/master/25.md) | Reactions | Yes | Kind `7`, sent inside a gift wrap. |
| [42](https://github.com/nostr-protocol/nips/blob/master/42.md) | Authentication of clients to relays | Yes | Answers `AUTH` challenges (kind `22242`) for relays that require it. |
| [44](https://github.com/nostr-protocol/nips/blob/master/44.md) | Versioned encryption | Yes | Encrypts both the seal and the gift wrap. |
| [59](https://github.com/nostr-protocol/nips/blob/master/59.md) | Gift wrap | Yes | Wraps every private message, reaction, receipt and call signal. |
| [98](https://github.com/nostr-protocol/nips/blob/master/98.md) | HTTP auth | Yes | Kind `27235`, used to authorize profile photo uploads. |

Not implemented yet: NIP-06 key derivation (see the note below), NIP-65 relay list metadata, NIP-09 event deletion, and NIP-96 or Blossom media servers.

> **About the recovery phrase.** Chatme generates a standard 12 word BIP-39 phrase, but derives the account key from it with its own method (SHA-256 of the phrase), not with the NIP-06 derivation path. The phrase restores your account in Chatme, but it will not give you the same key if you import it into another Nostr client. To use your account elsewhere, export the `nsec` key from the Security Vault instead.

### Event kinds used

| Kind | Name | Where | Used for |
| ---: | --- | --- | --- |
| `0` | Profile metadata | Public | Display name, picture, `nip05`. |
| `1` | Short text note | Public | Read only, legacy fallback for plain messages. |
| `4` | Encrypted direct message (NIP-04) | Public | Read only, legacy fallback. |
| `7` | Reaction | Inside gift wrap | Emoji reactions to a message. |
| `13` | Seal | Inside gift wrap | Signed by the sender, NIP-44 encrypted rumor. |
| `14` | Chat message (rumor) | Inside seal | The message itself. Unsigned. |
| `1059` | Gift wrap | Public | Signed with a one-time key, hides sender and content from relays. |
| `10050` | DM relay list | Public | Tells other clients which relays deliver messages to Chatme. |
| `22242` | Client authentication | Sent to relay | Answer to a relay `AUTH` challenge. |
| `27235` | HTTP auth | Sent to HTTP server | Authorizes photo uploads. |
| `3329` | Read receipt (custom) | Inside gift wrap | Chatme specific. Marks a message as read. |
| `3330` | Call signal (custom) | Inside gift wrap | Chatme specific. WebRTC offer, answer, ICE candidate, ICE restart offer and hang up. |

Kinds `3329` and `3330` are Chatme's own conventions and are not part of any NIP. Other clients ignore them, and a call or read receipt only works between two Chatme users.

---

## Tech stack

| Area | Technology |
| --- | --- |
| Framework | Flutter (Dart) |
| Protocol | Nostr (WebSocket relays), NIP-17, NIP-44 |
| Voice calls | `flutter_webrtc` |
| Local storage | Hive |
| Push notifications | Firebase Cloud Messaging, `flutter_local_notifications` |
| Push delivery | Cloudflare Worker |
| Username lookup | Firebase Realtime Database |

---

## Getting started

### Prerequisites
- Flutter SDK (`>=3.4.4 <4.0.0`)
- Android SDK and a device or emulator

### Run

```bash
git clone https://github.com/elregann/chatme
cd chatme
flutter pub get
flutter run
```

### Notes for building your own copy
- Messaging and calls work over public Nostr relays.
- Push notifications while the app is closed, and Global ID, need your own Firebase project (`google-services.json` in `android/app/`) and notification Worker.
- Voice calls across restrictive networks need a TURN server of your own.
- Release builds rely on `android/app/proguard-rules.pro` and `android/app/src/main/res/raw/keep.xml`. Keep them, or notifications will break.
- Never commit secrets, API keys, or TURN credentials to a public repository.

---

## Privacy and security

- Messages are encrypted on your device before sending. Private keys never leave it.
- Relays see encrypted events, not message content.
- The push pipeline (Cloudflare Worker and FCM) never receives plaintext or private keys, but it does carry metadata such as public keys, event IDs, and timing, plus the encrypted payload.
- Relays can still observe connection metadata such as IP addresses.
- This project has not been independently audited.

---

## License

Distributed under the MIT License. See [LICENSE](LICENSE) for details.

Developed by [@elregann](https://github.com/elregann).