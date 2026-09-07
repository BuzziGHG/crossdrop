import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../models/cloud_account.dart';

class CloudFileItem {
  final String name;
  final String path; // WebDAV path or Google Drive File ID
  final bool isDirectory;
  final int size;
  final DateTime? lastModified;
  final String? mimeType;

  CloudFileItem({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.size,
    this.lastModified,
    this.mimeType,
  });

  String get formattedSize {
    if (isDirectory) return 'Ordner';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  bool get isImage {
    final ext = p.extension(name).toLowerCase();
    return ext == '.jpg' || ext == '.jpeg' || ext == '.png' || ext == '.gif' || ext == '.webp' || ext == '.bmp' || ext == '.svg';
  }

  bool get isText {
    final ext = p.extension(name).toLowerCase();
    return ext == '.txt' || ext == '.log' || ext == '.md' || ext == '.json' || ext == '.xml' || ext == '.csv' || ext == '.yaml' || ext == '.yml' || ext == '.dart' || ext == '.py' || ext == '.sh';
  }

  bool get isPdf => p.extension(name).toLowerCase() == '.pdf';
}

class CloudService {
  static final CloudService _instance = CloudService._internal();
  factory CloudService() => _instance;
  CloudService._internal();

  HttpClient _createHttpClient() {
    return HttpClient()
      ..badCertificateCallback = ((cert, host, port) => true)
      ..connectionTimeout = const Duration(seconds: 15);
  }

  String _buildAuthHeader(CloudAccount account) {
    if (account.type == CloudProviderType.googleDrive) {
      return 'Bearer ${account.accessToken ?? ''}';
    }
    final credentials = '${account.username}:${account.password}';
    return 'Basic ${base64Encode(utf8.encode(credentials))}';
  }

  /// Universal WebDAV URI builder: prevents path duplication and handles relative & absolute hrefs
  Uri _buildUri(CloudAccount account, String path) {
    final baseUri = Uri.parse(account.normalizedWebDavUrl);
    final rawPath = path.trim();

    // 1. If path is already a full URI
    if (rawPath.startsWith('http://') || rawPath.startsWith('https://')) {
      return Uri.parse(rawPath);
    }

    // 2. Base path of the server
    final basePath = baseUri.path.endsWith('/')
        ? baseUri.path.substring(0, baseUri.path.length - 1)
        : baseUri.path;

    String finalPath;
    if (basePath.isNotEmpty && rawPath.startsWith(basePath)) {
      finalPath = rawPath;
    } else {
      final cleanSub = rawPath.startsWith('/') ? rawPath : '/$rawPath';
      finalPath = '$basePath$cleanSub';
    }

    finalPath = finalPath.replaceAll(RegExp(r'/{2,}'), '/');
    return baseUri.replace(path: finalPath);
  }

  // ==========================================
  // Connection Testing
  // ==========================================

