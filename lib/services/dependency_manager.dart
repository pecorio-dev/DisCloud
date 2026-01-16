import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum DependencyStatus { notInstalled, installed, updating, error }

class DependencyInfo {
  final String name;
  final String? version;
  final String? latestVersion;
  final DependencyStatus status;
  final String? path;
  final DateTime? lastChecked;
  final String? error;

  DependencyInfo({
    required this.name,
    this.version,
    this.latestVersion,
    this.status = DependencyStatus.notInstalled,
    this.path,
    this.lastChecked,
    this.error,
  });

  bool get needsUpdate => 
      status == DependencyStatus.installed && 
      latestVersion != null && 
      version != latestVersion;

  DependencyInfo copyWith({
    String? version,
    String? latestVersion,
    DependencyStatus? status,
    String? path,
    DateTime? lastChecked,
    String? error,
  }) {
    return DependencyInfo(
      name: name,
      version: version ?? this.version,
      latestVersion: latestVersion ?? this.latestVersion,
      status: status ?? this.status,
      path: path ?? this.path,
      lastChecked: lastChecked ?? this.lastChecked,
      error: error,
    );
  }
}

/// Gestionnaire automatique des dependances (aria2, yt-dlp)
class DependencyManager extends ChangeNotifier {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(minutes: 10),
    headers: {
      'User-Agent': 'DisCloud/2.5 (Windows)',
    },
  ));

  DependencyInfo _aria2 = DependencyInfo(name: 'aria2');
  DependencyInfo _ytDlp = DependencyInfo(name: 'yt-dlp');
  
  String? _binDir;
  bool _isInitialized = false;

  DependencyInfo get aria2 => _aria2;
  DependencyInfo get ytDlp => _ytDlp;
  bool get isInitialized => _isInitialized;
  
  String? get aria2Path => _aria2.path;
  String? get ytDlpPath => _ytDlp.path;

  /// Initialise le gestionnaire
  Future<void> init() async {
    if (_isInitialized) return;

    final appDir = await getApplicationSupportDirectory();
    _binDir = '${appDir.path}${Platform.pathSeparator}bin';
    
    // Creer le dossier bin si necessaire
    final binDirectory = Directory(_binDir!);
    if (!await binDirectory.exists()) {
      await binDirectory.create(recursive: true);
    }

    // Charger l'etat sauvegarde
    await _loadState();
    
    // Verifier les installations existantes
    await checkAll();
    
    _isInitialized = true;
    notifyListeners();
  }

  /// Verifie toutes les dependances
  Future<void> checkAll() async {
    await Future.wait([
      checkAria2(),
      checkYtDlp(),
    ]);
  }

  /// Verifie aria2
  Future<void> checkAria2() async {
    try {
      // Verifier si aria2c existe localement
      final localPath = '$_binDir${Platform.pathSeparator}aria2c.exe';
      final localFile = File(localPath);
      
      String? installedVersion;
      String? execPath;
      
      if (await localFile.exists()) {
        execPath = localPath;
        installedVersion = await _getAria2Version(localPath);
      } else {
        // Verifier dans le PATH systeme
        try {
          final result = await Process.run('aria2c', ['--version']);
          if (result.exitCode == 0) {
            execPath = 'aria2c';
            installedVersion = _parseAria2Version(result.stdout.toString());
          }
        } catch (_) {}
      }

      // Recuperer la derniere version
      final latestVersion = await _getLatestAria2Version();

      _aria2 = _aria2.copyWith(
        version: installedVersion,
        latestVersion: latestVersion,
        status: installedVersion != null ? DependencyStatus.installed : DependencyStatus.notInstalled,
        path: execPath,
        lastChecked: DateTime.now(),
      );
      
      await _saveState();
      notifyListeners();
    } catch (e) {
      _aria2 = _aria2.copyWith(
        status: DependencyStatus.error,
        error: e.toString(),
      );
      notifyListeners();
    }
  }

  /// Verifie yt-dlp
  Future<void> checkYtDlp() async {
    try {
      final localPath = '$_binDir${Platform.pathSeparator}yt-dlp.exe';
      final localFile = File(localPath);
      
      String? installedVersion;
      String? execPath;
      
      if (await localFile.exists()) {
        execPath = localPath;
        installedVersion = await _getYtDlpVersion(localPath);
      } else {
        // Verifier dans le PATH
        try {
          final result = await Process.run('yt-dlp', ['--version']);
          if (result.exitCode == 0) {
            execPath = 'yt-dlp';
            installedVersion = result.stdout.toString().trim();
          }
        } catch (_) {}
      }

      final latestVersion = await _getLatestYtDlpVersion();

      _ytDlp = _ytDlp.copyWith(
        version: installedVersion,
        latestVersion: latestVersion,
        status: installedVersion != null ? DependencyStatus.installed : DependencyStatus.notInstalled,
        path: execPath,
        lastChecked: DateTime.now(),
      );
      
      await _saveState();
      notifyListeners();
    } catch (e) {
      _ytDlp = _ytDlp.copyWith(
        status: DependencyStatus.error,
        error: e.toString(),
      );
      notifyListeners();
    }
  }

  /// Installe ou met a jour aria2
  Future<bool> installAria2({Function(double)? onProgress}) async {
    try {
      _aria2 = _aria2.copyWith(status: DependencyStatus.updating);
      notifyListeners();

      // Trouver la derniere release
      final response = await _dio.get(
        'https://api.github.com/repos/aria2/aria2/releases/latest',
      );
      
      final assets = response.data['assets'] as List;
      final windowsAsset = assets.firstWhere(
        (a) => a['name'].toString().contains('win-64bit') && a['name'].toString().endsWith('.zip'),
        orElse: () => null,
      );

      if (windowsAsset == null) {
        throw Exception('No Windows build found');
      }

      final downloadUrl = windowsAsset['browser_download_url'];
      final zipPath = '$_binDir${Platform.pathSeparator}aria2.zip';
      
      // Telecharger
      await _dio.download(
        downloadUrl,
        zipPath,
        onReceiveProgress: (received, total) {
          if (total > 0) onProgress?.call(received / total * 0.8);
        },
      );

      onProgress?.call(0.85);

      // Extraire
      final zipFile = File(zipPath);
      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      
      for (final file in archive) {
        if (file.name.endsWith('aria2c.exe')) {
          final outFile = File('$_binDir${Platform.pathSeparator}aria2c.exe');
          await outFile.writeAsBytes(file.content as List<int>);
          break;
        }
      }

      // Nettoyer
      await zipFile.delete();
      
      onProgress?.call(1.0);

      // Verifier l'installation
      await checkAria2();
      
      return _aria2.status == DependencyStatus.installed;
    } catch (e) {
      _aria2 = _aria2.copyWith(
        status: DependencyStatus.error,
        error: e.toString(),
      );
      notifyListeners();
      return false;
    }
  }

  /// Installe ou met a jour yt-dlp
  Future<bool> installYtDlp({Function(double)? onProgress}) async {
    try {
      _ytDlp = _ytDlp.copyWith(status: DependencyStatus.updating);
      notifyListeners();

      const downloadUrl = 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe';
      final exePath = '$_binDir${Platform.pathSeparator}yt-dlp.exe';
      
      await _dio.download(
        downloadUrl,
        exePath,
        onReceiveProgress: (received, total) {
          if (total > 0) onProgress?.call(received / total);
        },
      );

      // Verifier l'installation
      await checkYtDlp();
      
      return _ytDlp.status == DependencyStatus.installed;
    } catch (e) {
      _ytDlp = _ytDlp.copyWith(
        status: DependencyStatus.error,
        error: e.toString(),
      );
      notifyListeners();
      return false;
    }
  }

  /// Installe toutes les dependances manquantes
  Future<void> installAll({Function(String, double)? onProgress}) async {
    if (_aria2.status != DependencyStatus.installed) {
      await installAria2(onProgress: (p) => onProgress?.call('aria2', p));
    }
    if (_ytDlp.status != DependencyStatus.installed) {
      await installYtDlp(onProgress: (p) => onProgress?.call('yt-dlp', p));
    }
  }

  /// Met a jour toutes les dependances
  Future<void> updateAll({Function(String, double)? onProgress}) async {
    if (_aria2.needsUpdate) {
      await installAria2(onProgress: (p) => onProgress?.call('aria2', p));
    }
    if (_ytDlp.needsUpdate) {
      await installYtDlp(onProgress: (p) => onProgress?.call('yt-dlp', p));
    }
  }

  // Helpers
  Future<String?> _getAria2Version(String path) async {
    try {
      final result = await Process.run(path, ['--version']);
      if (result.exitCode == 0) {
        return _parseAria2Version(result.stdout.toString());
      }
    } catch (_) {}
    return null;
  }

  String? _parseAria2Version(String output) {
    // "aria2 version 1.37.0"
    final match = RegExp(r'aria2 version (\d+\.\d+\.\d+)').firstMatch(output);
    return match?.group(1);
  }

  Future<String?> _getYtDlpVersion(String path) async {
    try {
      final result = await Process.run(path, ['--version']);
      if (result.exitCode == 0) {
        return result.stdout.toString().trim();
      }
    } catch (_) {}
    return null;
  }

  Future<String?> _getLatestAria2Version() async {
    try {
      final response = await _dio.get(
        'https://api.github.com/repos/aria2/aria2/releases/latest',
      );
      final tagName = response.data['tag_name'] as String;
      return tagName.replaceFirst('release-', '');
    } catch (_) {
      return null;
    }
  }

  Future<String?> _getLatestYtDlpVersion() async {
    try {
      final response = await _dio.get(
        'https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest',
      );
      return response.data['tag_name'] as String;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final aria2Data = prefs.getString('dep_aria2');
      final ytdlpData = prefs.getString('dep_ytdlp');
      
      if (aria2Data != null) {
        final json = jsonDecode(aria2Data);
        _aria2 = DependencyInfo(
          name: 'aria2',
          version: json['version'],
          latestVersion: json['latestVersion'],
          path: json['path'],
          lastChecked: json['lastChecked'] != null ? DateTime.parse(json['lastChecked']) : null,
        );
      }
      
      if (ytdlpData != null) {
        final json = jsonDecode(ytdlpData);
        _ytDlp = DependencyInfo(
          name: 'yt-dlp',
          version: json['version'],
          latestVersion: json['latestVersion'],
          path: json['path'],
          lastChecked: json['lastChecked'] != null ? DateTime.parse(json['lastChecked']) : null,
        );
      }
    } catch (_) {}
  }

  Future<void> _saveState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      await prefs.setString('dep_aria2', jsonEncode({
        'version': _aria2.version,
        'latestVersion': _aria2.latestVersion,
        'path': _aria2.path,
        'lastChecked': _aria2.lastChecked?.toIso8601String(),
      }));
      
      await prefs.setString('dep_ytdlp', jsonEncode({
        'version': _ytDlp.version,
        'latestVersion': _ytDlp.latestVersion,
        'path': _ytDlp.path,
        'lastChecked': _ytDlp.lastChecked?.toIso8601String(),
      }));
    } catch (_) {}
  }
}
