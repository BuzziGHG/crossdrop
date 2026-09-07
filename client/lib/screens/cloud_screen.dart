import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/cloud_account.dart';
import '../services/app_state.dart';
import '../services/cloud_service.dart';

class CloudScreen extends StatefulWidget {
  const CloudScreen({super.key});

  @override
  State<CloudScreen> createState() => _CloudScreenState();
}

class _CloudScreenState extends State<CloudScreen> {
  final CloudService _cloudService = CloudService();

  String _currentRemotePath = '/';
  List<CloudFileItem> _files = [];
  bool _isLoadingFiles = false;
  String? _filesError;

  // Active download tracking: item path -> progress
  final Map<String, double> _downloadProgress = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = Provider.of<AppState>(context, listen: false);
      if (state.activeCloudAccount != null) {
        _currentRemotePath = state.activeCloudAccount!.remoteBasePath;
        _loadFiles();
      }
    });
  }

  Future<void> _loadFiles() async {
    final state = Provider.of<AppState>(context, listen: false);
    final account = state.activeCloudAccount;
    if (account == null) return;

    setState(() {
      _isLoadingFiles = true;
      _filesError = null;
    });

    try {
      final list = await _cloudService.listFiles(account, remotePath: _currentRemotePath);
      if (mounted) {
        setState(() {
          _files = list;
          _isLoadingFiles = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _filesError = e.toString().replaceAll('Exception: ', '');
          _isLoadingFiles = false;
        });
      }
    }
  }

  void _navigateInto(String folderName) {
    var next = _currentRemotePath;
    if (!next.endsWith('/')) next = '$next/';
    next = '$next$folderName';
    setState(() {
      _currentRemotePath = next;
    });
    _loadFiles();
  }

  void _navigateUp() {
    var path = _currentRemotePath;
    if (path.endsWith('/')) path = path.substring(0, path.length - 1);
    final lastSlash = path.lastIndexOf('/');
    if (lastSlash != -1) {
      path = path.substring(0, lastSlash + 1);
    } else {
      path = '/';
    }
    if (path.isEmpty) path = '/';
    setState(() {
      _currentRemotePath = path;
    });
    _loadFiles();
  }

  Future<void> _downloadFile(CloudFileItem item) async {
    final state = Provider.of<AppState>(context, listen: false);
    final account = state.activeCloudAccount;
    if (account == null) return;

    String downloadDir;
    try {
      if (Platform.isAndroid) {
        final dir = await getExternalStorageDirectory();
        downloadDir = dir?.path ?? (await getApplicationDocumentsDirectory()).path;
      } else {
        final dir = await getDownloadsDirectory();
        downloadDir = dir?.path ?? (await getApplicationDocumentsDirectory()).path;
      }
    } catch (_) {
      downloadDir = (await getApplicationDocumentsDirectory()).path;
    }

    final localPath = p.join(downloadDir, item.name);

    setState(() {
      _downloadProgress[item.path] = 0.01;
    });

    try {
      await _cloudService.downloadFile(
        account: account,
        remotePath: item.path,
        localSavePath: localPath,
        onProgress: (prog, _, __) {
          if (mounted) {
            setState(() {
              _downloadProgress[item.path] = prog;
            });
          }
        },
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Heruntergeladen: ${item.name}'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fehler beim Download: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _downloadProgress.remove(item.path);
        });
      }
    }
  }

  Future<void> _uploadFilesToCurrentDirectory() async {
    final state = Provider.of<AppState>(context, listen: false);
    final account = state.activeCloudAccount;
    if (account == null) return;

    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null || result.files.isEmpty) return;

    final files = result.files
        .where((f) => f.path != null)
        .map((f) => File(f.path!))
        .toList();

    if (files.isEmpty) return;

    await state.uploadFilesToCloud(
      account: account,
      files: files,
      remotePath: _currentRemotePath,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${files.length} Datei(en) werden in die Cloud hochgeladen...'),
      ),
    );
    await Future.delayed(const Duration(seconds: 1));
    _loadFiles();
  }

  Future<void> _createNewFolderDialog() async {
    final state = Provider.of<AppState>(context, listen: false);
    final account = state.activeCloudAccount;
    if (account == null) return;

    final folderController = TextEditingController();

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Neuen Ordner erstellen'),
        content: TextField(
          controller: folderController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Ordnername',
            hintText: 'z.B. Dokumente',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Erstellen'),
          ),
        ],
      ),
    );

    if (created == true && folderController.text.trim().isNotEmpty) {
      final name = folderController.text.trim();
      var targetPath = _currentRemotePath;
      if (!targetPath.endsWith('/')) targetPath = '$targetPath/';
      targetPath = '$targetPath$name';

      final success = await _cloudService.createDirectory(account, targetPath);
      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ordner "$name" erfolgreich erstellt.')),
        );
        _loadFiles();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fehler beim Erstellen des Ordners.'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _showAddAccountDialog({CloudAccount? editAccount}) async {
    final state = Provider.of<AppState>(context, listen: false);

    final nameController = TextEditingController(text: editAccount?.name ?? 'Nextcloud');
    final urlController = TextEditingController(text: editAccount?.serverUrl ?? '');
    final userController = TextEditingController(text: editAccount?.username ?? '');
    final passController = TextEditingController(text: editAccount?.password ?? '');
    final pathController = TextEditingController(text: editAccount?.remoteBasePath ?? '/');

    bool isTesting = false;
    Map<String, dynamic>? testResult;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              title: Text(editAccount == null ? 'Cloud-Konto verbinden' : 'Konto bearbeiten'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Bezeichnung',
                        hintText: 'z.B. Nextcloud Privat',
                        prefixIcon: Icon(Icons.label_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: urlController,
                      decoration: const InputDecoration(
                        labelText: 'Server-Adresse (IP oder Domain)',
                        hintText: 'z.B. 192.168.178.50 oder cloud.meinedomain.de',
                        prefixIcon: Icon(Icons.dns_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: userController,
                      decoration: const InputDecoration(
                        labelText: 'Benutzername',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Passwort oder App-Token',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: pathController,
                      decoration: const InputDecoration(
                        labelText: 'Basis-Pfad (WebDAV)',
                        hintText: '/',
                        prefixIcon: Icon(Icons.folder_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (testResult != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: testResult!['success'] == true
                              ? Colors.green.withOpacity(0.15)
                              : Colors.red.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: testResult!['success'] == true
                                ? Colors.green.withOpacity(0.4)
                                : Colors.red.withOpacity(0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              testResult!['success'] == true
                                  ? Icons.check_circle_outline
                                  : Icons.error_outline,
                              color: testResult!['success'] == true ? Colors.green : Colors.red,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                testResult!['message'] ?? '',
                                style: TextStyle(
                                  color: testResult!['success'] == true ? Colors.green[800] : Colors.red[800],
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    OutlinedButton.icon(
                      icon: isTesting
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.network_check),
                      label: const Text('Verbindung testen'),
                      onPressed: isTesting
                          ? null
                          : () async {
                              final temp = CloudAccount(
                                id: 'test',
                                name: nameController.text.trim(),
                                serverUrl: urlController.text.trim(),
                                username: userController.text.trim(),
                                password: passController.text.trim(),
                                remoteBasePath: pathController.text.trim().isEmpty ? '/' : pathController.text.trim(),
                              );
                              setDialogState(() {
                                isTesting = true;
                                testResult = null;
                              });
                              final res = await _cloudService.testConnection(temp);
                              setDialogState(() {
                                isTesting = false;
                                testResult = res;
                              });
                            },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Abbrechen'),
                ),
                FilledButton(
                  onPressed: () async {
                    if (urlController.text.trim().isEmpty ||
                        userController.text.trim().isEmpty ||
                        passController.text.trim().isEmpty) {
                      return;
                    }
                    final acc = CloudAccount(
                      id: editAccount?.id ?? const Uuid().v4(),
                      name: nameController.text.trim().isEmpty ? 'Nextcloud' : nameController.text.trim(),
                      serverUrl: urlController.text.trim(),
                      username: userController.text.trim(),
                      password: passController.text.trim(),
                      remoteBasePath: pathController.text.trim().isEmpty ? '/' : pathController.text.trim(),
                    );
                    await state.saveCloudAccount(acc);
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                    }
                    _currentRemotePath = acc.remoteBasePath;
                    _loadFiles();
                  },
                  child: const Text('Speichern'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<AppState>();
    final activeAccount = state.activeCloudAccount;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.cloud_sync, color: Colors.teal),
            const SizedBox(width: 10),
            const Text('Cloud-Sync'),
            if (activeAccount != null) ...[
              const SizedBox(width: 8),
              Chip(
                label: Text(activeAccount.name, style: const TextStyle(fontSize: 11)),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ],
        ),
        actions: [
          if (state.cloudAccounts.isNotEmpty) ...[
            PopupMenuButton<String>(
              icon: const Icon(Icons.switch_account_outlined),
              tooltip: 'Konto wechseln / verwalten',
              onSelected: (val) {
                if (val == 'add') {
                  _showAddAccountDialog();
                } else if (val == 'edit' && activeAccount != null) {
                  _showAddAccountDialog(editAccount: activeAccount);
                } else if (val == 'delete' && activeAccount != null) {
                  state.removeCloudAccount(activeAccount.id);
                  if (state.activeCloudAccount != null) {
                    _currentRemotePath = state.activeCloudAccount!.remoteBasePath;
                    _loadFiles();
                  }
                } else {
                  final target = state.cloudAccounts.firstWhere((a) => a.id == val);
                  state.setActiveCloudAccount(target);
                  _currentRemotePath = target.remoteBasePath;
                  _loadFiles();
                }
              },
              itemBuilder: (ctx) => [
                ...state.cloudAccounts.map((acc) => PopupMenuItem(
                      value: acc.id,
                      child: Row(
                        children: [
                          Icon(
                            acc.id == activeAccount?.id ? Icons.check : Icons.cloud_outlined,
                            color: acc.id == activeAccount?.id ? Colors.teal : null,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(acc.name, overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    )),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'add',
                  child: Row(
                    children: [
                      Icon(Icons.add, size: 20),
                      SizedBox(width: 8),
                      Text('Neues Konto hinzufügen'),
                    ],
                  ),
                ),
                if (activeAccount != null) ...[
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 20),
                        SizedBox(width: 8),
                        Text('Aktuelles Konto bearbeiten'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, color: Colors.red, size: 20),
                        SizedBox(width: 8),
                        Text('Konto löschen', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ],
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Aktualisieren',
            onPressed: activeAccount != null ? _loadFiles : null,
          ),
        ],
      ),
      body: activeAccount == null
          ? _buildNoAccountView(theme)
          : Column(
              children: [
                _buildPathBar(theme),
                Expanded(
                  child: _isLoadingFiles
                      ? const Center(child: CircularProgressIndicator())
                      : _filesError != null
                          ? _buildErrorView(theme)
                          : _buildFileList(theme),
                ),
              ],
            ),
      floatingActionButton: activeAccount != null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: 'new_folder',
                  onPressed: _createNewFolderDialog,
                  tooltip: 'Neuer Ordner',
                  child: const Icon(Icons.create_new_folder_outlined),
                ),
                const SizedBox(height: 12),
                FloatingActionButton.extended(
                  heroTag: 'upload_cloud',
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Hochladen'),
                  onPressed: _uploadFilesToCurrentDirectory,
                ),
              ],
            )
          : null,
    );
  }

  Widget _buildNoAccountView(ThemeData theme) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(28.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.teal.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.cloud_sync, size: 54, color: Colors.teal),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Cloud-Synchronisation',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Verbinden Sie Ihre persönliche Nextcloud oder einen beliebigen WebDAV-Server, um Dateien direkt zwischen all Ihren Geräten und Ihrer Cloud auszutauschen.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey, height: 1.4),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  icon: const Icon(Icons.add_link),
                  label: const Text('Nextcloud / WebDAV verbinden'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  ),
                  onPressed: () => _showAddAccountDialog(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPathBar(ThemeData theme) {
    final canGoUp = _currentRemotePath != '/' && _currentRemotePath.isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_upward),
            tooltip: 'Übergeordneter Ordner',
            onPressed: canGoUp ? _navigateUp : null,
          ),
          const SizedBox(width: 8),
          const Icon(Icons.folder_open, size: 20, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _currentRemotePath,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(
              'Fehler beim Laden',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              _filesError ?? 'Unbekannter Fehler',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: _loadFiles,
              child: const Text('Erneut versuchen'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileList(ThemeData theme) {
    if (_files.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open_outlined, size: 48, color: Colors.grey.withOpacity(0.5)),
            const SizedBox(height: 12),
            const Text('Dieser Ordner ist leer.', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _files.length,
      padding: const EdgeInsets.only(bottom: 88),
      itemBuilder: (ctx, index) {
        final item = _files[index];
        final isDownloading = _downloadProgress.containsKey(item.path);
        final downloadProg = _downloadProgress[item.path] ?? 0.0;

        return ListTile(
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: item.isDirectory
                  ? theme.colorScheme.primaryContainer.withOpacity(0.4)
                  : theme.colorScheme.surfaceVariant.withOpacity(0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              item.isDirectory ? Icons.folder : Icons.insert_drive_file,
              color: item.isDirectory ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: isDownloading
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    LinearProgressIndicator(value: downloadProg > 0 ? downloadProg : null),
                    const SizedBox(height: 2),
                    Text(
                      'Download: ${(downloadProg * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                )
              : Text(
                  item.isDirectory ? 'Ordner' : item.formattedSize,
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                ),
          trailing: item.isDirectory
              ? const Icon(Icons.chevron_right)
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: isDownloading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download_outlined),
                      tooltip: 'Herunterladen',
                      onPressed: isDownloading ? null : () => _downloadFile(item),
                    ),
                  ],
                ),
          onTap: () {
            if (item.isDirectory) {
              _navigateInto(item.name);
            } else {
              _downloadFile(item);
            }
          },
        );
      },
    );
  }
}
