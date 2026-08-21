import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app_logger.dart';
import 'crypto_vault_service.dart';

/// Identidad criptográfica de un nodo de la red mesh AEGIS.
class AegisMeshIdentity {
  /// ID público del nodo = SHA-256(clave pública Ed25519) hex.
  final String nodeId;

  /// Clave pública Ed25519 (32 bytes, serializada en base64) — firmas.
  final String publicKeyBase64;

  /// Clave pública X25519 (32 bytes, base64) — ECDH/E2EE.
  /// Derivada de la misma semilla; NO es intercambiable con Ed25519.
  final String x25519PublicKeyBase64;

  /// Huella legible para TOFU (primeros 8 bytes del nodeId en mayúsculas).
  String get fingerprint =>
      nodeId.substring(0, 16).toUpperCase().replaceAllMapped(
        RegExp(r'.{4}'),
        (m) => '${m.group(0)} ',
      ).trim();

  const AegisMeshIdentity({
    required this.nodeId,
    required this.publicKeyBase64,
    required this.x25519PublicKeyBase64,
  });

  @override
  String toString() => 'AegisMeshIdentity(nodeId: ${nodeId.substring(0, 8)}..., fp: $fingerprint)';
}

/// Par de contacto de confianza (TOFU).
class AegisTrustedPeer {
  final String nodeId;
  /// Clave pública Ed25519 (firmas).
  final String publicKeyBase64;
  /// Clave pública X25519 (E2EE). Vacía en peers legacy sin pk_x.
  final String x25519PublicKeyBase64;
  final String alias; // Nombre legible (puede ser vacío).
  final DateTime trustedSince;

  const AegisTrustedPeer({
    required this.nodeId,
    required this.publicKeyBase64,
    this.x25519PublicKeyBase64 = '',
    required this.alias,
    required this.trustedSince,
  });

  Map<String, dynamic> toJson() => {
        'node_id': nodeId,
        'public_key': publicKeyBase64,
        'public_key_x25519': x25519PublicKeyBase64,
        'alias': alias,
        'trusted_since': trustedSince.toIso8601String(),
      };

  factory AegisTrustedPeer.fromJson(Map<String, dynamic> json) => AegisTrustedPeer(
        nodeId: json['node_id'] as String,
        publicKeyBase64: json['public_key'] as String,
        x25519PublicKeyBase64: json['public_key_x25519'] as String? ?? '',
        alias: json['alias'] as String? ?? '',
        trustedSince: DateTime.tryParse(json['trusted_since'] as String? ?? '') ?? DateTime.now(),
      );
}

/// CRIPTOGRAFÍA PKI OFFLINE AEGIS (FASE 6a) — 100% puro Dart.
///
/// Implementa el esquema de identidad descentralizada y E2EE del mesh:
///
///  - **Ed25519** (package:cryptography): firmas de mensajes y autenticidad.
///  - **X25519** (package:cryptography): ECDH para acuerdo de clave E2EE.
///  - **AES-256-GCM**: cifrado simétrico del payload (clave derivada por ECDH).
///  - **Identity = SHA-256(pubkey Ed25519)**: sin CA central, sin MAC BLE.
///  - **TOFU**: Trust On First Use por QR fuera de banda. Almacén local cifrado.
///  - **Padding por cubos** (512 B / 2 KB / 8 KB): anti-fingerprinting en BLE.
///  - **Nodos intermedios ciegos**: los relays NUNCA descifran.
///
/// La semilla Ed25519 (32 bytes) se custodia cifrada con la bóveda maestra
/// ([CryptoVaultService] ENCv2) en FlutterSecureStorage.
/// Trade-off documentado: se usa Secure Storage (no hardware Keystore) para
/// portabilidad Dart entre plataformas. En Fase 6a este es el baseline;
/// Keystore hardware puede añadirse en un hardening posterior sin cambiar la API.
class AegisMeshCryptoService {
  // ── ALGORITMOS ──
  static final Ed25519 _ed25519 = Ed25519();
  static final X25519 _x25519 = X25519();
  static final AesGcm _aesGcm = AesGcm.with256bits();

  static const String _seedAlias = 'aegis_mesh_seed_v1';
  static const String _trustedPeersAlias = 'aegis_mesh_trusted_peers_v1';
  static const String _encPrefix = 'ENCv2:';

