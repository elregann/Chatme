# Chatme

**Decentralized, end-to-end encrypted messenger with voice calls, built with Flutter on the Nostr protocol.**

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