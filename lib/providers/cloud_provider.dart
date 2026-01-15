import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/cloud_file.dart';
import '../models/webhook_config.dart';
import '../services/discord_service.dart';
import '../services/file_system_service.dart';
import '../services/cloud_index_service.dart';

enum CloudStatus { idle, loading, uploading, downloading, syncing, error }

class CloudProvider extends ChangeNotifier {
  final FileSystemService _fileSystem = FileSystemService();
  final WebhookManager _webhookManager = WebhookManager();
  final CloudIndexService _indexService = CloudIndexService();
  final Dio _dio = Dio();
  DiscordService? _discord;

  String _currentPath = '/';
  List<CloudFile> _currentFiles = [];
  CloudStatus _status = CloudStatus.idle;
  String? _errorMessage;
  double _progress = 0;
  bool _isInitialized = false;
  String? _downloadPath;

  String get currentPath => _currentPath;
  List<CloudFile> get currentFiles => _currentFiles;
  CloudStatus get status => _status;
  String? get errorMessage => _errorMessage;
  double get progress => _progress;
  bool get isInitialized => _isInitialized;
  bool get isConnected => _discord != null || _webhookManager.activeWebhooks.isNotEmpty;
  WebhookManager get webhookManager => _webhookManager;
  String? get downloadPath => _downloadPath;

  int get totalFiles => _fileSystem.totalFiles;
  int get totalFolders => _fileSystem.totalFolders;
  int get totalSize => _fileSystem.totalSize;

  Future<void> init() async {
    await _fileSystem.init();
    await _webhookManager.init();
    
    final prefs = await SharedPreferences.getInstance();
    _downloadPath = prefs.getString('download_path');
    
    final savedWebhook = await _fileSystem.getSavedWebhook();
    if (savedWebhook != null) {
      _discord = DiscordService(webhookUrl: savedWebhook);
    }
    
    _isInitialized = true;
    await _refreshCurrentDirectory();
    notifyListeners();
  }

  Future<void> setDownloadPath(String path) async {
    _downloadPath = path;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('download_path', path);
    notifyListeners();
  }

