# Discord Cloud

<p align="center">
  <img src="assets/logo.png" width="120" alt="Discord Cloud Logo">
</p>

<p align="center">
  <strong>Unlimited cloud storage using Discord webhooks</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-Windows%20|%20Android%20|%20iOS%20|%20Web-blue">
  <img src="https://img.shields.io/badge/Flutter-3.x-02569B">
  <img src="https://img.shields.io/badge/License-MIT-green">
</p>

---

## Overview

Discord Cloud transforms Discord webhooks into a powerful, unlimited cloud storage solution. Upload any file type, organize with folders, sync local directories, and access your data from any device.

### Key Features

- **Unlimited Storage** - No storage limits, only Discord's file size restrictions
- **Multi-Platform** - Windows, Android, iOS, and Web support
- **Multi-Webhook Redundancy** - Upload to multiple Discord servers for backup
- **End-to-End Encryption** - Optional AES-256 encryption for sensitive files
- **Folder Sync** - Automatically sync local folders to the cloud
- **File Preview** - View images, videos, code, and documents in-app
- **Share Links** - Generate secure download links (without exposing webhooks)
- **Bandwidth Control** - Limit upload/download speeds to avoid saturating your connection

---

## Screenshots

| Home Screen | File Viewer | Settings |
|:-----------:|:-----------:|:--------:|
| Browse and manage files | Preview any file type | Configure all options |

---

## Installation

### Windows (Recommended)

1. Download the latest release from [Releases](../../releases)
2. Extract `discord_cloud.zip`
3. Run `discord_cloud.exe`

### Build from Source

```bash
# Clone the repository
git clone https://github.com/yourusername/discord_cloud.git
cd discord_cloud

# Install dependencies
flutter pub get

# Build for Windows
flutter build windows --release

# Build for Android
flutter build apk --release

# Build for Web
flutter build web --release
```

---

## Setup

### Creating a Discord Webhook

1. Open Discord and go to your server
2. Click **Server Settings** > **Integrations** > **Webhooks**
3. Click **New Webhook**
4. Give it a name (e.g., "Cloud Storage")
5. Copy the webhook URL
6. Paste it in Discord Cloud's setup screen

### Multiple Webhooks (Recommended)

For redundancy, you can add multiple webhooks from different servers:

| Mode | Description | Webhooks Used |
|------|-------------|---------------|
| **Quick** | Fastest upload, no redundancy | 1 webhook |
| **Balanced** | Good balance of speed and safety | 2 webhooks |
| **Redundant** | Maximum safety, slowest | All webhooks |

---

## Features

### File Management

- **Upload Files** - Drag & drop or use the file picker
- **Create Folders** - Organize your files with nested folders
- **Bulk Operations** - Select multiple files for download/delete
- **Search** - Find files by name or content

### File Chunking

Discord has file size limits:
- **Free users**: 10 MB per file
- **Nitro users**: 100 MB per file

Discord Cloud automatically splits larger files into chunks and reassembles them on download.

### Compression

Files are compressed with gzip before upload to:
- Reduce upload time
- Save Discord storage space
- Faster downloads

Compression level is configurable (1-9).

### Encryption

Three security modes:

| Mode | Description |
|------|-------------|
| **Standard** | No encryption, fastest |
| **Obfuscated** | Headers modified to prevent Discord scanning |
| **Encrypted** | Full AES-256 encryption (most secure) |

> **Warning**: If you lose your encryption key, files cannot be recovered!

### Folder Sync

Automatically sync local folders to the cloud:

1. Go to **Sync** screen
2. Add a folder to sync
3. Configure options:
   - **Include Subfolders** - Sync nested directories
   - **Ignore Errors** - Continue if some files fail
   - **Auto-Sync** - Periodic automatic sync
   - **Priority** - Order of sync operations

### Bandwidth Limiting

Control upload/download speeds:

| Mode | Description |
|------|-------------|
| **Unlimited** | Maximum speed |
| **Limited** | Custom MB/s limit |
| **Auto 50%** | Test connection, use half the speed |

### Share Links

Generate secure download links:

```
discloud://eyJuIjoibXlmaWxlLnppcCIsInMiOjEwMjQwMCwiYyI6WyJodHRwczovL2Nkbi5kaXNjb3JkLmNvbS8uLi4iXX0=
```

These links contain:
- File name and size
- Chunk download URLs (public CDN)
- Encryption key (if encrypted)

