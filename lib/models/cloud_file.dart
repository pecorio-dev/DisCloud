class CloudFile {
  final String id;
  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final List<String> chunkUrls;
  final List<String> messageIds; // Pour pouvoir supprimer de Discord
  final String? mimeType;
  final bool isCompressed;

  CloudFile({
    required this.id,
    required this.name,
    required this.path,
    required this.isDirectory,
    this.size = 0,
    DateTime? createdAt,
    DateTime? modifiedAt,
    this.chunkUrls = const [],
    this.messageIds = const [],
    this.mimeType,
    this.isCompressed = false,
  })  : createdAt = createdAt ?? DateTime.now(),
        modifiedAt = modifiedAt ?? DateTime.now();

  int get chunkCount => chunkUrls.length;

  factory CloudFile.fromJson(Map<String, dynamic> json) {
    return CloudFile(
      id: json['i'] ?? json['id'] ?? '',
      name: json['n'] ?? json['name'] ?? '',
      path: json['p'] ?? json['path'] ?? '',
      isDirectory: json['d'] ?? json['isDirectory'] ?? false,
      size: json['s'] ?? json['size'] ?? 0,
      createdAt: json['c'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['c'])
          : (json['createdAt'] != null ? DateTime.parse(json['createdAt']) : DateTime.now()),
      modifiedAt: json['m'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['m'])
          : (json['modifiedAt'] != null ? DateTime.parse(json['modifiedAt']) : DateTime.now()),
      chunkUrls: List<String>.from(json['u'] ?? json['chunkUrls'] ?? json['chunkIds'] ?? []),
      messageIds: List<String>.from(json['msg'] ?? json['messageIds'] ?? []),
      mimeType: json['t'] ?? json['mimeType'],
      isCompressed: json['z'] ?? json['isCompressed'] ?? false,
    );
  }

  // Format compact pour l'index Discord (moins de place)
  Map<String, dynamic> toJson() {
    return {
      'i': id,
      'n': name,
      'p': path,
      'd': isDirectory,
      's': size,
      'c': createdAt.millisecondsSinceEpoch,
      'm': modifiedAt.millisecondsSinceEpoch,
      'u': chunkUrls,
      'msg': messageIds,
      't': mimeType,
      'z': isCompressed,
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
    List<String>? chunkUrls,
    List<String>? messageIds,
    String? mimeType,
    bool? isCompressed,
  }) {
    return CloudFile(
      id: id ?? this.id,
      name: name ?? this.name,
      path: path ?? this.path,
      isDirectory: isDirectory ?? this.isDirectory,
      size: size ?? this.size,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      chunkUrls: chunkUrls ?? this.chunkUrls,
      messageIds: messageIds ?? this.messageIds,
      mimeType: mimeType ?? this.mimeType,
      isCompressed: isCompressed ?? this.isCompressed,
    );
  }

  String get extension {
    final parts = name.split('.');
    return parts.length > 1 ? parts.last.toLowerCase() : '';
  }

  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
