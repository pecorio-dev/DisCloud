import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

enum DownloadSourceType {
  direct,      // Lien direct
  youtube,     // YouTube
  video,       // Autres sites video (uqload, etc.)
  torrent,     // Fichier torrent ou magnet
  batch,       // Plusieurs liens
}

class DownloadSource {
  final String url;
  final DownloadSourceType type;
  final String? title;
  final Map<String, dynamic> metadata;

  DownloadSource({
    required this.url,
    required this.type,
    this.title,
    this.metadata = const {},
  });

  static DownloadSourceType detectType(String url) {
    final lower = url.toLowerCase();
    
    if (lower.startsWith('magnet:') || lower.endsWith('.torrent')) {
      return DownloadSourceType.torrent;
    }
    if (lower.contains('youtube.com') || lower.contains('youtu.be')) {
      return DownloadSourceType.youtube;
    }
    if (_isVideoHost(lower)) {
      return DownloadSourceType.video;
    }
    return DownloadSourceType.direct;
  }

  static bool _isVideoHost(String url) {
    final hosts = [
      'uqload', 'streamtape', 'doodstream', 'mixdrop', 'upstream',
      'vidoza', 'voe.sx', 'filemoon', 'streamwish', 'vidhide',
      'vimeo', 'dailymotion', 'twitch', 'facebook', 'twitter',
      'instagram', 'tiktok', 'reddit', 'soundcloud',
    ];
    return hosts.any((h) => url.contains(h));
  }
}

class ExtractedVideo {
  final String title;
  final String url;
  final String? thumbnailUrl;
  final int? duration;
  final int? fileSize;
  final String quality;
  final String format;
  final Map<String, String> headers;

  ExtractedVideo({
    required this.title,
    required this.url,
    this.thumbnailUrl,
    this.duration,
    this.fileSize,
    this.quality = 'unknown',
    this.format = 'mp4',
    this.headers = const {},
  });
}

