import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../models/cloud_file.dart';
import '../services/streaming_service.dart';

class CloudVideoPlayer extends StatefulWidget {
  final CloudFile file;
  final String? encryptionKey;

  const CloudVideoPlayer({
    super.key,
    required this.file,
    this.encryptionKey,
  });

  @override
  State<CloudVideoPlayer> createState() => _CloudVideoPlayerState();
}

class _CloudVideoPlayerState extends State<CloudVideoPlayer> {
  final StreamingService _streamingService = StreamingService();
  
  bool _isLoading = true;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _hasError = false;
  String? _errorMessage;
  double _progress = 0;
  double _bufferProgress = 0;
  
  File? _tempVideoFile;
  int _downloadedChunks = 0;
  int _totalChunks = 0;
  double _downloadSpeed = 0;
  DateTime? _downloadStartTime;
  int _lastBytesDownloaded = 0;
  Timer? _speedTimer;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  @override
  void dispose() {
    _speedTimer?.cancel();
    _streamingService.dispose();
    _tempVideoFile?.delete().catchError((_) {});
    super.dispose();
  }

  Future<void> _initPlayer() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
      _totalChunks = widget.file.chunkUrls.length;
    });

    try {
      // Initialiser le service de streaming
      await _streamingService.initStream(
        widget.file,
        encryptionKey: widget.encryptionKey,
        bufferAhead: 5,
        maxParallel: 4,
      );
      
      // Ecouter les mises a jour
      _streamingService.addListener(_onStreamUpdate);
      
      // Calculer la vitesse
      _downloadStartTime = DateTime.now();
      _speedTimer = Timer.periodic(const Duration(seconds: 1), (_) => _updateSpeed());
      
      // Attendre le buffer initial
      await _waitForInitialBuffer();
      
      setState(() {
        _isLoading = false;
      });
      
    } catch (e) {
      setState(() {
        _hasError = true;
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _waitForInitialBuffer() async {
    // Attendre que les premiers chunks soient prets
    while (!_streamingService.hasEnoughBuffer && mounted) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  void _onStreamUpdate() {
    if (!mounted) return;
    setState(() {
      _bufferProgress = _streamingService.bufferProgress;
      _downloadedChunks = _streamingService.bufferedChunks;
      _isBuffering = _streamingService.isBuffering && !_streamingService.hasEnoughBuffer;
    });
  }

  void _updateSpeed() {
    final currentBytes = _streamingService.totalBytesDownloaded;
    final elapsed = DateTime.now().difference(_downloadStartTime!).inSeconds;
    if (elapsed > 0) {
      setState(() {
        _downloadSpeed = (currentBytes - _lastBytesDownloaded).toDouble();
        _lastBytesDownloaded = currentBytes;
      });
    }
  }

  Future<void> _downloadFullVideo() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final data = await _streamingService.downloadFullFile(
        onProgress: (p) {
          setState(() {
            _progress = p;
          });
        },
      );

      if (data != null) {
        // Sauvegarder dans un fichier temporaire
        final tempDir = await getTemporaryDirectory();
        _tempVideoFile = File('${tempDir.path}/${widget.file.name}');
        await _tempVideoFile!.writeAsBytes(data);

        setState(() {
          _isLoading = false;
        });
        
        // Ouvrir avec le lecteur systeme
        if (mounted) {
          _showVideoReadyDialog();
        }
      }
    } catch (e) {
      setState(() {
        _hasError = true;
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  void _showVideoReadyDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Video Ready'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 64),
            const SizedBox(height: 16),
            Text('${widget.file.name} is ready!'),
            const SizedBox(height: 8),
            Text('Size: ${widget.file.formattedSize}'),
            if (_tempVideoFile != null) ...[
              const SizedBox(height: 8),
              Text('Saved to: ${_tempVideoFile!.path}', style: const TextStyle(fontSize: 11)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _openWithSystemPlayer();
            },
            icon: const Icon(Icons.play_arrow),
            label: const Text('Open'),
          ),
        ],
      ),
    );
  }

  Future<void> _openWithSystemPlayer() async {
    if (_tempVideoFile == null || !await _tempVideoFile!.exists()) return;
    
    // Sur Windows, ouvrir avec le lecteur par defaut
    if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', _tempVideoFile!.path]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [_tempVideoFile!.path]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [_tempVideoFile!.path]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.file.name, style: const TextStyle(fontSize: 14)),
        actions: [
          if (!_isLoading && !_hasError)
            IconButton(
              icon: const Icon(Icons.save_alt),
              onPressed: _saveVideo,
              tooltip: 'Save video',
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_hasError) {
      return _buildErrorView();
    }
    
    return Column(
      children: [
        // Zone video
        Expanded(
          child: Center(
            child: _isLoading ? _buildLoadingView() : _buildPlayerView(),
          ),
        ),
        
        // Infos et controles
        _buildControlBar(),
      ],
    );
  }

  Widget _buildLoadingView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Animation de chargement
        SizedBox(
          width: 120,
          height: 120,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 100,
                height: 100,
                child: CircularProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  strokeWidth: 6,
                  color: Colors.blue,
                  backgroundColor: Colors.grey.shade800,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_download, color: Colors.blue, size: 32),
                  if (_progress > 0)
                    Text('${(_progress * 100).toInt()}%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 24),
        
        Text(
          'Downloading video...',
          style: TextStyle(color: Colors.grey.shade400, fontSize: 16),
        ),
        
        const SizedBox(height: 8),
        
        Text(
          '$_downloadedChunks / $_totalChunks chunks',
          style: TextStyle(color: Colors.grey.shade600),
        ),
        
        if (_downloadSpeed > 0) ...[
          const SizedBox(height: 4),
          Text(
            '${(_downloadSpeed / 1024 / 1024).toStringAsFixed(1)} MB/s',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
        
        const SizedBox(height: 32),
        
        // Buffer indicator
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Buffer', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                  Text('${(_bufferProgress * 100).toInt()}%', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _bufferProgress,
                  minHeight: 8,
                  backgroundColor: Colors.grey.shade800,
                  valueColor: const AlwaysStoppedAnimation(Colors.green),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPlayerView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Preview
        Container(
          width: 300,
          height: 200,
          decoration: BoxDecoration(
            color: Colors.grey.shade900,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.movie, size: 64, color: Colors.grey.shade700),
              const SizedBox(height: 16),
              Text(widget.file.name, style: TextStyle(color: Colors.grey.shade500, fontSize: 12), textAlign: TextAlign.center),
            ],
          ),
        ),
        
        const SizedBox(height: 32),
        
        // Play button
        ElevatedButton.icon(
          onPressed: _downloadFullVideo,
          icon: const Icon(Icons.play_circle_filled, size: 32),
          label: const Text('Download & Play', style: TextStyle(fontSize: 16)),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Info
        if (widget.file.isEncrypted)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock, color: Colors.orange, size: 16),
              const SizedBox(width: 4),
              Text('Encrypted video', style: TextStyle(color: Colors.orange.shade300, fontSize: 12)),
            ],
          ),
      ],
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 64),
          const SizedBox(height: 16),
          const Text('Failed to load video', style: TextStyle(color: Colors.white, fontSize: 18)),
          const SizedBox(height: 8),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(_errorMessage!, style: TextStyle(color: Colors.grey.shade500, fontSize: 12), textAlign: TextAlign.center),
            ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _initPlayer,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildControlBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        border: Border(top: BorderSide(color: Colors.grey.shade800)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // File info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.file.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _InfoChip(icon: Icons.storage, label: widget.file.formattedSize),
                      const SizedBox(width: 8),
                      _InfoChip(icon: Icons.layers, label: '$_totalChunks chunks'),
                      if (widget.file.isEncrypted) ...[
                        const SizedBox(width: 8),
                        const _InfoChip(icon: Icons.lock, label: 'Encrypted', color: Colors.orange),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            
            // Buffer status
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _streamingService.hasEnoughBuffer ? Colors.green.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _streamingService.hasEnoughBuffer ? Icons.check : Icons.hourglass_empty,
                    size: 16,
                    color: _streamingService.hasEnoughBuffer ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _streamingService.hasEnoughBuffer ? 'Ready' : 'Buffering',
                    style: TextStyle(
                      color: _streamingService.hasEnoughBuffer ? Colors.green : Colors.orange,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveVideo() async {
    // Telecharger et sauvegarder
    await _downloadFullVideo();
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _InfoChip({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.grey.shade500;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: c),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: c, fontSize: 11)),
      ],
    );
  }
}
