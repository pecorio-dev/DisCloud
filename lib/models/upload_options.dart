import 'dart:convert';

enum CompressionLevel { none, fast, balanced, maximum }
enum EncryptionType { none, aes256, xor, custom }
enum ObfuscationType { none, base64, hex, reverse, shuffle }

class UploadOptions {
  // Compression
  final CompressionLevel compressionLevel;
  final bool adaptiveCompression; // Skip if already compressed (jpg, mp4, etc)
  
  // Encryption
  final EncryptionType encryptionType;
  final String? encryptionKey;
  final bool deriveKeyFromPassword; // Use PBKDF2
  
  // Obfuscation
  final ObfuscationType filenameObfuscation;
  final ObfuscationType contentObfuscation;
  final bool addFakeHeaders; // Add random bytes at start
  final int fakeHeaderSize;
  
  // Chunking
  final int chunkSizeKB; // 1024-9216 KB (free) or up to 95MB (Nitro)
  final bool parallelUpload;
  final int maxParallelChunks;
  
  // Integrity
  final bool calculateChecksum; // SHA-256
  final bool verifyAfterUpload;
  
  // Redundancy
  final bool enableRedundancy;
  final int redundancyCopies; // 1-3
  
  // Stealth
  final bool randomizeChunkOrder;
  final bool addRandomDelays;
  final int minDelayMs;
  final int maxDelayMs;

  const UploadOptions({
    this.compressionLevel = CompressionLevel.balanced,
    this.adaptiveCompression = true,
    this.encryptionType = EncryptionType.none,
    this.encryptionKey,
    this.deriveKeyFromPassword = true,
    this.filenameObfuscation = ObfuscationType.none,
    this.contentObfuscation = ObfuscationType.none,
    this.addFakeHeaders = false,
    this.fakeHeaderSize = 64,
    this.chunkSizeKB = 8192,
    this.parallelUpload = false,
    this.maxParallelChunks = 3,
    this.calculateChecksum = true,
    this.verifyAfterUpload = false,
    this.enableRedundancy = false,
    this.redundancyCopies = 1,
    this.randomizeChunkOrder = false,
    this.addRandomDelays = false,
    this.minDelayMs = 100,
    this.maxDelayMs = 500,
  });

  UploadOptions copyWith({
    CompressionLevel? compressionLevel,
    bool? adaptiveCompression,
    EncryptionType? encryptionType,
    String? encryptionKey,
    bool? deriveKeyFromPassword,
    ObfuscationType? filenameObfuscation,
    ObfuscationType? contentObfuscation,
    bool? addFakeHeaders,
    int? fakeHeaderSize,
    int? chunkSizeKB,
    bool? parallelUpload,
    int? maxParallelChunks,
    bool? calculateChecksum,
    bool? verifyAfterUpload,
    bool? enableRedundancy,
    int? redundancyCopies,
    bool? randomizeChunkOrder,
    bool? addRandomDelays,
    int? minDelayMs,
    int? maxDelayMs,
  }) {
    return UploadOptions(
      compressionLevel: compressionLevel ?? this.compressionLevel,
      adaptiveCompression: adaptiveCompression ?? this.adaptiveCompression,
      encryptionType: encryptionType ?? this.encryptionType,
      encryptionKey: encryptionKey ?? this.encryptionKey,
      deriveKeyFromPassword: deriveKeyFromPassword ?? this.deriveKeyFromPassword,
      filenameObfuscation: filenameObfuscation ?? this.filenameObfuscation,
      contentObfuscation: contentObfuscation ?? this.contentObfuscation,
      addFakeHeaders: addFakeHeaders ?? this.addFakeHeaders,
      fakeHeaderSize: fakeHeaderSize ?? this.fakeHeaderSize,
      chunkSizeKB: chunkSizeKB ?? this.chunkSizeKB,
      parallelUpload: parallelUpload ?? this.parallelUpload,
      maxParallelChunks: maxParallelChunks ?? this.maxParallelChunks,
      calculateChecksum: calculateChecksum ?? this.calculateChecksum,
      verifyAfterUpload: verifyAfterUpload ?? this.verifyAfterUpload,
      enableRedundancy: enableRedundancy ?? this.enableRedundancy,
      redundancyCopies: redundancyCopies ?? this.redundancyCopies,
      randomizeChunkOrder: randomizeChunkOrder ?? this.randomizeChunkOrder,
      addRandomDelays: addRandomDelays ?? this.addRandomDelays,
      minDelayMs: minDelayMs ?? this.minDelayMs,
      maxDelayMs: maxDelayMs ?? this.maxDelayMs,
    );
  }

