import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/upload_options.dart';
import 'crypto_service.dart';

// Isolate functions
Map<String, dynamic> _compressIsolate(Map<String, dynamic> params) {
  final Uint8List data = params['data'];
  final int level = params['level'];
  
  if (level == 0) return {'data': data, 'compressed': false};
  
  try {
    final codec = level == 1 ? GZipCodec(level: 1) 
                 : level == 2 ? GZipCodec(level: 6)
                 : GZipCodec(level: 9);
    final compressed = codec.encode(data);
    if (compressed.length < data.length * 0.95) {
      return {'data': Uint8List.fromList(compressed), 'compressed': true};
    }
  } catch (e) {}
  return {'data': data, 'compressed': false};
}

Uint8List _decompressIsolate(Uint8List data) {
  try {
    if (data.length > 2 && data[0] == 0x1f && data[1] == 0x8b) {
      return Uint8List.fromList(gzip.decode(data));
    }
  } catch (e) {}
  return data;
}

List<Uint8List> _splitChunksIsolate(Map<String, dynamic> params) {
  final Uint8List data = params['data'];
  final int maxSize = params['maxSize'];
  final bool randomOrder = params['randomOrder'] ?? false;
  
  final List<Uint8List> chunks = [];
  int offset = 0;
  while (offset < data.length) {
    final end = (offset + maxSize < data.length) ? offset + maxSize : data.length;
    chunks.add(data.sublist(offset, end));
    offset = end;
  }
  
  if (randomOrder && chunks.length > 1) {
    final indexed = <Uint8List>[];
    for (int i = 0; i < chunks.length; i++) {
      final header = Uint8List(4);
      header.buffer.asByteData().setUint32(0, i, Endian.big);
      indexed.add(Uint8List.fromList([...header, ...chunks[i]]));
    }
    indexed.shuffle(Random());
    return indexed;
  }
  
  return chunks;
}

class UploadResult {
  final List<String> urls;
  final List<String> messageIds;
  final bool isCompressed;
  final String? checksum;
  final Map<String, dynamic> metadata;
  
  UploadResult({
    required this.urls,
    required this.messageIds,
    required this.isCompressed,
    this.checksum,
    this.metadata = const {},
  });
}

class DiscordService {
  final String webhookUrl;
  final Dio _dio;
  static const int _maxRetries = 5;
  static const Duration _retryDelay = Duration(seconds: 3);

