import 'dart:convert';
import 'dart:math';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:crypto/crypto.dart';
import 'package:hex/hex.dart';
import 'package:bip340/bip340.dart' as bip340;
import 'notification_handler.dart';
import 'call.dart';
import 'roomchat.dart';
import 'relaymanager.dart';
import 'chatmanager.dart';
import 'tabcontact.dart';
import 'tabprofile.dart';
import 'tabchat.dart';

part 'main.g.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class DebugLogger {
  static final Map<String, List<String>> _logs = {};
  static bool _enabled = true;

  static void enable() => _enabled = true;
  static void disable() => _enabled = false;

  static void log(String message, {String type = 'INFO', String? tag}) {
    if (!_enabled) return;

    final timestamp = DateTime.now().toIso8601String();
    final logEntry = '[$timestamp][$type] ${tag != null ? '[$tag] ' : ''}$message';

    print(logEntry);

    if (!_logs.containsKey(type)) {
      _logs[type] = [];
    }
    _logs[type]!.insert(0, logEntry);
    if (_logs[type]!.length > 1000) {
      _logs[type]!.removeLast();
    }
  }

  static List<String> getLogs({String? type}) {
    if (type != null) {
      return _logs[type] ?? [];
    }
    return _logs.values.expand((list) => list).toList();
  }

  static void clearLogs() {
    _logs.clear();
  }
}

class MessageAdapter extends TypeAdapter<ChatMessage> {
  @override final int typeId = 1;

  @override
  ChatMessage read(BinaryReader reader) {
    return ChatMessage(
      id: reader.readString(),
      senderPubkey: reader.readString(),
      receiverPubkey: reader.readString(),
      content: reader.readString(),
      plaintext: reader.readString(),
      timestamp: reader.readInt(),
      status: reader.readString(),
      chatKey: reader.readString(),
      replyToId: reader.readString().isEmpty ? null : reader.readString(),
      replyToContent: reader.readString().isEmpty ? null : reader.readString(),
      reactions: Map<String, String>.from(reader.readMap()),
    );
  }

  @override
  void write(BinaryWriter writer, ChatMessage obj) {
    writer.writeString(obj.id);
    writer.writeString(obj.senderPubkey);
    writer.writeString(obj.receiverPubkey);
    writer.writeString(obj.content);
    writer.writeString(obj.plaintext);
    writer.writeInt(obj.timestamp);
    writer.writeString(obj.status);
    writer.writeString(obj.chatKey);
    writer.writeString(obj.replyToId ?? '');
    writer.writeString(obj.replyToContent ?? '');
    writer.writeMap(obj.reactions);
  }
}

@HiveType(typeId: 0)
class Contact {
  @HiveField(0) final String pubkey;
  @HiveField(1) String name;
  @HiveField(2) int lastChatTime;
  @HiveField(3) String lastMessage;
  @HiveField(4) int unreadCount;
  @HiveField(5) bool isSaved;

  Contact({
    required this.pubkey,
    required this.name,
    this.lastChatTime = 0,
    this.lastMessage = '',
    this.unreadCount = 0,
    this.isSaved = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'pubkey': pubkey,
      'name': name,
      'lastChatTime': lastChatTime,
      'lastMessage': lastMessage,
      'unreadCount': unreadCount,
    };
  }
}

@HiveType(typeId: 1)
class ChatMessage {
  @HiveField(0) final String id;
  @HiveField(1) final String senderPubkey;
  @HiveField(2) final String receiverPubkey;
  @HiveField(3) final String content;
  @HiveField(4) final String plaintext;
  @HiveField(5) final int timestamp;
  @HiveField(6) String status;
  @HiveField(7) final String chatKey;
  @HiveField(8) final String? replyToId;
  @HiveField(9) final String? replyToContent;
  @HiveField(10, defaultValue: {})
  Map<String, String> reactions;

  ChatMessage({
    required this.id,
    required this.senderPubkey,
    required this.receiverPubkey,
    required this.content,
    required this.plaintext,
    required this.timestamp,
    this.status = 'sent',
    required this.chatKey,
    this.replyToId,
    this.replyToContent,
    this.reactions = const {},
  });

