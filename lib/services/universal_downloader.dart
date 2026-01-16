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
  String? _aria2Path;
  bool _ytDlpAvailable = false;
  bool _aria2Available = false;

  bool get ytDlpAvailable => _ytDlpAvailable;
  bool get aria2Available => _aria2Available;
  String? get ytDlpPath => _ytDlpPath;
  String? get aria2Path => _aria2Path;

  /// Initialise avec les chemins du DependencyManager
  Future<void> init({String? ytDlpPath, String? aria2Path}) async {
    if (ytDlpPath != null) {
      _ytDlpPath = ytDlpPath;
      _ytDlpAvailable = true;
      debugPrint('yt-dlp path set: $ytDlpPath');
    }
    if (aria2Path != null) {
      _aria2Path = aria2Path;
      _aria2Available = true;
      debugPrint('aria2 path set: $aria2Path');
    }
    
    // Si pas de chemins fournis, chercher automatiquement
    if (_ytDlpPath == null) {
      await _findYtDlp();
    }
    if (_aria2Path == null) {
      await _findAria2();
    }
    
    notifyListeners();
  }

  /// Mettre a jour les chemins (appele par DependencyManager)
  void updatePaths({String? ytDlpPath, String? aria2Path}) {
    if (ytDlpPath != null) {
      _ytDlpPath = ytDlpPath;
      _ytDlpAvailable = true;
    }
    if (aria2Path != null) {
      _aria2Path = aria2Path;
      _aria2Available = true;
    }
    notifyListeners();
  }

  Future<void> _findYtDlp() async {
    // 1. Chercher dans le dossier bin de l'app
    try {
      final appDir = await getApplicationSupportDirectory();
      final binPath = '${appDir.path}${Platform.pathSeparator}bin${Platform.pathSeparator}yt-dlp.exe';
      final binFile = File(binPath);
      if (await binFile.exists()) {
        // Verifier que ca fonctionne
        final result = await Process.run(binPath, ['--version']);
        if (result.exitCode == 0) {
          _ytDlpPath = binPath;
          _ytDlpAvailable = true;
          debugPrint('yt-dlp found in bin: $binPath (${result.stdout.toString().trim()})');
          return;
        }
      }
    } catch (e) {
      debugPrint('Error checking bin/yt-dlp: $e');
    }
    
    // 2. Chercher dans le PATH systeme
    try {
      final result = await Process.run('yt-dlp', ['--version']);
      if (result.exitCode == 0) {
        _ytDlpPath = 'yt-dlp';
        _ytDlpAvailable = true;
        debugPrint('yt-dlp found in PATH: ${result.stdout}');
        return;
      }
    } catch (_) {}
    
    // 3. Chercher dans des emplacements communs Windows
    final commonPaths = [
      'C:\\Program Files\\yt-dlp\\yt-dlp.exe',
      'C:\\Program Files (x86)\\yt-dlp\\yt-dlp.exe',
      '${Platform.environment['LOCALAPPDATA']}\\yt-dlp\\yt-dlp.exe',
      '${Platform.environment['APPDATA']}\\yt-dlp\\yt-dlp.exe',
    ];
    
    for (final path in commonPaths) {
      try {
        if (await File(path).exists()) {
          final result = await Process.run(path, ['--version']);
          if (result.exitCode == 0) {
            _ytDlpPath = path;
            _ytDlpAvailable = true;
            debugPrint('yt-dlp found at: $path');
            return;
          }
        }
      } catch (_) {}
    }
    
    debugPrint('yt-dlp not found');
  }

  Future<void> _findAria2() async {
    // 1. Chercher dans le dossier bin de l'app
    try {
      final appDir = await getApplicationSupportDirectory();
      final binPath = '${appDir.path}${Platform.pathSeparator}bin${Platform.pathSeparator}aria2c.exe';
      final binFile = File(binPath);
      if (await binFile.exists()) {
        final result = await Process.run(binPath, ['--version']);
        if (result.exitCode == 0) {
          _aria2Path = binPath;
          _aria2Available = true;
          debugPrint('aria2 found in bin: $binPath');
          return;
        }
      }
    } catch (e) {
      debugPrint('Error checking bin/aria2c: $e');
    }
    
    // 2. Chercher dans le PATH
    try {
      final result = await Process.run('aria2c', ['--version']);
      if (result.exitCode == 0) {
        _aria2Path = 'aria2c';
        _aria2Available = true;
        debugPrint('aria2 found in PATH');
        return;
      }
    } catch (_) {}
    
    debugPrint('aria2 not found');
  }

  /// Force la re-detection des outils
  Future<void> refresh() async {
    _ytDlpAvailable = false;
    _aria2Available = false;
    _ytDlpPath = null;
    _aria2Path = null;
    await _findYtDlp();
    await _findAria2();
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
    debugPrint('=== Extracting with yt-dlp ===');
    debugPrint('URL: $url');
    debugPrint('yt-dlp path: $_ytDlpPath');
    
    try {
      // Verifier que yt-dlp existe
      final ytdlpFile = File(_ytDlpPath!);
      if (!await ytdlpFile.exists() && _ytDlpPath != 'yt-dlp') {
        debugPrint('yt-dlp file not found at $_ytDlpPath');
        return [];
      }

      final result = await Process.run(
        _ytDlpPath!,
        [
          '-j',                    // Output JSON
          '--no-playlist',         // Single video only
          '--no-warnings',         // Suppress warnings
          '--no-check-certificate', // Skip SSL verification
          '--user-agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          url,
        ],
        runInShell: true,
      );

      debugPrint('yt-dlp exit code: ${result.exitCode}');
      debugPrint('yt-dlp stdout length: ${result.stdout.toString().length}');
      
      if (result.stderr.toString().isNotEmpty) {
        debugPrint('yt-dlp stderr: ${result.stderr}');
      }

      if (result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty) {
        final jsonStr = result.stdout.toString().trim();
        debugPrint('Parsing JSON response...');
        
        final json = jsonDecode(jsonStr);
        final formats = <ExtractedVideo>[];

        final title = json['title'] ?? 'video';
        final thumbnail = json['thumbnail'];
        final duration = json['duration'];
        
        debugPrint('Video title: $title');

        // Ajouter les formats disponibles
        if (json['formats'] != null) {
          debugPrint('Found ${(json['formats'] as List).length} formats');
          
          for (final fmt in json['formats']) {
            final vcodec = fmt['vcodec']?.toString() ?? 'none';
            final acodec = fmt['acodec']?.toString() ?? 'none';
            final fmtUrl = fmt['url']?.toString() ?? '';
            
            // Ignorer les formats sans URL ou sans codec
            if (fmtUrl.isEmpty) continue;
            if (vcodec == 'none' && acodec == 'none') continue;
            
            final height = fmt['height'];
            final ext = fmt['ext'] ?? 'mp4';
            final filesize = fmt['filesize'] ?? fmt['filesize_approx'];
            
            formats.add(ExtractedVideo(
              title: title,
              url: fmtUrl,
              thumbnailUrl: thumbnail,
              duration: duration is int ? duration : null,
              fileSize: filesize is int ? filesize : null,
              quality: height != null ? '${height}p' : (fmt['format_note']?.toString() ?? 'unknown'),
              format: ext.toString(),
              headers: fmt['http_headers'] != null 
                  ? Map<String, String>.from(fmt['http_headers']) 
                  : {},
            ));
          }
        }

        // Si pas de formats mais URL directe disponible
        if (formats.isEmpty && json['url'] != null) {
          debugPrint('Using direct URL');
          formats.add(ExtractedVideo(
            title: title,
            url: json['url'],
            thumbnailUrl: thumbnail,
            duration: duration is int ? duration : null,
            quality: 'best',
            format: json['ext']?.toString() ?? 'mp4',
          ));
        }

        // Filtrer les doublons et URLs invalides
        final uniqueFormats = <String, ExtractedVideo>{};
        for (final fmt in formats) {
          if (fmt.url.startsWith('http')) {
            final key = '${fmt.quality}_${fmt.format}';
            if (!uniqueFormats.containsKey(key)) {
              uniqueFormats[key] = fmt;
            }
          }
        }

        // Trier par qualite (highest first)
        final sortedFormats = uniqueFormats.values.toList();
        sortedFormats.sort((a, b) {
          final aNum = int.tryParse(a.quality.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
          final bNum = int.tryParse(b.quality.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
          return bNum.compareTo(aNum);
        });

        debugPrint('Returning ${sortedFormats.length} formats');
        return sortedFormats;
      } else {
        debugPrint('yt-dlp failed or returned empty');
        debugPrint('Exit code: ${result.exitCode}');
        debugPrint('Stdout: ${result.stdout}');
        debugPrint('Stderr: ${result.stderr}');
      }
    } catch (e, stack) {
      debugPrint('yt-dlp extraction error: $e');
      debugPrint('Stack: $stack');
    }
    
    // Si yt-dlp echoue, essayer l'extraction manuelle
    debugPrint('Trying manual extraction...');
    return _extractManually(url);
  }

  /// Telecharge une video avec yt-dlp directement (sans extraire d'abord)
  Future<File?> downloadVideoWithYtDlp(
    String url, {
    String? quality,
    Function(double)? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (!_ytDlpAvailable || _ytDlpPath == null) {
      debugPrint('yt-dlp not available for direct download');
      return null;
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final outputPath = '${tempDir.path}${Platform.pathSeparator}discloud_%(title)s.%(ext)s';
      
      debugPrint('Downloading with yt-dlp to: $outputPath');
      
      final args = [
        '-o', outputPath,
        '--no-playlist',
        '--no-check-certificate',
        '--user-agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        '--progress',
        '--newline',
      ];
      
      // Ajouter la qualite si specifiee
      if (quality != null && quality.contains('p')) {
        final height = quality.replaceAll(RegExp(r'[^0-9]'), '');
        args.addAll(['-f', 'bestvideo[height<=$height]+bestaudio/best[height<=$height]/best']);
      } else {
        args.addAll(['-f', 'best']);
      }
      
      args.add(url);
      
      final process = await Process.start(_ytDlpPath!, args, runInShell: true);
      
      String? downloadedFile;
      
      await for (final line in process.stdout.transform(const SystemEncoding().decoder)) {
        debugPrint('yt-dlp: $line');
        
        // Parser la progression
        if (line.contains('%')) {
          final match = RegExp(r'(\d+\.?\d*)%').firstMatch(line);
          if (match != null) {
            final progress = double.tryParse(match.group(1)!) ?? 0;
            onProgress?.call(progress / 100);
          }
        }
        
        // Detecter le fichier telecharge
        if (line.contains('[download] Destination:')) {
          downloadedFile = line.split('Destination:').last.trim();
        }
        if (line.contains('has already been downloaded')) {
          downloadedFile = line.split('"')[1];
        }
        if (line.contains('[Merger]')) {
          final match = RegExp(r'Merging formats into "([^"]+)"').firstMatch(line);
          if (match != null) downloadedFile = match.group(1);
        }
      }
      
      await process.exitCode;
      
      // Trouver le fichier telecharge
      if (downloadedFile != null && await File(downloadedFile).exists()) {
        return File(downloadedFile);
      }
      
      // Chercher dans le dossier temp
      final files = await tempDir.list().where((f) => f.path.contains('discloud_')).toList();
      if (files.isNotEmpty) {
        return File(files.first.path);
      }
      
    } catch (e) {
      debugPrint('yt-dlp download error: $e');
    }
    
    return null;
  }

  Future<List<ExtractedVideo>> _extractManually(String url) async {
    // Extraction manuelle pour certains sites sans yt-dlp
    debugPrint('Manual extraction for: $url');
    
    try {
      final response = await _dio.get(
        url,
        options: Options(
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            'Referer': url,
          },
        ),
      );
      final html = response.data.toString();
      debugPrint('Page loaded, ${html.length} chars');
      
      // Chercher des patterns de video
      final videoUrls = <String>[];
      
      // Pattern simple pour les URLs video
      final urlPattern = RegExp(r'https?://[^\s"<>]+\.(mp4|m3u8|webm)[^\s"<>]*', caseSensitive: false);
      
      for (final match in urlPattern.allMatches(html)) {
        var u = match.group(0)!;
        // Nettoyer les caracteres d'echappement
        u = u.replaceAll(r'\/', '/').replaceAll(r'\"', '');
        // Couper aux caracteres invalides
        for (final c in ['"', "'", ' ', ')', '<', '>']) {
          final idx = u.indexOf(c);
          if (idx > 0) u = u.substring(0, idx);
        }
        
        if (u.startsWith('http') && !videoUrls.contains(u)) {
          videoUrls.add(u);
        }
      }
      
      debugPrint('Found ${videoUrls.length} video URLs manually');

      return videoUrls.map((u) => ExtractedVideo(
        title: Uri.parse(url).host,
        url: u,
        quality: u.contains('1080') ? '1080p' : (u.contains('720') ? '720p' : 'unknown'),
        format: u.contains('.m3u8') ? 'm3u8' : (u.contains('.webm') ? 'webm' : 'mp4'),
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
