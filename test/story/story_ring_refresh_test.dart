import 'dart:convert';
import 'dart:io';

import 'package:chatme/models/contact.dart';
import 'package:chatme/relay_manager.dart';
import 'package:chatme/services/app_settings.dart';
import 'package:chatme/story/story_item.dart';
import 'package:chatme/story/story_manager.dart';
import 'package:chatme/story/story_store.dart';
import 'package:chatme/story/story_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

const _tinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

const _me = 'me';
const _peer = 'peer';
const _storyId =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

StoryItem _peerStory(String localPath) {
  final now = DateTime.now().millisecondsSinceEpoch;
  return StoryItem(
    id: _storyId,
    authorPubkey: _peer,
    createdAt: now - 1000,
    expiresAt: now + 86400000,
    mediaUrl: 'https://example.com/$_storyId.enc',
    mimeType: 'image/png',
    encryptionKey: 'k',
    encryptionNonce: 'n',
    fileHash: 'f1',
    originalHash: 'o1',
    localPath: localPath,
  );
}

List<bool> _ringSegments(WidgetTester tester) {
  final painter = tester
      .widget<CustomPaint>(
        find.byWidgetPredicate(
          (widget) => widget is CustomPaint && widget.painter is StoryRingPainter,
        ),
      )
      .painter! as StoryRingPainter;
  return painter.segments;
}

Widget _host() {
  return MaterialApp(
    home: Scaffold(
      body: StoryStrip(
        relayManager: RelayManager(),
        onAddStory: () {},
        onOpenAuthor: (_) {},
      ),
    ),
  );
}

void main() {
  late Directory tempDir;
  late StoryItem story;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('story_ring_refresh');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ContactAdapter());
    await Hive.openBox<Contact>('contacts');
    await Hive.openBox<Map>(StoryStore.boxName);
  });

  // Hive boxes are intentionally left open: closing them while a viewer route
  // is draining an async media load can block the test runner indefinitely.
  tearDownAll(() {});

  setUp(() async {
    await Hive.box<Map>(StoryStore.boxName).clear();
    AppSettings.instance.myPubkey = _me;
    final file = File('${tempDir.path}/story.png');
    await file.writeAsBytes(base64Decode(_tinyPngBase64));
    story = _peerStory(file.path);
    await StoryManager.instance.store.put(story);
  });

  testWidgets('story strip repaints when markViewed notifies', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pump();
    expect(_ringSegments(tester), [true], reason: 'ring starts unviewed');

    await tester.runAsync(() => StoryManager.instance.markViewed(story));
    await tester.pump();

    expect(_ringSegments(tester), [false]);
  });

  testWidgets('story strip follows the stored view even without a revision bump',
      (tester) async {
    await tester.pumpWidget(_host());
    await tester.pump();
    expect(_ringSegments(tester), [true], reason: 'ring starts unviewed');

    final revision = StoryManager.instance.revision.value;
    await tester.runAsync(() => StoryManager.instance.store.markViewed(
          _storyId,
          _me,
          DateTime.now().millisecondsSinceEpoch,
        ));
    await tester.pump();

    expect(StoryManager.instance.revision.value, revision,
        reason: 'no manual notification in this scenario');
    expect(_ringSegments(tester), [false],
        reason: 'a persisted view must turn the ring gray immediately');
  });
}
