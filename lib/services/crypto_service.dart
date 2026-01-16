import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import '../models/upload_options.dart';

class CryptoService {
  static final _random = Random.secure();

  // ==================== HASHING ====================

  static String sha256Hash(Uint8List data) {
    return sha256.convert(data).toString();
  }

  static String md5Hash(Uint8List data) {
    return md5.convert(data).toString();
  }

  // ==================== KEY DERIVATION ====================

  static Uint8List deriveKey(String password, {Uint8List? salt, int iterations = 10000}) {
    salt ??= generateRandomBytes(16);
    
    // PBKDF2-like derivation using HMAC-SHA256
    var key = Uint8List.fromList(utf8.encode(password));
    var result = Uint8List(32);
    
    for (int i = 0; i < iterations; i++) {
      final hmac = Hmac(sha256, key);
      final digest = hmac.convert([...salt!, ...result]);
      for (int j = 0; j < 32; j++) {
        result[j] ^= digest.bytes[j];
      }
      key = Uint8List.fromList(digest.bytes);
    }
    
    return result;
  }

  static Uint8List generateRandomBytes(int length) {
    return Uint8List.fromList(List.generate(length, (_) => _random.nextInt(256)));
  }

  // ==================== ENCRYPTION ====================

  static Uint8List encryptAES256(Uint8List data, String password) {
    final salt = generateRandomBytes(16);
    final key = deriveKey(password, salt: salt, iterations: 10000);
    final iv = generateRandomBytes(16);
    
    final encrypter = enc.Encrypter(enc.AES(
      enc.Key(key),
      mode: enc.AESMode.cbc,
      padding: 'PKCS7',
    ));
    
    final encrypted = encrypter.encryptBytes(data, iv: enc.IV(iv));
    
    // Format: [salt(16)][iv(16)][encrypted data]
    return Uint8List.fromList([...salt, ...iv, ...encrypted.bytes]);
  }

  static Uint8List decryptAES256(Uint8List data, String password) {
    if (data.length < 33) throw Exception('Invalid encrypted data');
    
    final salt = Uint8List.fromList(data.sublist(0, 16));
    final iv = Uint8List.fromList(data.sublist(16, 32));
    final encryptedData = Uint8List.fromList(data.sublist(32));
    
    final key = deriveKey(password, salt: salt, iterations: 10000);
    
    final encrypter = enc.Encrypter(enc.AES(
      enc.Key(key),
      mode: enc.AESMode.cbc,
      padding: 'PKCS7',
    ));
    
    return Uint8List.fromList(encrypter.decryptBytes(
      enc.Encrypted(encryptedData),
      iv: enc.IV(iv),
    ));
  }

  static Uint8List encryptXOR(Uint8List data, String password) {
    final key = utf8.encode(password);
    final result = Uint8List(data.length);
    
    for (int i = 0; i < data.length; i++) {
      result[i] = data[i] ^ key[i % key.length];
    }
    
    return result;
  }

  static Uint8List decryptXOR(Uint8List data, String password) {
    return encryptXOR(data, password); // XOR is symmetric
  }

  // ==================== OBFUSCATION ====================

  static String obfuscateFilename(String filename, ObfuscationType type) {
    switch (type) {
      case ObfuscationType.none:
        return filename;
      case ObfuscationType.base64:
        return base64Url.encode(utf8.encode(filename)).replaceAll('=', '');
      case ObfuscationType.hex:
        return utf8.encode(filename).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      case ObfuscationType.reverse:
        return filename.split('').reversed.join();
      case ObfuscationType.shuffle:
        final chars = filename.split('');
        chars.shuffle(_random);
        final seed = _random.nextInt(65536);
        return '${seed.toRadixString(16).padLeft(4, '0')}_${chars.join()}';
    }
  }

  static String deobfuscateFilename(String obfuscated, ObfuscationType type) {
    switch (type) {
      case ObfuscationType.none:
        return obfuscated;
      case ObfuscationType.base64:
        var padded = obfuscated;
        while (padded.length % 4 != 0) padded += '=';
        return utf8.decode(base64Url.decode(padded));
      case ObfuscationType.hex:
        final bytes = <int>[];
        for (int i = 0; i < obfuscated.length; i += 2) {
          bytes.add(int.parse(obfuscated.substring(i, i + 2), radix: 16));
        }
        return utf8.decode(bytes);
      case ObfuscationType.reverse:
        return obfuscated.split('').reversed.join();
      case ObfuscationType.shuffle:
        return obfuscated; // Can't unshuffle without original
    }
  }

