import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/transfer_item.dart';
import 'storage_service.dart';

typedef TransferRequestCallback = Future<bool> Function(TransferItem item);
typedef TransferProgressCallback = void Function(TransferItem item);

class TransferServer {
  final StorageService _storage;
  HttpServer? _server;
  TransferRequestCallback? onRequest;
  TransferProgressCallback? onProgress;

  final Map<String, TransferItem> _activeTransfers = {};

  TransferServer(this._storage);

  bool get isRunning => _server != null;
  int get port => _server?.port ?? _storage.transferPort;

  Future<void> start({
    TransferRequestCallback? onRequest,
    TransferProgressCallback? onProgress,
  }) async {
    this.onRequest = onRequest;
    this.onProgress = onProgress;

    if (_server != null) return;

    try {
      _server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        _storage.transferPort,
        shared: true,
      );
      _server!.listen(_handleRequest);
    } catch (e) {
      try {
        _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
        _storage.setTransferPort(_server!.port);
        _server!.listen(_handleRequest);
      } catch (_) {}
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    request.response.headers.add('Access-Control-Allow-Headers', '*');

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    final path = request.uri.path;

    if (request.method == 'POST' && path == '/api/transfer/request') {
      await _handleHandshake(request);
    } else if (request.method == 'POST' && path.startsWith('/api/transfer/upload/')) {
      final taskId = path.substring('/api/transfer/upload/'.length);
      await _handleUploadStream(request, taskId);
    } else if (request.method == 'GET' && path == '/api/ping') {
      request.response.statusCode = HttpStatus.ok;
      request.response.write(jsonEncode({'status': 'online'}));
      await request.response.close();
    } else {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    }
  }

  Future<void> _handleHandshake(HttpRequest request) async {
    try {
      final content = await utf8.decoder.bind(request).join();
      final data = jsonDecode(content);

      final taskId = data['task_id'] ?? '';
      final filename = data['filename'] ?? 'unbenannte_datei';
      final fileSize = data['size'] ?? 0;
      final senderName = data['sender_name'] ?? 'Unbekanntes Gerät';
      final checksum = data['checksum'];
      final mode = data['mode'] ?? 'LAN';

      final item = TransferItem(
        id: taskId,
        filename: filename,
        totalBytes: fileSize,
        direction: TransferDirection.receive,
        peerDeviceName: senderName,
        peerIp: request.connectionInfo?.remoteAddress.address ?? 'Unbekannt',
        peerPort: request.connectionInfo?.remotePort ?? 0,
        checksumSha256: checksum,
        mode: mode,
        status: TransferStatus.pending,
      );

      _activeTransfers[taskId] = item;

      bool accept = _storage.autoAccept;
      if (!accept && onRequest != null) {
        accept = await onRequest!(item);
      }

      if (accept) {
        item.status = TransferStatus.running;
        request.response.statusCode = HttpStatus.ok;
        request.response.write(jsonEncode({'accepted': true, 'task_id': taskId}));
      } else {
        item.status = TransferStatus.rejected;
        _activeTransfers.remove(taskId);
        request.response.statusCode = HttpStatus.forbidden;
        request.response.write(jsonEncode({'accepted': false, 'reason': 'Vom Benutzer abgelehnt'}));
      }
    } catch (e) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.write(jsonEncode({'error': e.toString()}));
    } finally {
      await request.response.close();
    }
  }

  Future<void> _handleUploadStream(HttpRequest request, String taskId) async {
    final item = _activeTransfers[taskId];
    if (item == null) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write(jsonEncode({'error': 'Transfer-Sitzung nicht gefunden'}));
      await request.response.close();
      return;
    }

    String downloadDir = _storage.downloadPath ?? '';
    if (downloadDir.isEmpty) {
      final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      downloadDir = dir.path;
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
    final sink = targetFile.openWrite();

    int receivedBytes = 0;
    int lastCheckBytes = 0;
    DateTime lastTime = DateTime.now();

    try {
      await for (final chunk in request) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        item.bytesTransferred = receivedBytes;

        final now = DateTime.now();
        final ms = now.difference(lastTime).inMilliseconds;
        if (ms >= 500) {
          final bytesDiff = receivedBytes - lastCheckBytes;
          item.speedBytesPerSecond = (bytesDiff / (ms / 1000.0));
          lastCheckBytes = receivedBytes;
          lastTime = now;
          onProgress?.call(item);
        }
      }

      await sink.flush();
      await sink.close();

      // Verify SHA-256 if provided
      if (item.checksumSha256 != null && item.checksumSha256!.isNotEmpty) {
        final digest = await sha256.bind(targetFile.openRead()).first;
        final calculatedHash = digest.toString();
        if (calculatedHash != item.checksumSha256) {
          item.status = TransferStatus.failed;
          item.errorMessage = 'Prüfsummen-Fehler (SHA-256 stimmt nicht überein)';
          request.response.statusCode = HttpStatus.expectationFailed;
          request.response.write(jsonEncode({'error': 'Checksum mismatch'}));
          return;
        }
      }

      item.status = TransferStatus.completed;
      item.bytesTransferred = receivedBytes;
      item.speedBytesPerSecond = 0;
      onProgress?.call(item);

      request.response.statusCode = HttpStatus.ok;
      request.response.write(jsonEncode({'status': 'completed', 'path': finalPath}));
    } catch (e) {
      item.status = TransferStatus.failed;
      item.errorMessage = e.toString();
      onProgress?.call(item);
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write(jsonEncode({'error': e.toString()}));
    } finally {
      await request.response.close();
    }
  }
}
