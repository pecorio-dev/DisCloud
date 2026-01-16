import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../providers/cloud_provider.dart';
import '../models/upload_options.dart';
import 'upload_options_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        elevation: 0,
      ),
      body: Consumer<CloudProvider>(
        builder: (context, provider, _) {
          final settings = provider.settings;
          
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Connection Status
              _buildSection(
                context,
                'Connection',
                [
                  Card(
                    child: ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: provider.isConnected ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          provider.isConnected ? Icons.cloud_done : Icons.cloud_off,
                          color: provider.isConnected ? Colors.green : Colors.red,
                        ),
                      ),
                      title: Text(provider.isConnected ? 'Connected' : 'Disconnected'),
                      subtitle: provider.isConnected 
                          ? Text('${provider.totalFiles} files, ${provider.totalFolders} folders')
                          : const Text('Not connected to Discord'),
                      trailing: provider.webhooks.isNotEmpty
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text('${provider.webhooks.length}', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                            )
                          : null,
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 24),
              
              // Theme
              _buildSection(
                context,
                'Appearance',
                [
                  Consumer<ThemeProvider>(
                    builder: (context, themeProvider, _) {
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.palette, color: Theme.of(context).colorScheme.primary),
                                  const SizedBox(width: 12),
                                  const Text('Theme', style: TextStyle(fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  _ThemeButton(
                                    icon: Icons.light_mode,
                                    label: 'Light',
                                    isSelected: themeProvider.isLight,
                                    onTap: () {
                                      provider.updateSetting('theme', 'light');
                                      themeProvider.setTheme('light');
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  _ThemeButton(
                                    icon: Icons.brightness_auto,
                                    label: 'Auto',
                                    isSelected: themeProvider.isSystem,
                                    onTap: () {
                                      provider.updateSetting('theme', 'system');
                                      themeProvider.setTheme('system');
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  _ThemeButton(
                                    icon: Icons.dark_mode,
                                    label: 'Dark',
                                    isSelected: themeProvider.isDark,
                                    onTap: () {
                                      provider.updateSetting('theme', 'dark');
                                      themeProvider.setTheme('dark');
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
              
              const SizedBox(height: 24),
              
              // Upload Settings
              _buildSection(
                context,
                'Upload Settings',
                [
                  Card(
                    child: Column(
                      children: [
                        SwitchListTile(
                          secondary: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: settings['hasNitro'] == true ? Colors.purple.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.diamond, color: settings['hasNitro'] == true ? Colors.purple : Colors.grey),
                          ),
                          title: const Text('Discord Nitro'),
                          subtitle: Text(settings['hasNitro'] == true ? 'Max chunk: 100 MB' : 'Max chunk: 10 MB'),
                          value: settings['hasNitro'] == true,
                          onChanged: (v) => provider.updateSetting('hasNitro', v),
                        ),
                        const Divider(height: 1),
                        SwitchListTile(
                          secondary: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.compress, color: Colors.blue),
                          ),
                          title: const Text('Compression'),
                          subtitle: const Text('Compress files before upload'),
                          value: settings['compression'] != false,
                          onChanged: (v) => provider.updateSetting('compression', v),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.tune, color: Colors.orange),
                          ),
                          title: const Text('Advanced Options'),
                          subtitle: const Text('Encryption, obfuscation, etc.'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => UploadOptionsScreen(
                                  options: provider.uploadOptions,
                                  onSave: (options) => provider.setUploadOptions(options),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 24),
              
              // Storage Info
              _buildSection(
                context,
                'Storage',
                [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _StorageStat(icon: Icons.folder, label: 'Folders', value: '${provider.totalFolders}', color: Colors.amber),
                                const SizedBox(width: 12),
                                _StorageStat(icon: Icons.insert_drive_file, label: 'Files', value: '${provider.totalFiles}', color: Colors.blue),
                                const SizedBox(width: 12),
                                _StorageStat(icon: Icons.storage, label: 'Size', value: _formatSize(provider.totalSize), color: Colors.green),
                              ],
                            ),
                          ),
                          if (provider.webhooks.length > 1) ...[
                            const Divider(height: 24),
                            ...provider.webhooks.map((webhook) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  const Icon(Icons.webhook, size: 16, color: Colors.grey),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(webhook.name, style: const TextStyle(fontSize: 13))),
                                  Text('${webhook.fileCount} files', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                  const SizedBox(width: 8),
                                  Text(webhook.formattedSize, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            )),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 24),
              
              // Encryption Key
              _buildSection(
                context,
                'Security',
                [
                  Card(
                    child: ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.key, color: Colors.red),
                      ),
                      title: const Text('Encryption Key'),
                      subtitle: Text(provider.encryptionKey != null ? 'Key set' : 'No key set'),
                      trailing: TextButton(
                        onPressed: () => _showEncryptionKeyDialog(context, provider),
                        child: Text(provider.encryptionKey != null ? 'Change' : 'Set'),
                      ),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 24),
              
              // About
              _buildSection(
                context,
                'About',
                [
                  Card(
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
                                  color: Theme.of(context).colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.asset('assets/logo.png', fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(Icons.cloud, color: Theme.of(context).colorScheme.primary)),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('DisCloud', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                                  Text('Version 2.5', style: TextStyle(color: Colors.grey.shade600)),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const Text('Unlimited cloud storage using Discord webhooks.'),
                          const SizedBox(height: 8),
                          Text(
                            'All data is stored on Discord servers. Your webhook URLs are stored locally for connection.',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSection(BuildContext context, String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: 1,
            ),
          ),
        ),
        ...children,
      ],
    );
  }

  void _showEncryptionKeyDialog(BuildContext context, CloudProvider provider) {
    final controller = TextEditingController(text: provider.encryptionKey ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Encryption Key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('This key will be used to encrypt and decrypt your files.', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Encryption Key',
                hintText: 'Enter a strong password',
                prefixIcon: Icon(Icons.key),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          if (provider.encryptionKey != null)
            TextButton(
              onPressed: () {
                provider.setEncryptionKey(null);
                Navigator.pop(ctx);
              },
              child: const Text('Remove', style: TextStyle(color: Colors.red)),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              provider.setEncryptionKey(controller.text.isNotEmpty ? controller.text : null);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}

class _ThemeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemeButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected 
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected 
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected 
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected 
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StorageStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StorageStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 90,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          FittedBox(child: Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}
