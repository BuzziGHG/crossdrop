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

  int _sendModeTab = 0; // 0: Eigenes Gerät, 1: An anderen Account (E-Mail)
  final TextEditingController _emailController = TextEditingController();
  bool _isCheckingEmail = false;
  Map<String, dynamic>? _recipientData;
  String? _emailError;

  @override
  void initState() {
    super.initState();
    _selectedFile = widget.preselectedFile;
    _selectedDevice = widget.preselectedDevice;
    if (_selectedDevice != null) {
      _connectionMode = _selectedDevice!.preferredMode;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.isNotEmpty && result.files.first.path != null) {
      setState(() {
        _selectedFile = File(result.files.first.path!);
      });
    }
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
    if (_selectedFile == null) return;
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

    setState(() {
      _isSending = true;
    });

    try {
      if (_sendModeTab == 0) {
        await state.startSendingFile(
          file: _selectedFile!,
          targetDevice: _selectedDevice!,
          mode: _connectionMode,
        );
      } else {
        await state.startSendingFileByEmail(
          file: _selectedFile!,
          recipientEmail: _emailController.text.trim(),
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

            // 2. Mode Selector: Own Device vs Other Account via Email
            SegmentedButton<int>(
              segments: const [
                ButtonSegment<int>(
                  value: 0,
                  icon: Icon(Icons.devices),
                  label: Text('Meine Geräte'),
                ),
                ButtonSegment<int>(
                  value: 1,
                  icon: Icon(Icons.mail_outline),
                  label: Text('Per E-Mail senden'),
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
            ] else ...[
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
            ],
            const SizedBox(height: 32),

            // Send Button
            FilledButton.icon(
              icon: const Icon(Icons.send_rounded),
              label: Text(_sendModeTab == 1 ? 'An Empfänger senden' : 'Datei jetzt übertragen'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: (_selectedFile != null &&
                      !_isSending &&
                      (_sendModeTab == 0
                          ? _selectedDevice != null
                          : _emailController.text.trim().isNotEmpty))
                  ? _send
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

