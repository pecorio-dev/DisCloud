import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/cloud_file.dart';
import '../services/discord_service.dart';

enum CloudStatus { idle, loading, uploading, downloading, syncing, error }

/// Index stocke sur Discord
class CloudIndex {
  static const String marker = '::DISCLOUD_INDEX_V2::';
  
  String? indexMessageId;
  Map<String, CloudFile> files = {};
  Map<String, dynamic> settings = {
    'hasNitro': false,
    'compression': true,
    'theme': 'system',
  };
  DateTime lastModified = DateTime.now();

  CloudIndex();

  factory CloudIndex.fromJson(Map<String, dynamic> json) {
    final index = CloudIndex();
    index.indexMessageId = json['indexMsgId'];
    index.lastModified = json['lastMod'] != null 
        ? DateTime.fromMillisecondsSinceEpoch(json['lastMod'])
        : DateTime.now();
    index.settings = Map<String, dynamic>.from(json['settings'] ?? {});
    
    if (json['files'] != null) {
      final Map<String, dynamic> filesJson = json['files'];
      filesJson.forEach((key, value) {
        index.files[key] = CloudFile.fromJson(value);
      });
    }
    return index;
  }

  Map<String, dynamic> toJson() {
    return {
      'marker': marker,
      'indexMsgId': indexMessageId,
      'lastMod': lastModified.millisecondsSinceEpoch,
      'settings': settings,
      'files': files.map((k, v) => MapEntry(k, v.toJson())),
    };
  }

  Uint8List toCompressedBytes() {
    final json = jsonEncode(toJson());
    final bytes = utf8.encode(json);
    final compressed = gzip.encode(bytes);
    return Uint8List.fromList(compressed);
  }

  static CloudIndex? fromCompressedBytes(Uint8List data) {
    try {
      final decompressed = gzip.decode(data);
      final json = utf8.decode(decompressed);
      final map = jsonDecode(json);
      if (map['marker'] == marker) {
        return CloudIndex.fromJson(map);
      }
    } catch (e) {
      debugPrint('Failed to parse index: $e');
    }
    return null;
  }
}

class CloudProvider extends ChangeNotifier {
  DiscordService? _discord;
  CloudIndex _index = CloudIndex();
  final Dio _dio = Dio();
  CancelToken? _cancelToken;
  final _uuid = const Uuid();

  String _currentPath = '/';
  List<CloudFile> _currentFiles = [];
  CloudStatus _status = CloudStatus.idle;
  String? _errorMessage;
  double _progress = 0;
  bool _isInitialized = false;
  String? _currentOperation;
  String? _webhookUrl;

  // Getters
  String get currentPath => _currentPath;
  List<CloudFile> get currentFiles => _currentFiles;
  CloudStatus get status => _status;
  String? get errorMessage => _errorMessage;
  double get progress => _progress;
  bool get isInitialized => _isInitialized;
  bool get isConnected => _discord != null;
  String? get currentOperation => _currentOperation;
  bool get canCancel => _cancelToken != null && !_cancelToken!.isCancelled;
  Map<String, dynamic> get settings => _index.settings;

  int get totalFiles => _index.files.values.where((f) => !f.isDirectory).length;
  int get totalFolders => _index.files.values.where((f) => f.isDirectory).length;
  int get totalSize => _index.files.values.fold(0, (sum, f) => sum + f.size);

  Future<void> init() async {
    _isInitialized = true;
    notifyListeners();
  }

  /// Connexion au webhook et chargement de l'index depuis Discord
  Future<bool> connect(String webhookUrl) async {
    _status = CloudStatus.loading;
    _currentOperation = 'Connecting...';
    notifyListeners();

    try {
      final discord = DiscordService(webhookUrl: webhookUrl);
      final isValid = await discord.validateWebhook();

      if (!isValid) {
        _errorMessage = 'Invalid webhook URL';
        _status = CloudStatus.error;
        notifyListeners();
        return false;
      }

      _discord = discord;
      _webhookUrl = webhookUrl;
      
      // Chercher l'index existant sur Discord
      await _loadIndexFromDiscord();
      
      // Creer dossier racine si besoin
      if (!_index.files.containsKey('/')) {
        _index.files['/'] = CloudFile(
          id: 'root',
          name: 'Root',
          path: '/',
          isDirectory: true,
        );
      }

      _status = CloudStatus.idle;
      _currentOperation = null;
      _refreshCurrentDirectory();
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Connection failed: $e';
      _status = CloudStatus.error;
      _currentOperation = null;
      notifyListeners();
      return false;
    }
  }