  ChatMessage copyWithStatus(String newStatus) {
    return ChatMessage(
      id: id,
      senderPubkey: senderPubkey,
      receiverPubkey: receiverPubkey,
      content: content,
      plaintext: plaintext,
      timestamp: timestamp,
      status: newStatus,
      chatKey: chatKey,
      replyToId: replyToId,
      replyToContent: replyToContent,
      reactions: Map.from(reactions),
    );
  }

  ChatMessage copyWith({
    String? id,
    String? senderPubkey,
    String? receiverPubkey,
    String? content,
    String? plaintext,
    int? timestamp,
    String? status,
    String? chatKey,
    String? replyToId,
    String? replyToContent,
    Map<String, String>? reactions,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      senderPubkey: senderPubkey ?? this.senderPubkey,
      receiverPubkey: receiverPubkey ?? this.receiverPubkey,
      content: content ?? this.content,
      plaintext: plaintext ?? this.plaintext,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      chatKey: chatKey ?? this.chatKey,
      replyToId: replyToId ?? this.replyToId,
      replyToContent: replyToContent ?? this.replyToContent,
      reactions: reactions ?? Map.from(this.reactions),
    );
  }
  void addReaction(String senderPubkey, String emoji) {
    reactions[senderPubkey] = emoji;
  }

  void removeReaction(String senderPubkey) {
    reactions.remove(senderPubkey);
  }

  bool hasReactionFrom(String senderPubkey) {
    return reactions.containsKey(senderPubkey);
  }

  String? getReactionFrom(String senderPubkey) {
    return reactions[senderPubkey];
  }

  bool get hasReactions => reactions.isNotEmpty;

  int get reactionCount => reactions.length;

  bool get isMe => senderPubkey == AppSettings.instance.myPubkey;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'senderPubkey': senderPubkey,
      'receiverPubkey': receiverPubkey,
      'content': content,
      'plaintext': plaintext,
      'timestamp': timestamp,
      'status': status,
      'chatKey': chatKey,
      'replyToId': replyToId,
      'replyToContent': replyToContent,
      'reactions': reactions,
    };
  }

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: map['id'],
      senderPubkey: map['senderPubkey'],
      receiverPubkey: map['receiverPubkey'],
      content: map['content'],
      plaintext: map['plaintext'],
      timestamp: map['timestamp'],
      status: map['status'] ?? 'sent',
      chatKey: map['chatKey'],
      replyToId: map['replyToId'],
      replyToContent: map['replyToContent'],
      reactions: Map<String, String>.from(map['reactions'] ?? {}),
    );
  }
}

class AppSettings {
  static final AppSettings _instance = AppSettings._internal();
  factory AppSettings() => _instance;
  AppSettings._internal();

  static AppSettings get instance => _instance;

  String myPubkey = '';
  String myPrivkey = '';
  String myName = '';
  ThemeMode themeMode = ThemeMode.dark;

  Future<void> load() async {
    try {
      final settingsBox = Hive.box('settings');
      myPubkey = settingsBox.get('my_pubkey', defaultValue: '');
      myPrivkey = settingsBox.get('my_privkey', defaultValue: '');
      myName = settingsBox.get('my_name', defaultValue: 'User${Random().nextInt(9999)}');

      final savedTheme = settingsBox.get('theme_mode', defaultValue: 'system');
      if (savedTheme == 'dark') {
        themeMode = ThemeMode.dark;
      } else if (savedTheme == 'light') {
        themeMode = ThemeMode.light;
      } else {
        themeMode = ThemeMode.system;
      }

      if (myPubkey.isEmpty) {
        final keypair = _generateNostrKeypair();
        myPubkey = keypair['public']!;
        myPrivkey = keypair['private']!;

        await settingsBox.put('my_pubkey', myPubkey);
        await settingsBox.put('my_privkey', myPrivkey);
        await settingsBox.put('my_name', myName);
        DebugLogger.log('Generated new Nostr identity: ${myPubkey.substring(0, 16)}...', type: 'SETUP');
      }

      DebugLogger.log('Settings loaded. Pubkey: ${myPubkey.substring(0, 16)}...', type: 'SETUP');
    } catch (e) {
      DebugLogger.log('Error loading settings: $e', type: 'ERROR');
      rethrow;
    }
  }

