import 'package:chatme/ui/discovery/web_app_browser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('browser subtitle shows the full current URL', (tester) async {
    const url = 'https://www.google.com/search?q=nostr+fire&num=10';

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: BrowserUrlSubtitle(url))),
    );

    expect(find.text(url), findsOneWidget);
    expect(tester.widget<Text>(find.text(url)).maxLines, 1);
    expect(tester.widget<Tooltip>(find.byType(Tooltip)).message, url);
  });

  group('browser back', () {
    test('uses WebView history before closing the browser', () async {
      expect(
        await resolveBrowserBack(() async => true),
        BrowserBackAction.goBack,
      );
      expect(
        await resolveBrowserBack(() async => false),
        BrowserBackAction.close,
      );
    });

    test('closes the browser when the history check fails', () async {
      expect(
        await resolveBrowserBack(() async => throw StateError('no view')),
        BrowserBackAction.close,
      );
    });
  });
}
