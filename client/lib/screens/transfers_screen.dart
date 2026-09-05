import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';
import '../models/transfer_item.dart';
import '../services/app_state.dart';

class TransfersScreen extends StatelessWidget {
  const TransfersScreen({super.key});

  Color _getStatusColor(TransferStatus status) {
    switch (status) {
      case TransferStatus.running:
      case TransferStatus.connecting:
        return Colors.blue;
      case TransferStatus.completed:
        return Colors.green;
      case TransferStatus.failed:
      case TransferStatus.rejected:
        return Colors.red;
      case TransferStatus.pending:
        return Colors.orange;
    }
  }

  String _getStatusLabel(TransferStatus status) {
    switch (status) {
      case TransferStatus.pending:
        return 'Wartet auf Bestätigung...';
      case TransferStatus.connecting:
        return 'Verbinde mit Zielgerät...';
      case TransferStatus.running:
        return 'Wird übertragen...';
      case TransferStatus.completed:
        return 'Erfolgreich abgeschlossen';
      case TransferStatus.failed:
        return 'Fehlgeschlagen';
      case TransferStatus.rejected:
        return 'Abgelehnt';
    }
  }

  void _openFile(BuildContext context, String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final result = await OpenFilex.open(path);
      if (result.type != ResultType.done && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Konnte Datei nicht öffnen: ${result.message}')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dateiübertragungen'),
      ),
      body: state.transfers.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.swap_vert_circle_outlined, size: 72, color: theme.colorScheme.outline),
                  const SizedBox(height: 16),
                  Text('Noch keine Übertragungen', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    'Gesendete und empfangene Dateien werden hier angezeigt.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: state.transfers.length,
              itemBuilder: (context, index) {
                final item = state.transfers[index];
                final isSend = item.direction == TransferDirection.send;
                final statusColor = _getStatusColor(item.status);

                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header Row: Direction icon, filename, mode badge
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: (isSend ? Colors.blue : Colors.teal).withOpacity(0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isSend ? Icons.arrow_upward : Icons.arrow_downward,
                                color: isSend ? Colors.blue : Colors.teal,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.filename,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '${isSend ? "An" : "Von"}: ${item.peerDeviceName}',
                                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceVariant,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                item.mode,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Progress Bar (if running or connecting)
                        if (item.status == TransferStatus.running || item.status == TransferStatus.connecting) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: item.progress > 0 ? item.progress : null,
                              minHeight: 10,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${(item.progress * 100).toStringAsFixed(1)}% (${item.formattedTransferred} / ${item.formattedSize})',
                                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              Row(
                                children: [
                                  if (item.formattedEta.isNotEmpty) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primaryContainer.withOpacity(0.6),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '⏱️ ${item.formattedEta}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: theme.colorScheme.primary,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Text(
                                    item.formattedSpeed,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.status == TransferStatus.connecting
                                ? (item.direction == TransferDirection.receive
                                    ? 'Warte auf Bereitstellung durch Sender... (Relay)'
                                    : 'Verbindung wird aufgebaut...')
                                : (item.direction == TransferDirection.send
                                    ? 'Wird gesendet...'
                                    : 'Wird heruntergeladen...'),
                            style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
                          ),
                        ] else ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(radius: 4, backgroundColor: statusColor),
                                  const SizedBox(width: 6),
                                  Text(
                                    _getStatusLabel(item.status),
                                    style: TextStyle(
                                      color: statusColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              Text(item.formattedSize, style: theme.textTheme.bodySmall),
                            ],
                          ),
                        ],

                        // Error message
                        if (item.errorMessage != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            item.errorMessage!,
                            style: const TextStyle(color: Colors.red, fontSize: 12),
                          ),
                        ],

                        // Actions for completed receive files
                        if (item.status == TransferStatus.completed && item.localFilePath != null) ...[
                          const Divider(height: 20),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              icon: const Icon(Icons.folder_open, size: 18),
                              label: const Text('Datei öffnen'),
                              onPressed: () => _openFile(context, item.localFilePath),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
