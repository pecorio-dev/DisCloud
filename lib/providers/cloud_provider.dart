import 'dart:async';
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

class CloudIndex {
  static const String marker = '::DISCLOUD_INDEX_V3::';
  
  String? indexMessageId;
  Map<String, CloudFile> files = {};
  Map<String, dynamic> settings = {
    'hasNitro': false,
    'compression': true,
    'theme': 'system',
    'autoSyncEnabled': false,
    'autoSyncInterval': 30,
  };
  List<SyncFolder> syncFolders = [];
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
    
    if (json['syncFolders'] != null) {
      index.syncFolders = (json['syncFolders'] as List)
          .map((e) => SyncFolder.fromJson(e))
          .toList();
    }
    
    return index;
  }

  Map<String, dynamic> toJson() => {
    'marker': marker,
    'indexMsgId': indexMessageId,
    'lastMod': lastModified.millisecondsSinceEpoch,
    'settings': settings,
    'files': files.map((k, v) => MapEntry(k, v.toJson())),
    'syncFolders': syncFolders.map((e) => e.toJson()).toList(),
  };

  Uint8List toCompressedBytes() {
    final json = jsonEncode(toJson());
    final bytes = utf8.encode(json);
    return Uint8List.fromList(gzip.encode(bytes));
  }

  static CloudIndex? fromCompressedBytes(Uint8List data) {
    try {
      final decompressed = gzip.decode(data);
      final json = utf8.decode(decompressed);
      final map = jsonDecode(json);
      if (map['marker'] == marker || map['marker'] == '::DISCLOUD_INDEX_V2::') {
        return CloudIndex.fromJson(map);
      }
    } catch (e) {
      debugPrint('Failed to parse index: $e');
    }
    return null;
  }
}

class CloudProvider extends ChangeNotifier {
  final Map<String, DiscordService> _services = {};
  final Map<String, WebhookInfo> _webhooks = {};
  final Map<String, CloudIndex> _indexes = {};
  final Dio _dio = Dio();
  final _uuid = const Uuid();
  
  CancelToken? _cancelToken;
  Timer? _autoSyncTimer;
  
  String? _currentWebhookId;
  String _currentPath = '/';
  List<CloudFile> _currentFiles = [];
  CloudStatus _status = CloudStatus.idle;
  String? _errorMessage;
  double _progress = 0;
  bool _isInitialized = false;
  String? _currentOperation;

  // Getters
  String get currentPath => _currentPath;
  List<CloudFile> get currentFiles => _currentFiles;
  CloudStatus get status => _status;
  String? get errorMessage => _errorMessage;
  double get progress => _progress;
  bool get isInitialized => _isInitialized;
  String? get currentOperation => _currentOperation;
  bool get canCancel => _cancelToken != null && !_cancelToken!.isCancelled;
  
  List<WebhookInfo> get webhooks => _webhooks.values.toList();
  WebhookInfo? get currentWebhook => _currentWebhookId != null ? _webhooks[_currentWebhookId] : null;
  String? get currentWebhookId => _currentWebhookId;
  bool get isConnected => _webhooks.isNotEmpty;
  bool get hasMultipleWebhooks => _webhooks.length > 1;
  
  CloudIndex get _currentIndex => _indexes[_currentWebhookId] ?? CloudIndex();
  Map<String, dynamic> get settings => _currentIndex.settings;
  List<SyncFolder> get syncFolders => _currentIndex.syncFolders;

  int get totalFiles => _currentIndex.files.values.where((f) => !f.isDirectory).length;
  int get totalFolders => _currentIndex.files.values.where((f) => f.isDirectory).length;
  int get totalSize => _currentIndex.files.values.fold(0, (sum, f) => sum + f.size);

