import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/download_task.dart';
import '../models/upload_options.dart';
import '../services/crypto_service.dart';

class DownloadManager extends ChangeNotifier {
  final Dio _dio = Dio();
  final _uuid = const Uuid();
  
  final List<DownloadTask> _tasks = [];
  final Map<String, CancelToken> _cancelTokens = {};
  int _maxConcurrent = 2;
  bool _isProcessing = false;
  String? _globalEncryptionKey;

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);
  List<DownloadTask> get activeTasks => _tasks.where((t) => t.status == DownloadStatus.downloading).toList();
  List<DownloadTask> get queuedTasks => _tasks.where((t) => t.status == DownloadStatus.queued).toList();
  List<DownloadTask> get completedTasks => _tasks.where((t) => t.status == DownloadStatus.completed).toList();
  List<DownloadTask> get failedTasks => _tasks.where((t) => t.status == DownloadStatus.failed).toList();
  
  int get totalTasks => _tasks.length;
  int get activeCount => activeTasks.length;
  double get overallProgress {
    if (_tasks.isEmpty) return 0;
    return _tasks.fold<double>(0, (sum, t) => sum + t.progress) / _tasks.length;
  }

  void setMaxConcurrent(int max) {
    _maxConcurrent = max.clamp(1, 5);
  }

  void setGlobalEncryptionKey(String? key) {
    _globalEncryptionKey = key;
  }

  /// Ajoute un telechargement a la queue
  String addDownload({
    required String name,
    required int size,
    required List<String> urls,
    bool isCompressed = false,
    String? checksum,
    Map<String, dynamic> metadata = const {},
    String? savePath,
  }) {
    final task = DownloadTask(
      id: _uuid.v4(),
      name: name,
      size: size,
      urls: urls,
      isCompressed: isCompressed,
      checksum: checksum,
      metadata: metadata,
      savePath: savePath,
    );
    
    _tasks.insert(0, task);
    notifyListeners();
    _processQueue();
    return task.id;
  }

  /// Ajoute plusieurs telechargements
  List<String> addMultipleDownloads(List<Map<String, dynamic>> downloads) {
    final ids = <String>[];
    for (final dl in downloads) {
      ids.add(addDownload(
        name: dl['name'],
        size: dl['size'],
        urls: List<String>.from(dl['urls']),
        isCompressed: dl['isCompressed'] ?? false,
        checksum: dl['checksum'],
        metadata: Map<String, dynamic>.from(dl['metadata'] ?? {}),
        savePath: dl['savePath'],
      ));
    }
    return ids;
  }

  void pauseDownload(String id) {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index >= 0 && _tasks[index].status == DownloadStatus.downloading) {
      _cancelTokens[id]?.cancel('Paused');
      _tasks[index] = _tasks[index].copyWith(status: DownloadStatus.paused);
      notifyListeners();
    }
  }

  void resumeDownload(String id) {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index >= 0 && _tasks[index].status == DownloadStatus.paused) {
      _tasks[index] = _tasks[index].copyWith(status: DownloadStatus.queued);
      notifyListeners();
      _processQueue();
    }
  }

  void cancelDownload(String id) {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index >= 0) {
      _cancelTokens[id]?.cancel('Cancelled');
      _tasks[index] = _tasks[index].copyWith(status: DownloadStatus.cancelled);
      notifyListeners();
    }
  }

  void retryDownload(String id) {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index >= 0 && (_tasks[index].status == DownloadStatus.failed || _tasks[index].status == DownloadStatus.cancelled)) {
      _tasks[index] = _tasks[index].copyWith(
        status: DownloadStatus.queued,
        progress: 0,
        downloadedBytes: 0,
        currentChunk: 0,
        error: null,
      );
      notifyListeners();
      _processQueue();
    }
  }

  void removeTask(String id) {
    _cancelTokens[id]?.cancel('Removed');
    _tasks.removeWhere((t) => t.id == id);
    _cancelTokens.remove(id);
    notifyListeners();
  }

  void clearCompleted() {
    _tasks.removeWhere((t) => t.status == DownloadStatus.completed || t.status == DownloadStatus.cancelled);
    notifyListeners();
  }

  void clearAll() {
    for (final token in _cancelTokens.values) {
      token.cancel('Cleared');
    }
    _tasks.clear();
    _cancelTokens.clear();
    notifyListeners();
  }

  Future<void> _processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    while (activeTasks.length < _maxConcurrent && queuedTasks.isNotEmpty) {
      final task = queuedTasks.first;
      _downloadTask(task);
    }

    _isProcessing = false;
  }

  Future<void> _downloadTask(DownloadTask task) async {
    final index = _tasks.indexWhere((t) => t.id == task.id);
    if (index < 0) return;

    // Initialiser les progressions de chunks
    final initialChunkSizes = List.generate(task.urls.length, (_) => 0);
    task.initChunkProgresses(initialChunkSizes);
    
    _tasks[index] = task.copyWith(status: DownloadStatus.downloading);
    notifyListeners();

    final cancelToken = CancelToken();
    _cancelTokens[task.id] = cancelToken;

    final chunks = <Uint8List>[];
    final startTime = DateTime.now();
    int totalDownloaded = 0;

    try {
      for (int i = task.currentChunk; i < task.urls.length; i++) {
        if (cancelToken.isCancelled) break;

        final response = await _dio.get<List<int>>(
          task.urls[i],
          options: Options(responseType: ResponseType.bytes),
          cancelToken: cancelToken,
          onReceiveProgress: (received, total) {
            final elapsed = DateTime.now().difference(startTime).inMilliseconds / 1000;
            final speed = elapsed > 0 ? (totalDownloaded + received) / elapsed : 0;
            
            // Mettre a jour le progress du chunk actuel
            _tasks[index].updateChunkProgress(i, received, total > 0 ? total : received);
            
            _tasks[index] = _tasks[index].copyWith(
              progress: (i + received / (total > 0 ? total : 1)) / task.urls.length.toDouble(),
              downloadedBytes: totalDownloaded + received,
              currentChunk: i,
              speed: speed.toDouble(),
            );
            notifyListeners();
          },
        );

        if (response.data != null) {
          chunks.add(Uint8List.fromList(response.data!));
          totalDownloaded += response.data!.length;
          
          // Marquer le chunk comme complete
          _tasks[index].markChunkCompleted(i);
          notifyListeners();
        }
      }

      if (cancelToken.isCancelled) {
        _processQueue();
        return;
      }

      // Merge chunks
      var result = _mergeChunks(chunks);

      // Remove fake headers
      if (task.metadata['fakeHeaderSize'] != null) {
        result = CryptoService.removeFakeHeader(result);
      }

      // Deobfuscate content
      if (task.metadata['contentObfuscation'] != null) {
        final type = ObfuscationType.values[task.metadata['contentObfuscation'] as int];
        result = CryptoService.deobfuscateContent(result, type);
      }

      // Decrypt
      if (task.metadata['encrypted'] != null) {
        final key = _globalEncryptionKey;
        if (key != null) {
          final type = EncryptionType.values[task.metadata['encrypted'] as int];
          result = CryptoService.decryptData(result, type, key);
        }
      }

      // Decompress
      if (task.isCompressed) {
        result = Uint8List.fromList(gzip.decode(result));
      }

      // Verify checksum
      if (task.checksum != null) {
        final currentChecksum = CryptoService.sha256Hash(result);
        if (currentChecksum != task.checksum) {
          throw Exception('Checksum verification failed');
        }
      }

      // Save to file if path specified
      if (task.savePath != null) {
        final file = File('${task.savePath}/${task.name}');
        await file.writeAsBytes(result);
      }

      _tasks[index] = _tasks[index].copyWith(
        status: DownloadStatus.completed,
        progress: 1,
        data: result,
        completedAt: DateTime.now(),
      );
      notifyListeners();

    } catch (e) {
      if (!e.toString().contains('cancel')) {
        _tasks[index] = _tasks[index].copyWith(
          status: DownloadStatus.failed,
          error: e.toString(),
        );
        notifyListeners();
      }
    }

    _cancelTokens.remove(task.id);
    _processQueue();
  }

  Uint8List _mergeChunks(List<Uint8List> chunks) {
    final totalLength = chunks.fold<int>(0, (sum, chunk) => sum + chunk.length);
    final result = Uint8List(totalLength);
    int offset = 0;
    for (final chunk in chunks) {
      result.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return result;
  }

  /// Telecharge et sauvegarde immediatement
  Future<String?> downloadAndSave(DownloadTask task) async {
    try {
      final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      final id = addDownload(
        name: task.name,
        size: task.size,
        urls: task.urls,
        isCompressed: task.isCompressed,
        checksum: task.checksum,
        metadata: task.metadata,
        savePath: dir.path,
      );

      // Attendre la fin du telechargement
      while (true) {
        await Future.delayed(const Duration(milliseconds: 100));
        final t = _tasks.firstWhere((t) => t.id == id, orElse: () => task);
        if (t.status == DownloadStatus.completed) {
          return '${dir.path}/${task.name}';
        } else if (t.status == DownloadStatus.failed || t.status == DownloadStatus.cancelled) {
          return null;
        }
      }
    } catch (e) {
      return null;
    }
  }
}
