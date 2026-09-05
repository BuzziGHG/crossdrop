enum ConnectionMode { lan, vpn }

class DeviceModel {
  final String id;
  final String name;
  final String platform; // 'windows', 'linux', 'android'
  final List<String> localIps;
  final List<String> vpnIps;
  final int transferPort;
  final bool isOnline;
  final DateTime lastSeen;
  ConnectionMode preferredMode;

  DeviceModel({
    required this.id,
    required this.name,
    required this.platform,
    required this.localIps,
    required this.vpnIps,
    required this.transferPort,
    required this.isOnline,
    required this.lastSeen,
    this.preferredMode = ConnectionMode.lan,
  });

  factory DeviceModel.fromJson(Map<String, dynamic> json) {
    List<String> parseList(dynamic val) {
      if (val is List) {
        return val.map((e) => e.toString()).toList();
      }
      return [];
    }

    return DeviceModel(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Unbekanntes Gerät',
      platform: (json['platform'] ?? 'unknown').toString().toLowerCase(),
      localIps: parseList(json['local_ips']),
      vpnIps: parseList(json['vpn_ips']),
      transferPort: json['transfer_port'] ?? 52520,
      isOnline: json['is_online'] ?? false,
      lastSeen: json['last_seen'] != null
          ? DateTime.tryParse(json['last_seen']) ?? DateTime.now()
          : DateTime.now(),
      preferredMode: ConnectionMode.lan,
    );
  }

  String? get activeIp {
    if (preferredMode == ConnectionMode.vpn && vpnIps.isNotEmpty) {
      return vpnIps.first;
    }
    if (localIps.isNotEmpty) {
      return localIps.first;
    }
    return vpnIps.isNotEmpty ? vpnIps.first : null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeviceModel && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
