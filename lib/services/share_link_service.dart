import 'dart:convert';
import 'dart:typed_data';
import '../models/cloud_file.dart';

/// Service pour generer et parser des liens de partage securises
/// Le lien contient les URLs des chunks (CDN Discord) + infos de decryption
/// SANS le webhook URL (qui permettrait d'uploader)
class ShareLinkService {
  static const String _prefix = 'discloud://';
  static const int _version = 1;

  /// Genere un lien de partage pour un fichier
  static String generateShareLink(CloudFile file, {String? encryptionKey}) {
    // Collecter toutes les URLs de chunks
    List<String> chunkUrls = [];
    
    if (file.webhookChunks.isNotEmpty) {
      // Prendre les URLs du premier webhook disponible
      chunkUrls = file.webhookChunks.values.first;
    } else if (file.chunkIds.isNotEmpty) {
      chunkUrls = file.chunkIds;
    }

    if (chunkUrls.isEmpty) {
      throw Exception('No download URLs available');
    }

    final shareData = {
      'v': _version,
      'n': file.name,
      's': file.size,
      'c': chunkUrls,
      if (encryptionKey != null) 'k': encryptionKey,
      't': DateTime.now().millisecondsSinceEpoch,
    };

    final jsonString = jsonEncode(shareData);
    final encoded = base64Url.encode(utf8.encode(jsonString));
    
    return '$_prefix$encoded';
  }

  /// Parse un lien de partage
  static ShareLinkData? parseShareLink(String link) {
    try {
      if (!link.startsWith(_prefix)) {
        return null;
      }

      final encoded = link.substring(_prefix.length);
      final jsonString = utf8.decode(base64Url.decode(encoded));
      final data = jsonDecode(jsonString);

      return ShareLinkData(
        version: data['v'] ?? 1,
        fileName: data['n'] ?? 'unknown',
        fileSize: data['s'] ?? 0,
        chunkUrls: List<String>.from(data['c'] ?? []),
        encryptionKey: data['k'],
        timestamp: data['t'] != null 
            ? DateTime.fromMillisecondsSinceEpoch(data['t'])
            : null,
      );
    } catch (e) {
      return null;
    }
  }

  /// Verifie si une string est un lien de partage valide
  static bool isShareLink(String text) {
    return text.startsWith(_prefix) && parseShareLink(text) != null;
  }

  /// Genere un lien court (pour affichage)
  static String getShortLink(String fullLink) {
    if (fullLink.length <= 50) return fullLink;
    return '${fullLink.substring(0, 30)}...${fullLink.substring(fullLink.length - 15)}';
  }

  /// Genere un lien en format texte lisible (pour copier manuellement)
  static String generateTextFormat(CloudFile file, {String? encryptionKey}) {
    List<String> chunkUrls = [];
    
    if (file.webhookChunks.isNotEmpty) {
      chunkUrls = file.webhookChunks.values.first;
    } else if (file.chunkIds.isNotEmpty) {
      chunkUrls = file.chunkIds;
    }

    final buffer = StringBuffer();
    buffer.writeln('📁 DisCloud Share: ${file.name}');
    buffer.writeln('Size: ${_formatSize(file.size)}');
    buffer.writeln('Chunks: ${chunkUrls.length}');
    buffer.writeln('---');
    
    for (int i = 0; i < chunkUrls.length; i++) {
      buffer.writeln('[$i] ${chunkUrls[i]}');
    }
    
    if (encryptionKey != null) {
      buffer.writeln('---');
      buffer.writeln('Key: $encryptionKey');
    }

    return buffer.toString();
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class ShareLinkData {
  final int version;
  final String fileName;
  final int fileSize;
  final List<String> chunkUrls;
  final String? encryptionKey;
  final DateTime? timestamp;

  ShareLinkData({
    required this.version,
    required this.fileName,
    required this.fileSize,
    required this.chunkUrls,
    this.encryptionKey,
    this.timestamp,
  });

  String get formattedSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    if (fileSize < 1024 * 1024 * 1024) return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(fileSize / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  bool get isEncrypted => encryptionKey != null;
}
