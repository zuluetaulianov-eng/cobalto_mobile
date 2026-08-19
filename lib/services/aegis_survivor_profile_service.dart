import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import 'crypto_vault_service.dart';
import 'local_db_service.dart';

/// Perfil de sobreviviente AEGIS: datos médicos críticos (tipo de sangre,
/// alergias, condiciones) que viajarán en el paquete de "caja negra" hacia
/// los equipos de rescate.
///
/// Toda la información se cifra en reposo con la bóveda AES-256-GCM
/// ([CryptoVaultService]) antes de persistir en SQLite; nunca en claro.
class AegisSurvivorProfileService {
  static const String _dbId = '1';

  static Future<void> saveProfile({
    String bloodType = '',
    String allergies = '',
    String medicalConditions = '',
    String notes = '',
  }) async {
    final encrypted = <String, dynamic>{
      'blood_type': await _encrypt(bloodType),
      'allergies': await _encrypt(allergies),
      'medical_conditions': await _encrypt(medicalConditions),
      'notes': await _encrypt(notes),
      'updated_at': DateTime.now().toIso8601String(),
    };

    try {
      final db = await LocalDbService.database;
      await db.insert(
        'survivor_profile',
        {
          'id': _dbId,
          ...encrypted,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('⚠️ No se pudo guardar el perfil de sobreviviente: $e');
    }
  }

  static Future<Map<String, dynamic>> loadProfile() async {
    final empty = <String, dynamic>{
      'blood_type': '',
      'allergies': '',
      'medical_conditions': '',
      'notes': '',
      'updated_at': '',
    };
    try {
      final db = await LocalDbService.database;
      final rows = await db.query(
        'survivor_profile',
        where: 'id = ?',
        whereArgs: [_dbId],
        limit: 1,
      );
      if (rows.isEmpty) return empty;
      final row = rows.first;
      return {
        'blood_type': await _decrypt(row['blood_type']?.toString() ?? ''),
        'allergies': await _decrypt(row['allergies']?.toString() ?? ''),
        'medical_conditions':
            await _decrypt(row['medical_conditions']?.toString() ?? ''),
        'notes': await _decrypt(row['notes']?.toString() ?? ''),
        'updated_at': row['updated_at']?.toString() ?? '',
      };
    } catch (e) {
      debugPrint('⚠️ No se pudo leer el perfil de sobreviviente: $e');
      return empty;
    }
  }

  static Future<String> _encrypt(String plain) async {
    if (plain.isEmpty) return '';
    return CryptoVaultService.encryptText(plain);
  }

  static Future<String> _decrypt(String cipher) async {
    if (cipher.isEmpty) return '';
    if (!cipher.startsWith('ENC')) return cipher;
    return CryptoVaultService.decryptText(cipher);
  }
}
