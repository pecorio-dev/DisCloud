import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

Uint8List _compressIsolate(Uint8List data) {
  try {
    final compressed = gzip.encode(data);
    if (compressed.length < data.length) return Uint8List.fromList(compressed);
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

class UploadResult {
  final List<String> urls;
  final List<String> messageIds;
  final bool isCompressed;
  
  UploadResult({
    required this.urls,
    required this.messageIds,
    required this.isCompressed,
  });
}

class DiscordService {
  final String webhookUrl;
  final Dio _dio;
  static const int maxChunkSize = 9 * 1024 * 1024; // 9MB toujours
  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 2);
  static const Duration _chunkDelay = Duration(milliseconds: 600);

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

  /// Upload un fichier et retourne URLs + message IDs
  Future<UploadResult> uploadFile(
    Uint8List fileData,
    String fileName, {
    Function(double)? onProgress,
    CancelToken? cancelToken,
  }) async {
    // Compression
    final compressed = await compute(_compressIsolate, fileData);
    final isCompressed = compressed.length < fileData.length;
    final dataToUpload = isCompressed ? compressed : fileData;
    
    // Split
    final chunks = await compute(_splitChunksIsolate, {
      'data': dataToUpload,
      'maxSize': maxChunkSize,
    });
    
    final List<String> urls = [];
    final List<String> messageIds = [];

    for (int i = 0; i < chunks.length; i++) {
      if (cancelToken?.isCancelled == true) throw Exception('Cancelled');

      final chunk = chunks[i];
      String? url;
      String? msgId;
      int retries = 0;

      while (url == null && retries < _maxRetries) {
        try {
          final formData = FormData.fromMap({
            'file': MultipartFile.fromBytes(chunk, filename: '${i}_$fileName'),
          });

          final response = await _dio.post(
            '$webhookUrl?wait=true', // wait=true pour avoir l'ID du message
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
            throw Exception('Chunk $i failed');
          }
        }
      }

      if (url == null) throw Exception('No URL for chunk $i');
      
      urls.add(url);
      if (msgId != null) messageIds.add(msgId);
      
      if (i < chunks.length - 1) await Future.delayed(_chunkDelay);
    }

    return UploadResult(urls: urls, messageIds: messageIds, isCompressed: isCompressed);
  }

  /// Telecharge un fichier depuis ses URLs
  Future<Uint8List> downloadFile(
    List<String> urls, {
    bool isCompressed = false,
    Function(double)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final List<Uint8List> chunks = [];

    for (int i = 0; i < urls.length; i++) {
      if (cancelToken?.isCancelled == true) throw Exception('Cancelled');

      Uint8List? data;
      int retries = 0;

      while (data == null && retries < _maxRetries) {
        try {
          final response = await _dio.get<List<int>>(
            urls[i],
            options: Options(responseType: ResponseType.bytes),
            cancelToken: cancelToken,
            onReceiveProgress: (recv, total) {
              if (onProgress != null && total > 0) {
                onProgress((i + recv / total) / urls.length);
              }
            },
          );
          if (response.data != null && response.data!.isNotEmpty) {
            data = Uint8List.fromList(response.data!);
          }
        } on DioException catch (e) {
          if (e.type == DioExceptionType.cancel) rethrow;
          if (e.response?.statusCode == 404) throw Exception('File deleted from Discord');
          retries++;
          if (retries >= _maxRetries) throw Exception('Download chunk $i failed');
          await Future.delayed(_retryDelay * retries);
        }
      }
      if (data == null) throw Exception('No data for chunk $i');
      chunks.add(data);
    }

    final merged = await compute(_mergeChunksIsolate, chunks);
    return isCompressed ? await compute(_decompressIsolate, merged) : merged;
  }

  /// Supprime des messages Discord par leurs IDs
  Future<int> deleteMessages(List<String> messageIds) async {
    int deleted = 0;
    for (final msgId in messageIds) {
      try {
        final response = await _dio.delete('$webhookUrl/messages/$msgId');
        if (response.statusCode == 204 || response.statusCode == 200) deleted++;
        await Future.delayed(const Duration(milliseconds: 300)); // Rate limit
      } catch (e) {
        debugPrint('Failed to delete message $msgId: $e');
      }
    }
    return deleted;
  }

  /// Envoie un message texte (pour l'index)
  Future<String?> sendMessage(String content, {String? filename, Uint8List? fileData}) async {
    try {
      final Map<String, dynamic> data = {};
      
      if (fileData != null && filename != null) {
        final formData = FormData.fromMap({
          'file': MultipartFile.fromBytes(fileData, filename: filename),
          if (content.isNotEmpty) 'content': content,
        });
        final response = await _dio.post('$webhookUrl?wait=true', data: formData);
        if (response.statusCode == 200) return response.data['id']?.toString();
      } else {
        data['content'] = content;
        final response = await _dio.post('$webhookUrl?wait=true', data: data);
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
        final response = await _dio.patch(
          '$webhookUrl/messages/$messageId',
          data: {'content': content},
        );
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