**Important**: Links do NOT contain your webhook URL, so they're safe to share!

### Multi-Device Sync

Access your files from any device:

1. **Export Index** - Saves file list to Discord
2. **Import Index** - Restores file list on another device

Your files remain on Discord; only the index is synced.

---

## Project Structure

```
lib/
├── main.dart                 # App entry point
├── models/
│   ├── cloud_file.dart       # File model with multi-webhook support
│   └── webhook_config.dart   # Webhook configuration
├── providers/
│   ├── cloud_provider.dart   # Main state management
│   ├── theme_provider.dart   # Theme (light/dark/system)
│   └── webhook_provider.dart # Webhook state
├── screens/
│   ├── home_screen.dart      # File browser with selection mode
│   ├── setup_screen.dart     # Initial webhook setup
│   ├── webhooks_screen.dart  # Manage multiple webhooks
│   ├── sync_screen.dart      # Folder sync configuration
│   ├── settings_screen.dart  # App settings
│   ├── search_screen.dart    # File search
│   ├── downloads_screen.dart # Download queue
│   └── file_viewer_screen.dart # File preview router
├── services/
│   ├── discord_service.dart      # Discord API communication
│   ├── multi_webhook_service.dart # Multi-webhook upload/download
│   ├── file_system_service.dart  # Virtual filesystem
│   ├── encryption_service.dart   # AES-256 encryption
│   ├── sync_service.dart         # Folder sync logic
│   ├── download_manager.dart     # Download queue management
│   ├── bandwidth_service.dart    # Speed limiting
│   ├── share_link_service.dart   # Share link generation
│   ├── cloud_index_service.dart  # Index export/import
│   └── auto_sync_service.dart    # Background sync
└── widgets/
    ├── code_viewer.dart      # Code editor with syntax highlighting
    ├── text_viewer.dart      # Text editor
    ├── image_viewer.dart     # Image viewer with zoom
    └── media_player.dart     # Audio/video player
```

---

## Technical Details

### File Storage Format

Each uploaded file is stored as:
1. **Metadata message** - JSON with file info (embedded in Discord message)
2. **Data chunks** - Binary attachments (9MB or 95MB each)

### Chunk Format

```
[4 bytes: metadata length][JSON metadata][compressed data]
```

### Metadata Structure

```json
{
  "n": "filename.ext",
  "s": 1024000,
  "c": "md5hash",
  "t": 3,
  "i": 0,
  "z": true,
  "d": 1705312800000
}
```

| Field | Description |
|-------|-------------|
| `n` | Original filename |
| `s` | Original size (bytes) |
| `c` | MD5 checksum |
| `t` | Total chunks |
| `i` | Chunk index |
| `z` | Is compressed |
| `d` | Created timestamp |

### Multi-Webhook Storage

Files can be uploaded to multiple webhooks:

```json
{
  "webhookChunks": {
    "webhook1_id": ["url1", "url2", "url3"],
    "webhook2_id": ["url1", "url2", "url3"]
  }
}
```

Download attempts each webhook in order until one succeeds.

---

## Keyboard Shortcuts

### Code/Text Editor

| Shortcut | Action |
|----------|--------|
| `Ctrl+Z` | Undo |
| `Ctrl+Y` | Redo |
| `Ctrl+S` | Save |
| `Ctrl+F` | Search |

---

## Limitations

- **File Size**: Discord limits individual uploads (10MB free, 100MB Nitro)
- **Rate Limits**: Discord may throttle rapid uploads
- **URL Expiry**: Discord CDN URLs may expire after some time
- **No Versioning**: Overwriting a file deletes the old version

---

## Troubleshooting

### "Upload failed" errors

1. Check your internet connection
2. Verify webhook URL is valid
3. Try adding more webhooks for redundancy
4. Enable "Ignore Errors" in sync settings

### Files not syncing

1. Ensure folder path exists
2. Check file permissions
3. Try manual sync first

### Slow uploads

1. Enable compression
2. Use bandwidth limiting to avoid rate limits
3. Check your internet speed

---

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## Disclaimer

This project is not affiliated with Discord. Use responsibly and respect Discord's Terms of Service. The developers are not responsible for any data loss or account actions resulting from use of this software.

---

## Acknowledgments

- Flutter team for the amazing framework
- Discord for providing the webhook API
- All contributors and testers

---

<p align="center">
  Made with ❤️ and Flutter
</p>
