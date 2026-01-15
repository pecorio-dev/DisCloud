import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DiscordService {
  final String webhookUrl;
  final Dio _dio;
  int _maxChunkSize = 9 * 1024 * 1024; // 9MB default
  bool _enableCompression = true;
  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 2);

  int get maxChunkSize => _maxChunkSize;

  DiscordService({required this.webhookUrl})
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 120),
          sendTimeout: const Duration(seconds: 120),
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

  Uint8List _compress(Uint8List data) {
    if (!_enableCompression) return data;
    try {
      final compressed = gzip.encode(data);
      if (compressed.length < data.length) {
        return Uint8List.fromList(compressed);
      }
    } catch (e) {
      // Compression failed
    }
    return data;
  }

  Uint8List _decompress(Uint8List data) {
    try {
      if (data.length > 2 && data[0] == 0x1f && data[1] == 0x8b) {
        return Uint8List.fromList(gzip.decode(data));
      }
    } catch (e) {
      // Not compressed
    }
    return data;
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
    } catch (e) {
      // Error
    }
    return null;
  }

  Future<List<String>> uploadFile(
    Uint8List fileData,
    String fileName, {
    Function(double)? onProgress,
  }) async {
    final compressedData = _compress(fileData);
    final chunks = _splitIntoChunks(compressedData);
    final List<String> attachmentUrls = [];
    final uuid = const Uuid();

    for (int i = 0; i < chunks.length; i++) {
      final chunk = chunks[i];
      final chunkName = '${uuid.v4()}_${i}_$fileName';

      String? attachmentUrl;
      int retries = 0;

      // Retry loop for each chunk
      while (attachmentUrl == null && retries < _maxRetries) {
        try {
          final formData = FormData.fromMap({
            'file': MultipartFile.fromBytes(
              chunk,
              filename: chunkName,
            ),
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
            onSendProgress: (sent, total) {
              if (onProgress != null && total > 0) {
                final chunkProgress = sent / total;
                final overallProgress = (i + chunkProgress) / chunks.length;
                onProgress(overallProgress);
              }
            },
          );

          // Check for attachment URL in response
          if (response.statusCode == 200) {
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

          // If no URL found, wait and retry
          if (attachmentUrl == null) {
            retries++;
            if (retries < _maxRetries) {
              await Future.delayed(_retryDelay);
            }
          }
        } on DioException catch (e) {
          retries++;
          if (e.response?.statusCode == 429) {
            // Rate limited - wait longer
            final retryAfter = e.response?.headers.value('retry-after');
            final waitTime = int.tryParse(retryAfter ?? '5') ?? 5;
            await Future.delayed(Duration(seconds: waitTime + 1));
          } else if (retries < _maxRetries) {
            await Future.delayed(_retryDelay * retries);
          } else {
            throw Exception('Failed to upload chunk $i after $_maxRetries retries: $e');
          }
        } catch (e) {
          retries++;
          if (retries >= _maxRetries) {
            throw Exception('Failed to upload chunk $i: $e');
          }
          await Future.delayed(_retryDelay);
        }
      }

      if (attachmentUrl == null) {
        throw Exception('Failed to get attachment URL for chunk $i after $_maxRetries attempts');
      }

      attachmentUrls.add(attachmentUrl);
    }

    // Verify all chunks were uploaded
    if (attachmentUrls.length != chunks.length) {
      throw Exception(
        'Upload incomplete: got ${attachmentUrls.length} URLs for ${chunks.length} chunks'
      );
    }

    return attachmentUrls;
  }

  Future<Uint8List> downloadFile(
    List<String> attachmentUrls, {
    Function(double)? onProgress,
  }) async {
    final List<Uint8List> chunks = [];

    for (int i = 0; i < attachmentUrls.length; i++) {
      Uint8List? chunkData;
      int retries = 0;

      while (chunkData == null && retries < _maxRetries) {
        try {
          final response = await _dio.get<List<int>>(
            attachmentUrls[i],
            options: Options(responseType: ResponseType.bytes),
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
            if (retries < _maxRetries) {
              await Future.delayed(_retryDelay);
            }
          }
        } on DioException catch (e) {
          retries++;
          if (e.response?.statusCode == 404) {
            throw Exception('Chunk $i not found (file may have been deleted from Discord)');
          }
          if (retries >= _maxRetries) {
            throw Exception('Failed to download chunk $i after $_maxRetries retries: $e');
          }
          await Future.delayed(_retryDelay * retries);
        } catch (e) {
          retries++;
          if (retries >= _maxRetries) {
            throw Exception('Failed to download chunk $i: $e');
          }
          await Future.delayed(_retryDelay);
        }
      }

      if (chunkData == null) {
        throw Exception('Failed to download chunk $i after $_maxRetries attempts');
      }

      chunks.add(chunkData);
    }

    final merged = _mergeChunks(chunks);
    return _decompress(merged);
  }

  Future<bool> sendMessage(String content) async {
    try {
      final response = await _dio.post(webhookUrl, data: {'content': content});
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
      return false;
    }
  }

  List<Uint8List> _splitIntoChunks(Uint8List data) {
    final List<Uint8List> chunks = [];
    int offset = 0;

    while (offset < data.length) {
      final end = (offset + _maxChunkSize < data.length)
          ? offset + _maxChunkSize
          : data.length;
      chunks.add(data.sublist(offset, end));
      offset = end;
    }

    return chunks;
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
}
