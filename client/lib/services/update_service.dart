import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../config/constants.dart';

class UpdateInfo {
  final bool hasUpdate;
  final String currentVersion;
  final String latestVersion;
  final String releaseNotes;
  final String downloadUrl;
  final String fileName;
  final int fileSize;

  UpdateInfo({
    required this.hasUpdate,
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.fileName,
    required this.fileSize,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      hasUpdate: json['has_update'] == true,
      currentVersion: json['current_version']?.toString() ?? AppConstants.appVersion,
      latestVersion: json['latest_version']?.toString() ?? AppConstants.appVersion,
      releaseNotes: json['release_notes']?.toString() ?? 'Neue Version verfügbar.',
      downloadUrl: json['download_url']?.toString() ?? '',
      fileName: json['file_name']?.toString() ?? 'update.bin',
      fileSize: (json['file_size'] as num?)?.toInt() ?? 0,
    );
  }
}

class UpdateService {
  final String serverUrl;
  static const MethodChannel _installerChannel = MethodChannel('com.crossdrop.app/installer');

  UpdateService({required this.serverUrl});

  String get currentPlatform {
    if (Platform.isAndroid) return 'android';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final platform = currentPlatform;
      final uri = Uri.parse('$serverUrl/api/updates/check').replace(
        queryParameters: {
          'platform': platform,
          'current_version': AppConstants.appVersion,
        },
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        return UpdateInfo.fromJson(data);
      }
    } catch (e) {
      debugPrint('Update-Check fehlgeschlagen: $e');
    }
    return null;
  }

  Future<bool> canInstallUnknownApps() async {
    if (!Platform.isAndroid) return true;
    try {
      final res = await _installerChannel.invokeMethod<bool>('canInstallUnknownApps');
      return res ?? false;
    } catch (_) {
      return true;
    }
  }

  Future<void> openInstallPermissionSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _installerChannel.invokeMethod('openInstallPermissionSettings');
    } catch (_) {}
  }

  HttpClient? _activeClient;
  bool _isCancelled = false;

  void cancelDownload() {
    _isCancelled = true;
    try {
      _activeClient?.close(force: true);
    } catch (_) {}
    _activeClient = null;
  }

  Future<void> downloadAndInstall({
    required UpdateInfo updateInfo,
    required Function(double progress) onProgress,
    required Function(String filePath) onDownloaded,
    required Function(String error) onError,
  }) async {
    _isCancelled = false;
    try {
      String fullDownloadUrl = updateInfo.downloadUrl;
      if (!fullDownloadUrl.startsWith('http')) {
        fullDownloadUrl = '$serverUrl$fullDownloadUrl';
      }

      final uri = Uri.parse(fullDownloadUrl);
      final client = HttpClient()
        ..badCertificateCallback = ((cert, host, port) => true)
        ..connectionTimeout = const Duration(seconds: 15);
      _activeClient = client;

      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.connectionHeader, 'close');
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final response = await request.close();

      if (response.statusCode != 200) {
        client.close(force: true);
        _activeClient = null;
        onError('Download-Server antwortete mit Status ${response.statusCode}');
        return;
      }

      final totalBytes = response.contentLength > 0 ? response.contentLength : updateInfo.fileSize;
      int receivedBytes = 0;

      String targetDir;
      if (Platform.isAndroid) {
        final ext = await getExternalStorageDirectory();
        targetDir = ext?.path ?? (await getApplicationDocumentsDirectory()).path;
      } else {
        targetDir = (await getTemporaryDirectory()).path;
      }

      final targetFile = File(p.join(targetDir, updateInfo.fileName));
      if (await targetFile.exists()) {
        try {
          await targetFile.delete();
        } catch (_) {}
      }

      final sink = targetFile.openWrite();

      try {
        await for (final chunk in response.timeout(const Duration(seconds: 30))) {
          if (_isCancelled) break;
          sink.add(chunk);
          receivedBytes += chunk.length;
          if (totalBytes > 0) {
            final raw = receivedBytes / totalBytes;
            onProgress(raw.clamp(0.0, 0.98));
          }
          if (totalBytes > 0 && receivedBytes >= totalBytes) {
            // All bytes received
            break;
          }
        }
      } finally {
        await sink.flush();
        await sink.close();
        client.close(force: true);
        _activeClient = null;
      }

      if (_isCancelled) {
        onError('Download wurde abgebrochen.');
        return;
      }

      if (totalBytes > 0 && receivedBytes < totalBytes) {
        onError('Download unvollständig ($receivedBytes von $totalBytes Bytes übertragen).');
        return;
      }

      // Best effort copy to public downloads on Android
      if (Platform.isAndroid) {
        try {
          final pubDir = Directory('/storage/emulated/0/Download');
          if (await pubDir.exists()) {
            final pubFile = File(p.join(pubDir.path, updateInfo.fileName));
            await targetFile.copy(pubFile.path);
            debugPrint('Copied update APK to public Download folder: ${pubFile.path}');
          }
        } catch (e) {
          debugPrint('Notice: could not copy to public Download folder: $e');
        }
      }

      onProgress(1.0);
      onDownloaded(targetFile.path);

      // Attempt immediate installer launch
      await installUpdate(targetFile.path);
    } catch (e) {
      if (!_isCancelled) {
        onError('Fehler beim Herunterladen des Updates: $e');
      }
    }
  }

  Future<bool> installUpdate(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('Update-Datei existiert nicht: $filePath');
        return false;
      }

      if (Platform.isAndroid) {
        try {
          final res = await _installerChannel.invokeMethod<bool>('installApk', {'filePath': filePath});
          if (res == true) return true;
          if (res == false) {
            // Permission not yet granted; native code directed user to settings
            return false;
          }
        } catch (e) {
          debugPrint('Native installer channel error: $e');
        }

        final result = await OpenFilex.open(
          filePath,
          type: 'application/vnd.android.package-archive',
        );
        debugPrint('OpenFilex APK install result: ${result.type} - ${result.message}');
        return result.type == ResultType.done;
      } else {
        final result = await OpenFilex.open(filePath);
        return result.type == ResultType.done;
      }
    } catch (e) {
      debugPrint('Fehler bei der Installation: $e');
      return false;
    }
  }
}
