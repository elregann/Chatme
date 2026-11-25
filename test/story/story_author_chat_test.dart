import 'dart:io';

import 'package:chatme/models/contact.dart';
import 'package:chatme/relay_manager.dart';
import 'package:chatme/story/story_viewer_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  const authorPubkey =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('story_author_chat');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ContactAdapter());
    await Hive.openBox<Contact>('contacts');
  });

  Widget app() {
    return MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Builder(
                  builder: (viewerContext) => Scaffold(
                    body: TextButton(
                      onPressed: () => openStoryAuthorChat(
                        viewerContext,
                        authorPubkey: authorPubkey,
                        displayName: 'Alice',
                        relayManager: RelayManager(),
                        buildChatPage: (contact, _) => Scaffold(
                          body: Text('Chat ${contact.pubkey} ${contact.name}'),
                        ),
                      ),
                      child: const Text('Message'),
                    ),
                  ),
                ),
              ),
            ),
            child: const Text('Open story'),
          ),
        ),
      ),
    );
  }

  testWidgets('Message replaces the story route so back returns to chats',
      (tester) async {
    await tester.pumpWidget(app());

    await tester.tap(find.text('Open story'));
    await tester.pumpAndSettle();
    expect(find.text('Message'), findsOneWidget);

    await tester.tap(find.text('Message'));
    await tester.pumpAndSettle();
    const chatLabel = 'Chat $authorPubkey Alice';
    expect(find.text(chatLabel), findsOneWidget);
    expect(find.text('Message'), findsNothing);

    Navigator.of(tester.element(find.text(chatLabel))).pop();
    await tester.pumpAndSettle();
    expect(find.text('Open story'), findsOneWidget);
    expect(find.text('Message'), findsNothing);
  });

  testWidgets('Message reuses the saved contact display name', (tester) async {
    Hive.box<Contact>('contacts').put(
      authorPubkey,
      Contact(pubkey: authorPubkey, name: 'Saved Alice', isSaved: true),
    );

    await tester.pumpWidget(app());
    await tester.tap(find.text('Open story'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Message'));
    await tester.pumpAndSettle();

    expect(find.text('Chat $authorPubkey Saved Alice'), findsOneWidget);
  });
}
