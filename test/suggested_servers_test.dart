// suggested_servers_test.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatme/services/server_lists.dart';
import 'package:chatme/widgets/suggested_server_list.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BlossomSuggestions', () {
    test('every suggestion is a valid address already in normal form', () {
      for (final url in BlossomSuggestions.servers) {
        expect(ServerAddress.blossom(url), url);
      }
    });

    test('no suggestion repeats or is already a default', () {
      expect(BlossomSuggestions.servers.toSet().length, BlossomSuggestions.servers.length);
      expect(
        BlossomSuggestions.servers.toSet().intersection(BlossomDefaults.servers.toSet()),
        isEmpty,
      );
    });

    test('remaining leaves out the ones the user already has', () {
      final have = [BlossomDefaults.servers.first, BlossomSuggestions.servers.first];
      final left = BlossomSuggestions.remaining(have);
      expect(left, isNot(contains(BlossomSuggestions.servers.first)));
      expect(left.length, BlossomSuggestions.servers.length - 1);
    });

    test('remaining is empty when the user has them all', () {
      expect(BlossomSuggestions.remaining(BlossomSuggestions.servers), isEmpty);
    });

    test('remaining keeps the original order', () {
      expect(BlossomSuggestions.remaining(const []), BlossomSuggestions.servers);
    });
  });

  group('SuggestedServerList', () {
    Widget host(Widget child) => MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: child)),
        );

    testWidgets('shows the title, the description and each host', (tester) async {
      await tester.pumpWidget(host(const SuggestedServerList(
        title: 'SUGGESTED SERVERS',
        description: 'Copy one and paste it.',
        servers: ['https://files.example.com', 'https://blossom.example.org'],
      )));

      expect(find.text('SUGGESTED SERVERS'), findsOneWidget);
      expect(find.text('Copy one and paste it.'), findsOneWidget);
      expect(find.text('files.example.com'), findsOneWidget);
      expect(find.text('blossom.example.org'), findsOneWidget);
      expect(find.byIcon(Icons.copy_rounded), findsNWidgets(2));
    });

    testWidgets('the copy icon puts the full address on the clipboard, quietly', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      await tester.pumpWidget(host(const SuggestedServerList(
        title: 'T',
        description: '',
        servers: ['https://files.example.com', 'https://blossom.example.org'],
      )));

      await tester.tap(find.byIcon(Icons.copy_rounded).last);
      await tester.pump();

      expect(copied, 'https://blossom.example.org');
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}
