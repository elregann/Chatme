// main.dart

import 'dart:io';
import 'dart:ui';
import 'dart:isolate';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:remixicon/remixicon.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'models/contact.dart';
import 'models/chat_message.dart';
import 'models/call_log.dart';
import 'services/app_settings.dart';
import 'notification_handler.dart';
import 'services/network_manager.dart';
import 'services/background_service.dart';
import 'core/utils/debug_logger.dart';
import 'core/utils/bg_inbox.dart';
import 'room_chat.dart';
import 'relay_manager.dart';
import 'chat_manager.dart';
import 'tab_contact.dart';
import 'tab_profile.dart';
import 'tab_chat.dart';
import 'tab_calls.dart';
import 'call.dart';
import 'call_manager.dart';
import 'call_notification_handler.dart';

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

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ContactAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(ChatMessageAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(CallLogAdapter());

    await Hive.openBox('settings');
    await Hive.openBox<Contact>('contacts');
    await Hive.openBox('chats');
    await Hive.openBox<String>('profile_pictures');
    await Hive.openBox<CallLog>('call_logs');
    await Hive.openBox('processed_events');

    await AppSettings.instance.load();

    // CRITICAL: Set both launch flags BEFORE runApp() to avoid race condition with build()
    CallManager.instance.launchCallerPubkey = await NotificationHandler.peekCallLaunchPubkey();
    CallManager.instance.launchAutoAccept = await NotificationHandler.peekCallLaunchAutoAccept();

    await NotificationHandler.stopOngoingCall();

    if (!kIsWeb) {
      final myPubkey = AppSettings.instance.myPubkey;
      if (myPubkey.isNotEmpty) {
        final connectivityResult = await Connectivity().checkConnectivity();
        final isOnline = connectivityResult.any((r) =>
        r == ConnectivityResult.mobile ||
            r == ConnectivityResult.wifi ||
            r == ConnectivityResult.ethernet
        );
        if (isOnline) {
          FirebaseMessaging.instance
              .subscribeToTopic(myPubkey)
              .timeout(const Duration(seconds: 8))
              .catchError((_) {});
        }
      }
    }

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
  ReceivePort? _notificationPort;

  @override
  void initState() {
    super.initState();

    // Notification bar
    if (!kIsWeb) {
      IsolateNameServer.removePortNameMapping('chatme_notification_port');
      _notificationPort = ReceivePort();
      IsolateNameServer.registerPortWithName(_notificationPort!.sendPort, 'chatme_notification_port');
      const MethodChannel('com.chatme.app/task').setMethodCallHandler((call) async {
        if (call.method == 'openActiveCall') _openActiveCallScreen();
      });
      _notificationPort!.listen((dynamic data) async {
        if (data is Map) {
          debugPrint('[Nav] port tap id=${data['id']} action=${data['actionId']} state=${CallManager.instance.callState}');
          final actionId = data['actionId'];
          final input = data['input'];
          final payload = data['payload'];

          if (actionId == null && payload != null) {
            if (data['id'] == CallNotificationHandler.activeCallNotificationId &&
                CallManager.instance.callState != CallState.idle) {
              _openActiveCallScreen();
            } else {
              _navigateToChat(payload);
            }
          } else if (actionId == 'REPLY_ACTION' && input != null && payload != null) {
            _relayManager.connectIfNeeded();
            await Future.delayed(const Duration(milliseconds: 800));
            await ChatManager.sendReplyFromNotification(
              receiverPubkey: payload,
              plaintext: input,
              relayManager: _relayManager,
            );
          } else if (actionId == CallNotificationHandler.answerActionId) {
            _answerPendingCall(callerPubkey: payload?.toString());
          } else if (actionId == CallNotificationHandler.declineActionId) {
            await _declinePendingCall(callerPubkey: payload?.toString());
          } else if (actionId == CallNotificationHandler.endCallActionId) {
            await _endActiveCallFromNotification();
          } else if (actionId == 'MARK_READ_ACTION') {
            if (payload == null || payload.isEmpty) {
              return;
            }

            try {
              _relayManager.connectIfNeeded();
              await Future.delayed(const Duration(milliseconds: 800));
              await NotificationHandler.clearNotification(payload);
              await ChatManager.instance.clearUnreadCount(payload);

              final myPubkey = AppSettings.instance.myPubkey;
              final chatKey = ChatManager.instance.getChatKey(myPubkey, payload);
              final messages = await ChatManager.instance.getMessages(payload);

              for (final m in messages) {
                if (m.senderPubkey == payload && m.status != 'read') {
                  await ChatManager.instance.updateMessageStatus(
                    m.id, 'read', chatKey: chatKey,
                  );
                  await _relayManager.sendReceipt(m.id, payload, 'read');
                }
              }
              _relayManager.onMessageReceived?.call();
            } catch (e) {
              DebugLogger.log('[Notification] MARK_READ_ACTION failed | $e', type: 'ERROR');
            }
          }
        }
      });
    }

    NotificationHandler.init(relayManager: _relayManager);

    // Move heavy operations to Post-Frame to prevent UI jank/black screen on Cold Start
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _applyPendingReads();
      // Re-check after relays deliver initial batch
      Future.delayed(const Duration(seconds: 6), _applyPendingReads);
      _applyPendingDeclines();

      try {
        await BackgroundService.initialize();
        await BackgroundService.registerReconnectTask();
        await ChatManager.instance.cleanupTempMessages();
      } catch (e) {
        DebugLogger.log('[Startup] Deferred init failed | $e', type: 'ERROR');
      }

      // Connect relay immediately (no delay) for VoIP responsiveness
      _relayManager.connect();
      _networkManager.onReconnect = () {
        _relayManager.connectIfNeeded();
        if (!kIsWeb) {
          final myPubkey = AppSettings.instance.myPubkey;
          if (myPubkey.isNotEmpty) {
            FirebaseMessaging.instance
                .subscribeToTopic(myPubkey)
                .catchError((_) {});
          }
        }
      };
      _networkManager.initialize();
    });

    _relayManager.precacheAllProfilePictures();
    WidgetsBinding.instance.addObserver(this);

    // All notification taps are treated as chat navigations. The legacy
    // 'incoming_call' branch was removed: it was dead code (no producer
    // ever sent that payload) and it called pushNamed('/call'), a route
    // that no longer exists and could never carry the peerPubkey / SDP
    // data required by CallScreen. Incoming calls are now delivered
    // exclusively through the NIP-17 CALL_SIGNAL flow, which opens the
    // call screen with full session data.
    NotificationHandler.onNotificationClick.stream.listen((String? payload) {
      if (payload != null && payload.isNotEmpty) {
        _navigateToChat(payload);
      }
    });

    _requestIgnoreBatteryOptimization();

    Future.delayed(const Duration(seconds: 4), () {
      AppSettings.hydrateMissingContactNames();
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

  void _answerPendingCall({String? callerPubkey}) {
    final screenAccept = CallManager.instance.incomingScreenAccept;
    if (screenAccept != null) {
      screenAccept();
      return;
    }

    final pending = CallManager.instance.pendingIncoming;
    if (pending == null) {
      // Cold start: the offer has not arrived yet. Remember the tap.
      if (callerPubkey != null && callerPubkey.isNotEmpty) {
        CallManager.instance.autoAnswerPubkey = callerPubkey;
        CallManager.instance.autoAnswerAtMs = DateTime.now().millisecondsSinceEpoch;
        _relayManager.connectIfNeeded();
      }
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = navigatorKey.currentContext;
      if (ctx == null) {
        // Navigator not ready yet (cold start): retry shortly.
        Future.delayed(const Duration(milliseconds: 500), _answerPendingCall);
        return;
      }

      CallManager.instance.pendingIncoming = null;
      CallScreenNavigator.showCallScreen(
        context: ctx,
        peerName: pending.callerName,
        peerPubkey: pending.callerPubkey,
        isIncoming: true,
        relay: _relayManager,
        peerColor: pending.callerColor,
        remoteSdp: pending.remoteSdp,
        autoAccept: true,
      );
    });
  }

  Future<void> _declinePendingCall({String? callerPubkey}) async {
    final pending = CallManager.instance.pendingIncoming;
    final target = pending?.callerPubkey ?? callerPubkey;
    final callerName = pending?.callerName ??
        (callerPubkey != null && callerPubkey.isNotEmpty
            ? (Hive.box<Contact>('contacts').get(callerPubkey)?.displayName ??
            AppSettings.formatDisplayName(callerPubkey))
            : 'Kontak');
    if (target == null || target.isEmpty) return;

    final screenDecline = CallManager.instance.incomingScreenDecline;
    if (screenDecline != null) {
      try {
        await Hive.box('settings').put(
          'declined_call_$target',
          DateTime.now().millisecondsSinceEpoch,
        );
      } catch (_) {}
      CallManager.instance.pendingIncoming = null;
      screenDecline();
      return;
    }

    try {
      if (!Hive.isBoxOpen('settings')) {
        await Hive.openBox('settings');
      }
      await Hive.box('settings').put(
        'declined_call_$target',
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}

    CallManager.instance.pendingIncoming = null;
    CallManager.instance.autoAnswerPubkey = null;

    if (pending == null) {
      // Cold start: relays may not be connected yet, give them a moment.
      _relayManager.connectIfNeeded();
      await Future.delayed(const Duration(milliseconds: 1500));
    }

    await _relayManager.sendCallSignal(target, {'type': 'hangup'});

    // Explicitly save CallLog and incoming call ChatMessage so it appears in room chat and calls tab immediately
    try {
      if (!Hive.isBoxOpen('call_logs')) {
        await Hive.openBox<CallLog>('call_logs');
      }
      final callLogEntry = CallLog(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        peerPubkey: target,
        peerName: callerName,
        direction: 'incoming',
        mediaType: 'voice',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        durationSeconds: 0,
      );
      Hive.box<CallLog>('call_logs').add(callLogEntry);
    } catch (e) {
      debugPrint('[Call] Error saving CallLog on decline: $e');
    }

    try {
      final myPubkey = AppSettings.instance.myPubkey;
      if (myPubkey.isNotEmpty) {
        final chatKey = ChatManager.instance.getChatKey(myPubkey, target);
        const callMsgContent = '[CALL]:incoming:voice:duration:0';
        final chatMsg = ChatMessage(
          id: 'call_${DateTime.now().millisecondsSinceEpoch}',
          senderPubkey: target,
          receiverPubkey: myPubkey,
          content: callMsgContent,
          plaintext: callMsgContent,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          status: 'read',
          chatKey: chatKey,
        );
        ChatManager.instance.saveMessage(chatMsg);
      }
    } catch (e) {
      debugPrint('[Call] Error saving ChatMessage call record on decline: $e');
    }
    CallManager.instance.clearIdleSession();
  }

  /// Applies "mark as read" taps done while the app was closed.
  Future<void> _applyPendingReads() async {
    try {
      // Ids recorded while the app was closed are obsolete now.
      await BgInbox.clearAllUnread();

      final reads = await BgInbox.peekReads();
      for (final entry in reads.entries) {
        final peer = entry.key;
        final readIds = entry.value.toSet();
        final myPubkey = AppSettings.instance.myPubkey;
        final chatKey = ChatManager.instance.getChatKey(myPubkey, peer);

        final messages = await ChatManager.instance.getMessages(peer);
        bool stillUnread = false;
        for (final m in messages) {
          if (m.senderPubkey != peer) continue;
          if (readIds.contains(m.id)) {
            if (m.status != 'read') {
              await ChatManager.instance.updateMessageStatus(
                m.id, 'read', chatKey: chatKey,
              );
            }
            await BgInbox.consumeRead(peer, m.id);
          } else if (m.status != 'read') {
            stillUnread = true;
          }
        }
        if (!stillUnread) await ChatManager.instance.clearUnreadCount(peer);
      }
    } catch (e) {
      DebugLogger.log('[Notification] Apply pending reads failed | $e', type: 'ERROR');
    }
  }

  /// Saves records of calls declined or missed while the app was closed.
  Future<void> _applyPendingDeclines() async {
    try {
      final myPubkey = AppSettings.instance.myPubkey;
      final declinedAt = <String, int>{};

      // 1) Calls declined from the notification.
      final declined = await BgInbox.takeDeclinedCalls();
      for (final d in declined) {
        declinedAt[d.key] = d.value;
        await _markCallHandled(d.key, d.value);
        await _saveCallRecord(d.key, d.value, 'incoming');
      }

      // 2) Calls that went unanswered (caller cancelled or timed out).
      final missed = await BgInbox.takeMissedCalls();
      for (final m in missed) {
        final peer = m.key;
        final ts = m.value;

        // Mark the call as handled first: the relay will replay its old
        // offer/hangup signals, and those must not ring or log again.
        await _markCallHandled(peer, ts);

        // The user declined this call: it is not a missed call.
        final declinedTs = declinedAt[peer];
        if (declinedTs != null && (ts - declinedTs).abs() < 60000) continue;

        // The app already recorded this missed call through the relay.
        if (myPubkey.isNotEmpty) {
          final existing = await ChatManager.instance.getMessages(peer);
          final alreadyLogged = existing.any((msg) =>
          msg.senderPubkey == peer &&
              msg.plaintext.startsWith('[CALL]:missed:') &&
              (msg.timestamp - ts).abs() < 60000);
          if (alreadyLogged) continue;
        }

        await _saveCallRecord(peer, ts, 'missed');
      }

      // 3) Replies sent from a notification: refresh the chat list preview.
      final repliedPeers = await BgInbox.takeSentReplies();
      for (final peer in repliedPeers) {
        await _refreshChatPreview(peer);
      }
    } catch (e) {
      DebugLogger.log('[Call] Apply pending call notes failed | $e', type: 'ERROR');
    }
  }

  /// Sets the chat list preview to the newest message of the chat.
  Future<void> _refreshChatPreview(String peer) async {
    try {
      final messages = await ChatManager.instance.getMessages(peer);
      if (messages.isEmpty) return;
      final last = messages.last;
      final box = Hive.box<Contact>('contacts');
      final contact = box.get(peer);
      if (contact == null) return;
      if (last.timestamp >= contact.lastChatTime) {
        contact.lastMessage = last.plaintext;
        contact.lastChatTime = last.timestamp;
        await box.put(peer, contact);
      }
    } catch (_) {}
  }

  /// Makes the offer filter ignore signals of a call that is already over.
  Future<void> _markCallHandled(String peer, int ts) async {
    try {
      final box = Hive.box('settings');
      final old = (box.get('declined_call_$peer', defaultValue: 0) as int);
      if (ts > old) await box.put('declined_call_$peer', ts);
    } catch (_) {}
  }

  /// Saves a call record in the Calls tab and in the chat room.
  Future<void> _saveCallRecord(String peer, int ts, String direction) async {
    final contact = Hive.box<Contact>('contacts').get(peer);
    final name = contact?.displayName ?? AppSettings.formatDisplayName(peer);

    await Hive.box<CallLog>('call_logs').add(CallLog(
      id: ts.toString(),
      peerPubkey: peer,
      peerName: name,
      direction: direction,
      mediaType: 'voice',
      timestamp: ts,
      durationSeconds: 0,
    ));

    final myPubkey = AppSettings.instance.myPubkey;
    if (myPubkey.isEmpty) return;

    // Any notification for this call was already shown from the background.
    try {
      await Hive.box('settings').put('notified_call_$ts', true);
    } catch (_) {}

    final content = '[CALL]:$direction:voice:duration:0';
    await ChatManager.instance.saveMessage(ChatMessage(
      id: 'call_$ts',
      senderPubkey: peer,
      receiverPubkey: myPubkey,
      content: content,
      plaintext: content,
      timestamp: ts,
      status: 'read',
      chatKey: ChatManager.instance.getChatKey(myPubkey, peer),
    ));
  }

  Future<void> _endActiveCallFromNotification() async {
    final manager = CallManager.instance;
    if (manager.callState == CallState.idle) {
      await NotificationHandler.stopOngoingCall();
      return;
    }
    final peer = manager.activePeerPubkey;
    if (peer != null && peer.isNotEmpty) {
      await _relayManager.sendCallSignal(peer, {'type': 'hangup'});
    }
    await manager.stopCall(sendHangupSignal: false, byUser: true);
  }

  void _openActiveCallScreen() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = navigatorKey.currentContext;
      final manager = CallManager.instance;
      if (ctx == null || manager.callState == CallState.idle) return;
      if (CallScreenNavigator.openScreens > 0) return;
      Navigator.of(ctx).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (context) => CallScreen(
            peerName: manager.activePeerName ?? 'Unknown',
            peerPubkey: manager.activePeerPubkey ?? '',
            isIncoming: false,
            relay: _relayManager,
            peerColor: manager.activePeerColor ?? Colors.blue,
            onClose: () {},
          ),
        ),
      );
    });
  }

  void _navigateToChat(String pubkey) {
    if (pubkey.isEmpty) return;

    // Robust cold-start navigation check: ensure navigator is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigatorKey.currentState != null) {
        final contactsBox = Hive.box<Contact>('contacts');
        final contact = contactsBox.get(pubkey) ?? Contact(
          pubkey: pubkey,
          name: AppSettings.formatDisplayName(pubkey),
        );

        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (context) => ChatDetailScreen(
              contact: contact,
              relayManager: _relayManager,
            ),
          ),
        );
      } else {
        Future.delayed(const Duration(milliseconds: 500), () {
          _navigateToChat(pubkey);
        });
      }
    });
  }

  @override
  void dispose() {
    _notificationPort?.close();
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
        final isDark = AppSettings.instance.themeMode == ThemeMode.dark ||
            (AppSettings.instance.themeMode == ThemeMode.system &&
                MediaQuery.platformBrightnessOf(context) == Brightness.dark);

        final navBarColor = isDark ? const Color(0xFF121212) : Colors.white;

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            systemNavigationBarColor: navBarColor,
            systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          ),
          child: MaterialApp(
            navigatorKey: navigatorKey,
            debugShowCheckedModeBanner: false,
            themeMode: AppSettings.instance.themeMode,
            theme: _buildLightTheme(),
            darkTheme: _buildDarkTheme(),
            initialRoute: '/',
            routes: {
              '/': (context) {
                final callerPubkey = CallManager.instance.launchCallerPubkey;
                if (callerPubkey != null && callerPubkey.isNotEmpty) {
                  final contact = Hive.box<Contact>('contacts').get(callerPubkey);
                  return CallScreen(
                    peerName: contact?.displayName ??
                        AppSettings.formatDisplayName(callerPubkey),
                    peerPubkey: callerPubkey,
                    isIncoming: true,
                    relay: _relayManager,
                    peerColor: Color(
                        int.parse(callerPubkey.substring(0, 8), radix: 16) | 0xFF000000),
                    onClose: () {},
                    autoAccept: CallManager.instance.launchAutoAccept,
                  );
                }
                return MainScreen(
                  relayManager: _relayManager,
                  onThemeToggle: _toggleTheme,
                  networkManager: _networkManager,
                );
              },
            },
          ),
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
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(color: Colors.black87, fontSize: 20, fontWeight: FontWeight.bold),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Colors.white,
        elevation: 0,
        shadowColor: Colors.transparent,
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFF121212),
      colorScheme: ColorScheme.fromSeed(brightness: Brightness.dark, seedColor: Colors.blue, surface: const Color(0xFF1E1E1E)),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        backgroundColor: Color(0xFF121212),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Color(0xFF121212),
        elevation: 0,
        shadowColor: Colors.transparent,
      ),
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
    return ValueListenableBuilder<CallState>(
      valueListenable: CallManager.instance.callStateNotifier,
      builder: (context, callState, child) {
        return PopScope(
          canPop: callState == CallState.idle,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) {
              const MethodChannel('com.chatme.app/task')
                  .invokeMethod('moveToBack');
            }
          },
          child: child!,
        );
      },
      child: _buildMainScaffold(),
    );
  }

  Widget _buildMainScaffold() {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) => setState(() => _selectedIndex = index),
        children: [
          ChatsScreen(relayManager: widget.relayManager),
          ContactsScreen(relayManager: widget.relayManager),
          CallsScreen(relayManager: widget.relayManager),
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
        final totalUnread = box.values.where((contact) => contact.unreadCount > 0).length;
        return NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) {
            setState(() => _selectedIndex = index);
            _pageController.jumpToPage(index);
          },

          // Footer App
          indicatorColor: Theme.of(context).brightness == Brightness.dark
              ? Colors.grey.shade800
              : Colors.grey.shade300,
          destinations: [
            NavigationDestination(
              icon: Badge(
                  label: Text(
                    '$totalUnread',
                    style: const TextStyle(color: Colors.white),
                  ),
                  backgroundColor: Colors.red,
                  isLabelVisible: totalUnread > 0,
                  child: Icon(
                    Remix.chat_3_line,
                    color: Theme.of(context).iconTheme.color,
                  )),
              selectedIcon: Badge(
                  label: Text(
                    '$totalUnread',
                    style: const TextStyle(color: Colors.white),
                  ),
                  backgroundColor: Colors.red,
                  isLabelVisible: totalUnread > 0,
                  child: Icon(
                    Remix.chat_3_fill,
                    color: Theme.of(context).iconTheme.color,
                  )),
              label: 'Chats',
            ),
            NavigationDestination(
              icon: Icon(Remix.contacts_line, color: Theme.of(context).iconTheme.color),
              selectedIcon: Icon(Remix.contacts_fill, color: Theme.of(context).iconTheme.color),
              label: 'Contacts',
            ),
            NavigationDestination(
              icon: Icon(Icons.phone_outlined, color: Theme.of(context).iconTheme.color),
              selectedIcon: Icon(Icons.phone, color: Theme.of(context).iconTheme.color),
              label: 'Calls',
            ),
            NavigationDestination(
              icon: Icon(Remix.settings_line, color: Theme.of(context).iconTheme.color),
              selectedIcon: Icon(Remix.settings_fill, color: Theme.of(context).iconTheme.color),
              label: 'Settings',
            ),
          ],
        );
      },
    );
  }
}