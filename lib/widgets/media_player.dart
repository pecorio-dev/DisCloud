import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class AudioPlayer extends StatefulWidget {
  final Uint8List data;
  final String fileName;

  const AudioPlayer({
    super.key,
    required this.data,
    required this.fileName,
  });

  @override
  State<AudioPlayer> createState() => _AudioPlayerState();
}

class _AudioPlayerState extends State<AudioPlayer> {
  bool _isPlaying = false;
  double _progress = 0;
  String? _tempFilePath;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prepareTempFile();
  }

  Future<void> _prepareTempFile() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/${widget.fileName}');
      await file.writeAsBytes(widget.data);
      setState(() {
        _tempFilePath = file.path;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fileName),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [const Color(0xFF2D2D2D), const Color(0xFF1A1A1A)]
                : [Colors.indigo.shade100, Colors.indigo.shade50],
          ),
        ),
        child: Center(
          child: _isLoading
              ? const CircularProgressIndicator()
              : _error != null
                  ? _buildError()
                  : _buildPlayer(isDark),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error_outline, size: 64, color: Colors.red),
        const SizedBox(height: 16),
        Text('Error: $_error'),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _prepareTempFile,
          child: const Text('Retry'),
        ),
      ],
    );
  }

  Widget _buildPlayer(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              color: isDark ? Colors.grey.shade800 : Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Icon(
              _getFileIcon(),
              size: 80,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            widget.fileName,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            _formatFileSize(widget.data.length),
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 32),
          Slider(
            value: _progress,
            onChanged: (value) => setState(() => _progress = value),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatDuration(_progress * 180)),
              const Text('3:00'),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.skip_previous),
                iconSize: 36,
                onPressed: () => setState(() => _progress = 0),
              ),
              const SizedBox(width: 16),
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                  iconSize: 48,
                  color: Colors.white,
                  onPressed: () => setState(() => _isPlaying = !_isPlaying),
                ),
              ),
              const SizedBox(width: 16),
              IconButton(
                icon: const Icon(Icons.skip_next),
                iconSize: 36,
                onPressed: () => setState(() => _progress = 1),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Text(
            'Audio playback requires platform-specific implementation.\nFile saved to: $_tempFilePath',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.folder_open),
            label: const Text('Open in System Player'),
            onPressed: () {
              // Would open with system default player
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('File at: $_tempFilePath')),
              );
            },
          ),
        ],
      ),
    );
  }

  IconData _getFileIcon() {
    final ext = widget.fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'mp3':
      case 'wav':
      case 'ogg':
      case 'flac':
      case 'm4a':
        return Icons.music_note;
      case 'mp4':
      case 'avi':
      case 'mkv':
      case 'mov':
      case 'webm':
        return Icons.video_file;
      default:
        return Icons.audio_file;
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDuration(double seconds) {
    final mins = (seconds / 60).floor();
    final secs = (seconds % 60).floor();
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }
}

class VideoPlayer extends StatelessWidget {
  final Uint8List data;
  final String fileName;

  const VideoPlayer({
    super.key,
    required this.data,
    required this.fileName,
  });

  @override
  Widget build(BuildContext context) {
    return AudioPlayer(data: data, fileName: fileName);
  }
}
