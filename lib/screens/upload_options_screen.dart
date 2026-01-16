import 'package:flutter/material.dart';
import '../models/upload_options.dart';

class UploadOptionsScreen extends StatefulWidget {
  final UploadOptions options;
  final Function(UploadOptions) onSave;

  const UploadOptionsScreen({
    super.key,
    required this.options,
    required this.onSave,
  });

  @override
  State<UploadOptionsScreen> createState() => _UploadOptionsScreenState();
}

class _UploadOptionsScreenState extends State<UploadOptionsScreen> {
  late UploadOptions _options;
  final _keyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _options = widget.options;
    _keyController.text = _options.encryptionKey ?? '';
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload Options'),
        actions: [
          TextButton(
            onPressed: () {
              widget.onSave(_options);
              Navigator.pop(context);
            },
            child: const Text('SAVE', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Presets
          _buildSection('Quick Presets', [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _PresetChip(label: 'Fast', icon: Icons.flash_on, selected: false, onTap: () => setState(() => _options = UploadOptions.fast)),
                _PresetChip(label: 'Balanced', icon: Icons.balance, selected: false, onTap: () => setState(() => _options = const UploadOptions())),
                _PresetChip(label: 'Secure', icon: Icons.security, selected: false, onTap: () => setState(() => _options = UploadOptions.secure)),
                _PresetChip(label: 'Paranoid', icon: Icons.shield, selected: false, onTap: () => setState(() => _options = UploadOptions.paranoid)),
                _PresetChip(label: 'Max Compress', icon: Icons.compress, selected: false, onTap: () => setState(() => _options = UploadOptions.maxCompression)),
              ],
            ),
          ]),

          const Divider(height: 32),

          // Compression
          _buildSection('Compression', [
            _buildDropdown<CompressionLevel>(
              'Compression Level',
              _options.compressionLevel,
              CompressionLevel.values,
              (v) => setState(() => _options = _options.copyWith(compressionLevel: v)),
              (v) => ['None', 'Fast', 'Balanced', 'Maximum'][v.index],
              Icons.compress,
            ),
            _buildSwitch(
              'Adaptive Compression',
              'Skip compression for already compressed files (jpg, mp4, zip)',
              _options.adaptiveCompression,
              (v) => setState(() => _options = _options.copyWith(adaptiveCompression: v)),
            ),
          ]),

          const Divider(height: 32),

          // Encryption
          _buildSection('Encryption', [
            _buildDropdown<EncryptionType>(
              'Encryption Type',
              _options.encryptionType,
              EncryptionType.values,
              (v) => setState(() => _options = _options.copyWith(encryptionType: v)),
              (v) => ['None', 'AES-256-CBC', 'XOR (Fast)', 'Custom (AES+XOR)'][v.index],
              Icons.lock,
            ),
            if (_options.encryptionType != EncryptionType.none) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _keyController,
                decoration: InputDecoration(
                  labelText: 'Encryption Key / Password',
                  hintText: 'Enter a strong password',
                  prefixIcon: const Icon(Icons.key),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.auto_awesome),
                    tooltip: 'Generate random key',
                    onPressed: () {
                      final key = List.generate(24, (_) => 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'[DateTime.now().microsecond % 62]).join();
                      _keyController.text = key;
                      _options = _options.copyWith(encryptionKey: key);
                    },
                  ),
                  border: const OutlineInputBorder(),
                ),
                obscureText: true,
                onChanged: (v) => _options = _options.copyWith(encryptionKey: v),
              ),
              const SizedBox(height: 8),
              _buildSwitch(
                'Derive Key from Password',
                'Use PBKDF2 to strengthen the key (recommended)',
                _options.deriveKeyFromPassword,
                (v) => setState(() => _options = _options.copyWith(deriveKeyFromPassword: v)),
              ),
            ],
          ]),

          const Divider(height: 32),

          // Obfuscation
          _buildSection('Obfuscation', [
            _buildDropdown<ObfuscationType>(
              'Filename Obfuscation',
              _options.filenameObfuscation,
              ObfuscationType.values,
              (v) => setState(() => _options = _options.copyWith(filenameObfuscation: v)),
              (v) => ['None', 'Base64', 'Hex', 'Reverse', 'Shuffle'][v.index],
              Icons.text_fields,
            ),
            const SizedBox(height: 12),
            _buildDropdown<ObfuscationType>(
              'Content Obfuscation',
              _options.contentObfuscation,
              ObfuscationType.values,
              (v) => setState(() => _options = _options.copyWith(contentObfuscation: v)),
              (v) => ['None', 'Base64', 'Hex', 'Reverse', 'Shuffle'][v.index],
              Icons.shuffle,
            ),
            const SizedBox(height: 12),
            _buildSwitch(
              'Add Fake Headers',
              'Add random bytes at start of each chunk',
              _options.addFakeHeaders,
              (v) => setState(() => _options = _options.copyWith(addFakeHeaders: v)),
            ),
            if (_options.addFakeHeaders) ...[
              const SizedBox(height: 8),
              _buildSlider(
                'Fake Header Size',
                _options.fakeHeaderSize.toDouble(),
                32, 512,
                '${_options.fakeHeaderSize} bytes',
                (v) => setState(() => _options = _options.copyWith(fakeHeaderSize: v.toInt())),
              ),
            ],
          ]),

          const Divider(height: 32),

          // Chunking
          _buildSection('Chunking', [
            _buildSlider(
              'Chunk Size',
              _options.chunkSizeKB.toDouble(),
              1024, 9216,
              '${(_options.chunkSizeKB / 1024).toStringAsFixed(1)} MB',
              (v) => setState(() => _options = _options.copyWith(chunkSizeKB: v.toInt())),
            ),
            const SizedBox(height: 12),
            _buildSwitch(
              'Parallel Upload',
              'Upload multiple chunks simultaneously',
              _options.parallelUpload,
              (v) => setState(() => _options = _options.copyWith(parallelUpload: v)),
            ),
            if (_options.parallelUpload) ...[
              const SizedBox(height: 8),
              _buildSlider(
                'Max Parallel Chunks',
                _options.maxParallelChunks.toDouble(),
                2, 5,
                '${_options.maxParallelChunks} chunks',
                (v) => setState(() => _options = _options.copyWith(maxParallelChunks: v.toInt())),
              ),
            ],
            const SizedBox(height: 12),
            _buildSwitch(
              'Randomize Chunk Order',
              'Upload chunks in random order (stealth)',
              _options.randomizeChunkOrder,
              (v) => setState(() => _options = _options.copyWith(randomizeChunkOrder: v)),
            ),
          ]),

          const Divider(height: 32),

          // Integrity
          _buildSection('Integrity & Verification', [
            _buildSwitch(
              'Calculate Checksum',
              'SHA-256 hash for integrity verification',
              _options.calculateChecksum,
              (v) => setState(() => _options = _options.copyWith(calculateChecksum: v)),
            ),
            _buildSwitch(
              'Verify After Upload',
              'Re-download and verify each chunk',
              _options.verifyAfterUpload,
              (v) => setState(() => _options = _options.copyWith(verifyAfterUpload: v)),
            ),
          ]),

          const Divider(height: 32),

          // Redundancy
          _buildSection('Redundancy', [
            _buildSwitch(
              'Enable Redundancy',
              'Upload multiple copies for backup',
              _options.enableRedundancy,
              (v) => setState(() => _options = _options.copyWith(enableRedundancy: v)),
            ),
            if (_options.enableRedundancy) ...[
              const SizedBox(height: 8),
              _buildSlider(
                'Redundancy Copies',
                _options.redundancyCopies.toDouble(),
                1, 3,
                '${_options.redundancyCopies} copies',
                (v) => setState(() => _options = _options.copyWith(redundancyCopies: v.toInt())),
              ),
            ],
          ]),

          const Divider(height: 32),

          // Stealth
          _buildSection('Stealth Mode', [
            _buildSwitch(
              'Add Random Delays',
              'Wait between chunk uploads to avoid rate limits',
              _options.addRandomDelays,
              (v) => setState(() => _options = _options.copyWith(addRandomDelays: v)),
            ),
            if (_options.addRandomDelays) ...[
              const SizedBox(height: 8),
              _buildSlider(
                'Min Delay',
                _options.minDelayMs.toDouble(),
                50, 1000,
                '${_options.minDelayMs} ms',
                (v) => setState(() => _options = _options.copyWith(minDelayMs: v.toInt())),
              ),
              _buildSlider(
                'Max Delay',
                _options.maxDelayMs.toDouble(),
                100, 2000,
                '${_options.maxDelayMs} ms',
                (v) => setState(() => _options = _options.copyWith(maxDelayMs: v.toInt())),
              ),
            ],
          ]),

          const SizedBox(height: 32),

          // Info card
          Card(
            color: Colors.blue.withOpacity(0.1),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.info, color: Colors.blue),
                      const SizedBox(width: 8),
                      const Text('Current Configuration', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Compression: ${['None', 'Fast', 'Balanced', 'Maximum'][_options.compressionLevel.index]}'),
                  Text('Encryption: ${['None', 'AES-256', 'XOR', 'Custom'][_options.encryptionType.index]}'),
                  Text('Filename obfuscation: ${['None', 'Base64', 'Hex', 'Reverse', 'Shuffle'][_options.filenameObfuscation.index]}'),
                  Text('Chunk size: ${(_options.chunkSizeKB / 1024).toStringAsFixed(1)} MB'),
                  if (_options.enableRedundancy) Text('Redundancy: ${_options.redundancyCopies} copies'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }

  Widget _buildSwitch(String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      title: Text(title),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildSlider(String label, double value, double min, double max, String display, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text(display, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        Slider(value: value, min: min, max: max, divisions: ((max - min) / 32).round(), onChanged: onChanged),
      ],
    );
  }

  Widget _buildDropdown<T>(String label, T value, List<T> items, ValueChanged<T> onChanged, String Function(T) labelBuilder, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey),
        const SizedBox(width: 12),
        Expanded(child: Text(label)),
        DropdownButton<T>(
          value: value,
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(labelBuilder(e)))).toList(),
          onChanged: (v) => onChanged(v as T),
        ),
      ],
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _PresetChip({required this.label, required this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onPressed: onTap,
      backgroundColor: selected ? Theme.of(context).colorScheme.primaryContainer : null,
    );
  }
}
