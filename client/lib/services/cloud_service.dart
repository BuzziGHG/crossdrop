import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../models/cloud_account.dart';

class CloudFileItem {
  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final DateTime? lastModified;

  CloudFileItem({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.size,
    this.lastModified,
  });

  String get formattedSize {
    if (isDirectory) return 'Ordner';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class CloudService {
  static final CloudService _instance = CloudService._internal();
  factory CloudService() => _instance;
  CloudService._internal();

  HttpClient _createHttpClient() {
    return HttpClient()
      ..badCertificateCallback = ((cert, host, port) => true)
      ..connectionTimeout = const Duration(seconds: 12);
  }

  String _buildAuthHeader(CloudAccount account) {
    final credentials = '${account.username}:${account.password}';
    return 'Basic ${base64Encode(utf8.encode(credentials))}';
  }

  Uri _buildUri(CloudAccount account, String path) {
    var base = account.normalizedWebDavUrl;
    var cleanPath = path.trim();
    if (!cleanPath.startsWith('/')) cleanPath = '/$cleanPath';
    return Uri.parse('$base$cleanPath');
  }

  Future<Map<String, dynamic>> testConnection(CloudAccount account) async {
    final client = _createHttpClient();
    try {
      final uri = _buildUri(account, account.remoteBasePath);
      final request = await client.openUrl('PROPFIND', uri);
      request.headers.set(HttpHeaders.authorizationHeader, _buildAuthHeader(account));
      request.headers.set('Depth', '0');
      request.headers.set('Content-Type', 'text/xml; charset=utf-8');

      final response = await request.close().timeout(const Duration(seconds: 12));
      client.close();

      if (response.statusCode == 200 || response.statusCode == 207) {
        return {
          'success': true,
          'message': 'Verbindung erfolgreich hergestellt! (HTTP ${response.statusCode})',
        };
      } else if (response.statusCode == 401) {
        return {
          'success': false,
          'message': 'Authentifizierung fehlgeschlagen (401 Unauthorized). Bitte Benutzername und Passwort/App-Token prüfen.',
        };
      } else if (response.statusCode == 404) {
        return {
          'success': false,
          'message': 'Pfad nicht gefunden (404 Not Found). Bitte Server-Adresse und Zielordner prüfen.',
        };
      } else {
        return {
          'success': false,
          'message': 'Server antwortete mit Fehlercode HTTP ${response.statusCode}',
        };
      }
    } catch (e) {
      client.close(force: true);
      return {
        'success': false,
        'message': 'Verbindungsfehler: $e',
      };
    }
  }

  Future<List<CloudFileItem>> listFiles(CloudAccount account, {String remotePath = '/'}) async {
    final client = _createHttpClient();
    try {
      final uri = _buildUri(account, remotePath);
      final request = await client.openUrl('PROPFIND', uri);
      request.headers.set(HttpHeaders.authorizationHeader, _buildAuthHeader(account));
      request.headers.set('Depth', '1');
      request.headers.set('Content-Type', 'text/xml; charset=utf-8');

      final response = await request.close().timeout(const Duration(seconds: 15));
      final responseBody = await response.transform(utf8.decoder).join();
      client.close();

      if (response.statusCode != 200 && response.statusCode != 207) {
        throw Exception('Fehler beim Abrufen der Dateiliste (HTTP ${response.statusCode})');
      }

      return _parseWebDavXml(responseBody, remotePath);
    } catch (e) {
      client.close(force: true);
      rethrow;
    }
  }

  List<CloudFileItem> _parseWebDavXml(String xml, String requestedPath) {
    final items = <CloudFileItem>[];
    final responseRegex = RegExp(r'<(?:\w+:)?response[\s>](.*?)</(?:\w+:)?response>', dotAll: true);
    final hrefRegex = RegExp(r'<(?:\w+:)?href>(.*?)</(?:\w+:)?href>', dotAll: true);
    final isCollectionRegex = RegExp(r'<(?:\w+:)?collection\s*/>');
    final contentLengthRegex = RegExp(r'<(?:\w+:)?getcontentlength>(\d+)</(?:\w+:)?getcontentlength>');
    final lastModifiedRegex = RegExp(r'<(?:\w+:)?getlastmodified>(.*?)</(?:\w+:)?getlastmodified>');
    final displayNameRegex = RegExp(r'<(?:\w+:)?displayname>(.*?)</(?:\w+:)?displayname>');

    final matches = responseRegex.allMatches(xml);
    for (final match in matches) {
      final block = match.group(1) ?? '';
      final hrefMatch = hrefRegex.firstMatch(block);
      if (hrefMatch == null) continue;

      var href = Uri.decodeFull(hrefMatch.group(1) ?? '').trim();
      if (href.endsWith('/')) {
        href = href.substring(0, href.length - 1);
      }

      final isDir = isCollectionRegex.hasMatch(block);
      var displayName = displayNameRegex.firstMatch(block)?.group(1)?.trim();
      if (displayName == null || displayName.isEmpty) {
        displayName = p.basename(href);
      }

      // Skip the root folder entry itself
      final cleanReq = requestedPath.endsWith('/') && requestedPath.length > 1
          ? requestedPath.substring(0, requestedPath.length - 1)
          : requestedPath;
      if (href.endsWith(cleanReq) || href == cleanReq || displayName.isEmpty) {
        continue;
      }

      int size = 0;
      final sizeMatch = contentLengthRegex.firstMatch(block);
      if (sizeMatch != null) {
        size = int.tryParse(sizeMatch.group(1) ?? '0') ?? 0;
      }

      DateTime? lastMod;
      final modMatch = lastModifiedRegex.firstMatch(block);
      if (modMatch != null) {
        lastMod = DateTime.tryParse(modMatch.group(1) ?? '');
      }

      items.add(CloudFileItem(
        name: displayName,
        path: href,
        isDirectory: isDir,
        size: size,
        lastModified: lastMod,
      ));
    }

    // Sort: directories first, then alphabetically
    items.sort((a, b) {
      if (a.isDirectory && !b.isDirectory) return -1;
      if (!a.isDirectory && b.isDirectory) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return items;
  }

  Future<bool> createDirectory(CloudAccount account, String remotePath) async {
    final client = _createHttpClient();
    try {
      final uri = _buildUri(account, remotePath);
      final request = await client.openUrl('MKCOL', uri);
      request.headers.set(HttpHeaders.authorizationHeader, _buildAuthHeader(account));

      final response = await request.close().timeout(const Duration(seconds: 10));
      client.close();
      return response.statusCode == 201 || response.statusCode == 200;
    } catch (_) {
      client.close(force: true);
      return false;
    }
  }

  Future<void> uploadFile({
    required CloudAccount account,
    required File localFile,
    required String remoteDirectory,
    Function(double progress, int transferred, int total)? onProgress,
  }) async {
    final client = _createHttpClient();
    try {
      final filename = p.basename(localFile.path);
      var dir = remoteDirectory.trim();
      if (!dir.startsWith('/')) dir = '/$dir';
      if (!dir.endsWith('/')) dir = '$dir/';
      final targetPath = '$dir$filename';

      final uri = _buildUri(account, targetPath);
      final fileSize = await localFile.length();

      final request = await client.openUrl('PUT', uri);
      request.headers.set(HttpHeaders.authorizationHeader, _buildAuthHeader(account));
      request.headers.set(HttpHeaders.contentLengthHeader, fileSize);
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/octet-stream');

      final fileStream = localFile.openRead();
      int sentBytes = 0;

      await for (final chunk in fileStream) {
        request.add(chunk);
        sentBytes += chunk.length;
        if (fileSize > 0 && onProgress != null) {
          onProgress(sentBytes / fileSize, sentBytes, fileSize);
        }
      }

      final response = await request.close().timeout(const Duration(minutes: 5));
      client.close();

      if (response.statusCode != 200 && response.statusCode != 201 && response.statusCode != 204) {
        throw Exception('Upload fehlgeschlagen mit Status HTTP ${response.statusCode}');
      }
    } catch (e) {
      client.close(force: true);
      rethrow;
    }
  }

  Future<void> downloadFile({
    required CloudAccount account,
    required String remotePath,
    required String localSavePath,
    Function(double progress, int transferred, int total)? onProgress,
  }) async {
    final client = _createHttpClient();
    try {
      final uri = _buildUri(account, remotePath);
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.authorizationHeader, _buildAuthHeader(account));

      final response = await request.close().timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        client.close(force: true);
        throw Exception('Download fehlgeschlagen mit Status HTTP ${response.statusCode}');
      }

      final totalBytes = response.contentLength;
      int receivedBytes = 0;

      final targetFile = File(localSavePath);
      final sink = targetFile.openWrite();

      try {
        await for (final chunk in response) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          if (totalBytes > 0 && onProgress != null) {
            onProgress(receivedBytes / totalBytes, receivedBytes, totalBytes);
          }
        }
      } finally {
        await sink.flush();
        await sink.close();
        client.close();
      }
    } catch (e) {
      client.close(force: true);
      rethrow;
    }
  }

  Future<bool> deleteItem(CloudAccount account, String remotePath) async {
    final client = _createHttpClient();
    try {
      final uri = _buildUri(account, remotePath);
      final request = await client.openUrl('DELETE', uri);
      request.headers.set(HttpHeaders.authorizationHeader, _buildAuthHeader(account));

      final response = await request.close().timeout(const Duration(seconds: 10));
      client.close();
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (_) {
      client.close(force: true);
      return false;
    }
  }

  /// Upload batch of multiple files (up to 5000) sequentially with aggregate progress reporting
  Future<void> uploadBatch({
    required CloudAccount account,
    required List<File> files,
    required String remoteDirectory,
    required Function(int currentFileIndex, int totalFiles, String currentFileName, double totalProgress, String speed) onProgress,
    bool Function()? isCancelled,
  }) async {
    if (files.isEmpty) return;

    int totalBytes = 0;
    for (final f in files) {
      try {
        totalBytes += await f.length();
      } catch (_) {}
    }

    int overallTransferredBytes = 0;
    final startTime = DateTime.now();

    for (int i = 0; i < files.length; i++) {
      if (isCancelled != null && isCancelled()) break;

      final file = files[i];
      final filename = p.basename(file.path);
      final fileSize = await file.length();

      await uploadFile(
        account: account,
        localFile: file,
        remoteDirectory: remoteDirectory,
        onProgress: (fileProg, fileTransferred, _) {
          final currentOverall = overallTransferredBytes + fileTransferred;
          final elapsed = DateTime.now().difference(startTime).inMilliseconds / 1000.0;
          final speedBytesPerSec = elapsed > 0 ? (currentOverall / elapsed) : 0.0;
          final speedStr = speedBytesPerSec > 1024 * 1024
              ? '${(speedBytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s'
              : '${(speedBytesPerSec / 1024).toStringAsFixed(0)} KB/s';

          final totalProg = totalBytes > 0 ? (currentOverall / totalBytes) : (i / files.length);
          onProgress(i + 1, files.length, filename, totalProg.clamp(0.0, 1.0), speedStr);
        },
      );

      overallTransferredBytes += fileSize;
    }
  }
}
