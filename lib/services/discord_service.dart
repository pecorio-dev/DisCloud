import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

// Fonctions isolees pour compute()
Uint8List _compressIsolate(Uint8List data) {
  try {
    final compressed = gzip.encode(data);
    if (compressed.length < data.length) {
      return Uint8List.fromList(compressed);
    }
  } catch (e) {}
  return data;
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
  final List<Uint8List> chunks = [];
  int offset = 0;
  while (offset < data.length) {
    final end = (offset + maxSize < data.length) ? offset + maxSize : data.length;
    chunks.add(data.sublist(offset, end));
    offset = end;
  }
  return chunks;
}

Uint8List _mergeChunksIsolate(List<Uint8List> chunks) {
  final totalLength = chunks.fold<int>(0, (sum, chunk) => sum + chunk.length);
  final result = Uint8List(totalLength);
  int offset = 0;
  for (final chunk in chunks) {
    result.setRange(offset, offset + chunk.length, chunk);
    offset += chunk.length;
  }
  return result;
}

class DiscordService {
  final String webhookUrl;
  final Dio _dio;
  int _maxChunkSize = 9 * 1024 * 1024;
  bool _enableCompression = true;
  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 2);
  static const Duration _minChunkDelay = Duration(milliseconds: 500);

  int get maxChunkSize => _maxChunkSize;

  DiscordService({required this.webhookUrl})
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 60),
          sendTimeout: const Duration(seconds: 60),
        ));

  String get webhookId {
    final uri = Uri.parse(webhookUrl);
    final parts = uri.pathSegments;
    return parts.length >= 2 ? parts[parts.length - 2] : '';
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final hasNitro = prefs.getBool('hasNitro') ?? false;
    _enableCompression = prefs.getBool('enableCompression') ?? true;
    _maxChunkSize = hasNitro ? 95 * 1024 * 1024 : 9 * 1024 * 1024;
  }

  Future<Uint8List> _compress(Uint8List data) async {
    if (!_enableCompression || data.length < 1024) return data;
    return compute(_compressIsolate, data);
  }

  Future<Uint8List> _decompress(Uint8List data) async {
    return compute(_decompressIsolate, data);
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
      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>;
      }
    } catch (e) {}
    return null;
  }

  Future<List<String>> uploadFile(
    Uint8List fileData,
    String fileName, {
    Function(double)? onProgress,
    CancelToken? cancelToken,
  }) async {
    // Compression en arriere-plan
    final compressedData = await _compress(fileData);
    
    // Split en arriere-plan
    final chunks = await compute(_splitChunksIsolate, {
      'data': compressedData,
      'maxSize': _maxChunkSize,
    });
    
    final List<String> attachmentUrls = [];
    final uuid = const Uuid();

    for (int i = 0; i < chunks.length; i++) {
      if (cancelToken?.isCancelled == true) {
        throw Exception('Upload cancelled');
      }

      final chunk = chunks[i];
      final chunkName = '${uuid.v4()}_${i}_$fileName';

      String? attachmentUrl;
      int retries = 0;

      while (attachmentUrl == null && retries < _maxRetries) {
        try {
          final formData = FormData.fromMap({
            'file': MultipartFile.fromBytes(chunk, filename: chunkName),
            'content': jsonEncode({
              'type': 'discloud_chunk',
              'index': i,
              'total': chunks.length,
              'originalName': fileName,
            }),
          });

          final response = await _dio.post(
            webhookUrl,
            data: formData,
            cancelToken: cancelToken,
            onSendProgress: (sent, total) {
              if (onProgress != null && total > 0) {
                final chunkProgress = sent / total;
                final overallProgress = (i + chunkProgress) / chunks.length;
                onProgress(overallProgress);
              }
            },
          );

          if (response.statusCode == 200 || response.statusCode == 204) {
            final data = response.data;
            if (data is Map<String, dynamic>) {
              final attachments = data['attachments'] as List<dynamic>?;
              if (attachments != null && attachments.isNotEmpty) {
                final url = attachments[0]['url'];
                if (url != null && url is String && url.isNotEmpty) {
                  attachmentUrl = url;
                }
              }
            }
          }

          if (attachmentUrl == null) {
            retries++;
            if (retries < _maxRetries) {
              await Future.delayed(_retryDelay);
            }
          }
        } on DioException catch (e) {
          if (e.type == DioExceptionType.cancel) rethrow;
          
          retries++;
          if (e.response?.statusCode == 429) {
            final retryAfter = e.response?.headers.value('retry-after');
            final waitTime = int.tryParse(retryAfter ?? '5') ?? 5;
            await Future.delayed(Duration(seconds: waitTime + 1));
          } else if (retries < _maxRetries) {
            await Future.delayed(_retryDelay * retries);
          } else {
            throw Exception('Upload chunk $i failed after $_maxRetries retries');
          }
        } catch (e) {
          retries++;
          if (retries >= _maxRetries) {
            throw Exception('Upload chunk $i failed: $e');
          }
          await Future.delayed(_retryDelay);
        }
      }

      if (attachmentUrl == null) {
        throw Exception('No URL for chunk $i after $_maxRetries attempts');
      }

      attachmentUrls.add(attachmentUrl);
      
      // Petit delai entre chunks pour eviter rate limit
      if (i < chunks.length - 1) {
        await Future.delayed(_minChunkDelay);
      }
    }

    if (attachmentUrls.length != chunks.length) {
      throw Exception('Incomplete: ${attachmentUrls.length}/${chunks.length} chunks');
    }

    return attachmentUrls;
  }

  Future<Uint8List> downloadFile(
    List<String> attachmentUrls, {
    Function(double)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final List<Uint8List> chunks = [];

    for (int i = 0; i < attachmentUrls.length; i++) {
      if (cancelToken?.isCancelled == true) {
        throw Exception('Download cancelled');
      }

      Uint8List? chunkData;
      int retries = 0;

      while (chunkData == null && retries < _maxRetries) {
        try {
          final response = await _dio.get<List<int>>(
            attachmentUrls[i],
            options: Options(responseType: ResponseType.bytes),
            cancelToken: cancelToken,
            onReceiveProgress: (received, total) {
              if (onProgress != null && total > 0) {
                final chunkProgress = received / total;
                final overallProgress = (i + chunkProgress) / attachmentUrls.length;
                onProgress(overallProgress);
              }
            },
          );

          if (response.data != null && response.data!.isNotEmpty) {
            chunkData = Uint8List.fromList(response.data!);
          } else {
            retries++;
            if (retries < _maxRetries) await Future.delayed(_retryDelay);
          }
        } on DioException catch (e) {
          if (e.type == DioExceptionType.cancel) rethrow;
          
          retries++;
          if (e.response?.statusCode == 404) {
            throw Exception('Chunk $i not found (deleted from Discord)');
          }
          if (retries >= _maxRetries) {
            throw Exception('Download chunk $i failed after $_maxRetries retries');
          }
          await Future.delayed(_retryDelay * retries);
        } catch (e) {
          retries++;
          if (retries >= _maxRetries) {
            throw Exception('Download chunk $i failed: $e');
          }
          await Future.delayed(_retryDelay);
        }
      }

      if (chunkData == null) {
        throw Exception('No data for chunk $i after $_maxRetries attempts');
      }

      chunks.add(chunkData);
    }

    // Merge en arriere-plan
    final merged = await compute(_mergeChunksIsolate, chunks);
    return await _decompress(merged);
  }

  Future<bool> sendMessage(String content) async {
    try {
      final response = await _dio.post(webhookUrl, data: {'content': content});
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
      return false;
    }
  }
}