  Map<String, dynamic> toJson() => {
    'compressionLevel': compressionLevel.index,
    'adaptiveCompression': adaptiveCompression,
    'encryptionType': encryptionType.index,
    'encryptionKey': encryptionKey,
    'deriveKeyFromPassword': deriveKeyFromPassword,
    'filenameObfuscation': filenameObfuscation.index,
    'contentObfuscation': contentObfuscation.index,
    'addFakeHeaders': addFakeHeaders,
    'fakeHeaderSize': fakeHeaderSize,
    'chunkSizeKB': chunkSizeKB,
    'parallelUpload': parallelUpload,
    'maxParallelChunks': maxParallelChunks,
    'calculateChecksum': calculateChecksum,
    'verifyAfterUpload': verifyAfterUpload,
    'enableRedundancy': enableRedundancy,
    'redundancyCopies': redundancyCopies,
    'randomizeChunkOrder': randomizeChunkOrder,
    'addRandomDelays': addRandomDelays,
    'minDelayMs': minDelayMs,
    'maxDelayMs': maxDelayMs,
  };

  factory UploadOptions.fromJson(Map<String, dynamic> json) {
    return UploadOptions(
      compressionLevel: CompressionLevel.values[json['compressionLevel'] ?? 1],
      adaptiveCompression: json['adaptiveCompression'] ?? true,
      encryptionType: EncryptionType.values[json['encryptionType'] ?? 0],
      encryptionKey: json['encryptionKey'],
      deriveKeyFromPassword: json['deriveKeyFromPassword'] ?? true,
      filenameObfuscation: ObfuscationType.values[json['filenameObfuscation'] ?? 0],
      contentObfuscation: ObfuscationType.values[json['contentObfuscation'] ?? 0],
      addFakeHeaders: json['addFakeHeaders'] ?? false,
      fakeHeaderSize: json['fakeHeaderSize'] ?? 64,
      chunkSizeKB: json['chunkSizeKB'] ?? 8192,
      parallelUpload: json['parallelUpload'] ?? false,
      maxParallelChunks: json['maxParallelChunks'] ?? 3,
      calculateChecksum: json['calculateChecksum'] ?? true,
      verifyAfterUpload: json['verifyAfterUpload'] ?? false,
      enableRedundancy: json['enableRedundancy'] ?? false,
      redundancyCopies: json['redundancyCopies'] ?? 1,
      randomizeChunkOrder: json['randomizeChunkOrder'] ?? false,
      addRandomDelays: json['addRandomDelays'] ?? false,
      minDelayMs: json['minDelayMs'] ?? 100,
      maxDelayMs: json['maxDelayMs'] ?? 500,
    );
  }

  String toJsonString() => jsonEncode(toJson());
  factory UploadOptions.fromJsonString(String json) => UploadOptions.fromJson(jsonDecode(json));

  // Presets
  static const UploadOptions fast = UploadOptions(
    compressionLevel: CompressionLevel.fast,
    encryptionType: EncryptionType.none,
    calculateChecksum: false,
  );

  static const UploadOptions secure = UploadOptions(
    compressionLevel: CompressionLevel.balanced,
    encryptionType: EncryptionType.aes256,
    filenameObfuscation: ObfuscationType.base64,
    addFakeHeaders: true,
    calculateChecksum: true,
    verifyAfterUpload: true,
  );

  static const UploadOptions paranoid = UploadOptions(
    compressionLevel: CompressionLevel.maximum,
    encryptionType: EncryptionType.aes256,
    filenameObfuscation: ObfuscationType.shuffle,
    contentObfuscation: ObfuscationType.base64,
    addFakeHeaders: true,
    fakeHeaderSize: 256,
    calculateChecksum: true,
    verifyAfterUpload: true,
    enableRedundancy: true,
    redundancyCopies: 2,
    randomizeChunkOrder: true,
    addRandomDelays: true,
  );

  static const UploadOptions maxCompression = UploadOptions(
    compressionLevel: CompressionLevel.maximum,
    adaptiveCompression: false,
    encryptionType: EncryptionType.none,
    calculateChecksum: true,
  );
}
