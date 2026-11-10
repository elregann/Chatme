// message_highlight_test.dart

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatme/widgets/message_highlight.dart';

const _rowKey = Key('row');
const _bandKey = Key('message_highlight_band');
const _fadeKey = Key('message_highlight_fade');
const _blue = Color(0x382196F3);

Widget _app({
  required bool highlighted,
  double bleed = 8,
  VoidCallback? onTap,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 300,
          child: MessageHighlight(
            highlighted: highlighted,
            color: _blue,
            bleed: bleed,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: const SizedBox(key: _rowKey, width: 300, height: 40),
            ),
          ),
        ),
      ),
    ),
  );
}

double _opacity(WidgetTester tester) =>
    tester.renderObject<RenderAnimatedOpacity>(find.byKey(_fadeKey)).opacity.value;

void main() {
  testWidgets('is invisible when not highlighted', (tester) async {
    await tester.pumpWidget(_app(highlighted: false));
    expect(_opacity(tester), 0.0);
  });

  testWidgets('fades in when highlighted and out again', (tester) async {
    await tester.pumpWidget(_app(highlighted: false));
    await tester.pumpWidget(_app(highlighted: true));
    await tester.pump(const Duration(milliseconds: 150));
    expect(_opacity(tester), allOf(greaterThan(0.0), lessThan(1.0)));

    await tester.pump(MessageHighlight.fade);
    expect(_opacity(tester), 1.0);

    await tester.pumpWidget(_app(highlighted: false));
    await tester.pump(MessageHighlight.fade);
    expect(_opacity(tester), 0.0);
  });

  testWidgets('covers the row and bleeds past both sides', (tester) async {
    await tester.pumpWidget(_app(highlighted: true, bleed: 8));
    final row = tester.getRect(find.byKey(_rowKey));
    final band = tester.getRect(find.byKey(_bandKey));
    expect(band.left, row.left - 8);
    expect(band.right, row.right + 8);
    expect(band.top, row.top);
    expect(band.bottom, row.bottom);
  });

  testWidgets('without a bleed it matches the row exactly', (tester) async {
    await tester.pumpWidget(_app(highlighted: true, bleed: 0));
    expect(tester.getRect(find.byKey(_bandKey)), tester.getRect(find.byKey(_rowKey)));
  });

  testWidgets('uses the given color', (tester) async {
    await tester.pumpWidget(_app(highlighted: true));
    expect(tester.widget<ColoredBox>(find.byKey(_bandKey)).color, _blue);
  });

  testWidgets('taps still reach the row while it is highlighted', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_app(highlighted: true, onTap: () => taps++));
    await tester.pump(MessageHighlight.fade);
    await tester.tap(find.byKey(_rowKey), warnIfMissed: false);
    expect(taps, 1);
  });
}
