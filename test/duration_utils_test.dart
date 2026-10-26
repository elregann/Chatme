// duration_utils_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:chatme/core/utils/duration_utils.dart';

void main() {
  test('call duration label', () {
    expect(DurationUtils.formatCallDuration(0), '');
    expect(DurationUtils.formatCallDuration(27), '27s');
    expect(DurationUtils.formatCallDuration(60), '1m 0s');
    expect(DurationUtils.formatCallDuration(87), '1m 27s');
    expect(DurationUtils.formatCallDuration(3599), '59m 59s');
    expect(DurationUtils.formatCallDuration(3600), '1h 0m 0s');
    expect(DurationUtils.formatCallDuration(6483), '1h 48m 3s');
  });

  test('call screen clock', () {
    expect(DurationUtils.formatClock(0), '00:00');
    expect(DurationUtils.formatClock(93), '01:33');
    expect(DurationUtils.formatClock(3599), '59:59');
    expect(DurationUtils.formatClock(3600), '01:00:00');
    expect(DurationUtils.formatClock(5610), '01:33:30');
    expect(DurationUtils.formatClock(6483), '01:48:03');
  });
}
