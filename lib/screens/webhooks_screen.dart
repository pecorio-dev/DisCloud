import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/webhook_provider.dart';
import '../models/webhook_config.dart';

class WebhooksScreen extends StatefulWidget {
  const WebhooksScreen({super.key});

  @override
  State<WebhooksScreen> createState() => _WebhooksScreenState();
}

class _WebhooksScreenState extends State<WebhooksScreen> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Webhooks'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () => _showHelp(context),
            tooltip: 'Help',
          ),
        ],
      ),
      body: Consumer<WebhookProvider>(
        builder: (context, provider, _) {
          if (!provider.isInitialized) {
            return const Center(child: CircularProgressIndicator());
          }
          
          return Column(
            children: [
              _buildSaveModeSelector(context, provider, isDark),
              const Divider(height: 1),
              Expanded(
                child: provider.webhooks.isEmpty
                    ? _buildEmptyState()
                    : _buildWebhooksList(context, provider),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addWebhook(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Webhook'),
      ),
    );
  }

  Widget _buildSaveModeSelector(BuildContext context, WebhookProvider provider, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: isDark ? Colors.grey.shade900 : Colors.grey.shade50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              const Text(
                'Backup Mode',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Choose how many webhooks receive your files',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildModeCard(context, provider, SaveMode.quick, isDark)),
              const SizedBox(width: 8),
              Expanded(child: _buildModeCard(context, provider, SaveMode.balanced, isDark)),
              const SizedBox(width: 8),
              Expanded(child: _buildModeCard(context, provider, SaveMode.redundant, isDark)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModeCard(BuildContext context, WebhookProvider provider, SaveMode mode, bool isDark) {
    final isSelected = provider.saveMode == mode;
    
    IconData icon;
    String title;
    String subtitle;
    Color color;
    
    switch (mode) {
      case SaveMode.quick:
        icon = Icons.flash_on;
        title = 'Quick';
        subtitle = '1 server';
        color = Colors.orange;
        break;
      case SaveMode.balanced:
        icon = Icons.balance;
        title = 'Balanced';
        subtitle = '2 servers';
        color = Colors.blue;
        break;
      case SaveMode.redundant:
        icon = Icons.security;
        title = 'Secure';
        subtitle = 'All servers';
        color = Colors.green;
        break;
    }

    return GestureDetector(
      onTap: () => provider.setSaveMode(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected 
              ? color.withValues(alpha: isDark ? 0.2 : 0.1)
              : isDark ? Colors.grey.shade800 : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? color : Colors.grey, size: 28),
            const SizedBox(height: 6),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isSelected ? color : null,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.indigo.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.webhook, size: 64, color: Colors.indigo),
            ),
            const SizedBox(height: 24),
            const Text(
              'No Webhooks Yet',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Add Discord webhooks to store your files.\nMultiple webhooks = better backup!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _addWebhook(context),
              icon: const Icon(Icons.add),
              label: const Text('Add Your First Webhook'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebhooksList(BuildContext context, WebhookProvider provider) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: provider.webhooks.length,
      itemBuilder: (context, index) {
        final webhook = provider.webhooks[index];
        return _buildWebhookCard(context, provider, webhook, index);
      },
    );
  }

  Widget _buildWebhookCard(BuildContext context, WebhookProvider provider, WebhookInfo webhook, int index) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: webhook.isActive 
            ? BorderSide(color: Colors.green.withValues(alpha: 0.5), width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _editWebhook(context, provider, webhook),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: webhook.isActive 
                          ? Colors.green.withValues(alpha: 0.1)
                          : Colors.grey.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.webhook,
                      color: webhook.isActive ? Colors.green : Colors.grey,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              webhook.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: webhook.isActive ? Colors.green : Colors.grey,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                webhook.isActive ? 'Active' : 'Inactive',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'ID: ${webhook.webhookId}',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: webhook.isActive,
                    onChanged: (value) => provider.toggleWebhook(webhook.url, value),
                    activeColor: Colors.green,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStat(Icons.upload, '${webhook.uploadCount}', 'Uploads'),
                    Container(width: 1, height: 30, color: Colors.grey.shade400),
                    _buildStat(Icons.storage, _formatBytes(webhook.totalBytes), 'Data'),
                    Container(width: 1, height: 30, color: Colors.grey.shade400),
                    _buildStat(Icons.calendar_today, _formatDate(webhook.addedAt), 'Added'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _copyUrl(context, webhook),
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copy URL'),
                  ),
                  TextButton.icon(
                    onPressed: () => _deleteWebhook(context, provider, webhook),
                    icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                    label: const Text('Delete', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStat(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade600),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
      ],
    );
  }

  Future<void> _addWebhook(BuildContext context) async {
    final urlController = TextEditingController();
    final nameController = TextEditingController();
    
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.add_link, color: Colors.indigo),
            const SizedBox(width: 8),
            const Text('Add Webhook'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Name (optional)',
                  hintText: 'My Discord Server',
                  prefixIcon: Icon(Icons.label),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  labelText: 'Webhook URL',
                  hintText: 'https://discord.com/api/webhooks/...',
                  prefixIcon: Icon(Icons.link),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.blue, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Get webhook URL from Discord:\nServer Settings → Integrations → Webhooks',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (urlController.text.contains('discord.com/api/webhooks/')) {
                Navigator.pop(ctx, {
                  'url': urlController.text.trim(),
                  'name': nameController.text.trim(),
                });
              } else {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Invalid webhook URL'), backgroundColor: Colors.red),
                );
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result != null && result['url']!.isNotEmpty) {
      final provider = context.read<WebhookProvider>();
      try {
        await provider.addWebhook(WebhookInfo(
          url: result['url']!,
          name: result['name']!.isEmpty 
              ? 'Webhook ${provider.webhooks.length + 1}' 
              : result['name']!,
        ));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Webhook added!'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _editWebhook(BuildContext context, WebhookProvider provider, WebhookInfo webhook) async {
    final nameController = TextEditingController(text: webhook.name);
    
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Webhook'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Name',
            prefixIcon: Icon(Icons.label),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, nameController.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty) {
      await provider.updateWebhook(webhook.copyWith(name: newName));
    }
  }

  Future<void> _deleteWebhook(BuildContext context, WebhookProvider provider, WebhookInfo webhook) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Webhook'),
        content: Text('Remove "${webhook.name}"?\n\nFiles already uploaded will remain on Discord.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await provider.removeWebhook(webhook.url);
    }
  }

  void _copyUrl(BuildContext context, WebhookInfo webhook) {
    Clipboard.setData(ClipboardData(text: webhook.url));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('URL copied!')),
    );
  }

  void _showHelp(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.help, color: Colors.blue),
            const SizedBox(width: 8),
            const Text('How it works'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHelpItem('1.', 'Create Discord webhooks in different servers'),
              _buildHelpItem('2.', 'Add them here for redundant backup'),
              _buildHelpItem('3.', 'Files are uploaded to all active webhooks'),
              _buildHelpItem('4.', 'If one server is deleted, files remain on others'),
              const Divider(),
              const Text(
                'Backup Modes:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _buildHelpItem('Quick', 'Fast upload to 1 server (less safe)'),
              _buildHelpItem('Balanced', 'Upload to 2 servers (recommended)'),
              _buildHelpItem('Secure', 'Upload to ALL servers (safest)'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it!'),
          ),
        ],
      ),
    );
  }

  Widget _buildHelpItem(String number, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(number, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}';
  }
}
