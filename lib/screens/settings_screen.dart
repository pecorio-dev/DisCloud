import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../providers/cloud_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Consumer<CloudProvider>(
        builder: (context, provider, _) {
          final settings = provider.settings;
          
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Connection Status
              Card(
                child: ListTile(
                  leading: Icon(
                    provider.isConnected ? Icons.cloud_done : Icons.cloud_off,
                    color: provider.isConnected ? Colors.green : Colors.red,
                  ),
                  title: Text(provider.isConnected ? 'Connected' : 'Disconnected'),
                  subtitle: provider.isConnected 
                      ? Text('${provider.totalFiles} files, ${provider.totalFolders} folders')
                      : const Text('Not connected to Discord'),
                  trailing: provider.isConnected
                      ? TextButton(
                          onPressed: () {
                            provider.disconnect();
                            Navigator.popUntil(context, (route) => route.isFirst);
                          },
                          child: const Text('Disconnect', style: TextStyle(color: Colors.red)),
                        )
                      : null,
                ),
              ),
              
              const SizedBox(height: 16),
              const Text('Display', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              
              // Theme
              Card(
                child: Consumer<ThemeProvider>(
                  builder: (context, themeProvider, _) {
                    return ListTile(
                      leading: Icon(themeProvider.isDark ? Icons.dark_mode : Icons.light_mode),
                      title: const Text('Theme'),
                      trailing: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'light', icon: Icon(Icons.light_mode, size: 16)),
                          ButtonSegment(value: 'system', icon: Icon(Icons.brightness_auto, size: 16)),
                          ButtonSegment(value: 'dark', icon: Icon(Icons.dark_mode, size: 16)),
                        ],
                        selected: {settings['theme'] ?? 'system'},
                        onSelectionChanged: (s) {
                          provider.updateSetting('theme', s.first);
                          themeProvider.setTheme(s.first);
                        },
                      ),
                    );
                  },
                ),
              ),
              
              const SizedBox(height: 16),
              const Text('Upload Settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              
              // Nitro
              Card(
                child: SwitchListTile(
                  secondary: Icon(
                    Icons.diamond,
                    color: settings['hasNitro'] == true ? Colors.purple : Colors.grey,
                  ),
                  title: const Text('Discord Nitro'),
                  subtitle: Text(settings['hasNitro'] == true 
                      ? 'Max chunk: 100 MB' 
                      : 'Max chunk: 10 MB'),
                  value: settings['hasNitro'] == true,
                  onChanged: (v) => provider.updateSetting('hasNitro', v),
                ),
              ),
              
              // Compression
              Card(
                child: SwitchListTile(
                  secondary: const Icon(Icons.compress),
                  title: const Text('Compression'),
                  subtitle: const Text('Compress files before upload'),
                  value: settings['compression'] != false,
                  onChanged: (v) => provider.updateSetting('compression', v),
                ),
              ),
              
              const SizedBox(height: 16),
              const Text('Storage Info', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _InfoRow(icon: Icons.folder, label: 'Folders', value: '${provider.totalFolders}'),
                      _InfoRow(icon: Icons.insert_drive_file, label: 'Files', value: '${provider.totalFiles}'),
                      _InfoRow(icon: Icons.storage, label: 'Total Size', value: _formatSize(provider.totalSize)),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              const Text('About', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('DisCloud v2.0', style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: 8),
                      Text('Unlimited cloud storage using Discord webhooks.'),
                      SizedBox(height: 8),
                      Text(
                        'All data is stored on Discord servers. '
                        'No local storage is used except for temporary cache.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
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

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey),
          const SizedBox(width: 12),
          Text(label),
          const Spacer(),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
