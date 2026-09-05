import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/user.dart';
import '../models/device.dart';
import '../models/transfer_item.dart';
import 'storage_service.dart';
import 'api_service.dart';
import 'transfer_server.dart';
import 'transfer_client.dart';
import 'network_detector.dart';
import 'vpn_tunnel_service.dart';

class AppState extends ChangeNotifier {
  final StorageService storage;
  late final ApiService api;
  late final TransferServer server;
  late final VpnTunnelService vpnTunnel;

  AppUser? currentUser;
  List<DeviceModel> devices = [];
  final List<TransferItem> transfers = [];

  List<String> myLocalIps = [];
  List<String> myVpnIps = [];

  bool isLoading = false;
  bool isServerReachable = true;
  String? errorMessage;

  Timer? _heartbeatTimer;
  Timer? _devicePollTimer;

  // Pending approval request for UI dialog
  TransferItem? pendingApprovalItem;
  Completer<bool>? _approvalCompleter;

  AppState(this.storage) {
    api = ApiService(storage);
    server = TransferServer(storage);
    vpnTunnel = VpnTunnelService(storage);
    _init();
  }

  Future<void> _init() async {
    if (storage.token != null && storage.email != null && storage.userId != null) {
      currentUser = AppUser(
        id: storage.userId!,
        email: storage.email!,
        username: storage.username ?? 'Benutzer',
        token: storage.token!,
      );
      notifyListeners();
      await onUserLoggedIn();
    }
  }

  bool get isAuthenticated => currentUser != null;
  bool get isVpnActive => vpnTunnel.isConnected;
  String? get vpnIp => vpnTunnel.assignedVpnIp;

  String get deviceName {
    final name = storage.deviceName;
    if (name != null && name.isNotEmpty) return name;
    final platform = NetworkDetector.getPlatformName();
    return 'Gerät ($platform)';
  }

  Future<void> login(String email, String password) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      currentUser = await api.login(email, password);
      isServerReachable = true;
      await onUserLoggedIn();
    } catch (e) {
      errorMessage = e.toString().replaceAll('Exception: ', '');
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> register(String email, String username, String password) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      currentUser = await api.register(email, username, password);
      isServerReachable = true;
      await onUserLoggedIn();
    } catch (e) {
      errorMessage = e.toString().replaceAll('Exception: ', '');
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    _heartbeatTimer?.cancel();
    _devicePollTimer?.cancel();
    await vpnTunnel.stop();
    await server.stop();
    await storage.clearUser();
    currentUser = null;
    devices.clear();
    myVpnIps.clear();
    notifyListeners();
  }

  Future<void> onUserLoggedIn() async {
    await refreshNetwork();

    await server.start(
      onRequest: _handleIncomingTransferRequest,
      onProgress: _handleTransferProgress,
    );

    // Auto-connect Zero-Config VPN
    await vpnTunnel.startAutoVpn(
      onStatusChanged: (connected, assignedIp) {
        if (connected && assignedIp != null) {
          if (!myVpnIps.contains(assignedIp)) {
            myVpnIps.add(assignedIp);
          }
        } else {
          myVpnIps.clear();
        }
        notifyListeners();
      },
    );

    // Register device
    try {
      await api.registerDevice(
        deviceId: storage.deviceId,
        name: deviceName,
        platform: NetworkDetector.getPlatformName(),
        localIps: myLocalIps,
        vpnIps: myVpnIps,
        transferPort: server.port,
      );
      isServerReachable = true;
    } on AuthExpiredException {
      await _handleServerReset();
      return;
    } catch (_) {
      isServerReachable = false;
    }

    await refreshDevices();

    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (_) => _sendHeartbeat());

    _devicePollTimer?.cancel();
    _devicePollTimer = Timer.periodic(const Duration(seconds: 8), (_) => refreshDevices());
  }

  Future<void> _handleServerReset() async {
    await logout();
    errorMessage = 'Der Server wurde neu installiert oder die Sitzung ist abgelaufen. Bitte registrieren Sie sich neu oder melden Sie sich an.';
    notifyListeners();
  }

  Future<void> refreshNetwork() async {
    final ips = await NetworkDetector.detectIpAddresses();
    myLocalIps = ips['local'] ?? [];
    if (vpnTunnel.assignedVpnIp != null && !myVpnIps.contains(vpnTunnel.assignedVpnIp)) {
      myVpnIps.add(vpnTunnel.assignedVpnIp!);
    }
    notifyListeners();
  }

  Future<void> refreshDevices() async {
    if (!isAuthenticated) return;
    try {
      final list = await api.getDevices();
      devices = list.where((d) => d.id != storage.deviceId).toList();
      isServerReachable = true;
      notifyListeners();
    } on AuthExpiredException {
      await _handleServerReset();
    } catch (_) {
      isServerReachable = false;
      notifyListeners();
    }
  }

  Future<void> _sendHeartbeat() async {
    if (!isAuthenticated) return;
    try {
      await refreshNetwork();
      await api.sendHeartbeat(
        deviceId: storage.deviceId,
        localIps: myLocalIps,
        vpnIps: myVpnIps,
        transferPort: server.port,
      );
      isServerReachable = true;
    } on AuthExpiredException {
      await _handleServerReset();
    } catch (_) {
      isServerReachable = false;
    }
  }

  Future<bool> _handleIncomingTransferRequest(TransferItem item) async {
    pendingApprovalItem = item;
    _approvalCompleter = Completer<bool>();
    notifyListeners();

    final accepted = await _approvalCompleter!.future;
    pendingApprovalItem = null;
    if (accepted) {
      transfers.insert(0, item);
    }
    notifyListeners();
    return accepted;
  }

  void approveTransfer(bool accept) {
    if (_approvalCompleter != null && !_approvalCompleter!.isCompleted) {
      _approvalCompleter!.complete(accept);
    }
    pendingApprovalItem = null;
    notifyListeners();
  }

  void _handleTransferProgress(TransferItem item) {
    final index = transfers.indexWhere((t) => t.id == item.id);
    if (index != -1) {
      transfers[index] = item;
    } else {
      transfers.insert(0, item);
    }
    notifyListeners();
  }

  Future<void> startSendingFile({
    required File file,
    required DeviceModel targetDevice,
    required ConnectionMode mode,
  }) async {
    final targetIp = mode == ConnectionMode.vpn
        ? (targetDevice.vpnIps.isNotEmpty ? targetDevice.vpnIps.first : null)
        : (targetDevice.localIps.isNotEmpty ? targetDevice.localIps.first : null);

    if (targetIp == null) {
      throw Exception('Keine gültige ${mode == ConnectionMode.vpn ? "VPN" : "LAN"}-IP für ${targetDevice.name} gefunden.');
    }

    final modeString = mode == ConnectionMode.vpn ? 'VPN' : 'LAN';

    await TransferClient.sendFile(
      file: file,
      targetIp: targetIp,
      targetPort: targetDevice.transferPort,
      targetDeviceName: targetDevice.name,
      senderDeviceName: deviceName,
      connectionMode: modeString,
      onProgress: (item) {
        final idx = transfers.indexWhere((t) => t.id == item.id);
        if (idx != -1) {
          transfers[idx] = item;
        } else {
          transfers.insert(0, item);
        }
        notifyListeners();
      },
    );
  }

  void setDeviceConnectionMode(DeviceModel device, ConnectionMode mode) {
    device.preferredMode = mode;
    notifyListeners();
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _devicePollTimer?.cancel();
    vpnTunnel.stop();
    server.stop();
    super.dispose();
  }
}
