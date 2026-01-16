import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/cloud_provider.dart';
import '../providers/download_manager.dart';
import '../models/cloud_file.dart';
import '../models/upload_options.dart';
import 'file_viewer_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'webhooks_screen.dart';
import 'sync_screen.dart';
import 'upload_options_screen.dart';
import 'download_manager_screen.dart';
import 'share_screen.dart';
import 'download_center_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  bool _selectionMode = false;
  final Set<String> _selectedFiles = {};
  late AnimationController _fabAnimController;
  late AnimationController _progressAnimController;
  late Animation<double> _fabScaleAnim;
  bool _showMultiWebhookUpload = false;

  @override
  void initState() {
    super.initState();
    _fabAnimController = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _progressAnimController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _fabScaleAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _fabAnimController, curve: Curves.elasticOut),
    );
    _fabAnimController.forward();
  }

  @override
  void dispose() {
    _fabAnimController.dispose();
    _progressAnimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      drawer: _buildDrawer(),
      body: Column(
        children: [
          _buildAnimatedProgressBar(),
          _buildToolbar(),
          _buildBreadcrumb(),
          Expanded(child: _buildFileList()),
          _buildStatusBar(),
        ],
      ),
      floatingActionButton: _buildAnimatedFAB(),
    );
  }

  Widget _buildAnimatedFAB() {
    return ScaleTransition(
      scale: _fabScaleAnim,
      child: FloatingActionButton.extended(
        onPressed: _uploadFile,
        icon: const Icon(Icons.cloud_upload),
        label: const Text('Upload'),
        elevation: 4,
      ),
    );
  }

  Widget _buildDrawer() {
    return Consumer<CloudProvider>(
      builder: (context, provider, _) {
        return Drawer(
          child: Column(
            children: [
              // Header avec logo anime
              Container(
                height: 180,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Theme.of(context).colorScheme.primary,
                      Theme.of(context).colorScheme.secondary,
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 800),
                        curve: Curves.elasticOut,
                        builder: (context, value, child) {
                          return Transform.scale(
                            scale: value,
                            child: Container(
                              width: 70,
                              height: 70,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: const Offset(0, 4))],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Image.asset('assets/logo.png', fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.cloud, size: 40, color: Colors.blue)),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      const Text('DisCloud', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                      Text('${provider.webhooks.length} webhooks', style: const TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
              ),
              // Webhooks list
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text('WEBHOOKS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                    ),
                    ...provider.webhooks.asMap().entries.map((entry) {
                      final index = entry.key;
                      final webhook = entry.value;
                      final isSelected = webhook.id == provider.currentWebhookId;
                      return TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: Duration(milliseconds: 200 + index * 100),
                        curve: Curves.easeOutBack,
                        builder: (context, value, child) {
                          return Transform.translate(
                            offset: Offset(-50 * (1 - value), 0),
                            child: Opacity(opacity: value, child: child),
                          );
                        },
                        child: ListTile(
                          leading: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isSelected ? Theme.of(context).colorScheme.primaryContainer : Colors.grey.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.webhook, color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey),
                          ),
                          title: Text(webhook.name),
                          subtitle: Text('${webhook.fileCount} files', style: const TextStyle(fontSize: 11)),
                          trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.green) : null,
                          onTap: () {
                            provider.selectWebhook(webhook.id);
                            Navigator.pop(context);
                          },
                        ),
                      );
                    }),
                    const Divider(),
                    _DrawerItem(icon: Icons.add, title: 'Add Webhook', onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const WebhooksScreen())); }),
                    _DrawerItem(icon: Icons.cloud_download, title: 'Download Center', subtitle: 'Video, Torrent, Batch', onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const DownloadCenterScreen())); }),
                    _DrawerItem(icon: Icons.download, title: 'Downloads', badge: context.watch<DownloadManager>().activeCount, onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const DownloadManagerScreen())); }),
                    _DrawerItem(icon: Icons.sync, title: 'Auto Sync', subtitle: provider.settings['autoSyncEnabled'] == true ? 'Enabled' : 'Disabled', onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const SyncScreen())); }),
                    _DrawerItem(icon: Icons.settings, title: 'Settings', onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())); }),
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
          onPressed: () => setState(() { _selectionMode = false; _selectedFiles.clear(); }),
        ),
        title: TweenAnimationBuilder<int>(
          tween: IntTween(begin: 0, end: _selectedFiles.length),
          duration: const Duration(milliseconds: 300),
          builder: (context, value, _) => Text('$value selected'),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.select_all), onPressed: _selectAll, tooltip: 'Select all'),
          IconButton(icon: const Icon(Icons.share), onPressed: _selectedFiles.isEmpty ? null : _shareSelected, tooltip: 'Share'),
          IconButton(icon: const Icon(Icons.download), onPressed: _selectedFiles.isEmpty ? null : _downloadSelected, tooltip: 'Download'),
          IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: _selectedFiles.isEmpty ? null : _deleteSelected, tooltip: 'Delete'),
        ],
      );
    }

    return AppBar(
      leading: Builder(
        builder: (context) => IconButton(
          icon: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset('assets/logo.png', fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(Icons.cloud, color: Theme.of(context).colorScheme.primary)),
            ),
          ),
          onPressed: () => Scaffold.of(context).openDrawer(),
        ),
      ),
      title: Row(
        children: [
          const Text('DisCloud'),
          if (provider.currentWebhook != null) ...[
            const SizedBox(width: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(provider.currentWebhook!.name, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.primary)),
            ),
          ],
        ],
      ),
      actions: [
        IconButton(icon: const Icon(Icons.search), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())), tooltip: 'Search'),
        IconButton(icon: const Icon(Icons.download), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DownloadManagerScreen())), tooltip: 'Downloads'),
        IconButton(icon: const Icon(Icons.webhook), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WebhooksScreen())), tooltip: 'Webhooks'),
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
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _AnimatedToolbarButton(icon: Icons.upload_file, label: 'Upload', onPressed: _uploadFile),
            _AnimatedToolbarButton(icon: Icons.cloud_upload, label: 'Multi-Upload', onPressed: _showMultiUploadDialog),
            _AnimatedToolbarButton(icon: Icons.create_new_folder, label: 'New Folder', onPressed: _createFolder),
            _AnimatedToolbarButton(icon: Icons.link, label: 'From URL', onPressed: _uploadFromUrl),
            const VerticalDivider(width: 16),
            _AnimatedToolbarButton(icon: Icons.tune, label: 'Options', onPressed: _openUploadOptions),
            _AnimatedToolbarButton(icon: Icons.checklist, label: 'Select', onPressed: () => setState(() => _selectionMode = true)),
            _AnimatedToolbarButton(icon: Icons.sync, label: 'Sync', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SyncScreen()))),
            const SizedBox(width: 16),
            Consumer<CloudProvider>(
              builder: (context, provider, _) => Row(
                children: [
                  _AnimatedStatChip(icon: Icons.folder, value: '${provider.totalFolders}'),
                  const SizedBox(width: 8),
                  _AnimatedStatChip(icon: Icons.insert_drive_file, value: '${provider.totalFiles}'),
                  const SizedBox(width: 8),
                  _AnimatedStatChip(icon: Icons.storage, value: _formatSize(provider.totalSize)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedProgressBar() {
    return Consumer<CloudProvider>(
      builder: (context, provider, _) {
        final isActive = provider.status == CloudStatus.uploading ||
            provider.status == CloudStatus.downloading ||
            provider.status == CloudStatus.syncing;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
          height: isActive ? 70 : 0,
          child: isActive ? _ProgressBarContent(
            progress: provider.progress,
            operation: provider.currentOperation ?? 'Working...',
            canCancel: provider.canCancel,
            onCancel: provider.cancelCurrentOperation,
          ) : null,
        );
      },
    );
  }

  Widget _buildBreadcrumb() {
    return Consumer<CloudProvider>(
      builder: (context, provider, _) {
        final parts = provider.currentPath.split('/').where((p) => p.isNotEmpty).toList();

        return Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: Theme.of(context).brightness == Brightness.dark ? Colors.black26 : Colors.grey.shade100,
          child: Row(
            children: [
              _BreadcrumbItem(
                icon: Icons.home,
                label: 'Root',
                isFirst: true,
                onTap: () => provider.navigateTo('/'),
              ),
              ...parts.asMap().entries.map((entry) {
                final path = '/${parts.sublist(0, entry.key + 1).join('/')}';
                return _BreadcrumbItem(
                  label: entry.value,
                  onTap: () => provider.navigateTo(path),
                );
              }),
              const Spacer(),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  '${provider.currentFiles.length} items',
                  key: ValueKey(provider.currentFiles.length),
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
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
          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 500),
            builder: (context, value, child) {
              return Opacity(
                opacity: value,
                child: Transform.scale(scale: 0.8 + 0.2 * value, child: child),
              );
            },
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.folder_open, size: 80, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  const Text('Empty folder', style: TextStyle(fontSize: 18, color: Colors.grey)),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _uploadFile,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Upload files'),
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          itemCount: provider.currentFiles.length,
          itemBuilder: (context, index) {
            final file = provider.currentFiles[index];
            final isSelected = _selectedFiles.contains(file.path);
            
            return TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: Duration(milliseconds: 200 + index * 50),
              curve: Curves.easeOutBack,
              builder: (context, value, child) {
                return Transform.translate(
                  offset: Offset(0, 20 * (1 - value)),
                  child: Opacity(opacity: value, child: child),
                );
              },
              child: _AnimatedFileCard(
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
                    setState(() { _selectionMode = true; _selectedFiles.add(file.path); });
                  }
                },
                onDelete: () => _confirmDelete(file),
                onDownload: () => _downloadFile(file),
                onShare: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ShareScreen(files: [file]))),
              ),
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
          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.all(12),
            color: Colors.red.shade100,
            child: Row(
              children: [
                const Icon(Icons.error, color: Colors.red, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(provider.errorMessage!, style: const TextStyle(color: Colors.red))),
                IconButton(icon: const Icon(Icons.close, size: 20), onPressed: provider.clearError),
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

  void _showMultiUploadDialog() {
    final provider = context.read<CloudProvider>();
    final webhooks = provider.webhooks;
    final selected = <String>{provider.currentWebhookId ?? ''};
    bool uploadToAll = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Multi-Webhook Upload'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Select webhooks to upload to:'),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Upload to all webhooks'),
                value: uploadToAll,
                onChanged: (v) => setDialogState(() {
                  uploadToAll = v;
                  if (v) selected.addAll(webhooks.map((w) => w.id));
                }),
              ),
              if (!uploadToAll) ...webhooks.map((webhook) => CheckboxListTile(
                title: Text(webhook.name),
                subtitle: Text('${webhook.fileCount} files'),
                value: selected.contains(webhook.id),
                onChanged: (v) => setDialogState(() {
                  if (v == true) selected.add(webhook.id);
                  else selected.remove(webhook.id);
                }),
              )),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                _uploadToMultipleWebhooks(selected.toList());
              },
              child: Text('Upload to ${selected.length} webhook(s)'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _uploadToMultipleWebhooks(List<String> webhookIds) async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null) return;

    final provider = context.read<CloudProvider>();
    final originalWebhook = provider.currentWebhookId;

    for (final webhookId in webhookIds) {
      await provider.selectWebhook(webhookId);
      for (final file in result.files) {
        if (file.bytes != null) {
          await provider.uploadFile(file.name, file.bytes!);
        } else if (file.path != null) {
          final bytes = await File(file.path!).readAsBytes();
          await provider.uploadFile(file.name, bytes);
        }
      }
    }

    if (originalWebhook != null) {
      await provider.selectWebhook(originalWebhook);
    }
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
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'Folder name')),
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

  void _openUploadOptions() {
    final provider = context.read<CloudProvider>();
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => UploadOptionsScreen(
        options: provider.uploadOptions,
        onSave: (options) {
          provider.setUploadOptions(options);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upload options saved!'), backgroundColor: Colors.green));
        },
      ),
    ));
  }

  Future<void> _shareSelected() async {
    final provider = context.read<CloudProvider>();
    final files = provider.currentFiles.where((f) => _selectedFiles.contains(f.path) && !f.isDirectory).toList();
    
    if (files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No files selected')));
      return;
    }

    Navigator.push(context, MaterialPageRoute(builder: (_) => ShareScreen(files: files)));
    setState(() { _selectionMode = false; _selectedFiles.clear(); });
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

    setState(() { _selectionMode = false; _selectedFiles.clear(); });
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Download complete!'), backgroundColor: Colors.green));
  }

  Future<void> _deleteSelected() async {
    final provider = context.read<CloudProvider>();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete?'),
        content: Text('Delete ${_selectedFiles.length} items?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );

    if (confirm == true) {
      for (final path in _selectedFiles.toList()) {
        final file = provider.currentFiles.firstWhere((f) => f.path == path);
        await provider.deleteFile(file);
      }
      setState(() { _selectionMode = false; _selectedFiles.clear(); });
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
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm == true) context.read<CloudProvider>().deleteFile(file);
  }

  Future<void> _downloadFile(CloudFile file) async {
    final savePath = await FilePicker.platform.getDirectoryPath();
    if (savePath == null) return;

    final provider = context.read<CloudProvider>();
    final data = await provider.downloadFile(file);
    if (data != null) {
      final outFile = File('$savePath/${file.name}');
      await outFile.writeAsBytes(data);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved to $savePath'), backgroundColor: Colors.green));
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }
}

// ========== ANIMATED WIDGETS ==========

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final int? badge;
  final VoidCallback onTap;

  const _DrawerItem({required this.icon, required this.title, this.subtitle, this.badge, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: badge != null && badge! > 0
          ? Badge(label: Text('$badge'), child: Icon(icon))
          : Icon(icon),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle!, style: const TextStyle(fontSize: 11)) : null,
      onTap: onTap,
    );
  }
}

