import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/cloud_account.dart';
import '../services/app_state.dart';
import '../services/cloud_service.dart';
import 'send_file_screen.dart';

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

  void _navigateInto(CloudFileItem item) {
    if (item.isDirectory) {
      var next = _currentRemotePath;
      if (!next.endsWith('/')) next = '$next/';
      next = '$next${item.name}';
      setState(() {
        _currentRemotePath = next;
      });
      _loadFiles();
    }
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

  Future<String> _getLocalSavePath(String filename) async {
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
    return p.join(downloadDir, filename);
  }

  Future<File?> _downloadFile(CloudFileItem item, {bool openAfterDownload = false}) async {
    final state = Provider.of<AppState>(context, listen: false);
    final account = state.activeCloudAccount;
    if (account == null) return null;

    final localPath = await _getLocalSavePath(item.name);

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

      final file = File(localPath);

      if (!mounted) return file;

      if (openAfterDownload) {
        await OpenFilex.open(localPath);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Heruntergeladen: ${item.name}'),
            backgroundColor: Colors.green,
            action: SnackBarAction(
              label: 'Öffnen',
              textColor: Colors.white,
              onPressed: () => OpenFilex.open(localPath),
            ),
          ),
        );
      }
      return file;
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fehler beim Download: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _downloadProgress.remove(item.path);
        });
      }
    }
  }

  // ==========================================
  // In-App File Viewers & Previews
  // ==========================================

  void _openOrPreviewFile(CloudFileItem item) {
    if (item.isDirectory) {
      _navigateInto(item);
    } else if (item.isImage) {
      _showImagePreviewDialog(item);
    } else if (item.isText) {
      _showTextPreviewDialog(item);
    } else {
      // PDF or other documents -> download and open with system viewer
      _downloadFile(item, openAfterDownload: true);
    }
  }

  Future<void> _showImagePreviewDialog(CloudFileItem item) async {
    final state = Provider.of<AppState>(context, listen: false);
    final account = state.activeCloudAccount;
    if (account == null) return;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.black.withOpacity(0.92),
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header Bar
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      color: Colors.black87,
                      child: Row(
                        children: [
                          const Icon(Icons.image, color: Colors.tealAccent, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  item.formattedSize,
                                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.download_rounded, color: Colors.white),
                            tooltip: 'Herunterladen',
                            onPressed: () {
                              Navigator.pop(ctx);
                              _downloadFile(item);
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            tooltip: 'Schließen',
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),
                    // Image Viewer Container
                    Flexible(
                      child: Container(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.7,
                          maxWidth: MediaQuery.of(context).size.width * 0.9,
                        ),
                        child: FutureBuilder<Uint8List>(
                          future: _cloudService.getFileBytes(account, item.path),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(40.0),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      CircularProgressIndicator(color: Colors.tealAccent),
                                      SizedBox(height: 16),
                                      Text('Bild wird geladen...', style: TextStyle(color: Colors.white70)),
                                    ],
                                  ),
                                ),
                              );
                            }
                            if (snapshot.hasError) {
                              return Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24.0),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.broken_image, color: Colors.redAccent, size: 48),
                                      const SizedBox(height: 12),
                                      Text('Fehler beim Laden: ${snapshot.error}', style: const TextStyle(color: Colors.white70)),
                                    ],
                                  ),
                                ),
                              );
                            }
                            final bytes = snapshot.data!;
                            return InteractiveViewer(
                              minScale: 0.5,
                              maxScale: 4.0,
                              child: Image.memory(
                                bytes,
                                fit: BoxFit.contain,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showTextPreviewDialog(CloudFileItem item) async {
    final state = Provider.of<AppState>(context, listen: false);
    final account = state.activeCloudAccount;
    if (account == null) return;

    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppBar(
                  title: Text(item.name, style: const TextStyle(fontSize: 16)),
                  automaticallyImplyLeading: false,
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.download_rounded),
                      tooltip: 'Herunterladen',
                      onPressed: () {
                        Navigator.pop(ctx);
                        _downloadFile(item);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                Flexible(
                  child: Container(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.7,
                    ),
                    padding: const EdgeInsets.all(16),
                    child: FutureBuilder<Uint8List>(
                      future: _cloudService.getFileBytes(account, item.path),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (snapshot.hasError) {
                          return Center(child: Text('Fehler: ${snapshot.error}'));
                        }
                        final text = utf8.decode(snapshot.data!, allowMalformed: true);
                        return SingleChildScrollView(
                          child: SelectableText(
                            text,
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.4),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _shareFileToDevice(CloudFileItem item) async {
    final downloaded = await _downloadFile(item);
    if (downloaded != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SendFileScreen(preselectedFile: downloaded),
        ),
      );
    }
  }

  Future<void> _deleteItemDialog(CloudFileItem item) async {
    final state = Provider.of<AppState>(context, listen: false);
    final account = state.activeCloudAccount;
    if (account == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${item.isDirectory ? 'Ordner' : 'Datei'} löschen?'),
        content: Text('Möchten Sie "${item.name}" wirklich aus der Cloud löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await _cloudService.deleteItem(account, item.path);
      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${item.name}" gelöscht.')),
        );
        _loadFiles();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fehler beim Löschen.'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ==========================================
  // Cloud Actions (Upload & Create Folder)
  // ==========================================

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

  // ==========================================
  // Add / Edit Account Dialog (Nextcloud & Google Drive)
  // ==========================================

  Future<void> _showAddAccountDialog({CloudAccount? editAccount}) async {
    final state = Provider.of<AppState>(context, listen: false);

    CloudProviderType selectedType = editAccount?.type ?? CloudProviderType.nextcloud;
    final nameController = TextEditingController(text: editAccount?.name ?? 'Nextcloud');
    final urlController = TextEditingController(text: editAccount?.serverUrl ?? '');
    final userController = TextEditingController(text: editAccount?.username ?? '');
    final passController = TextEditingController(text: editAccount?.password ?? '');
    final pathController = TextEditingController(text: editAccount?.remoteBasePath ?? '/');
    final tokenController = TextEditingController(text: editAccount?.accessToken ?? '');

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
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Provider Selector
                    SegmentedButton<CloudProviderType>(
                      segments: const [
                        ButtonSegment(
                          value: CloudProviderType.nextcloud,
                          icon: Icon(Icons.cloud_outlined),
                          label: Text('Nextcloud'),
                        ),
                        ButtonSegment(
                          value: CloudProviderType.googleDrive,
                          icon: Icon(Icons.add_to_drive),
                          label: Text('Google Drive'),
                        ),
                        ButtonSegment(
                          value: CloudProviderType.webdav,
                          icon: Icon(Icons.dns_outlined),
                          label: Text('WebDAV'),
                        ),
                      ],
                      selected: {selectedType},
                      onSelectionChanged: (Set<CloudProviderType> newSelection) {
                        setDialogState(() {
                          selectedType = newSelection.first;
                          if (selectedType == CloudProviderType.googleDrive && nameController.text == 'Nextcloud') {
                            nameController.text = 'Google Drive';
                          } else if (selectedType == CloudProviderType.nextcloud && nameController.text == 'Google Drive') {
                            nameController.text = 'Nextcloud';
                          }
                          testResult = null;
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Bezeichnung',
                        hintText: 'z.B. Meine Cloud',
                        prefixIcon: Icon(Icons.label_outline),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),

                    if (selectedType == CloudProviderType.googleDrive) ...[
                      // Google Drive Configuration
                      TextField(
                        controller: userController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Google E-Mail-Adresse',
                          hintText: 'z.B. meinaccount@gmail.com',
                          prefixIcon: Icon(Icons.mail_outline),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: tokenController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Google OAuth Access Token',
                          hintText: 'ya29.a0...',
                          prefixIcon: Icon(Icons.key),
                          border: OutlineInputBorder(),
                          helperText: 'Token mit Google Drive Scope (drive.file / drive.readonly)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.blue.withOpacity(0.25)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.blue, size: 20),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Verbinden Sie Ihr Google-Konto direkt über Ihren Google OAuth-Token für nativen Zugriff auf Google Drive.',
                                style: TextStyle(fontSize: 12, height: 1.3),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      // Nextcloud / WebDAV Configuration
                      TextField(
                        controller: urlController,
                        decoration: InputDecoration(
                          labelText: 'Server-Adresse (IP oder Domain)',
                          hintText: selectedType == CloudProviderType.nextcloud
                              ? 'z.B. 192.168.178.50 oder cloud.meinedomain.de'
                              : 'z.B. https://webdav.server.de',
                          prefixIcon: const Icon(Icons.dns_outlined),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: userController,
                        decoration: const InputDecoration(
                          labelText: 'Benutzername',
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: passController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Passwort oder App-Token',
                          prefixIcon: Icon(Icons.lock_outline),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: pathController,
                        decoration: const InputDecoration(
                          labelText: 'Basis-Pfad (WebDAV)',
                          hintText: '/',
                          prefixIcon: Icon(Icons.folder_outlined),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],

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
                                type: selectedType,
                                serverUrl: selectedType == CloudProviderType.googleDrive
                                    ? 'https://www.googleapis.com'
                                    : urlController.text.trim(),
                                username: userController.text.trim(),
                                password: passController.text.trim(),
                                remoteBasePath: pathController.text.trim().isEmpty ? '/' : pathController.text.trim(),
                                accessToken: tokenController.text.trim(),
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
                    if (selectedType == CloudProviderType.googleDrive) {
                      if (userController.text.trim().isEmpty || tokenController.text.trim().isEmpty) {
                        return;
                      }
                    } else {
                      if (urlController.text.trim().isEmpty ||
                          userController.text.trim().isEmpty ||
                          passController.text.trim().isEmpty) {
                        return;
                      }
                    }

                    final acc = CloudAccount(
                      id: editAccount?.id ?? const Uuid().v4(),
                      name: nameController.text.trim().isEmpty
                          ? (selectedType == CloudProviderType.googleDrive ? 'Google Drive' : 'Nextcloud')
                          : nameController.text.trim(),
                      type: selectedType,
                      serverUrl: selectedType == CloudProviderType.googleDrive
                          ? 'https://www.googleapis.com'
                          : urlController.text.trim(),
                      username: userController.text.trim(),
                      password: passController.text.trim(),
                      remoteBasePath: pathController.text.trim().isEmpty ? '/' : pathController.text.trim(),
                      accessToken: tokenController.text.trim().isNotEmpty ? tokenController.text.trim() : null,
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
            Icon(
              activeAccount?.type == CloudProviderType.googleDrive ? Icons.add_to_drive : Icons.cloud_sync,
              color: Colors.teal,
            ),
            const SizedBox(width: 10),
            Text(activeAccount?.type == CloudProviderType.googleDrive ? 'Google Drive' : 'Cloud-Sync'),
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
                            acc.id == activeAccount?.id ? Icons.check : (acc.type == CloudProviderType.googleDrive ? Icons.add_to_drive : Icons.cloud_outlined),
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
                  'Verbinden Sie Ihre Nextcloud, Ihr Google Drive oder einen beliebigen WebDAV-Server, um Dateien direkt zwischen all Ihren Geräten und Ihrer Cloud auszutauschen.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey, height: 1.4),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  icon: const Icon(Icons.add_link),
                  label: const Text('Cloud-Konto verbinden'),
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

        IconData fileIcon;
        if (item.isDirectory) {
          fileIcon = Icons.folder;
        } else if (item.isImage) {
          fileIcon = Icons.image;
        } else if (item.isText) {
          fileIcon = Icons.description;
        } else if (item.isPdf) {
          fileIcon = Icons.picture_as_pdf;
        } else {
          fileIcon = Icons.insert_drive_file;
        }

        return ListTile(
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: item.isDirectory
                  ? theme.colorScheme.primaryContainer.withOpacity(0.4)
                  : (item.isImage ? Colors.purple.withOpacity(0.12) : theme.colorScheme.surfaceVariant.withOpacity(0.5)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              fileIcon,
              color: item.isDirectory
                  ? theme.colorScheme.primary
                  : (item.isImage ? Colors.purple : theme.colorScheme.onSurfaceVariant),
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
                    // Preview / View eye button for instant viewing
                    IconButton(
                      icon: const Icon(Icons.visibility_outlined),
                      tooltip: item.isImage ? 'Bild anzeigen' : (item.isText ? 'Text ansehen' : 'Öffnen'),
                      onPressed: () => _openOrPreviewFile(item),
                    ),
                    // Download button
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
                    // More options popup
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, size: 20),
                      onSelected: (val) {
                        if (val == 'view') {
                          _openOrPreviewFile(item);
                        } else if (val == 'download') {
                          _downloadFile(item);
                        } else if (val == 'share') {
                          _shareFileToDevice(item);
                        } else if (val == 'delete') {
                          _deleteItemDialog(item);
                        }
                      },
                      itemBuilder: (c) => [
                        PopupMenuItem(
                          value: 'view',
                          child: Row(
                            children: [
                              const Icon(Icons.visibility_outlined, size: 18),
                              const SizedBox(width: 8),
                              Text(item.isImage ? 'Bild ansehen' : 'Vorschau / Öffnen'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'download',
                          child: Row(
                            children: [
                              Icon(Icons.download_outlined, size: 18),
                              SizedBox(width: 8),
                              Text('In Downloads speichern'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'share',
                          child: Row(
                            children: [
                              Icon(Icons.send_outlined, size: 18),
                              SizedBox(width: 8),
                              Text('Per CrossDrop an Gerät senden'),
                            ],
                          ),
                        ),
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline, color: Colors.red, size: 18),
                              SizedBox(width: 8),
                              Text('Löschen', style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
          onTap: () => _openOrPreviewFile(item),
        );
      },
    );
  }
}
