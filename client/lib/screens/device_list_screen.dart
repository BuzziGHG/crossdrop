import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/device.dart';
import '../services/app_state.dart';
import 'send_file_screen.dart';

class DeviceListScreen extends StatelessWidget {
  const DeviceListScreen({super.key});

  IconData _getPlatformIcon(String platform) {
    switch (platform.toLowerCase()) {
      case 'windows':
        return Icons.desktop_windows_outlined;
      case 'linux':
        return Icons.laptop_chromebook_outlined;
      case 'android':
        return Icons.phone_android_outlined;
      default:
        return Icons.devices_outlined;
    }
  }

  Future<void> _pickAndSendFile(BuildContext context, DeviceModel device) async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: false);
    if (result != null && result.files.isNotEmpty && result.files.first.path != null) {
      final file = File(result.files.first.path!);
      if (!context.mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SendFileScreen(
            preselectedFile: file,
            preselectedDevice: device,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meine Geräte'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Geräte aktualisieren',
            onPressed: () => state.refreshDevices(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await state.refreshNetwork();
          await state.refreshDevices();
        },
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            // 1. Current Device Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              color: theme.colorScheme.surfaceVariant.withOpacity(0.4),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            _getPlatformIcon(state.storage.deviceId),
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    state.deviceName,
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.green),
                                    ),
                                    child: const Text(
                                      'Dieses Gerät',
                                      style: TextStyle(
                                        color: Colors.green,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Empfangs-Port: ${state.server.port}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Chip(
                          avatar: const Icon(Icons.wifi, size: 16),
                          label: Text(
                            state.myLocalIps.isNotEmpty
                                ? 'LAN: ${state.myLocalIps.join(", ")}'
                                : 'LAN: Nicht verbunden',
                          ),
                        ),
                        Chip(
                          avatar: const Icon(Icons.vpn_lock, size: 16),
                          label: Text(
                            state.myVpnIps.isNotEmpty
                                ? 'VPN: ${state.myVpnIps.join(", ")}'
                                : 'VPN: Inaktiv',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 2. Section Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Verfügbare Zielgeräte (${state.devices.length})',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.send, size: 18),
                  label: const Text('Datei senden'),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SendFileScreen()),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),

            // 3. Devices List
            if (state.devices.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40.0),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.devices_other_outlined, size: 64, color: theme.colorScheme.outline),
                      const SizedBox(height: 12),
                      Text(
                        'Keine anderen Geräte im Konto gefunden',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Installieren Sie CrossDrop auf Ihrem Windows-PC, Linux-Server\noder Android-Handy und melden Sie sich mit demselben Account an.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              )
            else
              ...state.devices.map((device) {
                final isOnline = device.isOnline;
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Device Header (Name, Platform, Online-Dot)
                        Row(
                          children: [
                            Icon(
                              _getPlatformIcon(device.platform),
                              size: 28,
                              color: isOnline ? theme.colorScheme.primary : Colors.grey,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    device.name,
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    device.platform.toUpperCase(),
                                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: isOnline
                                    ? Colors.green.withOpacity(0.15)
                                    : Colors.grey.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircleAvatar(
                                    radius: 4,
                                    backgroundColor: isOnline ? Colors.green : Colors.grey,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    isOnline ? 'Online' : 'Offline',
                                    style: TextStyle(
                                      color: isOnline ? Colors.green : Colors.grey,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Connection Mode Selector: LAN vs VPN
                        Text(
                          'Verbindungs-Modus:',
                          style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: ChoiceChip(
                                label: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.wifi, size: 16),
                                    const SizedBox(width: 6),
                                    Text(
                                      device.localIps.isNotEmpty
                                          ? 'LAN (${device.localIps.first})'
                                          : 'LAN (Keine IP)',
                                    ),
                                  ],
                                ),
                                selected: device.preferredMode == ConnectionMode.lan,
                                onSelected: device.localIps.isNotEmpty
                                    ? (_) => state.setDeviceConnectionMode(device, ConnectionMode.lan)
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ChoiceChip(
                                label: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.vpn_lock, size: 16),
                                    const SizedBox(width: 6),
                                    Text(
                                      device.vpnIps.isNotEmpty
                                          ? 'VPN (${device.vpnIps.first})'
                                          : 'VPN (Keine IP)',
                                    ),
                                  ],
                                ),
                                selected: device.preferredMode == ConnectionMode.vpn,
                                onSelected: device.vpnIps.isNotEmpty
                                    ? (_) => state.setDeviceConnectionMode(device, ConnectionMode.vpn)
                                    : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Send Button
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            icon: const Icon(Icons.upload_file),
                            label: const Text('Datei an dieses Gerät senden'),
                            onPressed: isOnline ? () => _pickAndSendFile(context, device) : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
