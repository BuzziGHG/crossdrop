import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'storage_service.dart';

typedef VpnStatusCallback = void Function(bool isConnected, String? assignedIp);
typedef VpnDataCallback = void Function(Map<String, dynamic> data);

class VpnTunnelService {
  final StorageService _storage;
  WebSocket? _socket;
  bool _isConnected = false;
  String? _assignedVpnIp;
  Timer? _reconnectTimer;
  bool _shouldBeConnected = false;

  VpnStatusCallback? onStatusChanged;
  VpnDataCallback? onDataReceived;

  VpnTunnelService(this._storage);

  bool get isConnected => _isConnected;
  String? get assignedVpnIp => _assignedVpnIp;

  Future<void> startAutoVpn({
    VpnStatusCallback? onStatusChanged,
    VpnDataCallback? onDataReceived,
  }) async {
    this.onStatusChanged = onStatusChanged;
    this.onDataReceived = onDataReceived;
    _shouldBeConnected = true;
    await _connect();
  }

  Future<void> stop() async {
    _shouldBeConnected = false;
    _reconnectTimer?.cancel();
    await _socket?.close();
    _socket = null;
    _isConnected = false;
    _assignedVpnIp = null;
    onStatusChanged?.call(false, null);
  }

  Future<void> _connect() async {
    if (!_shouldBeConnected || _storage.token == null) return;

    try {
      // Construct WebSocket URL from serverUrl
      var baseUrl = _storage.serverUrl;
      if (baseUrl.startsWith('https://')) {
        baseUrl = 'wss://${baseUrl.substring(8)}';
      } else if (baseUrl.startsWith('http://')) {
        baseUrl = 'ws://${baseUrl.substring(7)}';
      } else {
        baseUrl = 'ws://$baseUrl';
      }

      final wsUri = Uri.parse('$baseUrl/api/vpn/tunnel?token=${_storage.token}&device_id=${_storage.deviceId}');
      
      _socket = await WebSocket.connect(wsUri.toString()).timeout(const Duration(seconds: 10));

      _isConnected = true;
      _socket!.listen(
        _onMessage,
        onDone: _onDisconnected,
        onError: (err) => _onDisconnected(),
        cancelOnError: true,
      );
    } catch (e) {
      _onDisconnected();
    }
  }

  void _onMessage(dynamic raw) {
    try {
      final Map<String, dynamic> data = jsonDecode(raw.toString());
      final type = data['type'];

      if (type == 'vpn_connected') {
        _assignedVpnIp = data['assigned_ip'];
        _isConnected = true;
        onStatusChanged?.call(true, _assignedVpnIp);
      } else {
        onDataReceived?.call(data);
      }
    } catch (_) {}
  }

  void _onDisconnected() {
    _isConnected = false;
    _assignedVpnIp = null;
    _socket = null;
    onStatusChanged?.call(false, null);

    // Auto-reconnect if desired
    if (_shouldBeConnected) {
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(const Duration(seconds: 5), () => _connect());
    }
  }

  void sendThroughTunnel(Map<String, dynamic> payload) {
    if (_socket != null && _isConnected) {
      _socket!.add(jsonEncode(payload));
    }
  }
}
