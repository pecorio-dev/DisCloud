class CloudFile {
  final String id;
  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final List<String> chunkIds; // Legacy: single webhook URLs
  final Map<String, List<String>> webhookChunks; // Multi-webhook: webhookUrl -> chunk URLs
  final String? mimeType;

  CloudFile({
    required this.id,
    required this.name,
    required this.path,
    required this.isDirectory,
    this.size = 0,
    DateTime? createdAt,
    DateTime? modifiedAt,
    this.chunkIds = const [],
    this.webhookChunks = const {},
    this.mimeType,
  })  : createdAt = createdAt ?? DateTime.now(),
        modifiedAt = modifiedAt ?? DateTime.now();
  
  /// Retourne true si le fichier a des URLs multi-webhook
  bool get hasMultiWebhook => webhookChunks.isNotEmpty;
  
  /// Nombre de webhooks qui ont ce fichier
  int get webhookCount => webhookChunks.length;

  factory CloudFile.fromJson(Map<String, dynamic> json) {
    // Parse webhookChunks
    Map<String, List<String>> webhookChunks = {};
    if (json['webhookChunks'] != null) {
      final Map<String, dynamic> chunks = json['webhookChunks'];
      chunks.forEach((key, value) {
        webhookChunks[key] = List<String>.from(value);
      });
    }
    
    return CloudFile(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      path: json['path'] ?? '',
      isDirectory: json['isDirectory'] ?? false,
      size: json['size'] ?? 0,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      modifiedAt: json['modifiedAt'] != null
          ? DateTime.parse(json['modifiedAt'])
          : DateTime.now(),
      chunkIds: List<String>.from(json['chunkIds'] ?? []),
      webhookChunks: webhookChunks,
      mimeType: json['mimeType'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'path': path,
      'isDirectory': isDirectory,
      'size': size,
      'createdAt': createdAt.toIso8601String(),
      'modifiedAt': modifiedAt.toIso8601String(),
      'chunkIds': chunkIds,
      'webhookChunks': webhookChunks,
      'mimeType': mimeType,
    };
  }

  CloudFile copyWith({
    String? id,
    String? name,
    String? path,
    bool? isDirectory,
    int? size,
    DateTime? createdAt,
    DateTime? modifiedAt,
    List<String>? chunkIds,
    Map<String, List<String>>? webhookChunks,
    String? mimeType,
  }) {
    return CloudFile(
      id: id ?? this.id,
      name: name ?? this.name,
      path: path ?? this.path,
      isDirectory: isDirectory ?? this.isDirectory,
      size: size ?? this.size,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      chunkIds: chunkIds ?? this.chunkIds,
      webhookChunks: webhookChunks ?? this.webhookChunks,
      mimeType: mimeType ?? this.mimeType,
    );
  }

  String get extension {
    final parts = name.split('.');
    return parts.length > 1 ? parts.last.toLowerCase() : '';
  }

  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
