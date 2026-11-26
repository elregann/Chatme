import 'package:chatme/ui/profile/privacy_policy_content.dart';
import 'package:chatme/ui/profile/privacy_policy_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('PrivacyPolicyPage renders intro and all sections',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: PrivacyPolicyPage()),
    );

    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.byKey(PrivacyPolicyPage.introKey), findsOneWidget);
    expect(find.textContaining('Last updated'), findsOneWidget);
    expect(find.textContaining('Nostr'), findsWidgets);

    for (final section in PrivacyPolicyContent.sections) {
      await tester.scrollUntilVisible(
        find.byKey(PrivacyPolicyPage.sectionKey(section.title)),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(section.title), findsOneWidget);
    }
  });

  test('PrivacyPolicyContent covers key Chatme privacy facts', () {
    final allText = [
      PrivacyPolicyContent.intro,
      for (final section in PrivacyPolicyContent.sections) ...[
        section.title,
        ...section.paragraphs,
        ...section.bullets,
      ],
    ].join('\n');

    expect(allText, contains('NIP-17'));
    expect(allText, contains('NIP-44'));
    expect(allText, contains('Blossom'));
    expect(allText, contains('DTLS-SRTP'));
    expect(allText, contains('Link previews are off by default'));
    expect(allText, contains('Read receipts can be turned off'));
    expect(allText, contains('best effort'));
    expect(allText, contains('not been independently audited'));
    expect(allText, contains('private key or recovery phrase'));
  });
}
