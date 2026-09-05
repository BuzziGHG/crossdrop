import '../models/transfer_item.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import 'device_list_screen.dart';
import 'transfers_screen.dart';
import 'settings_screen.dart';

import '../services/update_service.dart';
import '../config/constants.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  bool _showingDialog = false;
  bool _checkedForUpdate = false;

  final List<Widget> _screens = const [
    DeviceListScreen(),
    TransfersScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAutoUpdate();
    });
  }

  Future<void> _checkAutoUpdate() async {
    if (_checkedForUpdate) return;
    _checkedForUpdate = true;

    try {
      final state = Provider.of<AppState>(context, listen: false);
      final updateService = UpdateService(serverUrl: state.storage.serverUrl);
      final update = await updateService.checkForUpdate();

      if (update != null && update.hasUpdate && mounted) {
        // 1. Persistent Top Banner with release notes
        ScaffoldMessenger.of(context).showMaterialBanner(
          MaterialBanner(
            leading: const Icon(Icons.rocket_launch, color: Colors.teal),
            content: Text(
              '🚀 Update v${update.latestVersion}: ${update.releaseNotes}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              TextButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
                },
                child: const Text('Später'),
              ),
              FilledButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
                  _showUpdateDialog(context, update, updateService);
                },
                child: const Text('Details & Update'),
              ),
            ],
          ),
        );

        // 2. Direct Popup Notification Dialog
        _showUpdateDialog(context, update, updateService);
      }
    } catch (e) {
      debugPrint('Auto-Update check error: $e');
    }
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
                  const Icon(Icons.rocket_launch, color: Colors.teal),
                  const SizedBox(width: 10),
                  Text('Neues Update v${update.latestVersion}'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Installierte Version: ${AppConstants.appVersion}'),
                  Text(
                    'Neue Version: ${update.latestVersion}',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal),
                  ),
                  const SizedBox(height: 14),
                  const Text('Neuigkeiten & Verbesserungen:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      update.releaseNotes,
                      style: const TextStyle(fontSize: 13, height: 1.3),
                    ),
                  ),
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

  void _checkPendingApproval(BuildContext context, AppState state) {
    if (state.pendingApprovalItem != null && !_showingDialog) {
      _showingDialog = true;
      final item = state.pendingApprovalItem!;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              icon: const Icon(Icons.file_download, size: 40, color: Colors.teal),
              title: const Text('Eingehende Datei'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Gerät "${item.peerDeviceName}" möchte eine Datei an Sie senden:',
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.insert_drive_file, color: Colors.teal),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.filename,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${item.formattedSize} • Verbindung: ${item.mode}',
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    _showingDialog = false;
                    Navigator.pop(ctx);
                    state.approveTransfer(false);
                  },
                  child: const Text('Ablehnen', style: TextStyle(color: Colors.red)),
                ),
                FilledButton(
                  onPressed: () {
                    _showingDialog = false;
                    Navigator.pop(ctx);
                    state.approveTransfer(true);
                  },
                  child: const Text('Annehmen'),
                ),
              ],
            );
          },
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    _checkPendingApproval(context, state);

    final isWideScreen = MediaQuery.of(context).size.width >= 700;

    if (isWideScreen) {
      // Desktop / Tablet layout with NavigationRail
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _currentIndex,
              onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
              labelType: NavigationRailLabelType.all,
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: 20.0),
                child: Icon(Icons.sync_alt, size: 36, color: Colors.teal),
              ),
              destinations: [
                const NavigationRailDestination(
                  icon: Icon(Icons.devices_outlined),
                  selectedIcon: Icon(Icons.devices),
                  label: Text('Geräte'),
                ),
                NavigationRailDestination(
                  icon: Badge(
                    isLabelVisible: state.transfers.any((t) => t.status == TransferStatus.running),
                    label: const Text('!'),
                    child: const Icon(Icons.swap_vert_outlined),
                  ),
                  selectedIcon: const Icon(Icons.swap_vert),
                  label: const Text('Transfers'),
                ),
                const NavigationRailDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: Text('Einstellungen'),
                ),
              ],
            ),
            const VerticalDivider(thickness: 1, width: 1),
            Expanded(child: _screens[_currentIndex]),
          ],
        ),
      );
    }

    // Mobile layout with NavigationBar
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.devices_outlined),
            selectedIcon: Icon(Icons.devices),
            label: 'Geräte',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: state.transfers.any((t) => t.status == TransferStatus.running),
              label: const Text('!'),
              child: const Icon(Icons.swap_vert_outlined),
            ),
            selectedIcon: const Icon(Icons.swap_vert),
            label: 'Transfers',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Einstellungen',
          ),
        ],
      ),
    );
  }
}
