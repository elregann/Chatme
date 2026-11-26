import 'dart:convert';
import 'dart:io';

import 'package:chatme/models/contact.dart';
import 'package:chatme/relay_manager.dart';
import 'package:chatme/story/story_item.dart';
import 'package:chatme/story/story_manager.dart';
import 'package:chatme/story/story_prepare_page.dart';
import 'package:chatme/story/story_store.dart';
import 'package:chatme/story/story_viewer_page.dart';
import 'package:chatme/widgets/root_back_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

// 1x1 transparent PNG so Image.file renders without errors in widget tests.
const _tinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

class _PopCountingObserver extends NavigatorObserver {
  int popCount = 0;
  final List<Route<dynamic>> poppedRoutes = <Route<dynamic>>[];

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popCount++;
    poppedRoutes.add(route);
    super.didPop(route, previousRoute);
  }
}

void main() {
  const authorPubkey =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const storyId =
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

  late Directory tempDir;
  late File imageFile;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('story_back_nav');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ContactAdapter());
    await Hive.openBox<Contact>('contacts');
    await Hive.openBox<Map>(StoryStore.boxName);

    imageFile = File('${tempDir.path}/story.png');
    await imageFile.writeAsBytes(base64Decode(_tinyPngBase64));
  });

  tearDownAll(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  setUp(() async {
    await Hive.box<Map>(StoryStore.boxName).clear();
    final now = DateTime.now().millisecondsSinceEpoch;
    await StoryManager.instance.store.put(
      StoryItem(
        id: storyId,
        authorPubkey: authorPubkey,
        createdAt: now - 1000,
        expiresAt: now + 86400000,
        mediaUrl: 'https://example.com/$storyId.enc',
        mimeType: 'image/png',
        encryptionKey: 'k',
        encryptionNonce: 'n',
        fileHash: 'f1',
        originalHash: 'o1',
        localPath: imageFile.path,
      ),
    );
  });

  group('Story back navigation', () {
    testWidgets(
      'StoryViewerPage: handlePopRoute + tap next on last story only pops once',
      (tester) async {
        final observer = _PopCountingObserver();
        final rootKey = GlobalKey();

        await tester.pumpWidget(
          MaterialApp(
            navigatorObservers: [observer],
            home: Builder(
              key: rootKey,
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => StoryViewerPage(
                        relayManager: RelayManager(),
                        initialAuthorPubkey: authorPubkey,
                      ),
                    ),
                  ),
                  child: const Text('Open story'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open story'));
        // Use bounded pumps: StoryViewerPage runs a periodic image timer.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.byType(StoryViewerPage), findsOneWidget);

        // Trigger system back and right-half tap (auto-next on last story)
        // before the pop transition finishes.
        await tester.binding.handlePopRoute();
        final rect = tester.getRect(find.byType(StoryViewerGestures));
        await tester.tapAt(Offset(rect.right - 20, rect.center.dy));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();

        expect(observer.popCount, 1);
        expect(find.byKey(rootKey), findsOneWidget);
        expect(find.byType(StoryViewerPage), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets(
      'StoryViewerGestures: pointer cancel prevents swipe/tap next from firing',
      (tester) async {
        var next = 0;
        var previous = 0;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StoryViewerGestures(
                onHoldStart: () {},
                onHoldEnd: () {},
                onNext: () => next++,
                onPrevious: () => previous++,
                child: const SizedBox.expand(
                  child: ColoredBox(color: Colors.black),
                ),
              ),
            ),
          ),
        );

        final rect = tester.getRect(find.byType(StoryViewerGestures));
        final gesture = await tester.startGesture(
          Offset(rect.right - 20, rect.center.dy),
        );
        await tester.pump();
        await gesture.moveBy(const Offset(-80, 0));
        await tester.pump();
        await gesture.cancel();
        await tester.pumpAndSettle();

        expect(next, 0);
        expect(previous, 0);
      },
    );

    testWidgets(
      'StoryPreparePage: tapping back and handlePopRoute only pops once',
      (tester) async {
        final observer = _PopCountingObserver();
        final rootKey = GlobalKey();

        await tester.pumpWidget(
          MaterialApp(
            navigatorObservers: [observer],
            home: Builder(
              key: rootKey,
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => StoryPreparePage(
                        mediaPath: imageFile.path,
                        isVideo: false,
                        imageLoader: (_) async =>
                            base64Decode(_tinyPngBase64),
                        imagePreviewBuilder: (_) => const SizedBox.expand(),
                      ),
                    ),
                  ),
                  child: const Text('Open prepare'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open prepare'));
        await tester.pumpAndSettle();
        expect(find.byType(StoryPreparePage), findsOneWidget);

        await tester.tap(find.byIcon(Icons.arrow_back_ios_rounded));
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(observer.popCount, 1);
        expect(find.byKey(rootKey), findsOneWidget);
        expect(find.byType(StoryPreparePage), findsNothing);
      },
    );

    testWidgets(
      'RootBackGuard absorbs rapid double back while pushed route is popping',
      (tester) async {
        final observer = _PopCountingObserver();
        final rootKey = GlobalKey();
        var moveToBackCount = 0;

        await tester.pumpWidget(
          MaterialApp(
            navigatorObservers: [observer],
            home: RootBackGuard(
              allowExit: true,
              onMoveToBack: () => moveToBackCount++,
              child: Builder(
                key: rootKey,
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const Scaffold(
                          body: Center(child: Text('Pushed')),
                        ),
                      ),
                    ),
                    child: const Text('Push'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Push'));
        await tester.pumpAndSettle();
        expect(find.text('Pushed'), findsOneWidget);

        // First back starts popping the pushed route; second back arrives
        // mid-transition (~100ms in) and must not pop root or moveToBack.
        await tester.binding.handlePopRoute();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(observer.popCount, 1);
        expect(moveToBackCount, 0);
        expect(find.byKey(rootKey), findsOneWidget);
        expect(find.text('Pushed'), findsNothing);
      },
    );
  });
}
