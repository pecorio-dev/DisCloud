import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/cloud_file.dart';
import '../models/upload_options.dart';
import 'crypto_service.dart';

enum ChunkStatus { pending, downloading, ready, error }

class ChunkInfo {
  final int index;
  final String url;
  ChunkStatus status;
  Uint8List? data;
  String? error;
  
  ChunkInfo({required this.index, required this.url, this.status = ChunkStatus.pending});
}

/// Service de streaming video avec pre-chargement et decryption
class StreamingService extends ChangeNotifier {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(minutes: 5),
  ));
  
  CloudFile? _currentFile;
  List<ChunkInfo> _chunks = [];
  final Map<int, Uint8List> _chunkCache = {};
  
  int _currentChunkIndex = 0;
  int _bufferAhead = 5; // Nombre de chunks a pre-charger
  int _maxParallel = 3; // Telechargements paralleles
  int _activeDownloads = 0;
  
  bool _isBuffering = false;
  bool _isPaused = false;
  double _bufferProgress = 0;
  int _totalBytesDownloaded = 0;
  
  File? _tempFile;
  RandomAccessFile? _tempRaf;
  String? _encryptionKey;
  
  // Getters
  CloudFile? get currentFile => _currentFile;
  bool get isBuffering => _isBuffering;
  bool get isPaused => _isPaused;
  double get bufferProgress => _bufferProgress;
  int get currentChunk => _currentChunkIndex;
  int get totalChunks => _chunks.length;
  int get bufferedChunks => _chunkCache.length;
  int get totalBytesDownloaded => _totalBytesDownloaded;
  
  bool get hasEnoughBuffer {
    int ready = 0;
    for (int i = _currentChunkIndex; i < _currentChunkIndex + _bufferAhead && i < _chunks.length; i++) {
      if (_chunkCache.containsKey(i)) ready++;
    }
    return ready >= (_bufferAhead / 2).ceil();
  }

  /// Initialise le streaming pour un fichier
  Future<void> initStream(CloudFile file, {String? encryptionKey, int bufferAhead = 5, int maxParallel = 3}) async {
    await dispose();
    
    _currentFile = file;
    _encryptionKey = encryptionKey;
    _bufferAhead = bufferAhead;
    _maxParallel = maxParallel;
    _currentChunkIndex = 0;
    _totalBytesDownloaded = 0;
    
    _chunks = file.chunkUrls.asMap().entries.map((e) => ChunkInfo(index: e.key, url: e.value)).toList();
    
    // Creer fichier temporaire pour le streaming
    final tempDir = await getTemporaryDirectory();
    _tempFile = File('${tempDir.path}/discloud_stream_${DateTime.now().millisecondsSinceEpoch}.tmp');
    
    debugPrint('StreamingService: Initialized for ${file.name}, ${_chunks.length} chunks');
    
    // Commencer le pre-chargement
    _startBuffering();
  }

  /// Demarre le buffering en arriere-plan
  void _startBuffering() {
    if (_isPaused || _currentFile == null) return;
    
    _isBuffering = true;
    notifyListeners();
    
    _fillBuffer();
  }

  Future<void> _fillBuffer() async {
    while (!_isPaused && _currentFile != null) {
      // Trouver les chunks a telecharger
      final toDownload = <int>[];
      for (int i = _currentChunkIndex; i < _currentChunkIndex + _bufferAhead + 2 && i < _chunks.length; i++) {
        if (!_chunkCache.containsKey(i) && _chunks[i].status == ChunkStatus.pending) {
          toDownload.add(i);
        }
      }
      
      if (toDownload.isEmpty) {
        // Buffer plein ou fin atteinte
        await Future.delayed(const Duration(milliseconds: 500));
        continue;
      }
      
      // Telecharger en parallele
      final futures = <Future>[];
      for (final idx in toDownload) {
        if (_activeDownloads >= _maxParallel) break;
        futures.add(_downloadChunk(idx));
      }
      
      if (futures.isNotEmpty) {
        await Future.wait(futures);
      }
      
      // Mettre a jour la progression
      _updateBufferProgress();
      
      // Petit delai pour eviter de surcharger
      await Future.delayed(const Duration(milliseconds: 100));
    }
    
    _isBuffering = false;
    notifyListeners();
  }

  Future<void> _downloadChunk(int index) async {
    if (index >= _chunks.length || _chunkCache.containsKey(index)) return;
    
    final chunk = _chunks[index];
    chunk.status = ChunkStatus.downloading;
    _activeDownloads++;
    notifyListeners();
    
    try {
      debugPrint('StreamingService: Downloading chunk $index');
      
      final response = await _dio.get<List<int>>(
        chunk.url,
        options: Options(responseType: ResponseType.bytes),
      );
      
      if (response.data != null && response.data!.isNotEmpty) {
        var data = Uint8List.fromList(response.data!);
        _totalBytesDownloaded += data.length;
        
        // Decrypter si necessaire
        data = _processChunkData(data, index);
        
        _chunkCache[index] = data;
        chunk.data = data;
        chunk.status = ChunkStatus.ready;
        
        debugPrint('StreamingService: Chunk $index ready (${data.length} bytes)');
      } else {
        chunk.status = ChunkStatus.error;
        chunk.error = 'Empty response';
      }
    } catch (e) {
      chunk.status = ChunkStatus.error;
      chunk.error = e.toString();
      debugPrint('StreamingService: Chunk $index error: $e');
    }
    
    _activeDownloads--;
    notifyListeners();
  }

  /// Traite les donnees d'un chunk (deobfuscation, decryption)
  Uint8List _processChunkData(Uint8List data, int chunkIndex) {
    if (_currentFile == null) return data;
    
    final metadata = _currentFile!.metadata;
    var result = data;
    
    // Pour le premier chunk seulement: enlever fake header
    if (chunkIndex == 0 && metadata['fakeHeaderSize'] != null) {
      result = CryptoService.removeFakeHeader(result);
    }
    
    // Deobfuscation (si appliquee par chunk)
    // Note: normalement l'obfuscation est sur le fichier entier, pas par chunk
    
    return result;
  }

  /// Recupere les donnees d'un chunk (attend si pas encore pret)
  Future<Uint8List?> getChunk(int index, {Duration timeout = const Duration(seconds: 30)}) async {
    if (index >= _chunks.length) return null;
    
    // Si deja en cache
    if (_chunkCache.containsKey(index)) {
      return _chunkCache[index];
    }
    
    // Attendre le telechargement
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_chunkCache.containsKey(index)) {
        return _chunkCache[index];
      }
      
      // S'assurer que le chunk est en cours de telechargement
      if (_chunks[index].status == ChunkStatus.pending) {
        _downloadChunk(index);
      }
      
      await Future.delayed(const Duration(milliseconds: 100));
    }
    
    return null;
  }

  /// Recupere plusieurs chunks merges
  Future<Uint8List?> getChunks(int startIndex, int count) async {
    final chunks = <Uint8List>[];
    
    for (int i = startIndex; i < startIndex + count && i < _chunks.length; i++) {
      final chunk = await getChunk(i);
      if (chunk != null) {
        chunks.add(chunk);
      } else {
        break;
      }
    }
    
    if (chunks.isEmpty) return null;
    
    // Merger
    final totalLength = chunks.fold<int>(0, (sum, c) => sum + c.length);
    final result = Uint8List(totalLength);
    int offset = 0;
    for (final chunk in chunks) {
      result.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    
    return result;
  }

  /// Avance la position de lecture
  void advanceTo(int chunkIndex) {
    if (chunkIndex >= _chunks.length) return;
    
    _currentChunkIndex = chunkIndex;
    
    // Nettoyer les vieux chunks du cache (garder quelques uns en arriere)
    final toRemove = <int>[];
    for (final key in _chunkCache.keys) {
      if (key < _currentChunkIndex - 2) {
        toRemove.add(key);
      }
    }
    for (final key in toRemove) {
      _chunkCache.remove(key);
      _chunks[key].data = null;
      _chunks[key].status = ChunkStatus.pending;
    }
    
    notifyListeners();
    
    // Relancer le buffering si necessaire
    if (!_isBuffering && !_isPaused) {
      _fillBuffer();
    }
  }

  void _updateBufferProgress() {
    if (_chunks.isEmpty) {
      _bufferProgress = 0;
      return;
    }
    
    int ready = 0;
    for (int i = _currentChunkIndex; i < _currentChunkIndex + _bufferAhead && i < _chunks.length; i++) {
      if (_chunkCache.containsKey(i)) ready++;
    }
    
    final targetChunks = (_currentChunkIndex + _bufferAhead < _chunks.length) 
        ? _bufferAhead 
        : _chunks.length - _currentChunkIndex;
    
    _bufferProgress = targetChunks > 0 ? ready / targetChunks : 1.0;
    notifyListeners();
  }

  void pause() {
    _isPaused = true;
    notifyListeners();
  }

  void resume() {
    _isPaused = false;
    _startBuffering();
  }

  /// Telecharge le fichier complet avec decryption
  Future<Uint8List?> downloadFullFile({Function(double)? onProgress}) async {
    if (_currentFile == null) return null;
    
    final chunks = <Uint8List>[];
    
    for (int i = 0; i < _chunks.length; i++) {
      final chunk = await getChunk(i, timeout: const Duration(minutes: 2));
      if (chunk == null) {
        debugPrint('Failed to get chunk $i');
        return null;
      }
      chunks.add(chunk);
      onProgress?.call((i + 1) / _chunks.length);
    }
    
    // Merger tous les chunks
    final totalLength = chunks.fold<int>(0, (sum, c) => sum + c.length);
    var result = Uint8List(totalLength);
    int offset = 0;
    for (final chunk in chunks) {
      result.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    
    // Decrypter le fichier complet si necessaire
    final metadata = _currentFile!.metadata;
    
    if (metadata['contentObfuscation'] != null) {
      final type = ObfuscationType.values[metadata['contentObfuscation'] as int];
      result = CryptoService.deobfuscateContent(result, type);
    }
    
    if (metadata['encrypted'] != null && _encryptionKey != null) {
      final type = EncryptionType.values[metadata['encrypted'] as int];
      result = CryptoService.decryptData(result, type, _encryptionKey);
    }
    
    if (_currentFile!.isCompressed) {
      try {
        if (result.length > 2 && result[0] == 0x1f && result[1] == 0x8b) {
          result = Uint8List.fromList(gzip.decode(result));
        }
      } catch (e) {
        debugPrint('Decompression error: $e');
      }
    }
    
    return result;
  }

  @override
  Future<void> dispose() async {
    _isPaused = true;
    _currentFile = null;
    _chunks.clear();
    _chunkCache.clear();
    
    await _tempRaf?.close();
    await _tempFile?.delete().catchError((_) {});
    
    super.dispose();
  }
}

/// Service de telechargement parallele
class ParallelDownloadService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(minutes: 5),
  ));
  
  /// Telecharge plusieurs URLs en parallele
  Future<List<Uint8List>> downloadParallel(
    List<String> urls, {
    int maxParallel = 4,
    Function(int completed, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final results = List<Uint8List?>.filled(urls.length, null);
    final queue = Queue<int>.from(List.generate(urls.length, (i) => i));
    int completed = 0;
    
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        if (cancelToken?.isCancelled == true) return;
        
        final index = queue.removeFirst();
        
        int retries = 0;
        while (retries < 3 && results[index] == null) {
          try {
            final response = await _dio.get<List<int>>(
              urls[index],
              options: Options(responseType: ResponseType.bytes),
              cancelToken: cancelToken,
            );
            
            if (response.data != null) {
              results[index] = Uint8List.fromList(response.data!);
              completed++;
              onProgress?.call(completed, urls.length);
            }
          } catch (e) {
            retries++;
            if (retries >= 3) {
              throw Exception('Failed to download chunk $index after 3 retries');
            }
            await Future.delayed(Duration(seconds: retries * 2));
          }
        }
      }
    }
    
    // Lancer les workers en parallele
    final workers = List.generate(maxParallel.clamp(1, urls.length), (_) => worker());
    await Future.wait(workers);
    
    // Verifier que tout est telecharge
    for (int i = 0; i < results.length; i++) {
      if (results[i] == null) {
        throw Exception('Missing chunk $i');
      }
    }
    
    return results.cast<Uint8List>();
  }
}
