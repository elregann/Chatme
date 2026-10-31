// server_list_widgets_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatme/services/server_lists.dart';
import 'package:chatme/widgets/editable_server_list.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  group('changeMessage', () {
    test('says what to type for a relay and for a file server', () {
      expect(changeMessage(ListChange.invalid, fileServer: false), contains('wss://'));
      expect(changeMessage(ListChange.invalid, fileServer: true), contains('https://'));
    });

    test('has a message for every refusal', () {
      for (final change in ListChange.values) {
        if (change == ListChange.ok) continue;
        expect(changeMessage(change, fileServer: false), isNotEmpty, reason: '$change');
        expect(changeMessage(change, fileServer: true), isNotEmpty, reason: '$change');
      }
    });

    test('a change that worked has no message', () {
      expect(changeMessage(ListChange.ok, fileServer: false), isEmpty);
    });

    test('keeping the last one names what must stay', () {
      expect(changeMessage(ListChange.tooFew, fileServer: false), contains('inbox relay'));
      expect(changeMessage(ListChange.tooFew, fileServer: true), contains('file server'));
    });
  });

  group('EditableServerList', () {
    testWidgets('shows each server, a Default label and the status', (tester) async {
      await tester.pumpWidget(_host(EditableServerList(
        title: 'INBOX RELAYS',
        description: 'Where people send you messages.',
        servers: const ['wss://nos.lol', 'wss://custom.example.com'],
        defaults: const ['wss://nos.lol'],
        addLabel: 'Add relay',
        hint: 'relay.example.com',
        fileServer: false,
        onSubmit: (_) async => const ListEdit(ListChange.ok, []),
        onRemove: (_) {},
        statusLabel: (url) => url.contains('nos.lol') ? 'Connected' : 'Connecting',
        statusColor: (url) => url.contains('nos.lol') ? Colors.green : Colors.orange,
      )));

      expect(find.text('INBOX RELAYS'), findsOneWidget);
      expect(find.text('Where people send you messages.'), findsOneWidget);
      expect(find.text('nos.lol'), findsOneWidget);
      expect(find.text('custom.example.com'), findsOneWidget);
      expect(find.text('Default'), findsOneWidget);
      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('Connecting'), findsOneWidget);
    });

    testWidgets('tapping the cross removes that server', (tester) async {
      String? removed;
      await tester.pumpWidget(_host(EditableServerList(
        title: 'RELAYS',
        description: '',
        servers: const ['wss://nos.lol', 'wss://custom.example.com'],
        defaults: const [],
        addLabel: 'Add relay',
        hint: 'relay.example.com',
        fileServer: false,
        onSubmit: (_) async => const ListEdit(ListChange.ok, []),
        onRemove: (url) => removed = url,
      )));

      await tester.tap(find.byIcon(Icons.close_rounded).last);
      expect(removed, 'wss://custom.example.com');
    });

    testWidgets('no add row when the list is full', (tester) async {
      await tester.pumpWidget(_host(EditableServerList(
        title: 'RELAYS',
        description: '',
        servers: const ['wss://nos.lol'],
        defaults: const [],
        addLabel: 'Add relay',
        hint: 'relay.example.com',
        fileServer: false,
        onSubmit: null,
        onRemove: (_) {},
      )));

      expect(find.text('Add relay'), findsNothing);
    });

    testWidgets('shows a warning when there is one', (tester) async {
      await tester.pumpWidget(_host(EditableServerList(
        title: 'RELAYS',
        description: '',
        warning: 'Three are enough.',
        servers: const ['wss://nos.lol'],
        defaults: const [],
        addLabel: 'Add relay',
        hint: 'relay.example.com',
        fileServer: false,
        onSubmit: (_) async => const ListEdit(ListChange.ok, []),
        onRemove: (_) {},
      )));

      expect(find.text('Three are enough.'), findsOneWidget);
    });
  });

  group('inline add row', () {
    testWidgets('turns into an input, explains a refusal, then adds', (tester) async {
      var list = <String>['wss://nos.lol'];
      late StateSetter refresh;

      await tester.pumpWidget(_host(StatefulBuilder(builder: (context, setState) {
        refresh = setState;
        return EditableServerList(
          title: 'RELAYS',
          description: '',
          servers: list,
          defaults: const [],
          addLabel: 'Add relay',
          hint: 'relay.example.com',
          fileServer: false,
          onSubmit: (text) async {
            final edit = ServerLists.add(list, text, normalize: ServerAddress.relay, max: 5);
            if (edit.ok) refresh(() => list = edit.list);
            return edit;
          },
          onRemove: (_) {},
        );
      })));

      expect(find.byType(TextField), findsNothing);
      expect(find.byIcon(Icons.add_rounded), findsOneWidget);

      await tester.tap(find.text('Add relay'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'ws://insecure.example.com');
      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pumpAndSettle();
      expect(find.text(changeMessage(ListChange.invalid, fileServer: false)), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'nos.lol');
      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pumpAndSettle();
      expect(find.text(changeMessage(ListChange.duplicate, fileServer: false)), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'relay.damus.io');
      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pumpAndSettle();

      expect(list, ['wss://nos.lol', 'wss://relay.damus.io']);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('relay.damus.io'), findsOneWidget);
      expect(find.text('Add relay'), findsOneWidget);
    });

    testWidgets('checking an empty input just closes it', (tester) async {
      await tester.pumpWidget(_host(EditableServerList(
        title: 'RELAYS',
        description: '',
        servers: const ['wss://nos.lol'],
        defaults: const [],
        addLabel: 'Add relay',
        hint: 'relay.example.com',
        fileServer: false,
        onSubmit: (_) async => fail('should not submit'),
        onRemove: (_) {},
      )));

      await tester.tap(find.text('Add relay'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(find.text('Add relay'), findsOneWidget);
    });
  });
}
