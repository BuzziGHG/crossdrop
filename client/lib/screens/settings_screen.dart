import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _pickDownloadDirectory(BuildContext context, AppState state) async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path != null) {
      await state.storage.setDownloadPath(path);
      state.notifyListeners();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Einstellungen'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. Account Info Section
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Benutzerkonto',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(state.currentUser?.username ?? 'Nicht angemeldet'),
                    subtitle: Text(state.currentUser?.email ?? ''),
                    trailing: OutlinedButton(
                      onPressed: () => state.logout(),
                      child: const Text('Abmelden'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 2. Transfer Preferences
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Übertragungs-Einstellungen',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Dateien automatisch annehmen'),
                    subtitle: const Text('Empfängt Dateien von eigenen Geräten im selben Konto ohne Nachfrage'),
                    value: state.storage.autoAccept,
                    onChanged: (val) async {
                      await state.storage.setAutoAccept(val);
                      state.notifyListeners();
                    },
                  ),
                  const Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Download-Ordner'),
                    subtitle: Text(
                      state.storage.downloadPath != null && state.storage.downloadPath!.isNotEmpty
                          ? state.storage.downloadPath!
                          : 'Standard-Download-Ordner des Systems',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.folder_open),
                      onPressed: () => _pickDownloadDirectory(context, state),
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Lokaler Transfer-Port'),
                    subtitle: Text('${state.server.port} (TCP)'),
                  ),
                  const Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Server-URL'),
                    subtitle: Text(state.storage.serverUrl),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 3. About Section
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Über CrossDrop',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'CrossDrop ermöglicht extrem schnelle, direkte Peer-to-Peer-Dateiübertragungen über Ihr lokales Netzwerk (WLAN/LAN) oder verschlüsselt über Ihr persönliches VPN (WireGuard, Tailscale).',
                  ),
                  const SizedBox(height: 8),
                  const Text('Version 1.0.0 • Multi-Platform (Windows, Linux, Android)'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
