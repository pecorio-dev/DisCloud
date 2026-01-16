import 'dart:convert';
import '../models/cloud_file.dart';

class ShareLinkService {
  static const String _prefix = 'discloud://';

  static String generateShareLink(CloudFile file) {
    if (file.chunkUrls.isEmpty) {
      throw Exception('No download URLs available');
    }

    final shareData = {
      'n': file.name,
      's': file.size,
      'u': file.chunkUrls,
      'z': file.isCompressed,
    };

    final jsonString = jsonEncode(shareData);
    final encoded = base64Url.encode(utf8.encode(jsonString));
    return '$_prefix$encoded';
  }

  static ShareLinkData? parseShareLink(String link) {
    try {
      if (!link.startsWith(_prefix)) return null;
      final encoded = link.substring(_prefix.length);
      final jsonString = utf8.decode(base64Url.decode(encoded));
      final data = jsonDecode(jsonString);

      return ShareLinkData(
        fileName: data['n'] ?? 'unknown',
        fileSize: data['s'] ?? 0,
        chunkUrls: List<String>.from(data['u'] ?? []),
        isCompressed: data['z'] ?? false,
      );
    } catch (e) {
      return null;
    }
  }
}

class ShareLinkData {
  final String fileName;
  final int fileSize;
  final List<String> chunkUrls;
  final bool isCompressed;

  ShareLinkData({
    required this.fileName,
    required this.fileSize,
    required this.chunkUrls,
    required this.isCompressed,
  });

  String get formattedSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    return '${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
