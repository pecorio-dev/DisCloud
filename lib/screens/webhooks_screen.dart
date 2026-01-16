import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/cloud_provider.dart';
import '../models/cloud_file.dart';

class WebhooksScreen extends StatelessWidget {
  const WebhooksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Webhooks'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddWebhookDialog(context),
            tooltip: 'Add Webhook',
          ),
        ],
      ),
      body: Consumer<CloudProvider>(
        builder: (context, provider, _) {
          if (provider.webhooks.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.webhook, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  const Text('No webhooks added'),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => _showAddWebhookDialog(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Webhook'),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: provider.webhooks.length,
            itemBuilder: (context, index) {
              final webhook = provider.webhooks[index];
              final isSelected = webhook.id == provider.currentWebhookId;
              
              return _WebhookCard(
                webhook: webhook,
                isSelected: isSelected,
                onSelect: () => provider.selectWebhook(webhook.id),
                onRename: () => _showRenameDialog(context, provider, webhook),
                onDelete: () => _showDeleteDialog(context, provider, webhook),
                onViewFiles: () => _viewWebhookFiles(context, provider, webhook),
              );
            },
          );
        },
      ),
    );
  }

  void _showAddWebhookDialog(BuildContext context) {
    final urlController = TextEditingController();
    final nameController = TextEditingController();
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final provider = context.read<CloudProvider>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Webhook'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: urlController,
              decoration: const InputDecoration(
                labelText: 'Webhook URL',
                hintText: 'https://discord.com/api/webhooks/...',
                prefixIcon: Icon(Icons.link),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Name (optional)',
                hintText: 'My Cloud Storage',
                prefixIcon: Icon(Icons.label),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final url = urlController.text.trim();
              if (url.isEmpty) {
                scaffoldMessenger.showSnackBar(
                  const SnackBar(content: Text('Please enter a webhook URL'), backgroundColor: Colors.orange),
                );
                return;
              }
              if (!url.contains('discord.com/api/webhooks/')) {
                scaffoldMessenger.showSnackBar(
                  const SnackBar(content: Text('Invalid Discord webhook URL'), backgroundColor: Colors.red),
                );
                return;
              }
              
              Navigator.pop(ctx);
              scaffoldMessenger.showSnackBar(
                const SnackBar(content: Text('Adding webhook...'), duration: Duration(seconds: 10)),
              );
              
              final success = await provider.addWebhook(
                url,
                name: nameController.text.isEmpty ? null : nameController.text,
              );
              
              scaffoldMessenger.hideCurrentSnackBar();
              if (success) {
                scaffoldMessenger.showSnackBar(
                  const SnackBar(content: Text('Webhook added successfully!'), backgroundColor: Colors.green),
                );
              } else {
                scaffoldMessenger.showSnackBar(
                  SnackBar(
                    content: Text(provider.errorMessage ?? 'Failed to add webhook'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(BuildContext context, CloudProvider provider, WebhookInfo webhook) {
    final controller = TextEditingController(text: webhook.name);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Webhook'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                provider.renameWebhook(webhook.id, controller.text);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, CloudProvider provider, WebhookInfo webhook) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${webhook.name}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('This will remove the webhook from the app.'),
            const SizedBox(height: 8),
            Text(
              'Files on Discord will NOT be deleted.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              provider.removeWebhook(webhook.id);
              Navigator.pop(ctx);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _viewWebhookFiles(BuildContext context, CloudProvider provider, WebhookInfo webhook) {
    provider.selectWebhook(webhook.id);
    Navigator.pop(context);
  }
}

class _WebhookCard extends StatelessWidget {
  final WebhookInfo webhook;
  final bool isSelected;
  final VoidCallback onSelect;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onViewFiles;

  const _WebhookCard({
    required this.webhook,
    required this.isSelected,
    required this.onSelect,
    required this.onRename,
    required this.onDelete,
    required this.onViewFiles,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected 
            ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onViewFiles,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isSelected 
                          ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.webhook,
                      color: isSelected 
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey.shade600,
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
                            if (isSelected) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'Active',
                                  style: TextStyle(color: Colors.white, fontSize: 10),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'ID: ${webhook.id}',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      switch (value) {
                        case 'select': onSelect(); break;
                        case 'rename': onRename(); break;
                        case 'delete': onDelete(); break;
                      }
                    },
                    itemBuilder: (_) => [
                      if (!isSelected)
                        const PopupMenuItem(
                          value: 'select',
                          child: Row(children: [
                            Icon(Icons.check, size: 20),
                            SizedBox(width: 12),
                            Text('Select'),
                          ]),
                        ),
                      const PopupMenuItem(
                        value: 'rename',
                        child: Row(children: [
                          Icon(Icons.edit, size: 20),
                          SizedBox(width: 12),
                          Text('Rename'),
                        ]),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(children: [
                          Icon(Icons.delete, size: 20, color: Colors.red),
                          SizedBox(width: 12),
                          Text('Delete', style: TextStyle(color: Colors.red)),
                        ]),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _StatItem(icon: Icons.insert_drive_file, label: 'Files', value: '${webhook.fileCount}'),
                  _StatItem(icon: Icons.storage, label: 'Size', value: webhook.formattedSize),
                  _StatItem(
                    icon: Icons.calendar_today,
                    label: 'Added',
                    value: '${webhook.addedAt.day}/${webhook.addedAt.month}/${webhook.addedAt.year}',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onViewFiles,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('View Files'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatItem({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 4),
        Text(
          '$label: ',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
        ),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        ),
      ],
    );
  }
}