class _AnimatedToolbarButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _AnimatedToolbarButton({required this.icon, required this.label, required this.onPressed});

  @override
  State<_AnimatedToolbarButton> createState() => _AnimatedToolbarButtonState();
}

class _AnimatedToolbarButtonState extends State<_AnimatedToolbarButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 150));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) { setState(() => _isHovered = true); _controller.forward(); },
      onExit: (_) { setState(() => _isHovered = false); _controller.reverse(); },
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: 1 + _controller.value * 0.05,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: TextButton.icon(
                onPressed: widget.onPressed,
                icon: Icon(widget.icon, size: 18),
                label: Text(widget.label, style: const TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  backgroundColor: _isHovered ? Theme.of(context).colorScheme.primary.withOpacity(0.1) : null,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AnimatedStatChip extends StatelessWidget {
  final IconData icon;
  final String value;

  const _AnimatedStatChip({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.8, end: 1),
      duration: const Duration(milliseconds: 300),
      builder: (context, scale, child) {
        return Transform.scale(scale: scale, child: child);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14),
            const SizedBox(width: 4),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(value, key: ValueKey(value), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressBarContent extends StatelessWidget {
  final double progress;
  final String operation;
  final bool canCancel;
  final VoidCallback onCancel;

  const _ProgressBarContent({required this.progress, required this.operation, required this.canCancel, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.withOpacity(0.1), Colors.purple.withOpacity(0.1)],
        ),
      ),
      child: Row(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 1000),
            builder: (context, value, child) {
              return Transform.rotate(
                angle: value * 2 * 3.14159,
                child: const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
              );
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(operation, style: const TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: progress),
                    duration: const Duration(milliseconds: 300),
                    builder: (context, value, _) {
                      return LinearProgressIndicator(
                        value: value,
                        minHeight: 6,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation(Color.lerp(Colors.blue, Colors.green, value)!),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TweenAnimationBuilder<int>(
            tween: IntTween(begin: 0, end: (progress * 100).toInt()),
            duration: const Duration(milliseconds: 300),
            builder: (context, value, _) => Text('$value%', style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          if (canCancel)
            IconButton(
              icon: const Icon(Icons.close, color: Colors.red),
              onPressed: onCancel,
              tooltip: 'Cancel',
            ),
        ],
      ),
    );
  }
}

class _BreadcrumbItem extends StatelessWidget {
  final IconData? icon;
  final String label;
  final bool isFirst;
  final VoidCallback onTap;

  const _BreadcrumbItem({this.icon, required this.label, this.isFirst = false, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!isFirst) Icon(Icons.chevron_right, size: 16, color: Colors.grey.shade600),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 4)],
                Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AnimatedFileCard extends StatefulWidget {
  final CloudFile file;
  final bool isSelected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onDelete;
  final VoidCallback onDownload;
  final VoidCallback onShare;

  const _AnimatedFileCard({
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
  State<_AnimatedFileCard> createState() => _AnimatedFileCardState();
}

class _AnimatedFileCardState extends State<_AnimatedFileCard> with SingleTickerProviderStateMixin {
  late AnimationController _hoverController;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _hoverController = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
  }

  @override
  void dispose() {
    _hoverController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) { setState(() => _isHovered = true); _hoverController.forward(); },
      onExit: (_) { setState(() => _isHovered = false); _hoverController.reverse(); },
      child: AnimatedBuilder(
        animation: _hoverController,
        builder: (context, child) {
          return Transform.scale(
            scale: 1 + _hoverController.value * 0.02,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(vertical: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: _isHovered ? [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 2))] : null,
              ),
              child: child,
            ),
          );
        },
        child: Card(
          elevation: widget.isSelected ? 4 : 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          color: widget.isSelected ? Theme.of(context).colorScheme.primaryContainer : null,
          child: InkWell(
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  if (widget.selectionMode)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      child: Checkbox(
                        value: widget.isSelected,
                        onChanged: (_) => widget.onTap(),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                    )
                  else
                    _buildFileIcon(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(widget.file.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500))),
                            if (widget.file.isEncrypted) const Icon(Icons.lock, size: 14, color: Colors.orange),
                            if (widget.file.isCompressed) const Icon(Icons.compress, size: 14, color: Colors.blue),
                          ],
                        ),
                        if (!widget.file.isDirectory) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(widget.file.formattedSize, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                              if (widget.file.chunkCount > 1) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text('${widget.file.chunkCount} chunks', style: const TextStyle(fontSize: 10, color: Colors.blue)),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (!widget.selectionMode) _buildActions(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFileIcon() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: widget.file.isDirectory ? Colors.amber.withOpacity(0.2) : Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        widget.file.isDirectory ? Icons.folder : _getFileIcon(widget.file.extension),
        color: widget.file.isDirectory ? Colors.amber.shade700 : Colors.blue,
        size: 24,
      ),
    );
  }

  Widget _buildActions() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!widget.file.isDirectory) ...[
          _ActionButton(icon: Icons.download, onPressed: widget.onDownload, tooltip: 'Download'),
          _ActionButton(icon: Icons.share, onPressed: widget.onShare, tooltip: 'Share'),
        ],
        _ActionButton(icon: Icons.delete_outline, onPressed: widget.onDelete, tooltip: 'Delete', color: Colors.red),
      ],
    );
  }

  IconData _getFileIcon(String ext) {
    switch (ext) {
      case 'pdf': return Icons.picture_as_pdf;
      case 'doc': case 'docx': return Icons.description;
      case 'xls': case 'xlsx': return Icons.table_chart;
      case 'zip': case 'rar': case '7z': return Icons.folder_zip;
      case 'jpg': case 'jpeg': case 'png': case 'gif': case 'webp': return Icons.image;
      case 'mp4': case 'avi': case 'mkv': case 'mov': return Icons.movie;
      case 'mp3': case 'wav': case 'ogg': case 'flac': return Icons.audiotrack;
      case 'js': case 'ts': case 'py': case 'dart': case 'java': return Icons.code;
      default: return Icons.insert_drive_file;
    }
  }
}

class _ActionButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;
  final Color? color;

  const _ActionButton({required this.icon, required this.onPressed, required this.tooltip, this.color});

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _controller.forward(),
      onExit: (_) => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: 1 + _controller.value * 0.2,
            child: IconButton(
              icon: Icon(widget.icon, size: 20, color: widget.color),
              onPressed: widget.onPressed,
              tooltip: widget.tooltip,
              splashRadius: 20,
            ),
          );
        },
      ),
    );
  }
}