  Future<void> importAccount(String privkey) async {
    try {
      if (privkey.length != 64) throw 'Private key must be 64 characters';
      final newPubkey = bip340.getPublicKey(privkey);
      myPrivkey = privkey;
      myPubkey = newPubkey;

      final settingsBox = Hive.box('settings');
      await settingsBox.put('my_pubkey', myPubkey);
      await settingsBox.put('my_privkey', myPrivkey);

      DebugLogger.log('✅ Account restored: $myPubkey', type: 'SETUP');
    } catch (e) {
      DebugLogger.log('❌ Failed to import account: $e', type: 'ERROR');
      rethrow;
    }
  }

  Future<void> saveTheme(ThemeMode mode) async {
    themeMode = mode;
    String themeString;

    if (mode == ThemeMode.dark) {
      themeString = 'dark';
    } else if (mode == ThemeMode.light) {
      themeString = 'light';
    } else {
      themeString = 'system';
    }
    await Hive.box('settings').put('theme_mode', themeString);
  }

  Future<Map<String, dynamic>> backupKeys() async {
    try {
      final backupData = {
        'public_key': myPubkey,
        'private_key': myPrivkey,
        'name': myName,
        'backup_date': DateTime.now().toIso8601String(),
        'app': 'ChatMe',
        'version': '1.0.0',
      };

      final backupString = jsonEncode(backupData);
      await Clipboard.setData(ClipboardData(text: backupString));
      DebugLogger.log('Keys backed up to clipboard', type: 'SETUP');
      return backupData;
    } catch (e) {
      DebugLogger.log('Error backing up keys: $e', type: 'ERROR');
      rethrow;
    }
  }

  String exportKeys() {
    return '''
CHATME KEY BACKUP

IMPORTANT: Save this information in a secure place.
Without these keys, you will lose access to your account.

Public Key (for sharing):
$myPubkey

Private Key (NEVER SHARE!):
$myPrivkey

Name: $myName
Backup Date: ${DateTime.now().toString()}

Instructions:
1. Save this information in a password manager
2. Never share your private key with anyone
3. If you lose this, you cannot recover your account
''';
  }

  Map<String, String> _generateNostrKeypair() {
    try {
      final random = Random.secure();
      final bytes = List<int>.generate(32, (_) => random.nextInt(256));
      final privateKey = HEX.encode(bytes);
      final publicKey = bip340.getPublicKey(privateKey);
      return {'private': privateKey, 'public': publicKey};
    } catch (e) {
      DebugLogger.log('Error generating keypair: $e', type: 'ERROR');
      rethrow;
    }
  }
}

class NostrHelpers {
  static String generateEventId(Map<String, dynamic> event) {
    try {
      final serialized = jsonEncode([
        0,
        event['pubkey'],
        event['created_at'],
        event['kind'],
        event['tags'],
        event['content']
      ]);
      return sha256.convert(utf8.encode(serialized)).toString();
    } catch (e) {
      rethrow;
    }
  }

  static String serializeEvent(Map<String, dynamic> event) {
    return jsonEncode([
      0,
      event['pubkey'],
      event['created_at'],
      event['kind'],
      event['tags'],
      event['content']
    ]);
  }

  static String getChatKey(String pubkey1, String pubkey2) {
    final sorted = [pubkey1, pubkey2]..sort();
    return 'chat_${sorted[0]}_${sorted[1]}';
  }
}

class TimeUtils {
  static String formatTimeHumanized(int timestamp) {
    if (timestamp == 0) return '';

    final now = DateTime.now();
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final aWeekAgo = today.subtract(const Duration(days: 7));
    final targetDate = DateTime(date.year, date.month, date.day);

    if (targetDate == today) {
      return DateFormat.jm().format(date);
    } else if (targetDate == yesterday) {
      return 'Yesterday';
    } else if (targetDate.isAfter(aWeekAgo)) {
      return DateFormat('EEEE').format(date);
    } else if (date.year == now.year) {
      return DateFormat('d MMM').format(date);
    } else {
      return DateFormat('d MMM yyyy').format(date);
    }
  }
}

