// privacy_policy_content.dart
//
// In-app privacy policy content. Kept out of tab_profile.dart so the policy
// can grow without turning the profile screen into a wall of text.

class PrivacyPolicySection {
  final String title;
  final List<String> paragraphs;
  final List<String> bullets;

  const PrivacyPolicySection({
    required this.title,
    this.paragraphs = const [],
    this.bullets = const [],
  });
}

class PrivacyPolicyContent {
  PrivacyPolicyContent._();

  static const String lastUpdated = 'November 2026';

  static const String intro =
      'Chatme is a decentralized messenger built on the Nostr protocol. '
      'This policy explains, in plain language, how Chatme handles data on '
      'your device, what is encrypted, and what relays or services can '
      'observe when you use the app.';

  static const List<PrivacyPolicySection> sections = [
    PrivacyPolicySection(
      title: 'Your Identity and Keys',
      paragraphs: [
        'Your Chatme account is a Nostr keypair. You can create a 12-word '
            'recovery phrase or import an existing nsec, hex private key, or '
            'recovery phrase.',
        'Your private key and recovery phrase stay on your device in secure '
            'system storage. Chatme does not upload them to Chatme servers.',
      ],
      bullets: [
        'If you lose your private key and recovery phrase, your account '
            'cannot be recovered.',
        'Anyone with your private key or recovery phrase can control your '
            'account.',
      ],
    ),
    PrivacyPolicySection(
      title: 'Messages',
      paragraphs: [
        'Private messages are end-to-end encrypted with NIP-17 gift wraps '
            'and NIP-44 encryption. Relays deliver encrypted events, but they '
            'cannot read your message content.',
        'Reactions, read receipts, and call signaling are also sent inside '
            'encrypted gift wraps.',
      ],
      bullets: [
        'Deleting a message removes it from your device. It does not remove '
            'the other person\'s copy.',
        'Chatme can read old NIP-04 messages for compatibility, but does '
            'not send new NIP-04 messages.',
      ],
    ),
    PrivacyPolicySection(
      title: 'Calls, Media, and Stories',
      paragraphs: [
        'Voice call signaling is sent through encrypted Nostr gift wraps. '
            'Call audio uses WebRTC with DTLS-SRTP encryption and is '
            'peer-to-peer when possible. On restrictive networks, STUN/TURN '
            'services may help connect the call and can see network metadata '
            'such as your IP address.',
        'Photos, videos, and voice notes are encrypted on your device with a '
            'fresh AES-GCM key before upload to a Blossom file server. The '
            'decryption key travels inside the encrypted message, not to the '
            'file server in plaintext.',
        'Stories are a Chatme prototype. They are encrypted, sent to your '
            'saved Chatme contacts and your own account, and hidden locally '
            'after 24 hours.',
      ],
      bullets: [
        'File servers can see encrypted files, size, upload time, and your '
            'IP address, but not the file content.',
        'Downloaded media stays decrypted on your device for app use. '
            'Deleting a message does not remove an already downloaded file.',
        'Story deletion/retract is best effort. When you delete a story or '
            'sign out, Chatme also asks the Blossom server to delete the '
            'encrypted blob when possible. Offline devices, relays, or file '
            'servers may still retain copies for a while, and older stories '
            'without a local upload key cannot be remotely deleted by this '
            'device.',
      ],
    ),
    PrivacyPolicySection(
      title: 'Relays, Global ID, and Public Profile',
      paragraphs: [
        'You can choose which relays and file servers Chatme connects to. '
            'Relays, file servers, and search relays can observe network '
            'metadata such as your IP address and connection timing.',
        'Global ID is optional. If you claim a `username@chatme`, the Chatme '
            'directory maps that username to your public key so others can '
            'find you.',
      ],
      bullets: [
        'Your profile (name, picture, NIP-05/Global ID, bio/about) is public '
            'Nostr profile data when published to relays.',
        'Global search sends your search words to the selected search '
            'relays.',
        'QR codes contain public contact info such as your public key and '
            'limited relay hints.',
      ],
    ),
    PrivacyPolicySection(
      title: 'Notifications and Local Data',
      paragraphs: [
        'Chatme may use Android notifications and Firebase Cloud Messaging '
            'for background delivery. The push pipeline should not receive your '
            'private key or plaintext message content, but it can carry '
            'metadata such as public keys, event IDs, timing, and encrypted '
            'payload data.',
        'Chatme stores local app data on your device, including chats, '
            'contacts, settings, caches, stories, and downloaded media.',
      ],
      bullets: [
        'Link previews are off by default. If enabled, your device fetches '
            'the linked page directly, and that website can see your IP '
            'address.',
        'Read receipts can be turned off in settings.',
        'Gallery save for received media is optional.',
      ],
    ),
    PrivacyPolicySection(
      title: 'Logout and Limits',
      paragraphs: [
        'Signing out wipes local Chatme data from this device, including '
            'local chats, contacts, settings, caches, stories, downloaded '
            'media, notifications, and identity secrets stored by the app. It '
            'also tries to unsubscribe push topics and retract active stories.',
        'Chatme cannot guarantee deletion from relays, file servers, other '
            'users\' devices, backups, or infrastructure outside your control.',
      ],
      bullets: [
        'Chatme is beta software and has not been independently audited.',
        'This policy describes current app behavior and may change as '
            'Chatme evolves.',
      ],
    ),
  ];
}
