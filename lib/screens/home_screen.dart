import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/cloud_provider.dart';
import '../models/cloud_file.dart';
import '../services/download_manager.dart';
import '../services/share_link_service.dart';
import 'file_viewer_screen.dart';
import 'sync_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'webhooks_screen.dart';
import 'downloads_screen.dart';

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
      appBar: _selectionMode ? _buildSelectionAppBar() : _buildNormalAppBar(),
      body: Column(
        children: [
          _buildProgressBar(),
          _buildBreadcrumb(),
          _buildQuickActions(),
          Expanded(child: _buildFileList()),
        ],
      ),
      floatingActionButton: _selectionMode ? null : _buildFAB(),
    );
  }

  PreferredSizeWidget _buildSelectionAppBar() {
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
        IconButton(
          icon: const Icon(Icons.select_all),
          onPressed: _selectAll,
          tooltip: 'Select all',
        ),
        IconButton(
          icon: const Icon(Icons.download),
          onPressed: _selectedFiles.isEmpty ? null : _downloadSelected,
          tooltip: 'Download',
        ),
        IconButton(
          icon: const Icon(Icons.share),
          onPressed: _selectedFiles.length == 1 ? _shareSelected : null,
          tooltip: 'Share link',
        ),
        IconButton(
          icon: const Icon(Icons.delete, color: Colors.red),
          onPressed: _selectedFiles.isEmpty ? null : _deleteSelected,
          tooltip: 'Delete',
        ),
      ],
    );
  }

  PreferredSizeWidget _buildNormalAppBar() {
    return AppBar(
      title: const Text('Discord Cloud'),
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          onPressed: () => Navigator.push(context, 
            MaterialPageRoute(builder: (_) => const SearchScreen())),
          tooltip: 'Search',
        ),
        Consumer<DownloadManager>(
          builder: (context, manager, _) {
            final activeCount = manager.activeDownloads.length + manager.pendingDownloads.length;
            return Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.download),
                  onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const DownloadsScreen())),
                  tooltip: 'Downloads',
                ),
                if (activeCount > 0)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: Text('$activeCount', 
                        style: const TextStyle(color: Colors.white, fontSize: 10)),
                    ),
                  ),
              ],
            );
          },
        ),
        PopupMenuButton<String>(
          onSelected: _handleMenu,
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'select', child: Row(children: [
              Icon(Icons.check_box_outlined, size: 20), SizedBox(width: 12), Text('Select')
            ])),
            PopupMenuItem(value: 'upload_url', child: Row(children: [
              Icon(Icons.link, size: 20), SizedBox(width: 12), Text('Upload from URL')
            ])),
            PopupMenuItem(value: 'import_link', child: Row(children: [
              Icon(Icons.download, size: 20), SizedBox(width: 12), Text('Import share link')
            ])),
            PopupMenuDivider(),
            PopupMenuItem(value: 'webhooks', child: Row(children: [
              Icon(Icons.webhook, size: 20), SizedBox(width: 12), Text('Webhooks')
            ])),
            PopupMenuItem(value: 'sync', child: Row(children: [
              Icon(Icons.sync, size: 20), SizedBox(width: 12), Text('Sync')
            ])),
            PopupMenuItem(value: 'settings', child: Row(children: [
              Icon(Icons.settings, size: 20), SizedBox(width: 12), Text('Settings')
            ])),
            PopupMenuDivider(),
            PopupMenuItem(value: 'delete_all', child: Row(children: [
              Icon(Icons.delete_sweep, size: 20, color: Colors.orange), 
              SizedBox(width: 12), 
              Text('Delete All Here', style: TextStyle(color: Colors.orange))
            ])),
          ],
        ),
      ],
    );
  }

  void _handleMenu(String value) async {
    final provider = context.read<CloudProvider>();
    
    switch (value) {
      case 'select':
        setState(() => _selectionMode = true);
        break;
      case 'upload_url':
        _uploadFromUrl();
        break;
      case 'import_link':
        _importShareLink();
        break;
      case 'webhooks':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const WebhooksScreen()));
        break;
      case 'sync':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const SyncScreen()));
        break;
      case 'settings':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
        break;
      case 'delete_all':
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete All?'),
            content: Text('Delete all ${provider.currentFiles.length} items?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete All'),
              ),
            ],
          ),
        );
        if (confirm == true) {
          final count = await provider.deleteAllInCurrentFolder();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Deleted $count items')),
            );
          }
        }
        break;
    }
  }

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

  void _downloadSelected() async {
    final provider = context.read<CloudProvider>();
    final manager = context.read<DownloadManager>();
    
    // Demander le dossier de destination
    String? savePath = await FilePicker.platform.getDirectoryPath();
    
    final selectedFiles = provider.currentFiles
        .where((f) => _selectedFiles.contains(f.path) && !f.isDirectory)
        .toList();

    manager.addMultipleToQueue(selectedFiles, savePath: savePath);
    
    setState(() {
      _selectionMode = false;
      _selectedFiles.clear();
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added ${selectedFiles.length} files to download queue'),
          action: SnackBarAction(
            label: 'View',
            onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const DownloadsScreen())),
          ),
        ),
      );
    }
  }

  void _shareSelected() {
    final provider = context.read<CloudProvider>();
    final file = provider.currentFiles.firstWhere(
      (f) => _selectedFiles.contains(f.path),
    );

    _showShareDialog(file);
  }

  void _showShareDialog(CloudFile file) async {
    try {
      final link = ShareLinkService.generateShareLink(file);
      final textFormat = ShareLinkService.generateTextFormat(file);

      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.share, color: Colors.blue),
              const SizedBox(width: 8),
              Expanded(child: Text('Share ${file.name}')),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Share Link:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: SelectableText(
                    link,
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: link));
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('Link copied!')),
                          );
                        },
                        icon: const Icon(Icons.copy),
                        label: const Text('Copy Link'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: textFormat));
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('Text format copied!')),
                          );
                        },
                        icon: const Icon(Icons.text_snippet),
                        label: const Text('Copy Text'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info, color: Colors.blue, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This link is safe to share. It only contains download URLs, NOT your webhook.',
                          style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }

    setState(() {
      _selectionMode = false;
      _selectedFiles.clear();
    });
  }

  void _deleteSelected() async {
    final provider = context.read<CloudProvider>();
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete selected?'),
        content: Text('Delete ${_selectedFiles.length} items?'),
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
        if (file.isDirectory) {
          await provider.deleteFolderRecursive(file);
        } else {
          await provider.deleteFile(file);
        }
      }

      setState(() {
        _selectionMode = false;
        _selectedFiles.clear();
      });
    }
  }

  void _importShareLink() async {
    final controller = TextEditingController();
    
    final link = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.link, color: Colors.blue),
            SizedBox(width: 8),
            Text('Import Share Link'),
          ],
        ),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'discloud://...',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Import'),
          ),
        ],
      ),
    );

    if (link != null && link.isNotEmpty) {
      final data = ShareLinkService.parseShareLink(link);
      if (data != null) {
        _showImportConfirmDialog(data);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid share link'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showImportConfirmDialog(ShareLinkData data) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Download File'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: const Icon(Icons.insert_drive_file),
              title: Text(data.fileName),
              subtitle: Text('${data.formattedSize} - ${data.chunkUrls.length} chunks'),
            ),
            if (data.isEncrypted)
              const ListTile(
                leading: Icon(Icons.lock, color: Colors.green),
                title: Text('Encrypted'),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Download'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // TODO: Implementer le telechargement depuis ShareLinkData
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Downloading ${data.fileName}...')),
      );
    }
  }

  Widget _buildProgressBar() {
    return Consumer<CloudProvider>(
      builder: (context, provider, _) {
        if (provider.status != CloudStatus.uploading &&
            provider.status != CloudStatus.downloading) {
          return const SizedBox.shrink();
        }

        return Container(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(provider.status == CloudStatus.uploading ? Icons.upload : Icons.download, size: 16),
                  const SizedBox(width: 8),
                  Text(provider.status == CloudStatus.uploading ? 'Uploading...' : 'Downloading...'),
                  const Spacer(),
                  Text('${(provider.progress * 100).toInt()}%'),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: provider.progress, minHeight: 6),
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
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: isDark ? Colors.black12 : Colors.grey.shade100,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              TextButton.icon(
                onPressed: () => provider.navigateTo('/'),
                icon: const Icon(Icons.home, size: 18),
                label: const Text('Home'),
              ),
              ...parts.asMap().entries.map((entry) {
                final path = '/${parts.sublist(0, entry.key + 1).join('/')}';
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.chevron_right, size: 18),
                    TextButton(
                      onPressed: () => provider.navigateTo(path),
                      child: Text(entry.value),
                    ),
                  ],
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuickActions() {
    return Consumer<CloudProvider>(
      builder: (context, provider, _) {
        if (provider.currentPath == '/') return const SizedBox.shrink();
        
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Text('${provider.currentFiles.length} items',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => provider.navigateUp(),
                icon: const Icon(Icons.arrow_upward, size: 16),
                label: const Text('Up'),
              ),
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
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          itemCount: provider.currentFiles.length,
          itemBuilder: (context, index) {
            final file = provider.currentFiles[index];
            final isSelected = _selectedFiles.contains(file.path);
            
            return _FileItem(
              file: file,
              isSelected: isSelected,
              selectionMode: _selectionMode,
              onTap: () {
                if (_selectionMode) {
                  setState(() {
                    if (isSelected) {
                      _selectedFiles.remove(file.path);
                    } else {
                      _selectedFiles.add(file.path);
                    }
                  });
                } else {
                  _handleFileTap(file, provider);
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
              onShare: () => _showShareDialog(file),
            );
          },
        );
      },
    );
  }

  void _handleFileTap(CloudFile file, CloudProvider provider) {
    if (file.isDirectory) {
      provider.navigateTo(file.path);
    } else {
      Navigator.push(context,
        MaterialPageRoute(builder: (_) => FileViewerScreen(file: file)));
    }
  }

  Widget _buildFAB() {
    return Consumer<CloudProvider>(
      builder: (context, provider, _) {
        final isWorking = provider.status == CloudStatus.uploading ||
            provider.status == CloudStatus.downloading;

        return FloatingActionButton(
          onPressed: isWorking ? null : _showAddMenu,
          child: isWorking 
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.add),
        );
      },
    );
  }

  void _showAddMenu() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('Upload File'),
              onTap: () { Navigator.pop(ctx); _uploadFile(); },
            ),
            ListTile(
              leading: const Icon(Icons.create_new_folder),
              title: const Text('New Folder'),
              onTap: () { Navigator.pop(ctx); _createFolder(); },
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Upload from URL'),
              onTap: () { Navigator.pop(ctx); _uploadFromUrl(); },
            ),
          ],
        ),
      ),
    );
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
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      context.read<CloudProvider>().createFolder(name);
    }
  }

  Future<void> _uploadFromUrl() async {
    final controller = TextEditingController();
    final nameController = TextEditingController();
    
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Upload from URL'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'URL',
                hintText: 'https://example.com/file.zip',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'File name (optional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, {
              'url': controller.text,
              'name': nameController.text,
            }),
            child: const Text('Upload'),
          ),
        ],
      ),
    );

    if (result != null && result['url']!.isNotEmpty) {
      context.read<CloudProvider>().uploadFromUrl(
        result['url']!,
        customName: result['name']!.isEmpty ? null : result['name'],
      );
    }
  }
}

