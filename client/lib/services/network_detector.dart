import 'dart:io';

class NetworkDetector {
  /// Scans all local network interfaces and categorizes them into LAN and VPN IPs.
  static Future<Map<String, List<String>>> detectIpAddresses() async {
    final List<String> localIps = [];
    final List<String> vpnIps = [];

    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      for (var iface in interfaces) {
        final name = iface.name.toLowerCase();
        final isVpnInterface = name.contains('tun') ||
            name.contains('tap') ||
            name.contains('wg') ||
            name.contains('tailscale') ||
            name.contains('utun') ||
            name.contains('ppp') ||
            name.contains('wireguard') ||
            name.contains('openvpn') ||
            name.contains('vpn');

        for (var addr in iface.addresses) {
          final ip = addr.address;
          // Ignore localhost / link-local addresses
          if (ip.startsWith('127.') || ip.startsWith('169.254.')) {
            continue;
          }

          // Tailscale uses 100.64.0.0/10 Carrier-Grade NAT block
          final isTailscaleIp = ip.startsWith('100.');
          // WireGuard common defaults like 10.8.0.x or 10.14.0.x
          final isTypicalVpnIp = isVpnInterface || isTailscaleIp;

          if (isTypicalVpnIp) {
            if (!vpnIps.contains(ip)) vpnIps.add(ip);
          } else {
            if (!localIps.contains(ip)) localIps.add(ip);
          }
        }
      }
    } catch (e) {
      // Fallback
    }

    return {
      'local': localIps,
      'vpn': vpnIps,
    };
  }

  static String getPlatformName() {
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    if (Platform.isAndroid) return 'android';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isIOS) return 'ios';
    return 'unknown';
  }
}
