import 'dart:convert';

enum CloudProviderType {
  nextcloud,
  webdav,
  googleDrive,
}

class CloudAccount {
  final String id;
  final String name;
  final CloudProviderType type;
  final String serverUrl; // IP or domain for WebDAV, or 'https://www.googleapis.com' for Google Drive
  final String username; // Username for WebDAV, or Google Account Email
  final String password; // Password/App-Token for WebDAV
  final String remoteBasePath; // e.g. /CrossDrop or / or 'root' for Google Drive
  final bool autoSync;
  final DateTime? lastSyncTime;

  // Google Drive specific fields
  final String? accessToken;
  final String? refreshToken;
  final String? clientId;
  final DateTime? tokenExpiry;

  CloudAccount({
    required this.id,
    required this.name,
    this.type = CloudProviderType.nextcloud,
    required this.serverUrl,
    required this.username,
    required this.password,
    this.remoteBasePath = '/',
    this.autoSync = false,
    this.lastSyncTime,
    this.accessToken,
    this.refreshToken,
    this.clientId,
    this.tokenExpiry,
  });

  /// Normalize server URL into proper WebDAV endpoint for Nextcloud / WebDAV
  String get normalizedWebDavUrl {
    var base = serverUrl.trim();
    if (!base.startsWith('http://') && !base.startsWith('https://')) {
      if (RegExp(r'^\d+\.\d+\.\d+\.\d+').hasMatch(base) || base.contains('localhost')) {
        base = 'http://$base';
      } else {
        base = 'https://$base';
      }
    }
    if (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }

    if (type == CloudProviderType.nextcloud) {
      if (!base.contains('/remote.php/dav/files/')) {
        return '$base/remote.php/dav/files/$username';
      }
    }
    return base;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'serverUrl': serverUrl,
        'username': username,
        'password': password,
        'remoteBasePath': remoteBasePath,
        'autoSync': autoSync,
        'lastSyncTime': lastSyncTime?.toIso8601String(),
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'clientId': clientId,
        'tokenExpiry': tokenExpiry?.toIso8601String(),
      };

  factory CloudAccount.fromJson(Map<String, dynamic> json) {
    return CloudAccount(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Cloud',
      type: CloudProviderType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => CloudProviderType.nextcloud,
      ),
      serverUrl: json['serverUrl'] as String? ?? '',
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
      remoteBasePath: json['remoteBasePath'] as String? ?? '/',
      autoSync: json['autoSync'] as bool? ?? false,
      lastSyncTime: json['lastSyncTime'] != null
          ? DateTime.tryParse(json['lastSyncTime'] as String)
          : null,
      accessToken: json['accessToken'] as String?,
      refreshToken: json['refreshToken'] as String?,
      clientId: json['clientId'] as String?,
      tokenExpiry: json['tokenExpiry'] != null
          ? DateTime.tryParse(json['tokenExpiry'] as String)
          : null,
    );
  }

  CloudAccount copyWith({
    String? name,
    CloudProviderType? type,
    String? serverUrl,
    String? username,
    String? password,
    String? remoteBasePath,
    bool? autoSync,
    DateTime? lastSyncTime,
    String? accessToken,
    String? refreshToken,
    String? clientId,
    DateTime? tokenExpiry,
  }) {
    return CloudAccount(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      remoteBasePath: remoteBasePath ?? this.remoteBasePath,
      autoSync: autoSync ?? this.autoSync,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      clientId: clientId ?? this.clientId,
      tokenExpiry: tokenExpiry ?? this.tokenExpiry,
    );
  }
}
