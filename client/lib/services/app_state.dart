import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/user.dart';
import '../models/device.dart';
import '../models/transfer_item.dart';
import 'storage_service.dart';
import 'api_service.dart';
import 'transfer_server.dart';
import 'transfer_client.dart';
import 'network_detector.dart';
import 'vpn_tunnel_service.dart';
import 'notification_service.dart';

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

  // Active send and download task tracking
  String? activeSendingTaskId;
  final Map<String, HttpClient> _activeDownloads = {};
  final Set<String> _cancelledDownloads = {};

  void cancelTransfer(String taskId) {
    _cancelledDownloads.add(taskId);

    // 1. Cancel active outgoing send if this task is sending
    TransferClient.cancelTransfer(taskId);

    // 2. Cancel active incoming local server upload
    server.cancelTransfer(taskId);

    // 3. Cancel active incoming relay download if this task is downloading
    final downloadClient = _activeDownloads.remove(taskId);
    try {
      downloadClient?.close(force: true);
    } catch (_) {}

    // 3. Mark transfer as cancelled locally
    final transfer = transfers.where((t) => t.id == taskId).firstOrNull;
    if (transfer != null) {
      transfer.status = TransferStatus.cancelled;
      transfer.errorMessage = 'Übertragung durch Benutzer abgebrochen.';
      transfer.speedBytesPerSecond = 0;
      _handleTransferProgress(transfer);

      // Signal cancellation to peer via WebSocket tunnel if connected
      if (vpnTunnel.isConnected && transfer.peerDeviceId != null && transfer.peerDeviceId!.isNotEmpty) {
        vpnTunnel.sendThroughTunnel({
          'type': 'transfer_cancelled',
          'task_id': taskId,
          'target_device_id': transfer.peerDeviceId,
        });
      }
    }

    if (activeSendingTaskId == taskId) {
      activeSendingTaskId = null;
    }
    NotificationService().cancel(taskId);
    notifyListeners();
  }

  // Tab navigation state
  int selectedNavIndex = 0;

  void setNavIndex(int index) {
    if (selectedNavIndex != index) {
      selectedNavIndex = index;
      notifyListeners();
    }
  }

  TransferItem? get activeTransfer {
    try {
      return transfers.firstWhere(
        (t) => t.status == TransferStatus.running || t.status == TransferStatus.connecting,
      );
    } catch (_) {
      return null;
    }
  }

  AppState(this.storage) {
    api = ApiService(storage);
    server = TransferServer(storage);
    vpnTunnel = VpnTunnelService(storage);

    // Persistent login: Initialize user synchronously so the UI stays logged in
    if (storage.token != null && storage.token!.isNotEmpty) {
      currentUser = AppUser(
        id: storage.userId ?? 0,
        email: storage.email ?? '',
        username: storage.username ?? 'Benutzer',
        token: storage.token!,
      );
    }
    _init();
  }

  Future<void> _init() async {
    await NotificationService().init();
    if (currentUser != null) {
      try {
        final me = await api.getMe();
        currentUser = me;
        await storage.saveUser(id: me.id, email: me.email, username: me.username);
        notifyListeners();
      } catch (_) {}
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
      onDataReceived: _handleTunnelData,
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
      // Only keep active/online devices belonging to other machines
      devices = list.where((d) => d.id != storage.deviceId && d.isOnline).toList();
      isServerReachable = true;
      notifyListeners();
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
    } catch (_) {
      isServerReachable = false;
    }
  }

  Future<bool> _handleIncomingTransferRequest(TransferItem item) async {
    // Eigene Geräte / gleicher Account / lokales LAN: IMMER automatisch annehmen!
    final isOwnTransfer = !item.isCrossAccount &&
        (item.senderEmail == null || item.senderEmail == currentUser?.email);

    if (isOwnTransfer || (!item.isCrossAccount && storage.autoAccept)) {
      transfers.insert(0, item);
      notifyListeners();
      return true;
    }

    // Nur bei echten Cross-Account-Übertragungen von externen E-Mails fragen:
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

    // Live Notification Bar progress update
    if (item.status == TransferStatus.running) {
      NotificationService().showTransferProgress(
        taskId: item.id,
        filename: item.filename,
        progressPercent: (item.progress * 100).round(),
        speed: item.formattedSpeed,
        eta: item.formattedEta,
        isSend: item.direction == TransferDirection.send,
      );
    } else if (item.status == TransferStatus.completed) {
      NotificationService().showTransferCompleted(
        taskId: item.id,
        filename: item.filename,
        isSend: item.direction == TransferDirection.send,
      );
    } else if (item.status == TransferStatus.failed || item.status == TransferStatus.rejected) {
      NotificationService().showTransferFailed(
        taskId: item.id,
        filename: item.filename,
        reason: item.errorMessage ?? (item.status == TransferStatus.rejected ? 'Abgelehnt' : 'Fehlgeschlagen'),
      );
    } else if (item.status == TransferStatus.cancelled) {
      NotificationService().cancel(item.id);
    }
  }

  Future<void> _handleTunnelData(Map<String, dynamic> data) async {
    final type = data['type'];
    if (type == 'transfer_cancelled') {
      final taskId = data['task_id'];
      if (taskId != null) {
        _cancelledDownloads.add(taskId);
        TransferClient.cancelTransfer(taskId);
        server.cancelTransfer(taskId);
        final downloadClient = _activeDownloads.remove(taskId);
        try {
          downloadClient?.close(force: true);
        } catch (_) {}

        final transfer = transfers.where((t) => t.id == taskId).firstOrNull;
        if (transfer != null) {
          transfer.status = TransferStatus.cancelled;
          transfer.errorMessage = 'Übertragung vom Partner abgebrochen.';
          transfer.speedBytesPerSecond = 0;
          _handleTransferProgress(transfer);
        }
        if (activeSendingTaskId == taskId) {
          activeSendingTaskId = null;
        }
        NotificationService().cancel(taskId);
        notifyListeners();
      }
      return;
    }

    if (type == 'relay_finished') {
      final taskId = data['task_id'];
      final transfer = transfers.where((t) => t.id == taskId).firstOrNull;
      if (transfer != null) {
        transfer.status = TransferStatus.completed;
        transfer.bytesTransferred = transfer.totalBytes;
        transfer.speedBytesPerSecond = 0;
        transfer.errorMessage = null;
        _handleTransferProgress(transfer);
      }
      return;
    }

    if (type == 'transfer_rejected') {
      final taskId = data['task_id'];
      final transfer = transfers.where((t) => t.id == taskId).firstOrNull;
      if (transfer != null) {
        transfer.status = TransferStatus.rejected;
        transfer.errorMessage = 'Vom Empfänger abgelehnt.';
        transfer.speedBytesPerSecond = 0;
        _handleTransferProgress(transfer);
      }
      return;
    }

    if (type == 'relay_sender_progress') {
      // Direct streaming pipe tracks true 1:1 live progress locally
      return;
    }

    if (type == 'relay_receiver_progress') {
      // Direct streaming pipe tracks true 1:1 live progress locally
      return;
    }

    if (type == 'transfer_request') {
      final taskId = data['task_id'] ?? '';
      final filename = data['filename'] ?? 'Datei';
      final fileSize = data['size'] ?? 0;
      final senderName = data['sender_name'] ?? 'Gerät';
      final senderId = data['sender_device_id'] ?? '';
      final mode = data['mode'] ?? 'Relay';
      final senderEmail = data['sender_email'] as String?;
      final isCrossAccount = data['is_cross_account'] == true;

      final item = TransferItem(
        id: taskId,
        filename: filename,
        totalBytes: fileSize,
        direction: TransferDirection.receive,
        peerDeviceName: isCrossAccount && senderEmail != null ? senderEmail : senderName,
        peerDeviceId: senderId,
        peerIp: 'Server-Relay',
        peerPort: 2603,
        mode: mode,
        senderEmail: senderEmail,
        isCrossAccount: isCrossAccount,
        status: TransferStatus.pending,
      );

      final accepted = await _handleIncomingTransferRequest(item);
      if (accepted) {
        _startRelayDownload(item, taskId);
      } else {
        // Inform sender immediately that transfer was declined
        if (vpnTunnel.isConnected && senderId.isNotEmpty) {
          vpnTunnel.sendThroughTunnel({
            'type': 'transfer_rejected',
            'task_id': taskId,
            'target_device_id': senderId,
          });
        }
      }
    }
  }

  Future<void> _startRelayDownload(TransferItem item, String taskId) async {
    item.status = TransferStatus.running;
    item.bytesTransferred = 0;
    item.errorMessage = 'Verbinde mit Sender über Server-Relay...';
    _handleTransferProgress(item);

    // 1. Prepare destination path
    String downloadDir = storage.downloadPath ?? '';
    if (downloadDir.isEmpty) {
      if (Platform.isAndroid) {
        final androidDownloadDir = Directory('/storage/emulated/0/Download');
        if (await androidDownloadDir.exists()) {
          downloadDir = androidDownloadDir.path;
        } else {
          final extDir = await getExternalStorageDirectory();
          downloadDir = extDir?.path ?? (await getApplicationDocumentsDirectory()).path;
        }
      } else {
        final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
        downloadDir = dir.path;
      }
    }

    String finalPath = p.join(downloadDir, item.filename);
    int counter = 1;
    final extension = p.extension(item.filename);
    final basenameWithoutExt = p.basenameWithoutExtension(item.filename);
    while (File(finalPath).existsSync()) {
      finalPath = p.join(downloadDir, '$basenameWithoutExt($counter)$extension');
      counter++;
    }

    final targetFile = File(finalPath);
    final sink = targetFile.openWrite(mode: FileMode.write);

    // 2. Stream download directly from server relay in-memory pipe
    final client = HttpClient();
    client.idleTimeout = const Duration(seconds: 120);
    client.connectionTimeout = const Duration(seconds: 30);
    _activeDownloads[taskId] = client;

    try {
      item.errorMessage = 'Streaming von Sender läuft...';
      _handleTransferProgress(item);

      final downloadUri = Uri.parse('${storage.serverUrl}/api/transfer/relay/pipe/$taskId/download');
      final request = await client.getUrl(downloadUri);
      if (storage.token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${storage.token}');
      }
      final response = await request.close();

      if (response.statusCode != 200) {
        throw Exception('Server-Download fehlgeschlagen (HTTP ${response.statusCode})');
      }

      if (response.contentLength > 0 && item.totalBytes <= 0) {
        item.totalBytes = response.contentLength;
      }

      int receivedBytes = 0;
      int lastCheckBytes = 0;
      DateTime lastTime = DateTime.now();

      await for (final chunk in response) {
        if (_cancelledDownloads.contains(taskId)) {
          break;
        }

        sink.add(chunk);
        receivedBytes += chunk.length;

        // 1:1 Live synchronous progress (0% -> 100%)
        item.bytesTransferred = receivedBytes;
        item.errorMessage = null;

        final now = DateTime.now();
        final ms = now.difference(lastTime).inMilliseconds;
        if (ms >= 300) {
          final bytesDiff = receivedBytes - lastCheckBytes;
          final currentSpeed = (bytesDiff / (ms / 1000.0));
          item.speedBytesPerSecond = item.speedBytesPerSecond == 0
              ? currentSpeed
              : (item.speedBytesPerSecond * 0.4 + currentSpeed * 0.6);
          lastCheckBytes = receivedBytes;
          lastTime = now;
          _handleTransferProgress(item);
        }
      }

      await sink.flush();
      await sink.close();

      if (_cancelledDownloads.contains(taskId)) {
        try {
          if (await targetFile.exists()) await targetFile.delete();
        } catch (_) {}
        item.status = TransferStatus.cancelled;
        item.errorMessage = 'Übertragung abgebrochen.';
        item.speedBytesPerSecond = 0;
        _handleTransferProgress(item);
        return;
      }

      if (item.totalBytes > 0 && receivedBytes < item.totalBytes) {
        try {
          if (await targetFile.exists()) await targetFile.delete();
        } catch (_) {}
        throw Exception('Unvollständiger Download: Nur $receivedBytes von ${item.totalBytes} Bytes empfangen.');
      }

      item.status = TransferStatus.completed;
      item.bytesTransferred = item.totalBytes > 0 ? item.totalBytes : receivedBytes;
      item.speedBytesPerSecond = 0;
      item.errorMessage = null;
      _handleTransferProgress(item);

      // Clean up relay task on server (best effort)
      try {
        await api.deleteRelayFile(taskId);
      } catch (_) {}

      // Notify sender that download is 100% complete!
      if (vpnTunnel.isConnected && item.peerDeviceId != null) {
        vpnTunnel.sendThroughTunnel({
          'type': 'relay_finished',
          'task_id': taskId,
          'target_device_id': item.peerDeviceId,
        });
      }
    } catch (e) {
      try {
        await sink.close();
      } catch (_) {}
      if (_cancelledDownloads.contains(taskId)) {
        try {
          if (await targetFile.exists()) await targetFile.delete();
        } catch (_) {}
        item.status = TransferStatus.cancelled;
        item.errorMessage = 'Übertragung abgebrochen.';
        item.speedBytesPerSecond = 0;
      } else {
        item.status = TransferStatus.failed;
        item.errorMessage = 'Download-Fehler: $e';
      }
      _handleTransferProgress(item);
    } finally {
      _activeDownloads.remove(taskId);
      _cancelledDownloads.remove(taskId);
      client.close();
    }
  }

  Future<void> startSendingFile({
    required File file,
    required DeviceModel targetDevice,
    required ConnectionMode mode,
  }) async {
    final targetIp = mode == ConnectionMode.vpn
        ? (targetDevice.vpnIps.isNotEmpty ? targetDevice.vpnIps.first : '10.42.0.1')
        : (targetDevice.localIps.isNotEmpty ? targetDevice.localIps.first : (targetDevice.vpnIps.isNotEmpty ? targetDevice.vpnIps.first : '10.42.0.1'));

    final modeString = mode == ConnectionMode.vpn ? 'VPN' : 'LAN';

    final candidateIps = <String>[
      if (mode == ConnectionMode.lan) ...targetDevice.localIps,
      if (targetDevice.vpnIps.isNotEmpty) ...targetDevice.vpnIps,
    ];

    try {
      await TransferClient.sendFile(
        file: file,
        targetIp: targetIp,
        targetPort: targetDevice.transferPort,
        targetDeviceName: targetDevice.name,
        senderDeviceName: deviceName,
        connectionMode: modeString,
        candidateIps: candidateIps,
        targetDeviceId: targetDevice.id,
        senderDeviceId: storage.deviceId,
        serverUrl: storage.serverUrl,
        token: storage.token,
        vpnTunnel: vpnTunnel,
        onProgress: (item) {
          activeSendingTaskId = item.id;
          _handleTransferProgress(item);
        },
      );
    } finally {
      // Keep activeSendingTaskId visible briefly for UI to show finished state
      Future.delayed(const Duration(seconds: 4), () {
        if (activeSendingTaskId != null) {
          activeSendingTaskId = null;
          notifyListeners();
        }
      });
    }
  }

  Future<void> startSendingFileByEmail({
    required File file,
    required String recipientEmail,
  }) async {
    // 1. Verify recipient with server
    final recipient = await api.lookupRecipient(recipientEmail);
    final targetDeviceId = recipient['target_device_id'] as String?;
    final targetDeviceName = recipient['target_device_name'] as String? ??
        recipient['username'] as String? ??
        'Empfänger';
    final hasOnlineDevice = recipient['has_online_device'] as bool? ?? false;

    if (targetDeviceId == null || !hasOnlineDevice) {
      throw Exception('Der Account "$recipientEmail" hat momentan kein empfangsbereites Gerät online.');
    }

    // 2. Transfer via VPN Server-Relay with cross-account approval required
    try {
      await TransferClient.sendFile(
        file: file,
        targetIp: '10.42.0.1',
        targetPort: 2603,
        targetDeviceName: targetDeviceName,
        senderDeviceName: deviceName,
        connectionMode: 'VPN',
        targetDeviceId: targetDeviceId,
        senderDeviceId: storage.deviceId,
        serverUrl: storage.serverUrl,
        token: storage.token,
        vpnTunnel: vpnTunnel,
        isCrossAccount: true,
        senderEmail: storage.email,
        recipientEmail: recipientEmail.trim(),
        onProgress: (item) {
          activeSendingTaskId = item.id;
          _handleTransferProgress(item);
        },
      );
    } finally {
      Future.delayed(const Duration(seconds: 4), () {
        if (activeSendingTaskId != null) {
          activeSendingTaskId = null;
          notifyListeners();
        }
      });
    }
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
