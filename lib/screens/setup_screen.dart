import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/cloud_provider.dart';
import '../providers/theme_provider.dart';

// Discord Colors
const _blurple = Color(0xFF5865F2);
const _darkBg = Color(0xFF1E1F22);
const _darkSecondary = Color(0xFF2B2D31);

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> with SingleTickerProviderStateMixin {
  final _webhookController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _webhookController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final webhookUrl = _webhookController.text.trim();
    
    if (webhookUrl.isEmpty) {
      setState(() => _error = 'Please enter a webhook URL');
      return;
    }

    if (!webhookUrl.contains('discord.com/api/webhooks/')) {
      setState(() => _error = 'Invalid Discord webhook URL');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final provider = context.read<CloudProvider>();
    final success = await provider.connect(webhookUrl);

    setState(() => _isLoading = false);

    if (!success && mounted) {
      setState(() => _error = provider.errorMessage ?? 'Connection failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [_darkBg, _darkSecondary]
                : [_blurple, const Color(0xFF7289DA)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: FadeTransition(
                opacity: _fadeAnim,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 450),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildLogo(isDark),
                      const SizedBox(height: 32),
                      _buildCard(isDark),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        mini: true,
        onPressed: () => _showThemeSelector(context),
        child: Consumer<ThemeProvider>(
          builder: (context, theme, _) => Icon(
            theme.isDark ? Icons.dark_mode : 
            theme.isLight ? Icons.light_mode : Icons.brightness_auto,
          ),
        ),
      ),
    );
  }

  Widget _buildLogo(bool isDark) {
    return Column(
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF5865F2) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Icon(
            Icons.cloud,
            size: 60,
            color: isDark ? Colors.white : const Color(0xFF5865F2),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Discord Cloud',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 10,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Unlimited cloud storage using Discord',
          style: TextStyle(
            fontSize: 16,
            color: Colors.white.withValues(alpha: 0.9),
          ),
        ),
      ],
    );
  }

  Widget _buildCard(bool isDark) {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Connect your webhook',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Enter your Discord webhook URL to start storing files',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _webhookController,
              decoration: InputDecoration(
                labelText: 'Webhook URL',
                hintText: 'https://discord.com/api/webhooks/...',
                prefixIcon: const Icon(Icons.link),
                errorText: _error,
                suffixIcon: _webhookController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _webhookController.clear();
                          setState(() => _error = null);
                        },
                      )
                    : null,
              ),
              onSubmitted: (_) => _connect(),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _connect,
                child: _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.login),
                          SizedBox(width: 8),
                          Text('Connect', style: TextStyle(fontSize: 16)),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 20),
            _buildHelpSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildHelpSection() {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Row(
          children: [
            Icon(Icons.help_outline, size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              'How to get a webhook URL',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _buildStep(1, 'Open Discord and go to your server'),
                _buildStep(2, 'Right-click a channel > Edit Channel'),
                _buildStep(3, 'Go to Integrations > Webhooks'),
                _buildStep(4, 'Create a new webhook'),
                _buildStep(5, 'Copy the webhook URL'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep(int number, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                '$number',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showThemeSelector(BuildContext context) {
    final themeProvider = context.read<ThemeProvider>();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Choose Theme',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildThemeOption(ctx, themeProvider, 'light', Icons.light_mode, 'Light'),
                  _buildThemeOption(ctx, themeProvider, 'system', Icons.brightness_auto, 'Auto'),
                  _buildThemeOption(ctx, themeProvider, 'dark', Icons.dark_mode, 'Dark'),
                ],
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThemeOption(BuildContext ctx, ThemeProvider provider, String value, IconData icon, String label) {
    final isSelected = (value == 'dark' && provider.isDark) ||
                       (value == 'light' && provider.isLight) ||
                       (value == 'system' && provider.isSystem);
    
    return GestureDetector(
      onTap: () {
        provider.setTheme(value);
        Navigator.pop(ctx);
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected 
              ? Theme.of(ctx).colorScheme.primary.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected 
                ? Theme.of(ctx).colorScheme.primary
                : Colors.grey.withValues(alpha: 0.3),
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 32,
              color: isSelected 
                  ? Theme.of(ctx).colorScheme.primary
                  : Theme.of(ctx).colorScheme.onSurface,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected 
                    ? Theme.of(ctx).colorScheme.primary
                    : Theme.of(ctx).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
