import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../services/download_manager.dart';
import '../services/share_link_service.dart';

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads'),
        actions: [
          IconButton(
            icon: const Icon(Icons.link),
            onPressed: () => _showImportLinkDialog(context),
            tooltip: 'Import from link',
          ),
          Consumer<DownloadManager>(
            builder: (context, manager, _) {
              if (manager.activeDownloads.isEmpty && manager.pendingDownloads.isEmpty) {
                return const SizedBox.shrink();
              }
              return IconButton(
                icon: const Icon(Icons.cancel),
                onPressed: () => _cancelAll(context, manager),
                tooltip: 'Cancel all',
              );
            },
          ),
          Consumer<DownloadManager>(
            builder: (context, manager, _) {
              if (manager.completedDownloads.isEmpty) {
                return const SizedBox.shrink();
              }
              return IconButton(
                icon: const Icon(Icons.clear_all),
                onPressed: manager.clearCompleted,
                tooltip: 'Clear completed',
              );
            },
          ),
        ],
      ),
      body: Consumer<DownloadManager>(
        builder: (context, manager, _) {
          if (manager.queue.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.download_done, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  const Text('No downloads'),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => _showImportLinkDialog(context),
                    icon: const Icon(Icons.link),
                    label: const Text('Import from share link'),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: manager.queue.length,
            itemBuilder: (context, index) {
              final task = manager.queue[index];
              return _DownloadTaskTile(task: task);
            },
          );
        },
      ),
    );
  }

  void _cancelAll(BuildContext context, DownloadManager manager) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel all?'),
        content: const Text('Cancel all downloads in progress?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes')),
        ],
      ),
    );
    if (confirm == true) {
      manager.cancelAll();
    }
  }

  void _showImportLinkDialog(BuildContext context) async {
    final controller = TextEditingController();
    
    final link = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.link, color: Colors.blue),
            const SizedBox(width: 8),
            const Text('Import Share Link'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Paste a DisCloud share link:'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'discloud://...',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
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
      _importFromLink(context, link);
    }
  }

  void _importFromLink(BuildContext context, String link) {
    final data = ShareLinkService.parseShareLink(link);
    
    if (data == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid share link'), backgroundColor: Colors.red),
      );
      return;
    }

    showDialog(
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
                subtitle: Text('File will be decrypted after download'),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _downloadFromShareData(context, data);
            },
            child: const Text('Download'),
          ),
        ],
      ),
    );
  }

  void _downloadFromShareData(BuildContext context, ShareLinkData data) async {
    // Demander ou sauvegarder
    String? savePath;
    
    if (!kIsWeb) {
      savePath = await FilePicker.platform.getDirectoryPath();
    }

    // Creer un CloudFile temporaire pour le download manager
    // (sans l'ajouter au file system)
    final manager = context.read<DownloadManager>();
    
    // Pour l'instant, on telecharge directement sans passer par CloudFile
    // car on n'a pas toutes les infos
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Downloading ${data.fileName}...')),
    );

    // TODO: Implementer le telechargement direct depuis ShareLinkData
  }
}

class _DownloadTaskTile extends StatelessWidget {
  final DownloadTask task;

  const _DownloadTaskTile({required this.task});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    Color statusColor;
    IconData statusIcon;
    
    switch (task.status) {
      case DownloadStatus.queued:
        statusColor = Colors.orange;
        statusIcon = Icons.schedule;
        break;
      case DownloadStatus.downloading:
        statusColor = Colors.blue;
        statusIcon = Icons.downloading;
        break;
      case DownloadStatus.completed:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case DownloadStatus.failed:
        statusColor = Colors.red;
        statusIcon = Icons.error;
        break;
      case DownloadStatus.cancelled:
        statusColor = Colors.grey;
        statusIcon = Icons.cancel;
        break;
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(statusIcon, color: statusColor),
        title: Text(task.file.name, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (task.status == DownloadStatus.downloading)
              LinearProgressIndicator(value: task.progress),
            if (task.status == DownloadStatus.downloading)
              Text('${(task.progress * 100).toInt()}%'),
            if (task.error != null)
              Text(task.error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            Text(task.file.formattedSize, 
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ],
        ),
        trailing: _buildActions(context),
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    final manager = context.read<DownloadManager>();
    
    switch (task.status) {
      case DownloadStatus.queued:
      case DownloadStatus.downloading:
        return IconButton(
          icon: const Icon(Icons.cancel, color: Colors.red),
          onPressed: () => manager.cancelDownload(task.id),
          tooltip: 'Cancel',
        );
      case DownloadStatus.failed:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => manager.retryDownload(task.id),
              tooltip: 'Retry',
            ),
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () => manager.removeFromQueue(task.id),
              tooltip: 'Remove',
            ),
          ],
        );
      case DownloadStatus.completed:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (task.savePath != null)
              IconButton(
                icon: const Icon(Icons.folder_open),
                onPressed: () => _openFolder(task.savePath!),
                tooltip: 'Open folder',
              ),
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () => manager.removeFromQueue(task.id),
              tooltip: 'Remove',
            ),
          ],
        );
      case DownloadStatus.cancelled:
        return IconButton(
          icon: const Icon(Icons.delete),
          onPressed: () => manager.removeFromQueue(task.id),
          tooltip: 'Remove',
        );
    }
  }

  void _openFolder(String path) async {
    // Ouvrir le dossier dans l'explorateur
    if (Platform.isWindows) {
      Process.run('explorer', [path]);
    }
  }
}

const kIsWeb = bool.fromEnvironment('dart.library.html');