  Future<bool> connect(String webhookUrl) async {
    _status = CloudStatus.loading;
    notifyListeners();

    try {
      final discord = DiscordService(webhookUrl: webhookUrl);
      final isValid = await discord.validateWebhook();

      if (isValid) {
        _discord = discord;
        await _fileSystem.saveWebhook(webhookUrl);
        
        try {
          await _webhookManager.addWebhook(WebhookInfo(
            url: webhookUrl,
            name: 'Primary Webhook',
          ));
        } catch (e) {}
        
        _status = CloudStatus.idle;
        notifyListeners();
        return true;
      } else {
        _errorMessage = 'Invalid webhook URL';
        _status = CloudStatus.error;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = 'Connection failed: $e';
      _status = CloudStatus.error;
      notifyListeners();
      return false;
    }
  }

  Future<void> disconnect() async {
    _discord = null;
    await _fileSystem.clearWebhook();
    notifyListeners();
  }

  Future<void> navigateTo(String path) async {
    _currentPath = path;
    await _refreshCurrentDirectory();
  }

  Future<void> navigateUp() async {
    if (_currentPath == '/') return;
    final parts = _currentPath.split('/').where((p) => p.isNotEmpty).toList();
    _currentPath = parts.length <= 1 ? '/' : '/${parts.sublist(0, parts.length - 1).join('/')}';
    await _refreshCurrentDirectory();
  }

  Future<void> _refreshCurrentDirectory() async {
    _currentFiles = _fileSystem.getChildren(_currentPath);
    _currentFiles.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    notifyListeners();
  }

  Future<void> createFolder(String name) async {
    try {
      await _fileSystem.createDirectory(_currentPath, name);
      await _refreshCurrentDirectory();
    } catch (e) {
      if (!e.toString().contains('already exists')) {
        _errorMessage = 'Failed to create folder: $e';
        _status = CloudStatus.error;
        notifyListeners();
      }
    }
  }

  Future<void> ensurePathExists(String path) async {
    if (path == '/' || path.isEmpty) return;
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    String currentPath = '/';
    for (final part in parts) {
      try { await _fileSystem.createDirectory(currentPath, part); } catch (e) {}
      currentPath = currentPath == '/' ? '/$part' : '$currentPath/$part';
    }
  }

  // ==================== UPLOAD ====================

  Future<void> uploadFile(String name, Uint8List data, {String? mimeType}) async {
    // Recharger les webhooks pour etre sur d'avoir la derniere config
    await _webhookManager.init();
    
    final webhooksToUse = _webhookManager.getWebhooksForUpload();
    final hasWebhooks = webhooksToUse.isNotEmpty;
    
    if (!hasWebhooks && _discord == null) {
      _errorMessage = 'Not connected to Discord';
      _status = CloudStatus.error;
      notifyListeners();
      return;
    }

    _status = CloudStatus.uploading;
    _progress = 0;
    notifyListeners();

    try {
      Map<String, List<String>> webhookChunks = {};
      List<String> legacyChunkIds = [];
      
      if (hasWebhooks) {
        // Upload vers TOUS les webhooks selectionnes
        for (int i = 0; i < webhooksToUse.length; i++) {
          final webhook = webhooksToUse[i];
          final service = DiscordService(webhookUrl: webhook.url);
          
          try {
            final urls = await service.uploadFile(data, name,
              onProgress: (p) {
                _progress = (i + p) / webhooksToUse.length;
                notifyListeners();
              },
            );
            
            webhookChunks[webhook.url] = urls;
            await _webhookManager.incrementStats(webhook.url, data.length);
          } catch (e) {
            // Log error but continue with other webhooks
            debugPrint('Failed to upload to ${webhook.name}: $e');
          }
        }
        
        if (webhookChunks.isEmpty) {
          throw Exception('Failed to upload to any webhook');
        }
      } else if (_discord != null) {
        legacyChunkIds = await _discord!.uploadFile(data, name,
          onProgress: (p) { _progress = p; notifyListeners(); },
        );
      }

      await _fileSystem.addFile(
        parentPath: _currentPath,
        name: name,
        size: data.length,
        chunkIds: legacyChunkIds,
        webhookChunks: webhookChunks,
        mimeType: mimeType,
      );

      _status = CloudStatus.idle;
      _progress = 0;
      await _refreshCurrentDirectory();
    } catch (e) {
      _errorMessage = 'Upload failed: $e';
      _status = CloudStatus.error;
      notifyListeners();
    }
  }

  Future<void> uploadFromUrl(String url, {String? customName}) async {
    _status = CloudStatus.downloading;
    _progress = 0;
    notifyListeners();

    try {
      final uri = Uri.parse(url);
      String fileName = customName ?? uri.pathSegments.lastOrNull ?? 'downloaded_file';
      
      final response = await _dio.get<List<int>>(url,
        options: Options(responseType: ResponseType.bytes),
        onReceiveProgress: (received, total) {
          if (total > 0) { _progress = received / total * 0.5; notifyListeners(); }
        },
      );

      if (response.data == null) throw Exception('No data received');
      
      _status = CloudStatus.uploading;
      _progress = 0.5;
      notifyListeners();

      await uploadFile(fileName, Uint8List.fromList(response.data!));
    } catch (e) {
      _errorMessage = 'URL upload failed: $e';
      _status = CloudStatus.error;
      notifyListeners();
    }
  }

  // ==================== DOWNLOAD ====================

  Future<String?> downloadToTemp(CloudFile file) async {
    final data = await _downloadFileData(file);
    if (data == null) return null;

    try {
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/preview_${file.name}');
      await tempFile.writeAsBytes(data);
      return tempFile.path;
    } catch (e) {
      _errorMessage = 'Failed to save temp file: $e';
      return null;
    }
  }

  Future<String?> downloadToSync(CloudFile file) async {
    if (_downloadPath == null) {
      _errorMessage = 'No download path configured';
      _status = CloudStatus.error;
      notifyListeners();
      return null;
    }

    final data = await _downloadFileData(file);
    if (data == null) return null;

    try {
      final filePath = '$_downloadPath/${file.name}';
      final outFile = File(filePath);
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(data);
      return filePath;
    } catch (e) {
      _errorMessage = 'Failed to save file: $e';
      return null;
    }
  }

  Future<Uint8List?> downloadFile(CloudFile file) async {
    return await _downloadFileData(file);
  }

  Future<Uint8List?> _downloadFileData(CloudFile file) async {
    final hasMultiWebhooks = file.webhookChunks.isNotEmpty;
    
    if (!hasMultiWebhooks && _discord == null && file.chunkIds.isEmpty) {
      _errorMessage = 'No file data available';
      _status = CloudStatus.error;
      notifyListeners();
      return null;
    }

    _status = CloudStatus.downloading;
    _progress = 0;
    notifyListeners();

    try {
      Uint8List? data;
      
      if (hasMultiWebhooks) {
        // Essayer chaque webhook jusqu'a reussir
        for (final entry in file.webhookChunks.entries) {
          try {
            final service = DiscordService(webhookUrl: entry.key);
            data = await service.downloadFile(entry.value,
              onProgress: (p) { _progress = p; notifyListeners(); },
            );
            break; // Succes!
          } catch (e) {
            debugPrint('Download from ${entry.key} failed: $e');
            // Continuer avec le prochain webhook
          }
        }
        
        if (data == null) {
          throw Exception('Failed to download from any webhook');
        }
      } else if (file.chunkIds.isNotEmpty) {
        if (_discord == null) throw Exception('Not connected');
        data = await _discord!.downloadFile(file.chunkIds,
          onProgress: (p) { _progress = p; notifyListeners(); },
        );
      } else {
        throw Exception('No download URLs available');
      }

      _status = CloudStatus.idle;
      _progress = 0;
      notifyListeners();
      return data;
    } catch (e) {
      _errorMessage = 'Download failed: $e';
      _status = CloudStatus.error;
      notifyListeners();
      return null;
    }
  }

  // ==================== CLOUD SYNC ====================

  /// Exporte l'index vers Discord pour synchronisation entre appareils
  Future<bool> exportCloudIndex() async {
    if (_webhookManager.activeWebhooks.isEmpty && _discord == null) {
      _errorMessage = 'No webhook configured';
      return false;
    }

    _status = CloudStatus.syncing;
    notifyListeners();

    try {
      final webhookUrl = _webhookManager.activeWebhooks.isNotEmpty 
          ? _webhookManager.activeWebhooks.first.url 
          : (await _fileSystem.getSavedWebhook())!;
      
      final allFiles = _fileSystem.getAllFiles();
      await _indexService.exportIndex(webhookUrl, allFiles);
      
      _status = CloudStatus.idle;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Export failed: $e';
      _status = CloudStatus.error;
      notifyListeners();
      return false;
    }
  }

  /// Importe l'index depuis un JSON (copie depuis Discord)
  Future<bool> importCloudIndex(String jsonData) async {
    _status = CloudStatus.syncing;
    notifyListeners();

    try {
      final data = jsonDecode(jsonData);
      
      if (data['files'] != null) {
        final Map<String, dynamic> files = data['files'];
        int imported = 0;
        
        for (final entry in files.entries) {
          try {
            final file = CloudFile.fromJson(entry.value);
            if (!file.isDirectory) {
              await _fileSystem.importFile(file);
              imported++;
            }
          } catch (e) {
            // Skip invalid files
          }
        }
        
        await _refreshCurrentDirectory();
        _status = CloudStatus.idle;
        notifyListeners();
        return imported > 0;
      }
      
      throw Exception('Invalid index format');
    } catch (e) {
      _errorMessage = 'Import failed: $e';
      _status = CloudStatus.error;
      notifyListeners();
      return false;
    }
  }

  // ==================== DELETE ====================

  Future<void> deleteFile(CloudFile file) async {
    try {
      await _fileSystem.deleteFile(file.path);
      await _refreshCurrentDirectory();
    } catch (e) {
      _errorMessage = 'Failed to delete: $e';
      _status = CloudStatus.error;
      notifyListeners();
    }
  }

  Future<int> deleteAllInCurrentFolder() async {
    try {
      final count = await _fileSystem.emptyFolder(_currentPath);
      await _refreshCurrentDirectory();
      return count;
    } catch (e) {
      _errorMessage = 'Failed to delete: $e';
      _status = CloudStatus.error;
      notifyListeners();
      return 0;
    }
  }

  Future<int> deleteFolderRecursive(CloudFile folder) async {
    if (!folder.isDirectory) {
      await deleteFile(folder);
      return 1;
    }

    try {
      final count = await _fileSystem.deleteAllInFolder(folder.path);
      await _fileSystem.deleteFile(folder.path);
      await _refreshCurrentDirectory();
      return count + 1;
    } catch (e) {
      _errorMessage = 'Failed to delete folder: $e';
      _status = CloudStatus.error;
      notifyListeners();
      return 0;
    }
  }

  // ==================== RENAME / UPDATE ====================

  Future<void> renameFile(CloudFile file, String newName) async {
    try {
      await _fileSystem.renameFile(file.path, newName);
      await _refreshCurrentDirectory();
    } catch (e) {
      _errorMessage = 'Failed to rename: $e';
      _status = CloudStatus.error;
      notifyListeners();
    }
  }

  Future<void> updateFile(CloudFile file, Uint8List newData) async {
    await _webhookManager.init();
    final webhooksToUse = _webhookManager.getWebhooksForUpload();
    
    if (webhooksToUse.isEmpty && _discord == null) {
      _errorMessage = 'Not connected to Discord';
      _status = CloudStatus.error;
      notifyListeners();
      return;
    }

    _status = CloudStatus.uploading;
    _progress = 0;
    notifyListeners();

    try {
      Map<String, List<String>> webhookChunks = {};
      List<String> legacyChunkIds = [];
      
      if (webhooksToUse.isNotEmpty) {
        for (int i = 0; i < webhooksToUse.length; i++) {
          final webhook = webhooksToUse[i];
          final service = DiscordService(webhookUrl: webhook.url);
          
          try {
            final urls = await service.uploadFile(newData, file.name,
              onProgress: (p) { _progress = (i + p) / webhooksToUse.length; notifyListeners(); },
            );
            webhookChunks[webhook.url] = urls;
          } catch (e) {
            debugPrint('Failed to update on ${webhook.name}: $e');
          }
        }
      } else if (_discord != null) {
        legacyChunkIds = await _discord!.uploadFile(newData, file.name,
          onProgress: (p) { _progress = p; notifyListeners(); },
        );
      }

      await _fileSystem.deleteFile(file.path);
      await _fileSystem.addFile(
        parentPath: _getParentPath(file.path),
        name: file.name,
        size: newData.length,
        chunkIds: legacyChunkIds,
        webhookChunks: webhookChunks,
        mimeType: file.mimeType,
      );

      _status = CloudStatus.idle;
      _progress = 0;
      await _refreshCurrentDirectory();
    } catch (e) {
      _errorMessage = 'Update failed: $e';
      _status = CloudStatus.error;
      notifyListeners();
    }
  }

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

  Future<void> cleanTempFiles() async {
    try {
      final tempDir = await getTemporaryDirectory();
      for (final file in tempDir.listSync()) {
        if (file is File && file.path.contains('preview_')) {
          await file.delete();
        }
      }
    } catch (e) {}
  }
}