  /// Charge l'index depuis Discord (cherche le message avec le marker)
  Future<void> _loadIndexFromDiscord() async {
    if (_discord == null) return;
    
    _currentOperation = 'Loading index from Discord...';
    notifyListeners();

    try {
      // Recuperer les derniers messages pour trouver l'index
      final response = await _dio.get(
        '${_webhookUrl!.replaceAll('/webhooks/', '/channels/').split('/').take(6).join('/')}/messages?limit=50',
        options: Options(headers: {
          'Authorization': 'Bot ${_discord!.webhookToken}', // Ne marchera pas sans bot
        }),
      );
      // Cette methode ne marche pas sans bot token, on utilise une autre approche
    } catch (e) {
      // Fallback: pas d'index trouve, on part de zero
      debugPrint('No existing index found, starting fresh');
    }

    // Si on a un indexMessageId sauvegarde localement temporairement
    // pour la transition, on le charge
    try {
      final tempDir = await getTemporaryDirectory();
      final indexFile = File('${tempDir.path}/discloud_index_ref.txt');
      if (await indexFile.exists()) {
        final msgId = await indexFile.readAsString();
        if (msgId.isNotEmpty) {
          final msg = await _discord!.getMessage(msgId.trim());
          if (msg != null && msg['attachments'] != null) {
            final attachments = msg['attachments'] as List;
            if (attachments.isNotEmpty) {
              final url = attachments[0]['url'];
              final response = await _dio.get<List<int>>(
                url,
                options: Options(responseType: ResponseType.bytes),
              );
              if (response.data != null) {
                final loaded = CloudIndex.fromCompressedBytes(Uint8List.fromList(response.data!));
                if (loaded != null) {
                  _index = loaded;
                  _index.indexMessageId = msgId.trim();
                  debugPrint('Index loaded: ${_index.files.length} files');
                }
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to load saved index: $e');
    }
  }

  /// Sauvegarde l'index sur Discord
  Future<void> _saveIndexToDiscord() async {
    if (_discord == null) return;

    try {
      _index.lastModified = DateTime.now();
      final data = _index.toCompressedBytes();
      
      // Verifier taille < 9MB
      if (data.length > 9 * 1024 * 1024) {
        throw Exception('Index too large (${(data.length / 1024 / 1024).toStringAsFixed(2)} MB)');
      }

      String? newMsgId;
      
      if (_index.indexMessageId != null) {
        // Essayer de mettre a jour le message existant
        final success = await _discord!.editMessage(
          _index.indexMessageId!,
          content: CloudIndex.marker,
          fileData: data,
          filename: 'index.dcidx',
        );
        if (success) {
          newMsgId = _index.indexMessageId;
        }
      }
      
      if (newMsgId == null) {
        // Creer nouveau message d'index
        newMsgId = await _discord!.sendMessage(
          CloudIndex.marker,
          filename: 'index.dcidx',
          fileData: data,
        );
        _index.indexMessageId = newMsgId;
      }

      // Sauvegarder la reference localement (temporaire pour transition)
      if (newMsgId != null) {
        final tempDir = await getTemporaryDirectory();
        final indexFile = File('${tempDir.path}/discloud_index_ref.txt');
        await indexFile.writeAsString(newMsgId);
      }
    } catch (e) {
      debugPrint('Failed to save index: $e');
    }
  }

  void cancelCurrentOperation() {
    _cancelToken?.cancel('Cancelled');
    _cancelToken = null;
    _status = CloudStatus.idle;
    _progress = 0;
    _currentOperation = null;
    notifyListeners();
  }

  Future<void> disconnect() async {
    _discord = null;
    _webhookUrl = null;
    _index = CloudIndex();
    _currentFiles = [];
    _currentPath = '/';
    notifyListeners();
  }

  Future<void> navigateTo(String path) async {
    _currentPath = path;
    _refreshCurrentDirectory();
  }

  Future<void> navigateUp() async {
    if (_currentPath == '/') return;
    final parts = _currentPath.split('/').where((p) => p.isNotEmpty).toList();
    _currentPath = parts.length <= 1 ? '/' : '/${parts.sublist(0, parts.length - 1).join('/')}';
    _refreshCurrentDirectory();
  }

  void _refreshCurrentDirectory() {
    _currentFiles = _index.files.values.where((f) {
      if (f.path == '/') return false;
      final parentPath = _getParentPath(f.path);
      return parentPath == _currentPath;
    }).toList();
    
    _currentFiles.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    notifyListeners();
  }

  Future<void> createFolder(String name) async {
    final path = _currentPath == '/' ? '/$name' : '$_currentPath/$name';
    
    if (_index.files.containsKey(path)) {
      _errorMessage = 'Folder already exists';
      return;
    }

    _index.files[path] = CloudFile(
      id: _uuid.v4(),
      name: name,
      path: path,
      isDirectory: true,
    );
    
    await _saveIndexToDiscord();
    _refreshCurrentDirectory();
  }

  // ==================== UPLOAD ====================

  Future<void> uploadFile(String name, Uint8List data, {String? mimeType}) async {
    if (_discord == null) {
      _errorMessage = 'Not connected';
      _status = CloudStatus.error;
      notifyListeners();
      return;
    }

    final path = _currentPath == '/' ? '/$name' : '$_currentPath/$name';
    
    // Si le fichier existe deja, le supprimer d'abord de Discord
    if (_index.files.containsKey(path)) {
      await _deleteFileFromDiscord(_index.files[path]!);
    }

    _status = CloudStatus.uploading;
    _progress = 0;
    _currentOperation = 'Uploading $name';
    _cancelToken = CancelToken();
    notifyListeners();

    try {
      final result = await _discord!.uploadFile(
        data,
        name,
        cancelToken: _cancelToken,
        onProgress: (p) {
          _progress = p;
          notifyListeners();
        },
      );

      _index.files[path] = CloudFile(
        id: _uuid.v4(),
        name: name,
        path: path,
        isDirectory: false,
        size: data.length,
        chunkUrls: result.urls,
        messageIds: result.messageIds,
        mimeType: mimeType,
        isCompressed: result.isCompressed,
      );

      await _saveIndexToDiscord();
      
      _status = CloudStatus.idle;
      _progress = 0;
      _currentOperation = null;
      _cancelToken = null;
      _refreshCurrentDirectory();
    } catch (e) {
      if (!e.toString().contains('Cancelled')) {
        _errorMessage = 'Upload failed: $e';
        _status = CloudStatus.error;
      } else {
        _status = CloudStatus.idle;
      }
      _progress = 0;
      _currentOperation = null;
      _cancelToken = null;
      notifyListeners();
    }
  }

  Future<void> uploadFromUrl(String url, {String? customName}) async {
    _status = CloudStatus.downloading;
    _progress = 0;
    _currentOperation = 'Downloading from URL';
    _cancelToken = CancelToken();
    notifyListeners();

    try {
      final uri = Uri.parse(url);
      String fileName = customName ?? uri.pathSegments.lastOrNull ?? 'file';
      
      final response = await _dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
        cancelToken: _cancelToken,
        onReceiveProgress: (recv, total) {
          if (total > 0) { _progress = recv / total * 0.5; notifyListeners(); }
        },
      );

      if (response.data == null) throw Exception('No data');
      
      _currentOperation = 'Uploading $fileName';
      _progress = 0.5;
      notifyListeners();

      await uploadFile(fileName, Uint8List.fromList(response.data!));
    } catch (e) {
      if (!e.toString().contains('Cancelled')) {
        _errorMessage = 'Failed: $e';
        _status = CloudStatus.error;
      } else {
        _status = CloudStatus.idle;
      }
      _progress = 0;
      _currentOperation = null;
      _cancelToken = null;
      notifyListeners();
    }
  }

  // ==================== DOWNLOAD ====================

  Future<Uint8List?> downloadFile(CloudFile file) async {
    if (_discord == null || file.chunkUrls.isEmpty) return null;

    _status = CloudStatus.downloading;
    _progress = 0;
    _currentOperation = 'Downloading ${file.name}';
    _cancelToken = CancelToken();
    notifyListeners();

    try {
      final data = await _discord!.downloadFile(
        file.chunkUrls,
        isCompressed: file.isCompressed,
        cancelToken: _cancelToken,
        onProgress: (p) { _progress = p; notifyListeners(); },
      );

      _status = CloudStatus.idle;
      _progress = 0;
      _currentOperation = null;
      _cancelToken = null;
      notifyListeners();
      return data;
    } catch (e) {
      if (!e.toString().contains('Cancelled')) {
        _errorMessage = 'Download failed: $e';
        _status = CloudStatus.error;
      } else {
        _status = CloudStatus.idle;
      }
      _progress = 0;
      _currentOperation = null;
      _cancelToken = null;
      notifyListeners();
      return null;
    }
  }

  Future<String?> downloadToTemp(CloudFile file) async {
    final data = await downloadFile(file);
    if (data == null) return null;
    try {
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/${file.name}');
      await tempFile.writeAsBytes(data);
      return tempFile.path;
    } catch (e) {
      return null;
    }
  }

  // ==================== DELETE ====================

  Future<void> _deleteFileFromDiscord(CloudFile file) async {
    if (_discord == null || file.messageIds.isEmpty) return;
    await _discord!.deleteMessages(file.messageIds);
  }

  Future<void> deleteFile(CloudFile file) async {
    _currentOperation = 'Deleting ${file.name}';
    notifyListeners();

    try {
      // Supprimer de Discord
      await _deleteFileFromDiscord(file);
      
      // Supprimer de l'index
      _index.files.remove(file.path);
      
      // Si c'est un dossier, supprimer le contenu
      if (file.isDirectory) {
        final toDelete = _index.files.keys
            .where((p) => p.startsWith('${file.path}/'))
            .toList();
        for (final path in toDelete) {
          final f = _index.files[path];
          if (f != null) await _deleteFileFromDiscord(f);
          _index.files.remove(path);
        }
      }

      await _saveIndexToDiscord();
      _currentOperation = null;
      _refreshCurrentDirectory();
    } catch (e) {
      _errorMessage = 'Delete failed: $e';
      _currentOperation = null;
      notifyListeners();
    }
  }

  Future<int> deleteAllInCurrentFolder() async {
    final toDelete = _currentFiles.toList();
    int count = 0;
    for (final file in toDelete) {
      await deleteFile(file);
      count++;
    }
    return count;
  }

  // ==================== UPDATE ====================

  Future<void> updateFile(CloudFile file, Uint8List newData) async {
    // Supprimer l'ancien de Discord d'abord
    await _deleteFileFromDiscord(file);
    
    // Uploader le nouveau
    await uploadFile(file.name, newData, mimeType: file.mimeType);
  }

  Future<void> renameFile(CloudFile file, String newName) async {
    final parentPath = _getParentPath(file.path);
    final newPath = parentPath == '/' ? '/$newName' : '$parentPath/$newName';
    
    _index.files.remove(file.path);
    _index.files[newPath] = file.copyWith(name: newName, path: newPath);
    
    // Si c'est un dossier, renommer le contenu aussi
    if (file.isDirectory) {
      final toRename = _index.files.keys
          .where((p) => p.startsWith('${file.path}/'))
          .toList();
      for (final oldPath in toRename) {
        final f = _index.files[oldPath]!;
        final newChildPath = oldPath.replaceFirst(file.path, newPath);
        _index.files.remove(oldPath);
        _index.files[newChildPath] = f.copyWith(path: newChildPath);
      }
    }

    await _saveIndexToDiscord();
    _refreshCurrentDirectory();
  }

  // ==================== SETTINGS ====================

  Future<void> updateSetting(String key, dynamic value) async {
    _index.settings[key] = value;
    await _saveIndexToDiscord();
    notifyListeners();
  }

  // ==================== UTILS ====================

  String _getParentPath(String path) {
    if (path == '/') return '/';
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    return parts.length <= 1 ? '/' : '/${parts.sublist(0, parts.length - 1).join('/')}';
  }

  void clearError() {
    _errorMessage = null;
    _status = CloudStatus.idle;
    notifyListeners();
  }

  List<CloudFile> getAllFiles() {
    return _index.files.values.where((f) => !f.isDirectory).toList();
  }
}
