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
}