  static final FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      migrateWithBackup: true,
    ),
  );

  // Caché en memoria (evita múltiples hits a SecureStorage por sesión).
  static AegisMeshIdentity? _cachedIdentity;
  static SimpleKeyPair? _cachedKeyPairEd25519;
  static SimpleKeyPair? _cachedKeyPairX25519;

  // ── CUBOS DE PADDING (anti-fingerprinting BLE) ──
  static const List<int> _paddingBuckets = [512, 2048, 8192];

  // ── GENERACIÓN / RECUPERACIÓN DE IDENTIDAD ──

  /// Carga o genera la identidad del nodo (idempotente).
  ///
  /// Primera vez: genera semilla aleatoria segura (32 bytes), la cifra con
  /// [CryptoVaultService] y la guarda en SecureStorage.
  /// Siguientes veces: recupera y descifra la semilla almacenada.
  static Future<AegisMeshIdentity> getOrCreateIdentity() async {
    if (_cachedIdentity != null) return _cachedIdentity!;

    final seed = await _getOrCreateSeed();
    final keyPair = await _ed25519.newKeyPairFromSeed(seed);
    _cachedKeyPairEd25519 = keyPair;

    final pubKey = await keyPair.extractPublicKey();
    final pubKeyBytes = pubKey.bytes;
    final nodeId = await _sha256Hex(pubKeyBytes);
    final pubKeyBase64 = base64.encode(pubKeyBytes);

    // Par X25519 independiente (misma semilla) — claves NO intercambiables con Ed25519.
    final xKp = await _x25519.newKeyPairFromSeed(seed);
    _cachedKeyPairX25519 = xKp;
    final xPub = await xKp.extractPublicKey();
    final xPubBase64 = base64.encode(xPub.bytes);

    _cachedIdentity = AegisMeshIdentity(
      nodeId: nodeId,
      publicKeyBase64: pubKeyBase64,
      x25519PublicKeyBase64: xPubBase64,
    );
    AppLogger.info('Identidad mesh cargada: ${_cachedIdentity!.fingerprint}', tag: 'MeshCrypto');
    return _cachedIdentity!;
  }

  /// Genera o recupera la semilla Ed25519/X25519 (32 bytes).
  static Future<List<int>> _getOrCreateSeed() async {
    try {
      final stored = await _secureStorage.read(key: _seedAlias);
      if (stored != null && stored.isNotEmpty) {
        final clear = await CryptoVaultService.decryptText(stored);
        // Formato actual: base64 crudo de 32 bytes.
        // Legacy: 'ENCv2:' + base64 (doble prefijo accidental).
        final payload = clear.startsWith(_encPrefix)
            ? clear.substring(_encPrefix.length)
            : clear;
        final seed = base64.decode(payload);
        if (seed.length == 32) return seed;
      }
    } catch (e) {
      AppLogger.warn('No se pudo recuperar la semilla mesh; generando nueva.', tag: 'MeshCrypto', error: e);
    }

    // Generar nueva semilla segura y cifrar solo el base64 de la semilla.
    final seed = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    final sealed = await CryptoVaultService.encryptText(base64.encode(seed));
    try {
      await _secureStorage.write(key: _seedAlias, value: sealed);
    } catch (e) {
      AppLogger.warn('No se pudo persistir la semilla mesh.', tag: 'MeshCrypto', error: e);
    }
    return seed;
  }

  /// Par X25519 derivado de la misma semilla Ed25519.
  /// Se usa para el acuerdo ECDH de la clave de sesión.
  static Future<SimpleKeyPair> _getX25519KeyPair() async {
    if (_cachedKeyPairX25519 != null) return _cachedKeyPairX25519!;
    await getOrCreateIdentity(); // carga ambos pares
    return _cachedKeyPairX25519!;
  }

  // ── FIRMA / VERIFICACIÓN (Ed25519) ──

  /// Firma [message] con la clave Ed25519 del nodo local.
  /// Retorna la firma como lista de bytes (64 bytes).
  static Future<List<int>> sign(List<int> message) async {
    final identity = await getOrCreateIdentity(); // Asegura que el par está cargado.
    final kp = _cachedKeyPairEd25519!;
    final sig = await _ed25519.sign(message, keyPair: kp);
    debugPrint('✍️ Mensaje firmado con identidad ${identity.fingerprint}');
    return sig.bytes;
  }

  /// Verifica la firma [signatureBytes] de [message] con la clave pública [publicKeyBase64].
  /// Retorna true si la firma es válida.
  static Future<bool> verify({
    required List<int> message,
    required List<int> signatureBytes,
    required String publicKeyBase64,
  }) async {
    try {
      final pubKeyBytes = base64.decode(publicKeyBase64);
      final pubKey = SimplePublicKey(pubKeyBytes, type: KeyPairType.ed25519);
      final sig = Signature(signatureBytes, publicKey: pubKey);
      return await _ed25519.verify(message, signature: sig);
    } catch (e) {
      AppLogger.warn('Verificación de firma fallida.', tag: 'MeshCrypto', error: e);
      return false;
    }
  }

  // ── E2EE: ECDH → AES-GCM ──

  /// Cifra [plaintext] para el destinatario con clave pública **X25519** [recipientX25519PubKeyBase64].
  ///
  /// Flujo: ECDH(ephemeral_X25519, recipient_X25519) → sharedSecret → AES-256-GCM(plaintext).
  /// El payload se rellena a cubos de tamaño para anti-fingerprinting.
  ///
  /// Formato del sobre cifrado (bytes):
  ///   [32B ephemeral_pubkey][12B nonce][4B ciphertext_len][ciphertext+mac][padding]
  ///
  /// Retorna el sobre como base64 con prefijo `E2E:`.
  ///
  /// IMPORTANTE: pasar la clave X25519 del peer (`peer.x25519PublicKeyBase64`),
  /// nunca la Ed25519 (`publicKeyBase64`).
  static Future<String> encryptForPeer({
    required String plaintext,
    required String recipientPubKeyBase64,
  }) async {
    try {
      // 1. Par efímero X25519 (nuevo para cada mensaje: forward secrecy).
      final ephemeralKp = await _x25519.newKeyPair();
      final ephemeralPub = await ephemeralKp.extractPublicKey();

      // 2. ECDH: secreto compartido (recipient DEBE ser X25519).
      final recipientPubBytes = base64.decode(recipientPubKeyBase64);
      if (recipientPubBytes.length != 32) {
        throw ArgumentError(
          'Clave X25519 del destinatario inválida (${recipientPubBytes.length} bytes).',
        );
      }
      final recipientPub = SimplePublicKey(recipientPubBytes, type: KeyPairType.x25519);
      final sharedSecret = await _x25519.sharedSecretKey(keyPair: ephemeralKp, remotePublicKey: recipientPub);

      // 3. Derivar clave AES-256-GCM desde el secreto compartido (HKDF ligero: SHA-256).
      final sharedBytes = await sharedSecret.extractBytes();
      final aesKeyBytes = await _hkdfLite(sharedBytes, info: 'aegis-e2ee-v1');
      final aesKey = SecretKey(aesKeyBytes);

      // 4. Cifrar.
      final plaintextBytes = utf8.encode(plaintext);
      final nonce = List<int>.generate(12, (_) => Random.secure().nextInt(256));
      final box = await _aesGcm.encrypt(plaintextBytes, secretKey: aesKey, nonce: nonce);

      // 5. Serializar sobre.
      final cipherWithMac = [...box.cipherText, ...box.mac.bytes]; // cipher + 16B mac
      final cipherLen = cipherWithMac.length;
      final envelope = [
        ...ephemeralPub.bytes,               // 32B pubkey efímera
        ...nonce,                             // 12B nonce
        (cipherLen >> 24) & 0xFF,            // 4B longitud (big-endian)
        (cipherLen >> 16) & 0xFF,
        (cipherLen >> 8) & 0xFF,
        cipherLen & 0xFF,
        ...cipherWithMac,                     // payload cifrado + mac
      ];

      // 6. Padding por cubos (anti-fingerprinting).
      final padded = _padToBucket(envelope);
      return 'E2E:${base64.encode(padded)}';
    } catch (e) {
      AppLogger.warn('E2EE encryptForPeer fallido.', tag: 'MeshCrypto', error: e);
      rethrow;
    }
  }

  /// Descifra un sobre `E2E:...` con la clave X25519 local.
  static Future<String> decryptFromPeer(String envelopeBase64) async {
    if (!envelopeBase64.startsWith('E2E:')) {
      throw ArgumentError('No es un sobre E2EE válido (falta prefijo E2E:)');
    }
    try {
      final raw = base64.decode(envelopeBase64.substring(4));
      if (raw.length < 32 + 12 + 4 + 16) {
        throw StateError('Sobre E2EE demasiado corto: ${raw.length} bytes');
      }

      // Extraer componentes.
      final ephemeralPubBytes = raw.sublist(0, 32);
      final nonce = raw.sublist(32, 44);
      final cipherLen = (raw[44] << 24) | (raw[45] << 16) | (raw[46] << 8) | raw[47];
      if (raw.length < 48 + cipherLen) {
        throw StateError('Sobre truncado: se esperaban ${48 + cipherLen} bytes, hay ${raw.length}');
      }
      final cipherWithMac = raw.sublist(48, 48 + cipherLen);

      // ECDH con clave local.
      final localKp = await _getX25519KeyPair();
      final ephemeralPub = SimplePublicKey(ephemeralPubBytes, type: KeyPairType.x25519);
      final sharedSecret = await _x25519.sharedSecretKey(keyPair: localKp, remotePublicKey: ephemeralPub);
      final sharedBytes = await sharedSecret.extractBytes();
      final aesKeyBytes = await _hkdfLite(sharedBytes, info: 'aegis-e2ee-v1');
      final aesKey = SecretKey(aesKeyBytes);

      // Descifrar.
      final mac = Mac(cipherWithMac.sublist(cipherWithMac.length - 16));
      final cipher = cipherWithMac.sublist(0, cipherWithMac.length - 16);
      final plain = await _aesGcm.decrypt(
        SecretBox(cipher, nonce: nonce, mac: mac),
        secretKey: aesKey,
      );
      return utf8.decode(plain);
    } catch (e) {
      AppLogger.warn('E2EE decryptFromPeer fallido.', tag: 'MeshCrypto', error: e);
      rethrow;
    }
  }

  // ── QR TOFU ──

  /// Genera el payload QR de presentación del nodo local.
  /// Formato: JSON con nodeId, pk Ed25519, pk_x X25519, alias y timestamp.
  static Future<String> generateQrPayload({String alias = ''}) async {
    final identity = await getOrCreateIdentity();
    return json.encode({
      'v': 1,
      'nid': identity.nodeId,
      'pk': identity.publicKeyBase64,
      'pk_x': identity.x25519PublicKeyBase64,
      'alias': alias,
      'ts': DateTime.now().toUtc().millisecondsSinceEpoch,
    });
  }

  /// Parsea y valida un payload QR de otro nodo.
  /// Retorna el [AegisTrustedPeer] si el QR es válido, null si es inválido.
  static Future<AegisTrustedPeer?> parseQrPayload(String qrPayload) async {
    try {
      final data = json.decode(qrPayload) as Map<String, dynamic>;
      final version = data['v'] as int? ?? 0;
      if (version != 1) {
        AppLogger.warn('QR TOFU: versión no soportada ($version).', tag: 'MeshCrypto');
        return null;
      }
      final nodeId = data['nid'] as String?;
      final pubKeyBase64 = data['pk'] as String?;
      if (nodeId == null || pubKeyBase64 == null) return null;

      // Verificar que nodeId = SHA-256(pubKey Ed25519).
      final pubKeyBytes = base64.decode(pubKeyBase64);
      final expectedId = await _sha256Hex(pubKeyBytes);
      if (expectedId != nodeId) {
        AppLogger.warn('QR TOFU: nodeId no coincide con hash(pubKey).', tag: 'MeshCrypto');
        return null;
      }

      final pkX = data['pk_x'] as String? ?? '';

      return AegisTrustedPeer(
        nodeId: nodeId,
        publicKeyBase64: pubKeyBase64,
        x25519PublicKeyBase64: pkX,
        alias: data['alias'] as String? ?? '',
        trustedSince: DateTime.now().toUtc(),
      );
    } catch (e) {
      AppLogger.warn('QR TOFU: error parseando payload.', tag: 'MeshCrypto', error: e);
      return null;
    }
  }

  // ── ALMACÉN TOFU (TRUSTED PEERS) ──

  /// Añade un peer de confianza al almacén local cifrado.
  static Future<void> trustPeer(AegisTrustedPeer peer) async {
    final peers = await getTrustedPeers();
    // Evitar duplicados; actualizar si ya existe.
    peers.removeWhere((p) => p.nodeId == peer.nodeId);
    peers.add(peer);
    await _savePeers(peers);
    AppLogger.info('TOFU: peer ${peer.nodeId.substring(0, 8)}... añadido.', tag: 'MeshCrypto');
  }

  /// Elimina un peer de confianza.
  static Future<void> removePeer(String nodeId) async {
    final peers = await getTrustedPeers();
    peers.removeWhere((p) => p.nodeId == nodeId);
    await _savePeers(peers);
  }

  /// Recupera todos los peers de confianza.
  static Future<List<AegisTrustedPeer>> getTrustedPeers() async {
    try {
      final stored = await _secureStorage.read(key: _trustedPeersAlias);
      if (stored == null || stored.isEmpty) return [];
      final clear = await CryptoVaultService.decryptText(stored);
      final list = json.decode(clear) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(AegisTrustedPeer.fromJson)
          .toList();
    } catch (e) {
      AppLogger.warn('No se pudo recuperar peers TOFU.', tag: 'MeshCrypto', error: e);
      return [];
    }
  }

  /// Busca un peer por nodeId.
  static Future<AegisTrustedPeer?> findPeer(String nodeId) async {
    final peers = await getTrustedPeers();
    try {
      return peers.firstWhere((p) => p.nodeId == nodeId);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _savePeers(List<AegisTrustedPeer> peers) async {
    final jsonStr = json.encode(peers.map((p) => p.toJson()).toList());
    final sealed = await CryptoVaultService.encryptText(jsonStr);
    await _secureStorage.write(key: _trustedPeersAlias, value: sealed);
  }

  // ── UTILIDADES INTERNAS ──

  /// SHA-256 de [bytes] retornado como hex lowercase.
  static Future<String> _sha256Hex(List<int> bytes) async {
    final hash = await Sha256().hash(bytes);
    return hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// HKDF mínimo: SHA-256(sharedSecret || info) como clave AES-256.
  /// Solo para derivación interna; en Fase 6 se puede sustituir por HKDF completo.
  static Future<List<int>> _hkdfLite(List<int> ikm, {required String info}) async {
    final infoBytes = utf8.encode(info);
    final hash = await Sha256().hash([...ikm, ...infoBytes]);
    return hash.bytes; // 32 bytes = 256 bits para AES-256-GCM.
  }

  /// Rellena [data] al bucket más pequeño ≥ su longitud (anti-fingerprinting).
  static List<int> _padToBucket(List<int> data) {
    final target = _paddingBuckets.firstWhere(
      (b) => b >= data.length,
      orElse: () => data.length, // Si supera 8 KB, sin padding.
    );
    if (target <= data.length) return data;
    final padding = List<int>.generate(target - data.length, (_) => Random.secure().nextInt(256));
    return [...data, ...padding];
  }

  // ── EXPORTACIÓN PÚBLICA DE IDENTIDAD ──

  /// Exporta la clave pública del nodo como bytes crudos (para incluir en protos).
  static Future<List<int>> getPublicKeyBytes() async {
    final identity = await getOrCreateIdentity();
    return base64.decode(identity.publicKeyBase64);
  }

  /// Exporta la identidad como mapa legible para la UI.
  static Future<Map<String, String>> getIdentityInfo() async {
    final identity = await getOrCreateIdentity();
    return {
      'node_id': identity.nodeId,
      'fingerprint': identity.fingerprint,
      'public_key': identity.publicKeyBase64,
      'public_key_x25519': identity.x25519PublicKeyBase64,
    };
  }

  /// Limpia la caché en memoria (llamar al cerrar sesión o en tests).
  static void clearCache() {
    _cachedIdentity = null;
    _cachedKeyPairEd25519 = null;
    _cachedKeyPairX25519 = null;
  }
}
