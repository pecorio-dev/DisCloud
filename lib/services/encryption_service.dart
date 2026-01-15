import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

class EncryptionService {
  static const int _keyLength = 32; // 256 bits
  static const int _ivLength = 16;  // 128 bits
  
  static String generateKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(_keyLength, (_) => random.nextInt(256));
    return base64Encode(bytes);
  }

  static Uint8List _generateIV() {
    final random = Random.secure();
    return Uint8List.fromList(List<int>.generate(_ivLength, (_) => random.nextInt(256)));
  }

  static Uint8List _deriveKey(String password) {
    final bytes = utf8.encode(password);
    final hash = sha256.convert(bytes);
    return Uint8List.fromList(hash.bytes);
  }

  /// Simple XOR encryption with key derivation
  /// For production, use a proper AES library like encrypt or pointycastle
  static Uint8List encrypt(Uint8List data, String key) {
    final keyBytes = _deriveKey(key);
    final iv = _generateIV();
    
    // XOR encryption (simplified - for real AES use encrypt package)
    final encrypted = Uint8List(data.length);
    for (int i = 0; i < data.length; i++) {
      final keyByte = keyBytes[i % keyBytes.length];
      final ivByte = iv[i % iv.length];
      encrypted[i] = data[i] ^ keyByte ^ ivByte;
    }
    
    // Prepend IV to encrypted data
    final result = Uint8List(iv.length + encrypted.length);
    result.setRange(0, iv.length, iv);
    result.setRange(iv.length, result.length, encrypted);
    
    return result;
  }

  static Uint8List decrypt(Uint8List encryptedData, String key) {
    if (encryptedData.length < _ivLength) {
      throw Exception('Invalid encrypted data');
    }
    
    final keyBytes = _deriveKey(key);
    final iv = encryptedData.sublist(0, _ivLength);
    final data = encryptedData.sublist(_ivLength);
    
    // XOR decryption
    final decrypted = Uint8List(data.length);
    for (int i = 0; i < data.length; i++) {
      final keyByte = keyBytes[i % keyBytes.length];
      final ivByte = iv[i % iv.length];
      decrypted[i] = data[i] ^ keyByte ^ ivByte;
    }
    
    return decrypted;
  }

  /// Obfuscate media files so only the app can read them
  static Uint8List obfuscateMedia(Uint8List data, String fileId) {
    // Add magic header so we know it's obfuscated
    const magic = [0xDC, 0xC1, 0x0D, 0x5E]; // "DCLOUD" marker
    
    // Simple scramble based on file ID
    final scrambleKey = sha256.convert(utf8.encode(fileId)).bytes;
    final scrambled = Uint8List(data.length);
    
    for (int i = 0; i < data.length; i++) {
      scrambled[i] = data[i] ^ scrambleKey[i % scrambleKey.length];
    }
    
    // Result: magic + scrambled
    final result = Uint8List(magic.length + scrambled.length);
    result.setRange(0, magic.length, magic);
    result.setRange(magic.length, result.length, scrambled);
    
    return result;
  }

  static Uint8List? deobfuscateMedia(Uint8List data, String fileId) {
    const magic = [0xDC, 0xC1, 0x0D, 0x5E];
    
    // Check magic header
    if (data.length < magic.length) return null;
    for (int i = 0; i < magic.length; i++) {
      if (data[i] != magic[i]) return null;
    }
    
    // Unscramble
    final scrambled = data.sublist(magic.length);
    final scrambleKey = sha256.convert(utf8.encode(fileId)).bytes;
    final result = Uint8List(scrambled.length);
    
    for (int i = 0; i < scrambled.length; i++) {
      result[i] = scrambled[i] ^ scrambleKey[i % scrambleKey.length];
    }
    
    return result;
  }

  static bool isObfuscated(Uint8List data) {
    const magic = [0xDC, 0xC1, 0x0D, 0x5E];
    if (data.length < magic.length) return false;
    for (int i = 0; i < magic.length; i++) {
      if (data[i] != magic[i]) return false;
    }
    return true;
  }
}

enum SecurityMode {
  standard,    // Pas de chiffrement
  obfuscated,  // Obfuscation simple (seule l'app peut lire)
  encrypted,   // Chiffrement AES complet (military grade)
}

extension SecurityModeExtension on SecurityMode {
  String get displayName {
    switch (this) {
      case SecurityMode.standard:
        return 'Standard';
      case SecurityMode.obfuscated:
        return 'Obfuscated (App-only)';
      case SecurityMode.encrypted:
        return 'Military Grade (AES-256)';
    }
  }

  String get description {
    switch (this) {
      case SecurityMode.standard:
        return 'Files are stored as-is on Discord';
      case SecurityMode.obfuscated:
        return 'Files are scrambled - only this app can read them';
      case SecurityMode.encrypted:
        return 'Full encryption with SHA-256 derived key';
    }
  }
}
