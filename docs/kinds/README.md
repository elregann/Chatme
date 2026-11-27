# Chatme custom Nostr kinds

This folder documents the private event conventions Chatme uses for features Nostr has not standardized yet. It describes the **current implementation**, not a proposal. None of these kinds is a registered NIP, and Chatme does not define a new protocol.

## Honest summary

Chatme builds on existing specifications:

- **NIP-17 / NIP-59** for private messages: an unsigned inner rumor, a kind `13` seal encrypted with NIP-44, and a kind `1059` gift wrap encrypted with NIP-44 and signed by a one-time key.
- **NIP-01** event ids: the rumor id is `sha256` of the JSON array `[0, pubkey, created_at, kind, tags, content]`. The rumor itself is not signed; the seal is the layer that authenticates the real sender.
- **Kind `15` file messages** for media. Chatme reuses its normal file layout for story media, with the encrypted blob stored on a Blossom server and the key, nonce and hashes carried inside the gift-wrapped rumor.

On top of that envelope, Chatme uses inner rumor kinds `3329`–`3332` for its own features. Those numbers are **Chatme-only conventions**, not registered or standardized kinds. Other clients have no defined behavior for them and normally ignore them. A read receipt, call signal, story or story view receipt only works when both sides run a Chatme build that understands the same convention. Story kinds are prototypes and may change.

Kind numbers are not globally reserved here. Collisions are possible in principle; Chatme reduces confusion by routing on the exact kind **and** the expected tags or content, and by applying the application checks documented on each page.

## Kind index

| Kind | Name | Status | Details |
| ---: | --- | --- | --- |
| `3329` | Read receipt | Chatme convention | [3329.md](3329.md) |
| `3330` | Call signal | Chatme convention | [3330.md](3330.md) |
| `3331` | Story post or retract | Chatme prototype | [3331.md](3331.md) |
| `3332` | Story view receipt | Chatme prototype | [3332.md](3332.md) |

For the standard kinds used alongside these, see the [main README](../../README.md), especially **Supported NIPs** and **Event kinds used**.

## Shared envelope

Relays only ever see the gift wrap. An illustrative public event looks like this:

```json
{
  "kind": 1059,
  "pubkey": "<one-time 64-hex pubkey>",
  "created_at": 1760000001,
  "tags": [["p", "<recipient 64-hex pubkey>"]],
  "content": "<NIP-44 ciphertext of the signed seal>",
  "id": "<64-hex sha256 event id>",
  "sig": "<BIP-340 signature by the one-time key>"
}
```

The seal and gift wrap use randomized timestamps in the past two days, so their `created_at` values are deliberately not the same as the inner rumor's timestamp. The recipient decrypts both layers, verifies the seal id and signature, and checks that the rumor's `pubkey` matches the seal's `pubkey`. Only then is the custom kind routed to the application code.

The decrypted rumor always has this shape:

```json
{
  "pubkey": "<sender 64-hex pubkey>",
  "created_at": 1760000000,
  "kind": 3329,
  "tags": [["e", "<target 64-hex id>"], ["p", "<recipient 64-hex pubkey>"]],
  "content": "read",
  "id": "<64-hex sha256 of [0, pubkey, created_at, kind, tags, content]>"
}
```

Notes that matter for interoperability:

- Tags are arrays of strings. There are no nested tag objects.
- The rumor has an `id` but no `sig`. Do not expect a signature on the innermost event.
- Chatme's unwrapper only accepts the inner kinds it knows: `14`, `15`, `7`, `3329`, `3330`, `3331` and `3332`. Unknown inner kinds are rejected before application routing.
- Chatme publishes each wrap to all currently connected relays whose status is up. It does not look up the recipient's kind `10050` relay list before sending.
- These custom messages have no delivery acknowledgement of their own. A call signal, read receipt, story or view receipt can be dropped by a relay; each feature has its own best-effort behavior.

## What is modified, and what is not

| Layer | Source | What Chatme changes |
| --- | --- | --- |
| Event id | NIP-01 | Nothing. The same serialization is used for custom rumor kinds. |
| Encryption | NIP-44 | Nothing. Both the seal and the gift wrap use it. |
| Privacy envelope | NIP-17 / NIP-59 | Nothing. The three-layer structure is unchanged. |
| Inner rumor kind | NIP-17 allows application kinds | Chatme assigns `3329`–`3332` privately for its own features. |
| Tags and plaintext | Application layer | Each custom page below defines the exact tags and content Chatme reads and writes. |
| Media files | Blossom + kind `15` file layout | Story media reuses the file tags; the binary stays outside the Nostr event. |

## Code map

| File | Role |
| --- | --- |
| `lib/core/crypto/nip17.dart` | Kind constants, wrap/unwrap, NIP-44 layers, seal verification and rumor id computation. |
| `lib/core/crypto/nip17_isolate.dart` | Background/isolate wrapping used by the call-signal path. |
| `lib/core/crypto/nip17_file.dart` | Kind `15` file tags, validation and the local `alg` field name. |
| `lib/relay_manager.dart` | Sends and routes read receipts, call signals, story posts and view receipts. |
| `lib/story/story_event.dart` | Story, retract and view-receipt tag builders and validators. |
| `lib/story/story_manager.dart` | Story publish, retract, receive, local view state and local media caching. |
| `lib/call_manager.dart` | WebRTC signal types and their handling. |
| `lib/core/utils/background_chat_actions.dart` | Read receipts sent while the app is in the background. |
| `lib/core/utils/background_call_signal.dart` | Background hangup signal. |

When reading a page, treat the JSON examples as **shape illustrations with anonymized placeholders**, not as captured production events.
