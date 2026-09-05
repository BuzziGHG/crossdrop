import '../models/transfer_item.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import 'device_list_screen.dart';
import 'transfers_screen.dart';
import 'settings_screen.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  bool _showingDialog = false;

  final List<Widget> _screens = const [
    DeviceListScreen(),
    TransfersScreen(),
    SettingsScreen(),
  ];

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
