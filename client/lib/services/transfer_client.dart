import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../models/transfer_item.dart';

typedef TransferClientProgressCallback = void Function(TransferItem item);

class TransferClient {
  // High-performance chunk buffer: 512 KB (maximizes LAN & VPN throughput)
  static const int _chunkSize = 512 * 1024;

  static Future<void> sendFile({
    required File file,
    required String targetIp,
    required int targetPort,
    required String targetDeviceName,
    required String senderDeviceName,
    required String connectionMode,
    required TransferClientProgressCallback onProgress,
  }) async {
    final taskId = const Uuid().v4();
    final filename = p.basename(file.path);
    final fileSize = await file.length();

    final item = TransferItem(
      id: taskId,
      filename: filename,
      localFilePath: file.path,
      totalBytes: fileSize,
      direction: TransferDirection.send,
      peerDeviceName: targetDeviceName,
      peerIp: targetIp,
      peerPort: targetPort,
      mode: connectionMode,
      status: TransferStatus.connecting,
    );

    onProgress(item);

    try {
      // 1. Handshake Request to Target Device
      final handshakeUri = Uri.parse('http://$targetIp:$targetPort/api/transfer/request');
      final handshakeResponse = await http
          .post(
            handshakeUri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'task_id': taskId,
              'filename': filename,
              'size': fileSize,
              'sender_name': senderDeviceName,
              'mode': connectionMode,
            }),
          )
          .timeout(const Duration(seconds: 60));

      if (handshakeResponse.statusCode != 200) {
        item.status = TransferStatus.rejected;
        item.errorMessage = 'Anfrage abgelehnt oder Ziel nicht erreichbar';
        onProgress(item);
        return;
      }

      // 2. High-Speed Direct Stream Upload using Native HttpClient
      item.status = TransferStatus.running;
      onProgress(item);

      final uploadUri = Uri.parse('http://$targetIp:$targetPort/api/transfer/upload/$taskId');

      final client = HttpClient();
      client.idleTimeout = const Duration(seconds: 120);
      client.connectionTimeout = const Duration(seconds: 30);

      final request = await client.postUrl(uploadUri);
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/octet-stream');
      request.contentLength = fileSize;
      request.bufferOutput = false; // direct pipeline streaming to socket without intermediate buffering

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
          sentBytes += chunk.length;
          item.bytesTransferred = sentBytes;

          final now = DateTime.now();
          final ms = now.difference(lastTime).inMilliseconds;
          if (ms >= 300) {
            final bytesDiff = sentBytes - lastCheckBytes;
            final currentSpeed = (bytesDiff / (ms / 1000.0));
            // Rolling average for smooth speed display
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
        item.status = TransferStatus.completed;
        item.bytesTransferred = fileSize;
        item.speedBytesPerSecond = 0;
        onProgress(item);
      } else {
        item.status = TransferStatus.failed;
        item.errorMessage = 'Fehler beim Übertragen (HTTP ${response.statusCode}): $responseBody';
        onProgress(item);
      }
    } on TimeoutException {
      item.status = TransferStatus.failed;
      item.errorMessage =
          'Verbindungs-Timeout: Zielgerät nicht erreichbar oder Transfer nicht angenommen (60 s).\n'
          'Bitte prüfe: Sind beide Geräte im selben WLAN? Ist CrossDrop auf dem Zielgerät geöffnet?';
      onProgress(item);
    } catch (e) {
      item.status = TransferStatus.failed;
      item.errorMessage = 'Verbindungsfehler: $e';
      onProgress(item);
    }
  }
}
