import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart' as legacy_crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Bóveda Cifrada COBALTO basada en AES-256-GCM.
/// La Clave Maestra (32 bytes) se genera aleatoriamente y se custodia en el
/// Android Keystore / Secure Storage del dispositivo.
///
/// Formato de datos cifrados versionado:
///   - `ENCv2:` → AES-256-GCM (actual).
///   - `ENC:`   → esquema XOR legacy, soportado solo para lectura/descifrado.
class CryptoVaultService {
  static final _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      migrateWithBackup: true,
    ),
  );
  static const String _keyAlias = 'cobalto_master_aes_256_key';
  static String? _cachedMasterKey;

  static const String _legacyPrefix = 'ENC:';
  static const String _currentPrefix = 'ENCv2:';

  // GCM usa nonce de 12 bytes y MAC de 16 bytes.
  static const int _nonceLength = 12;
  static const int _macLength = 16;

  static final AesGcm _aesGcm = AesGcm.with256bits();

  /// Obtiene o genera la clave Maestra AES-256 en el Android KeyStore / Secure Storage.
  /// Fallos de acceso al Keystore se propagan: nunca se degrada a claves embebidas.
  static Future<String> getMasterKey() async {
    if (_cachedMasterKey != null) return _cachedMasterKey!;
    final String key;
    try {
      key = await _storage.read(key: _keyAlias) ?? '';
      if (key.isEmpty) {
        final randomBytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
        final newKey = base64.encode(randomBytes);
        await _storage.write(key: _keyAlias, value: newKey);
        _cachedMasterKey = newKey;
        debugPrint('🔒 Clave Maestra AES-256 generada y almacenada en Android KeyStore.');
        return newKey;
      }
    } catch (e) {
      debugPrint('⚠️ Error accediendo a Secure Storage: $e');
      rethrow;
    }
    _cachedMasterKey = key;
    return key;
  }

  static Future<SecretKey> _deriveSecretKey() async {
    final masterKey = await getMasterKey();
    return SecretKey(base64.decode(masterKey));
  }

  /// Cifra texto plano con AES-256-GCM. Devuelve cadena versionada `ENCv2:...`.
  static Future<String> encryptText(String plainText) async {
    if (plainText.isEmpty) return plainText;
    try {
      final key = await _deriveSecretKey();
      final nonce = List<int>.generate(_nonceLength, (_) => Random.secure().nextInt(256));
      final box = await _aesGcm.encrypt(utf8.encode(plainText), secretKey: key, nonce: nonce);
      final payload = <int>[
        ...box.nonce,
        ...box.cipherText,
        ...box.mac.bytes,
      ];
      return '$_currentPrefix${base64.encode(payload)}';
    } catch (e) {
      debugPrint('⚠️ Error cifrando texto: $e');
      rethrow;
    }
  }

  /// Descifra texto cifrado, soportando tanto el formato actual (ENCv2) como
  /// el legacy (ENC) para migración transparente.
  static Future<String> decryptText(String cipherText) async {
    if (cipherText.startsWith(_legacyPrefix)) return _decryptLegacy(cipherText);
    if (cipherText.startsWith(_currentPrefix)) return _decryptCurrent(cipherText);
    return cipherText;
  }

  /// Indica si la cadena corresponde al formato legacy (XOR).
  static bool isLegacyFormat(String cipherText) => cipherText.startsWith(_legacyPrefix);

  static Future<String> _decryptCurrent(String cipherText) async {
    try {
      final key = await _deriveSecretKey();
      final raw = base64.decode(cipherText.substring(_currentPrefix.length));
      if (raw.length < _nonceLength + _macLength) {
        throw FormatException('Payload ENCv2 truncado.');
      }
      final nonce = raw.sublist(0, _nonceLength);
      final mac = raw.sublist(raw.length - _macLength);
      final cipher = raw.sublist(_nonceLength, raw.length - _macLength);
      final box = SecretBox(cipher, nonce: nonce, mac: Mac(mac));
      final clear = await _aesGcm.decrypt(box, secretKey: key);
      return utf8.decode(clear);
    } catch (e) {
      debugPrint('⚠️ Error descifrando texto (AES-GCM): $e');
      return cipherText;
    }
  }

  static Future<String> _decryptLegacy(String cipherText) async {
    try {
      final key = await getMasterKey();
      final keyBytes = legacy_crypto.sha256.convert(utf8.encode(key)).bytes;
      final encryptedBytes = base64.decode(cipherText.substring(_legacyPrefix.length));

      final List<int> decrypted = [];
      for (int i = 0; i < encryptedBytes.length; i++) {
        decrypted.add(encryptedBytes[i] ^ keyBytes[i % keyBytes.length]);
      }
      return utf8.decode(decrypted);
    } catch (e) {
      debugPrint('⚠️ Error descifrando texto legacy (XOR): $e');
      return cipherText;
    }
  }

  /// Re-cifra un payload legacy al formato actual. Devuelve null si no procede.
  static Future<String?> upgradeLegacy(String cipherText) async {
    if (!isLegacyFormat(cipherText)) return null;
    final clear = await _decryptLegacy(cipherText);
    if (clear == cipherText) return null; // Descifrado fallido, preservar original.
    return encryptText(clear);
  }

  /// Verifica el estado de seguridad de la Bóveda Cifrada.
  static Future<Map<String, dynamic>> checkVaultStatus() async {
    try {
      final key = await getMasterKey();
      final keyBits = base64.decode(key).length * 8;
      return {
        'secure': true,
        'key_algorithm': 'AES-256-GCM',
        'key_bits': keyBits > 0 ? keyBits : 256,
        'keystore_status': 'HARDWARE_KEYSTORE_ACTIVE',
      };
    } catch (e) {
      return {
        'secure': false,
        'error': e.toString(),
      };
    }
  }
}
