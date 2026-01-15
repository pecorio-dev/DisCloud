import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../services/encryption_service.dart';
import '../services/bandwidth_service.dart';
import '../providers/theme_provider.dart';
import '../providers/cloud_provider.dart';

class AppSettings {
  bool hasNitro;
  bool enableCompression;
  int compressionLevel;
  bool autoSync;
  int autoSyncInterval;
  String theme;
  bool showHiddenFiles;
  SecurityMode securityMode;
  bool computeHashes;
  bool verifyOnDownload;

  AppSettings({
    this.hasNitro = false,
    this.enableCompression = true,
    this.compressionLevel = 6,
    this.autoSync = false,
    this.autoSyncInterval = 30,
    this.theme = 'system',
    this.showHiddenFiles = false,
    this.securityMode = SecurityMode.standard,
    this.computeHashes = true,
    this.verifyOnDownload = true,
  });

  int get maxChunkSize => hasNitro ? 95 * 1024 * 1024 : 9 * 1024 * 1024;
  String get maxChunkSizeFormatted => hasNitro ? '95 MB' : '9 MB';

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasNitro', hasNitro);
    await prefs.setBool('enableCompression', enableCompression);
    await prefs.setInt('compressionLevel', compressionLevel);
    await prefs.setBool('autoSync', autoSync);
    await prefs.setInt('autoSyncInterval', autoSyncInterval);
    await prefs.setString('theme', theme);
    await prefs.setBool('showHiddenFiles', showHiddenFiles);
    await prefs.setInt('securityMode', securityMode.index);
    await prefs.setBool('computeHashes', computeHashes);
    await prefs.setBool('verifyOnDownload', verifyOnDownload);
  }

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      hasNitro: prefs.getBool('hasNitro') ?? false,
      enableCompression: prefs.getBool('enableCompression') ?? true,
      compressionLevel: prefs.getInt('compressionLevel') ?? 6,
      autoSync: prefs.getBool('autoSync') ?? false,
      autoSyncInterval: prefs.getInt('autoSyncInterval') ?? 30,
      theme: prefs.getString('theme') ?? 'system',
      showHiddenFiles: prefs.getBool('showHiddenFiles') ?? false,
      securityMode: SecurityMode.values[(prefs.getInt('securityMode') ?? 0).clamp(0, 2)],
      computeHashes: prefs.getBool('computeHashes') ?? true,
      verifyOnDownload: prefs.getBool('verifyOnDownload') ?? true,
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  AppSettings? _settings;
  bool _isLoading = true;
  final BandwidthService _bandwidthService = BandwidthService();
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await AppSettings.load();
    await _bandwidthService.init();
    setState(() {
      _settings = settings;
      _isLoading = false;
    });
  }

  Future<void> _testSpeed() async {
    setState(() => _isTesting = true);
    final speed = await _bandwidthService.testConnectionSpeed();
    setState(() => _isTesting = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Speed: ${speed.toStringAsFixed(2)} MB/s')),
      );
    }
  }

  Future<void> _setAuto50() async {
    setState(() => _isTesting = true);
    await _bandwidthService.setAuto50Percent();
    setState(() => _isTesting = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Limit set to ${_bandwidthService.config.uploadLimitMBps.toStringAsFixed(2)} MB/s (50%)')),
      );
    }
  }

  Future<void> _saveSettings() async {
    await _settings?.save();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved'), backgroundColor: Colors.green),
      );
    }
  }

  Future<void> _exportIndex() async {
    final provider = context.read<CloudProvider>();
    final success = await provider.exportCloudIndex();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Index exported to Discord!' : 'Export failed'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  Future<void> _importIndex() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import Index'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Paste the JSON from Discord:'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 8,
                decoration: const InputDecoration(
                  hintText: '{"marker": "📁 DISCLOUD_INDEX_V1", ...}',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Import'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      final provider = context.read<CloudProvider>();
      final success = await provider.importCloudIndex(result);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Index imported!' : 'Import failed'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    }
  }

  // Helper for help icons
  Widget _help(String title, String content) {
    return IconButton(
      icon: Icon(Icons.help_outline, size: 18, color: Colors.grey.shade500),
      onPressed: () => showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(children: [
            const Icon(Icons.help, color: Colors.blue),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 16))),
          ]),
          content: SingleChildScrollView(child: Text(content)),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      ),
      tooltip: 'Help',
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Settings'),
            _help('Settings', 
              'Configure how Discord Cloud works.\n\n'
              'Changes are saved when you tap the save icon.\n\n'
              'Some settings affect upload speed and file sizes.'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveSettings,
            tooltip: 'Save',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _buildSection('Discord Account', Icons.discord, [
                  _buildSettingTile(
                    icon: Icons.diamond,
                    iconColor: _settings!.hasNitro ? Colors.purple : Colors.grey,
                    title: 'Discord Nitro',
                    subtitle: _settings!.hasNitro ? 'Max: 100 MB/chunk' : 'Max: 10 MB/chunk',
                    trailing: Switch(
                      value: _settings!.hasNitro,
                      onChanged: (v) => setState(() => _settings!.hasNitro = v),
                    ),
                    helpTitle: 'Discord Nitro',
                    helpText: 'Enable this if you have Discord Nitro subscription.\n\n'
                        'With Nitro: Files up to 100MB can be uploaded in one piece.\n'
                        'Without Nitro: Files are split into 10MB chunks.\n\n'
                        'Larger chunks = faster uploads for big files.',
                  ),
                ]),
                
                _buildSection('Compression', Icons.compress, [
                  _buildSettingTile(
                    icon: Icons.compress,
                    title: 'Enable Compression',
                    subtitle: 'Compress files before upload',
                    trailing: Switch(
                      value: _settings!.enableCompression,
                      onChanged: (v) => setState(() => _settings!.enableCompression = v),
                    ),
                    helpTitle: 'Compression',
                    helpText: 'Files are compressed using gzip before upload.\n\n'
                        'Benefits:\n'
                        '- Smaller file sizes (faster upload)\n'
                        '- Less Discord storage used\n\n'
                        'Note: Already compressed files (ZIP, JPG, MP3) won\'t shrink much.',
                  ),
                  if (_settings!.enableCompression)
                    _buildSettingTile(
                      icon: Icons.speed,
                      title: 'Compression Level',
                      subtitle: 'Higher = smaller files, slower',
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${_settings!.compressionLevel}'),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 120,
                            child: Slider(
                              value: _settings!.compressionLevel.toDouble(),
                              min: 1, max: 9, divisions: 8,
                              onChanged: (v) => setState(() => _settings!.compressionLevel = v.round()),
                            ),
                          ),
                        ],
                      ),
                      helpTitle: 'Compression Level',
                      helpText: 'Level 1-3: Fast compression, larger files\n'
                          'Level 4-6: Balanced (recommended)\n'
                          'Level 7-9: Maximum compression, slower\n\n'
                          'For most users, level 6 is ideal.',
                    ),
                ]),
                
                _buildSection('Security', Icons.security, [
                  _buildSettingTile(
                    icon: _settings!.securityMode == SecurityMode.encrypted ? Icons.lock : Icons.lock_open,
                    iconColor: _settings!.securityMode == SecurityMode.encrypted ? Colors.red : Colors.grey,
                    title: 'Security Mode',
                    subtitle: _settings!.securityMode.description,
                    trailing: DropdownButton<SecurityMode>(
                      value: _settings!.securityMode,
                      underline: const SizedBox(),
                      items: SecurityMode.values.map((m) => 
                        DropdownMenuItem(value: m, child: Text(m.displayName))).toList(),
                      onChanged: (v) { if (v != null) setState(() => _settings!.securityMode = v); },
                    ),
                    helpTitle: 'Security Mode',
                    helpText: 'Standard: Files uploaded as-is\n\n'
                        'Obfuscated: File headers are modified to prevent Discord from scanning content\n\n'
                        'Encrypted: Files are encrypted with a key (most secure)\n\n'
                        'Warning: If you lose your encryption key, files cannot be recovered!',
                  ),
                  _buildSettingTile(
                    icon: Icons.fingerprint,
                    title: 'Compute Hashes',
                    subtitle: 'Calculate MD5 & SHA-256',
                    trailing: Switch(
                      value: _settings!.computeHashes,
                      onChanged: (v) => setState(() => _settings!.computeHashes = v),
                    ),
                    helpTitle: 'File Hashes',
                    helpText: 'Generates unique fingerprints for each file.\n\n'
                        'Used to:\n'
                        '- Verify file integrity\n'
                        '- Detect corruption\n'
                        '- Avoid duplicate uploads\n\n'
                        'Slightly slower uploads, but recommended for important files.',
                  ),
                  _buildSettingTile(
                    icon: Icons.verified_user,
                    title: 'Verify Downloads',
                    subtitle: 'Check integrity after download',
                    trailing: Switch(
                      value: _settings!.verifyOnDownload,
                      onChanged: (v) => setState(() => _settings!.verifyOnDownload = v),
                    ),
                    helpTitle: 'Verify Downloads',
                    helpText: 'After downloading, the file hash is checked against the original.\n\n'
                        'If they don\'t match, the file may be corrupted and you\'ll be warned.\n\n'
                        'Recommended: ON for important files.',
                  ),
                ]),
                
                _buildSection('Bandwidth', Icons.speed, [
                  _buildSettingTile(
                    icon: Icons.network_check,
                    title: 'Bandwidth Mode',
                    subtitle: _bandwidthService.config.mode == BandwidthMode.unlimited
                        ? 'Unlimited'
                        : _bandwidthService.config.mode == BandwidthMode.auto50percent
                            ? 'Auto 50%'
                            : 'Limited',
                    trailing: DropdownButton<BandwidthMode>(
                      value: _bandwidthService.config.mode,
                      underline: const SizedBox(),
                      items: BandwidthMode.values.map((m) => DropdownMenuItem(
                        value: m,
                        child: Text(m == BandwidthMode.unlimited ? 'Unlimited' 
                            : m == BandwidthMode.auto50percent ? 'Auto 50%' : 'Limited'),
                      )).toList(),
                      onChanged: (v) async {
                        if (v != null) {
                          if (v == BandwidthMode.auto50percent) {
                            await _setAuto50();
                          } else {
                            await _bandwidthService.setMode(v);
                            setState(() {});
                          }
                        }
                      },
                    ),
                    helpTitle: 'Bandwidth Mode',
                    helpText: 'Unlimited: Use maximum available speed\n\n'
                        'Limited: Set custom upload/download limits\n\n'
                        'Auto 50%: Test your connection and use 50% of it\n\n'
                        'Useful to avoid saturating your internet connection.',
                  ),
                  _buildSettingTile(
                    icon: Icons.speed,
                    title: 'Test Connection',
                    subtitle: _bandwidthService.config.measuredSpeedMBps > 0 
                        ? 'Last: ${_bandwidthService.config.measuredSpeedMBps.toStringAsFixed(2)} MB/s'
                        : 'Tap to measure',
                    trailing: _isTesting
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                        : ElevatedButton(onPressed: _testSpeed, child: const Text('Test')),
                    helpTitle: 'Speed Test',
                    helpText: 'Measures your download speed using Cloudflare.\n\n'
                        'This helps set appropriate bandwidth limits.\n\n'
                        'The test downloads a small file to measure speed.',
                  ),
                  if (_bandwidthService.config.mode == BandwidthMode.limited) ...[
                    _buildSettingTile(
                      icon: Icons.upload,
                      title: 'Upload Limit',
                      subtitle: '${_bandwidthService.config.uploadLimitMBps.toStringAsFixed(1)} MB/s',
                      trailing: SizedBox(
                        width: 150,
                        child: Slider(
                          value: _bandwidthService.config.uploadLimitMBps.clamp(0.1, 50),
                          min: 0.1, max: 50, divisions: 49,
                          onChanged: (v) async {
                            await _bandwidthService.setLimits(v, _bandwidthService.config.downloadLimitMBps);
                            setState(() {});
                          },
                        ),
                      ),
                      helpTitle: 'Upload Limit',
                      helpText: 'Maximum upload speed in megabytes per second.\n\n'
                          'Lower values leave more bandwidth for other apps.',
                    ),
                    _buildSettingTile(
                      icon: Icons.download,
                      title: 'Download Limit',
                      subtitle: '${_bandwidthService.config.downloadLimitMBps.toStringAsFixed(1)} MB/s',
                      trailing: SizedBox(
                        width: 150,
                        child: Slider(
                          value: _bandwidthService.config.downloadLimitMBps.clamp(0.1, 50),
                          min: 0.1, max: 50, divisions: 49,
                          onChanged: (v) async {
                            await _bandwidthService.setLimits(_bandwidthService.config.uploadLimitMBps, v);
                            setState(() {});
                          },
                        ),
                      ),
                      helpTitle: 'Download Limit',
                      helpText: 'Maximum download speed in megabytes per second.\n\n'
                          'Lower values leave more bandwidth for other apps.',
                    ),
                  ],
                ]),
                
                _buildSection('Sync', Icons.sync, [
                  _buildSettingTile(
                    icon: Icons.sync,
                    title: 'Auto-sync',
                    subtitle: 'Automatically sync folders',
                    trailing: Switch(
                      value: _settings!.autoSync,
                      onChanged: (v) => setState(() => _settings!.autoSync = v),
                    ),
                    helpTitle: 'Auto-Sync',
                    helpText: 'When enabled, sync folders are automatically uploaded periodically.\n\n'
                        'The app checks for new or modified files and uploads them.\n\n'
                        'Requires sync folders to be configured in the Sync screen.',
                  ),
                  if (_settings!.autoSync)
                    _buildSettingTile(
                      icon: Icons.timer,
                      title: 'Sync Interval',
                      subtitle: 'How often to check for changes',
                      trailing: DropdownButton<int>(
                        value: _settings!.autoSyncInterval,
                        underline: const SizedBox(),
                        items: [5, 10, 15, 30, 60].map((v) => 
                          DropdownMenuItem(value: v, child: Text('$v min'))).toList(),
                        onChanged: (v) { if (v != null) setState(() => _settings!.autoSyncInterval = v); },
                      ),
                      helpTitle: 'Sync Interval',
                      helpText: 'How often the app checks for file changes.\n\n'
                          '5 min: Frequent updates (uses more resources)\n'
                          '30 min: Good balance (recommended)\n'
                          '60 min: Hourly check (saves battery)\n\n'
                          'Files are also synced when you manually trigger it.',
                    ),
                ]),
                
                _buildSection('Display', Icons.palette, [
                  Consumer<ThemeProvider>(
                    builder: (context, themeProvider, _) {
                      return _buildSettingTile(
                        icon: themeProvider.isDark ? Icons.dark_mode : Icons.light_mode,
                        title: 'Theme',
                        subtitle: _settings!.theme == 'system' ? 'Follow system' : _settings!.theme,
                        trailing: SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'light', icon: Icon(Icons.light_mode, size: 18)),
                            ButtonSegment(value: 'system', icon: Icon(Icons.brightness_auto, size: 18)),
                            ButtonSegment(value: 'dark', icon: Icon(Icons.dark_mode, size: 18)),
                          ],
                          selected: {_settings!.theme},
                          onSelectionChanged: (s) {
                            setState(() => _settings!.theme = s.first);
                            themeProvider.setTheme(s.first);
                          },
                        ),
                        helpTitle: 'Theme',
                        helpText: 'Light: Bright background\n'
                            'System: Follows your device settings\n'
                            'Dark: Dark background (easier on eyes)\n\n'
                            'The dark theme uses Discord\'s color palette.',
                      );
                    },
                  ),
                  _buildSettingTile(
                    icon: Icons.visibility,
                    title: 'Show Hidden Files',
                    subtitle: 'Display files starting with .',
                    trailing: Switch(
                      value: _settings!.showHiddenFiles,
                      onChanged: (v) => setState(() => _settings!.showHiddenFiles = v),
                    ),
                    helpTitle: 'Hidden Files',
                    helpText: 'Files starting with a dot (.) are usually system files.\n\n'
                        'Examples: .gitignore, .env, .DS_Store\n\n'
                        'Enable this to see and sync these files too.',
                  ),
                ]),
                
                _buildSection('Cloud Sync (Multi-Device)', Icons.devices, [
                  _buildSettingTile(
                    icon: Icons.cloud_upload,
                    title: 'Export Index to Discord',
                    subtitle: 'Save file list to Discord for other devices',
                    trailing: ElevatedButton(
                      onPressed: _exportIndex,
                      child: const Text('Export'),
                    ),
                    helpTitle: 'Export Index',
                    helpText: 'Exports your file index to Discord.\n\n'
                        'This allows you to recover your file list on another device.\n\n'
                        'Your files stay on Discord, only the list is exported.',
                  ),
                  _buildSettingTile(
                    icon: Icons.cloud_download,
                    title: 'Import Index',
                    subtitle: 'Restore file list from Discord',
                    trailing: ElevatedButton(
                      onPressed: _importIndex,
                      child: const Text('Import'),
                    ),
                    helpTitle: 'Import Index',
                    helpText: 'Import a file index from another device.\n\n'
                        'Copy the JSON from Discord and paste it here.\n\n'
                        'This will add files to your list without deleting existing ones.',
                  ),
                ]),

                _buildSection('Info', Icons.info, [
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.storage, size: 20),
                    title: const Text('Chunk Size'),
                    trailing: Text(_settings!.maxChunkSizeFormatted, 
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.cloud, size: 20),
                    title: const Text('Discord Limits'),
                    trailing: Text(_settings!.hasNitro ? '100 MB' : '10 MB'),
                  ),
                ]),
              ],
            ),
    );
  }

  Widget _buildSection(String title, IconData icon, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(title, style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                )),
              ],
            ),
          ),
          ...children,
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    Color? iconColor,
    required String title,
    required String subtitle,
    required Widget trailing,
    required String helpTitle,
    required String helpText,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 20, color: iconColor ?? Colors.grey.shade600),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(title, style: const TextStyle(fontSize: 14)),
                    _help(helpTitle, helpText),
                  ],
                ),
                Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}
