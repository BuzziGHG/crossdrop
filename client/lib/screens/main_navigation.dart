import 'dart:io';
import 'package:flutter/services.dart';
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
      barrierDismissible: true,
      builder: (ctx) {
        double downloadProgress = 0.0;
        bool isDownloading = false;
        bool isDownloaded = false;
        String? downloadedFilePath;
        String? errorMessage;

        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return PopScope(
              canPop: true,
              onPopInvokedWithResult: (didPop, _) {
                if (didPop && isDownloading) {
                  service.cancelDownload();
                }
              },
              child: AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: Row(
                  children: [
                    const Icon(Icons.rocket_launch, color: Colors.teal),
                    const SizedBox(width: 10),
                    Text('Neues Update v${update.latestVersion}'),
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
                              child: SelectableText(
                                update.releaseNotes,
                                style: const TextStyle(fontSize: 13, height: 1.4),
                              ),
                            ),
                            if (isDownloading && !isDownloaded) ...[
                              const SizedBox(height: 16),
                              LinearProgressIndicator(value: downloadProgress > 0 ? downloadProgress : null),
                              const SizedBox(height: 8),
                              Text(
                                downloadProgress >= 0.98
                                    ? 'Wird abgeschlossen... Bitte warten'
                                    : '${(downloadProgress * 100).toStringAsFixed(0)}% heruntergeladen...',
                              ),
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
                                          'Download abgeschlossen!',
                                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      Platform.isAndroid
                                          ? 'Die Update-Datei wurde heruntergeladen. Tippen Sie unten auf "Jetzt installieren". Falls die Installation blockiert wird, bitte "Berechtigung prüfen" antippen.'
                                          : 'Das Update wurde erfolgreich heruntergeladen. Tippen Sie auf "Jetzt installieren", um die Aktualisierung abzuschließen.',
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
                        TextButton(
                          onPressed: () {
                            service.cancelDownload();
                            setDialogState(() {
                              isDownloading = false;
                              downloadProgress = 0.0;
                              errorMessage = 'Download abgebrochen.';
                            });
                          },
                          child: const Text('Abbrechen', style: TextStyle(color: Colors.red)),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(right: 12, left: 8),
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
                                    errorMessage = 'Installation konnte nicht automatisch gestartet werden. Bitte tippen Sie auf "Berechtigung prüfen" (Zulassen) oder öffnen Sie die Datei direkt in Ihrer "Downloads"-App.';
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
              ),
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
            final isExternal = item.isCrossAccount || item.senderEmail != null;

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              icon: Icon(
                isExternal ? Icons.mark_email_unread_rounded : Icons.file_download,
                size: 40,
                color: isExternal ? Colors.orange : Colors.teal,
              ),
              title: Text(isExternal ? 'Eingehende Datei (Anderer Account)' : 'Eingehende Datei'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isExternal) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        '🌐 Cross-Account Transfer via VPN',
                        style: TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Text(
                      'Benutzer "${item.senderEmail ?? item.peerDeviceName}" möchte eine Datei an Sie senden:',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ] else ...[
                    Text(
                      'Gerät "${item.peerDeviceName}" möchte eine Datei an Sie senden:',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.insert_drive_file, color: isExternal ? Colors.orange : Colors.teal),
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
                  child: const Text('Annehmen & Empfangen'),
                ),
              ],
            );
          },
        );
      });
    }
  }

  Widget _buildActiveTransferBar(BuildContext context, TransferItem active) {
    final theme = Theme.of(context);
    final isSend = active.direction == TransferDirection.send;

    return GestureDetector(
      onTap: () {
        setState(() => _currentIndex = 1);
        final state = Provider.of<AppState>(context, listen: false);
        state.selectedNavIndex = 1;
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.primary.withOpacity(0.35)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isSend ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 16,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        active.filename,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${isSend ? "An" : "Von"} ${active.peerDeviceName} • ${active.formattedSpeed}',
                        style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
                      ),
                    ],
                  ),
                ),
                if (active.formattedEta.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '⏱️ ${active.formattedEta}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  '${(active.progress * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.cancel_outlined, color: Colors.red, size: 20),
                  tooltip: 'Abbrechen',
                  onPressed: () {
                    final state = Provider.of<AppState>(context, listen: false);
                    state.cancelTransfer(active.id);
                  },
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: active.progress > 0 ? active.progress : null,
                minHeight: 4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    _checkPendingApproval(context, state);

    if (state.selectedNavIndex != _currentIndex) {
      _currentIndex = state.selectedNavIndex;
    }

    final activeTransfer = state.activeTransfer;
    final isWideScreen = MediaQuery.of(context).size.width >= 700;

    final content = isWideScreen
        ? Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _currentIndex,
                  onDestinationSelected: (idx) {
                    setState(() => _currentIndex = idx);
                    state.selectedNavIndex = idx;
                  },
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
                Expanded(
                  child: Column(
                    children: [
                      Expanded(child: _screens[_currentIndex]),
                      if (activeTransfer != null && _currentIndex != 1)
                        _buildActiveTransferBar(context, activeTransfer),
                    ],
                  ),
                ),
              ],
            ),
          )
        : Scaffold(
            body: Column(
              children: [
                Expanded(child: _screens[_currentIndex]),
                if (activeTransfer != null && _currentIndex != 1)
                  _buildActiveTransferBar(context, activeTransfer),
              ],
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _currentIndex,
              onDestinationSelected: (idx) {
                setState(() => _currentIndex = idx);
                state.selectedNavIndex = idx;
              },
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (Platform.isAndroid) {
          try {
            const MethodChannel('com.crossdrop.app/installer').invokeMethod('moveToBackground');
          } catch (_) {}
        }
      },
      child: content,
    );
  }
}

