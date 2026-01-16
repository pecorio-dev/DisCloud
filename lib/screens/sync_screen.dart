import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../providers/cloud_provider.dart';
import '../models/cloud_file.dart';

class SyncScreen extends StatelessWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sync')),
        body: const Center(
          child: Text('Folder sync is not available on web'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Auto Sync'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _addSyncFolder(context),
            tooltip: 'Add Folder',
          ),
        ],
      ),
      body: Consumer<CloudProvider>(
        builder: (context, provider, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Global auto-sync toggle
              Card(
                child: SwitchListTile(
                  secondary: const Icon(Icons.sync),
                  title: const Text('Auto Sync'),
                  subtitle: const Text('Automatically sync folders periodically'),
                  value: provider.settings['autoSyncEnabled'] == true,
                  onChanged: (v) => provider.updateSetting('autoSyncEnabled', v),
                ),
              ),
              
              if (provider.settings['autoSyncEnabled'] == true)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.timer),
                    title: const Text('Sync Interval'),
                    trailing: DropdownButton<int>(
                      value: provider.settings['autoSyncInterval'] ?? 30,
                      items: [5, 10, 15, 30, 60].map((v) => 
                        DropdownMenuItem(value: v, child: Text('$v min'))
                      ).toList(),
                      onChanged: (v) {
                        if (v != null) provider.updateSetting('autoSyncInterval', v);
                      },
                    ),
                  ),
                ),

              const SizedBox(height: 16),
              
              Row(
                children: [
                  const Text('Sync Folders', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const Spacer(),
                  Text('${provider.syncFolders.length} folders', style: TextStyle(color: Colors.grey.shade600)),
                ],
              ),
              
              const SizedBox(height: 8),

              if (provider.syncFolders.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        Icon(Icons.folder_off, size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        const Text('No sync folders'),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: () => _addSyncFolder(context),
                          icon: const Icon(Icons.add),
                          label: const Text('Add Folder'),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...provider.syncFolders.map((folder) => _SyncFolderCard(
                  folder: folder,
                  webhookName: provider.currentWebhook?.name ?? 'Unknown',
                  onSync: () => provider.syncFolder(folder),
                  onToggleAuto: (v) => provider.updateSyncFolder(folder.copyWith(autoSync: v)),
                  onDelete: () => _confirmDelete(context, provider, folder),
                  onChangeInterval: (v) => provider.updateSyncFolder(folder.copyWith(intervalMinutes: v)),
                )),
            ],
          );
        },
      ),
    );
  }

  Future<void> _addSyncFolder(BuildContext context) async {
    final localPath = await FilePicker.platform.getDirectoryPath();
    if (localPath == null) return;

    final cloudPath = await _showCloudPathDialog(context);
    if (cloudPath == null) return;

    final provider = context.read<CloudProvider>();
    
    // Check if already added
    if (provider.syncFolders.any((f) => f.localPath == localPath)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Folder already added'), backgroundColor: Colors.orange),
      );
      return;
    }

    await provider.addSyncFolder(SyncFolder(
      localPath: localPath,
      cloudPath: cloudPath,
      webhookId: provider.currentWebhookId ?? '',
      autoSync: false,
      intervalMinutes: 30,
    ));
  }

  Future<String?> _showCloudPathDialog(BuildContext context) {
    final controller = TextEditingController(text: '/');

    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cloud Destination'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Cloud path',
            hintText: '/Backup',
            prefixIcon: Icon(Icons.cloud),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.isEmpty ? '/' : controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, CloudProvider provider, SyncFolder folder) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Folder?'),
        content: Text('Remove "${folder.localPath.split(Platform.pathSeparator).last}" from sync?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              provider.removeSyncFolder(folder.localPath);
              Navigator.pop(ctx);
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}

class _SyncFolderCard extends StatelessWidget {
  final SyncFolder folder;
  final String webhookName;
  final VoidCallback onSync;
  final Function(bool) onToggleAuto;
  final VoidCallback onDelete;
  final Function(int) onChangeInterval;

  const _SyncFolderCard({
    required this.folder,
    required this.webhookName,
    required this.onSync,
    required this.onToggleAuto,
    required this.onDelete,
    required this.onChangeInterval,
  });

  @override
  Widget build(BuildContext context) {
    final folderName = folder.localPath.split(Platform.pathSeparator).last;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.folder, color: Colors.amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(folderName, style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(folder.localPath, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: onDelete,
                ),
              ],
            ),
            const Divider(),
            Row(
              children: [
                Icon(Icons.cloud, size: 16, color: Colors.blue.shade300),
                const SizedBox(width: 8),
                Text('To: ${folder.cloudPath}', style: const TextStyle(fontSize: 12)),
                const Spacer(),
                Text('via $webhookName', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ],
            ),
            if (folder.lastSync != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.schedule, size: 16, color: Colors.grey.shade400),
                  const SizedBox(width: 8),
                  Text(
                    'Last: ${folder.lastSync!.day}/${folder.lastSync!.month} ${folder.lastSync!.hour}:${folder.lastSync!.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Switch(
                        value: folder.autoSync,
                        onChanged: onToggleAuto,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      const Text('Auto', style: TextStyle(fontSize: 12)),
                      if (folder.autoSync) ...[
                        const SizedBox(width: 8),
                        DropdownButton<int>(
                          value: folder.intervalMinutes,
                          underline: const SizedBox(),
                          isDense: true,
                          items: [5, 10, 15, 30, 60].map((v) => 
                            DropdownMenuItem(value: v, child: Text('$v min', style: const TextStyle(fontSize: 12)))
                          ).toList(),
                          onChanged: (v) { if (v != null) onChangeInterval(v); },
                        ),
                      ],
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: onSync,
                  icon: const Icon(Icons.sync, size: 18),
                  label: const Text('Sync Now'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
