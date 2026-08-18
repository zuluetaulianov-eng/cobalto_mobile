import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as raw_crypto;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Cuenta de Operador Local COBALTO.
///
/// Provee autenticación de entrada a la app totalmente offline: el operador
/// crea una cuenta (nombre de usuario + contraseña) en el propio dispositivo y
/// esta se valida localmente, sin depender del backend. La contraseña se
/// almacena como hash salado (SHA-256 iterado) en Secure Storage.
///
/// La autenticación contra el servidor (JWT) sigue existiendo para las APIs,
/// pero el acceso a la app ya no queda bloqueado si el servidor está ausente.
class LocalAuthService {
  static const _storage = FlutterSecureStorage();

  static const String _usernameKey = 'local_operator_username';
  static const String _saltKey = 'local_operator_salt';
  static const String _hashKey = 'local_operator_hash';
  static const String _duressKey = 'local_operator_duress';

  static const int _minUsernameLength = 3;
  static const int _minPasswordLength = 4;
  static const int _hashIterations = 2048;

  // ── CONSULTA DE ESTADO ──

  /// Indica si ya existe una cuenta de operador configurada.
  static Future<bool> hasLocalUser() async {
    try {
      final user = await _storage.read(key: _usernameKey);
      return user != null && user.isNotEmpty;
    } catch (e) {
      debugPrint('⚠️ No se pudo leer la cuenta local: $e');
      return false;
    }
  }

  /// Devuelve el nombre de usuario del operador local, o null si no existe.
  static Future<String?> getUsername() async {
    try {
      return await _storage.read(key: _usernameKey);
    } catch (e) {
      debugPrint('⚠️ No se pudo leer el usuario local: $e');
      return null;
    }
  }

  // ── CREACIÓN DE CUENTA ──

  /// Crea la cuenta de operador local (solo si aún no existe).
  /// Lanza [ArgumentError] si la contraseña no supera las validaciones.
  /// Lanza [StateError] si ya existe una cuenta configurada.
  static Future<void> createUser(String username, String password) async {
    final user = username.trim();
    if (user.length < _minUsernameLength) {
      throw ArgumentError('El nombre de usuario debe tener al menos $_minUsernameLength caracteres.');
    }
    if (password.length < _minPasswordLength) {
      throw ArgumentError('La contraseña debe tener al menos $_minPasswordLength caracteres.');
    }
    if (await hasLocalUser()) {
      throw StateError('Ya existe un operador local. Use el inicio de sesión o ajústelo en Ajustes.');
    }

    final salt = base64Encode(_randomBytes(16));
    final hash = _derive(password, salt);

    await _storage.write(key: _usernameKey, value: user);
    await _storage.write(key: _saltKey, value: salt);
    await _storage.write(key: _hashKey, value: hash);
  }

  // ── AUTENTICACIÓN ──

  /// Valida las credenciales contra la cuenta local. Devuelve false si no
  /// existe cuenta o si las credenciales no coinciden (comparación constante).
  static Future<bool> verifyLogin(String username, String password) async {
    try {
      final storedUser = await _storage.read(key: _usernameKey);
      final storedSalt = await _storage.read(key: _saltKey);
      final storedHash = await _storage.read(key: _hashKey);
      if (storedUser == null || storedSalt == null || storedHash == null) return false;
      if (storedUser.trim() != username.trim()) return false;

      final candidate = _derive(password, storedSalt);
      return _constantTimeEquals(candidate, storedHash);
    } catch (e) {
      debugPrint('⚠️ Error validando credenciales locales: $e');
      return false;
    }
  }

  // ── COACCIÓN (DURESS) ──

  /// Configura la contraseña de coacción. Si el operador la usa para
  /// desbloquear, la app entra con apariencia normal pero dispara un SOS
  /// silencioso. Devuelve `true` si se registró, `false` si el código es débil.
  static Future<bool> setDuressCode(String code) async {
    if (code.length < _minPasswordLength) return false;
    final salt = base64Encode(_randomBytes(16));
    final hash = _derive(code, salt);
    await _storage.write(key: _duressKey, value: '$salt:$hash');
    return true;
  }

  /// Indica si existe una contraseña de coacción configurada.
  static Future<bool> hasDuressCode() async {
    try {
      final stored = await _storage.read(key: _duressKey);
      return stored != null && stored.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Valida si el código ingresado corresponde a la contraseña de coacción.
  static Future<bool> verifyDuress(String code) async {
    try {
      final stored = await _storage.read(key: _duressKey);
      if (stored == null || stored.isEmpty) return false;
      final separator = stored.lastIndexOf(':');
      if (separator <= 0) return false;
      final salt = stored.substring(0, separator);
      final storedHash = stored.substring(separator + 1);
      final candidate = _derive(code, salt);
      return _constantTimeEquals(candidate, storedHash);
    } catch (e) {
      debugPrint('⚠️ Error validando coacción local: $e');
      return false;
    }
  }

  /// Elimina la contraseña de coacción configurada.
  static Future<void> clearDuressCode() async {
    await _storage.delete(key: _duressKey);
  }

  // ── EDICIÓN DE CREDENCIALES ──

  /// Cambia el nombre de usuario, validando previamente la contraseña actual.
  /// Lanza [StateError] si la contraseña es incorrecta o no hay cuenta.
  static Future<void> changeUsername(String newUsername, String currentPassword) async {
    final user = newUsername.trim();
    if (user.length < _minUsernameLength) {
      throw ArgumentError('El nombre de usuario debe tener al menos $_minUsernameLength caracteres.');
    }
    if (!await verifyLogin(await getUsername() ?? '', currentPassword)) {
      throw StateError('Contraseña actual incorrecta. No se modificó el operador.');
    }
    await _storage.write(key: _usernameKey, value: user);
  }

  /// Cambia la contraseña, validando previamente la contraseña actual.
  /// Lanza [StateError] si la contraseña es incorrecta o no hay cuenta.
  static Future<void> changePassword(String newPassword, String currentPassword) async {
    if (newPassword.length < _minPasswordLength) {
      throw ArgumentError('La contraseña debe tener al menos $_minPasswordLength caracteres.');
    }
    if (!await verifyLogin(await getUsername() ?? '', currentPassword)) {
      throw StateError('Contraseña actual incorrecta. No se modificó la contraseña.');
    }

    final salt = base64Encode(_randomBytes(16));
    final hash = _derive(newPassword, salt);
    await _storage.write(key: _saltKey, value: salt);
    await _storage.write(key: _hashKey, value: hash);
  }

  // ── INTERNOS ──

  static List<int> _randomBytes(int length) {
    return List<int>.generate(length, (_) => Random.secure().nextInt(256));
  }

  /// Deriva un hash salado de la contraseña usando SHA-256 iterado.
  static String _derive(String password, String salt) {
    var digest = raw_crypto.sha256.convert(utf8.encode('$salt:$password'));
    for (int i = 0; i < _hashIterations; i++) {
      digest = raw_crypto.sha256.convert(digest.bytes);
    }
    return base64.encode(digest.bytes);
  }

  /// Compara dos cadenas en tiempo constante (evita timing attacks).
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}