<div align="center">

<img src="docs/design/icon/chatme.svg" alt="Chatme logo" width="120" height="120">

# Chatme

**Decentralized, end-to-end encrypted messenger with voice calls, voice notes, pictures and videos, built with Flutter on the Nostr protocol.**

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Platform: Android](https://img.shields.io/badge/platform-Android-3DDC84.svg)
![Flutter](https://img.shields.io/badge/built%20with-Flutter-02569B.svg)
![Protocol: Nostr](https://img.shields.io/badge/protocol-Nostr-8E44AD.svg)
[![XERJ Corpus Hub contributor](https://hub.xerj.org/contributors/elregann/badge.svg)](https://hub.xerj.org/contributors/elregann)
[![Wiki: DeepWiki](https://img.shields.io/badge/wiki-DeepWiki-2EA6A0.svg)](https://deepwiki.com/elregann/Chatme)
![Status: beta](https://img.shields.io/badge/status-beta-orange.svg)

</div>

Chatme is an instant messaging app where your identity is a cryptographic key you own: no phone number, no email, and no central server holding your account. Messages and call signaling travel through Nostr relays, encrypted on your device before they leave it.

> **Status:** beta. Android is the primary target. A web build runs in Chrome for testing, but voice notes and QR scanning need Android.

---

## Features

### Messaging
- Direct messages using **NIP-17 gift wrap** with **NIP-44** encryption (rumor, seal, and gift wrap layers), so relays cannot read the content or easily see who is talking to whom. Legacy NIP-04 messages are still understood.
- Replies, emoji reactions, delivery and read status, and date grouping.
- Long press a message for a floating bar of quick reactions, a plus button that opens a categorized emoji sheet, and Reply, Copy and Delete. Delete removes the message from this device only; the other person keeps their copy.
- Emoji panel in the input bar that takes the exact place of the keyboard and swaps with it smoothly.
- Offline outbox: messages and voice notes written without a connection are sent automatically when the network returns.
- Optional link previews, off by default.
- Read receipts that you can turn off.
- Names, profile pictures and bios from standard Nostr profile metadata (kind `0`). Your bio is edited under Global ID and shown below your name in Me; a contact's bio appears under their `npub`. A long bio is clipped to a few lines and opens in a scrollable sheet when tapped. Text written by other people is always shown as plain text.

### Voice notes
- Tap the microphone to record, then send or cancel from the recording bar.
- Sent as NIP-17 file messages (kind `15`). The audio is encrypted on your device with AES-GCM and a fresh key for every file, then uploaded to a Blossom server. The key travels only inside the gift wrapped message.
- Received voice notes are downloaded on tap, checked against their hash, decrypted and played in the chat.
- Every voice note of a conversation is listed in the Voice tab of the contact profile.

### Pictures and videos
- Pictures are resized to an upright JPEG with no camera or location data, then encrypted with AES-GCM and a fresh key for every file.
- Videos are encrypted in 256 KiB chunks while they are uploaded, so a large video never has to fit in memory. Every chunk is authenticated, and the receiver checks the size and hash as the bytes arrive and discards the file if anything is wrong.
- Both are sent as NIP-17 file messages (kind `15`) to a Blossom server, the same way as voice notes. The key travels only inside the gift wrapped message.
- In the contact profile, the Media tab is a grid of every picture and video of the conversation. It opens a swipeable gallery where a video starts playing as soon as its page is on screen.

### Contacts
- Add a contact with an `npub`, an `nprofile`, a `nostr:` link or a QR code.
- Your own QR code is one tap away from the Me tab, and each contact profile has one too. Scanning a code fills in the add contact form.
- Contact profile with a Media tab and a Voice tab.
- Global search finds people in two places at once: the Chatme directory of `username@chatme` handles, and the wider Nostr ecosystem through **NIP-50** profile search on the Search relays. Chatme names appear first, results are matched by public key, and the relay a result came from is shown under the name. Searching an `npub` or a hex public key looks that profile up directly instead of using full text search.

### Voice calls
- Peer-to-peer voice calls with WebRTC.
- Call signaling over Nostr relays, with no dedicated signaling server.
- STUN and TURN support for strict networks such as mobile data.
- Incoming call notifications with Answer and Decline, system ringtone, and caller photo.
- Calls reconnect by themselves after a network change, and stay connected while the app is in the background.
- Call history in the Calls tab and in the chat, including declined and missed calls.

### Notifications
- Push notifications while the app is closed, through Firebase Cloud Messaging.
- Conversation-style notifications grouped per contact, with name and photo.
- Reply and Mark as Read directly from the notification.

### Identity and security
- Accounts are secp256k1 keypairs (BIP-340 Schnorr signatures).
- Security Vault to view and export `npub` and `nsec` keys.
- BIP-39 recovery phrase (NIP-06) for backup and restore, compatible with other Nostr clients.
- Converter between hexadecimal and NIP-19 Bech32 keys.
- Optional Global ID handle (`username@chatme`). A `name@chatme` handle is shown on a profile only when the Chatme directory confirms that the public key is registered under that username. Every other profile is labelled **Nostr user**, so a kind `0` profile name can never impersonate a Chatme username. Adding a NIP-50 search result never saves the profile name as a Chatme handle.
- Bios are published as the `about` field of the kind `0` profile. A bio is public: it is stored on the relays your profile reaches, and it can be set with or without a claimed Global ID.

### Relays and file servers
- Simultaneous connections to multiple relays with live status.
- Automatic reconnection with exponential backoff.
- NIP-42 authentication for relays that require it.
- The relay list is yours to edit in Me, Network, Relays. Inbox relays are where people send you messages and are announced to other clients. Search relays answer NIP-50 profile searches for the global search box, and are only connected while a search is running. Other relays are extra connections. Built in relays are marked Default, any relay can be removed or added, and Reset to defaults brings the originals back. Changes connect or disconnect relays right away, without restarting the app.
- Search relays are kept separate from message relays on purpose. Results are never written to your contact list or profile cache; a profile is saved only when you tap Add. Removing every search relay turns off relay search, so global search then only finds Chatme handles.
- File servers are edited the same way in Me, Network, File servers. Voice notes, pictures and videos are uploaded to the servers from top to bottom, up to five, and the next one is used when a server fails. A new server gets a small test upload before it is added.

---

## Supported NIPs

Status: Yes means fully supported, Partial means only part of the NIP is implemented.

| NIP | Description | Status | Notes |
| --- | --- | --- | --- |
| [01](https://github.com/nostr-protocol/nips/blob/master/01.md) | Basic protocol flow | Yes | Events, `REQ`, `EVENT`, `OK`, BIP-340 Schnorr signatures. Profile metadata (kind `0`) is published and read, including the `name`, `picture`, `nip05` and `about` fields. Kind `0` keeps the newest `created_at`, with the lowest event id winning a tie, and remembers the winner across restarts. |
| [04](https://github.com/nostr-protocol/nips/blob/master/04.md) | Encrypted direct messages (legacy) | Partial | Receive only (kind `4`), so older conversations stay readable. New messages never use it. |
| [05](https://github.com/nostr-protocol/nips/blob/master/05.md) | DNS-based identifiers | Partial | The `nip05` field is published in the profile. The `username@chatme` handle is verified through Chatme's own backend, not a `.well-known/nostr.json` lookup. |
| [06](https://github.com/nostr-protocol/nips/blob/master/06.md) | Key derivation from mnemonic seed phrase | Yes | 12 word BIP-39 phrase, derived with BIP-32 at `m/44'/1237'/0'/0/0`. The same phrase gives the same account in other NIP-06 clients. |
| [17](https://github.com/nostr-protocol/nips/blob/master/17.md) | Private direct messages | Partial | Rumor (kind `14`), file message (kind `15`, used for voice notes, pictures and videos), seal (kind `13`), gift wrap (kind `1059`). Publishes your Inbox relays as the DM relay list (kind `10050`), and again whenever you change them, so other clients such as Amethyst can reach Chatme. It does not read the recipient's kind `10050` yet, so messages go to the relays Chatme is connected to. |
| [19](https://github.com/nostr-protocol/nips/blob/master/19.md) | bech32 encoded entities | Partial | `npub` and `nsec` (view, export, convert, add contact), plus `nprofile` for contact QR codes and when adding a contact. Other entities such as `nevent` and `naddr` are not handled. |
| [21](https://github.com/nostr-protocol/nips/blob/master/21.md) | `nostr:` URI scheme | Partial | Contact QR codes hold a `nostr:nprofile` link, and `nostr:npub` and `nostr:nprofile` are accepted when adding a contact. Secret keys are refused. Other entities are not handled. |
| [24](https://github.com/nostr-protocol/nips/blob/master/24.md) | Extra metadata fields | Partial | The `display_name` field is read from kind `0` search results and used as a label when `name` is empty. Contacts and Me use `name`; other extra fields such as `website`, `banner`, `bot` and `birthday` are not displayed. |
| [25](https://github.com/nostr-protocol/nips/blob/master/25.md) | Reactions | Yes | Kind `7`, sent inside a gift wrap. |
| [42](https://github.com/nostr-protocol/nips/blob/master/42.md) | Authentication of clients to relays | Yes | Answers `AUTH` challenges (kind `22242`) for relays that require it. |
| [44](https://github.com/nostr-protocol/nips/blob/master/44.md) | Versioned encryption | Yes | Encrypts both the seal and the gift wrap. |
| [50](https://github.com/nostr-protocol/nips/blob/master/50.md) | Search capability | Partial | Global search sends kind `0` filters with a `search` term to the relays listed under Search relays. Results are signature checked, deduplicated by public key, and the newest kind `0` wins. An `npub` or hex key is looked up with an `authors` filter instead. Only profile search is used, not note search. |
| [59](https://github.com/nostr-protocol/nips/blob/master/59.md) | Gift wrap | Yes | Wraps every private message, reaction, receipt and call signal. |
| [98](https://github.com/nostr-protocol/nips/blob/master/98.md) | HTTP auth | Yes | Kind `27235`, used to authorize profile photo uploads and Global ID requests. |

Not implemented yet: NIP-65 relay list metadata and NIP-09 event deletion.

### Other specifications

| Specification | Used for | Notes |
| --- | --- | --- |
| [Blossom](https://github.com/hzrd149/blossom) (BUD-01, BUD-02) | Storing encrypted voice notes, pictures and videos | `PUT /upload` with a kind `24242` authorization event. Defaults are `blossom.ditto.pub`, `blossom.jumble.social` and `nostr.download`, tried in that order, and the list can be changed in the app. Each upload is signed with a throwaway key, never the account key. Some Blossom servers, such as `blossom.nostr.build` and `blossom.primal.net`, refuse encrypted files by policy, so they are not used by default. |

### Event kinds used

| Kind | Name | Where | Used for |
| ---: | --- | --- | --- |
| `0` | Profile metadata | Public | Display name, picture, `nip05` and the `about` bio. Also read from search relays through NIP-50. |
| `1` | Short text note | Public | Read only, legacy fallback for plain messages. |
| `4` | Encrypted direct message (NIP-04) | Public | Read only, legacy fallback. |
| `7` | Reaction | Inside gift wrap | Emoji reactions to a message. |
| `13` | Seal | Inside gift wrap | Signed by the sender, NIP-44 encrypted rumor. |
| `14` | Chat message (rumor) | Inside seal | The message itself. Unsigned. |
| `15` | File message (rumor) | Inside seal | A voice note, picture or video: the link to the encrypted file, plus the key, nonce and hashes the receiver needs. Unsigned. |
| `1059` | Gift wrap | Public | Signed with a one-time key, hides sender and content from relays. |
| `10050` | DM relay list | Public | Tells other clients which relays deliver messages to Chatme. It holds your Inbox relays. |
| `22242` | Client authentication | Sent to relay | Answer to a relay `AUTH` challenge. |
| `24242` | Blossom authorization | Sent to file server | Authorizes one upload. Signed with a throwaway key. |
| `27235` | HTTP auth | Sent to HTTP server | Authorizes photo uploads and Global ID requests. |
| `3329` | Read receipt (custom) | Inside gift wrap | Chatme specific. Marks a message as read. |
| `3330` | Call signal (custom) | Inside gift wrap | Chatme specific. WebRTC offer, answer, ICE candidate, ICE restart offer and hang up. |

Kinds `3329` and `3330` are Chatme's own conventions and are not part of any NIP. Other clients ignore them, and a call or read receipt only works between two Chatme users. Voice notes add one extra tag, `duration` (in seconds), to the standard kind `15` tags. A video adds an `alg` tag with the value `aes-gcm-chunked`, which is Chatme's own chunked layout, so other clients cannot open it. Other clients ignore the extra tags.

---

## Tech stack

| Area | Technology |
| --- | --- |
| Framework | Flutter (Dart) |
| Protocol | Nostr (WebSocket relays), NIP-17, NIP-44 |
| Voice calls | `flutter_webrtc` |
| Voice notes | `record`, `just_audio`, AES-GCM file encryption |
| Pictures and videos | `image_picker`, `video_player`, AES-GCM, chunked AES-GCM streaming for videos |
| Rendering | Skia on Android. Impeller is turned off because its Vulkan backend lost the GPU while playing video on a Samsung phone |
| File storage | Blossom servers |
| QR codes | `qr_flutter`, `mobile_scanner` |
| Local storage | Hive |
| Push notifications | Firebase Cloud Messaging, `flutter_local_notifications` |
| Push delivery | Cloudflare Worker |
| Global ID | Cloudflare Worker that checks Nostr signed requests, with Firebase Realtime Database |

---

## Getting started

### Prerequisites
- Flutter 3.38 or newer (the dependency lock file requires it)
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
- Voice notes, pictures and videos upload to public Blossom servers and need no setup. Those servers set their own rules, so the defaults may change, and you can pick your own in the app. The app asks for microphone permission to record and camera permission to scan QR codes.
- Release builds rely on `android/app/proguard-rules.pro` and `android/app/src/main/res/raw/keep.xml`. Keep them, or notifications will break.
- Never commit secrets, API keys, or TURN credentials to a public repository.

---

## Privacy and security

- Messages are encrypted on your device before sending. Private keys never leave it.
- Relays see encrypted events, not message content.
- Voice notes, pictures and videos are encrypted on your device with a fresh key before upload, and the key is sent only inside the gift wrapped message. File servers see the encrypted file, its size, the time and your IP address, but not the content. Uploads are signed with a throwaway key, so the signature does not link them to your account or to each other, although the IP address and timing still can.
- Downloaded files are kept decrypted on your device. Deleting a message removes it from the chat, but does not remove a file that was already downloaded.
- Link previews are off by default. When you turn them on, your device fetches the linked page directly, so that website can see your IP address.
- A QR code holds only your public key and two relay hints. Read receipts can be turned off.
- The push pipeline (Cloudflare Worker and FCM) never receives plaintext or private keys, but it does carry metadata such as public keys, event IDs, and timing, plus the encrypted payload.
- Relays can still observe connection metadata such as IP addresses. A relay or file server you add yourself can see your IP address too, but never the content of your messages or files.
- Global search sends your search words to the Search relays you selected. Those relays can see the words and your IP address, so you can remove any of them or turn relay search off completely.
- This project has not been independently audited.

---

## License

Distributed under the MIT License. See [LICENSE](LICENSE) for details.

Developed by [@elregann](https://github.com/elregann).