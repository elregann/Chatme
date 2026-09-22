# Chatme

Chatme is a decentralized, cross-platform instant messaging application built with Flutter. It utilizes the Nostr protocol to provide user-owned identity, censorship resistance, and true end-to-end encryption without reliance on centralized server infrastructures.

---

## Key Features

### Messaging & Communication
- **End-to-End Encryption**: Direct messages secured via **NIP-04** (secp256k1 ECDH combined with AES-256-CBC), ensuring full interoperability with the wider Nostr ecosystem.
- **Protocol Extensibility**: Architectural groundwork prepared for upcoming protocol upgrades including NIP-17 and NIP-44.
- **Core Messaging**: Support for message replies, reaction emojis, delivery status tracking, and chronological date grouping.
- **Offline Reliability**: Outbox queueing mechanism that automatically transmits pending messages upon network re-establishment.

### Voice Calls (WebRTC)
- **Peer-to-Peer Audio**: Real-time voice communication powered by WebRTC.
- **Decentralized Signaling**: Call signaling routed securely across Nostr relays, eliminating dedicated third-party signaling servers.
- **Device Integration**: Proximity sensor management for screen dimming during calls, speakerphone and microphone mute toggles, and automatic recovery on network disruptions.

### Identity & Security
- **Self-Sovereign Identity**: User accounts are anchored to cryptographic Nostr keypairs (secp256k1 Schnorr signatures via BIP-340) with no phone number or email requirement.
- **Security Vault**: Local management and export facilities for public (`npub`) and private (`nsec`) keys.
- **Recovery & Restoration**: BIP-39 mnemonic phrase generation and account restoration.
- **Key Conversion**: Utilities for translating between hexadecimal keys and NIP-19 Bech32 formats.
- **Global ID**: Optional user directory mapping for `username@chatme` handles.

### Relay Management
- **Multi-Relay Connectivity**: Simultaneous connections to multiple Nostr relays.
- **Health Monitoring**: Real-time connection status and latency observation per relay.
- **Automatic Reconnection**: Exponential backoff reconnection algorithms ensuring continuous relay synchronization.

### Notifications
- **Background Push Notifications**: Integration with Firebase Cloud Messaging (FCM) for reliable alert delivery.
- **Rich Conversations**: Grouped notification threads per contact supporting inline replies and read acknowledgments directly from the notification shade.

---

## Architecture & Technology Stack

- **Framework**: Flutter (Dart)
- **Protocol**: Nostr (WebSocket Relays)
- **Encryption**: NIP-04 (AES-256-CBC)
- **Voice Communication**: `flutter_webrtc`
- **Local Database**: Hive (`hive_flutter`)
- **Username Resolution**: Firebase Realtime Database
- **Push Notifications**: Firebase Cloud Messaging (`firebase_messaging`)

---

## Getting Started

### Prerequisites
- Flutter SDK (`>=3.4.4 <4.0.0`)
- Target platform development environment (Android / iOS)

### Installation

```bash
# Clone the repository
git clone https://github.com/elregann/chatme
cd chatme

# Install dependencies
flutter pub get

# Run the application
flutter run
```

---

## Privacy & Security

Chatme operates under a zero-knowledge trust model regarding user data and credentials. All message encryption occurs locally before relay transmission. Firebase services are restricted exclusively to username resolution (Global ID) and push notification dispatch, retaining no access to message payloads or private keys.

---

## License

Distributed under the MIT License. See [LICENSE](LICENSE) for more details.

---

Developed by [@elregann](https://github.com/elregann).
