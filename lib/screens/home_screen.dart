import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/cloud_provider.dart';
import '../models/cloud_file.dart';
import '../services/share_link_service.dart';
import 'file_viewer_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'webhooks_screen.dart';
import 'sync_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _selectionMode = false;
  final Set<String> _selectedFiles = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      drawer: _buildDrawer(),
      body: Column(
        children: [
          _buildProgressBar(),
          _buildToolbar(),
          _buildBreadcrumb(),
          Expanded(child: _buildFileList()),
          _buildStatusBar(),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    return Consumer<CloudProvider>(
      builder: (context, provider, _) {
        return Drawer(
          child: Column(
            children: [
              DrawerHeader(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.cloud, size: 48, color: Colors.white),
                    const SizedBox(height: 8),
                    const Text('DisCloud', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                    Text('${provider.webhooks.length} webhooks', style: const TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
              // Webhooks list
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Text('WEBHOOKS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                    ),
                    ...provider.webhooks.map((webhook) {
                      final isSelected = webhook.id == provider.currentWebhookId;
                      return ListTile(
                        leading: Icon(
                          Icons.webhook,
                          color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey,
                        ),
                        title: Text(webhook.name),
                        subtitle: Text('${webhook.fileCount} files', style: const TextStyle(fontSize: 11)),
                        selected: isSelected,
                        trailing: isSelected ? const Icon(Icons.check, color: Colors.green) : null,
                        onTap: () {
                          provider.selectWebhook(webhook.id);
                          Navigator.pop(context);
                        },
                      );
                    }),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.add),
                      title: const Text('Add Webhook'),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const WebhooksScreen()));
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.manage_accounts),
                      title: const Text('Manage Webhooks'),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const WebhooksScreen()));
                      },
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.sync),
                      title: const Text('Auto Sync'),
                      subtitle: Text(provider.settings['autoSyncEnabled'] == true ? 'Enabled' : 'Disabled', style: const TextStyle(fontSize: 11)),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const SyncScreen()));
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.settings),
                      title: const Text('Settings'),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final provider = context.watch<CloudProvider>();
    
    if (_selectionMode) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => setState(() {
            _selectionMode = false;
            _selectedFiles.clear();
          }),
        ),
        title: Text('${_selectedFiles.length} selected'),
        actions: [
          IconButton(icon: const Icon(Icons.select_all), onPressed: _selectAll, tooltip: 'Select all'),
          IconButton(icon: const Icon(Icons.download), onPressed: _selectedFiles.isEmpty ? null : _downloadSelected, tooltip: 'Download'),
          IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: _selectedFiles.isEmpty ? null : _deleteSelected, tooltip: 'Delete'),
        ],
      );
    }

    return AppBar(
      title: Row(
        children: [
          const Text('DisCloud'),
          if (provider.currentWebhook != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                provider.currentWebhook!.name,
                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.primary),
              ),
            ),
          ],
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())),
          tooltip: 'Search',
        ),
        IconButton(
          icon: const Icon(Icons.webhook),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WebhooksScreen())),
          tooltip: 'Webhooks',
        ),
      ],
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          _ToolbarButton(icon: Icons.upload_file, label: 'Upload', onPressed: _uploadFile),
          _ToolbarButton(icon: Icons.create_new_folder, label: 'New Folder', onPressed: _createFolder),
          _ToolbarButton(icon: Icons.link, label: 'From URL', onPressed: _uploadFromUrl),
          const VerticalDivider(width: 16),
          _ToolbarButton(icon: Icons.checklist, label: 'Select', onPressed: () => setState(() => _selectionMode = true)),
          _ToolbarButton(icon: Icons.sync, label: 'Sync', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SyncScreen()))),
          const Spacer(),
          Consumer<CloudProvider>(
            builder: (context, provider, _) => Row(
              children: [
                _StatChip(icon: Icons.folder, value: '${provider.totalFolders}'),
                const SizedBox(width: 8),
                _StatChip(icon: Icons.insert_drive_file, value: '${provider.totalFiles}'),
                const SizedBox(width: 8),
                _StatChip(icon: Icons.storage, value: _formatSize(provider.totalSize)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    return Consumer<CloudProvider>(
      builder: (context, provider, _) {
        if (provider.status != CloudStatus.uploading &&
            provider.status != CloudStatus.downloading &&
            provider.status != CloudStatus.syncing) {
          return const SizedBox.shrink();
        }

        return Container(
          padding: const EdgeInsets.all(12),
          color: Colors.blue.withOpacity(0.1),
          child: Row(
            children: [
              SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, value: provider.progress > 0 ? provider.progress : null),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(provider.currentOperation ?? 'Working...', style: const TextStyle(fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(value: provider.progress, minHeight: 4),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text('${(provider.progress * 100).toInt()}%'),
              if (provider.canCancel)
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.red),
                  onPressed: () => provider.cancelCurrentOperation(),
                  tooltip: 'Cancel',
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBreadcrumb() {
    return Consumer<CloudProvider>(
      builder: (context, provider, _) {
        final parts = provider.currentPath.split('/').where((p) => p.isNotEmpty).toList();

        return Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          color: Theme.of(context).brightness == Brightness.dark ? Colors.black26 : Colors.grey.shade100,
          child: Row(
            children: [
              InkWell(
                onTap: () => provider.navigateTo('/'),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Row(children: [Icon(Icons.home, size: 16), SizedBox(width: 4), Text('Root')]),
                ),
              ),
              ...parts.asMap().entries.map((entry) {
                final path = '/${parts.sublist(0, entry.key + 1).join('/')}';
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.chevron_right, size: 16),
                    InkWell(
                      onTap: () => provider.navigateTo(path),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(entry.value),
                      ),
                    ),
                  ],
                );
              }),
              const Spacer(),
              Text('${provider.currentFiles.length} items', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFileList() {
    return Consumer<CloudProvider>(
      builder: (context, provider, _) {
        if (provider.currentFiles.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.folder_open, size: 64, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                const Text('Empty folder'),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _uploadFile,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Upload a file'),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          itemCount: provider.currentFiles.length,
          itemBuilder: (context, index) {
            final file = provider.currentFiles[index];
            final isSelected = _selectedFiles.contains(file.path);
            
            return _FileListItem(
              file: file,
              isSelected: isSelected,
              selectionMode: _selectionMode,
              onTap: () {
                if (_selectionMode) {
                  setState(() {
                    if (isSelected) _selectedFiles.remove(file.path);
                    else _selectedFiles.add(file.path);
                  });
                } else if (file.isDirectory) {
                  provider.navigateTo(file.path);
                } else {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => FileViewerScreen(file: file)));
                }
              },
              onLongPress: () {
                if (!_selectionMode) {
                  setState(() {
                    _selectionMode = true;
                    _selectedFiles.add(file.path);
                  });
                }
              },
              onDelete: () => _confirmDelete(file),
              onDownload: () => _downloadFile(file),
              onShare: () => _showShareDialog(file),
            );
          },
        );
      },
    );
  }

  Widget _buildStatusBar() {
    return Consumer<CloudProvider>(
      builder: (context, provider, _) {
        if (provider.errorMessage != null) {
          return Container(
            padding: const EdgeInsets.all(8),
            color: Colors.red.shade100,
            child: Row(
              children: [
                const Icon(Icons.error, color: Colors.red, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(provider.errorMessage!, style: const TextStyle(color: Colors.red))),
                IconButton(icon: const Icon(Icons.close, size: 16), onPressed: () => provider.clearError()),
              ],
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  // ========== ACTIONS ==========

  void _selectAll() {
    final provider = context.read<CloudProvider>();
    setState(() {
      if (_selectedFiles.length == provider.currentFiles.length) {
        _selectedFiles.clear();
      } else {
        _selectedFiles.clear();
        for (final file in provider.currentFiles) {
          _selectedFiles.add(file.path);
        }
      }
    });
  }

  Future<void> _uploadFile() async {
    final provider = context.read<CloudProvider>();
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null) return;

    for (final file in result.files) {
      if (file.bytes != null) {
        await provider.uploadFile(file.name, file.bytes!);
      } else if (file.path != null) {
        final bytes = await File(file.path!).readAsBytes();
        await provider.uploadFile(file.name, bytes);
      }
    }
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Folder name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Create')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      context.read<CloudProvider>().createFolder(name);
    }
  }

  Future<void> _uploadFromUrl() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Upload from URL'),
        content: TextField(controller: controller, decoration: const InputDecoration(hintText: 'https://...')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Upload')),
        ],
      ),
    );
    if (url != null && url.isNotEmpty) {
      context.read<CloudProvider>().uploadFromUrl(url);
    }
  }

  Future<void> _downloadSelected() async {
    final provider = context.read<CloudProvider>();
    final savePath = await FilePicker.platform.getDirectoryPath();
    if (savePath == null) return;

    for (final path in _selectedFiles.toList()) {
      final file = provider.currentFiles.firstWhere((f) => f.path == path);
      if (!file.isDirectory) {
        final data = await provider.downloadFile(file);
        if (data != null) {
          final outFile = File('$savePath/${file.name}');
          await outFile.writeAsBytes(data);
        }
      }
    }

    setState(() {
      _selectionMode = false;
      _selectedFiles.clear();
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Download complete!')));
    }
  }

  Future<void> _deleteSelected() async {
    final provider = context.read<CloudProvider>();
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete?'),
        content: Text('Delete ${_selectedFiles.length} items? Files will be removed from Discord.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      for (final path in _selectedFiles.toList()) {
        final file = provider.currentFiles.firstWhere((f) => f.path == path);
        await provider.deleteFile(file);
      }
      setState(() {
        _selectionMode = false;
        _selectedFiles.clear();
      });
    }
  }

  Future<void> _confirmDelete(CloudFile file) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${file.name}?'),
        content: const Text('This will also delete the file from Discord.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      context.read<CloudProvider>().deleteFile(file);
    }
  }

  Future<void> _downloadFile(CloudFile file) async {
    final savePath = await FilePicker.platform.getDirectoryPath();
    if (savePath == null) return;

    final provider = context.read<CloudProvider>();
    final data = await provider.downloadFile(file);
    if (data != null) {
      final outFile = File('$savePath/${file.name}');
      await outFile.writeAsBytes(data);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved to $savePath')));
      }
    }
  }

  void _showShareDialog(CloudFile file) {
    try {
      final link = ShareLinkService.generateShareLink(file);
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Share Link'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(4)),
                child: SelectableText(link, style: const TextStyle(fontSize: 10, fontFamily: 'monospace')),
              ),
              const SizedBox(height: 12),
              const Text('This link contains download URLs only, not your webhook.', style: TextStyle(fontSize: 12, color: Colors.green)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: link));
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Copied!')));
              },
              child: const Text('Copy'),
            ),
            ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }
}

// ========== WIDGETS ==========

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _ToolbarButton({required this.icon, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), minimumSize: Size.zero),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String value;

  const _StatChip({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 12), const SizedBox(width: 4), Text(value, style: const TextStyle(fontSize: 11))],
      ),
    );
  }
}

