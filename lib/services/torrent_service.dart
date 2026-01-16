import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

enum TorrentStatus { checking, downloading, seeding, paused, error, completed }

class TorrentFile {
  final String name;
  final int size;
  final int index;
  double progress;
  
  TorrentFile({required this.name, required this.size, required this.index, this.progress = 0});
  
  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

class TorrentInfo {
  final String infoHash;
  final String name;
  final int totalSize;
  final List<TorrentFile> files;
  TorrentStatus status;
  double progress;
  int downloadSpeed;
  int uploadSpeed;
  int peers;
  int seeds;
  String? error;

  TorrentInfo({
    required this.infoHash,
    required this.name,
    required this.totalSize,
    required this.files,
    this.status = TorrentStatus.checking,
    this.progress = 0,
    this.downloadSpeed = 0,
    this.uploadSpeed = 0,
    this.peers = 0,
    this.seeds = 0,
    this.error,
  });

  String get formattedSize {
    if (totalSize < 1024) return '$totalSize B';
    if (totalSize < 1024 * 1024) return '${(totalSize / 1024).toStringAsFixed(1)} KB';
    if (totalSize < 1024 * 1024 * 1024) return '${(totalSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(totalSize / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String get formattedSpeed {
    if (downloadSpeed < 1024) return '$downloadSpeed B/s';
    if (downloadSpeed < 1024 * 1024) return '${(downloadSpeed / 1024).toStringAsFixed(1)} KB/s';
    return '${(downloadSpeed / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }
}

/// Service Torrent utilisant aria2c ou transmission-remote
class TorrentService extends ChangeNotifier {
  final Dio _dio = Dio();
  Process? _aria2Process;
  String? _aria2RpcUrl;
  String? _aria2Secret;
  String? _aria2Path; // Chemin vers aria2c
  bool _isRunning = false;
  final Map<String, TorrentInfo> _torrents = {};
  Timer? _updateTimer;

  bool get isRunning => _isRunning;
  List<TorrentInfo> get torrents => _torrents.values.toList();
  String? get aria2Path => _aria2Path;

  /// Definir le chemin aria2
  void setAria2Path(String path) {
    _aria2Path = path;
    debugPrint('TorrentService: aria2 path set to $path');
    notifyListeners();
  }

  /// Demarre le service aria2c
  Future<bool> start() async {
    if (_isRunning) return true;

    // Determiner le chemin aria2
    String aria2Executable = _aria2Path ?? 'aria2c';

    try {
      // Verifier si aria2c est disponible
      final testResult = await Process.run(aria2Executable, ['--version']);
      if (testResult.exitCode != 0) {
        debugPrint('aria2c not found at: $aria2Executable');
        return false;
      }
      debugPrint('aria2c found: ${testResult.stdout.toString().split('\n').first}');

      // Demarrer aria2c en mode RPC
      _aria2Secret = DateTime.now().millisecondsSinceEpoch.toString();
      final tempDir = await getTemporaryDirectory();
      
      _aria2Process = await Process.start(
        aria2Executable,
        [
          '--enable-rpc',
          '--rpc-listen-port=6800',
          '--rpc-secret=$_aria2Secret',
          '--dir=${tempDir.path}/discloud_torrents',
          '--seed-time=0', // Ne pas seeder
          '--max-concurrent-downloads=3',
          '--split=4',
          '--min-split-size=1M',
          '--bt-enable-lpd=false',
          '--bt-max-peers=50',
          '--quiet',
        ],
      );

      _aria2RpcUrl = 'http://localhost:6800/jsonrpc';
      
      // Attendre que aria2 demarre
      await Future.delayed(const Duration(seconds: 2));
      
      // Verifier la connexion
      final version = await _rpcCall('aria2.getVersion');
      if (version != null) {
        _isRunning = true;
        _startUpdateTimer();
        notifyListeners();
        debugPrint('aria2c started: ${version['version']}');
        return true;
      }
    } catch (e) {
      debugPrint('Failed to start aria2c: $e');
    }

    return false;
  }

  /// Arrete le service
  Future<void> stop() async {
    _updateTimer?.cancel();
    _aria2Process?.kill();
    _isRunning = false;
    _torrents.clear();
    notifyListeners();
  }

  /// Ajoute un torrent (magnet ou fichier .torrent)
  Future<String?> addTorrent(String magnetOrUrl) async {
    if (!_isRunning) {
      if (!await start()) return null;
    }

    try {
      List<dynamic>? result;
      
      if (magnetOrUrl.startsWith('magnet:')) {
        result = await _rpcCall('aria2.addUri', [[magnetOrUrl]]);
      } else if (magnetOrUrl.endsWith('.torrent')) {
        // Telecharger le fichier torrent
        final response = await _dio.get<List<int>>(
          magnetOrUrl,
          options: Options(responseType: ResponseType.bytes),
        );
        final torrentData = base64Encode(response.data!);
        result = await _rpcCall('aria2.addTorrent', [torrentData]);
      } else {
        // URL directe
        result = await _rpcCall('aria2.addUri', [[magnetOrUrl]]);
      }

      if (result != null) {
        final gid = result.toString();
        debugPrint('Torrent added: $gid');
        await _updateTorrentInfo(gid);
        return gid;
      }
    } catch (e) {
      debugPrint('Failed to add torrent: $e');
    }

    return null;
  }

  /// Pause un torrent
  Future<bool> pauseTorrent(String gid) async {
    final result = await _rpcCall('aria2.pause', [gid]);
    return result != null;
  }

