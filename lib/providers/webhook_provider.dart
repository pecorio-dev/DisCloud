import 'package:flutter/foundation.dart';
import '../models/webhook_config.dart';

class WebhookProvider extends ChangeNotifier {
  final WebhookManager _manager = WebhookManager();
  bool _isInitialized = false;

  WebhookManager get manager => _manager;
  bool get isInitialized => _isInitialized;
  List<WebhookInfo> get webhooks => _manager.webhooks;
  List<WebhookInfo> get activeWebhooks => _manager.activeWebhooks;
  SaveMode get saveMode => _manager.saveMode;
  bool get hasWebhooks => _manager.webhooks.isNotEmpty;

  Future<void> init() async {
    if (_isInitialized) return;
    await _manager.init();
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> addWebhook(WebhookInfo webhook) async {
    await _manager.addWebhook(webhook);
    notifyListeners();
  }

  Future<void> removeWebhook(String url) async {
    await _manager.removeWebhook(url);
    notifyListeners();
  }

  Future<void> updateWebhook(WebhookInfo webhook) async {
    await _manager.updateWebhook(webhook);
    notifyListeners();
  }

  Future<void> toggleWebhook(String url, bool isActive) async {
    await _manager.toggleWebhook(url, isActive);
    notifyListeners();
  }

  Future<void> setSaveMode(SaveMode mode) async {
    await _manager.setSaveMode(mode);
    notifyListeners();
  }

  Future<void> incrementStats(String url, int bytes) async {
    await _manager.incrementStats(url, bytes);
    notifyListeners();
  }

  String exportConfig() {
    // Export all webhooks as JSON for backup/transfer
    final data = webhooks.map((w) => w.toJson()).toList();
    return data.toString();
  }

  Future<void> importConfig(List<Map<String, dynamic>> configs) async {
    for (final config in configs) {
      try {
        await addWebhook(WebhookInfo.fromJson(config));
      } catch (e) {
        // Skip duplicates
      }
    }
  }
}
