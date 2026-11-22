import 'package:chatme/services/browser_cache.dart';
import 'package:chatme/tab_discovery.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remixicon/remixicon.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Future<void> Function() originalCleaner;
  var clears = 0;

  setUpAll(() {
    originalCleaner = BrowserCache.clear;
  });

  tearDownAll(() {
    BrowserCache.clear = originalCleaner;
  });

  setUp(() {
    clears = 0;
    BrowserCache.clear = () async {
      clears++;
    };
  });

  testWidgets('address bar opens a bare domain over https', (tester) async {
    String? opened;

    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryScreen(onOpenUrl: (url) => opened = url),
      ),
    );
    await tester.enterText(find.byType(TextField), 'primal.net');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(opened, 'https://primal.net');
  });

  testWidgets('address bar sends non URL input to Google', (tester) async {
    String? opened;

    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryScreen(onOpenUrl: (url) => opened = url),
      ),
    );
    await tester.enterText(find.byType(TextField), 'nostr fire');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(opened, 'https://www.google.com/search?q=nostr+fire');
  });

  testWidgets('search bar shows the Google logo only', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: DiscoveryScreen(onOpenUrl: (_) {})),
    );

    expect(find.byIcon(Remix.google_fill), findsOneWidget);
  });

  testWidgets('overflow menu clears browser data', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: DiscoveryScreen(onOpenUrl: (_) {})),
    );

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pump();
    await tester.tap(find.text('Clear cache'));
    await tester.pumpAndSettle();

    expect(clears, 1);
    expect(find.text('Browser data cleared'), findsNothing);
    expect(find.text('Could not clear browser data'), findsNothing);
  });
}
