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
          .timeout(const Duration(seconds: 15));

      if (handshakeResponse.statusCode != 200) {
        item.status = TransferStatus.rejected;
        item.errorMessage = 'Anfrage abgelehnt oder Ziel nicht erreichbar';
        onProgress(item);
        return;
      }

      // 2. Open Stream Upload to Target Device
      item.status = TransferStatus.running;
      onProgress(item);

      final uploadUri = Uri.parse('http://$targetIp:$targetPort/api/transfer/upload/$taskId');
      final request = http.StreamedRequest('POST', uploadUri);
      request.headers['Content-Type'] = 'application/octet-stream';
      request.contentLength = fileSize;

      final fileStream = file.openRead();
      int sentBytes = 0;
      int lastCheckBytes = 0;
      DateTime lastTime = DateTime.now();

      final pipeFuture = () async {
        await for (final chunk in fileStream) {
          request.sink.add(chunk);
          sentBytes += chunk.length;
          item.bytesTransferred = sentBytes;

          final now = DateTime.now();
          final ms = now.difference(lastTime).inMilliseconds;
          if (ms >= 500) {
            final bytesDiff = sentBytes - lastCheckBytes;
            item.speedBytesPerSecond = (bytesDiff / (ms / 1000.0));
            lastCheckBytes = sentBytes;
            lastTime = now;
            onProgress(item);
          }
        }
        await request.sink.close();
      }();

      final responseFuture = request.send();
      await Future.wait([pipeFuture, responseFuture]);

      final streamedResponse = await responseFuture;
      final responseBody = await streamedResponse.stream.bytesToString();

      if (streamedResponse.statusCode == 200) {
        item.status = TransferStatus.completed;
        item.bytesTransferred = fileSize;
        item.speedBytesPerSecond = 0;
        onProgress(item);
      } else {
        item.status = TransferStatus.failed;
        item.errorMessage = 'Fehler beim Übertragen: $responseBody';
        onProgress(item);
      }
    } catch (e) {
      item.status = TransferStatus.failed;
      item.errorMessage = 'Verbindungsfehler: $e';
      onProgress(item);
    }
  }
}
