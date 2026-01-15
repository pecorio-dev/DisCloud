import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'sync_service.dart';

class AutoSyncService extends ChangeNotifier {
  static final AutoSyncService _instance = AutoSyncService._internal();
  factory AutoSyncService() => _instance;
  AutoSyncService._internal();

  final SyncService _syncService = SyncService();
  Timer? _autoSyncTimer;
  final Map<String, StreamSubscription> _watchers = {};
  
  bool _isRunning = false;
  bool _isSyncing = false;
  String _status = 'Idle';
  DateTime? _lastSync;
  int _pendingChanges = 0;
  final List<String> _syncLog = [];

  bool get isRunning => _isRunning;
  bool get isSyncing => _isSyncing;
  String get status => _status;
  DateTime? get lastSync => _lastSync;
  int get pendingChanges => _pendingChanges;
  List<String> get syncLog => List.unmodifiable(_syncLog);
  List<SyncFolder> get syncFolders => _syncService.syncFolders;

  Future<void> init() async {
    await _syncService.init();
    await _loadLastSync();
    notifyListeners();
  }

  Future<void> _loadLastSync() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt('last_auto_sync');
    if (timestamp != null) {
      _lastSync = DateTime.fromMillisecondsSinceEpoch(timestamp);
    }
  }

  Future<void> _saveLastSync() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_auto_sync', DateTime.now().millisecondsSinceEpoch);
  }

  void start({int intervalMinutes = 30}) {
    if (_isRunning) return;
    
    _isRunning = true;
    _status = 'Running';
    _log('Auto-sync started (interval: $intervalMinutes min)');
    
    // Start file watchers
    _startWatchers();
    
    // Start periodic sync
    _autoSyncTimer = Timer.periodic(
      Duration(minutes: intervalMinutes),
      (_) => _performAutoSync(),
    );
    
    notifyListeners();
  }

  void stop() {
    _isRunning = false;
    _status = 'Stopped';
    _log('Auto-sync stopped');
    
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
    
    _stopWatchers();
    
    notifyListeners();
  }

  void _startWatchers() {
    for (final folder in _syncService.syncFolders) {
      if (folder.autoSync) {
        _watchFolder(folder);
      }
    }
  }

  void _stopWatchers() {
    for (final sub in _watchers.values) {
      sub.cancel();
    }
    _watchers.clear();
  }

  void _watchFolder(SyncFolder folder) {
    if (_watchers.containsKey(folder.localPath)) return;
    
    final dir = Directory(folder.localPath);
    if (!dir.existsSync()) return;
    
    _watchers[folder.localPath] = dir.watch(recursive: true).listen((event) {
      _onFileChanged(folder, event);
    });
    
    _log('Watching: ${folder.localPath}');
  }

  void _onFileChanged(SyncFolder folder, FileSystemEvent event) {
    String action;
    switch (event.type) {
      case FileSystemEvent.create:
        action = 'Created';
        break;
      case FileSystemEvent.modify:
        action = 'Modified';
        break;
      case FileSystemEvent.delete:
        action = 'Deleted';
        break;
      case FileSystemEvent.move:
        action = 'Moved';
        break;
      default:
        return;
    }
    
    final fileName = event.path.split(Platform.pathSeparator).last;
    
    // Ignore temp files
    if (fileName.startsWith('.') || 
        fileName.endsWith('.tmp') || 
        fileName.endsWith('.temp')) {
      return;
    }
    
    _pendingChanges++;
    _log('$action: $fileName');
    notifyListeners();
  }

  Future<void> _performAutoSync() async {
    if (_isSyncing) return;
    
    _isSyncing = true;
    _status = 'Syncing...';
    notifyListeners();
    
    try {
      for (final folder in _syncService.syncFolders) {
        if (folder.autoSync) {
          _log('Syncing: ${folder.localPath}');
          // Actual sync would happen here through the provider
          await Future.delayed(const Duration(seconds: 1)); // Placeholder
        }
      }
      
      _lastSync = DateTime.now();
      await _saveLastSync();
      _pendingChanges = 0;
      _status = 'Last sync: ${_formatTime(_lastSync!)}';
      _log('Sync complete');
    } catch (e) {
      _status = 'Sync failed: $e';
      _log('Error: $e');
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> syncNow() async {
    await _performAutoSync();
  }

  void _log(String message) {
    final time = DateTime.now();
    final logEntry = '[${_formatTime(time)}] $message';
    _syncLog.insert(0, logEntry);
    
    // Keep only last 100 entries
    if (_syncLog.length > 100) {
      _syncLog.removeRange(100, _syncLog.length);
    }
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }

  void clearLog() {
    _syncLog.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