class _FileItem extends StatelessWidget {
  final CloudFile file;
  final bool isSelected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onShare;

  const _FileItem({
    required this.file,
    required this.isSelected,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: selectionMode
          ? Checkbox(
              value: isSelected,
              onChanged: (_) => onTap(),
            )
          : Icon(
              file.isDirectory ? Icons.folder : _getFileIcon(file.extension),
              color: file.isDirectory ? Colors.amber : Colors.blueGrey,
            ),
      title: Text(file.name, overflow: TextOverflow.ellipsis),
      subtitle: file.isDirectory 
          ? null 
          : Text(file.formattedSize, style: const TextStyle(fontSize: 12)),
      trailing: selectionMode
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!file.isDirectory && file.webhookChunks.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.share, size: 20),
                    onPressed: onShare,
                    tooltip: 'Share',
                  ),
                if (file.webhookCount > 1)
                  Chip(
                    label: Text('${file.webhookCount}', style: const TextStyle(fontSize: 10)),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
      selected: isSelected,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }

  IconData _getFileIcon(String ext) {
    switch (ext) {
      case 'pdf': return Icons.picture_as_pdf;
      case 'doc': case 'docx': return Icons.description;
      case 'xls': case 'xlsx': return Icons.table_chart;
      case 'zip': case 'rar': case '7z': return Icons.archive;
      case 'jpg': case 'jpeg': case 'png': case 'gif': return Icons.image;
      case 'mp4': case 'avi': case 'mkv': return Icons.movie;
      case 'mp3': case 'wav': case 'ogg': return Icons.audiotrack;
      case 'js': case 'ts': case 'py': case 'dart': return Icons.code;
      default: return Icons.insert_drive_file;
    }
  }
}
