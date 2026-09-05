import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../models/transfer_item.dart';
import 'vpn_tunnel_service.dart';

typedef TransferClientProgressCallback = void Function(TransferItem item);

class TransferClient {
  // High-performance chunk buffer: 64 KB (ensures smooth, real-time TCP flow control)
  static const int _chunkSize = 64 * 1024;

  static Future<void> sendFile({
    required File file,
    required String targetIp,
    required int targetPort,
    required String targetDeviceName,
    required String senderDeviceName,
    required String connectionMode,
    List<String> candidateIps = const [],
    String? targetDeviceId,
    String? senderDeviceId,
    String? serverUrl,
    String? token,
    VpnTunnelService? vpnTunnel,
    required TransferClientProgressCallback onProgress,
  }) async {
    final taskId = const Uuid().v4();
    final filename = p.basename(file.path);
    final fileSize = await file.length();

    final isVpnMode = connectionMode == 'VPN' || targetIp.startsWith('10.42.0.');

    final item = TransferItem(
      id: taskId,
      filename: filename,
      localFilePath: file.path,
      totalBytes: fileSize,
      direction: TransferDirection.send,
      peerDeviceName: targetDeviceName,
      peerDeviceId: targetDeviceId,
      peerIp: isVpnMode ? 'Server-Relay' : targetIp,
      peerPort: isVpnMode ? 2603 : targetPort,
      mode: isVpnMode ? 'Relay' : connectionMode,
      status: TransferStatus.connecting,
    );

    onProgress(item);

    // If VPN or Remote selected, use Server Relay directly
    if (isVpnMode || serverUrl == null) {
      if (serverUrl != null && targetDeviceId != null) {
        await _sendViaRelay(
          file: file,
          taskId: taskId,
          item: item,
          targetDeviceName: targetDeviceName,
          senderDeviceName: senderDeviceName,
          targetDeviceId: targetDeviceId,
          senderDeviceId: senderDeviceId ?? '',
          serverUrl: serverUrl,
          token: token ?? '',
          vpnTunnel: vpnTunnel,
          onProgress: onProgress,
        );
        return;
      }
    }

    // Try Direct LAN across all candidate IPs
    bool lanConnected = false;
    String activeTargetIp = targetIp;

    final ipsToTest = <String>[
      if (!targetIp.startsWith('10.42.0.') && !targetIp.startsWith('127.')) targetIp,
      ...candidateIps.where((ip) => !ip.startsWith('10.42.0.') && !ip.startsWith('127.') && ip != targetIp),
    ];

    for (final testIp in ipsToTest) {
      try {
        final pingUri = Uri.parse('http://$testIp:$targetPort/api/ping');
        final pingRes = await http.get(pingUri).timeout(const Duration(milliseconds: 1500));
        if (pingRes.statusCode == 200) {
          lanConnected = true;
          activeTargetIp = testIp;
          item.peerIp = testIp;
          item.mode = 'LAN';
          break;
        }
      } catch (_) {}
    }

    if (lanConnected) {
      try {
        // 1. Direct LAN Handshake
        final handshakeUri = Uri.parse('http://$activeTargetIp:$targetPort/api/transfer/request');
        final handshakeResponse = await http
            .post(
              handshakeUri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'task_id': taskId,
                'filename': filename,
                'size': fileSize,
                'sender_name': senderDeviceName,
                'mode': 'LAN',
              }),
            )
            .timeout(const Duration(seconds: 45));

        if (handshakeResponse.statusCode == 200) {
          // Direct P2P stream upload with real-time synchronous socket flushing
          await _streamDirectToPeer(
            file: file,
            taskId: taskId,
            targetIp: activeTargetIp,
            targetPort: targetPort,
            fileSize: fileSize,
            item: item,
            onProgress: onProgress,
          );
          return;
        } else {
          item.status = TransferStatus.rejected;
          item.errorMessage = 'Transfer vom Empfänger abgelehnt.';
          onProgress(item);
          return;
        }
      } catch (e) {
        // Direct LAN handshake failed, fallback to Relay below
      }
    }

    // Fallback to Server Relay if direct LAN is blocked by firewall/network isolation
    if (serverUrl != null && targetDeviceId != null) {
      item.errorMessage = 'LAN nicht erreichbar – Schalte auf Server-Relay um...';
      item.mode = 'Relay';
      onProgress(item);

      await _sendViaRelay(
        file: file,
        taskId: taskId,
        item: item,
        targetDeviceName: targetDeviceName,
        senderDeviceName: senderDeviceName,
        targetDeviceId: targetDeviceId,
        senderDeviceId: senderDeviceId ?? '',
        serverUrl: serverUrl,
        token: token ?? '',
        vpnTunnel: vpnTunnel,
        onProgress: onProgress,
      );
    } else {
      item.status = TransferStatus.failed;
      item.errorMessage = 'Verbindungsfehler: Zielgerät im LAN nicht erreichbar.';
      onProgress(item);
    }
  }

  static Future<void> _streamDirectToPeer({
    required File file,
    required String taskId,
    required String targetIp,
    required int targetPort,
    required int fileSize,
    required TransferItem item,
    required TransferClientProgressCallback onProgress,
  }) async {
    item.status = TransferStatus.running;
    onProgress(item);

    final uploadUri = Uri.parse('http://$targetIp:$targetPort/api/transfer/upload/$taskId');

    final client = HttpClient();
    client.idleTimeout = const Duration(seconds: 120);
    client.connectionTimeout = const Duration(seconds: 30);

    try {
      final request = await client.postUrl(uploadUri);
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/octet-stream');
      request.contentLength = fileSize;
      request.bufferOutput = false;

      int sentBytes = 0;
      int lastCheckBytes = 0;
      DateTime lastTime = DateTime.now();

      final raf = await file.open(mode: FileMode.read);
      try {
        while (sentBytes < fileSize) {
          final toRead = (fileSize - sentBytes) > _chunkSize ? _chunkSize : (fileSize - sentBytes);
          final chunk = await raf.read(toRead);
          if (chunk.isEmpty) break;

          request.add(chunk);
          await request.flush();
          sentBytes += chunk.length;
          // Hold sender progress at max 98% until receiver confirms complete write
          item.bytesTransferred = (sentBytes >= fileSize) ? (fileSize * 0.98).round() : sentBytes;

          final now = DateTime.now();
          final ms = now.difference(lastTime).inMilliseconds;
          if (ms >= 300) {
            final bytesDiff = sentBytes - lastCheckBytes;
            final currentSpeed = (bytesDiff / (ms / 1000.0));
            item.speedBytesPerSecond = item.speedBytesPerSecond == 0
                ? currentSpeed
                : (item.speedBytesPerSecond * 0.4 + currentSpeed * 0.6);
            lastCheckBytes = sentBytes;
            lastTime = now;
            onProgress(item);
          }
        }
      } finally {
        await raf.close();
      }

      item.bytesTransferred = (fileSize * 0.98).round();
      item.errorMessage = 'Empfänger schließt Speicherung ab...';
      onProgress(item);

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      client.close();

      if (response.statusCode == 200) {
        item.status = TransferStatus.completed;
        item.bytesTransferred = fileSize;
        item.speedBytesPerSecond = 0;
        item.errorMessage = null;
        onProgress(item);
      } else {
        item.status = TransferStatus.failed;
        item.errorMessage = 'Fehler beim Übertragen (HTTP ${response.statusCode}): $responseBody';
        onProgress(item);
      }
    } catch (e) {
      client.close();
      item.status = TransferStatus.failed;
      item.errorMessage = 'Fehler bei Direktübertragung: $e';
      onProgress(item);
    }
  }

  static Future<void> _sendViaRelay({
    required File file,
    required String taskId,
    required TransferItem item,
    required String targetDeviceName,
    required String senderDeviceName,
    required String targetDeviceId,
    required String senderDeviceId,
    required String serverUrl,
    required String token,
    VpnTunnelService? vpnTunnel,
    required TransferClientProgressCallback onProgress,
  }) async {
    final filename = p.basename(file.path);
    final fileSize = await file.length();

    item.status = TransferStatus.running;
    item.errorMessage = 'Phase 1: Wird an Server-Relay übertragen...';
    onProgress(item);

    // 1. Notify receiver over WebSocket tunnel
    if (vpnTunnel != null && vpnTunnel.isConnected) {
      vpnTunnel.sendThroughTunnel({
        'type': 'transfer_request',
        'task_id': taskId,
        'filename': filename,
        'size': fileSize,
        'sender_name': senderDeviceName,
        'sender_device_id': senderDeviceId,
        'target_device_id': targetDeviceId,
        'mode': 'Relay',
      });
    }

    // 2. Stream upload to server relay
    final uploadUri = Uri.parse(
      '$serverUrl/api/transfer/relay/upload/$taskId'
      '?filename=${Uri.encodeComponent(filename)}'
      '&size=$fileSize'
      '&sender_name=${Uri.encodeComponent(senderDeviceName)}',
    );

    final client = HttpClient();
    client.idleTimeout = const Duration(seconds: 120);
    client.connectionTimeout = const Duration(seconds: 30);

    try {
      final request = await client.postUrl(uploadUri);
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/octet-stream');
      if (token.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      request.contentLength = fileSize;
      request.bufferOutput = false;

      int sentBytes = 0;
      int lastCheckBytes = 0;
      DateTime lastTime = DateTime.now();

      final raf = await file.open(mode: FileMode.read);
      try {
        while (sentBytes < fileSize) {
          final toRead = (fileSize - sentBytes) > _chunkSize ? _chunkSize : (fileSize - sentBytes);
          final chunk = await raf.read(toRead);
          if (chunk.isEmpty) break;

          request.add(chunk);
          await request.flush();
          sentBytes += chunk.length;
          // Scale Phase 1 (server upload) to 0-50%
          item.bytesTransferred = (sentBytes * 0.50).round();
          item.errorMessage = 'Phase 1: Wird an Server-Relay übertragen...';

          final now = DateTime.now();
          final ms = now.difference(lastTime).inMilliseconds;
          if (ms >= 300) {
            final bytesDiff = sentBytes - lastCheckBytes;
            final currentSpeed = (bytesDiff / (ms / 1000.0));
            item.speedBytesPerSecond = item.speedBytesPerSecond == 0
                ? currentSpeed
                : (item.speedBytesPerSecond * 0.4 + currentSpeed * 0.6);
            lastCheckBytes = sentBytes;
            lastTime = now;
            onProgress(item);
          }
        }
      } finally {
        await raf.close();
      }

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      client.close();

      if (response.statusCode == 200) {
        // Stage 1 (Server Upload) done! Stage 2 (Receiver download) begins!
        item.status = TransferStatus.running;
        item.bytesTransferred = (fileSize * 0.50).round();
        item.errorMessage = 'Phase 2: Empfänger lädt Datei herunter...';
        item.speedBytesPerSecond = 0;
        onProgress(item);

        // Notify target device that upload is complete on server relay
        if (vpnTunnel != null && vpnTunnel.isConnected) {
          vpnTunnel.sendThroughTunnel({
            'type': 'relay_ready',
            'task_id': taskId,
            'target_device_id': targetDeviceId,
            'sender_device_id': senderDeviceId,
          });
        }
      } else {
        item.status = TransferStatus.failed;
        item.errorMessage = 'Relay-Upload fehlgeschlagen (HTTP ${response.statusCode}): $responseBody';
        onProgress(item);
      }
    } catch (e) {
      client.close();
      item.status = TransferStatus.failed;
      item.errorMessage = 'Relay-Verbindungsfehler: $e';
      onProgress(item);
    }
  }
}
