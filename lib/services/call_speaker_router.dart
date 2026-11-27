import 'package:flutter/foundation.dart';

/// Applies one speaker change to one audio owner.
typedef SpeakerSetter = Future<void> Function(bool enabled);

/// Keeps the WebRTC audio session and our native override from drifting apart.
///
/// flutter_webrtc owns an AudioSwitch session for the whole call. Writing to
/// our own AudioManager channel at the same time leaves two routing states:
/// the UI can say "speaker off" while the device still plays through speaker.
/// During a call only WebRTC changes the route; the native override is cleared
/// on teardown so a late state cannot keep the speaker forced on. Changes are
/// serialized so a toggle still in flight cannot land after the teardown reset.
class CallSpeakerRouter {
  CallSpeakerRouter({
    required this.viaWebRtc,
    required this.viaNative,
    bool Function()? isWeb,
  }) : _isWeb = isWeb ?? (() => kIsWeb);

  final SpeakerSetter viaWebRtc;
  final SpeakerSetter viaNative;
  final bool Function() _isWeb;

  Future<void> _tail = Future.value();

  Future<void> setDuringCall(bool enabled) => _enqueue(() async {
        if (_isWeb()) return;
        await viaWebRtc(enabled);
      });

  Future<void> resetAfterCall() => _enqueue(() async {
        if (_isWeb()) return;
        try {
          await viaWebRtc(false);
        } catch (e) {
          // Cleanup is best effort; the native override must still be released.
          debugPrint('[CallSpeakerRouter] WebRTC speaker reset failed | $e');
        }
        await viaNative(false);
      });

  Future<void> _enqueue(Future<void> Function() action) {
    final next = _tail.then((_) => action());
    // Keep the chain alive even when one change fails.
    _tail = next.catchError((_) {});
    return next;
  }
}
