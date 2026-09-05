import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../models/device.dart';
import '../models/transfer_item.dart';
import '../services/app_state.dart';

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
  File? _selectedFile;
  DeviceModel? _selectedDevice;
  ConnectionMode _connectionMode = ConnectionMode.lan;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _selectedFile = widget.preselectedFile;
    _selectedDevice = widget.preselectedDevice;
    if (_selectedDevice != null) {
      _connectionMode = _selectedDevice!.preferredMode;
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.isNotEmpty && result.files.first.path != null) {
      setState(() {
        _selectedFile = File(result.files.first.path!);
      });
    }
  }

  Future<void> _send() async {
    if (_selectedFile == null || _selectedDevice == null) return;

    final state = Provider.of<AppState>(context, listen: false);

    setState(() {
      _isSending = true;
    });

    try {
      await state.startSendingFile(
        file: _selectedFile!,
        targetDevice: _selectedDevice!,
        mode: _connectionMode,
      );

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
                            : (isFailed ? Colors.red.withOpacity(0.15) : theme.colorScheme.primaryContainer),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isDone
                            ? Icons.check_circle_rounded
                            : (isFailed ? Icons.error_rounded : Icons.cloud_upload_rounded),
                        size: 48,
                        color: isDone
                            ? Colors.green
                            : (isFailed ? Colors.red : theme.colorScheme.primary),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Filename & Target
                    Text(
                      activeItem.filename,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'An: ${activeItem.peerDeviceName} (${activeItem.mode})',
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
                                      : (isDone ? 'Abgeschlossen' : (isFailed ? 'Fehlgeschlagen' : 'Berechne...')),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: isDone ? Colors.green : (isFailed ? Colors.red : theme.colorScheme.primary),
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
                    else
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
            // 1. File Selection Card
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    if (_selectedFile == null) ...[
                      Icon(Icons.cloud_upload_outlined, size: 64, color: theme.colorScheme.primary),
                      const SizedBox(height: 12),
                      const Text(
                        'Wählen Sie eine Datei von diesem Gerät aus',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        icon: const Icon(Icons.attach_file),
                        label: const Text('Datei auswählen'),
                        onPressed: _pickFile,
                      ),
                    ] else ...[
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.insert_drive_file, color: theme.colorScheme.onPrimaryContainer),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.basename(_selectedFile!.path),
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                FutureBuilder<int>(
                                  future: _selectedFile!.length(),
                                  builder: (context, snapshot) {
                                    final size = snapshot.data ?? 0;
                                    return Text(
                                      TransferItem.formatBytes(size),
                                      style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.change_circle_outlined),
                            tooltip: 'Andere Datei wählen',
                            onPressed: _pickFile,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 2. Target Device (Confirmed card if preselected, or dropdown if opened generic)
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

            // 3. Connection Mode Selector (LAN vs VPN)
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
            const SizedBox(height: 32),

            // 4. Send Button
            FilledButton.icon(
              icon: const Icon(Icons.send_rounded),
              label: const Text('Datei jetzt übertragen'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: (_selectedFile != null && _selectedDevice != null && !_isSending)
                  ? _send
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

