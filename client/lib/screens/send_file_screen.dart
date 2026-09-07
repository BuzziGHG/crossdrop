import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../models/cloud_account.dart';
import '../models/device.dart';
import '../models/transfer_item.dart';
import '../services/app_state.dart';
import 'cloud_screen.dart';

class SendFileScreen extends StatefulWidget {
  final File? preselectedFile;
  final DeviceModel? preselectedDevice;

  const SendFileScreen({
    super.key,
    this.preselectedFile,
    this.preselectedDevice,
  });

  @override
  State<SendFileScreen> createState() => _SendFileScreenState();
}

class _SendFileScreenState extends State<SendFileScreen> {
  List<File> _selectedFiles = [];
  DeviceModel? _selectedDevice;
  ConnectionMode _connectionMode = ConnectionMode.lan;
  bool _isSending = false;

  int _sendModeTab = 0; // 0: Eigenes Gerät, 1: An anderen Account (E-Mail), 2: Cloud-Speicher (Nextcloud)
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _cloudPathController = TextEditingController(text: '/');
  bool _isCheckingEmail = false;
  Map<String, dynamic>? _recipientData;
  String? _emailError;
  bool _isScanningFolder = false;

  @override
  void initState() {
    super.initState();
    if (widget.preselectedFile != null) {
      _selectedFiles = [widget.preselectedFile!];
    }
    _selectedDevice = widget.preselectedDevice;
    if (_selectedDevice != null) {
      _connectionMode = _selectedDevice!.preferredMode;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _cloudPathController.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result != null && result.files.isNotEmpty) {
      final picked = result.files
          .where((f) => f.path != null)
          .map((f) => File(f.path!))
          .toList();
      if (picked.isNotEmpty) {
        setState(() {
          _selectedFiles = picked;
        });
      }
    }
  }

