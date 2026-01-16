import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../models/cloud_file.dart';

class ShareLinkService {
  static const String protocol = 'discloud://';
  static const int version = 2;

  /// Genere un lien de partage pour un ou plusieurs fichiers
  static String generateShareLink(List<CloudFile> files) {
    final shareData = {
      'v': version,
      'files': files.map((f) => _fileToShareData(f)).toList(),
    };
    
    final json = jsonEncode(shareData);
    final compressed = gzip.encode(utf8.encode(json));
    final encoded = base64Url.encode(compressed).replaceAll('=', '');
    
    return '$protocol$encoded';
  }

  /// Genere un lien pour un seul fichier
  static String generateSingleLink(CloudFile file) {
    return generateShareLink([file]);
  }

  static Map<String, dynamic> _fileToShareData(CloudFile file) {
    return {
      'n': file.name, // name
      's': file.size, // size
      'c': file.chunkUrls.length, // chunk count
      'u': file.chunkUrls, // urls
      'z': file.isCompressed, // compressed
      'h': file.checksum, // checksum
      'm': file.metadata, // metadata for decryption/deobfuscation
    };
  }

  /// Parse un lien de partage
  static ShareData? parseShareLink(String link) {
    try {
      if (!link.startsWith(protocol)) return null;
      
      var encoded = link.substring(protocol.length);
      // Restore padding
      while (encoded.length % 4 != 0) encoded += '=';
      
      final compressed = base64Url.decode(encoded);
      final json = utf8.decode(gzip.decode(compressed));
      final data = jsonDecode(json) as Map<String, dynamic>;
      
      final files = (data['files'] as List).map((f) => SharedFile(
        name: f['n'] ?? 'file',
        size: f['s'] ?? 0,
        chunkCount: f['c'] ?? 1,
        urls: List<String>.from(f['u'] ?? []),
        isCompressed: f['z'] ?? false,
        checksum: f['h'],
        metadata: Map<String, dynamic>.from(f['m'] ?? {}),
      )).toList();
      
      return ShareData(version: data['v'] ?? 1, files: files);
    } catch (e) {
      return null;
    }
  }

  /// Genere un QR code data pour le lien
  static String generateQRData(String link) {
    // Pour les longs liens, on peut utiliser un raccourcisseur ou juste le lien
    return link;
  }
}

class ShareData {
  final int version;
  final List<SharedFile> files;
  
  ShareData({required this.version, required this.files});
  
  int get totalSize => files.fold(0, (sum, f) => sum + f.size);
  int get totalChunks => files.fold(0, (sum, f) => sum + f.chunkCount);
  bool get hasEncryptedFiles => files.any((f) => f.metadata['encrypted'] != null);
}

class SharedFile {
  final String name;
  final int size;
  final int chunkCount;
  final List<String> urls;
  final bool isCompressed;
  final String? checksum;
  final Map<String, dynamic> metadata;
  
  SharedFile({
    required this.name,
    required this.size,
    required this.chunkCount,
    required this.urls,
    this.isCompressed = false,
    this.checksum,
    this.metadata = const {},
  });
  
  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  
  bool get isEncrypted => metadata['encrypted'] != null;
}
