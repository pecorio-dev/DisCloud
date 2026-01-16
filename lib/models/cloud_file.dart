class CloudFile {
  final String id;
  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final List<String> chunkUrls;
  final List<String> messageIds;
  final String? mimeType;
  final bool isCompressed;
  final String webhookId; // ID du webhook qui contient ce fichier

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
    this.webhookId = '',
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
      chunkUrls: List<String>.from(json['u'] ?? json['chunkUrls'] ?? []),
      messageIds: List<String>.from(json['msg'] ?? json['messageIds'] ?? []),
      mimeType: json['t'] ?? json['mimeType'],
      isCompressed: json['z'] ?? json['isCompressed'] ?? false,
      webhookId: json['w'] ?? json['webhookId'] ?? '',
    );
  }

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
      'w': webhookId,
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
    String? webhookId,
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
      webhookId: webhookId ?? this.webhookId,
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

class WebhookInfo {
  final String id;
  final String name;
  final String url;
  final int fileCount;
  final int totalSize;
  final DateTime addedAt;
  final String? indexMessageId;

  WebhookInfo({
    required this.id,
    required this.name,
    required this.url,
    this.fileCount = 0,
    this.totalSize = 0,
    DateTime? addedAt,
    this.indexMessageId,
  }) : addedAt = addedAt ?? DateTime.now();

  factory WebhookInfo.fromJson(Map<String, dynamic> json) {
    return WebhookInfo(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Webhook',
      url: json['url'] ?? '',
      fileCount: json['fileCount'] ?? 0,
      totalSize: json['totalSize'] ?? 0,
      addedAt: json['addedAt'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(json['addedAt'])
          : DateTime.now(),
      indexMessageId: json['indexMsgId'],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'fileCount': fileCount,
    'totalSize': totalSize,
    'addedAt': addedAt.millisecondsSinceEpoch,
    'indexMsgId': indexMessageId,
  };

  WebhookInfo copyWith({
    String? id,
    String? name,
    String? url,
    int? fileCount,
    int? totalSize,
    DateTime? addedAt,
    String? indexMessageId,
  }) {
    return WebhookInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      fileCount: fileCount ?? this.fileCount,
      totalSize: totalSize ?? this.totalSize,
      addedAt: addedAt ?? this.addedAt,
      indexMessageId: indexMessageId ?? this.indexMessageId,
    );
  }

  String get formattedSize {
    if (totalSize < 1024) return '$totalSize B';
    if (totalSize < 1024 * 1024) return '${(totalSize / 1024).toStringAsFixed(1)} KB';
    if (totalSize < 1024 * 1024 * 1024) return '${(totalSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(totalSize / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

class SyncFolder {
  final String localPath;
  final String cloudPath;
  final String webhookId;
  final bool autoSync;
  final int intervalMinutes;
  final DateTime? lastSync;

  SyncFolder({
    required this.localPath,
    required this.cloudPath,
    required this.webhookId,
    this.autoSync = false,
    this.intervalMinutes = 30,
    this.lastSync,
  });

  factory SyncFolder.fromJson(Map<String, dynamic> json) {
    return SyncFolder(
      localPath: json['localPath'] ?? '',
      cloudPath: json['cloudPath'] ?? '/',
      webhookId: json['webhookId'] ?? '',
      autoSync: json['autoSync'] ?? false,
      intervalMinutes: json['interval'] ?? 30,
      lastSync: json['lastSync'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(json['lastSync'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'localPath': localPath,
    'cloudPath': cloudPath,
    'webhookId': webhookId,
    'autoSync': autoSync,
    'interval': intervalMinutes,
    'lastSync': lastSync?.millisecondsSinceEpoch,
  };

  SyncFolder copyWith({
    String? localPath,
    String? cloudPath,
    String? webhookId,
    bool? autoSync,
    int? intervalMinutes,
    DateTime? lastSync,
  }) {
    return SyncFolder(
      localPath: localPath ?? this.localPath,
      cloudPath: cloudPath ?? this.cloudPath,
      webhookId: webhookId ?? this.webhookId,
      autoSync: autoSync ?? this.autoSync,
      intervalMinutes: intervalMinutes ?? this.intervalMinutes,
      lastSync: lastSync ?? this.lastSync,
    );
  }
}
