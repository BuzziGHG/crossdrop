import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/constants.dart';
import '../services/app_state.dart';
import '../services/update_service.dart';

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

          // 3. App Updates Section
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'App-Aktualisierungen',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'CrossDrop aktualisiert sich automatisch direkt über Ihren eigenen Server, ohne dass neue APKs manuell von GitHub geladen werden müssen.',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Installierte Version', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          Text('v${AppConstants.appVersion}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.refresh),
                        label: const Text('Nach Updates suchen'),
                        onPressed: () => _checkUpdate(context, state),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 4. About Section
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
                    'CrossDrop ermöglicht extrem schnelle, direkte Peer-to-Peer-Dateiübertragungen über Ihr lokales Netzwerk (WLAN/LAN) oder verschlüsselt über Ihren Zero-Config VPN-Tunnel.',
                  ),
                  const SizedBox(height: 8),
                  Text('Version ${AppConstants.appVersion} • Multi-Platform (Windows, Linux, Android)'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _checkUpdate(BuildContext context, AppState state) async {
    final scaffold = ScaffoldMessenger.of(context);
    scaffold.showSnackBar(
      const SnackBar(content: Text('Suche nach Updates auf dem Server...'), duration: Duration(seconds: 1)),
    );

    final updateService = UpdateService(serverUrl: state.storage.serverUrl);
    final update = await updateService.checkForUpdate();

    if (!context.mounted) return;

    if (update == null || !update.hasUpdate) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('App ist aktuell'),
          content: Text('Sie verwenden bereits die neueste Version (${AppConstants.appVersion}).'),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
      return;
    }

    _showUpdateDialog(context, update, updateService);
  }

  void _showUpdateDialog(BuildContext context, UpdateInfo update, UpdateService service) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        double downloadProgress = 0.0;
        bool isDownloading = false;
        String? errorMessage;

        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.system_update, color: Colors.teal),
                  const SizedBox(width: 10),
                  Text('Update v${update.latestVersion}'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Installierte Version: ${AppConstants.appVersion}'),
                  Text('Neue Version: ${update.latestVersion}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
                  const SizedBox(height: 12),
                  const Text('Hinweise zur Aktualisierung:', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(update.releaseNotes, style: const TextStyle(color: Colors.grey)),
                  if (isDownloading) ...[
                    const SizedBox(height: 16),
                    LinearProgressIndicator(value: downloadProgress > 0 ? downloadProgress : null),
                    const SizedBox(height: 8),
                    Text('${(downloadProgress * 100).toStringAsFixed(0)}% heruntergeladen...'),
                  ],
                  if (errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                  ],
                ],
              ),
              actions: isDownloading
                  ? []
                  : [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Später'),
                      ),
                      FilledButton.icon(
                        icon: const Icon(Icons.download),
                        label: const Text('Jetzt aktualisieren'),
                        onPressed: () {
                          setDialogState(() {
                            isDownloading = true;
                            errorMessage = null;
                          });
                          service.downloadAndInstall(
                            updateInfo: update,
                            onProgress: (p) => setDialogState(() => downloadProgress = p),
                            onDownloaded: (path) {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Update heruntergeladen. Installation wird gestartet...')),
                              );
                            },
                            onError: (err) {
                              setDialogState(() {
                                isDownloading = false;
                                errorMessage = err;
                              });
                            },
                          );
                        },
                      ),
                    ],
            );
          },
        );
      },
    );
  }
}
