// network_manager.dart

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class NetworkManager {
  static final NetworkManager _instance = NetworkManager._internal();
  factory NetworkManager() => _instance;
  NetworkManager._internal();

  bool _isConnected = true;
  StreamSubscription? _subscription;
  Function? onReconnect;

  Future<void> initialize() async {
    if (kIsWeb) return;

    // Check initial connection
    final result = await Connectivity().checkConnectivity();
    _isConnected = _isOnline(result);

    // Monitor connection changes in realtime
    _subscription = Connectivity().onConnectivityChanged.listen((result) {
      final wasConnected = _isConnected;
      _isConnected = _isOnline(result);

      // If was offline and back online → trigger reconnect
      if (!wasConnected && _isConnected) {
        onReconnect?.call();
      }
    });
  }

  bool _isOnline(List<ConnectivityResult> result) {
    return result.any((r) =>
    r == ConnectivityResult.mobile ||
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.ethernet);
  }

  bool get isConnected => _isConnected;

  void dispose() {
    _subscription?.cancel();
  }
}