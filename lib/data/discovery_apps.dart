// discovery_apps.dart

/// One curated Nostr web app in the Discovery tab.
///
/// Every entry ships with its own logo, bundled as a local asset. That keeps
/// the directory fully offline-capable and avoids the broken-icon problem of
/// guessing remote `apple-touch-icon` paths.
class DiscoveryApp {
  const DiscoveryApp({
    required this.name,
    required this.url,
    required this.description,
    required this.iconAsset,
  });

  final String name;
  final String url;
  final String description;
  final String iconAsset;

  /// The bare host, shown under the app name in the in-app browser.
  String get host => Uri.parse(url).host;
}

/// A short, hand-picked list of well-known, reachable Nostr web apps.
///
/// Local data only: no API, no fetch, no user state. The selection follows the
/// same sources as Amethyst's Discover list (nostrapps.com + awesome-nostr) and
/// 0xchat's curated NApp directory, narrowed down to widely used apps whose
/// homepages and icons were verified to respond. Inactive or dead entries are
/// left out on purpose.
const List<DiscoveryApp> discoveryApps = [
  DiscoveryApp(
    name: 'Primal',
    url: 'https://primal.net',
    description: 'Fast social client with a built-in wallet',
    iconAsset: 'assets/discovery_icons/primal.png',
  ),
  DiscoveryApp(
    name: 'Coracle',
    url: 'https://coracle.social',
    description: 'Relay-savvy client with custom feeds',
    iconAsset: 'assets/discovery_icons/coracle.jpg',
  ),
  DiscoveryApp(
    name: 'Snort',
    url: 'https://snort.social',
    description: 'Established, fast social client',
    iconAsset: 'assets/discovery_icons/snort.jpg',
  ),
  DiscoveryApp(
    name: 'noStrudel',
    url: 'https://nostrudel.ninja',
    description: 'Power-user client and protocol explorer',
    iconAsset: 'assets/discovery_icons/nostrudel.png',
  ),
  DiscoveryApp(
    name: 'Iris',
    url: 'https://iris.to',
    description: 'Simple, lightweight social client',
    iconAsset: 'assets/discovery_icons/iris.png',
  ),
  DiscoveryApp(
    name: 'Nostria',
    url: 'https://nostria.app',
    description: 'Social, communities and media',
    iconAsset: 'assets/discovery_icons/nostria.png',
  ),
  DiscoveryApp(
    name: 'Jumble',
    url: 'https://jumble.social',
    description: 'Browse feeds relay by relay',
    iconAsset: 'assets/discovery_icons/jumble.png',
  ),
  DiscoveryApp(
    name: 'Ditto',
    url: 'https://ditto.pub',
    description: 'Friendly, accessible social client',
    iconAsset: 'assets/discovery_icons/ditto.png',
  ),
  DiscoveryApp(
    name: 'YakiHonne',
    url: 'https://yakihonne.com',
    description: 'Social feed, articles and creator tools',
    iconAsset: 'assets/discovery_icons/yakihonne.png',
  ),
  DiscoveryApp(
    name: 'Nostter',
    url: 'https://nostter.app',
    description: 'Simple Twitter-style web client',
    iconAsset: 'assets/discovery_icons/nostter.png',
  ),
  DiscoveryApp(
    name: 'Habla',
    url: 'https://habla.news',
    description: 'Long-form articles and blogs',
    iconAsset: 'assets/discovery_icons/habla.png',
  ),
  DiscoveryApp(
    name: 'Highlighter',
    url: 'https://highlighter.com',
    description: 'Highlights, reading and discovery',
    iconAsset: 'assets/discovery_icons/highlighter.png',
  ),
  DiscoveryApp(
    name: 'Flotilla',
    url: 'https://flotilla.social',
    description: 'Community spaces and group chat',
    iconAsset: 'assets/discovery_icons/flotilla.png',
  ),
  DiscoveryApp(
    name: 'zap.stream',
    url: 'https://zap.stream',
    description: 'Live streams with Lightning zaps',
    iconAsset: 'assets/discovery_icons/zapstream.png',
  ),
  DiscoveryApp(
    name: 'Olas',
    url: 'https://olas.app',
    description: 'Photos and media on Nostr',
    iconAsset: 'assets/discovery_icons/olas.png',
  ),
  DiscoveryApp(
    name: 'Zaptrax',
    url: 'https://zaptrax.app',
    description: 'Music streaming with value for value',
    iconAsset: 'assets/discovery_icons/zaptrax.png',
  ),
  DiscoveryApp(
    name: 'nostr.build',
    url: 'https://nostr.build',
    description: 'Image and media uploads',
    iconAsset: 'assets/discovery_icons/nostrbuild.png',
  ),
  DiscoveryApp(
    name: 'nostrcheck',
    url: 'https://nostrcheck.me',
    description: 'NIP-05 identity and media hosting',
    iconAsset: 'assets/discovery_icons/nostrcheck.jpg',
  ),
  DiscoveryApp(
    name: 'Nstart',
    url: 'https://nstart.me',
    description: 'Guided Nostr account setup',
    iconAsset: 'assets/discovery_icons/nstart.png',
  ),
  DiscoveryApp(
    name: 'Plebeian Market',
    url: 'https://plebeian.market',
    description: 'Bitcoin-native marketplace',
    iconAsset: 'assets/discovery_icons/plebeianmarket.png',
  ),
  DiscoveryApp(
    name: 'Alby',
    url: 'https://getalby.com',
    description: 'Bitcoin wallet and Nostr signer',
    iconAsset: 'assets/discovery_icons/alby.png',
  ),
  DiscoveryApp(
    name: 'Openvibe',
    url: 'https://openvibe.social',
    description: 'Social client for the open internet',
    iconAsset: 'assets/discovery_icons/openvibe.png',
  ),
  DiscoveryApp(
    name: 'Nosotros',
    url: 'https://nosotros.app',
    description: 'Fast, minimal social client',
    iconAsset: 'assets/discovery_icons/nosotros.png',
  ),
  DiscoveryApp(
    name: 'Nym',
    url: 'https://nym.bar',
    description: 'Anonymous chat with encrypted DMs',
    iconAsset: 'assets/discovery_icons/nym.png',
  ),
  DiscoveryApp(
    name: 'Primal Studio',
    url: 'https://studio.primal.net',
    description: 'Creator tools from the Primal team',
    iconAsset: 'assets/discovery_icons/primalstudio.png',
  ),
  DiscoveryApp(
    name: 'Nostr Doctor',
    url: 'https://nostr.doctor',
    description: 'Diagnose and fix your Nostr account',
    iconAsset: 'assets/discovery_icons/nostrdoctor.png',
  ),
  DiscoveryApp(
    name: 'Nests',
    url: 'https://nostrnests.com',
    description: 'Audio rooms on Nostr',
    iconAsset: 'assets/discovery_icons/nests.png',
  ),
  DiscoveryApp(
    name: 'Shosho',
    url: 'https://shosho.live',
    description: 'Live video streaming',
    iconAsset: 'assets/discovery_icons/shosho.png',
  ),
  DiscoveryApp(
    name: 'Nostu',
    url: 'https://nostu.be',
    description: 'Video and music discovery',
    iconAsset: 'assets/discovery_icons/nostu.png',
  ),
  DiscoveryApp(
    name: 'Mostro',
    url: 'https://mostro.network',
    description: 'No-KYC P2P Lightning marketplace',
    iconAsset: 'assets/discovery_icons/mostro.png',
  ),
  DiscoveryApp(
    name: 'Oddbean',
    url: 'https://oddbean.com',
    description: 'Hacker News style discussions',
    iconAsset: 'assets/discovery_icons/oddbean.png',
  ),
  DiscoveryApp(
    name: 'Nostrord',
    url: 'https://web.nostrord.com',
    description: 'NIP-29 decentralized group chat',
    iconAsset: 'assets/discovery_icons/nostrord.png',
  ),
];