/// Service universel de telechargement
class UniversalDownloader extends ChangeNotifier {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(minutes: 30),
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    },
  ));

  Process? _ytDlpProcess;
  String? _ytDlpPath;
  bool _ytDlpAvailable = false;

  bool get ytDlpAvailable => _ytDlpAvailable;

  Future<void> init() async {
    await _checkYtDlp();
  }

  Future<void> _checkYtDlp() async {
    // Chercher yt-dlp dans le PATH ou le dossier de l'app
    try {
      final result = await Process.run('yt-dlp', ['--version']);
      if (result.exitCode == 0) {
        _ytDlpPath = 'yt-dlp';
        _ytDlpAvailable = true;
        debugPrint('yt-dlp found: ${result.stdout}');
      }
    } catch (e) {
      // Essayer avec chemin complet Windows
      try {
        final appDir = await getApplicationSupportDirectory();
        final ytdlpFile = File('${appDir.path}/yt-dlp.exe');
        if (await ytdlpFile.exists()) {
          _ytDlpPath = ytdlpFile.path;
          _ytDlpAvailable = true;
        }
      } catch (_) {}
    }
    notifyListeners();
  }

  /// Telecharge yt-dlp automatiquement
  Future<bool> downloadYtDlp({Function(double)? onProgress}) async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final ytdlpFile = File('${appDir.path}/yt-dlp.exe');
      
      const url = 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe';
      
      await _dio.download(
        url,
        ytdlpFile.path,
        onReceiveProgress: (received, total) {
          if (total > 0) onProgress?.call(received / total);
        },
      );

      _ytDlpPath = ytdlpFile.path;
      _ytDlpAvailable = true;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Failed to download yt-dlp: $e');
      return false;
    }
  }

  /// Extrait les informations video depuis une URL
  Future<List<ExtractedVideo>> extractVideoInfo(String url) async {
    final type = DownloadSource.detectType(url);
    
    if (_ytDlpAvailable && (type == DownloadSourceType.youtube || type == DownloadSourceType.video)) {
      return _extractWithYtDlp(url);
    }
    
    // Fallback: extraction manuelle pour certains sites
    return _extractManually(url);
  }

  Future<List<ExtractedVideo>> _extractWithYtDlp(String url) async {
    try {
      final result = await Process.run(
        _ytDlpPath!,
        ['-j', '--no-playlist', url],
      );

      if (result.exitCode == 0) {
        final json = jsonDecode(result.stdout as String);
        final formats = <ExtractedVideo>[];

        final title = json['title'] ?? 'video';
        final thumbnail = json['thumbnail'];
        final duration = json['duration'];

        // Ajouter les formats disponibles
        if (json['formats'] != null) {
          for (final fmt in json['formats']) {
            if (fmt['vcodec'] != 'none' || fmt['acodec'] != 'none') {
              final height = fmt['height'];
              final ext = fmt['ext'] ?? 'mp4';
              final filesize = fmt['filesize'] ?? fmt['filesize_approx'];
              
              formats.add(ExtractedVideo(
                title: title,
                url: fmt['url'] ?? '',
                thumbnailUrl: thumbnail,
                duration: duration,
                fileSize: filesize,
                quality: height != null ? '${height}p' : (fmt['format_note'] ?? 'unknown'),
                format: ext,
                headers: Map<String, String>.from(fmt['http_headers'] ?? {}),
              ));
            }
          }
        }

        // Si pas de formats, utiliser l'URL directe
        if (formats.isEmpty && json['url'] != null) {
          formats.add(ExtractedVideo(
            title: title,
            url: json['url'],
            thumbnailUrl: thumbnail,
            duration: duration,
            quality: 'best',
            format: json['ext'] ?? 'mp4',
          ));
        }

        // Trier par qualite
        formats.sort((a, b) {
          final aNum = int.tryParse(a.quality.replaceAll('p', '')) ?? 0;
          final bNum = int.tryParse(b.quality.replaceAll('p', '')) ?? 0;
          return bNum.compareTo(aNum);
        });

        return formats;
      }
    } catch (e) {
      debugPrint('yt-dlp extraction failed: $e');
    }
    
    return [];
  }

  Future<List<ExtractedVideo>> _extractManually(String url) async {
    // Extraction manuelle pour certains sites sans yt-dlp
    try {
      final response = await _dio.get(url);
      final html = response.data.toString();
      
      // Chercher des patterns de video
      final videoUrls = <String>[];
      
      // Pattern pour les sources video directes (mp4, m3u8, webm)
      final mp4Pattern = RegExp(r'https?://[^\s"<>]+\.mp4[^\s"<>]*', caseSensitive: false);
      final m3u8Pattern = RegExp(r'https?://[^\s"<>]+\.m3u8[^\s"<>]*', caseSensitive: false);
      final webmPattern = RegExp(r'https?://[^\s"<>]+\.webm[^\s"<>]*', caseSensitive: false);
      
      for (final match in mp4Pattern.allMatches(html)) {
        videoUrls.add(match.group(0)!);
      }
      for (final match in m3u8Pattern.allMatches(html)) {
        videoUrls.add(match.group(0)!);
      }
      for (final match in webmPattern.allMatches(html)) {
        videoUrls.add(match.group(0)!);
      }

      return videoUrls.map((u) => ExtractedVideo(
        title: Uri.parse(url).host,
        url: u,
        quality: 'unknown',
      )).toList();

    } catch (e) {
      debugPrint('Manual extraction failed: $e');
    }
    
    return [];
  }

  String _decodePackedJs(String packed) {
    // Decodeur basique pour le JS packe
    try {
      final match = RegExp(r"\('([^']+)',(\d+),(\d+),'([^']+)'").firstMatch(packed);
      if (match == null) return '';
      
      final p = match.group(1)!;
      final a = int.parse(match.group(2)!);
      final c = int.parse(match.group(3)!);
      final k = match.group(4)!.split('|');
      
      var result = p;
      for (int i = c - 1; i >= 0; i--) {
        if (k[i].isNotEmpty) {
          final pattern = RegExp('\\b${i.toRadixString(a)}\\b');
          result = result.replaceAll(pattern, k[i]);
        }
      }
      return result;
    } catch (e) {
      return '';
    }
  }

  /// Telecharge un fichier avec streaming vers Discord
  Future<void> downloadAndUpload({
    required String url,
    required String filename,
    required Future<void> Function(String name, Uint8List data) uploadFunc,
    Function(double)? onProgress,
    Map<String, String> headers = const {},
    CancelToken? cancelToken,
  }) async {
    // Telecharger par chunks et uploader directement
    final response = await _dio.get<ResponseBody>(
      url,
      options: Options(
        responseType: ResponseType.stream,
        headers: headers,
      ),
      cancelToken: cancelToken,
    );

    final totalSize = int.tryParse(response.headers.value('content-length') ?? '0') ?? 0;
    final chunks = <int>[];
    int received = 0;
    const chunkSize = 8 * 1024 * 1024; // 8MB chunks

    await for (final data in response.data!.stream) {
      chunks.addAll(data);
      received += data.length;
      
      if (totalSize > 0) {
        onProgress?.call(received / totalSize);
      }

      // Quand on a assez de donnees, uploader un chunk
      while (chunks.length >= chunkSize) {
        final chunkData = Uint8List.fromList(chunks.sublist(0, chunkSize));
        chunks.removeRange(0, chunkSize);
        
        final chunkNum = (received / chunkSize).floor();
        await uploadFunc('${chunkNum}_$filename', chunkData);
      }
    }

    // Uploader le reste
    if (chunks.isNotEmpty) {
      final chunkNum = (received / chunkSize).floor();
      await uploadFunc('${chunkNum}_$filename', Uint8List.fromList(chunks));
    }
  }

  /// Telecharge en batch plusieurs URLs
  Future<List<Uint8List>> downloadBatch(
    List<String> urls, {
    int maxParallel = 3,
    Function(int completed, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final results = List<Uint8List?>.filled(urls.length, null);
    final queue = List<int>.generate(urls.length, (i) => i);
    int completed = 0;

    Future<void> worker() async {
      while (queue.isNotEmpty) {
        if (cancelToken?.isCancelled ?? false) return;
        
        final index = queue.removeAt(0);
        
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
          debugPrint('Failed to download ${urls[index]}: $e');
          // Retry once
          queue.add(index);
        }
      }
    }

    final workers = List.generate(maxParallel.clamp(1, urls.length), (_) => worker());
    await Future.wait(workers);

    return results.whereType<Uint8List>().toList();
  }

  @override
  void dispose() {
    _ytDlpProcess?.kill();
    super.dispose();
  }
}
