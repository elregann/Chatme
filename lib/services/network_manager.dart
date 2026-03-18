// network_manager.dart

class NetworkManager {
  static final NetworkManager _instance = NetworkManager._internal();
  factory NetworkManager() => _instance;
  NetworkManager._internal();

  bool _isConnected = true;

  Future<void> initialize() async {
    _isConnected = true;
  }

  bool get isConnected => _isConnected;

  Future<bool> checkConnection() async {
    return _isConnected;
  }

  void updateStatus(bool connected) {
    _isConnected = connected;
  }

  void dispose() {}
}