  Future<void> init() async {
    await _loadWebhooksFromLocal();
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> _loadWebhooksFromLocal() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/discloud_webhooks.json');
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString());
        final List webhooksList = json['webhooks'] ?? [];
        for (final w in webhooksList) {
          final info = WebhookInfo.fromJson(w);
          _webhooks[info.id] = info;
          _services[info.id] = DiscordService(webhookUrl: info.url);
        }
        if (_webhooks.isNotEmpty && _currentWebhookId == null) {
          await selectWebhook(_webhooks.keys.first);
        }
      }
    } catch (e) {
      debugPrint('Failed to load webhooks: $e');
    }
  }

  Future<void> _saveWebhooksToLocal() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/discloud_webhooks.json');
      await file.writeAsString(jsonEncode({
        'webhooks': _webhooks.values.map((w) => w.toJson()).toList(),
      }));
    } catch (e) {
      debugPrint('Failed to save webhooks: $e');
    }
  }

  // ==================== WEBHOOK MANAGEMENT ====================

  Future<bool> addWebhook(String url, {String? name}) async {
    _status = CloudStatus.loading;
    _currentOperation = 'Adding webhook...';
    notifyListeners();

    try {
      final service = DiscordService(webhookUrl: url);
      final isValid = await service.validateWebhook();
      if (!isValid) {
        _errorMessage = 'Invalid webhook URL';
        _status = CloudStatus.error;
        notifyListeners();
        return false;
      }

      final info = await service.getWebhookInfo();
      final webhookId = service.webhookId;
      
      if (_webhooks.containsKey(webhookId)) {
        _errorMessage = 'Webhook already added';
        _status = CloudStatus.error;
        notifyListeners();
        return false;
      }

      _webhooks[webhookId] = WebhookInfo(
        id: webhookId,
        name: name ?? info?['name'] ?? 'Webhook ${_webhooks.length + 1}',
        url: url,
      );
      _services[webhookId] = service;
      _indexes[webhookId] = CloudIndex();

      await _saveWebhooksToLocal();
      
      // Charger l'index de ce webhook
      await _loadIndexForWebhook(webhookId);

      if (_currentWebhookId == null) {
        await selectWebhook(webhookId);
      }

      _status = CloudStatus.idle;
      _currentOperation = null;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to add webhook: $e';
      _status = CloudStatus.error;
      _currentOperation = null;
      notifyListeners();
      return false;
    }
  }

  Future<void> removeWebhook(String webhookId) async {
    _webhooks.remove(webhookId);
    _services.remove(webhookId);
    _indexes.remove(webhookId);
    
    if (_currentWebhookId == webhookId) {
      _currentWebhookId = _webhooks.isNotEmpty ? _webhooks.keys.first : null;
      _refreshCurrentDirectory();
    }
    
    await _saveWebhooksToLocal();
    notifyListeners();
  }

  Future<void> selectWebhook(String webhookId) async {
    if (!_webhooks.containsKey(webhookId)) return;
    
    _currentWebhookId = webhookId;
    _currentPath = '/';
    
    if (!_indexes.containsKey(webhookId)) {
      await _loadIndexForWebhook(webhookId);
    }
    
    // Creer dossier racine si besoin
    if (!_currentIndex.files.containsKey('/')) {
      _currentIndex.files['/'] = CloudFile(
        id: 'root',
        name: 'Root',
        path: '/',
        isDirectory: true,
        webhookId: webhookId,
      );
    }
    
    _refreshCurrentDirectory();
    _updateWebhookStats(webhookId);
    _setupAutoSync();
  }

  Future<void> renameWebhook(String webhookId, String newName) async {
    if (_webhooks.containsKey(webhookId)) {
      _webhooks[webhookId] = _webhooks[webhookId]!.copyWith(name: newName);
      await _saveWebhooksToLocal();
      notifyListeners();
    }
  }

  void _updateWebhookStats(String webhookId) {
    final index = _indexes[webhookId];
    if (index != null && _webhooks.containsKey(webhookId)) {
      final files = index.files.values.where((f) => !f.isDirectory);
      _webhooks[webhookId] = _webhooks[webhookId]!.copyWith(
        fileCount: files.length,
        totalSize: files.fold<int>(0, (sum, f) => sum + f.size),
      );
    }
  }

  // ==================== INDEX MANAGEMENT ====================

  Future<void> _loadIndexForWebhook(String webhookId) async {
    final service = _services[webhookId];
    final webhook = _webhooks[webhookId];
    if (service == null || webhook == null) return;

    _currentOperation = 'Loading index...';
    notifyListeners();

    try {
      // Essayer de charger depuis le message ID sauvegarde
      if (webhook.indexMessageId != null) {
        final msg = await service.getMessage(webhook.indexMessageId!);
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
                _indexes[webhookId] = loaded;
                _indexes[webhookId]!.indexMessageId = webhook.indexMessageId;
                debugPrint('Index loaded for $webhookId: ${loaded.files.length} files');
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to load index for $webhookId: $e');
    }

    _indexes[webhookId] ??= CloudIndex();
    _currentOperation = null;
    notifyListeners();
  }

  Future<void> _saveIndexForWebhook(String webhookId) async {
    final service = _services[webhookId];
    final index = _indexes[webhookId];
    if (service == null || index == null) return;

    try {
      index.lastModified = DateTime.now();
      final data = index.toCompressedBytes();
      
      if (data.length > 9 * 1024 * 1024) {
        throw Exception('Index too large');
      }

      String? newMsgId;
      
      if (index.indexMessageId != null) {
        final success = await service.editMessage(
          index.indexMessageId!,
          content: CloudIndex.marker,
          fileData: data,
          filename: 'index.dcidx',
        );
        if (success) newMsgId = index.indexMessageId;
      }
      
      if (newMsgId == null) {
        newMsgId = await service.sendMessage(
          CloudIndex.marker,
          filename: 'index.dcidx',
          fileData: data,
        );
        index.indexMessageId = newMsgId;
      }

      if (newMsgId != null && _webhooks.containsKey(webhookId)) {
        _webhooks[webhookId] = _webhooks[webhookId]!.copyWith(indexMessageId: newMsgId);
        await _saveWebhooksToLocal();
      }
    } catch (e) {
      debugPrint('Failed to save index: $e');
    }
  }

  // ==================== AUTO SYNC ====================

  void _setupAutoSync() {
    _autoSyncTimer?.cancel();
    
    final enabled = _currentIndex.settings['autoSyncEnabled'] == true;
    final interval = _currentIndex.settings['autoSyncInterval'] as int? ?? 30;
    
    if (enabled && syncFolders.any((f) => f.autoSync)) {
      _autoSyncTimer = Timer.periodic(Duration(minutes: interval), (_) => _runAutoSync());
    }
  }

  Future<void> _runAutoSync() async {
    if (_status != CloudStatus.idle) return;
    
    for (final folder in syncFolders.where((f) => f.autoSync)) {
      if (folder.webhookId == _currentWebhookId) {
        await syncFolder(folder);
      }
    }
  }

  Future<void> addSyncFolder(SyncFolder folder) async {
    _currentIndex.syncFolders.add(folder.copyWith(webhookId: _currentWebhookId ?? ''));
    await _saveIndexForWebhook(_currentWebhookId!);
    _setupAutoSync();
    notifyListeners();
  }

  Future<void> removeSyncFolder(String localPath) async {
    _currentIndex.syncFolders.removeWhere((f) => f.localPath == localPath);
    await _saveIndexForWebhook(_currentWebhookId!);
    _setupAutoSync();
    notifyListeners();
  }

  Future<void> updateSyncFolder(SyncFolder folder) async {
    final index = _currentIndex.syncFolders.indexWhere((f) => f.localPath == folder.localPath);
    if (index >= 0) {
      _currentIndex.syncFolders[index] = folder;
      await _saveIndexForWebhook(_currentWebhookId!);
      _setupAutoSync();
      notifyListeners();
    }
  }

  Future<void> syncFolder(SyncFolder folder) async {
    if (_currentWebhookId == null || kIsWeb) return;

    _status = CloudStatus.syncing;
    _currentOperation = 'Syncing ${folder.localPath.split(Platform.pathSeparator).last}...';
    _progress = 0;
    notifyListeners();

    try {
      final dir = Directory(folder.localPath);
      if (!await dir.exists()) throw Exception('Folder not found');

      final files = await dir.list(recursive: true).where((e) => e is File).toList();
      
      for (int i = 0; i < files.length; i++) {
        final file = files[i] as File;
        final relativePath = file.path.substring(folder.localPath.length).replaceAll('\\', '/');
        final cloudPath = folder.cloudPath == '/' 
            ? relativePath 
            : '${folder.cloudPath}$relativePath';

        _progress = i / files.length;
        _currentOperation = 'Uploading ${file.uri.pathSegments.last}...';
        notifyListeners();

        final bytes = await file.readAsBytes();
        await _uploadFileInternal(file.uri.pathSegments.last, bytes, cloudPath: cloudPath);
      }

      // Update last sync
      final idx = _currentIndex.syncFolders.indexWhere((f) => f.localPath == folder.localPath);
      if (idx >= 0) {
        _currentIndex.syncFolders[idx] = folder.copyWith(lastSync: DateTime.now());
        await _saveIndexForWebhook(_currentWebhookId!);
      }

      _status = CloudStatus.idle;
      _progress = 0;
      _currentOperation = null;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Sync failed: $e';
      _status = CloudStatus.error;
      _progress = 0;
      _currentOperation = null;
      notifyListeners();
    }
  }

  // ==================== NAVIGATION ====================

  void cancelCurrentOperation() {
    _cancelToken?.cancel('Cancelled');
    _cancelToken = null;
    _status = CloudStatus.idle;
    _progress = 0;
    _currentOperation = null;
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
    _currentFiles = _currentIndex.files.values.where((f) {
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
    if (_currentWebhookId == null) return;
    
    final path = _currentPath == '/' ? '/$name' : '$_currentPath/$name';
    
    if (_currentIndex.files.containsKey(path)) {
      _errorMessage = 'Folder already exists';
      notifyListeners();
      return;
    }

    _currentIndex.files[path] = CloudFile(
      id: _uuid.v4(),
      name: name,
      path: path,
      isDirectory: true,
      webhookId: _currentWebhookId!,
    );
    
    await _saveIndexForWebhook(_currentWebhookId!);
    _refreshCurrentDirectory();
  }

  // ==================== UPLOAD ====================

  Future<void> uploadFile(String name, Uint8List data, {String? mimeType}) async {
    await _uploadFileInternal(name, data, mimeType: mimeType);
  }

  Future<void> _uploadFileInternal(String name, Uint8List data, {String? mimeType, String? cloudPath}) async {
    if (_currentWebhookId == null) {
      _errorMessage = 'No webhook selected';
      _status = CloudStatus.error;
      notifyListeners();
      return;
    }

    final service = _services[_currentWebhookId];
    if (service == null) return;

    final path = cloudPath ?? (_currentPath == '/' ? '/$name' : '$_currentPath/$name');
    
    // Si existe, supprimer d'abord
    if (_currentIndex.files.containsKey(path)) {
      await _deleteFileFromDiscord(_currentIndex.files[path]!);
    }

    _status = CloudStatus.uploading;
    _progress = 0;
    _currentOperation = 'Uploading $name';
    _cancelToken = CancelToken();
    notifyListeners();

    try {
      final result = await service.uploadFile(
        data, name,
        cancelToken: _cancelToken,
        onProgress: (p) { _progress = p; notifyListeners(); },
      );

      _currentIndex.files[path] = CloudFile(
        id: _uuid.v4(),
        name: name,
        path: path,
        isDirectory: false,
        size: data.length,
        chunkUrls: result.urls,
        messageIds: result.messageIds,
        mimeType: mimeType,
        isCompressed: result.isCompressed,
        webhookId: _currentWebhookId!,
      );

      await _saveIndexForWebhook(_currentWebhookId!);
      _updateWebhookStats(_currentWebhookId!);
      
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
    final service = _services[file.webhookId.isNotEmpty ? file.webhookId : _currentWebhookId];
    if (service == null || file.chunkUrls.isEmpty) return null;

    _status = CloudStatus.downloading;
    _progress = 0;
    _currentOperation = 'Downloading ${file.name}';
    _cancelToken = CancelToken();
    notifyListeners();

    try {
      final data = await service.downloadFile(
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
    final service = _services[file.webhookId.isNotEmpty ? file.webhookId : _currentWebhookId];
    if (service == null || file.messageIds.isEmpty) return;
    await service.deleteMessages(file.messageIds);
  }

  Future<void> deleteFile(CloudFile file) async {
    _currentOperation = 'Deleting ${file.name}';
    notifyListeners();

    try {
      await _deleteFileFromDiscord(file);
      _currentIndex.files.remove(file.path);
      
      if (file.isDirectory) {
        final toDelete = _currentIndex.files.keys.where((p) => p.startsWith('${file.path}/')).toList();
        for (final path in toDelete) {
          final f = _currentIndex.files[path];
          if (f != null) await _deleteFileFromDiscord(f);
          _currentIndex.files.remove(path);
        }
      }

      await _saveIndexForWebhook(_currentWebhookId!);
      _updateWebhookStats(_currentWebhookId!);
      _currentOperation = null;
      _refreshCurrentDirectory();
    } catch (e) {
      _errorMessage = 'Delete failed: $e';
      _currentOperation = null;
      notifyListeners();
    }
  }

  // ==================== UPDATE ====================

  Future<void> updateFile(CloudFile file, Uint8List newData) async {
    await _deleteFileFromDiscord(file);
    await uploadFile(file.name, newData, mimeType: file.mimeType);
  }

  Future<void> renameFile(CloudFile file, String newName) async {
    final parentPath = _getParentPath(file.path);
    final newPath = parentPath == '/' ? '/$newName' : '$parentPath/$newName';
    
    _currentIndex.files.remove(file.path);
    _currentIndex.files[newPath] = file.copyWith(name: newName, path: newPath);
    
    if (file.isDirectory) {
      final toRename = _currentIndex.files.keys.where((p) => p.startsWith('${file.path}/')).toList();
      for (final oldPath in toRename) {
        final f = _currentIndex.files[oldPath]!;
        final newChildPath = oldPath.replaceFirst(file.path, newPath);
        _currentIndex.files.remove(oldPath);
        _currentIndex.files[newChildPath] = f.copyWith(path: newChildPath);
      }
    }

    await _saveIndexForWebhook(_currentWebhookId!);
    _refreshCurrentDirectory();
  }

  // ==================== SETTINGS ====================

  Future<void> updateSetting(String key, dynamic value) async {
    _currentIndex.settings[key] = value;
    await _saveIndexForWebhook(_currentWebhookId!);
    if (key == 'autoSyncEnabled' || key == 'autoSyncInterval') {
      _setupAutoSync();
    }
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
    return _currentIndex.files.values.where((f) => !f.isDirectory).toList();
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    super.dispose();
  }
}