  Future<Map<String, dynamic>> testConnection(CloudAccount account) async {
    if (account.type == CloudProviderType.googleDrive) {
      return _testGoogleDriveConnection(account);
    }

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

  Future<Map<String, dynamic>> _testGoogleDriveConnection(CloudAccount account) async {
    if (account.accessToken == null || account.accessToken!.isEmpty) {
      return {
        'success': false,
        'message': 'Kein Google Access Token vorhanden. Bitte mit Google anmelden.',
      };
    }

    final client = _createHttpClient();
    try {
      final uri = Uri.parse('https://www.googleapis.com/drive/v3/about?fields=user,storageQuota');
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${account.accessToken}');

      final response = await request.close().timeout(const Duration(seconds: 12));
      final responseBody = await response.transform(utf8.decoder).join();
      client.close();

      if (response.statusCode == 200) {
        final data = json.decode(responseBody);
        final user = data['user']?['emailAddress'] ?? account.username;
        return {
          'success': true,
          'message': 'Google Drive verbunden als $user!',
        };
      } else if (response.statusCode == 401) {
        return {
          'success': false,
          'message': 'Google Token abgelaufen oder ungültig (401). Bitte Token erneuern.',
        };
      } else {
        return {
          'success': false,
          'message': 'Google Drive API Fehler: HTTP ${response.statusCode}',
        };
      }
    } catch (e) {
      client.close(force: true);
      return {
        'success': false,
        'message': 'Google Verbindungsfehler: $e',
      };
    }
  }

  // ==========================================
  // File Listing
  // ==========================================

  Future<List<CloudFileItem>> listFiles(CloudAccount account, {String remotePath = '/'}) async {
    if (account.type == CloudProviderType.googleDrive) {
      return _listGoogleDriveFiles(account, folderId: remotePath == '/' ? 'root' : remotePath);
    }

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

  Future<List<CloudFileItem>> _listGoogleDriveFiles(CloudAccount account, {String folderId = 'root'}) async {
    final client = _createHttpClient();
    try {
      final safeFolder = folderId.replaceAll("'", "\\'");
      final query = Uri.encodeComponent("'$safeFolder' in parents and trashed = false");
      final uri = Uri.parse(
          'https://www.googleapis.com/drive/v3/files?q=$query&fields=files(id,name,mimeType,size,modifiedTime)&pageSize=1000&orderBy=folder,name');

      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${account.accessToken}');

      final response = await request.close().timeout(const Duration(seconds: 15));
      final responseBody = await response.transform(utf8.decoder).join();
      client.close();

      if (response.statusCode != 200) {
        throw Exception('Google Drive Fehler (HTTP ${response.statusCode}): $responseBody');
      }

      final data = json.decode(responseBody);
      final rawFiles = (data['files'] as List<dynamic>?) ?? [];

      final items = <CloudFileItem>[];
      for (final f in rawFiles) {
        final mimeType = f['mimeType'] as String? ?? '';
        final isDir = mimeType == 'application/vnd.google-apps.folder';
        final size = int.tryParse(f['size']?.toString() ?? '0') ?? 0;
        final modTime = f['modifiedTime'] != null ? DateTime.tryParse(f['modifiedTime']) : null;

        items.add(CloudFileItem(
          name: f['name'] as String? ?? 'Unbekannt',
          path: f['id'] as String? ?? '',
          isDirectory: isDir,
          size: size,
          lastModified: modTime,
          mimeType: mimeType,
        ));
      }

      items.sort((a, b) {
        if (a.isDirectory && !b.isDirectory) return -1;
        if (!a.isDirectory && b.isDirectory) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      return items;
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

      // Skip root folder entry itself
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

    items.sort((a, b) {
      if (a.isDirectory && !b.isDirectory) return -1;
      if (!a.isDirectory && b.isDirectory) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return items;
  }

  // ==========================================
  // Fetch Bytes (for instant in-app previews)
  // ==========================================

  Future<Uint8List> getFileBytes(CloudAccount account, String remotePath) async {
    final client = _createHttpClient();
    try {
      final Uri uri = account.type == CloudProviderType.googleDrive
          ? Uri.parse('https://www.googleapis.com/drive/v3/files/$remotePath?alt=media')
          : _buildUri(account, remotePath);

      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.authorizationHeader, _buildAuthHeader(account));

      final response = await request.close().timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        client.close(force: true);
        throw Exception('Vorschau fehlgeschlagen (HTTP ${response.statusCode})');
      }

      final bytesBuilder = BytesBuilder();
      await for (final chunk in response) {
        bytesBuilder.add(chunk);
      }
      client.close();
      return bytesBuilder.toBytes();
    } catch (e) {
      client.close(force: true);
      rethrow;
    }
  }

  // ==========================================
  // File Download
  // ==========================================

  Future<void> downloadFile({
    required CloudAccount account,
    required String remotePath,
    required String localSavePath,
    Function(double progress, int transferred, int total)? onProgress,
  }) async {
    final client = _createHttpClient();
    try {
      final Uri uri = account.type == CloudProviderType.googleDrive
          ? Uri.parse('https://www.googleapis.com/drive/v3/files/$remotePath?alt=media')
          : _buildUri(account, remotePath);

      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.authorizationHeader, _buildAuthHeader(account));

      final response = await request.close().timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        client.close(force: true);
        throw Exception('Download fehlgeschlagen mit Status HTTP ${response.statusCode}');
      }

      final totalBytes = response.contentLength;
      int receivedBytes = 0;

      final targetFile = File(localSavePath);
      await targetFile.parent.create(recursive: true);
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

  // ==========================================
  // File Upload
  // ==========================================

  Future<void> uploadFile({
    required CloudAccount account,
    required File localFile,
    required String remoteDirectory,
    Function(double progress, int transferred, int total)? onProgress,
  }) async {
    if (account.type == CloudProviderType.googleDrive) {
      return _uploadGoogleDriveFile(account, localFile, remoteDirectory, onProgress);
    }

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

  Future<void> _uploadGoogleDriveFile(
    CloudAccount account,
    File localFile,
    String parentFolderId,
    Function(double progress, int transferred, int total)? onProgress,
  ) async {
    final client = _createHttpClient();
    try {
      final filename = p.basename(localFile.path);
      final folderId = parentFolderId == '/' ? 'root' : parentFolderId;
      final fileSize = await localFile.length();

      final uri = Uri.parse('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart');
      final boundary = '----CrossDropGoogleBoundary${DateTime.now().millisecondsSinceEpoch}';

      final request = await client.postUrl(uri);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${account.accessToken}');
      request.headers.set(HttpHeaders.contentTypeHeader, 'multipart/related; boundary=$boundary');

      final metadata = json.encode({
        'name': filename,
        'parents': [folderId],
      });

      final metadataHeader = '--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n$metadata\r\n';
      final fileHeader = '--$boundary\r\nContent-Type: application/octet-stream\r\n\r\n';
      final footer = '\r\n--$boundary--\r\n';

      final metaBytes = utf8.encode(metadataHeader);
      final fileHeaderBytes = utf8.encode(fileHeader);
      final footerBytes = utf8.encode(footer);

      final totalPayload = metaBytes.length + fileHeaderBytes.length + fileSize + footerBytes.length;
      request.headers.set(HttpHeaders.contentLengthHeader, totalPayload);

      request.add(metaBytes);
      request.add(fileHeaderBytes);

      int sentBytes = 0;
      await for (final chunk in localFile.openRead()) {
        request.add(chunk);
        sentBytes += chunk.length;
        if (fileSize > 0 && onProgress != null) {
          onProgress(sentBytes / fileSize, sentBytes, fileSize);
        }
      }

      request.add(footerBytes);

      final response = await request.close().timeout(const Duration(minutes: 5));
      client.close();

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Google Drive Upload fehlgeschlagen: HTTP ${response.statusCode}');
      }
    } catch (e) {
      client.close(force: true);
      rethrow;
    }
  }

  // ==========================================
  // Directory & Item Management
  // ==========================================

  Future<bool> createDirectory(CloudAccount account, String remotePath) async {
    final client = _createHttpClient();
    try {
      if (account.type == CloudProviderType.googleDrive) {
        final folderName = p.basename(remotePath);
        final parentId = p.dirname(remotePath) == '.' || p.dirname(remotePath) == '/' ? 'root' : p.dirname(remotePath);
        final uri = Uri.parse('https://www.googleapis.com/drive/v3/files');
        final request = await client.postUrl(uri);
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${account.accessToken}');
        request.headers.set(HttpHeaders.contentTypeHeader, 'application/json; charset=UTF-8');
        request.add(utf8.encode(json.encode({
          'name': folderName,
          'mimeType': 'application/vnd.google-apps.folder',
          'parents': [parentId],
        })));
        final res = await request.close();
        client.close();
        return res.statusCode == 200 || res.statusCode == 201;
      }

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

  Future<bool> deleteItem(CloudAccount account, String remotePath) async {
    final client = _createHttpClient();
    try {
      final Uri uri = account.type == CloudProviderType.googleDrive
          ? Uri.parse('https://www.googleapis.com/drive/v3/files/$remotePath')
          : _buildUri(account, remotePath);

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

  // ==========================================
  // Batch Upload
  // ==========================================

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