  DiscordService({required this.webhookUrl})
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(minutes: 10), // Plus long pour gros fichiers
          sendTimeout: const Duration(minutes: 5),
        ));

  String get webhookId {
    final uri = Uri.parse(webhookUrl);
    final parts = uri.pathSegments;
    return parts.length >= 2 ? parts[parts.length - 2] : '';
  }

  String get webhookToken {
    final uri = Uri.parse(webhookUrl);
    return uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
  }

  Future<bool> validateWebhook() async {
    try {
      final response = await _dio.get(webhookUrl);
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> getWebhookInfo() async {
    try {
      final response = await _dio.get(webhookUrl);
      if (response.statusCode == 200) return response.data as Map<String, dynamic>;
    } catch (e) {}
    return null;
  }

  static const _compressedExtensions = {
    'jpg', 'jpeg', 'png', 'gif', 'webp', 'mp4', 'mkv', 'avi', 'mov',
    'mp3', 'aac', 'ogg', 'flac', 'zip', 'rar', '7z', 'gz', 'bz2', 'xz',
    'pdf', 'docx', 'xlsx', 'pptx',
  };

  bool _isAlreadyCompressed(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return _compressedExtensions.contains(ext);
  }

  /// Upload un fichier avec options avancees
  Future<UploadResult> uploadFile(
    Uint8List fileData,
    String fileName, {
    UploadOptions options = const UploadOptions(),
    Function(double)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final metadata = <String, dynamic>{};
    Uint8List dataToProcess = fileData;
    bool wasCompressed = false;
    String? checksum;

    // 1. Checksum original
    if (options.calculateChecksum) {
      checksum = CryptoService.sha256Hash(fileData);
      metadata['originalChecksum'] = checksum;
      metadata['originalSize'] = fileData.length;
    }

    // 2. Compression
    final shouldCompress = options.compressionLevel != CompressionLevel.none &&
        (!options.adaptiveCompression || !_isAlreadyCompressed(fileName));
    
    if (shouldCompress) {
      final result = await compute(_compressIsolate, {
        'data': dataToProcess,
        'level': options.compressionLevel.index,
      });
      dataToProcess = result['data'] as Uint8List;
      wasCompressed = result['compressed'] as bool;
      if (wasCompressed) {
        metadata['compressionRatio'] = (fileData.length / dataToProcess.length).toStringAsFixed(2);
      }
    }

    // 3. Encryption
    if (options.encryptionType != EncryptionType.none && options.encryptionKey != null) {
      dataToProcess = CryptoService.encryptData(dataToProcess, options.encryptionType, options.encryptionKey);
      metadata['encrypted'] = options.encryptionType.index;
    }

    // 4. Content obfuscation
    if (options.contentObfuscation != ObfuscationType.none) {
      dataToProcess = CryptoService.obfuscateContent(dataToProcess, options.contentObfuscation);
      metadata['contentObfuscation'] = options.contentObfuscation.index;
    }

    // 5. Fake headers
    if (options.addFakeHeaders) {
      dataToProcess = CryptoService.addFakeHeader(dataToProcess, options.fakeHeaderSize);
      metadata['fakeHeaderSize'] = options.fakeHeaderSize;
    }

    // 6. Filename obfuscation
    String uploadFileName = fileName;
    if (options.filenameObfuscation != ObfuscationType.none) {
      uploadFileName = CryptoService.obfuscateFilename(fileName, options.filenameObfuscation);
      metadata['originalFilename'] = fileName;
      metadata['filenameObfuscation'] = options.filenameObfuscation.index;
    }

    // 7. Chunking
    final maxChunk = options.chunkSizeKB * 1024;
    final chunks = await compute(_splitChunksIsolate, {
      'data': dataToProcess,
      'maxSize': maxChunk,
      'randomOrder': options.randomizeChunkOrder,
    });
    
    if (options.randomizeChunkOrder) {
      metadata['randomizedChunks'] = true;
    }
    
    metadata['totalChunks'] = chunks.length;

    // 8. Upload
    final List<String> urls = [];
    final List<String> messageIds = [];
    final random = Random();
    final chunkDelay = options.addRandomDelays
        ? () => Duration(milliseconds: options.minDelayMs + random.nextInt(options.maxDelayMs - options.minDelayMs))
        : () => const Duration(milliseconds: 600);

    for (int i = 0; i < chunks.length; i++) {
      if (cancelToken?.isCancelled == true) throw Exception('Cancelled');

      final chunk = chunks[i];
      String? url;
      String? msgId;

      final copies = options.enableRedundancy ? options.redundancyCopies : 1;
      final copyUrls = <String>[];
      final copyMsgIds = <String>[];

      for (int copy = 0; copy < copies; copy++) {
        int retries = 0;
        while (url == null && retries < _maxRetries) {
          try {
            final formData = FormData.fromMap({
              'file': MultipartFile.fromBytes(chunk, filename: '${i}_$uploadFileName'),
            });

            final response = await _dio.post(
              '$webhookUrl?wait=true',
              data: formData,
              cancelToken: cancelToken,
              onSendProgress: (sent, total) {
                if (onProgress != null && total > 0) {
                  onProgress((i + sent / total) / chunks.length);
                }
              },
            );

            if (response.statusCode == 200) {
              final data = response.data;
              if (data is Map<String, dynamic>) {
                msgId = data['id']?.toString();
                final attachments = data['attachments'] as List<dynamic>?;
                if (attachments != null && attachments.isNotEmpty) {
                  url = attachments[0]['url']?.toString();
                }
              }
            }

            if (url == null) {
              retries++;
              if (retries < _maxRetries) await Future.delayed(_retryDelay);
            }
          } on DioException catch (e) {
            if (e.type == DioExceptionType.cancel) rethrow;
            retries++;
            if (e.response?.statusCode == 429) {
              final wait = int.tryParse(e.response?.headers.value('retry-after') ?? '5') ?? 5;
              await Future.delayed(Duration(seconds: wait + 1));
            } else if (retries < _maxRetries) {
              await Future.delayed(_retryDelay * retries);
            } else {
              throw Exception('Chunk $i failed after $retries retries');
            }
          }
        }

        if (url != null) {
          copyUrls.add(url);
          if (msgId != null) copyMsgIds.add(msgId);
        }

        if (copy < copies - 1) {
          await Future.delayed(chunkDelay());
          url = null;
          msgId = null;
        }
      }

      if (copyUrls.isEmpty) throw Exception('No URL for chunk $i');
      
      urls.add(copyUrls.first);
      messageIds.addAll(copyMsgIds);
      
      if (copies > 1 && copyUrls.length > 1) {
        metadata['redundantUrls_$i'] = copyUrls.sublist(1);
      }

      if (options.verifyAfterUpload) {
        try {
          final verifyResponse = await _dio.get<List<int>>(
            copyUrls.first,
            options: Options(responseType: ResponseType.bytes),
          );
          if (verifyResponse.data == null || verifyResponse.data!.length != chunk.length) {
            throw Exception('Verification failed for chunk $i');
          }
        } catch (e) {
          debugPrint('Verify failed: $e');
        }
      }

      if (i < chunks.length - 1) await Future.delayed(chunkDelay());
    }

    return UploadResult(
      urls: urls,
      messageIds: messageIds,
      isCompressed: wasCompressed,
      checksum: checksum,
      metadata: metadata,
    );
  }

  /// Telecharge un fichier complet - avec telechargement parallele
  Future<Uint8List> downloadFile(
    List<String> urls, {
    bool isCompressed = false,
    Map<String, dynamic> metadata = const {},
    String? encryptionKey,
    Function(double)? onProgress,
    CancelToken? cancelToken,
    int maxParallel = 4, // Nombre de telechargements paralleles
  }) async {
    debugPrint('Starting download: ${urls.length} chunks (parallel: $maxParallel)');
    
    final totalChunks = urls.length;
    final estimatedSize = metadata['originalSize'] as int? ?? 0;
    final wasRandomized = metadata['randomizedChunks'] == true;
    
    // Pour les gros fichiers, utiliser le telechargement parallele avec streaming
    if (totalChunks > 10 || estimatedSize > 100 * 1024 * 1024) {
      return _downloadParallelLargeFile(
        urls, 
        maxParallel: maxParallel,
        isCompressed: isCompressed, 
        metadata: metadata, 
        encryptionKey: encryptionKey, 
        onProgress: onProgress, 
        cancelToken: cancelToken,
      );
    }

    // Pour les petits fichiers, telechargement parallele en memoire
    final chunks = await _downloadChunksParallel(
      urls, 
      maxParallel: maxParallel,
      metadata: metadata,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );

    debugPrint('All chunks downloaded, merging...');
    return _processDownloadedData(chunks, wasRandomized, isCompressed, metadata, encryptionKey);
  }

  /// Telecharge les chunks en parallele
  Future<List<Uint8List>> _downloadChunksParallel(
    List<String> urls, {
    required int maxParallel,
    required Map<String, dynamic> metadata,
    Function(double)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final results = List<Uint8List?>.filled(urls.length, null);
    final queue = List<int>.generate(urls.length, (i) => i);
    int completed = 0;
    int activeDownloads = 0;
    final completer = Completer<void>();
    
    Future<void> downloadWorker() async {
      while (queue.isNotEmpty && !(cancelToken?.isCancelled ?? false)) {
        final index = queue.removeAt(0);
        activeDownloads++;
        
        try {
          final data = await _downloadSingleChunk(
            urls[index], 
            index, 
            urls.length, 
            (p) {
              // Progress pour ce chunk
            },
            cancelToken,
            metadata: metadata,
          );
          
          results[index] = data;
          completed++;
          onProgress?.call(completed / urls.length);
          debugPrint('Chunk $index completed ($completed/${urls.length})');
          
        } catch (e) {
          debugPrint('Chunk $index failed: $e');
          // Re-ajouter a la queue pour retry
          if (!queue.contains(index)) {
            queue.add(index);
          }
        }
        
        activeDownloads--;
      }
    }
    
    // Lancer les workers en parallele
    final workers = <Future>[];
    for (int i = 0; i < maxParallel.clamp(1, urls.length); i++) {
      workers.add(downloadWorker());
    }
    
    await Future.wait(workers);
    
    if (cancelToken?.isCancelled ?? false) {
      throw Exception('Cancelled');
    }
    
    // Verifier que tout est telecharge
    for (int i = 0; i < results.length; i++) {
      if (results[i] == null) {
        throw Exception('Missing chunk $i');
      }
    }
    
    return results.cast<Uint8List>();
  }

  /// Telechargement parallele de gros fichiers avec streaming vers fichier temporaire
  Future<Uint8List> _downloadParallelLargeFile(
    List<String> urls, {
    int maxParallel = 4,
    bool isCompressed = false,
    Map<String, dynamic> metadata = const {},
    String? encryptionKey,
    Function(double)? onProgress,
    CancelToken? cancelToken,
  }) async {
    debugPrint('Large file parallel download: ${urls.length} chunks (parallel: $maxParallel)');
    
    final tempDir = await getTemporaryDirectory();
    final wasRandomized = metadata['randomizedChunks'] == true;
    
    // Telecharger tous les chunks en parallele
    final chunks = await _downloadChunksParallel(
      urls,
      maxParallel: maxParallel,
      metadata: metadata,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
    
    // Si randomized, reordonner
    if (wasRandomized) {
      return _processDownloadedData(chunks, true, isCompressed, metadata, encryptionKey);
    }
    
    // Sauvegarder dans un fichier temporaire pour eviter les problemes memoire
    final tempFile = File('${tempDir.path}/discloud_download_${DateTime.now().millisecondsSinceEpoch}.tmp');
    final sink = tempFile.openWrite();
    
    try {
      int totalWritten = 0;
      for (final chunk in chunks) {
        sink.add(chunk);
        totalWritten += chunk.length;
      }
      
      await sink.close();
      debugPrint('All chunks saved to temp file: ${(totalWritten / 1024 / 1024).toStringAsFixed(1)} MB');
      
      // Lire le fichier complet
      var result = await tempFile.readAsBytes();
      debugPrint('Total merged size: ${result.length} bytes');
      
      // Nettoyer
      await tempFile.delete();
      
      // Process (sans randomized car deja fait)
      return _processDownloadedData([result], false, isCompressed, metadata, encryptionKey);
      
    } catch (e) {
      await sink.close();
      if (await tempFile.exists()) await tempFile.delete();
      rethrow;
    }
  }

  Future<Uint8List> _downloadSingleChunk(
    String url, 
    int index, 
    int total, 
    Function(double)? onProgress, 
    CancelToken? cancelToken, {
    Map<String, dynamic>? metadata,
  }) async {
    int retries = 0;
    
    while (retries < _maxRetries) {
      try {
        final response = await _dio.get<List<int>>(
          url,
          options: Options(responseType: ResponseType.bytes),
          cancelToken: cancelToken,
          onReceiveProgress: (recv, totalBytes) {
            if (onProgress != null) {
              final chunkProgress = totalBytes > 0 ? recv / totalBytes : 0.0;
              onProgress((index + chunkProgress) / total);
            }
          },
        );
        
        if (response.data != null && response.data!.isNotEmpty) {
          return Uint8List.fromList(response.data!);
        }
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) rethrow;
        
        // Essayer URL de redundance si 404
        if (e.response?.statusCode == 404 && metadata != null) {
          final redundantUrls = metadata['redundantUrls_$index'] as List<String>?;
          if (redundantUrls != null && redundantUrls.isNotEmpty) {
            debugPrint('Trying redundant URL for chunk $index');
            try {
              final response = await _dio.get<List<int>>(redundantUrls.first, options: Options(responseType: ResponseType.bytes));
              if (response.data != null) return Uint8List.fromList(response.data!);
            } catch (_) {}
          }
        }
        
        retries++;
        if (retries >= _maxRetries) {
          throw Exception('Download chunk $index failed after $retries retries: ${e.message}');
        }
        debugPrint('Retry $retries for chunk $index: ${e.message}');
        await Future.delayed(_retryDelay * retries);
      }
    }
    
    throw Exception('Failed to download chunk $index');
  }

  Uint8List _processDownloadedData(
    List<Uint8List> chunks,
    bool wasRandomized,
    bool isCompressed,
    Map<String, dynamic> metadata,
    String? encryptionKey,
  ) {
    // Merge chunks
    Uint8List result;
    
    if (wasRandomized && chunks.length > 1) {
      // Reordonner selon l'index dans le header de chaque chunk
      final indexed = <int, Uint8List>{};
      for (final chunk in chunks) {
        if (chunk.length >= 4) {
          final idx = chunk.buffer.asByteData().getUint32(0, Endian.big);
          indexed[idx] = Uint8List.fromList(chunk.sublist(4));
        }
      }
      final ordered = List.generate(indexed.length, (i) => indexed[i]!);
      result = _mergeChunks(ordered);
    } else if (chunks.length == 1) {
      result = chunks.first;
    } else {
      result = _mergeChunks(chunks);
    }
    
    debugPrint('Merged size: ${result.length} bytes');

    // Remove fake headers
    if (metadata['fakeHeaderSize'] != null) {
      result = CryptoService.removeFakeHeader(result);
      debugPrint('After removing fake header: ${result.length} bytes');
    }

    // Deobfuscate content
    if (metadata['contentObfuscation'] != null) {
      final type = ObfuscationType.values[metadata['contentObfuscation'] as int];
      result = CryptoService.deobfuscateContent(result, type);
      debugPrint('After deobfuscation: ${result.length} bytes');
    }

    // Decrypt
    if (metadata['encrypted'] != null && encryptionKey != null) {
      final type = EncryptionType.values[metadata['encrypted'] as int];
      result = CryptoService.decryptData(result, type, encryptionKey);
      debugPrint('After decryption: ${result.length} bytes');
    }

    // Decompress
    if (isCompressed) {
      try {
        if (result.length > 2 && result[0] == 0x1f && result[1] == 0x8b) {
          result = Uint8List.fromList(gzip.decode(result));
          debugPrint('After decompression: ${result.length} bytes');
        }
      } catch (e) {
        debugPrint('Decompression error: $e');
      }
    }

    // Verify checksum
    if (metadata['originalChecksum'] != null) {
      final currentChecksum = CryptoService.sha256Hash(result);
      if (currentChecksum != metadata['originalChecksum']) {
        debugPrint('WARNING: Checksum mismatch! Expected: ${metadata['originalChecksum']}, Got: $currentChecksum');
      } else {
        debugPrint('Checksum verified OK');
      }
    }
    
    // Verify size
    if (metadata['originalSize'] != null) {
      final expectedSize = metadata['originalSize'] as int;
      if (result.length != expectedSize) {
        debugPrint('WARNING: Size mismatch! Expected: $expectedSize, Got: ${result.length}');
      } else {
        debugPrint('Size verified OK: ${result.length} bytes');
      }
    }

    return result;
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

  /// Supprime des messages Discord par leurs IDs
  Future<int> deleteMessages(List<String> messageIds) async {
    int deleted = 0;
    for (final msgId in messageIds) {
      try {
        final response = await _dio.delete('$webhookUrl/messages/$msgId');
        if (response.statusCode == 204 || response.statusCode == 200) deleted++;
        await Future.delayed(const Duration(milliseconds: 300));
      } catch (e) {
        debugPrint('Failed to delete message $msgId: $e');
      }
    }
    return deleted;
  }

  /// Envoie un message texte (pour l'index)
  Future<String?> sendMessage(String content, {String? filename, Uint8List? fileData}) async {
    try {
      if (fileData != null && filename != null) {
        final formData = FormData.fromMap({
          'file': MultipartFile.fromBytes(fileData, filename: filename),
          if (content.isNotEmpty) 'content': content,
        });
        final response = await _dio.post('$webhookUrl?wait=true', data: formData);
        if (response.statusCode == 200) return response.data['id']?.toString();
      } else {
        final response = await _dio.post('$webhookUrl?wait=true', data: {'content': content});
        if (response.statusCode == 200) return response.data['id']?.toString();
      }
    } catch (e) {
      debugPrint('sendMessage error: $e');
    }
    return null;
  }

  /// Edite un message existant
  Future<bool> editMessage(String messageId, {String? content, Uint8List? fileData, String? filename}) async {
    try {
      if (fileData != null && filename != null) {
        final formData = FormData.fromMap({
          'file': MultipartFile.fromBytes(fileData, filename: filename),
          if (content != null) 'content': content,
        });
        final response = await _dio.patch('$webhookUrl/messages/$messageId', data: formData);
        return response.statusCode == 200;
      } else {
        final response = await _dio.patch('$webhookUrl/messages/$messageId', data: {'content': content});
        return response.statusCode == 200;
      }
    } catch (e) {
      debugPrint('editMessage error: $e');
    }
    return false;
  }

  /// Recupere un message par son ID
  Future<Map<String, dynamic>?> getMessage(String messageId) async {
    try {
      final response = await _dio.get('$webhookUrl/messages/$messageId');
      if (response.statusCode == 200) return response.data;
    } catch (e) {}
    return null;
  }
}
