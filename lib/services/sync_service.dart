import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

class SyncFolder {
  final String localPath;
  final String cloudPath;
  final bool autoSync;
  final bool includeSubfolders;
  final int syncIntervalMinutes;
  final int priority;
  final DateTime? lastSync;
  final int syncedFiles;
  final List<String> excludePatterns;

  SyncFolder({
    required this.localPath,
    required this.cloudPath,
    this.autoSync = false,
    this.includeSubfolders = false,
    this.syncIntervalMinutes = 30,
    this.priority = 0,
    this.lastSync,
    this.syncedFiles = 0,
    this.excludePatterns = const ['*.tmp', '*.temp', '.DS_Store', 'Thumbs.db'],
  });

  factory SyncFolder.fromJson(Map<String, dynamic> json) {
    return SyncFolder(
      localPath: json['localPath'] ?? '',
      cloudPath: json['cloudPath'] ?? '',
      autoSync: json['autoSync'] ?? false,
      includeSubfolders: json['includeSubfolders'] ?? false,
      syncIntervalMinutes: json['syncIntervalMinutes'] ?? 30,
      priority: json['priority'] ?? 0,
      lastSync: json['lastSync'] != null ? DateTime.parse(json['lastSync']) : null,
      syncedFiles: json['syncedFiles'] ?? 0,
      excludePatterns: List<String>.from(json['excludePatterns'] ?? []),
    );
  }

  Map<String, dynamic> toJson() => {
    'localPath': localPath,
    'cloudPath': cloudPath,
    'autoSync': autoSync,
    'includeSubfolders': includeSubfolders,
    'syncIntervalMinutes': syncIntervalMinutes,
    'priority': priority,
    'lastSync': lastSync?.toIso8601String(),
    'syncedFiles': syncedFiles,
    'excludePatterns': excludePatterns,
  };

  SyncFolder copyWith({
    String? localPath,
    String? cloudPath,
    bool? autoSync,
    bool? includeSubfolders,
    int? syncIntervalMinutes,
    int? priority,
    DateTime? lastSync,
    int? syncedFiles,
    List<String>? excludePatterns,
  }) {
    return SyncFolder(
      localPath: localPath ?? this.localPath,
      cloudPath: cloudPath ?? this.cloudPath,
      autoSync: autoSync ?? this.autoSync,
      includeSubfolders: includeSubfolders ?? this.includeSubfolders,
      syncIntervalMinutes: syncIntervalMinutes ?? this.syncIntervalMinutes,
      priority: priority ?? this.priority,
      lastSync: lastSync ?? this.lastSync,
      syncedFiles: syncedFiles ?? this.syncedFiles,
      excludePatterns: excludePatterns ?? this.excludePatterns,
    );
  }

  String get folderName => localPath.split(Platform.pathSeparator).last;
}

class SyncService {
  static const String _syncFoldersKey = 'discord_cloud_sync_folders';
  final List<SyncFolder> _syncFolders = [];
  final Map<String, StreamSubscription> _watchers = {};

  List<SyncFolder> get syncFolders => List.unmodifiable(_syncFolders);
  List<SyncFolder> get sortedByPriority => 
      List.from(_syncFolders)..sort((a, b) => b.priority.compareTo(a.priority));

  Future<void> init() async {
    await _loadSyncFolders();
  }

  Future<void> _loadSyncFolders() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_syncFoldersKey);
    if (json != null) {
      final List<dynamic> list = jsonDecode(json);
      _syncFolders.clear();
      _syncFolders.addAll(list.map((e) => SyncFolder.fromJson(e)));
    }
  }

  Future<void> _saveSyncFolders() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_syncFoldersKey, jsonEncode(_syncFolders.map((e) => e.toJson()).toList()));
  }

  Future<void> addSyncFolder(SyncFolder folder) async {
    if (_syncFolders.any((f) => f.localPath == folder.localPath)) {
      throw Exception('Folder already exists in sync list');
    }
    _syncFolders.add(folder);
    await _saveSyncFolders();
  }

  Future<void> removeSyncFolder(String localPath) async {
    _stopWatching(localPath);
    _syncFolders.removeWhere((f) => f.localPath == localPath);
    await _saveSyncFolders();
  }

  Future<void> updateSyncFolder(SyncFolder folder) async {
    final index = _syncFolders.indexWhere((f) => f.localPath == folder.localPath);
    if (index >= 0) {
      _syncFolders[index] = folder;
      await _saveSyncFolders();
    }
  }

  Future<void> setPriority(String localPath, int priority) async {
    final index = _syncFolders.indexWhere((f) => f.localPath == localPath);
    if (index >= 0) {
      _syncFolders[index] = _syncFolders[index].copyWith(priority: priority);
      await _saveSyncFolders();
    }
  }

  Future<void> reorderFolders(List<String> orderedPaths) async {
    for (int i = 0; i < orderedPaths.length; i++) {
      await setPriority(orderedPaths[i], orderedPaths.length - i);
    }
  }

  void startWatching(String localPath, Function(FileSystemEvent) onEvent) {
    _stopWatching(localPath);
    final dir = Directory(localPath);
    if (dir.existsSync()) {
      final folder = _syncFolders.firstWhere((f) => f.localPath == localPath);
      _watchers[localPath] = dir.watch(recursive: folder.includeSubfolders).listen(onEvent);
    }
  }

  void _stopWatching(String localPath) {
    _watchers[localPath]?.cancel();
    _watchers.remove(localPath);
  }

  void stopAllWatching() {
    for (final sub in _watchers.values) {
      sub.cancel();
    }
    _watchers.clear();
  }

  bool shouldExclude(String fileName, List<String> patterns) {
    for (final pattern in patterns) {
      if (pattern.startsWith('*.')) {
        if (fileName.endsWith(pattern.substring(1))) return true;
      } else if (fileName == pattern) {
        return true;
      }
    }
    return false;
  }
}
