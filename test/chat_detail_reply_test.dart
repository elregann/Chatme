import 'dart:io';

import 'package:chatme/models/chat_message.dart';
import 'package:chatme/models/contact.dart';
import 'package:chatme/relay_manager.dart';
import 'package:chatme/room_chat.dart';
import 'package:chatme/services/app_settings.dart';
import 'package:chatme/services/chat_reply.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    FlutterLocalNotificationsPlatform.instance = _SilentNotifications();
    tempDir = await Directory.systemTemp.createTemp('chatme_reply_test');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ContactAdapter());
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(ChatMessageAdapter());
    }
    await Hive.openBox('settings');
    await Hive.openBox<Contact>('contacts');
    await Hive.openBox('chats');
    await Hive.openBox<String>('profile_pictures');
    await Hive.openBox('processed_events');
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  setUp(() {
    ChatScreenRegistry.clear();
    AppSettings.instance.myPubkey = 'me';
  });

  ChatMessage image(String id) => ChatMessage(
        id: id,
        senderPubkey: 'me',
        receiverPubkey: 'peer',
        content: '',
        plaintext: 'Photo',
        timestamp: 1,
        chatKey: 'chat',
        file: const {'type': 'image/jpeg'},
        localPath: '/x/$id.jpg',
      );

  Widget app(ChatDetailScreen screen) => MaterialApp(home: screen);

  testWidgets('an initial reply shows its preview and opens the keyboard',
      (tester) async {
    await tester.pumpWidget(app(ChatDetailScreen(
      contact: Contact(pubkey: 'peer', name: 'Peer'),
      relayManager: RelayManager(),
      initialReply: image('photo'),
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Photo'), findsOneWidget);
    expect(find.byIcon(Icons.reply), findsOneWidget);

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode?.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
  });

  testWidgets(
      'a reply sent to the open chat shows its preview and opens the keyboard',
      (tester) async {
    await tester.pumpWidget(app(ChatDetailScreen(
      contact: Contact(pubkey: 'peer', name: 'Peer'),
      relayManager: RelayManager(),
    )));
    await tester.pump();

    ChatScreenRegistry.find('peer')!.onReply(image('photo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Photo'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode?.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
  });

  testWidgets(
      'a reply from the viewer returns to the chat and opens the keyboard',
      (tester) async {
    await tester.pumpWidget(app(ChatDetailScreen(
      contact: Contact(pubkey: 'peer', name: 'Peer'),
      relayManager: RelayManager(),
    )));
    await tester.pump();

    final navigator = Navigator.of(tester.element(find.byType(ChatDetailScreen)));
    navigator.push(MaterialPageRoute(
      builder: (_) => Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => ChatReplyNavigator.instance
                .openReply(context, image('photo')),
            child: const Text('Viewer'),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Viewer'));
    await tester.pumpAndSettle();

    expect(find.text('Viewer'), findsNothing);
    expect(find.text('Photo'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode?.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
  });
}

class _SilentNotifications extends FlutterLocalNotificationsPlatform {
  @override
  Future<void> cancel(int id) async {}
}
