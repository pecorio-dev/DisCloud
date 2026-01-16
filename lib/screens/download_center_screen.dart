import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/cloud_provider.dart';
import '../providers/download_manager.dart';
import '../models/download_task.dart';
import '../services/universal_downloader.dart';
import '../services/torrent_service.dart';
import '../services/dependency_manager.dart';
import '../services/share_link_service.dart';

class DownloadCenterScreen extends StatefulWidget {
  const DownloadCenterScreen({super.key});

  @override
  State<DownloadCenterScreen> createState() => _DownloadCenterScreenState();
}

class _DownloadCenterScreenState extends State<DownloadCenterScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  final UniversalDownloader _downloader = UniversalDownloader();
  final TorrentService _torrentService = TorrentService();
  final DependencyManager _depManager = DependencyManager();
  
  final _urlController = TextEditingController();
  final _batchController = TextEditingController();
  
  bool _isExtracting = false;
  bool _isDownloading = false;
  bool _isInstallingDeps = false;
  double _progress = 0;
  String? _status;
  List<ExtractedVideo>? _extractedVideos;
  String? _error;
  String? _installingDep;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _initDeps();
    _torrentService.addListener(() => setState(() {}));
    _depManager.addListener(() => setState(() {}));
  }

  Future<void> _initDeps() async {
    await _depManager.init();
    
    // Passer les chemins des outils au downloader
    await _downloader.init(
      ytDlpPath: _depManager.ytDlpPath,
      aria2Path: _depManager.aria2Path,
    );
    
    // Mettre a jour les chemins quand les dependances changent
    _depManager.addListener(_onDepManagerUpdate);
  }
  
  void _onDepManagerUpdate() {
    _downloader.updatePaths(
      ytDlpPath: _depManager.ytDlpPath,
      aria2Path: _depManager.aria2Path,
    );
    
    // Mettre a jour aussi le TorrentService avec aria2
    if (_depManager.aria2Path != null && !_torrentService.isRunning) {
      _torrentService.setAria2Path(_depManager.aria2Path!);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _urlController.dispose();
    _batchController.dispose();
    _downloader.dispose();
    _torrentService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Download Center'),
        actions: [
          // Indicateur de statut des dependances
          _buildDependencyStatusIcon(),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            const Tab(icon: Icon(Icons.download), text: 'Queue'),
            const Tab(icon: Icon(Icons.link), text: 'Direct'),
            const Tab(icon: Icon(Icons.video_library), text: 'Video'),
            const Tab(icon: Icon(Icons.cloud_download), text: 'Torrent'),
            const Tab(icon: Icon(Icons.list), text: 'Batch'),
            const Tab(icon: Icon(Icons.build), text: 'Tools'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildQueueTab(),
          _buildDirectTab(),
          _buildVideoTab(),
          _buildTorrentTab(),
          _buildBatchTab(),
          _buildToolsTab(),
        ],
      ),
    );
  }

  Widget _buildDependencyStatusIcon() {
    final allInstalled = _depManager.aria2.status == DependencyStatus.installed &&
                         _depManager.ytDlp.status == DependencyStatus.installed;
    final hasUpdates = _depManager.aria2.needsUpdate || _depManager.ytDlp.needsUpdate;
    
    return IconButton(
      icon: Icon(
        allInstalled 
            ? (hasUpdates ? Icons.system_update : Icons.check_circle)
            : Icons.warning,
        color: allInstalled 
            ? (hasUpdates ? Colors.orange : Colors.green)
            : Colors.red,
      ),
      tooltip: allInstalled 
          ? (hasUpdates ? 'Updates available' : 'All tools installed')
          : 'Missing tools',
      onPressed: () => _tabController.animateTo(5),
    );
  }

  // ========== QUEUE TAB (integrated download manager) ==========
  Widget _buildQueueTab() {
    return Consumer<DownloadManager>(
      builder: (context, manager, _) {
        final allTasks = [...manager.activeTasks, ...manager.queuedTasks, ...manager.completedTasks, ...manager.failedTasks];
        
        if (allTasks.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.cloud_download, size: 80, color: Colors.grey.shade300),
                const SizedBox(height: 16),
                const Text('No downloads', style: TextStyle(fontSize: 18, color: Colors.grey)),
                const SizedBox(height: 8),
                const Text('Add files from Video, Torrent or Batch tabs', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: _showImportLinkDialog,
                  icon: const Icon(Icons.link),
                  label: const Text('Import DisCloud Link'),
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            // Stats bar
            Container(
              padding: const EdgeInsets.all(12),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _QueueStat(label: 'Active', value: manager.activeTasks.length, color: Colors.blue),
                  _QueueStat(label: 'Queued', value: manager.queuedTasks.length, color: Colors.orange),
                  _QueueStat(label: 'Done', value: manager.completedTasks.length, color: Colors.green),
                  _QueueStat(label: 'Failed', value: manager.failedTasks.length, color: Colors.red),
                ],
              ),
            ),
            // Actions bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: _showImportLinkDialog,
                    icon: const Icon(Icons.add_link, size: 18),
                    label: const Text('Import Link'),
                  ),
                  const Spacer(),
                  if (manager.completedTasks.isNotEmpty)
                    TextButton(
                      onPressed: manager.clearCompleted,
                      child: const Text('Clear Done'),
                    ),
                  if (allTasks.isNotEmpty)
                    TextButton(
                      onPressed: manager.clearAll,
                      child: const Text('Clear All', style: TextStyle(color: Colors.red)),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Task list
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: allTasks.length,
                itemBuilder: (context, index) {
                  final task = allTasks[index];
                  return _DownloadTaskCard(
                    task: task,
                    onPause: () => manager.pauseDownload(task.id),
                    onResume: () => manager.resumeDownload(task.id),
                    onCancel: () => manager.cancelDownload(task.id),
                    onRetry: () => manager.retryDownload(task.id),
                    onRemove: () => manager.removeTask(task.id),
                    onSave: () => _saveDownloadedFile(task),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  void _showImportLinkDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import DisCloud Link'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'DisCloud Link',
                hintText: 'discloud://...',
                prefixIcon: Icon(Icons.link),
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  final data = await Clipboard.getData('text/plain');
                  if (data?.text != null) controller.text = data!.text!;
                },
                icon: const Icon(Icons.paste),
                label: const Text('Paste'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _importDisCloudLink(controller.text);
            },
            child: const Text('Import'),
          ),
        ],
      ),
    );
  }

  void _importDisCloudLink(String link) {
    final shareData = ShareLinkService.parseShareLink(link);
    if (shareData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid link'), backgroundColor: Colors.red),
      );
      return;
    }

    final manager = context.read<DownloadManager>();
    
    if (shareData.hasEncryptedFiles) {
      _showDecryptionKeyDialog(shareData, manager);
    } else {
      _addDownloadsFromShareData(shareData, manager);
    }
  }

  void _showDecryptionKeyDialog(ShareData shareData, DownloadManager manager) {
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
                border: OutlineInputBorder(),
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
      SnackBar(content: Text('Added ${shareData.files.length} download(s)'), backgroundColor: Colors.green),
    );
  }

  Future<void> _saveDownloadedFile(DownloadTask task) async {
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

  Widget _buildToolsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Download Tools', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Required tools for advanced downloads', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          
          // aria2
          _DependencyCard(
            info: _depManager.aria2,
            description: 'High-speed download utility for torrents and parallel downloads',
            isInstalling: _isInstallingDeps && _installingDep == 'aria2',
            progress: _isInstallingDeps && _installingDep == 'aria2' ? _progress : null,
            onInstall: () => _installDependency('aria2'),
            onUpdate: _depManager.aria2.needsUpdate ? () => _installDependency('aria2') : null,
          ),
          
          const SizedBox(height: 16),
          
          // yt-dlp
          _DependencyCard(
            info: _depManager.ytDlp,
            description: 'Video downloader supporting 1000+ sites (YouTube, Vimeo, etc.)',
            isInstalling: _isInstallingDeps && _installingDep == 'yt-dlp',
            progress: _isInstallingDeps && _installingDep == 'yt-dlp' ? _progress : null,
            onInstall: () => _installDependency('yt-dlp'),
            onUpdate: _depManager.ytDlp.needsUpdate ? () => _installDependency('yt-dlp') : null,
          ),
          
          const SizedBox(height: 24),
          
          // Install all button
          if (_depManager.aria2.status != DependencyStatus.installed ||
              _depManager.ytDlp.status != DependencyStatus.installed)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isInstallingDeps ? null : _installAllDependencies,
                icon: const Icon(Icons.download),
                label: const Text('Install All Missing Tools'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          
          // Update all button
          if (_depManager.aria2.needsUpdate || _depManager.ytDlp.needsUpdate)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isInstallingDeps ? null : _updateAllDependencies,
                  icon: const Icon(Icons.system_update),
                  label: const Text('Update All'),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(16)),
                ),
              ),
            ),
          
          const SizedBox(height: 24),
          
          // Refresh button
          Center(
            child: TextButton.icon(
              onPressed: _isInstallingDeps ? null : () => _depManager.checkAll(),
              icon: const Icon(Icons.refresh),
              label: const Text('Check for Updates'),
            ),
          ),
          
          const SizedBox(height: 32),
          
          // Info card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.info, color: Colors.blue),
                    SizedBox(width: 8),
                    Text('About Tools', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  '• aria2 enables torrent downloads and parallel file downloads\n'
                  '• yt-dlp extracts video URLs from YouTube, Vimeo, TikTok, and 1000+ sites\n'
                  '• Tools are downloaded from official GitHub releases\n'
                  '• Installed in app data folder (no admin required)',
                  style: TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _installDependency(String name) async {
    setState(() {
      _isInstallingDeps = true;
      _installingDep = name;
      _progress = 0;
    });

    bool success;
    if (name == 'aria2') {
      success = await _depManager.installAria2(
        onProgress: (p) => setState(() => _progress = p),
      );
    } else {
      success = await _depManager.installYtDlp(
        onProgress: (p) => setState(() => _progress = p),
      );
    }

    setState(() {
      _isInstallingDeps = false;
      _installingDep = null;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? '$name installed successfully!' : 'Failed to install $name'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  Future<void> _installAllDependencies() async {
    setState(() {
      _isInstallingDeps = true;
    });

    await _depManager.installAll(
      onProgress: (name, p) => setState(() {
        _installingDep = name;
        _progress = p;
      }),
    );

    setState(() {
      _isInstallingDeps = false;
      _installingDep = null;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All tools installed!'), backgroundColor: Colors.green),
      );
    }
  }

  Future<void> _updateAllDependencies() async {
    setState(() {
      _isInstallingDeps = true;
    });

    await _depManager.updateAll(
      onProgress: (name, p) => setState(() {
        _installingDep = name;
        _progress = p;
      }),
    );

    setState(() {
      _isInstallingDeps = false;
      _installingDep = null;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All tools updated!'), backgroundColor: Colors.green),
      );
    }
  }

  Widget _buildDirectTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Direct URL Download', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Download any file directly to Discord', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          
          TextField(
            controller: _urlController,
            decoration: InputDecoration(
              labelText: 'URL',
              hintText: 'https://example.com/file.zip',
              prefixIcon: const Icon(Icons.link),
              suffixIcon: IconButton(
                icon: const Icon(Icons.paste),
                onPressed: () async {
                  final data = await Clipboard.getData('text/plain');
                  if (data?.text != null) _urlController.text = data!.text!;
                },
              ),
              border: const OutlineInputBorder(),
            ),
          ),
          
          const SizedBox(height: 16),
          
          if (_isDownloading) _buildProgressCard(),
          
          const SizedBox(height: 16),
          
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isDownloading ? null : _downloadDirect,
              icon: const Icon(Icons.cloud_upload),
              label: const Text('Download to Discord'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Video Downloader', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Text('YouTube, Uqload, Vimeo, and more', style: TextStyle(color: Colors.grey)),
                        const SizedBox(width: 8),
                        if (_downloader.ytDlpAvailable)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.check, size: 12, color: Colors.green),
                                const SizedBox(width: 4),
                                Text('yt-dlp ready', style: TextStyle(fontSize: 10, color: Colors.green.shade700)),
                              ],
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.warning, size: 12, color: Colors.orange),
                                const SizedBox(width: 4),
                                Text('yt-dlp needed', style: TextStyle(fontSize: 10, color: Colors.orange.shade700)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!_downloader.ytDlpAvailable)
                ElevatedButton.icon(
                  onPressed: () async {
                    await _installDependency('yt-dlp');
                    await _downloader.refresh();
                    setState(() {});
                  },
                  icon: const Icon(Icons.download, size: 16),
                  label: const Text('Install yt-dlp'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          
          TextField(
            controller: _urlController,
            decoration: InputDecoration(
              labelText: 'Video URL',
              hintText: 'https://youtube.com/watch?v=...',
              prefixIcon: const Icon(Icons.video_library),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(icon: const Icon(Icons.paste), onPressed: () async {
                    final data = await Clipboard.getData('text/plain');
                    if (data?.text != null) _urlController.text = data!.text!;
                  }),
                  IconButton(icon: const Icon(Icons.search), onPressed: _extractVideo),
                ],
              ),
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _extractVideo(),
          ),
          
          const SizedBox(height: 16),
          
          if (_isExtracting)
            const Center(child: CircularProgressIndicator())
          else if (_error != null)
            _buildErrorCard()
          else if (_extractedVideos != null && _extractedVideos!.isNotEmpty)
            _buildVideoList()
          else if (_isDownloading)
            _buildProgressCard(),
          
          const SizedBox(height: 16),
          
          // Supported sites
          ExpansionTile(
            title: const Text('Supported Sites'),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _SiteChip('YouTube'),
                  _SiteChip('Vimeo'),
                  _SiteChip('Dailymotion'),
                  _SiteChip('Twitch'),
                  _SiteChip('Facebook'),
                  _SiteChip('Twitter'),
                  _SiteChip('Instagram'),
                  _SiteChip('TikTok'),
                  _SiteChip('Uqload'),
                  _SiteChip('Streamtape'),
                  _SiteChip('Doodstream'),
                  _SiteChip('Mixdrop'),
                  _SiteChip('+ 1000 more'),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTorrentTab() {
    final aria2Installed = _depManager.aria2.status == DependencyStatus.installed;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Torrent to Discord', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (aria2Installed) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.check, size: 12, color: Colors.green),
                                const SizedBox(width: 4),
                                Text('aria2 ready', style: TextStyle(fontSize: 10, color: Colors.green.shade700)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _torrentService.isRunning ? 'Service running' : 'Service stopped',
                            style: TextStyle(fontSize: 12, color: _torrentService.isRunning ? Colors.green : Colors.grey),
                          ),
                        ] else
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.warning, size: 12, color: Colors.orange),
                                const SizedBox(width: 4),
                                Text('aria2 needed', style: TextStyle(fontSize: 10, color: Colors.orange.shade700)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (aria2Installed)
                Switch(
                  value: _torrentService.isRunning,
                  onChanged: (v) async {
                    if (v) {
                      _torrentService.setAria2Path(_depManager.aria2Path!);
                      final success = await _torrentService.start();
                      if (!success && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Failed to start aria2. Check if the path is correct.'), backgroundColor: Colors.red),
                        );
                      }
                    } else {
                      await _torrentService.stop();
                    }
                    if (mounted) setState(() {});
                  },
                )
              else
                ElevatedButton.icon(
                  onPressed: () async {
                    await _installDependency('aria2');
                    setState(() {});
                  },
                  icon: const Icon(Icons.download, size: 16),
                  label: const Text('Install'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
            ],
          ),
          
          const SizedBox(height: 8),
          const Text('Download torrents directly to Discord without storing locally', style: TextStyle(color: Colors.grey)),
          
          const SizedBox(height: 24),
          
          if (!aria2Installed)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.info, color: Colors.orange, size: 32),
                  const SizedBox(height: 8),
                  const Text('aria2 Required', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  const Text('Click the Install button above to download aria2 automatically.', style: TextStyle(fontSize: 12), textAlign: TextAlign.center),
                ],
              ),
            )
          else ...[
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                labelText: 'Magnet Link or Torrent URL',
                hintText: 'magnet:?xt=urn:btih:...',
                prefixIcon: const Icon(Icons.link),
                suffixIcon: IconButton(icon: const Icon(Icons.paste), onPressed: () async {
                  final data = await Clipboard.getData('text/plain');
                  if (data?.text != null) _urlController.text = data!.text!;
                }),
              border: const OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          
            const SizedBox(height: 16),
            
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _torrentService.isRunning ? _addTorrent : null,
                icon: const Icon(Icons.add),
                label: const Text('Add Torrent'),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
              ),
            ),
            
            const SizedBox(height: 24),
            
            if (_torrentService.torrents.isNotEmpty) ...[
              const Text('Active Torrents', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ...torrentService.torrents.map((t) => _TorrentCard(
                info: t,
                onPause: () => _torrentService.pauseTorrent(t.infoHash),
                onResume: () => _torrentService.resumeTorrent(t.infoHash),
                onRemove: () => _torrentService.removeTorrent(t.infoHash),
                onUploadToDiscord: () => _uploadTorrentToDiscord(t),
              )),
            ],
            
            if (!_torrentService.isRunning && aria2Installed)
              Container(
                margin: const EdgeInsets.only(top: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.info, color: Colors.blue),
                    SizedBox(width: 12),
                    Expanded(child: Text('Enable the service (switch above) to start downloading torrents.', style: TextStyle(fontSize: 12))),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildBatchTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Batch Download', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Download multiple files at once', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          
          TextField(
            controller: _batchController,
            decoration: const InputDecoration(
              labelText: 'URLs (one per line)',
              hintText: 'https://example.com/file1.zip\nhttps://example.com/file2.zip\n...',
              border: OutlineInputBorder(),
            ),
            maxLines: 10,
          ),
          
          const SizedBox(height: 16),
          
          if (_isDownloading) _buildProgressCard(),
          
          const SizedBox(height: 16),
          
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final data = await Clipboard.getData('text/plain');
                    if (data?.text != null) _batchController.text = data!.text!;
                  },
                  icon: const Icon(Icons.paste),
                  label: const Text('Paste from Clipboard'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isDownloading ? null : _downloadBatch,
                  icon: const Icon(Icons.cloud_upload),
                  label: const Text('Download All'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgressCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 12),
                Expanded(child: Text(_status ?? 'Downloading...', style: const TextStyle(fontWeight: FontWeight.w500))),
                Text('${(_progress * 100).toInt()}%'),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: _progress, minHeight: 8),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard() {
    return Card(
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.error, color: Colors.red),
            const SizedBox(width: 12),
            Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red))),
            IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _error = null)),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${_extractedVideos!.length} formats found', style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ...extractedVideos!.take(5).map((v) => Card(
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(v.quality, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            title: Text(v.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${v.format.toUpperCase()} ${v.fileSize != null ? "- ${_formatSize(v.fileSize!)}" : ""}'),
            trailing: IconButton(
              icon: const Icon(Icons.cloud_upload),
              onPressed: () => _downloadVideo(v),
            ),
          ),
        )),
      ],
    );
  }

  // Actions
  Future<void> _downloadDirect() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _isDownloading = true;
      _progress = 0;
      _status = 'Downloading...';
      _error = null;
    });

    try {
      final provider = context.read<CloudProvider>();
      final filename = Uri.parse(url).pathSegments.lastOrNull ?? 'file';

      await _downloader.downloadAndUpload(
        url: url,
        filename: filename,
        uploadFunc: (name, data) => provider.uploadFile(name, data),
        onProgress: (p) => setState(() {
          _progress = p;
          _status = 'Downloading... ${(p * 100).toInt()}%';
        }),
      );

      setState(() {
        _status = 'Completed!';
        _progress = 1;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Download complete!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isDownloading = false);
    }
  }

  Future<void> _extractVideo() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    // Verifier si yt-dlp est disponible
    if (!_downloader.ytDlpAvailable) {
      setState(() {
        _error = 'yt-dlp is not installed. Please go to the Tools tab to install it.';
      });
      
      // Proposer d'installer
      if (mounted) {
        final install = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('yt-dlp Required'),
            content: const Text(
              'yt-dlp is required to extract videos from most sites.\n\n'
              'Would you like to install it now?'
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Install'),
              ),
            ],
          ),
        );
        
        if (install == true) {
          await _installDependency('yt-dlp');
          await _downloader.refresh();
          setState(() => _error = null);
          // Re-essayer l'extraction
          if (_downloader.ytDlpAvailable) {
            _extractVideo();
          }
        }
      }
      return;
    }

    setState(() {
      _isExtracting = true;
      _extractedVideos = null;
      _error = null;
    });

    try {
      debugPrint('Extracting video from: $url');
      debugPrint('Using yt-dlp at: ${_downloader.ytDlpPath}');
      
      final videos = await _downloader.extractVideoInfo(url);
      setState(() => _extractedVideos = videos);
      
      if (videos.isEmpty) {
        setState(() {
          _error = 'No videos found at this URL.\n\n'
              'Possible reasons:\n'
              '• The URL might be invalid or expired\n'
              '• The site may require authentication\n'
              '• yt-dlp may need to be updated';
        });
      }
    } catch (e) {
      setState(() => _error = 'Error extracting video: $e');
    } finally {
      setState(() => _isExtracting = false);
    }
  }

  Future<void> _downloadVideo(ExtractedVideo video) async {
    setState(() {
      _isDownloading = true;
      _progress = 0;
      _status = 'Downloading ${video.title}...';
      _extractedVideos = null;
    });

    try {
      final provider = context.read<CloudProvider>();
      final filename = '${video.title}.${video.format}';

      await _downloader.downloadAndUpload(
        url: video.url,
        filename: filename,
        uploadFunc: (name, data) => provider.uploadFile(name, data),
        onProgress: (p) => setState(() {
          _progress = p;
          _status = 'Downloading... ${(p * 100).toInt()}%';
        }),
        headers: video.headers,
      );

      setState(() {
        _status = 'Completed!';
        _progress = 1;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Video uploaded to Discord!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isDownloading = false);
    }
  }

  Future<void> _addTorrent() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    final gid = await _torrentService.addTorrent(url);
    if (gid != null) {
      _urlController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Torrent added!'), backgroundColor: Colors.green),
        );
      }
    }
  }

  Future<void> _uploadTorrentToDiscord(TorrentInfo info) async {
    if (info.status != TorrentStatus.completed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wait for download to complete'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() {
      _isDownloading = true;
      _status = 'Uploading ${info.name} to Discord...';
      _progress = 0;
    });

    try {
      final provider = context.read<CloudProvider>();
      final files = await _torrentService.getTorrentFiles(info.infoHash);
      
      int totalFiles = files.length;
      int uploaded = 0;

      for (final file in files) {
        final data = await file.readAsBytes();
        await provider.uploadFile(file.uri.pathSegments.last, data);
        uploaded++;
        setState(() {
          _progress = uploaded / totalFiles;
          _status = 'Uploading... $uploaded/$totalFiles';
        });
      }

      // Supprimer le torrent
      await _torrentService.removeTorrent(info.infoHash);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Uploaded to Discord!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isDownloading = false);
    }
  }

  Future<void> _downloadBatch() async {
    final urls = _batchController.text.split('\n').where((u) => u.trim().isNotEmpty).toList();
    if (urls.isEmpty) return;

    setState(() {
      _isDownloading = true;
      _progress = 0;
      _status = 'Downloading 0/${urls.length}...';
    });

    try {
      final provider = context.read<CloudProvider>();
      int completed = 0;

      for (final url in urls) {
        try {
          final filename = Uri.parse(url.trim()).pathSegments.lastOrNull ?? 'file_$completed';
          
          await _downloader.downloadAndUpload(
            url: url.trim(),
            filename: filename,
            uploadFunc: (name, data) => provider.uploadFile(name, data),
            onProgress: (p) => setState(() {
              _progress = (completed + p) / urls.length;
            }),
          );
          
          completed++;
          setState(() {
            _status = 'Downloading $completed/${urls.length}...';
            _progress = completed / urls.length;
          });
        } catch (e) {
          debugPrint('Failed to download $url: $e');
        }
      }

      setState(() {
        _status = 'Completed! $completed/${urls.length} files';
        _progress = 1;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Batch complete: $completed/${urls.length}'), backgroundColor: Colors.green),
        );
      }
    } finally {
      setState(() => _isDownloading = false);
    }
  }

  void _openUrl(String url) async {
    if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', url]);
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  
  TorrentService get torrentService => _torrentService;
  List<ExtractedVideo>? get extractedVideos => _extractedVideos;
}

