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
        bool isDownloaded = false;
        String? downloadedFilePath;
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
              content: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.6,
                  maxWidth: 480,
                ),
                child: Scrollbar(
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Installierte Version: ${AppConstants.appVersion}'),
                          Text('Neue Version: ${update.latestVersion}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
                          const SizedBox(height: 12),
                          const Text('Hinweise zur Aktualisierung:', style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: SelectableText(
                              update.releaseNotes,
                              style: const TextStyle(fontSize: 13, height: 1.4),
                            ),
                          ),
                          if (isDownloading && !isDownloaded) ...[
                            const SizedBox(height: 16),
                            LinearProgressIndicator(value: downloadProgress > 0 ? downloadProgress : null),
                            const SizedBox(height: 8),
                            Text('${(downloadProgress * 100).toStringAsFixed(0)}% heruntergeladen...'),
                          ],
                          if (isDownloaded) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.green.withOpacity(0.4)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.check_circle, color: Colors.green, size: 20),
                                      SizedBox(width: 8),
                                      Text(
                                        'Download 100% abgeschlossen!',
                                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    Platform.isAndroid
                                        ? 'Die Update-Datei liegt in "Downloads". Tippen Sie auf "Jetzt installieren".'
                                        : 'Das Update wurde erfolgreich heruntergeladen. Tippen Sie auf "Jetzt installieren".',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (errorMessage != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.red.withOpacity(0.3)),
                              ),
                              child: Text(
                                errorMessage!,
                                style: const TextStyle(color: Colors.red, fontSize: 12),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              actions: isDownloading && !isDownloaded
                  ? [
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Text(
                          '${(downloadProgress * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal),
                        ),
                      ),
                    ]
                  : isDownloaded
                      ? [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Schließen'),
                          ),
                          if (Platform.isAndroid)
                            TextButton.icon(
                              icon: const Icon(Icons.security, size: 18),
                              label: const Text('Berechtigung prüfen'),
                              onPressed: () => service.openInstallPermissionSettings(),
                            ),
                          FilledButton.icon(
                            icon: const Icon(Icons.system_update),
                            label: const Text('Jetzt installieren'),
                            style: FilledButton.styleFrom(backgroundColor: Colors.green),
                            onPressed: () async {
                              if (downloadedFilePath != null) {
                                final ok = await service.installUpdate(downloadedFilePath!);
                                if (!ok && Platform.isAndroid) {
                                  setDialogState(() {
                                    errorMessage = 'Installation konnte nicht gestartet werden. Bitte "Berechtigung prüfen" (Zulassen) antippen oder APK in "Downloads" öffnen.';
                                  });
                                }
                              }
                            },
                          ),
                        ]
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
                                  setDialogState(() {
                                    isDownloading = false;
                                    isDownloaded = true;
                                    downloadedFilePath = path;
                                  });
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