class NetworkManager {
  static final NetworkManager _instance = NetworkManager._internal();
  factory NetworkManager() => _instance;
  NetworkManager._internal();

  bool _isConnected = true;

  Future<void> initialize() async {
    _isConnected = true;
  }

  bool get isConnected => _isConnected;

  Future<bool> checkConnection() async {
    return _isConnected;
  }

  void updateStatus(bool connected) {
    _isConnected = connected;
  }

  void dispose() {}
}

class Lock {
  bool _locked = false;
  final List<Completer<void>> _waiting = [];

  Future<T> synchronized<T>(Future<T> Function() task) async {
    while (_locked) {
      final completer = Completer<void>();
      _waiting.add(completer);
      await completer.future;
    }

    _locked = true;
    try {
      return await task();
    } finally {
      _locked = false;
      if (_waiting.isNotEmpty) {
        _waiting.removeAt(0).complete();
      }
    }
  }
}

class UIUtils {
  static Color getAvatarColor(String pubkey) {
    if (pubkey.isEmpty) return Colors.grey;
    try {
      return Color(int.parse(pubkey.substring(0, 8), radix: 16) | 0xFF000000);
    } catch (e) {
      return Colors.blueGrey;
    }
  }

  static String getInitials(String name) {
    if (name.trim().isEmpty) return "?";
    return name.trim().substring(0, 1).toUpperCase();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Hive.initFlutter();

    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ContactAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(ChatMessageAdapter());

    await Hive.openBox('settings');
    await Hive.openBox<Contact>('contacts');
    await Hive.openBox('chats');

    NotificationHandler.init().then((_) {
    });

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    await AppSettings.instance.load();
    await ChatManager.instance.cleanupTempMessages();

    FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    runApp(const ChatMeApp());

  } catch (e) {

    runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Text("Error saat memulai aplikasi: $e", textAlign: TextAlign.center),
          ),
        ),
      ),
    ));
  }
}

class ChatMeApp extends StatefulWidget {
  const ChatMeApp({super.key});

  @override
  State<ChatMeApp> createState() => _ChatMeAppState();
}

class _ChatMeAppState extends State<ChatMeApp> with WidgetsBindingObserver {
  final RelayManager _relayManager = RelayManager();
  final NetworkManager _networkManager = NetworkManager();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    NotificationHandler.onNotificationClick.stream.listen((String? payload) {
      if (payload != null && payload.isNotEmpty) {
        if (payload == 'incoming_call') {
          navigatorKey.currentState?.pushNamed('/call');
        } else {
          _navigateToChat(payload);
        }
      }
    });

    _requestIgnoreBatteryOptimization();

    Future.delayed(const Duration(milliseconds: 500), () {
      _relayManager.connect();
      _networkManager.initialize();
    });
  }

  Future<void> _requestIgnoreBatteryOptimization() async {
    if (kIsWeb) {
      print("🌐 Berjalan di Web: Skip permintaan izin baterai.");
      return;
    }

    try {
      if (Platform.isAndroid) {
        const channel = MethodChannel('com.chatme.app/battery');
        await channel.invokeMethod('requestIgnoreBatteryOptimization');
      }
    } catch (e) {
      print("❌ Gagal meminta izin baterai: $e");
    }
  }

  void _navigateToChat(String pubkey) {
    if (mounted) {
      final contactsBox = Hive.box<Contact>('contacts');
      final contact = contactsBox.get(pubkey);

      final chatContact = contact ?? Contact(
        pubkey: pubkey,
        name: 'User ${pubkey.substring(0, 8)}',
      );

      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (context) => ChatDetailScreen(
            contact: chatContact,
            relayManager: _relayManager,
          ),
        ),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      print('📱 App Resumed: Checking connection...');
      _relayManager.connect();
    } else if (state == AppLifecycleState.paused) {
      print('📱 App Paused: Staying connected in background...');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _relayManager.dispose();
    _networkManager.dispose();
    super.dispose();
  }

  void _toggleTheme(ThemeMode mode) async {
    await AppSettings.instance.saveTheme(mode);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: Hive.box('settings').listenable(),
      builder: (context, Box box, _) {
        final currentMode = AppSettings.instance.themeMode;

        return MaterialApp(
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.light,
            useMaterial3: true,
            colorSchemeSeed: Colors.blue,
            appBarTheme: const AppBarTheme(
              elevation: 0,
              centerTitle: true,
              surfaceTintColor: Colors.transparent,
              backgroundColor: Colors.transparent,
              systemOverlayStyle: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.dark,
                statusBarBrightness: Brightness.light,
              ),
            ),
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            useMaterial3: true,
            colorSchemeSeed: Colors.blue,
            appBarTheme: const AppBarTheme(
              elevation: 0,
              centerTitle: true,
              surfaceTintColor: Colors.transparent,
              backgroundColor: Colors.transparent,
              systemOverlayStyle: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.light,
                statusBarBrightness: Brightness.dark,
              ),
            ),
          ),
          themeMode: currentMode,
          initialRoute: '/',
          routes: {
            '/': (context) => MainScreen(
              relayManager: _relayManager,
              onThemeToggle: _toggleTheme,
              networkManager: _networkManager,
            ),
            '/call': (context) => CallScreen(
              peerName: "Panggilan Masuk",
              peerPubkey: "",
              isIncoming: true,
              relay: _relayManager,
              peerColor: Colors.blue,
            ),
          },
        );
      },
    );
  }
}

