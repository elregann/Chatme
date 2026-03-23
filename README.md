# Chatme

A decentralized messaging and calling application built with Flutter and the Nostr protocol.  
Chatme provides end‑to‑end encrypted communication, voice calls, and optional global user discovery — all without central servers.

---

## Features

### Decentralized Communication
- Built on **Nostr** – messages are published to multiple relays, ensuring no single point of failure.
- **End‑to‑end encryption** using NIP‑04 (AES‑256‑CBC with ECDH shared secret on secp256k1).
- **Self‑sovereign identity** – keys are generated locally; you control your account.

### Messaging
- Send text messages with support for replies and emoji reactions.
- Read receipts (status: sending, sent, read).
- Offline message queue – messages are stored locally and automatically sent when connectivity is restored.

### Voice Calls
- **WebRTC** peer‑to‑peer audio calls with signaling over Nostr (kind 1000).
- STUN / TURN support via free public servers to work behind restrictive networks.
- Mute, speaker toggle, and proximity sensor (screen turns off during calls).

### Account & Security
- **Recovery phrase** – 12‑word mnemonic (BIP‑39) to restore your account.
- **Key converter** – convert between hex and bech32 (npub/nsec) formats.
- **Security vault** – view and copy your public and private keys (private key hidden by default).

### Global Discovery (Optional)
- **Voluntary username registration** – users may link a unique username to their public key in a public search index.
- **Global search** – find other users by their registered username via Firebase Realtime Database.
- **Privacy‑first** – the registry acts solely as a directory and does not store or access any messages, private communications, or encrypted data.
- **Opt‑out available** – users who prefer not to be indexed can add contacts manually; their username and public key will not appear in global search.

### User Interface
- Light and dark themes (follow system or manual selection).
- Material Design 3 with a clean, responsive layout.
- Unread message counters and badges.

### Network & Reliability
- Connects to multiple default Nostr relays (damus.io, nos.lol, nostr.mom, primal.net).
- Auto‑reconnect on network changes or app resume.
- Real‑time connection status display.

### Notifications
- Push notifications via Firebase Cloud Messaging for incoming messages and calls.
- Actionable notifications – reply or mark as read directly from the notification.

---

## Tech Stack

| Technology          | Purpose                                 |
|---------------------|-----------------------------------------|
| Flutter             | Cross‑platform UI framework             |
| Nostr               | Decentralized communication protocol    |
| WebRTC              | Real‑time voice calls                   |
| Hive                | Local storage for contacts and messages |
| Firebase            | Cloud messaging (FCM) and global username registry |
| bip39               | Mnemonic generation                     |
| pointycastle        | Elliptic curve operations (secp256k1)   |
| bech32              | Key format conversion                   |

---

## Privacy

Chatme is designed with privacy as the core principle:

- **No central servers** – your messages flow through open Nostr relays; the app does not operate any infrastructure that stores your data.
- **End‑to‑end encryption** – messages are encrypted locally before they leave your device.
- **No data collection** – the app does not collect, store, or transmit any personal information, analytics, or usage data.
- **Optional discovery** – the global username registry is opt‑in; you can use the app entirely without it.

You are solely responsible for your private key. Without it, account recovery is impossible — a deliberate trade‑off for true self‑sovereignty.

---

## License

This project is open‑source. See the repository for license details.

---

## Contributing

Contributions, issues, and feature requests are welcome.  
Feel free to open an issue or submit a pull request.

---