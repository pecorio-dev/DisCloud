import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../models/cloud_file.dart';
import 'discord_service.dart';

enum DownloadStatus { queued, downloading, completed, failed, cancelled }

class DownloadTask {
  final String id;
  final CloudFile file;
  final String? savePath;
  DownloadStatus status;
  double progress;
  String? error;
  CancelToken? cancelToken;
  Uint8List? data;
  DateTime addedAt;

  DownloadTask({
    required this.id,
    required this.file,
    this.savePath,
    this.status = DownloadStatus.queued,
    this.progress = 0,
    this.error,
    this.cancelToken,
    this.data,
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  DownloadTask copyWith({
    DownloadStatus? status,
    double? progress,
    String? error,
    CancelToken? cancelToken,
    Uint8List? data,
  }) {
    return DownloadTask(
      id: id,
      file: file,
      savePath: savePath,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      error: error ?? this.error,
      cancelToken: cancelToken ?? this.cancelToken,
      data: data ?? this.data,
      addedAt: addedAt,
    );
  }
}

class DownloadManager extends ChangeNotifier {
  final List<DownloadTask> _queue = [];
  final Dio _dio = Dio();
  bool _isProcessing = false;
  int _maxConcurrent = 2;

  List<DownloadTask> get queue => List.unmodifiable(_queue);
  List<DownloadTask> get activeDownloads => 
      _queue.where((t) => t.status == DownloadStatus.downloading).toList();
  List<DownloadTask> get pendingDownloads => 
      _queue.where((t) => t.status == DownloadStatus.queued).toList();
  List<DownloadTask> get completedDownloads => 
      _queue.where((t) => t.status == DownloadStatus.completed).toList();

  /// Ajoute un fichier a la queue de telechargement
  String addToQueue(CloudFile file, {String? savePath}) {
    final id = '${file.path}_${DateTime.now().millisecondsSinceEpoch}';
    final task = DownloadTask(
      id: id,
      file: file,
      savePath: savePath,
      cancelToken: CancelToken(),
    );
    _queue.add(task);
    notifyListeners();
    _processQueue();
    return id;
  }

  /// Ajoute plusieurs fichiers a la queue
  List<String> addMultipleToQueue(List<CloudFile> files, {String? savePath}) {
    final ids = <String>[];
    for (final file in files) {
      if (!file.isDirectory) {
        ids.add(addToQueue(file, savePath: savePath));
      }
    }
    return ids;
  }

  /// Annule un telechargement
  void cancelDownload(String taskId) {
    final index = _queue.indexWhere((t) => t.id == taskId);
    if (index >= 0) {
      final task = _queue[index];
      task.cancelToken?.cancel('Cancelled by user');
      _queue[index] = task.copyWith(
        status: DownloadStatus.cancelled,
        error: 'Cancelled',
      );
      notifyListeners();
    }
  }

  /// Annule tous les telechargements
  void cancelAll() {
    for (int i = 0; i < _queue.length; i++) {
      final task = _queue[i];
      if (task.status == DownloadStatus.queued || 
          task.status == DownloadStatus.downloading) {
        task.cancelToken?.cancel('Cancelled by user');
        _queue[i] = task.copyWith(
          status: DownloadStatus.cancelled,
          error: 'Cancelled',
        );
      }
    }
    notifyListeners();
  }

  /// Supprime un telechargement de la queue
  void removeFromQueue(String taskId) {
    final index = _queue.indexWhere((t) => t.id == taskId);
    if (index >= 0) {
      final task = _queue[index];
      if (task.status == DownloadStatus.downloading) {
        task.cancelToken?.cancel();
      }
      _queue.removeAt(index);
      notifyListeners();
    }
  }

  /// Supprime les telechargements termines
  void clearCompleted() {
    _queue.removeWhere((t) => 
        t.status == DownloadStatus.completed || 
        t.status == DownloadStatus.cancelled ||
        t.status == DownloadStatus.failed);
    notifyListeners();
  }

  /// Reessayer un telechargement echoue
  void retryDownload(String taskId) {
    final index = _queue.indexWhere((t) => t.id == taskId);
    if (index >= 0) {
      _queue[index] = _queue[index].copyWith(
        status: DownloadStatus.queued,
        progress: 0,
        error: null,
        cancelToken: CancelToken(),
      );
      notifyListeners();
      _processQueue();
    }
  }

  /// Recupere les donnees d'un telechargement termine
  Uint8List? getData(String taskId) {
    final task = _queue.firstWhere((t) => t.id == taskId, 
        orElse: () => throw Exception('Task not found'));
    return task.data;
  }

  Future<void> _processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    while (true) {
      // Trouver les taches en attente
      final pending = _queue.where((t) => t.status == DownloadStatus.queued).toList();
      final active = _queue.where((t) => t.status == DownloadStatus.downloading).length;

      if (pending.isEmpty || active >= _maxConcurrent) break;

      // Demarrer une nouvelle tache
      final task = pending.first;
      final index = _queue.indexOf(task);
      _queue[index] = task.copyWith(status: DownloadStatus.downloading);
      notifyListeners();

      // Lancer le telechargement en arriere-plan
      _downloadFile(task);
    }

    _isProcessing = false;
  }

  Future<void> _downloadFile(DownloadTask task) async {
    final index = _queue.indexWhere((t) => t.id == task.id);
    if (index < 0) return;

    try {
      final file = task.file;
      final List<Uint8List> chunks = [];
      
      // Determiner les URLs a utiliser
      List<String> urls = [];
      if (file.webhookChunks.isNotEmpty) {
        urls = file.webhookChunks.values.first;
      } else if (file.chunkIds.isNotEmpty) {
        urls = file.chunkIds;
      }

      if (urls.isEmpty) {
        throw Exception('No download URLs');
      }

      // Telecharger chaque chunk
      for (int i = 0; i < urls.length; i++) {
        if (task.cancelToken?.isCancelled ?? false) {
          throw Exception('Cancelled');
        }

        final response = await _dio.get<List<int>>(
          urls[i],
          options: Options(responseType: ResponseType.bytes),
          cancelToken: task.cancelToken,
          onReceiveProgress: (received, total) {
            if (total > 0) {
              final chunkProgress = received / total;
              final overallProgress = (i + chunkProgress) / urls.length;
              _updateProgress(task.id, overallProgress);
            }
          },
        );

        if (response.data != null) {
          chunks.add(Uint8List.fromList(response.data!));
        }
      }

      // Fusionner les chunks
      final totalLength = chunks.fold<int>(0, (sum, c) => sum + c.length);
      final result = Uint8List(totalLength);
      int offset = 0;
      for (final chunk in chunks) {
        result.setRange(offset, offset + chunk.length, chunk);
        offset += chunk.length;
      }

      // Decompresser si necessaire
      Uint8List finalData = result;
      if (result.length > 2 && result[0] == 0x1f && result[1] == 0x8b) {
        try {
          finalData = Uint8List.fromList(gzip.decode(result));
        } catch (e) {
          // Pas compresse ou erreur
        }
      }

      // Sauvegarder si chemin specifie
      if (task.savePath != null) {
        final outFile = File('${task.savePath}/${file.name}');
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(finalData);
      }

      _updateTask(task.id, DownloadStatus.completed, data: finalData);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        _updateTask(task.id, DownloadStatus.cancelled, error: 'Cancelled');
      } else {
        _updateTask(task.id, DownloadStatus.failed, error: e.message);
      }
    } catch (e) {
      _updateTask(task.id, DownloadStatus.failed, error: e.toString());
    }

    // Continuer avec la queue
    _processQueue();
  }

  void _updateProgress(String taskId, double progress) {
    final index = _queue.indexWhere((t) => t.id == taskId);
    if (index >= 0) {
      _queue[index] = _queue[index].copyWith(progress: progress);
      notifyListeners();
    }
  }

  void _updateTask(String taskId, DownloadStatus status, {String? error, Uint8List? data}) {
    final index = _queue.indexWhere((t) => t.id == taskId);
    if (index >= 0) {
      _queue[index] = _queue[index].copyWith(
        status: status,
        error: error,
        data: data,
        progress: status == DownloadStatus.completed ? 1.0 : _queue[index].progress,
      );
      notifyListeners();
    }
  }
}
