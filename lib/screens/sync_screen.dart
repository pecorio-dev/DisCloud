import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../providers/cloud_provider.dart';
import '../services/sync_service.dart';

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final SyncService _syncService = SyncService();
  bool _isLoading = true;
  String? _syncingFolder;
  
  // Options globales
  bool _ignoreErrors = true;
  bool _syncSubfolders = false;

  @override
  void initState() {
    super.initState();
    _loadSyncFolders();
  }

  Future<void> _loadSyncFolders() async {
    await _syncService.init();
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Sync Folders'),
            _helpIcon(context, 'Sync Folders', 
              'Synchronize local folders with your Discord cloud storage.\n\n'
              'Files from your computer will be uploaded to Discord webhooks.\n\n'
              'Use multiple folders to organize your backups.'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
      floatingActionButton: kIsWeb ? null : FloatingActionButton.extended(
        onPressed: _addSyncFolder,
        icon: const Icon(Icons.add),
        label: const Text('Add Folder'),
      ),
    );
  }

  Widget _buildBody() {
    if (kIsWeb) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sync_disabled, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text('Folder sync not available on web'),
          ],
        ),
      );
    }

    return Column(
      children: [
        _buildGlobalOptions(),
        const Divider(height: 1),
        Expanded(
          child: _syncService.syncFolders.isEmpty
              ? _buildEmptyState()
              : _buildFolderList(),
        ),
      ],
    );
  }

  Widget _buildGlobalOptions() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.settings, size: 20),
              const SizedBox(width: 8),
              const Text('Sync Options', style: TextStyle(fontWeight: FontWeight.bold)),
              _helpIcon(context, 'Sync Options', 
                'Configure how synchronization behaves.\n\n'
                'These settings apply to all sync folders.'),
            ],
          ),
          const SizedBox(height: 12),
          _buildOptionRow(
            icon: Icons.error_outline,
            title: 'Ignore errors',
            subtitle: 'Continue syncing even if some files fail',
            value: _ignoreErrors,
            onChanged: (v) => setState(() => _ignoreErrors = v),
            helpTitle: 'Ignore Errors',
            helpText: 'When enabled, if a file fails to upload, the sync will continue with other files.\n\n'
                'When disabled, sync stops at the first error.\n\n'
                'Recommended: ON for large folders with many files.',
          ),
          _buildOptionRow(
            icon: Icons.folder_copy,
            title: 'Include subfolders',
            subtitle: 'Sync all files in subdirectories',
            value: _syncSubfolders,
            onChanged: (v) => setState(() => _syncSubfolders = v),
            helpTitle: 'Include Subfolders',
            helpText: 'When enabled, all files inside subfolders will also be uploaded.\n\n'
                'The folder structure will be recreated in the cloud.\n\n'
                'Warning: This can upload many files if your folder has deep nesting.',
          ),
        ],
      ),
    );
  }

  Widget _buildOptionRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool) onChanged,
    required String helpTitle,
    required String helpText,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(title),
                    _helpIcon(context, helpTitle, helpText),
                  ],
                ),
                Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_off, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text('No sync folders'),
          const SizedBox(height: 8),
          Text('Tap + to add a folder', style: TextStyle(color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _buildFolderList() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _syncService.syncFolders.length,
      itemBuilder: (context, index) {
        final folder = _syncService.syncFolders[index];
        return _buildFolderCard(folder);
      },
    );
  }

  Widget _buildFolderCard(SyncFolder folder) {
    final isSyncing = _syncingFolder == folder.localPath;
    final folderName = folder.localPath.split(Platform.pathSeparator).last;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.folder, color: Colors.amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(folderName, style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(
                        folder.localPath,
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                _helpIcon(context, 'Sync Folder', 
                  'Local: ${folder.localPath}\n\n'
                  'Cloud: ${folder.cloudPath}\n\n'
                  'Files from this local folder will be uploaded to the cloud path.'),
              ],
            ),
            const SizedBox(height: 8),
            // Cloud path
            Row(
              children: [
                Icon(Icons.cloud, size: 16, color: Colors.blue.shade300),
                const SizedBox(width: 8),
                Text('Cloud: ${folder.cloudPath}', 
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
            // Last sync
            if (folder.lastSync != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.schedule, size: 16, color: Colors.grey.shade400),
                  const SizedBox(width: 8),
                  Text('Last: ${_formatDate(folder.lastSync!)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
            ],
            const Divider(height: 16),
            // Actions
            Row(
              children: [
                // Auto-sync toggle
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: folder.autoSync,
                      onChanged: (v) => _toggleAutoSync(folder, v),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    const Text('Auto', style: TextStyle(fontSize: 12)),
                    _helpIcon(context, 'Auto-Sync',
                      'When enabled, this folder will be automatically synchronized periodically.\n\n'
                      'The app monitors changes and uploads new or modified files.'),
                  ],
                ),
                const Spacer(),
                // Sync button
                TextButton.icon(
                  onPressed: isSyncing ? null : () => _syncFolder(folder),
                  icon: isSyncing
                      ? const SizedBox(width: 16, height: 16, 
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.sync, size: 20),
                  label: Text(isSyncing ? 'Syncing...' : 'Sync'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
                // Delete button
                IconButton(
                  icon: const Icon(Icons.delete, size: 20),
                  color: Colors.red,
                  onPressed: () => _removeSyncFolder(folder),
                  tooltip: 'Remove',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _helpIcon(BuildContext context, String title, String content) {
    return IconButton(
      icon: Icon(Icons.help_outline, size: 18, color: Colors.grey.shade500),
      onPressed: () => _showHelp(context, title, content),
      tooltip: 'Help',
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(),
    );
  }

  void _showHelp(BuildContext context, String title, String content) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.help, color: Colors.blue),
            const SizedBox(width: 8),
            Expanded(child: Text(title)),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(content),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Future<void> _addSyncFolder() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result == null) return;

    final cloudPath = await _showCloudPathDialog();
    if (cloudPath == null) return;

    try {
      await _syncService.addSyncFolder(SyncFolder(
        localPath: result,
        cloudPath: cloudPath.startsWith('/') ? cloudPath : '/$cloudPath',
        autoSync: false,
      ));
      setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<String?> _showCloudPathDialog() async {
    final controller = TextEditingController(text: '/Backup');

    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Text('Cloud Destination'),
            _helpIcon(ctx, 'Cloud Path',
              'Choose where files will be stored in your Discord cloud.\n\n'
              'Example: /Documents/Work\n'
              'Example: /Backup/Photos\n\n'
              'The folder will be created automatically if it doesn\'t exist.'),
          ],
        ),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Cloud path',
            hintText: '/Documents/MyFolder',
            prefixIcon: Icon(Icons.cloud),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _removeSyncFolder(SyncFolder folder) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Folder?'),
        content: Text('Stop syncing "${folder.localPath.split(Platform.pathSeparator).last}"?\n\n'
            'Files already uploaded will remain in the cloud.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _syncService.removeSyncFolder(folder.localPath);
      setState(() {});
    }
  }

  Future<void> _toggleAutoSync(SyncFolder folder, bool value) async {
    await _syncService.updateSyncFolder(folder.copyWith(autoSync: value));
    setState(() {});
  }

  Future<void> _syncFolder(SyncFolder folder) async {
    setState(() => _syncingFolder = folder.localPath);

    int uploadedCount = 0;
    int errorCount = 0;
    int skippedCount = 0;

    try {
      final provider = context.read<CloudProvider>();
      final localDir = Directory(folder.localPath);
      
      if (!localDir.existsSync()) {
        throw Exception('Folder not found');
      }

      // Ensure cloud path exists
      String cloudPath = folder.cloudPath;
      if (!cloudPath.startsWith('/')) cloudPath = '/$cloudPath';
      await provider.ensurePathExists(cloudPath);

      final originalPath = provider.currentPath;

      // Get files (recursive or not based on option)
      final entities = localDir.listSync(recursive: _syncSubfolders);
      
      for (final entity in entities) {
        if (entity is File) {
          try {
            // Calculate relative path for subfolders
            String relativePath = entity.path.substring(folder.localPath.length);
            if (relativePath.startsWith(Platform.pathSeparator)) {
              relativePath = relativePath.substring(1);
            }
            
            final fileName = entity.uri.pathSegments.last;
            final fileDir = relativePath.contains(Platform.pathSeparator)
                ? relativePath.substring(0, relativePath.lastIndexOf(Platform.pathSeparator))
                : '';

            // Create subfolder in cloud if needed
            if (fileDir.isNotEmpty && _syncSubfolders) {
              final subCloudPath = '$cloudPath/$fileDir'.replaceAll('\\', '/');
              await provider.ensurePathExists(subCloudPath);
              await provider.navigateTo(subCloudPath);
            } else {
              await provider.navigateTo(cloudPath);
            }

            final data = await entity.readAsBytes();
            await provider.uploadFile(fileName, data);
            uploadedCount++;
          } catch (e) {
            errorCount++;
            if (!_ignoreErrors) {
              rethrow;
            }
          }
        } else if (entity is Directory && _syncSubfolders) {
          // Skip directories themselves, we handle them when uploading files
          skippedCount++;
        }
      }

      await provider.navigateTo(originalPath);
      
      await _syncService.updateSyncFolder(
        folder.copyWith(lastSync: DateTime.now()),
      );

      if (mounted) {
        String message = 'Synced $uploadedCount files';
        if (errorCount > 0) message += ', $errorCount errors';
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: errorCount > 0 ? Colors.orange : Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _syncingFolder = null);
      }
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