  Future<void> _pickFolder() async {
    setState(() => _isScanningFolder = true);
    try {
      final dirPath = await FilePicker.platform.getDirectoryPath();
      if (dirPath != null && dirPath.isNotEmpty) {
        final dir = Directory(dirPath);
        if (await dir.exists()) {
          final List<File> files = [];
          await for (final entity in dir.list(recursive: true, followLinks: false)) {
            if (entity is File) {
              files.add(entity);
              if (files.length >= 5000) break;
            }
          }
          if (files.isNotEmpty) {
            setState(() {
              _selectedFiles = files;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error picking folder: $e');
    } finally {
      if (mounted) setState(() => _isScanningFolder = false);
    }
  }

  Future<int> _calculateTotalBytes() async {
    int total = 0;
    for (final f in _selectedFiles) {
      try {
        total += await f.length();
      } catch (_) {}
    }
    return total;
  }

  Future<void> _checkEmail() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _emailError = 'Bitte eine gültige E-Mail-Adresse eingeben.';
        _recipientData = null;
      });
      return;
    }

    final state = Provider.of<AppState>(context, listen: false);
    setState(() {
      _isCheckingEmail = true;
      _emailError = null;
    });

    try {
      final res = await state.api.lookupRecipient(email);
      if (mounted) {
        setState(() {
          _recipientData = res;
          _emailError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _recipientData = null;
          _emailError = e.toString().replaceAll('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingEmail = false;
        });
      }
    }
  }

  Future<void> _send() async {
    if (_selectedFiles.isEmpty) return;
    if (_sendModeTab == 0 && _selectedDevice == null) return;
    if (_sendModeTab == 1 && (_recipientData == null || _recipientData!['has_online_device'] != true)) {
      await _checkEmail();
      if (_recipientData == null || _recipientData!['has_online_device'] != true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_emailError ?? 'Kein empfangsbereites Gerät für diesen Account online.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    final state = Provider.of<AppState>(context, listen: false);

    if (_sendModeTab == 2) {
      final account = state.activeCloudAccount ?? (state.cloudAccounts.isNotEmpty ? state.cloudAccounts.first : null);
      if (account == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bitte zuerst ein Cloud-Konto anlegen.'), backgroundColor: Colors.orange),
        );
        return;
      }
    }

    setState(() {
      _isSending = true;
    });

    try {
      if (_sendModeTab == 0) {
        if (_selectedFiles.length == 1) {
          await state.startSendingFile(
            file: _selectedFiles.first,
            targetDevice: _selectedDevice!,
            mode: _connectionMode,
          );
        } else {
          await state.startSendingFilesBatch(
            files: _selectedFiles,
            targetDevice: _selectedDevice!,
            mode: _connectionMode,
          );
        }
      } else if (_sendModeTab == 1) {
        if (_selectedFiles.length == 1) {
          await state.startSendingFileByEmail(
            file: _selectedFiles.first,
            recipientEmail: _emailController.text.trim(),
          );
        } else {
          await state.startSendingFilesBatch(
            files: _selectedFiles,
            targetDevice: DeviceModel(
              id: 'cross-account',
              name: _recipientData?['target_device_name'] ?? _emailController.text.trim(),
              platform: 'remote',
              transferPort: 2603,
              localIps: [],
              vpnIps: [],
              isOnline: true,
              lastSeen: DateTime.now(),
            ),
            mode: ConnectionMode.vpn,
            isCrossAccount: true,
            recipientEmail: _emailController.text.trim(),
          );
        }
      } else if (_sendModeTab == 2) {
        final account = state.activeCloudAccount ?? state.cloudAccounts.first;
        await state.uploadFilesToCloud(
          account: account,
          files: _selectedFiles,
          remotePath: _cloudPathController.text.trim().isEmpty ? '/' : _cloudPathController.text.trim(),
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Übertragung gestartet! Siehe Reiter "Transfers".')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fehler beim Senden: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<AppState>();

    // Ensure preselected device is preserved or matched from current device list
    if (widget.preselectedDevice != null) {
      _selectedDevice = state.devices.firstWhere(
        (d) => d.id == widget.preselectedDevice!.id,
        orElse: () => widget.preselectedDevice!,
      );
    } else if (_selectedDevice == null && state.devices.isNotEmpty) {
      _selectedDevice = state.devices.first;
    }

    // If currently sending and we have an active transfer item, show live progress view!
    final activeItem = state.activeSendingTaskId != null
        ? state.transfers.where((t) => t.id == state.activeSendingTaskId).firstOrNull
        : null;

    if (_isSending && activeItem != null) {
      final isDone = activeItem.status == TransferStatus.completed;
      final isFailed = activeItem.status == TransferStatus.failed;
      final isCancelled = activeItem.status == TransferStatus.cancelled;

      return Scaffold(
        appBar: AppBar(
          title: const Text('Datei wird übertragen'),
          automaticallyImplyLeading: false,
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Status Icon
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDone
                            ? Colors.green.withOpacity(0.15)
                            : (isFailed
                                ? Colors.red.withOpacity(0.15)
                                : (isCancelled ? Colors.orange.withOpacity(0.15) : theme.colorScheme.primaryContainer)),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isDone
                            ? Icons.check_circle_rounded
                            : (isFailed
                                ? Icons.error_rounded
                                : (isCancelled ? Icons.cancel_outlined : Icons.cloud_upload_rounded)),
                        size: 48,
                        color: isDone
                            ? Colors.green
                            : (isFailed ? Colors.red : (isCancelled ? Colors.orange : theme.colorScheme.primary)),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Filename & Target
                    Text(
                      activeItem.isBatch && activeItem.batchCurrentFileName != null
                          ? '${activeItem.filename}\nAktuell: ${activeItem.batchCurrentFileName!} (${activeItem.batchCurrentFileIndex}/${activeItem.batchTotalFiles})'
                          : activeItem.filename,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Ziel: ${activeItem.peerDeviceName} (${activeItem.mode})',
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                    ),
                    const SizedBox(height: 24),

                    // Progress Bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: activeItem.progress > 0 ? activeItem.progress : null,
                        minHeight: 12,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Percentage & Transferred / Total
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${(activeItem.progress * 100).toStringAsFixed(1)}%',
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${activeItem.formattedTransferred} / ${activeItem.formattedSize}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Speed & Remaining Time (ETA) Badges
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              children: [
                                const Text('Geschwindigkeit', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                const SizedBox(height: 2),
                                Text(
                                  activeItem.formattedSpeed,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              children: [
                                const Text('Verbleibende Zeit', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                const SizedBox(height: 2),
                                Text(
                                  activeItem.formattedEta.isNotEmpty
                                      ? activeItem.formattedEta
                                      : (isDone
                                          ? 'Abgeschlossen'
                                          : (isFailed
                                              ? 'Fehlgeschlagen'
                                              : (isCancelled ? 'Abgebrochen' : 'Berechne...'))),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: isDone
                                        ? Colors.green
                                        : (isFailed
                                            ? Colors.red
                                            : (isCancelled ? Colors.orange : theme.colorScheme.primary)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (activeItem.errorMessage != null && activeItem.status == TransferStatus.running) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: theme.colorScheme.primary.withOpacity(0.2)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.primary),
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                activeItem.errorMessage!,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),

                    // Action Button
                    if (isDone)
                      FilledButton.icon(
                        icon: const Icon(Icons.check),
                        label: const Text('Fertig'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          state.setNavIndex(1);
                        },
                      )
                    else if (isFailed)
                      FilledButton.icon(
                        icon: const Icon(Icons.close),
                        label: const Text('Schließen'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red,
                          minimumSize: const Size(double.infinity, 48),
                        ),
                        onPressed: () => Navigator.pop(context),
                      )
                    else if (isCancelled)
                      FilledButton.icon(
                        icon: const Icon(Icons.close),
                        label: const Text('Abgebrochen – Schließen'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.orange,
                          minimumSize: const Size(double.infinity, 48),
                        ),
                        onPressed: () => Navigator.pop(context),
                      )
                    else
                      Column(
                        children: [
                          OutlinedButton.icon(
                            icon: const Icon(Icons.open_in_new),
                            label: const Text('Im Hintergrund fortsetzen'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 48),
                            ),
                            onPressed: () {
                              Navigator.pop(context);
                              state.setNavIndex(1);
                            },
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                            label: const Text('Übertragung abbrechen', style: TextStyle(color: Colors.red)),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.red),
                              minimumSize: const Size(double.infinity, 48),
                            ),
                            onPressed: () {
                              state.cancelTransfer(activeItem.id);
                              Navigator.pop(context);
                            },
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Datei senden'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. File Selection Card (Supports single file, multi-file & whole folders up to 5,000 files)
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    if (_selectedFiles.isEmpty) ...[
                      Icon(Icons.drive_folder_upload_outlined, size: 56, color: theme.colorScheme.primary),
                      const SizedBox(height: 12),
                      const Text(
                        'Dateien oder Ordner auswählen',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Stapel-Übertragung von bis zu 5.000 Dateien unterstützt',
                        style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      if (_isScanningFolder) ...[
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                            SizedBox(width: 12),
                            Text('Ordner wird eingelesen...', style: TextStyle(fontSize: 13)),
                          ],
                        ),
                      ] else ...[
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            FilledButton.icon(
                              icon: const Icon(Icons.attach_file),
                              label: const Text('Dateien wählen'),
                              onPressed: _pickFiles,
                            ),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.folder_open),
                              label: const Text('Ganzen Ordner'),
                              onPressed: _pickFolder,
                            ),
                          ],
                        ),
                      ],
                    ] else ...[
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              _selectedFiles.length > 1 ? Icons.folder_copy : Icons.insert_drive_file,
                              color: theme.colorScheme.onPrimaryContainer,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _selectedFiles.length == 1
                                      ? p.basename(_selectedFiles.first.path)
                                      : '${_selectedFiles.length} Dateien ausgewählt',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                FutureBuilder<int>(
                                  future: _calculateTotalBytes(),
                                  builder: (context, snapshot) {
                                    final size = snapshot.data ?? 0;
                                    return Text(
                                      '${TransferItem.formatBytes(size)}${_selectedFiles.length > 1 ? ' gesamt' : ''}',
                                      style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            tooltip: 'Mehr Dateien hinzufügen',
                            onPressed: _pickFiles,
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: 'Auswahl zurücksetzen',
                            onPressed: () {
                              setState(() {
                                _selectedFiles = [];
                              });
                            },
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 2. Mode Selector: Own Device vs Other Account (Email) vs Cloud (Nextcloud)
            SegmentedButton<int>(
              segments: const [
                ButtonSegment<int>(
                  value: 0,
                  icon: Icon(Icons.devices),
                  label: Text('Geräte'),
                ),
                ButtonSegment<int>(
                  value: 1,
                  icon: Icon(Icons.mail_outline),
                  label: Text('E-Mail'),
                ),
                ButtonSegment<int>(
                  value: 2,
                  icon: Icon(Icons.cloud_sync),
                  label: Text('Cloud'),
                ),
              ],
              selected: {_sendModeTab},
              onSelectionChanged: (Set<int> newSelection) {
                setState(() {
                  _sendModeTab = newSelection.first;
                  if (_sendModeTab == 1) {
                    _connectionMode = ConnectionMode.vpn;
                  }
                });
              },
            ),
            const SizedBox(height: 24),

            if (_sendModeTab == 0) ...[
              // Target Device Selection (Confirmed card if preselected, or dropdown if opened generic)
              Text(
                'Zielgerät',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (widget.preselectedDevice != null && _selectedDevice != null) ...[
                Card(
                  elevation: 1,
                  color: theme.colorScheme.primaryContainer.withOpacity(0.35),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: theme.colorScheme.primary.withOpacity(0.4)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.check, size: 18, color: Colors.white),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selectedDevice!.name,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              Text(
                                '${_selectedDevice!.platform.toUpperCase()} • Bereit zur Übertragung',
                                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Ausgewählt',
                            style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else if (state.devices.isEmpty) ...[
                const Text('Keine anderen registrierten Geräte vorhanden.')
              ] else ...[
                DropdownButtonFormField<DeviceModel>(
                  value: _selectedDevice,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.devices),
                  ),
                  items: state.devices.map((dev) {
                    return DropdownMenuItem<DeviceModel>(
                      value: dev,
                      child: Row(
                        children: [
                          Text(dev.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          Text('(${dev.platform})', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                          if (!dev.isOnline) ...[
                            const SizedBox(width: 8),
                            const Text('[Offline]', style: TextStyle(color: Colors.red, fontSize: 12)),
                          ],
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedDevice = val;
                    });
                  },
                ),
              ],
              const SizedBox(height: 24),

              // Connection Mode Selector (LAN vs VPN)
              Text(
                'Übertragungsweg auswählen',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              RadioListTile<ConnectionMode>(
                value: ConnectionMode.lan,
                groupValue: _connectionMode,
                title: const Text('Lokales Netzwerk (LAN / WLAN)'),
                subtitle: const Text('Maximale Geschwindigkeit P2P (automatischer Relay-Fallback bei Firewall)'),
                secondary: const Icon(Icons.wifi),
                onChanged: (val) {
                  if (val != null) setState(() => _connectionMode = val);
                },
              ),
              RadioListTile<ConnectionMode>(
                value: ConnectionMode.vpn,
                groupValue: _connectionMode,
                title: const Text('VPN / Server-Relay (Unterwegs & Remote)'),
                subtitle: const Text('Sichere Übertragung über Server-Relay von unterwegs oder mobilem Netz'),
                secondary: const Icon(Icons.vpn_lock),
                onChanged: (val) {
                  if (val != null) setState(() => _connectionMode = val);
                },
              ),
            ] else if (_sendModeTab == 1) ...[
              // Cross-Account E-Mail Mode UI
              Text(
                'Empfänger-Account (E-Mail)',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        hintText: 'empfaenger@beispiel.de',
                        prefixIcon: const Icon(Icons.email_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                      onFieldSubmitted: (_) => _checkEmail(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.tonal(
                    onPressed: _isCheckingEmail ? null : _checkEmail,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isCheckingEmail
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Prüfen'),
                  ),
                ],
              ),
              if (_emailError != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _emailError!,
                          style: const TextStyle(color: Colors.red, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_recipientData != null) ...[
                const SizedBox(height: 12),
                Card(
                  elevation: 1,
                  color: _recipientData!['has_online_device'] == true
                      ? Colors.green.withOpacity(0.12)
                      : Colors.orange.withOpacity(0.12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: _recipientData!['has_online_device'] == true
                          ? Colors.green.withOpacity(0.4)
                          : Colors.orange.withOpacity(0.4),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Icon(
                          _recipientData!['has_online_device'] == true
                              ? Icons.check_circle_outline
                              : Icons.warning_amber_rounded,
                          color: _recipientData!['has_online_device'] == true ? Colors.green : Colors.orange,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Account: ${_recipientData!['username']} (${_recipientData!['email']})',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _recipientData!['has_online_device'] == true
                                    ? 'Zielgerät: ${_recipientData!['target_device_name'] ?? 'Online'} (Empfangsbereit)'
                                    : 'Aktuell kein Gerät im VPN-Tunnel online',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _recipientData!['has_online_device'] == true
                                      ? Colors.green[800]
                                      : Colors.orange[800],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),

              // Info Box: Secure VPN Relay & Mandatory Confirmation
              Card(
                elevation: 0,
                color: theme.colorScheme.primaryContainer.withOpacity(0.45),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: theme.colorScheme.primary.withOpacity(0.3)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.shield_outlined, color: theme.colorScheme.primary, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Sicherer Cross-Account VPN-Transfer',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Der Versand an andere Accounts erfolgt immer verschlüsselt über das Server-Relay. Der Empfänger muss die Datei vor dem Empfang immer erst annehmen.',
                              style: TextStyle(fontSize: 12, height: 1.3),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else if (_sendModeTab == 2) ...[
              // Cloud Storage Mode (Nextcloud / WebDAV)
              Text(
                'Cloud-Konto (Nextcloud / WebDAV)',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (state.cloudAccounts.isEmpty) ...[
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      children: [
                        Icon(Icons.cloud_off_outlined, size: 48, color: theme.colorScheme.primary),
                        const SizedBox(height: 12),
                        const Text(
                          'Noch kein Cloud-Konto verbunden',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Verbinden Sie Ihre Nextcloud mit IP-Adresse / Domain und Zugangsdaten, um Dateien direkt hochzuladen.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          icon: const Icon(Icons.add),
                          label: const Text('Nextcloud verbinden'),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const CloudScreen()),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                DropdownButtonFormField<CloudAccount>(
                  value: state.activeCloudAccount ?? state.cloudAccounts.first,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.cloud_done),
                    labelText: 'Aktives Cloud-Konto',
                  ),
                  items: state.cloudAccounts.map((acc) {
                    return DropdownMenuItem<CloudAccount>(
                      value: acc,
                      child: Text('${acc.name} (${acc.serverUrl})', overflow: TextOverflow.ellipsis),
                    );
                  }).toList(),
                  onChanged: (acc) {
                    if (acc != null) {
                      state.setActiveCloudAccount(acc);
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _cloudPathController,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.folder_open),
                    labelText: 'Zielordner auf der Cloud',
                    hintText: '/',
                    helperText: 'Dateien werden in dieses Verzeichnis auf Ihrer Nextcloud geladen',
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Card(
                elevation: 0,
                color: theme.colorScheme.primaryContainer.withOpacity(0.35),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: theme.colorScheme.primary.withOpacity(0.25)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Row(
                    children: [
                      Icon(Icons.cloud_sync, color: theme.colorScheme.primary, size: 24),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Dateien werden direkt über WebDAV auf Ihren Server übertragen. Es wird kein fremder Cloud-Speicher zwischengeschaltet.',
                          style: TextStyle(fontSize: 12, height: 1.3),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 32),

            // Send Button
            FilledButton.icon(
              icon: const Icon(Icons.send_rounded),
              label: Text(
                _sendModeTab == 2
                    ? (_selectedFiles.length > 1
                        ? '${_selectedFiles.length} Dateien in Cloud laden'
                        : 'In Cloud hochladen')
                    : (_sendModeTab == 1
                        ? (_selectedFiles.length > 1
                            ? '${_selectedFiles.length} Dateien per E-Mail senden'
                            : 'An Empfänger senden')
                        : (_selectedFiles.length > 1
                            ? '${_selectedFiles.length} Dateien übertragen'
                            : 'Datei jetzt übertragen')),
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: (_selectedFiles.isNotEmpty &&
                      !_isSending &&
                      (_sendModeTab == 0
                          ? _selectedDevice != null
                          : (_sendModeTab == 1
                              ? _emailController.text.trim().isNotEmpty
                              : state.cloudAccounts.isNotEmpty)))
                  ? _send
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

