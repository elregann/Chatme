import 'package:chatme/models/chat_message.dart';
import 'package:chatme/models/contact.dart';
import 'package:chatme/relay_manager.dart';
import 'package:chatme/services/app_settings.dart';
import 'package:chatme/services/chat_reply.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ChatMessage message(String id,
          {String sender = 'peer', String receiver = 'me'}) =>
      ChatMessage(
        id: id,
        senderPubkey: sender,
        receiverPubkey: receiver,
        content: '',
        plaintext: 'Photo',
        timestamp: 1,
        chatKey: 'chat',
        file: const {'type': 'image/jpeg'},
        localPath: '/x/$id.jpg',
      );

  setUp(() {
    ChatScreenRegistry.clear();
    AppSettings.instance.myPubkey = 'me';
  });

  group('canReplyTo', () {
    test('allows a sent message', () {
      expect(canReplyTo(message('event')), isTrue);
    });

    test('blocks a message that is still sending or pending', () {
      expect(canReplyTo(message('temp_1')), isFalse);
      expect(canReplyTo(message('pending_1')), isFalse);
    });
  });

  testWidgets('reply goes back to the chat that is already open',
      (tester) async {
    final replies = <ChatMessage>[];

    await tester.pumpWidget(MaterialApp(
      home: _OpenChat(pubkey: 'peer', replies: replies),
    ));
    await tester.pumpAndSettle();

    final navigator = Navigator.of(tester.element(find.text('Open chat')));
    navigator.push(MaterialPageRoute(
      builder: (_) => const Scaffold(body: Text('Contact profile')),
    ));
    await tester.pumpAndSettle();

    navigator.push(MaterialPageRoute(
      builder: (viewerContext) => Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => ChatReplyNavigator.instance.openReply(
              context,
              message('photo'),
            ),
            child: const Text('Viewer'),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Viewer'));
    await tester.pumpAndSettle();

    expect(find.text('Open chat'), findsOneWidget);
    expect(find.text('Contact profile'), findsNothing);
    expect(find.text('Viewer'), findsNothing);
    expect(replies.map((m) => m.id), ['photo']);
  });

  testWidgets('reply opens one chat when none is open yet', (tester) async {
    final navigator = ChatReplyNavigator(
      buildChatPage: (contact, relay, initialReply) => Scaffold(
        body: Text('New chat ${contact.pubkey} ${initialReply.id}'),
      ),
    );

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => navigator.openReply(
              context,
              message('photo'),
              contact: Contact(pubkey: 'peer', name: 'Peer'),
              relayManager: RelayManager(),
            ),
            child: const Text('Open viewer'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open viewer'));
    await tester.pumpAndSettle();

    expect(find.text('New chat peer photo'), findsOneWidget);
    expect(find.text('Open viewer'), findsNothing);
  });

  testWidgets('a pending picture does not leave the viewer', (tester) async {
    final replies = <ChatMessage>[];

    await tester.pumpWidget(MaterialApp(
      home: _OpenChat(pubkey: 'peer', replies: replies),
    ));
    await tester.pumpAndSettle();

    final navigator = Navigator.of(tester.element(find.text('Open chat')));
    navigator.push(MaterialPageRoute(
      builder: (viewerContext) => Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => ChatReplyNavigator.instance.openReply(
              context,
              message('temp_1'),
            ),
            child: const Text('Viewer'),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Viewer'));
    await tester.pumpAndSettle();

    expect(find.text('Viewer'), findsOneWidget);
    expect(replies, isEmpty);
  });
}

class _OpenChat extends StatefulWidget {
  final String pubkey;
  final List<ChatMessage> replies;

  const _OpenChat({required this.pubkey, required this.replies});

  @override
  State<_OpenChat> createState() => _OpenChatState();
}

class _OpenChatState extends State<_OpenChat> {
  ChatScreenHandle? _handle;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route == null || identical(route, _handle?.route)) return;
    if (_handle != null) ChatScreenRegistry.unregister(_handle!);
    _handle = ChatScreenHandle(
      pubkey: widget.pubkey,
      route: route,
      onReply: widget.replies.add,
    );
    ChatScreenRegistry.register(_handle!);
  }

  @override
  void dispose() {
    if (_handle != null) ChatScreenRegistry.unregister(_handle!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('Open chat')));
  }
}
