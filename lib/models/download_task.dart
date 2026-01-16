import 'dart:typed_data';

enum DownloadStatus { queued, downloading, paused, completed, failed, cancelled }

class DownloadTask {
  final String id;
  final String name;
  final int size;
  final List<String> urls;
  final bool isCompressed;
  final String? checksum;
  final Map<String, dynamic> metadata;
  final String? savePath;
  final DateTime createdAt;
  
  DownloadStatus status;
  double progress;
  int downloadedBytes;
  int currentChunk;
  String? error;
  Uint8List? data;
  DateTime? completedAt;
  double speed; // bytes per second

  DownloadTask({
    required this.id,
    required this.name,
    required this.size,
    required this.urls,
    this.isCompressed = false,
    this.checksum,
    this.metadata = const {},
    this.savePath,
    DateTime? createdAt,
    this.status = DownloadStatus.queued,
    this.progress = 0,
    this.downloadedBytes = 0,
    this.currentChunk = 0,
    this.error,
    this.data,
    this.completedAt,
    this.speed = 0,
  }) : createdAt = createdAt ?? DateTime.now();

  int get chunkCount => urls.length;
  
  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  
  String get formattedSpeed {
    if (speed < 1024) return '${speed.toInt()} B/s';
    if (speed < 1024 * 1024) return '${(speed / 1024).toStringAsFixed(1)} KB/s';
    return '${(speed / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }
  
  String get formattedETA {
    if (speed <= 0 || progress >= 1) return '--';
    final remaining = size - downloadedBytes;
    final seconds = remaining / speed;
    if (seconds < 60) return '${seconds.toInt()}s';
    if (seconds < 3600) return '${(seconds / 60).toInt()}m';
    return '${(seconds / 3600).toInt()}h ${((seconds % 3600) / 60).toInt()}m';
  }
  
  bool get isEncrypted => metadata['encrypted'] != null;
  
  DownloadTask copyWith({
    DownloadStatus? status,
    double? progress,
    int? downloadedBytes,
    int? currentChunk,
    String? error,
    Uint8List? data,
    DateTime? completedAt,
    double? speed,
  }) {
    return DownloadTask(
      id: id,
      name: name,
      size: size,
      urls: urls,
      isCompressed: isCompressed,
      checksum: checksum,
      metadata: metadata,
      savePath: savePath,
      createdAt: createdAt,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      currentChunk: currentChunk ?? this.currentChunk,
      error: error ?? this.error,
      data: data ?? this.data,
      completedAt: completedAt ?? this.completedAt,
      speed: speed ?? this.speed,
    );
  }
}
