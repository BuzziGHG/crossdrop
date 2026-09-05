enum TransferStatus { pending, connecting, running, completed, failed, rejected }
enum TransferDirection { send, receive }

class TransferItem {
  final String id;
  final String filename;
  final String? localFilePath;
  final int totalBytes;
  int bytesTransferred;
  double speedBytesPerSecond;
  TransferStatus status;
  final TransferDirection direction;
  final String peerDeviceName;
  final String? peerDeviceId;
  final String peerIp;
  final int peerPort;
  final String? checksumSha256;
  final String mode; // 'LAN' or 'VPN' or 'Relay'
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

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
