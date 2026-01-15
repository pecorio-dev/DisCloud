import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class ImageViewer extends StatefulWidget {
  final Uint8List imageData;
  final String fileName;
  final List<Uint8List>? allImages;
  final List<String>? allNames;
  final int initialIndex;

  const ImageViewer({
    super.key,
    required this.imageData,
    required this.fileName,
    this.allImages,
    this.allNames,
    this.initialIndex = 0,
  });

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> with SingleTickerProviderStateMixin {
  late TransformationController _transformController;
  late int _currentIndex;
  double _rotation = 0;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _transformController = TransformationController();
    _currentIndex = widget.initialIndex;
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  Uint8List get _currentImage => widget.allImages?[_currentIndex] ?? widget.imageData;
  String get _currentName => widget.allNames?[_currentIndex] ?? widget.fileName;
  bool get _hasMultiple => (widget.allImages?.length ?? 1) > 1;

  void _resetTransform() {
    _transformController.value = Matrix4.identity();
    setState(() => _rotation = 0);
  }

  void _rotate(double degrees) {
    setState(() => _rotation += degrees);
  }

  void _nextImage() {
    if (_currentIndex < (widget.allImages?.length ?? 1) - 1) {
      setState(() {
        _currentIndex++;
        _resetTransform();
      });
    }
  }

  void _previousImage() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _resetTransform();
      });
    }
  }

  Future<void> _saveImage() async {
    try {
      final directory = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_currentName');
      await file.writeAsBytes(_currentImage);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved to: ${file.path}'), backgroundColor: Colors.green),
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.grey.shade900,
      appBar: _showControls ? AppBar(
        backgroundColor: Colors.transparent,
        title: Text(_currentName, style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.rotate_left),
            onPressed: () => _rotate(-90),
            tooltip: 'Rotate left',
          ),
          IconButton(
            icon: const Icon(Icons.rotate_right),
            onPressed: () => _rotate(90),
            tooltip: 'Rotate right',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _resetTransform,
            tooltip: 'Reset',
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _saveImage,
            tooltip: 'Save',
          ),
        ],
      ) : null,
      body: GestureDetector(
        onTap: () => setState(() => _showControls = !_showControls),
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                transformationController: _transformController,
                minScale: 0.5,
                maxScale: 5.0,
                child: Transform.rotate(
                  angle: _rotation * 3.14159 / 180,
                  child: Image.memory(
                    _currentImage,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            if (_hasMultiple && _showControls) ...[
              Positioned(
                left: 16,
                top: 0,
                bottom: 0,
                child: Center(
                  child: IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(Icons.chevron_left, color: Colors.white, size: 32),
                    ),
                    onPressed: _currentIndex > 0 ? _previousImage : null,
                  ),
                ),
              ),
              Positioned(
                right: 16,
                top: 0,
                bottom: 0,
                child: Center(
                  child: IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(Icons.chevron_right, color: Colors.white, size: 32),
                    ),
                    onPressed: _currentIndex < (widget.allImages!.length - 1) ? _nextImage : null,
                  ),
                ),
              ),
              Positioned(
                bottom: 20,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_currentIndex + 1} / ${widget.allImages!.length}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
