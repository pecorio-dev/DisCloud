import 'dart:typed_data';

enum DownloadStatus { queued, downloading, paused, completed, failed, cancelled }

/// Progress d'un chunk individuel
class ChunkProgress {
  final int index;
  final int size;
  int downloadedBytes;
  double progress;
  bool completed;
  bool failed;
  String? error;

  ChunkProgress({
    required this.index,
    required this.size,
    this.downloadedBytes = 0,
    this.progress = 0,
    this.completed = false,
    this.failed = false,
    this.error,
  });

  ChunkProgress copyWith({
    int? downloadedBytes,
    double? progress,
    bool? completed,
    bool? failed,
    String? error,
  }) {
    return ChunkProgress(
      index: index,
      size: size,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      progress: progress ?? this.progress,
      completed: completed ?? this.completed,
      failed: failed ?? this.failed,
      error: error ?? this.error,
    );
  }
}

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
  
  // Progress par chunk
  List<ChunkProgress> chunkProgresses;

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
    List<ChunkProgress>? chunkProgresses,
  }) : createdAt = createdAt ?? DateTime.now(),
       chunkProgresses = chunkProgresses ?? [];

  int get chunkCount => urls.length;
  
  /// Initialise les progres de chunks si pas encore fait
  void initChunkProgresses(List<int> chunkSizes) {
    if (chunkProgresses.isEmpty) {
      chunkProgresses = List.generate(
        chunkSizes.length, 
        (i) => ChunkProgress(index: i, size: chunkSizes[i]),
      );
    }
  }
  
  /// Met a jour le progress d'un chunk
  void updateChunkProgress(int index, int downloaded, int total) {
    if (index < chunkProgresses.length) {
      chunkProgresses[index] = chunkProgresses[index].copyWith(
        downloadedBytes: downloaded,
        progress: total > 0 ? downloaded / total : 0,
      );
    }
  }
  
  /// Marque un chunk comme complete
  void markChunkCompleted(int index) {
    if (index < chunkProgresses.length) {
      chunkProgresses[index] = chunkProgresses[index].copyWith(
        completed: true,
        progress: 1.0,
      );
    }
  }
  
  /// Marque un chunk comme echoue
  void markChunkFailed(int index, String error) {
    if (index < chunkProgresses.length) {
      chunkProgresses[index] = chunkProgresses[index].copyWith(
        failed: true,
        error: error,
      );
    }
  }
  
  /// Nombre de chunks completes
  int get completedChunks => chunkProgresses.where((c) => c.completed).length;
  
  /// Nombre de chunks en echec
  int get failedChunks => chunkProgresses.where((c) => c.failed).length;
  
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
    bool clearError = false,
    Uint8List? data,
    DateTime? completedAt,
    double? speed,
    List<ChunkProgress>? chunkProgresses,
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
      error: clearError ? null : (error ?? this.error),
      data: data ?? this.data,
      completedAt: completedAt ?? this.completedAt,
      speed: speed ?? this.speed,
      chunkProgresses: chunkProgresses ?? this.chunkProgresses,
    );
  }
}
