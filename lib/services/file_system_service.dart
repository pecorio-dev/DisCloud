import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/cloud_file.dart';

class FileSystemService {
  static const String _filesKey = 'discord_cloud_files';
  static const String _webhookKey = 'discord_cloud_webhook';
  
  final Map<String, CloudFile> _files = {};
  final Uuid _uuid = const Uuid();

  Future<void> init() async {
    await _loadFromStorage();
  }

  Future<void> _loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final filesJson = prefs.getString(_filesKey);
    
    if (filesJson != null) {
      final Map<String, dynamic> data = jsonDecode(filesJson);
      _files.clear();
      data.forEach((key, value) {
        _files[key] = CloudFile.fromJson(value);
      });
    }
    
    if (!_files.containsKey('/')) {
      _files['/'] = CloudFile(
        id: _uuid.v4(),
        name: 'Root',
        path: '/',
        isDirectory: true,
      );
      await _saveToStorage();
    }
  }

  Future<void> _saveToStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic> data = {};
    _files.forEach((key, value) {
      data[key] = value.toJson();
    });
    await prefs.setString(_filesKey, jsonEncode(data));
  }

  Future<String?> getSavedWebhook() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_webhookKey);
  }

  Future<void> saveWebhook(String webhookUrl) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_webhookKey, webhookUrl);
  }

  Future<void> clearWebhook() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_webhookKey);
  }

  List<CloudFile> getChildren(String path) {
    final normalizedPath = path.endsWith('/') ? path : '$path/';
    return _files.values.where((file) {
      if (file.path == '/') return false;
      final parentPath = _getParentPath(file.path);
      return parentPath == path || parentPath == normalizedPath.substring(0, normalizedPath.length - 1);
    }).toList();
  }

  String _getParentPath(String path) {
    if (path == '/') return '/';
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.length <= 1) return '/';
    return '/${parts.sublist(0, parts.length - 1).join('/')}';
  }

  CloudFile? getFile(String path) {
    return _files[path];
  }

  Future<CloudFile> createDirectory(String parentPath, String name) async {
    final path = parentPath == '/' ? '/$name' : '$parentPath/$name';
    
    if (_files.containsKey(path)) {
      throw Exception('Directory already exists');
    }

    final dir = CloudFile(
      id: _uuid.v4(),
      name: name,
      path: path,
      isDirectory: true,
    );

    _files[path] = dir;
    await _saveToStorage();
    return dir;
  }

  Future<CloudFile> addFile({
    required String parentPath,
    required String name,
    required int size,
    List<String> chunkIds = const [],
    Map<String, List<String>> webhookChunks = const {},
    String? mimeType,
  }) async {
    final path = parentPath == '/' ? '/$name' : '$parentPath/$name';

    final file = CloudFile(
      id: _uuid.v4(),
      name: name,
      path: path,
      isDirectory: false,
      size: size,
      chunkIds: chunkIds,
      webhookChunks: webhookChunks,
      mimeType: mimeType,
    );

    _files[path] = file;
    await _saveToStorage();
    return file;
  }

  Future<void> deleteFile(String path) async {
    if (path == '/') {
      throw Exception('Cannot delete root directory');
    }

    final file = _files[path];
    if (file == null) {
      throw Exception('File not found');
    }

    if (file.isDirectory) {
      final children = getChildren(path);
      if (children.isNotEmpty) {
        throw Exception('Directory is not empty');
      }
    }

    _files.remove(path);
    await _saveToStorage();
  }

  /// Supprime tous les fichiers dans un dossier (recursif)
  Future<int> deleteAllInFolder(String folderPath) async {
    if (folderPath == '/') {
      throw Exception('Cannot delete root contents');
    }

    final children = getChildren(folderPath);
    int deleted = 0;

    for (final child in children) {
      if (child.isDirectory) {
        // Supprimer recursivement le contenu du sous-dossier
        deleted += await deleteAllInFolder(child.path);
        _files.remove(child.path);
        deleted++;
      } else {
        _files.remove(child.path);
        deleted++;
      }
    }

    await _saveToStorage();
    return deleted;
  }

  /// Vide un dossier mais garde le dossier
  Future<int> emptyFolder(String folderPath) async {
    final children = getChildren(folderPath);
    int deleted = 0;

    for (final child in children) {
      if (child.isDirectory) {
        deleted += await deleteAllInFolder(child.path);
        _files.remove(child.path);
        deleted++;
      } else {
        _files.remove(child.path);
        deleted++;
      }
    }

    await _saveToStorage();
    return deleted;
  }

  Future<CloudFile> renameFile(String path, String newName) async {
    final file = _files[path];
    if (file == null) {
      throw Exception('File not found');
    }

    final parentPath = _getParentPath(path);
    final newPath = parentPath == '/' ? '/$newName' : '$parentPath/$newName';

    if (_files.containsKey(newPath) && newPath != path) {
      throw Exception('A file with that name already exists');
    }

    final renamedFile = file.copyWith(
      name: newName,
      path: newPath,
      modifiedAt: DateTime.now(),
    );

    _files.remove(path);
    _files[newPath] = renamedFile;
    await _saveToStorage();
    return renamedFile;
  }

  Future<void> clearAll() async {
    _files.clear();
    _files['/'] = CloudFile(
      id: _uuid.v4(),
      name: 'Root',
      path: '/',
      isDirectory: true,
    );
    await _saveToStorage();
  }

  int get totalFiles => _files.values.where((f) => !f.isDirectory).length;
  int get totalFolders => _files.values.where((f) => f.isDirectory).length - 1;
  int get totalSize => _files.values.fold(0, (sum, f) => sum + f.size);

  /// Retourne tous les fichiers pour export
  Map<String, CloudFile> getAllFiles() {
    return Map.from(_files);
  }

  /// Importe un fichier depuis un index externe
  Future<void> importFile(CloudFile file) async {
    // S'assurer que le chemin parent existe
    final parentPath = _getParentPath(file.path);
    if (parentPath != '/' && !_files.containsKey(parentPath)) {
      // Creer les dossiers parents
      final parts = parentPath.split('/').where((p) => p.isNotEmpty).toList();
      String currentPath = '/';
      for (final part in parts) {
        final dirPath = currentPath == '/' ? '/$part' : '$currentPath/$part';
        if (!_files.containsKey(dirPath)) {
          _files[dirPath] = CloudFile(
            id: _uuid.v4(),
            name: part,
            path: dirPath,
            isDirectory: true,
          );
        }
        currentPath = dirPath;
      }
    }
    
    // Ajouter le fichier
    _files[file.path] = file;
    await _saveToStorage();
  }
}