class _SiteChip extends StatelessWidget {
  final String name;
  const _SiteChip(this.name);

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(name, style: const TextStyle(fontSize: 12)),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _TorrentCard extends StatelessWidget {
  final TorrentInfo info;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onRemove;
  final VoidCallback onUploadToDiscord;

  const _TorrentCard({
    required this.info,
    required this.onPause,
    required this.onResume,
    required this.onRemove,
    required this.onUploadToDiscord,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
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
                      Text(info.name, style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text('${info.formattedSize} - ${info.files.length} files', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                _buildActions(),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: info.progress,
                minHeight: 6,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation(info.status == TorrentStatus.completed ? Colors.green : Colors.blue),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${(info.progress * 100).toInt()}%', style: const TextStyle(fontSize: 12)),
                if (info.status == TorrentStatus.downloading)
                  Text('${info.formattedSpeed} - ${info.peers} peers', style: const TextStyle(fontSize: 12)),
                if (info.status == TorrentStatus.completed)
                  TextButton.icon(
                    onPressed: onUploadToDiscord,
                    icon: const Icon(Icons.cloud_upload, size: 16),
                    label: const Text('Upload to Discord'),
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon() {
    IconData icon;
    Color color;

    switch (info.status) {
      case TorrentStatus.checking:
        icon = Icons.hourglass_empty;
        color = Colors.orange;
        break;
      case TorrentStatus.downloading:
        icon = Icons.downloading;
        color = Colors.blue;
        break;
      case TorrentStatus.seeding:
        icon = Icons.upload;
        color = Colors.green;
        break;
      case TorrentStatus.paused:
        icon = Icons.pause;
        color = Colors.grey;
        break;
      case TorrentStatus.completed:
        icon = Icons.check_circle;
        color = Colors.green;
        break;
      case TorrentStatus.error:
        icon = Icons.error;
        color = Colors.red;
        break;
    }

    return Icon(icon, color: color, size: 28);
  }

  Widget _buildActions() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (info.status == TorrentStatus.downloading)
          IconButton(icon: const Icon(Icons.pause), onPressed: onPause, tooltip: 'Pause'),
        if (info.status == TorrentStatus.paused)
          IconButton(icon: const Icon(Icons.play_arrow), onPressed: onResume, tooltip: 'Resume'),
        IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: onRemove, tooltip: 'Remove'),
      ],
    );
  }
}

class _DependencyCard extends StatelessWidget {
  final DependencyInfo info;
  final String description;
  final bool isInstalling;
  final double? progress;
  final VoidCallback onInstall;
  final VoidCallback? onUpdate;

  const _DependencyCard({
    required this.info,
    required this.description,
    required this.isInstalling,
    this.progress,
    required this.onInstall,
    this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final isInstalled = info.status == DependencyStatus.installed;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                      Row(
                        children: [
                          Text(info.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          if (isInstalled && info.version != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text('v${info.version}', style: const TextStyle(fontSize: 11, color: Colors.green)),
                            ),
                          ],
                          if (info.needsUpdate) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text('${info.latestVersion} available', style: const TextStyle(fontSize: 11, color: Colors.orange)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(description, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                _buildActionButton(),
              ],
            ),
            if (isInstalling && progress != null) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: Colors.grey.shade200,
                ),
              ),
              const SizedBox(height: 4),
              Text('${(progress! * 100).toInt()}%', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ],
            if (info.error != null) ...[
              const SizedBox(height: 8),
              Text(info.error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
            if (info.lastChecked != null) ...[
              const SizedBox(height: 8),
              Text(
                'Last checked: ${info.lastChecked!.day}/${info.lastChecked!.month} ${info.lastChecked!.hour}:${info.lastChecked!.minute.toString().padLeft(2, '0')}',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon() {
    IconData icon;
    Color color;
    
    switch (info.status) {
      case DependencyStatus.installed:
        icon = Icons.check_circle;
        color = Colors.green;
        break;
      case DependencyStatus.notInstalled:
        icon = Icons.download;
        color = Colors.grey;
        break;
      case DependencyStatus.updating:
        icon = Icons.sync;
        color = Colors.blue;
        break;
      case DependencyStatus.error:
        icon = Icons.error;
        color = Colors.red;
        break;
    }
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 28),
    );
  }

  Widget _buildActionButton() {
    if (isInstalling) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    
    if (info.status == DependencyStatus.notInstalled) {
      return ElevatedButton.icon(
        onPressed: onInstall,
        icon: const Icon(Icons.download, size: 18),
        label: const Text('Install'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
        ),
      );
    }
    
    if (info.needsUpdate && onUpdate != null) {
      return OutlinedButton.icon(
        onPressed: onUpdate,
        icon: const Icon(Icons.system_update, size: 18),
        label: const Text('Update'),
      );
    }
    
    return const Icon(Icons.check, color: Colors.green);
  }
}

// ========== Queue Tab Widgets ==========

class _QueueStat extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _QueueStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('$value', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
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
              
              // Si plusieurs chunks, afficher mini-barres
              if (task.chunkCount > 1 && task.chunkProgresses.isNotEmpty) ...[
                _buildChunkProgressBars(),
                const SizedBox(height: 8),
              ] else ...[
                // Barre unique pour fichiers simples
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: task.progress,
                    minHeight: 6,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation(Color.lerp(Colors.blue, Colors.green, task.progress)!),
                  ),
                ),
              ],
              
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${(task.progress * 100).toInt()}%', style: const TextStyle(fontSize: 12)),
                  if (task.chunkCount > 1)
                    Text('${task.completedChunks}/${task.chunkCount} chunks', style: const TextStyle(fontSize: 12, color: Colors.blue)),
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

  /// Construit les mini-barres de progression pour chaque chunk
  Widget _buildChunkProgressBars() {
    final chunks = task.chunkProgresses;
    final maxPerRow = 8; // Max chunks par ligne
    
    return LayoutBuilder(
      builder: (context, constraints) {
        final barWidth = (constraints.maxWidth - (maxPerRow - 1) * 2) / maxPerRow;
        
        return Wrap(
          spacing: 2,
          runSpacing: 4,
          children: chunks.map((chunk) {
            Color barColor;
            if (chunk.completed) {
              barColor = Colors.green;
            } else if (chunk.failed) {
              barColor = Colors.red;
            } else if (chunk.progress > 0) {
              barColor = Colors.blue;
            } else {
              barColor = Colors.grey.shade300;
            }
            
            return Tooltip(
              message: 'Chunk ${chunk.index + 1}: ${(chunk.progress * 100).toInt()}%',
              child: Container(
                width: barWidth.clamp(20.0, 50.0),
                height: 8,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: Colors.grey.shade200,
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: chunk.progress.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: barColor,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildStatusIcon() {
    IconData icon;
    Color color;
    switch (task.status) {
      case DownloadStatus.queued:
        icon = Icons.hourglass_empty; color = Colors.orange; break;
      case DownloadStatus.downloading:
        icon = Icons.downloading; color = Colors.blue; break;
      case DownloadStatus.paused:
        icon = Icons.pause_circle; color = Colors.grey; break;
      case DownloadStatus.completed:
        icon = Icons.check_circle; color = Colors.green; break;
      case DownloadStatus.failed:
        icon = Icons.error; color = Colors.red; break;
      case DownloadStatus.cancelled:
        icon = Icons.cancel; color = Colors.grey; break;
    }
    return Icon(icon, color: color, size: 28);
  }

  Widget _buildActions() {
    switch (task.status) {
      case DownloadStatus.downloading:
        return Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(icon: const Icon(Icons.pause), onPressed: onPause, tooltip: 'Pause'),
          IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: onCancel, tooltip: 'Cancel'),
        ]);
      case DownloadStatus.paused:
        return Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(icon: const Icon(Icons.play_arrow, color: Colors.green), onPressed: onResume, tooltip: 'Resume'),
          IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: onCancel, tooltip: 'Cancel'),
        ]);
      case DownloadStatus.queued:
        return IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: onCancel, tooltip: 'Cancel');
      case DownloadStatus.completed:
        return Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(icon: const Icon(Icons.save_alt, color: Colors.blue), onPressed: onSave, tooltip: 'Save'),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: onRemove, tooltip: 'Remove'),
        ]);
      case DownloadStatus.failed:
      case DownloadStatus.cancelled:
        return Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(icon: const Icon(Icons.refresh, color: Colors.orange), onPressed: onRetry, tooltip: 'Retry'),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: onRemove, tooltip: 'Remove'),
        ]);
    }
  }
}
