import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
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

  Future<void> downloadAndInstall({
    required UpdateInfo updateInfo,
    required Function(double progress) onProgress,
    required Function(String filePath) onDownloaded,
    required Function(String error) onError,
  }) async {
    try {
      String fullDownloadUrl = updateInfo.downloadUrl;
      if (!fullDownloadUrl.startsWith('http')) {
        fullDownloadUrl = '$serverUrl$fullDownloadUrl';
      }

      final uri = Uri.parse(fullDownloadUrl);
      final client = http.Client();
      final request = http.Request('GET', uri);
      final streamedResponse = await client.send(request);

      if (streamedResponse.statusCode != 200) {
        onError('Download-Server antwortete mit Status ${streamedResponse.statusCode}');
        return;
      }

      final totalBytes = streamedResponse.contentLength ?? updateInfo.fileSize;
      int receivedBytes = 0;

      String targetDir;
      if (Platform.isAndroid) {
        final dlDir = Directory('/storage/emulated/0/Download');
        if (await dlDir.exists()) {
          targetDir = dlDir.path;
        } else {
          final ext = await getExternalStorageDirectory();
          targetDir = ext?.path ?? (await getTemporaryDirectory()).path;
        }
      } else {
        targetDir = (await getTemporaryDirectory()).path;
      }
      final targetFile = File(p.join(targetDir, updateInfo.fileName));
      final sink = targetFile.openWrite();

      await for (final chunk in streamedResponse.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          onProgress(receivedBytes / totalBytes);
        }
      }

      await sink.flush();
      await sink.close();

      onProgress(1.0);
      onDownloaded(targetFile.path);

      // Trigger automatic installation
      final installed = await installUpdate(targetFile.path);
      if (!installed && Platform.isAndroid) {
        onError('Update gespeichert in "Downloads" (${targetFile.path}). Bitte dort antippen oder "Unbekannte Apps installieren" für CrossDrop erlauben.');
      }
    } catch (e) {
      onError('Fehler beim Herunterladen des Updates: $e');
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
