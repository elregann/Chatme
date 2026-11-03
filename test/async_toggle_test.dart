import 'dart:async';

import 'package:chatme/services/async_toggle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('flips the value after the change succeeds', () async {
    final toggle = AsyncToggle();
    final applied = <bool>[];

    expect(await toggle.toggle((next) async => applied.add(next)), isTrue);
    expect(toggle.value, isTrue);
    expect(await toggle.toggle((next) async => applied.add(next)), isTrue);
    expect(toggle.value, isFalse);
    expect(applied, [true, false]);
  });

  test('ignores taps while a change is still running', () async {
    final toggle = AsyncToggle();
    final gate = Completer<void>();
    var calls = 0;

    final first = toggle.toggle((next) {
      calls++;
      return gate.future;
    });
    final second = toggle.toggle((next) async => calls++);
    final third = toggle.toggle((next) async => calls++);

    expect(toggle.busy, isTrue);
    expect(await second, isFalse);
    expect(await third, isFalse);

    gate.complete();
    expect(await first, isTrue);
    expect(calls, 1);
    expect(toggle.value, isTrue);
    expect(toggle.busy, isFalse);
  });

  test('rapid taps always end with a value that matches what was applied', () async {
    final toggle = AsyncToggle();
    var deviceState = false;

    for (var i = 0; i < 25; i++) {
      await toggle.toggle((next) async {
        await Future<void>.delayed(Duration.zero);
        deviceState = next;
      });
    }

    expect(toggle.value, deviceState);
    expect(toggle.value, isTrue);
  });

  test('keeps the old value and stays usable when the change fails', () async {
    final toggle = AsyncToggle();

    final changed = await toggle.toggle((next) async => throw StateError('native failure'));
    expect(changed, isFalse);
    expect(toggle.value, isFalse);
    expect(toggle.busy, isFalse);

    expect(await toggle.toggle((next) async {}), isTrue);
    expect(toggle.value, isTrue);
  });

  test('reset sets the value without applying anything', () async {
    final toggle = AsyncToggle(value: true);
    toggle.reset(false);
    expect(toggle.value, isFalse);
  });
}
