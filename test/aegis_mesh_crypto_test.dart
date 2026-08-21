import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:cobalto_mobile/services/aegis_mesh_crypto_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Tests unitarios — Fase 6a (PKI offline & E2EE Criptografía Mesh)
///
/// TODOS puro Dart: validan las funciones criptográficas y el contrato de identidad.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    AegisMeshCryptoService.clearCache();
  });

  group('AegisMeshCryptoService — Identidad & Firmas Ed25519', () {
    tearDown(() {
      AegisMeshCryptoService.clearCache();
    });

    test('getOrCreateIdentity devuelve un nodeId de 64 caracteres hex (SHA-256)', () async {
      final identity = await AegisMeshCryptoService.getOrCreateIdentity();
      expect(identity.nodeId.length, equals(64));
      expect(RegExp(r'^[a-f0-9]{64}$').hasMatch(identity.nodeId), isTrue);
      expect(identity.publicKeyBase64, isNotEmpty);
      expect(identity.fingerprint, isNotEmpty);
    });

    test('fingerprint formatea los primeros 16 caracteres hex en bloques de 4', () async {
      final identity = await AegisMeshCryptoService.getOrCreateIdentity();
      final fp = identity.fingerprint;
      // Ejemplo: "A1B2 C3D4 E5F6 7890"
      final parts = fp.split(' ');
      expect(parts.length, equals(4));
      for (final p in parts) {
        expect(p.length, equals(4));
      }
    });

    test('sign() y verify() con firma válida retornan true', () async {
      final identity = await AegisMeshCryptoService.getOrCreateIdentity();
      final message = utf8.encode('Mensaje de prueba AEGIS');

      final sigBytes = await AegisMeshCryptoService.sign(message);
      expect(sigBytes.length, equals(64)); // Firma Ed25519 = 64 bytes

      final isValid = await AegisMeshCryptoService.verify(
        message: message,
        signatureBytes: sigBytes,
        publicKeyBase64: identity.publicKeyBase64,
      );
      expect(isValid, isTrue);
    });

    test('verify() rechaza mensaje alterado', () async {
      final identity = await AegisMeshCryptoService.getOrCreateIdentity();
      final original = utf8.encode('Mensaje original');
      final tampered = utf8.encode('Mensaje ALTERADO');

      final sigBytes = await AegisMeshCryptoService.sign(original);

      final isValid = await AegisMeshCryptoService.verify(
        message: tampered,
        signatureBytes: sigBytes,
        publicKeyBase64: identity.publicKeyBase64,
      );
      expect(isValid, isFalse);
    });
  });

  group('AegisMeshCryptoService — QR TOFU & Trusted Peers', () {
    test('generateQrPayload y parseQrPayload procesan correctamente la identidad', () async {
      final identity = await AegisMeshCryptoService.getOrCreateIdentity();
      final qr = await AegisMeshCryptoService.generateQrPayload(alias: 'NodoAlfa');

      final peer = await AegisMeshCryptoService.parseQrPayload(qr);
      expect(peer, isNotNull);
      expect(peer!.nodeId, equals(identity.nodeId));
      expect(peer.publicKeyBase64, equals(identity.publicKeyBase64));
      expect(peer.alias, equals('NodoAlfa'));
    });

    test('parseQrPayload rechaza JSON corrupto o invalido', () async {
      final invalid = await AegisMeshCryptoService.parseQrPayload('{"invalid": true}');
      expect(invalid, isNull);
    });

    test('parseQrPayload rechaza si nid no coincide con hash(pubKey)', () async {
      final identity = await AegisMeshCryptoService.getOrCreateIdentity();
      final fakeQr = json.encode({
        'v': 1,
        'nid': '0000000000000000000000000000000000000000000000000000000000000000',
        'pk': identity.publicKeyBase64,
        'alias': 'Falso',
        'ts': DateTime.now().millisecondsSinceEpoch,
      });

      final peer = await AegisMeshCryptoService.parseQrPayload(fakeQr);
      expect(peer, isNull, reason: 'Debe rechazar si el Node ID no es el SHA-256 de la PubKey');
    });
  });
}
