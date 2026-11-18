import 'dart:io';

import 'package:chatme/data/discovery_apps.dart';
import 'package:chatme/tab_discovery.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remixicon/remixicon.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('curated apps are complete, unique and locally iconned', () {
    expect(discoveryApps.length, inInclusiveRange(30, 40));
    expect(
      discoveryApps.map((app) => app.name).toList(),
      containsAll(<String>[
        'Alby',
        'Openvibe',
        'Nosotros',
        'Nym',
        'Primal Studio',
        'Nostr Doctor',
        'Nests',
        'Shosho',
        'Nostu',
        'Mostro',
        'Oddbean',
        'Nostrord',
      ]),
    );
    expect(discoveryApps.map((app) => app.url).toSet().length,
        discoveryApps.length);
    expect(discoveryApps.map((app) => app.iconAsset).toSet().length,
        discoveryApps.length);

    for (final app in discoveryApps) {
      expect(app.name, isNotEmpty);
      expect(app.description, isNotEmpty);
      expect(app.url, startsWith('https://'));
      expect(app.iconAsset, startsWith('assets/discovery_icons/'));
      expect(File(app.iconAsset).existsSync(), isTrue,
          reason: 'Missing bundled icon: ${app.iconAsset}');
      expect(app.host, isNotEmpty);
      expect(app.host, isNot(contains('https')));
    }
  });

  testWidgets('Discovery is a flat list with icons and opens a web app',
      (tester) async {
    DiscoveryApp? opened;

    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryScreen(onOpen: (app) => opened = app),
      ),
    );
    await tester.pump();

    expect(find.text('Discovery'), findsOneWidget);
    final appBar = tester.widget<AppBar>(find.byType(AppBar).first);
    expect(appBar.centerTitle, isFalse);
    expect(appBar.titleSpacing, 16);

    // No category headers anymore.
    for (final label in ['Social', 'Reading', 'Media', 'Tools', 'Games']) {
      expect(find.text(label), findsNothing);
    }

    expect(find.text('Primal'), findsOneWidget);
    expect(find.text('Fast social client with a built-in wallet'),
        findsOneWidget);
    expect(find.byType(Image), findsAtLeastNWidgets(1));
    expect(find.byIcon(Remix.global_line), findsNothing);

    await tester.tap(find.text('Primal'));
    await tester.pump();

    expect(opened, isNotNull);
    expect(opened!.url, 'https://primal.net');
    expect(opened!.iconAsset, 'assets/discovery_icons/primal.png');
  });
}
