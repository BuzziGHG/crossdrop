enum TransferStatus { pending, connecting, running, completed, failed, rejected, cancelled }
enum TransferDirection { send, receive }

class TransferItem {
  final String id;
  final String filename;
  final String? localFilePath;
  int totalBytes;
  int bytesTransferred;
  double speedBytesPerSecond;
  TransferStatus status;
  final TransferDirection direction;
  final String peerDeviceName;
  final String? peerDeviceId;
  String peerIp;
  final int peerPort;
  final String? checksumSha256;
  String mode; // 'LAN' or 'VPN' or 'Relay'
  final String? senderEmail;
  final bool isCrossAccount;
  String? errorMessage;
  final DateTime createdAt;

  TransferItem({
    required this.id,
    required this.filename,
    this.localFilePath,
    required this.totalBytes,
    this.bytesTransferred = 0,
    this.speedBytesPerSecond = 0,
    this.status = TransferStatus.pending,
    required this.direction,
    required this.peerDeviceName,
    this.peerDeviceId,
    required this.peerIp,
    required this.peerPort,
    this.checksumSha256,
    this.mode = 'LAN',
    this.senderEmail,
    this.isCrossAccount = false,
    this.errorMessage,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  double get progress {
    if (totalBytes <= 0) return 0.0;
    return (bytesTransferred / totalBytes).clamp(0.0, 1.0);
  }

  String get formattedSize {
    return formatBytes(totalBytes);
  }

  String get formattedTransferred {
    return formatBytes(bytesTransferred);
  }

  String get formattedSpeed {
    if (speedBytesPerSecond <= 0) return '0 KB/s';
    return '${formatBytes(speedBytesPerSecond.round())}/s';
  }

  String get formattedEta {
    if (status != TransferStatus.running || speedBytesPerSecond <= 100 || totalBytes <= 0) {
      return '';
    }
    final remainingBytes = totalBytes - bytesTransferred;
    if (remainingBytes <= 0) return 'Fertig';
    final secondsRemaining = (remainingBytes / speedBytesPerSecond).ceil();
    if (secondsRemaining <= 1) {
      return 'noch 1 Sek.';
    } else if (secondsRemaining < 60) {
      return 'noch ${secondsRemaining}s';
    } else if (secondsRemaining < 3600) {
      final minutes = secondsRemaining ~/ 60;
      final sec = secondsRemaining % 60;
      return 'noch ${minutes}m ${sec}s';
    } else {
      final hours = secondsRemaining ~/ 3600;
      final minutes = (secondsRemaining % 3600) ~/ 60;
      return 'noch ${hours}h ${minutes}m';
    }
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
