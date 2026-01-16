import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/cloud_provider.dart';
import '../services/universal_downloader.dart';
import '../services/torrent_service.dart';

class DownloadCenterScreen extends StatefulWidget {
  const DownloadCenterScreen({super.key});

  @override
  State<DownloadCenterScreen> createState() => _DownloadCenterScreenState();
}

class _DownloadCenterScreenState extends State<DownloadCenterScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  final UniversalDownloader _downloader = UniversalDownloader();
  final TorrentService _torrentService = TorrentService();
  
  final _urlController = TextEditingController();
  final _batchController = TextEditingController();
  
  bool _isExtracting = false;
  bool _isDownloading = false;
  double _progress = 0;
  String? _status;
  List<ExtractedVideo>? _extractedVideos;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _downloader.init();
    _torrentService.addListener(() => setState(() {}));
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
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.link), text: 'Direct URL'),
            Tab(icon: Icon(Icons.video_library), text: 'Video'),
            Tab(icon: Icon(Icons.cloud_download), text: 'Torrent'),
            Tab(icon: Icon(Icons.list), text: 'Batch'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDirectTab(),
          _buildVideoTab(),
          _buildTorrentTab(),
          _buildBatchTab(),
        ],
      ),
    );
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
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Video Downloader', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    SizedBox(height: 4),
                    Text('YouTube, Uqload, Vimeo, and more', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
              if (!_downloader.ytDlpAvailable)
                TextButton.icon(
                  onPressed: _installYtDlp,
                  icon: const Icon(Icons.download),
                  label: const Text('Install yt-dlp'),
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
                    Text(
                      _torrentService.isRunning ? 'Service running' : 'Service stopped',
                      style: TextStyle(color: _torrentService.isRunning ? Colors.green : Colors.grey),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _torrentService.isRunning,
                onChanged: (v) async {
                  if (v) await _torrentService.start();
                  else await _torrentService.stop();
                },
              ),
            ],
          ),
          
          const SizedBox(height: 8),
          const Text('Download torrents directly to Discord without storing locally', style: TextStyle(color: Colors.grey)),
          
          const SizedBox(height: 24),
          
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
          
          if (!_torrentService.isRunning)
            Container(
              margin: const EdgeInsets.only(top: 24),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.info, color: Colors.orange),
                  const SizedBox(height: 8),
                  const Text('Requires aria2c', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text('Install aria2 to enable torrent downloads', style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => _openUrl('https://aria2.github.io/'),
                    child: const Text('Download aria2'),
                  ),
                ],
              ),
            ),
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

    setState(() {
      _isExtracting = true;
      _extractedVideos = null;
      _error = null;
    });

    try {
      final videos = await _downloader.extractVideoInfo(url);
      setState(() => _extractedVideos = videos);
      
      if (videos.isEmpty) {
        setState(() => _error = 'No videos found. Try installing yt-dlp for better support.');
      }
    } catch (e) {
      setState(() => _error = e.toString());
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

  Future<void> _installYtDlp() async {
    setState(() {
      _isDownloading = true;
      _status = 'Downloading yt-dlp...';
      _progress = 0;
    });

    final success = await _downloader.downloadYtDlp(
      onProgress: (p) => setState(() => _progress = p),
    );

    setState(() => _isDownloading = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'yt-dlp installed!' : 'Failed to install yt-dlp'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
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
