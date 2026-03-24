# Chatme — Decentralized Messenger

> **Own your conversations. No servers. No surveillance.**

Chatme is a fully decentralized chat application built on the [Nostr protocol](https://nostr.com), where privacy is not a feature — it's the foundation. Your messages are encrypted end-to-end using your own private key, and your data lives only on your device.

---

## Features

### Messaging
- End-to-end encrypted direct messages via **NIP-04** (AES-256-CBC)
- Cross-platform compatible with other Nostr clients (Damus, Primal, Amethyst, etc.)
- Reply to specific messages with swipe gesture
- Emoji reactions on messages
- Message status indicators (sending → sent → read)
- Offline message queue — messages are sent automatically when connection is restored
- Chat history with date dividers and floating date label while scrolling

### Contacts
- Add contacts manually via hex public key
- Global search — find other Chatme users by username
- Long press to remove contact (chat history preserved)

### Voice Calls
- Peer-to-peer voice calls powered by **WebRTC**
- Signaling via Nostr relay — no third-party call server needed
- Proximity sensor support (screen dims when held to ear)
- Mute and speakerphone controls
- Automatic reconnection on network disruption

### Identity & Security
- **Nostr keypair** — your identity is a cryptographic key pair, not a phone number or email
- **Global ID** — optionally claim a `username@chatme` handle for discoverability
- **Recovery phrase** — 12-word BIP-39 mnemonic backup (tap to reveal)
- **Security vault** — view and export your public/private keys
- **Restore account** — import via hex private key or 12-word recovery phrase
- **Key converter** — convert between hex and `npub`/`nsec` (NIP-19 Bech32) format

### Network
- Connects to multiple Nostr relays simultaneously
- Automatic reconnection with exponential backoff
- Real-time relay status monitoring per relay
- Relay list optimized for broad ecosystem coverage:
    - `wss://relay.damus.io`
    - `wss://nos.lol`
    - `wss://nostr.mom`
    - `wss://relay.primal.net`

### Notifications
- Push notifications via **Firebase Cloud Messaging (FCM)**
- WhatsApp-style grouped notifications per contact
- Inline reply directly from notification bar
- Mark as read from notification bar
- Auto-clear notification when chat is opened

### Appearance
- Light and dark mode support
- System default theme option
- Minimalist UI design

---

## Architecture

Chatme is built with a zero-server philosophy — all core functionality runs without any proprietary backend:

| Feature | Technology | Cost |
|---|---|---|
| Messaging | Nostr relays (public) | Free |
| Voice call signaling | Nostr relays (WebRTC over Nostr) | Free |
| Global username directory | Firebase Realtime Database | Free tier |
| Local storage | Hive (on-device) | Free |
| Push notifications | Firebase Cloud Messaging | Free tier |
| Encryption | NIP-04 / AES-256-CBC | — |

---

## Cryptography

Chatme implements the **NIP-04** standard for message encryption, ensuring compatibility with the broader Nostr ecosystem:

- **Key exchange**: secp256k1 ECDH
- **Message encryption**: AES-256-CBC
- **Integrity**: SHA-256 / HMAC
- **Identity**: Schnorr signatures (BIP-340)

> Chatme is also the reference implementation for **[Curve256189](https://github.com/elregann/Curve256189)** — a custom elliptic curve cryptography library featuring **FPOW (Fixed-Point One-Way Wrap)**, a novel quantum-hardening scalar obfuscation mechanism developed as an original research project.

---

## Tech Stack

- **Framework**: Flutter (Dart)
- **Protocol**: Nostr (WebSocket relays)
- **Voice**: flutter_webrtc
- **Local DB**: Hive
- **Notifications**: firebase_messaging + flutter_local_notifications
- **Key format**: bech32 (NIP-19)
- **Mnemonic**: BIP-39

---

## Getting Started

### Prerequisites
- Flutter SDK `>=3.4.4`
- Android device or emulator

### Installation

```bash
git clone https://github.com/elregann/chatme
cd chatme
flutter pub get
flutter run
```

### Create an Account
1. Launch the app — a keypair is automatically generated for you
2. Your **public key** is your identity — share it with friends
3. Optionally claim a `username@chatme` handle in Profile → Global ID
4. Back up your **recovery phrase** or **private key** in Profile → Security Vault

---

## Privacy Policy

Chatme does not collect, store, or have access to your personal data, messages, or keys. All messages are encrypted locally using your private key before being sent to any relay. The Global ID directory only maps a chosen username to your public key — it has no access to your messages or private key.

---

## License

MIT License — see [LICENSE](LICENSE) for details.

---

## Author

Built by [@elregann](https://github.com/elregann) — one developer, zero budget, full decentralization.

> *"Own your data. Own your identity. Own your conversations."*