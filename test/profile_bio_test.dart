// profile_bio_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatme/widgets/profile_bio.dart';

Future<void> pumpBio(
  WidgetTester tester,
  Widget child,
) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  testWidgets('renders the bio as plain text', (tester) async {
    const text = 'Hello **world** <script>alert(1)</script>';

    await pumpBio(tester, const ProfileBioText(about: text));

    // The exact source string is shown: no markdown or HTML is interpreted.
    expect(find.text(text), findsOneWidget);
  });

  testWidgets('truncates a long bio to the requested number of lines',
      (tester) async {
    const text = 'A bio that is long enough to need several lines on screen.';

    await pumpBio(
      tester,
      const ProfileBioText(about: text, maxLines: 2),
    );

    final widget = tester.widget<Text>(find.text(text));
    expect(widget.maxLines, 2);
    expect(widget.overflow, TextOverflow.ellipsis);
  });

  testWidgets('tapping the bio opens a sheet with the full text',
      (tester) async {
    final text = List.filled(80, 'The full biography text.').join(' ');

    await pumpBio(tester, ProfileBioText(about: text));
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();

    final sheetText = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(sheetText.data, text);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('an empty bio renders nothing unless the hint is enabled',
      (tester) async {
    await pumpBio(tester, const ProfileBioText(about: '   '));

    expect(find.byType(Text), findsNothing);
  });

  testWidgets('an empty bio shows the hint and calls the tap handler',
      (tester) async {
    var tapped = false;

    await pumpBio(
      tester,
      ProfileBioText(
        about: '',
        showEmptyHint: true,
        emptyHint: 'Add a bio',
        onEmptyTap: () => tapped = true,
      ),
    );

    expect(find.text('Add a bio'), findsOneWidget);

    await tester.tap(find.text('Add a bio'));
    expect(tapped, isTrue);
  });

  testWidgets('sanitizes remote text before showing it', (tester) async {
    await pumpBio(
      tester,
      const ProfileBioText(about: '  hello\u0000\n\n\n\nworld  '),
    );

    expect(find.text('hello\n\nworld'), findsOneWidget);
  });
}
