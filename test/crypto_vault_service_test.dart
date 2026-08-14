import 'dart:convert';

import 'package:crypto/crypto.dart' as legacy_crypto;
import 'package:cobalto_mobile/services/crypto_vault_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Semilla determinista de la clave maestra para reproducibilidad.
    final masterKey = base64.encode(List<int>.generate(32, (i) => i));
    FlutterSecureStorage.setMockInitialValues({
      'cobalto_master_aes_256_key': masterKey,
    });
  });

  test('encryptText/decryptText roundtrip con AES-256-GCM', () async {
    const plain = 'Reporte CONFIDENCIAL: coord 10.480593, -66.903606';
    final enc = await CryptoVaultService.encryptText(plain);
    expect(enc, startsWith('ENCv2:'));
    final dec = await CryptoVaultService.decryptText(enc);
    expect(dec, plain);
  });

  test('mismo texto produce cifrados distintos (nonce aleatorio)', () async {
    const plain = 'mensaje repetido';
    final a = await CryptoVaultService.encryptText(plain);
    final b = await CryptoVaultService.encryptText(plain);
    expect(a, isNot(b));
  });

  test('texto vacío no se cifra', () async {
    expect(await CryptoVaultService.encryptText(''), '');
  });

  test('texto no cifrado se devuelve tal cual', () async {
    expect(await CryptoVaultService.decryptText('texto-plano'), 'texto-plano');
  });

  test('upgradeLegacy migra payload XOR legacy a AES-GCM', () async {
    const plain = 'histórico legacy';
    final keyStr = await CryptoVaultService.getMasterKey();
    final keyBytes = legacy_crypto.sha256.convert(utf8.encode(keyStr)).bytes;
    final clearBytes = utf8.encode(plain);
    final legacyBytes = <int>[
      for (var i = 0; i < clearBytes.length; i++)
        clearBytes[i] ^ keyBytes[i % keyBytes.length],
    ];
    final legacyCipher = 'ENC:${base64.encode(legacyBytes)}';

    // Lectura transparente del formato legacy.
    expect(await CryptoVaultService.decryptText(legacyCipher), plain);
    expect(CryptoVaultService.isLegacyFormat(legacyCipher), isTrue);

    // Migración al formato actual.
    final upgraded = await CryptoVaultService.upgradeLegacy(legacyCipher);
    expect(upgraded, isNotNull);
    final migrated = upgraded as String;
    expect(migrated, startsWith('ENCv2:'));
    expect(await CryptoVaultService.decryptText(migrated), plain);
    expect(CryptoVaultService.isLegacyFormat(migrated), isFalse);
  });

  test('checkVaultStatus reporta AES-256-GCM', () async {
    final status = await CryptoVaultService.checkVaultStatus();
    expect(status['secure'], isTrue);
    expect(status['key_algorithm'], 'AES-256-GCM');
  });
}