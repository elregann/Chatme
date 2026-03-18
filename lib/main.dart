// main.dart

import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'models/contact.dart';
import 'models/chat_message.dart';
import 'services/app_settings.dart';
import 'notification_handler.dart';
import 'services/network_manager.dart';
import 'core/utils/debug_logger.dart';

import 'call.dart';
import 'roomchat.dart';
import 'relaymanager.dart';
import 'chatmanager.dart';
import 'tabcontact.dart';
import 'tabprofile.dart';
import 'tabchat.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    if (kIsWeb) {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: "AIzaSyCQyZZuU7sKqdKNqUDWBhGwuujVxrL6T6I",
          authDomain: "chatme-412d1.firebaseapp.com",
          databaseURL: "https://chatme-412d1-default-rtdb.asia-southeast1.firebasedatabase.app",
          projectId: "chatme-412d1",
          storageBucket: "chatme-412d1.firebasestorage.app",
          messagingSenderId: "446305355740",
          appId: "1:446305355740:web:49ea3ae055fce21ca07119",
        ),
      );
    } else {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    }

    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ContactAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(ChatMessageAdapter());

    await Hive.openBox('settings');
    await Hive.openBox<Contact>('contacts');
    await Hive.openBox('chats');

    await NotificationHandler.init();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    await AppSettings.instance.load();
    await ChatManager.instance.cleanupTempMessages();

    if (!kIsWeb) {
      await FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }

    runApp(const ChatMeApp());

  } catch (e) {
    runApp(MaterialApp(
      home: Scaffold(body: Center(child: Text("Error Initialization: $e"))),
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
    if (kIsWeb) return;
    try {
      if (Platform.isAndroid) {
        const channel = MethodChannel('com.chatme.app/battery');
        await channel.invokeMethod('requestIgnoreBatteryOptimization');
      }
    } catch (e) {
      DebugLogger.log("Battery optimization request failed: $e", type: 'ERROR');
    }
  }

  void _navigateToChat(String pubkey) {
    if (mounted) {
      final contactsBox = Hive.box<Contact>('contacts');
      final contact = contactsBox.get(pubkey) ?? Contact(
        pubkey: pubkey,
        name: 'User ${pubkey.substring(0, 8)}',
      );

      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (context) => ChatDetailScreen(
            contact: contact,
            relayManager: _relayManager,
          ),
        ),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _relayManager.connect();
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
        return MaterialApp(
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          themeMode: AppSettings.instance.themeMode,
          theme: _buildLightTheme(),
          darkTheme: _buildDarkTheme(),
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
              onClose: () {},
            ),
          },
        );
      },
    );
  }

  ThemeData _buildLightTheme() {
    return ThemeData(
      brightness: Brightness.light,
      useMaterial3: true,
      scaffoldBackgroundColor: Colors.white,
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, surface: Colors.white),
      appBarTheme: const AppBarTheme(
        elevation: 0, centerTitle: true, backgroundColor: Colors.white,
        titleTextStyle: TextStyle(color: Colors.black87, fontSize: 20, fontWeight: FontWeight.bold),
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFF121212),
      colorScheme: ColorScheme.fromSeed(brightness: Brightness.dark, seedColor: Colors.blue, surface: const Color(0xFF1E1E1E)),
      appBarTheme: const AppBarTheme(elevation: 0, centerTitle: true, backgroundColor: Color(0xFF121212)),
    );
  }
}

class MainScreen extends StatefulWidget {
  final RelayManager relayManager;
  final NetworkManager networkManager;
  final Function(ThemeMode) onThemeToggle;

  const MainScreen({super.key, required this.relayManager, required this.onThemeToggle, required this.networkManager});

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
      widget.relayManager.connectIfNeeded();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) => setState(() => _selectedIndex = index),
        children: [
          ChatsScreen(relayManager: widget.relayManager),
          ContactsScreen(relayManager: widget.relayManager),
          ProfileScreen(onThemeToggle: widget.onThemeToggle, relayManager: widget.relayManager),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return ValueListenableBuilder(
      valueListenable: Hive.box<Contact>('contacts').listenable(),
      builder: (context, Box<Contact> box, _) {
        final totalUnread = box.values.fold<int>(0, (sum, contact) => sum + contact.unreadCount);
        return NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) {
            setState(() => _selectedIndex = index);
            _pageController.jumpToPage(index);
          },
          destinations: [
            NavigationDestination(
              icon: Badge(label: Text('$totalUnread'), isLabelVisible: totalUnread > 0, child: const Icon(Icons.chat_bubble_outline)),
              label: 'Chats',
            ),
            const NavigationDestination(icon: Icon(Icons.people_outline), label: 'Contacts'),
            const NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Profile'),
          ],
        );
      },
    );
  }
}