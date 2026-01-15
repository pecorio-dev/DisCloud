import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../models/webhook_config.dart';
import 'discord_service.dart';

/// Service pour gerer l'upload/download sur plusieurs webhooks
class MultiWebhookService {
  final WebhookManager _manager;
  final Map<String, DiscordService> _services = {};
  
  MultiWebhookService(this._manager);
  
  /// Initialise les services Discord pour chaque webhook
  void _ensureServices() {
    for (final webhook in _manager.activeWebhooks) {
      if (!_services.containsKey(webhook.url)) {
        _services[webhook.url] = DiscordService(webhookUrl: webhook.url);
      }
    }
    // Nettoyer les anciens services
    _services.removeWhere((url, _) => 
      !_manager.webhooks.any((w) => w.url == url));
  }
  
  /// Upload un fichier vers les webhooks selon le mode de sauvegarde
  /// Retourne une map: webhookUrl -> List<attachmentUrls>
  Future<Map<String, List<String>>> uploadFile(
    Uint8List fileData,
    String fileName, {
    Function(double)? onProgress,
  }) async {
    _ensureServices();
    
    final webhooksToUse = _manager.getWebhooksForUpload();
    if (webhooksToUse.isEmpty) {
      throw Exception('No active webhooks available');
    }
    
    final Map<String, List<String>> results = {};
    final errors = <String>[];
    
    for (int i = 0; i < webhooksToUse.length; i++) {
      final webhook = webhooksToUse[i];
      final service = _services[webhook.url];
      
      if (service == null) continue;
      
      try {
        final urls = await service.uploadFile(
          fileData,
          fileName,
          onProgress: onProgress != null ? (p) {
            // Progress global: webhook actuel + progress dans ce webhook
            final globalProgress = (i + p) / webhooksToUse.length;
            onProgress(globalProgress);
          } : null,
        );
        
        results[webhook.url] = urls;
        
        // Mettre a jour les stats
        await _manager.incrementStats(webhook.url, fileData.length);
      } catch (e) {
        errors.add('${webhook.name}: $e');
        // Continue avec les autres webhooks
      }
    }
    
    if (results.isEmpty) {
      throw Exception('Failed to upload to any webhook: ${errors.join(', ')}');
    }
    
    return results;
  }
  
  /// Telecharge un fichier depuis les webhooks disponibles
  /// Essaie chaque webhook jusqu'a reussir
  Future<Uint8List> downloadFile(
    Map<String, List<String>> webhookUrls, {
    Function(double)? onProgress,
  }) async {
    _ensureServices();
    
    // Trier les webhooks par priorite (actifs d'abord)
    final activeUrls = _manager.activeWebhooks.map((w) => w.url).toSet();
    final sortedEntries = webhookUrls.entries.toList()
      ..sort((a, b) {
        final aActive = activeUrls.contains(a.key) ? 0 : 1;
        final bActive = activeUrls.contains(b.key) ? 0 : 1;
        return aActive.compareTo(bActive);
      });
    
    Exception? lastError;
    
    for (final entry in sortedEntries) {
      // Creer un service temporaire si necessaire
      var service = _services[entry.key];
      service ??= DiscordService(webhookUrl: entry.key);
      
      try {
        final data = await service.downloadFile(
          entry.value,
          onProgress: onProgress,
        );
        return data;
      } catch (e) {
        lastError = Exception('Download from ${entry.key} failed: $e');
        // Continuer avec le prochain webhook
      }
    }
    
    throw lastError ?? Exception('No URLs available to download');
  }
  
  /// Verifie si un fichier est disponible sur au moins un webhook
  Future<Map<String, bool>> checkAvailability(
    Map<String, List<String>> webhookUrls,
  ) async {
    final results = <String, bool>{};
    final dio = Dio();
    
    for (final entry in webhookUrls.entries) {
      if (entry.value.isEmpty) {
        results[entry.key] = false;
        continue;
      }
      
      try {
        // Verifier juste la premiere URL (HEAD request)
        final response = await dio.head(entry.value.first);
        results[entry.key] = response.statusCode == 200;
      } catch (e) {
        results[entry.key] = false;
      }
    }
    
    return results;
  }
  
  /// Valide tous les webhooks et retourne leur status
  Future<Map<String, bool>> validateAllWebhooks() async {
    _ensureServices();
    
    final results = <String, bool>{};
    
    for (final webhook in _manager.webhooks) {
      final service = _services[webhook.url] ?? 
                      DiscordService(webhookUrl: webhook.url);
      try {
        results[webhook.url] = await service.validateWebhook();
      } catch (e) {
        results[webhook.url] = false;
      }
    }
    
    return results;
  }
}
