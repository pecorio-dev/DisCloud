import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

enum SaveMode {
  redundant,  // Envoie a tous les webhooks (securite max)
  quick,      // Envoie a 1 seul webhook (rapide)
  balanced,   // Envoie a 2 webhooks
}

class WebhookInfo {
  final String url;
  final String name;
  final bool isActive;
  final DateTime addedAt;
  final int uploadCount;
  final int totalBytes;

  WebhookInfo({
    required this.url,
    required this.name,
    this.isActive = true,
    DateTime? addedAt,
    this.uploadCount = 0,
    this.totalBytes = 0,
  }) : addedAt = addedAt ?? DateTime.now();

  String get webhookId {
    final uri = Uri.parse(url);
    final parts = uri.pathSegments;
    return parts.length >= 2 ? parts[parts.length - 2] : '';
  }

  factory WebhookInfo.fromJson(Map<String, dynamic> json) {
    return WebhookInfo(
      url: json['url'] ?? '',
      name: json['name'] ?? 'Webhook',
      isActive: json['isActive'] ?? true,
      addedAt: json['addedAt'] != null ? DateTime.parse(json['addedAt']) : DateTime.now(),
      uploadCount: json['uploadCount'] ?? 0,
      totalBytes: json['totalBytes'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'url': url,
    'name': name,
    'isActive': isActive,
    'addedAt': addedAt.toIso8601String(),
    'uploadCount': uploadCount,
    'totalBytes': totalBytes,
  };

  WebhookInfo copyWith({
    String? url,
    String? name,
    bool? isActive,
    DateTime? addedAt,
    int? uploadCount,
    int? totalBytes,
  }) {
    return WebhookInfo(
      url: url ?? this.url,
      name: name ?? this.name,
      isActive: isActive ?? this.isActive,
      addedAt: addedAt ?? this.addedAt,
      uploadCount: uploadCount ?? this.uploadCount,
      totalBytes: totalBytes ?? this.totalBytes,
    );
  }
}

class WebhookManager {
  static const String _webhooksKey = 'discord_cloud_webhooks';
  static const String _saveModeKey = 'discord_cloud_save_mode';
  
  final List<WebhookInfo> _webhooks = [];
  SaveMode _saveMode = SaveMode.redundant;

  List<WebhookInfo> get webhooks => List.unmodifiable(_webhooks);
  List<WebhookInfo> get activeWebhooks => _webhooks.where((w) => w.isActive).toList();
  SaveMode get saveMode => _saveMode;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    
    final webhooksJson = prefs.getString(_webhooksKey);
    if (webhooksJson != null) {
      final List<dynamic> list = jsonDecode(webhooksJson);
      _webhooks.clear();
      _webhooks.addAll(list.map((e) => WebhookInfo.fromJson(e)));
    }
    
    final saveModeIndex = prefs.getInt(_saveModeKey) ?? 0;
    _saveMode = SaveMode.values[saveModeIndex.clamp(0, SaveMode.values.length - 1)];
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_webhooksKey, jsonEncode(_webhooks.map((w) => w.toJson()).toList()));
    await prefs.setInt(_saveModeKey, _saveMode.index);
  }

  Future<void> addWebhook(WebhookInfo webhook) async {
    if (_webhooks.any((w) => w.url == webhook.url)) {
      throw Exception('Webhook already exists');
    }
    _webhooks.add(webhook);
    await _save();
  }

  Future<void> removeWebhook(String url) async {
    _webhooks.removeWhere((w) => w.url == url);
    await _save();
  }

  Future<void> updateWebhook(WebhookInfo webhook) async {
    final index = _webhooks.indexWhere((w) => w.url == webhook.url);
    if (index >= 0) {
      _webhooks[index] = webhook;
      await _save();
    }
  }

  Future<void> toggleWebhook(String url, bool isActive) async {
    final index = _webhooks.indexWhere((w) => w.url == url);
    if (index >= 0) {
      _webhooks[index] = _webhooks[index].copyWith(isActive: isActive);
      await _save();
    }
  }

  Future<void> setSaveMode(SaveMode mode) async {
    _saveMode = mode;
    await _save();
  }

  List<WebhookInfo> getWebhooksForUpload() {
    final active = activeWebhooks;
    if (active.isEmpty) return [];
    
    switch (_saveMode) {
      case SaveMode.quick:
        return [active.first];
      case SaveMode.balanced:
        return active.take(2).toList();
      case SaveMode.redundant:
        return active;
    }
  }

  Future<void> incrementStats(String url, int bytes) async {
    final index = _webhooks.indexWhere((w) => w.url == url);
    if (index >= 0) {
      final w = _webhooks[index];
      _webhooks[index] = w.copyWith(
        uploadCount: w.uploadCount + 1,
        totalBytes: w.totalBytes + bytes,
      );
      await _save();
    }
  }
}
