import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../models/download_task.dart';
import '../providers/download_manager.dart';
import '../services/share_link_service.dart';

class DownloadManagerScreen extends StatefulWidget {
  const DownloadManagerScreen({super.key});

  @override
  State<DownloadManagerScreen> createState() => _DownloadManagerScreenState();
}

class _DownloadManagerScreenState extends State<DownloadManagerScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  final _linkController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Download Manager'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_link),
            onPressed: _showAddLinkDialog,
            tooltip: 'Add from link',
          ),
          PopupMenuButton<String>(
            onSelected: (action) {
              final manager = context.read<DownloadManager>();
              if (action == 'clear_completed') manager.clearCompleted();
              if (action == 'clear_all') manager.clearAll();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'clear_completed', child: Text('Clear completed')),
              const PopupMenuItem(value: 'clear_all', child: Text('Clear all')),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.download), text: 'Active'),
            Tab(icon: Icon(Icons.check_circle), text: 'Completed'),
            Tab(icon: Icon(Icons.error), text: 'Failed'),
          ],
        ),
      ),
      body: Consumer<DownloadManager>(
        builder: (context, manager, _) {
          return TabBarView(
            controller: _tabController,
            children: [
              _buildTaskList([...manager.activeTasks, ...manager.queuedTasks], manager),
              _buildTaskList(manager.completedTasks, manager),
              _buildTaskList(manager.failedTasks, manager),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddLinkDialog,
        icon: const Icon(Icons.add),
        label: const Text('Import Link'),
      ),
    );
  }

  Widget _buildTaskList(List<DownloadTask> tasks, DownloadManager manager) {
    if (tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_download, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text('No downloads', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        final task = tasks[index];
        return _DownloadTaskCard(
          task: task,
          onPause: () => manager.pauseDownload(task.id),
          onResume: () => manager.resumeDownload(task.id),
          onCancel: () => manager.cancelDownload(task.id),
          onRetry: () => manager.retryDownload(task.id),
          onRemove: () => manager.removeTask(task.id),
          onSave: () => _saveFile(task),
        );
      },
    );
  }

  void _showAddLinkDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import DisCloud Link'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _linkController,
              decoration: const InputDecoration(
                labelText: 'DisCloud Link',
                hintText: 'discloud://...',
                prefixIcon: Icon(Icons.link),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () async {
                    final data = await Clipboard.getData('text/plain');
                    if (data?.text != null) {
                      _linkController.text = data!.text!;
                    }
                  },
                  icon: const Icon(Icons.paste),
                  label: const Text('Paste'),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _importLink(_linkController.text);
              _linkController.clear();
            },
            child: const Text('Import'),
          ),
        ],
      ),
    );
  }

  void _importLink(String link) {
    final shareData = ShareLinkService.parseShareLink(link);
    if (shareData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid link'), backgroundColor: Colors.red),
      );
      return;
    }

    final manager = context.read<DownloadManager>();
    
    // Si fichiers encryptes, demander le mot de passe
    if (shareData.hasEncryptedFiles) {
      _showPasswordDialog(shareData, manager);
    } else {
      _addDownloadsFromShareData(shareData, manager);
    }
  }

  void _showPasswordDialog(ShareData shareData, DownloadManager manager) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Encrypted Files'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('These files are encrypted. Enter the decryption key:'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Decryption Key',
                prefixIcon: Icon(Icons.key),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              manager.setGlobalEncryptionKey(controller.text);
              _addDownloadsFromShareData(shareData, manager);
            },
            child: const Text('Decrypt & Download'),
          ),
        ],
      ),
    );
  }

  void _addDownloadsFromShareData(ShareData shareData, DownloadManager manager) {
    for (final file in shareData.files) {
      manager.addDownload(
        name: file.name,
        size: file.size,
        urls: file.urls,
        isCompressed: file.isCompressed,
        checksum: file.checksum,
        metadata: file.metadata,
      );
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added ${shareData.files.length} download(s)'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _saveFile(DownloadTask task) async {
    if (task.data == null) return;
    
    final savePath = await FilePicker.platform.getDirectoryPath();
    if (savePath == null) return;

    try {
      final file = File('$savePath/${task.name}');
      await file.writeAsBytes(task.data!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved to $savePath'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}

class _DownloadTaskCard extends StatelessWidget {
  final DownloadTask task;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final VoidCallback onRemove;
  final VoidCallback onSave;

  const _DownloadTaskCard({
    required this.task,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
    required this.onRetry,
    required this.onRemove,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildStatusIcon(),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(task.name, style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(task.formattedSize, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                          const SizedBox(width: 8),
                          Text('${task.chunkCount} chunks', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                          if (task.isEncrypted) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.lock, size: 14, color: Colors.orange),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                _buildActions(),
              ],
            ),
            if (task.status == DownloadStatus.downloading || task.status == DownloadStatus.queued) ...[
              const SizedBox(height: 12),
              _AnimatedProgressBar(progress: task.progress),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${(task.progress * 100).toInt()}%', style: const TextStyle(fontSize: 12)),
                  if (task.status == DownloadStatus.downloading) ...[
                    Text(task.formattedSpeed, style: const TextStyle(fontSize: 12)),
                    Text('ETA: ${task.formattedETA}', style: const TextStyle(fontSize: 12)),
                  ] else
                    const Text('Queued', style: TextStyle(fontSize: 12, color: Colors.orange)),
                ],
              ),
            ],
            if (task.status == DownloadStatus.failed && task.error != null) ...[
              const SizedBox(height: 8),
              Text(task.error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon() {
    IconData icon;
    Color color;
    
    switch (task.status) {
      case DownloadStatus.queued:
        icon = Icons.hourglass_empty;
        color = Colors.orange;
        break;
      case DownloadStatus.downloading:
        icon = Icons.downloading;
        color = Colors.blue;
        break;
      case DownloadStatus.paused:
        icon = Icons.pause_circle;
        color = Colors.grey;
        break;
      case DownloadStatus.completed:
        icon = Icons.check_circle;
        color = Colors.green;
        break;
      case DownloadStatus.failed:
        icon = Icons.error;
        color = Colors.red;
        break;
      case DownloadStatus.cancelled:
        icon = Icons.cancel;
        color = Colors.grey;
        break;
    }

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 300),
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: Icon(icon, color: color, size: 32),
        );
      },
    );
  }

  Widget _buildActions() {
    switch (task.status) {
      case DownloadStatus.downloading:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(icon: const Icon(Icons.pause), onPressed: onPause, tooltip: 'Pause'),
            IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: onCancel, tooltip: 'Cancel'),
          ],
        );
      case DownloadStatus.paused:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(icon: const Icon(Icons.play_arrow, color: Colors.green), onPressed: onResume, tooltip: 'Resume'),
            IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: onCancel, tooltip: 'Cancel'),
          ],
        );
      case DownloadStatus.queued:
        return IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: onCancel, tooltip: 'Cancel');
      case DownloadStatus.completed:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(icon: const Icon(Icons.save_alt, color: Colors.blue), onPressed: onSave, tooltip: 'Save'),
            IconButton(icon: const Icon(Icons.delete_outline), onPressed: onRemove, tooltip: 'Remove'),
          ],
        );
      case DownloadStatus.failed:
      case DownloadStatus.cancelled:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(icon: const Icon(Icons.refresh, color: Colors.orange), onPressed: onRetry, tooltip: 'Retry'),
            IconButton(icon: const Icon(Icons.delete_outline), onPressed: onRemove, tooltip: 'Remove'),
          ],
        );
    }
  }
}

class _AnimatedProgressBar extends StatelessWidget {
  final double progress;

  const _AnimatedProgressBar({required this.progress});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: progress),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      builder: (context, value, child) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 8,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation(
              Color.lerp(Colors.blue, Colors.green, value)!,
            ),
          ),
        );
      },
    );
  }
}