class MainScreen extends StatefulWidget {
  final RelayManager relayManager;
  final NetworkManager networkManager;
  final Function(ThemeMode) onThemeToggle;

  const MainScreen({
    super.key,
    required this.relayManager,
    required this.onThemeToggle,
    required this.networkManager,
  });

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _selectedIndex);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _pageController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      DebugLogger.log('📱 App Resumed: Checking relay connection...', type: 'SYSTEM');
      widget.relayManager.connectIfNeeded();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() => _selectedIndex = index);
        },
        children: [
          ChatsScreen(relayManager: widget.relayManager),
          ContactsScreen(relayManager: widget.relayManager),
          ProfileScreen(
            onThemeToggle: widget.onThemeToggle,
            relayManager: widget.relayManager,
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
        ),
        child: Theme(
          data: Theme.of(context).copyWith(
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
          ),
          child: ValueListenableBuilder(
            valueListenable: Hive.box<Contact>('contacts').listenable(),
            builder: (context, Box<Contact> box, _) {
              final totalUnread = box.values.fold<int>(0, (sum, contact) => sum + contact.unreadCount);
              final isDarkMode = Theme.of(context).brightness == Brightness.dark;

              return NavigationBarTheme(
                data: NavigationBarThemeData(
                  indicatorColor: Colors.blue.withAlpha(40),

                  iconTheme: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return const IconThemeData(color: Colors.blue, size: 24);
                    }
                    return IconThemeData(
                        color: isDarkMode ? Colors.white70 : Colors.black54,
                        size: 24
                    );
                  }),
                ),
                child: NavigationBar(
                  backgroundColor: Colors.transparent,
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (index) {
                    setState(() => _selectedIndex = index);
                    _pageController.jumpToPage(index);
                  },
                  labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
                  height: 65,
                  destinations: [
                    NavigationDestination(
                      icon: Badge(
                        backgroundColor: Colors.red,
                        label: Text(
                          '$totalUnread',
                          style: const TextStyle(fontSize: 10, color: Colors.white),
                        ),
                        isLabelVisible: totalUnread > 0,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: const Icon(Icons.chat_bubble_outline_rounded),
                      ),
                      selectedIcon: Badge(
                        backgroundColor: Colors.red,
                        label: Text(
                          '$totalUnread',
                          style: const TextStyle(fontSize: 10, color: Colors.white),
                        ),
                        isLabelVisible: totalUnread > 0,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: const Icon(Icons.chat_bubble_rounded),
                      ),
                      label: 'Chats',
                    ),
                    const NavigationDestination(
                      icon: Icon(Icons.people_outline_rounded),
                      selectedIcon: Icon(Icons.people_rounded),
                      label: 'Contacts',
                    ),
                    const NavigationDestination(
                      icon: Icon(Icons.manage_accounts_outlined),
                      selectedIcon: Icon(Icons.manage_accounts),
                      label: 'Profile',
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}