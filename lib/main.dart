import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/cloud_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/download_manager.dart';
import 'screens/setup_screen.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const DiscordCloudApp());
}

class DiscordCloudApp extends StatelessWidget {
  const DiscordCloudApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CloudProvider()..init()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()..init()),
        ChangeNotifierProvider(create: (_) => DownloadManager()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: 'DisCloud',
            debugShowCheckedModeBanner: false,
            theme: ThemeProvider.lightTheme,
            darkTheme: ThemeProvider.darkTheme,
            themeMode: themeProvider.themeMode,
            home: const MainWrapper(),
          );
        },
      ),
    );
  }
}

class MainWrapper extends StatelessWidget {
  const MainWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<CloudProvider>(
      builder: (context, provider, _) {
        if (!provider.isInitialized) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/logo.png',
                    width: 100,
                    height: 100,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.cloud,
                      size: 100,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  const Text('Loading...'),
                ],
              ),
            ),
          );
        }

        if (!provider.isConnected) {
          return const SetupScreen();
        }

        return const HomeScreen();
      },
    );
  }
}
