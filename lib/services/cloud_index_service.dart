import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/cloud_file.dart';

/// Service pour synchroniser l'index des fichiers entre appareils via Discord
class CloudIndexService {
  static const String _indexMarker = '📁 DISCLOUD_INDEX_V1';
  final Dio _dio = Dio();

  /// Exporte l'index des fichiers vers Discord (comme message JSON)
  Future<bool> exportIndex(String webhookUrl, Map<String, CloudFile> files) async {
    try {
      final indexData = {
        'marker': _indexMarker,
        'version': 1,
        'timestamp': DateTime.now().toIso8601String(),
        'files': files.map((k, v) => MapEntry(k, v.toJson())),
      };

      final jsonString = jsonEncode(indexData);
      
      // Si l'index est trop grand, le diviser
      if (jsonString.length > 1900) {
        // Diviser en plusieurs messages
        final chunks = _splitString(jsonString, 1900);
        for (int i = 0; i < chunks.length; i++) {
          await _dio.post(webhookUrl, data: {
            'content': '$_indexMarker PART ${i + 1}/${chunks.length}\n```json\n${chunks[i]}\n```',
          });
          // Petit delai pour eviter rate limit
          await Future.delayed(const Duration(milliseconds: 500));
        }
      } else {
        await _dio.post(webhookUrl, data: {
          'content': '$_indexMarker\n```json\n$jsonString\n```',
        });
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Envoie un embed avec les metadonnees d'un fichier (pour le retrouver)
  Future<void> sendFileMetadata(
    String webhookUrl,
    CloudFile file,
    List<String> chunkUrls,
  ) async {
    try {
      final metadata = {
        'type': 'discloud_file_meta',
        'file': file.toJson(),
        'chunks': chunkUrls,
      };

      await _dio.post(webhookUrl, data: {
        'content': '📄 **${file.name}** (${_formatSize(file.size)})',
        'embeds': [{
          'title': file.name,
          'description': 'DisCloud File Metadata',
          'color': 5814783, // Blurple
          'fields': [
            {'name': 'Path', 'value': file.path, 'inline': true},
            {'name': 'Size', 'value': _formatSize(file.size), 'inline': true},
            {'name': 'Chunks', 'value': '${chunkUrls.length}', 'inline': true},
          ],
          'footer': {'text': jsonEncode(metadata)},
        }],
      });
    } catch (e) {
      // Ignorer les erreurs de metadata
    }
  }

  List<String> _splitString(String str, int chunkSize) {
    final chunks = <String>[];
    for (int i = 0; i < str.length; i += chunkSize) {
      final end = (i + chunkSize < str.length) ? i + chunkSize : str.length;
      chunks.add(str.substring(i, end));
    }
    return chunks;
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