  static Uint8List obfuscateContent(Uint8List data, ObfuscationType type) {
    switch (type) {
      case ObfuscationType.none:
        return data;
      case ObfuscationType.base64:
        return Uint8List.fromList(utf8.encode(base64.encode(data)));
      case ObfuscationType.hex:
        return Uint8List.fromList(utf8.encode(data.map((b) => b.toRadixString(16).padLeft(2, '0')).join()));
      case ObfuscationType.reverse:
        return Uint8List.fromList(data.reversed.toList());
      case ObfuscationType.shuffle:
        final seed = _random.nextInt(65536);
        final indices = List.generate(data.length, (i) => i);
        indices.shuffle(Random(seed));
        final result = Uint8List(data.length + 2);
        result[0] = (seed >> 8) & 0xFF;
        result[1] = seed & 0xFF;
        for (int i = 0; i < data.length; i++) {
          result[i + 2] = data[indices[i]];
        }
        return result;
    }
  }

  static Uint8List deobfuscateContent(Uint8List data, ObfuscationType type) {
    switch (type) {
      case ObfuscationType.none:
        return data;
      case ObfuscationType.base64:
        return Uint8List.fromList(base64.decode(utf8.decode(data)));
      case ObfuscationType.hex:
        final hexStr = utf8.decode(data);
        final bytes = <int>[];
        for (int i = 0; i < hexStr.length; i += 2) {
          bytes.add(int.parse(hexStr.substring(i, i + 2), radix: 16));
        }
        return Uint8List.fromList(bytes);
      case ObfuscationType.reverse:
        return Uint8List.fromList(data.reversed.toList());
      case ObfuscationType.shuffle:
        if (data.length < 2) return data;
        final seed = (data[0] << 8) | data[1];
        final actualData = data.sublist(2);
        final indices = List.generate(actualData.length, (i) => i);
        indices.shuffle(Random(seed));
        final result = Uint8List(actualData.length);
        for (int i = 0; i < actualData.length; i++) {
          result[indices[i]] = actualData[i];
        }
        return result;
    }
  }

  // ==================== FAKE HEADERS ====================

  static Uint8List addFakeHeader(Uint8List data, int headerSize) {
    final header = generateRandomBytes(headerSize);
    final sizeBytes = Uint8List(4);
    sizeBytes.buffer.asByteData().setUint32(0, headerSize, Endian.big);
    return Uint8List.fromList([...sizeBytes, ...header, ...data]);
  }

  static Uint8List removeFakeHeader(Uint8List data) {
    if (data.length < 4) return data;
    final headerSize = data.buffer.asByteData().getUint32(0, Endian.big);
    if (data.length < 4 + headerSize) return data;
    return Uint8List.fromList(data.sublist(4 + headerSize));
  }

  // ==================== FULL PIPELINE ====================

  static Uint8List encryptData(Uint8List data, EncryptionType type, String? key) {
    if (key == null || key.isEmpty || type == EncryptionType.none) return data;
    
    switch (type) {
      case EncryptionType.none:
        return data;
      case EncryptionType.aes256:
        return encryptAES256(data, key);
      case EncryptionType.xor:
        return encryptXOR(data, key);
      case EncryptionType.custom:
        // Custom = AES + XOR double layer
        final aes = encryptAES256(data, key);
        return encryptXOR(aes, key.split('').reversed.join());
    }
  }

  static Uint8List decryptData(Uint8List data, EncryptionType type, String? key) {
    if (key == null || key.isEmpty || type == EncryptionType.none) return data;
    
    switch (type) {
      case EncryptionType.none:
        return data;
      case EncryptionType.aes256:
        return decryptAES256(data, key);
      case EncryptionType.xor:
        return decryptXOR(data, key);
      case EncryptionType.custom:
        final xorDecrypted = decryptXOR(data, key.split('').reversed.join());
        return decryptAES256(xorDecrypted, key);
    }
  }
}
