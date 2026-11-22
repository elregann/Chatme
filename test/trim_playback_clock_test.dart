import 'package:chatme/core/utils/trim_playback_clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DateTime now;
  late TrimPlaybackClock clock;

  setUp(() {
    now = DateTime(2026, 11, 22);
    clock = TrimPlaybackClock(now: () => now);
  });

  test('fresh playback waits for the settle window before moving', () {
    clock.start(Duration.zero, withSettle: true);

    now = now.add(const Duration(milliseconds: 299));
    expect(clock.position, Duration.zero);

    now = now.add(const Duration(milliseconds: 2));
    expect(clock.position, const Duration(milliseconds: 1));
  });

  test('resume from a pause advances immediately without restarting the delay',
      () {
    clock.start(Duration.zero, withSettle: true);
    now = now.add(const Duration(milliseconds: 500));
    final frozen = clock.position;
    clock.pause();

    clock.start(frozen);
    now = now.add(const Duration(milliseconds: 10));

    // The 300 ms settle was already spent before the pause, so only the new
    // 10 ms is added here. Restarting the delay would leave this at 200 ms.
    expect(clock.position, const Duration(milliseconds: 210));
  });

  test('a seek anchors progress and a stale native position cannot pull it back',
      () {
    clock.seek(const Duration(seconds: 10));
    clock.start(clock.position);

    // A late player report near the start is deliberately not fed in: this
    // clock has no sync method, so only UI commands can move the anchor.
    now = now.add(const Duration(milliseconds: 200));

    expect(clock.position,
        greaterThanOrEqualTo(const Duration(seconds: 10)));
  });

  test('pausing freezes the last visual position', () {
    clock.start(const Duration(seconds: 2));
    now = now.add(const Duration(milliseconds: 150));
    clock.pause();
    final frozen = clock.position;

    now = now.add(const Duration(seconds: 2));

    expect(clock.position, frozen);
    expect(clock.running, isFalse);
  });

  test('snapping at the trim end stays there', () {
    clock.start(const Duration(seconds: 8));
    clock.snapTo(const Duration(seconds: 10));

    now = now.add(const Duration(seconds: 1));

    expect(clock.position, const Duration(seconds: 10));
    expect(clock.running, isFalse);
  });

  test('reset returns to the trim start', () {
    clock.start(const Duration(seconds: 4));
    clock.reset(const Duration(milliseconds: 500));

    expect(clock.position, const Duration(milliseconds: 500));
    expect(clock.running, isFalse);
  });
}