  /// Resume un torrent
  Future<bool> resumeTorrent(String gid) async {
    final result = await _rpcCall('aria2.unpause', [gid]);
    return result != null;
  }

  /// Supprime un torrent
  Future<bool> removeTorrent(String gid) async {
    final result = await _rpcCall('aria2.remove', [gid]);
    if (result != null) {
      _torrents.remove(gid);
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Recupere les fichiers telecharges d'un torrent
  Future<List<File>> getTorrentFiles(String gid) async {
    final info = _torrents[gid];
    if (info == null) return [];

    final tempDir = await getTemporaryDirectory();
    final files = <File>[];

    for (final tf in info.files) {
      final file = File('${tempDir.path}/discloud_torrents/${info.name}/${tf.name}');
      if (await file.exists()) {
        files.add(file);
      }
    }

    return files;
  }

  /// Telecharge un torrent directement vers Discord (streaming)
  Future<void> downloadToDiscord({
    required String magnetOrUrl,
    required Future<void> Function(String name, Uint8List data) uploadChunk,
    Function(TorrentInfo)? onProgress,
  }) async {
    final gid = await addTorrent(magnetOrUrl);
    if (gid == null) throw Exception('Failed to add torrent');

    // Attendre que le torrent soit complet
    while (true) {
      await Future.delayed(const Duration(seconds: 2));
      await _updateTorrentInfo(gid);
      
      final info = _torrents[gid];
      if (info == null) break;
      
      onProgress?.call(info);
      
      if (info.status == TorrentStatus.completed) {
        // Uploader chaque fichier vers Discord
        final files = await getTorrentFiles(gid);
        for (final file in files) {
          final data = await file.readAsBytes();
          
          // Chunker si necessaire
          const chunkSize = 8 * 1024 * 1024;
          int offset = 0;
          int chunkNum = 0;
          
          while (offset < data.length) {
            final end = (offset + chunkSize < data.length) ? offset + chunkSize : data.length;
            final chunk = data.sublist(offset, end);
            await uploadChunk('${chunkNum}_${file.uri.pathSegments.last}', Uint8List.fromList(chunk));
            offset = end;
            chunkNum++;
          }
        }
        
        // Nettoyer
        await removeTorrent(gid);
        break;
      }
      
      if (info.status == TorrentStatus.error) {
        throw Exception(info.error ?? 'Torrent download failed');
      }
    }
  }

  void _startUpdateTimer() {
    _updateTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      for (final gid in _torrents.keys.toList()) {
        await _updateTorrentInfo(gid);
      }
    });
  }

  Future<void> _updateTorrentInfo(String gid) async {
    try {
      final status = await _rpcCall('aria2.tellStatus', [gid]);
      if (status == null) return;

      final files = <TorrentFile>[];
      if (status['files'] != null) {
        for (int i = 0; i < status['files'].length; i++) {
          final f = status['files'][i];
          files.add(TorrentFile(
            name: f['path']?.split('/').last ?? 'file_$i',
            size: int.tryParse(f['length']?.toString() ?? '0') ?? 0,
            index: i,
            progress: (int.tryParse(f['completedLength']?.toString() ?? '0') ?? 0) / 
                     (int.tryParse(f['length']?.toString() ?? '1') ?? 1),
          ));
        }
      }

      final totalLength = int.tryParse(status['totalLength']?.toString() ?? '0') ?? 0;
      final completedLength = int.tryParse(status['completedLength']?.toString() ?? '0') ?? 0;

      TorrentStatus torrentStatus;
      switch (status['status']) {
        case 'active':
          torrentStatus = TorrentStatus.downloading;
          break;
        case 'waiting':
          torrentStatus = TorrentStatus.checking;
          break;
        case 'paused':
          torrentStatus = TorrentStatus.paused;
          break;
        case 'complete':
          torrentStatus = TorrentStatus.completed;
          break;
        case 'error':
          torrentStatus = TorrentStatus.error;
          break;
        default:
          torrentStatus = TorrentStatus.checking;
      }

      _torrents[gid] = TorrentInfo(
        infoHash: status['infoHash'] ?? gid,
        name: status['bittorrent']?['info']?['name'] ?? 'Unknown',
        totalSize: totalLength,
        files: files,
        status: torrentStatus,
        progress: totalLength > 0 ? completedLength / totalLength : 0,
        downloadSpeed: int.tryParse(status['downloadSpeed']?.toString() ?? '0') ?? 0,
        uploadSpeed: int.tryParse(status['uploadSpeed']?.toString() ?? '0') ?? 0,
        peers: int.tryParse(status['connections']?.toString() ?? '0') ?? 0,
        seeds: int.tryParse(status['numSeeders']?.toString() ?? '0') ?? 0,
        error: status['errorMessage'],
      );

      notifyListeners();
    } catch (e) {
      debugPrint('Failed to update torrent info: $e');
    }
  }

  Future<dynamic> _rpcCall(String method, [List<dynamic>? params]) async {
    try {
      final body = {
        'jsonrpc': '2.0',
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'method': method,
        'params': ['token:$_aria2Secret', ...(params ?? [])],
      };

      final response = await _dio.post(
        _aria2RpcUrl!,
        data: jsonEncode(body),
        options: Options(contentType: 'application/json'),
      );

      if (response.data['result'] != null) {
        return response.data['result'];
      }
      if (response.data['error'] != null) {
        debugPrint('RPC error: ${response.data['error']}');
      }
    } catch (e) {
      debugPrint('RPC call failed: $e');
    }
    return null;
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
