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

    // If preselected was not available in devices, choose first
    if (_selectedDevice == null && state.devices.isNotEmpty) {
      _selectedDevice = state.devices.first;
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

            // 2. Target Device Picker
            Text(
              'Zielgerät auswählen',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (state.devices.isEmpty)
              const Text('Keine anderen registrierten Geräte vorhanden.')
            else
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
              subtitle: const Text('Maximale Geschwindigkeit im selben Heimnetz / Firmennetz'),
              secondary: const Icon(Icons.wifi),
              onChanged: (val) {
                if (val != null) setState(() => _connectionMode = val);
              },
            ),
            RadioListTile<ConnectionMode>(
              value: ConnectionMode.vpn,
              groupValue: _connectionMode,
              title: const Text('VPN-Verbindung (WireGuard / Tailscale)'),
              subtitle: const Text('Sichere verschlüsselte Direktverbindung von unterwegs'),
              secondary: const Icon(Icons.vpn_lock),
              onChanged: (val) {
                if (val != null) setState(() => _connectionMode = val);
              },
            ),
            const SizedBox(height: 32),

            // 4. Send Button
            FilledButton.icon(
              icon: _isSending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded),
              label: Text(_isSending ? 'Verbinde...' : 'Datei jetzt übertragen'),
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