class _FileListItem extends StatelessWidget {
  final CloudFile file;
  final bool isSelected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onDelete;
  final VoidCallback onDownload;
  final VoidCallback onShare;

  const _FileListItem({
    required this.file,
    required this.isSelected,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
    required this.onDelete,
    required this.onDownload,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        dense: true,
        leading: selectionMode
            ? Checkbox(value: isSelected, onChanged: (_) => onTap())
            : Icon(file.isDirectory ? Icons.folder : _getFileIcon(file.extension), color: file.isDirectory ? Colors.amber : Colors.blueGrey, size: 32),
        title: Text(file.name, overflow: TextOverflow.ellipsis),
        subtitle: file.isDirectory
            ? null
            : Row(
                children: [
                  Text(file.formattedSize, style: const TextStyle(fontSize: 11)),
                  if (file.chunkCount > 1) ...[
                    const SizedBox(width: 8),
                    Text('${file.chunkCount} chunks', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  ],
                ],
              ),
        trailing: selectionMode
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!file.isDirectory) ...[
                    IconButton(icon: const Icon(Icons.download, size: 20), onPressed: onDownload, tooltip: 'Download'),
                    IconButton(icon: const Icon(Icons.share, size: 20), onPressed: onShare, tooltip: 'Share'),
                  ],
                  IconButton(icon: const Icon(Icons.delete, size: 20, color: Colors.red), onPressed: onDelete, tooltip: 'Delete'),
                ],
              ),
        selected: isSelected,
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }

  IconData _getFileIcon(String ext) {
    switch (ext) {
      case 'pdf': return Icons.picture_as_pdf;
      case 'doc': case 'docx': return Icons.description;
      case 'xls': case 'xlsx': return Icons.table_chart;
      case 'zip': case 'rar': case '7z': return Icons.archive;
      case 'jpg': case 'jpeg': case 'png': case 'gif': case 'webp': return Icons.image;
      case 'mp4': case 'avi': case 'mkv': case 'mov': return Icons.movie;
      case 'mp3': case 'wav': case 'ogg': case 'flac': return Icons.audiotrack;
      case 'js': case 'ts': case 'py': case 'dart': case 'java': return Icons.code;
      default: return Icons.insert_drive_file;
    }
  }
}
