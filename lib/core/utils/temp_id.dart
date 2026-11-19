// temp_id.dart

import 'dart:math' as math;

/// Process-wide salt, so two runs that send in the same millisecond still get
/// different identities.
final int _session = math.Random().nextInt(1 << 30);

int _sequence = 0;

/// Unique identity for a message that has not been wrapped yet.
///
/// Keeps the `temp_` prefix because cleanup, the offline queue and the reply
/// filters all recognise a local send by that prefix. The millisecond keeps
/// ids readable and roughly ordered; the session salt and sequence make
/// several sends inside one frame distinct.
String newTempId([int? millis]) {
  final ms = millis ?? DateTime.now().millisecondsSinceEpoch;
  return 'temp_${ms}_${_session}_${_sequence++}';
}

/// File-name-safe unique part of [tempId], for `out_<token>.jpg` and friends.
String tempIdFileToken(String tempId) => tempId.substring('temp_'.length);
