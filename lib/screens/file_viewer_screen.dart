import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../models/cloud_file.dart';
import '../providers/cloud_provider.dart';
import '../widgets/image_viewer.dart';
import '../widgets/code_viewer.dart';
import '../widgets/text_viewer.dart';
import '../widgets/media_player.dart';
import '../widgets/cloud_video_player.dart';

enum FileType {
  image,
  video,
  audio,
  code,
  text,
  pdf,
  archive,
  unknown,
}

class FileViewerScreen extends StatefulWidget {
  final CloudFile file;
  final Uint8List? data; // Optional - will download if not provided
  final Function(Uint8List)? onSave;

  const FileViewerScreen({
    super.key,
    required this.file,
    this.data,
    this.onSave,
  });

  @override
  State<FileViewerScreen> createState() => _FileViewerScreenState();
}

class _FileViewerScreenState extends State<FileViewerScreen> {
  late FileType _fileType;
  late String _language;
  Uint8List? _data;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fileType = _detectFileType(widget.file.extension);
    _language = _getLanguage(widget.file.extension);
    _data = widget.data;
    
    if (_data == null) {
      _loadData();
    } else {
      _isLoading = false;
    }
  }

  Future<void> _loadData() async {
    try {
      final provider = context.read<CloudProvider>();
      final data = await provider.downloadFile(widget.file);
      if (mounted) {
        setState(() {
          _data = data;
          _isLoading = false;
          if (data == null) _error = 'Failed to download file';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  FileType _detectFileType(String ext) {
    switch (ext.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
      case 'bmp':
      case 'ico':
      case 'svg':
        return FileType.image;
      case 'mp4':
      case 'avi':
      case 'mkv':
      case 'mov':
      case 'webm':
      case 'wmv':
      case 'flv':
        return FileType.video;
      case 'mp3':
      case 'wav':
      case 'ogg':
      case 'flac':
      case 'm4a':
      case 'aac':
      case 'wma':
        return FileType.audio;
      case 'dart':
      case 'py':
      case 'js':
      case 'ts':
      case 'jsx':
      case 'tsx':
      case 'java':
      case 'kt':
      case 'swift':
      case 'cpp':
      case 'c':
      case 'h':
      case 'cs':
      case 'go':
      case 'rs':
      case 'rb':
      case 'php':
      case 'html':
      case 'css':
      case 'scss':
      case 'sass':
      case 'less':
      case 'json':
      case 'xml':
      case 'yaml':
      case 'yml':
      case 'toml':
      case 'sql':
      case 'sh':
      case 'bash':
      case 'zsh':
      case 'bat':
      case 'ps1':
      case 'r':
      case 'lua':
      case 'perl':
      case 'scala':
      case 'groovy':
      case 'vue':
      case 'svelte':
        return FileType.code;
      case 'txt':
      case 'md':
      case 'markdown':
      case 'log':
      case 'csv':
      case 'ini':
      case 'cfg':
      case 'conf':
      case 'env':
      case 'gitignore':
      case 'dockerignore':
        return FileType.text;
      case 'pdf':
        return FileType.pdf;
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
      case 'bz2':
      case 'xz':
        return FileType.archive;
      default:
        return FileType.unknown;
    }
  }

  String _getLanguage(String ext) {
    switch (ext.toLowerCase()) {
      case 'py':
        return 'python';
      case 'js':
      case 'jsx':
        return 'javascript';
      case 'ts':
      case 'tsx':
        return 'typescript';
      case 'dart':
        return 'dart';
      case 'java':
        return 'java';
      case 'kt':
        return 'kotlin';
      case 'swift':
        return 'swift';
      case 'cpp':
      case 'c':
      case 'h':
        return 'cpp';
      case 'cs':
        return 'csharp';
      case 'go':
        return 'go';
      case 'rs':
        return 'rust';
      case 'rb':
        return 'ruby';
      case 'php':
        return 'php';
      case 'html':
        return 'html';
      case 'css':
      case 'scss':
      case 'sass':
      case 'less':
        return 'css';
      case 'json':
        return 'json';
      case 'xml':
        return 'xml';
      case 'yaml':
      case 'yml':
        return 'yaml';
      case 'sql':
        return 'sql';
      case 'sh':
      case 'bash':
      case 'zsh':
      case 'bat':
      case 'ps1':
        return 'shell';
      default:
        return ext;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Loading state
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.file.name)),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading file...'),
            ],
          ),
        ),
      );
    }

    // Error state
    if (_error != null || _data == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.file.name)),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(_error ?? 'Failed to load file'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _error = null;
                  });
                  _loadData();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    switch (_fileType) {
      case FileType.image:
        return ImageViewer(
          imageData: _data!,
          fileName: widget.file.name,
        );
      case FileType.video:
        // Utiliser le lecteur video avec streaming et decryption
        final provider = context.read<CloudProvider>();
        return CloudVideoPlayer(
          file: widget.file,
          encryptionKey: provider.encryptionKey,
        );
      case FileType.audio:
        return AudioPlayer(
          data: _data!,
          fileName: widget.file.name,
        );
      case FileType.code:
        return CodeViewer(
          data: _data!,
          fileName: widget.file.name,
          language: _language,
          onSave: widget.onSave,
        );
      case FileType.text:
        return TextViewer(
          data: _data!,
          fileName: widget.file.name,
          onSave: widget.onSave,
        );
      case FileType.pdf:
        return _buildPdfViewer();
      case FileType.archive:
        return _buildArchiveViewer();
      case FileType.unknown:
      default:
        return _buildUnknownViewer();
    }
  }

  Widget _buildPdfViewer() {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.file.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _downloadFile,
            tooltip: 'Download',
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.picture_as_pdf, size: 80, color: Colors.red.shade700),
            ),
            const SizedBox(height: 24),
            Text(
              widget.file.name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              widget.file.formattedSize,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),
            const Text(
              'PDF preview requires additional package',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _downloadFile,
              icon: const Icon(Icons.download),
              label: const Text('Download to view'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArchiveViewer() {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.file.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _downloadFile,
            tooltip: 'Download',
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.folder_zip, size: 80, color: Colors.amber.shade700),
            ),
            const SizedBox(height: 24),
            Text(
              widget.file.name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              widget.file.formattedSize,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),
            const Text(
              'Archive file - download to extract',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _downloadFile,
              icon: const Icon(Icons.download),
              label: const Text('Download'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnknownViewer() {
    // Try to display as text if it looks like text
    bool isText = false;
    String? textContent;
    
    try {
      textContent = utf8.decode(_data!);
      // Check if it looks like text (no control characters except newlines/tabs)
      isText = !textContent.contains(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'));
    } catch (e) {
      isText = false;
    }

    if (isText && textContent != null) {
      return TextViewer(
        data: _data!,
        fileName: widget.file.name,
        onSave: widget.onSave,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.file.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _downloadFile,
            tooltip: 'Download',
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.insert_drive_file, size: 80, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),
            Text(
              widget.file.name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              widget.file.formattedSize,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            Text(
              'Type: .${widget.file.extension}',
              style: TextStyle(color: Colors.grey.shade500),
            ),
            const SizedBox(height: 24),
            const Text(
              'Preview not available for this file type',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _downloadFile,
              icon: const Icon(Icons.download),
              label: const Text('Download'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadFile() async {
    try {
      if (kIsWeb) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Use browser download for web')),
        );
        return;
      }

      final directory = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/${widget.file.name}';
      final file = File(filePath);
      await file.writeAsBytes(_data!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to: $filePath'),
            backgroundColor: Colors.green,
            action: SnackBarAction(
              label: 'Open',
              textColor: Colors.white,
              onPressed: () {
                // Would open file with system default app
              },
            ),
          ),
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
