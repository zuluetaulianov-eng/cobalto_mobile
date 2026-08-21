import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'aegis_battery_service.dart';
import 'aegis_survivor_profile_service.dart';
import 'app_logger.dart';
import 'cobalto_api_service.dart';
import 'crypto_vault_service.dart';
import 'gps_service.dart';
import 'local_db_service.dart';
import 'tactical_camera_service.dart';

/// CAJA NEGRA AEGIS (FASE 3): evidencia y telemetría de supervivencia que
/// viaja en cola offline hasta que haya enlace con el nodo central.
///
///  - **Fotos silenciosas continuas**: captura periódica de contexto con el
///    estampado de telemetría existente ([TacticalCameraService]) — sin sonido
///    de obturador, sin UI. Reutiliza la cola de subida de FieldReports.
///  - **Paquete cifrado AEGIS**: batería + GPS (lat/lon/altitud/precisión/
///    rumbo/velocidad) + perfil de sobreviviente (tipo de sangre, alergias,
///    condiciones), cifrado AES-256-GCM con la **clave de transporte** del
///    equipo de rescate (no la clave maestra del dispositivo). Si no hay
///    enlace, queda encolado y se reintenta al arrancar.
///
/// La clave de transporte se custodia cifrada con la bóveda del dispositivo
/// y debe coincidir con la que el equipo de rescate/usuario provisiona en la
/// base (vía [setTransportKey]). En FASE 6a será sustituida por PKI offline.
class AegisBlackBoxService {
  static const String _enabledKey = 'aegis_blackbox_enabled';
  static const String _photoIntervalMinKey = 'aegis_blackbox_photo_interval_min';
  static const String _packageIntervalMinKey = 'aegis_blackbox_package_interval_min';
  static const String _minBatteryKey = 'aegis_blackbox_min_battery';
  static const String _pendingQueueKey = 'pending_aegis_blackbox';
  static const String _lastSeqKey = 'aegis_blackbox_last_seq';
  static const String _transportKeyAlias = 'aegis_blackbox_transport_key';

  static const String _transportPrefix = 'TRA:';
  static const int _nonceLength = 12;
  static const int _macLength = 16;
  static final AesGcm _aesGcm = AesGcm.with256bits();
  static final FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      migrateWithBackup: true,
    ),
  );

  static Timer? _photoTimer;
  static Timer? _packageTimer;

  /// Último paquete emitido (para monitoreo/UI futura).
  static final ValueNotifier<Map<String, dynamic>?> lastPackage =
      ValueNotifier<Map<String, dynamic>?>(null);

  // ── CONFIGURACIÓN PERSISTENTE ──

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? true;
  }

  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
    if (enabled) {
      unawaited(startMonitoring());
    } else {
      stopMonitoring();
    }
  }

  static Future<int> photoIntervalMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_photoIntervalMinKey) ?? 30;
  }

  static Future<void> setPhotoIntervalMinutes(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_photoIntervalMinKey, minutes);
    unawaited(startMonitoring());
  }

  static Future<int> packageIntervalMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_packageIntervalMinKey) ?? 15;
  }

  static Future<void> setPackageIntervalMinutes(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_packageIntervalMinKey, minutes);
    unawaited(startMonitoring());
  }

  static Future<int> minBatteryPercent() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_minBatteryKey) ?? 15;
  }

  static Future<void> setMinBatteryPercent(int percent) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_minBatteryKey, percent);
  }

  // ── CLAVE DE TRANSPORTE (compartida con el equipo de rescate) ──

  /// Clave de transporte para el paquete. Se genera una vez (32 bytes) y se
  /// custodia CIFRADA con la bóveda maestra del dispositivo. La base debe
  /// conocer la misma clave (provisionada por el operador).
  static Future<String> _getTransportKey() async {
    String? cached;
    try {
      cached = await _secureStorage.read(key: _transportKeyAlias);
    } catch (e) {
      AppLogger.warn('No se pudo leer la clave de transporte.', tag: 'BlackBox', error: e);
    }
    if (cached != null && cached.isNotEmpty) {
      final clear = await CryptoVaultService.decryptText(cached);
      if (clear.startsWith(_transportPrefix)) return clear.substring(_transportPrefix.length);
    }

    final randomBytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    final newKey = base64.encode(randomBytes);
    final sealed = await CryptoVaultService.encryptText('$_transportPrefix$newKey');
    try {
      await _secureStorage.write(key: _transportKeyAlias, value: sealed);
    } catch (e) {
      AppLogger.warn('No se pudo custodiar la clave de transporte.', tag: 'BlackBox', error: e);
    }
    return newKey;
  }

  /// Provisiona una clave de transporte compartida con el equipo de rescate
  /// (debe ser la misma que usa la base para descifrar los paquetes).
  static Future<void> setTransportKey(String base64Key) async {
    final sealed = await CryptoVaultService.encryptText('$_transportPrefix$base64Key');
    await _secureStorage.write(key: _transportKeyAlias, value: sealed);
  }

  /// Cifra [plain] con la clave de transporte (AES-256-GCM).
  /// Formato: `TRA:` + base64(nonce + cipher + mac).
  static Future<String> sealForTransport(String plain) async {
    final keyBytes = base64.decode(await _getTransportKey());
    final key = SecretKey(keyBytes);
    final nonce = List<int>.generate(_nonceLength, (_) => Random.secure().nextInt(256));
    final box = await _aesGcm.encrypt(utf8.encode(plain), secretKey: key, nonce: nonce);
    final payload = <int>[...box.nonce, ...box.cipherText, ...box.mac.bytes];
    return '$_transportPrefix${base64.encode(payload)}';
  }

  /// Descifra un paquete [cipher] (`TRA:...`) con la clave de transporte.
  /// Útil para verificar roundtrip en pruebas y para el equipo local.
  static Future<String> openFromTransport(String cipher) async {
    if (!cipher.startsWith(_transportPrefix)) return cipher;
    final keyBytes = base64.decode(await _getTransportKey());
    final key = SecretKey(keyBytes);
    final raw = base64.decode(cipher.substring(_transportPrefix.length));
    if (raw.length < _nonceLength + _macLength) return cipher;
    final nonce = raw.sublist(0, _nonceLength);
    final mac = raw.sublist(raw.length - _macLength);
    final sealed = raw.sublist(_nonceLength, raw.length - _macLength);
    try {
      final clear = await _aesGcm.decrypt(SecretBox(sealed, nonce: nonce, mac: Mac(mac)), secretKey: key);
      return utf8.decode(clear);
    } catch (e) {
      AppLogger.warn('Fallo al abrir paquete de transporte.', tag: 'BlackBox', error: e);
      return cipher;
    }
  }

  // ── PAQUETE CIFRADO ──

  static Future<Map<String, dynamic>> _freshSnapshot() async {
    final cached = GpsService.lastSnapshot;
    if (cached != null &&
        DateTime.now().toUtc().difference(cached.timestampUtc).inSeconds <= 120) {
      return _snapshotToMap(cached);
    }
    try {
      await GpsService.getCurrentPosition();
    } catch (e) {
      // Se conserva lo que haya.
    }
    return _snapshotToMap(GpsService.lastSnapshot);
  }

  static Map<String, dynamic> _snapshotToMap(TacticalSnapshot? s) => {
        if (s != null) ...{
          'lat': s.lat,
          'lon': s.lon,
          'altitude_m': s.altitudeM,
          'accuracy_m': s.accuracyM,
          'heading_deg': s.headingDeg,
          'speed_mps': s.speedMps,
          'gps_utc': s.timestampUtc.toIso8601String(),
        },
      };

  /// Construye y emite (envía + encola si offline) un paquete de caja negra.
  /// Devuelve el sobre (envelope) generado, o null si la caja negra está off.
  static Future<Map<String, dynamic>?> emitPackage() async {
    if (!await isEnabled()) return null;

    // Batería lo más fresca posible.
    final int? battery = await AegisBatteryService.refresh() ??
        GpsService.lastSnapshot?.batteryLevel;

    final Map<String, dynamic> gps = await _freshSnapshot();
    final profile = await AegisSurvivorProfileService.loadProfile();

    final payload = <String, dynamic>{
      'kind': 'aegis_blackbox_payload',
      'utc_ms': DateTime.now().toUtc().millisecondsSinceEpoch,
      'battery_pct': battery,
      ...gps,
      'blood_type': profile['blood_type'],
      'allergies': profile['allergies'],
      'medical_conditions': profile['medical_conditions'],
      'profile_updated': profile['updated_at'],
    };

    final String cipher = await sealForTransport(json.encode(payload));
    final String hash = crypto.sha256.convert(utf8.encode(cipher)).toString();

    final int seq = await _nextSeq();
    final envelope = <String, dynamic>{
      'kind': 'aegis_blackbox_v1',
      'seq': seq,
      'created_utc': DateTime.now().toUtc().toIso8601String(),
      'cipher': cipher,
      'hash_sha256': hash,
    };

    final ok = await CobaltoApiService.sendBlackBoxPackage(envelope);
    if (ok['success'] != true) {
      await _enqueue(envelope);
    }

    lastPackage.value = envelope;
    await LocalDbService.logEmergencyEvent('BLACKBOX_PAQUETE', data: {
      'seq': seq,
      'hash': hash,
      'enviado': ok['success'] == true,
    });
    debugPrint('📦 Paquete AEGIS #$seq emitido (enviado=${ok['success'] == true}).');
    return envelope;
  }

  static Future<int> _nextSeq() async {
    final prefs = await SharedPreferences.getInstance();
    final int last = prefs.getInt(_lastSeqKey) ?? 0;
    final int next = last + 1;
    await prefs.setInt(_lastSeqKey, next);
    return next;
  }

  static Future<void> _enqueue(Map<String, dynamic> envelope) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_pendingQueueKey);
      List<dynamic> queue = [];
      if (raw != null && raw.isNotEmpty) {
        try {
          queue = json.decode(raw);
        } catch (e) {
          // Cola corrupta: se reinicia.
        }
      }
      queue.add(envelope);
      await prefs.setString(_pendingQueueKey, json.encode(queue));
      AppLogger.warn('📦 BlackBox sin enlace: paquete #${envelope['seq']} encolado.', tag: 'BlackBox');
    } catch (e) {
      AppLogger.warn('No se pudo encolar el paquete AEGIS.', tag: 'BlackBox', error: e);
    }
  }

  /// Reintenta los paquetes pendientes persistidos (se invoca al arrancar).
  static Future<void> retryPending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_pendingQueueKey);
      if (raw == null || raw.isEmpty) return;

      final List<dynamic> queue;
      try {
        queue = json.decode(raw);
      } catch (e) {
        await prefs.remove(_pendingQueueKey);
        return;
      }
      if (queue.isEmpty) return;

      final List<dynamic> remaining = [];
      for (final item in queue) {
        if (item is! Map) continue;
        final res = await CobaltoApiService.sendBlackBoxPackage(
          Map<String, dynamic>.from(item),
        );
        if (res['success'] != true) remaining.add(item);
      }
      await prefs.setString(_pendingQueueKey, json.encode(remaining));
      AppLogger.info('Retry de BlackBox completado: ${remaining.length} pendientes.', tag: 'BlackBox');
    } catch (e) {
      AppLogger.warn('Retry de BlackBox fallido.', tag: 'BlackBox', error: e);
    }
  }

  static Future<int> pendingCount() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingQueueKey);
    if (raw == null || raw.isEmpty) return 0;
    try {
      return (json.decode(raw) as List).length;
    } catch (e) {
      return 0;
    }
  }

  // ── FOTOS SILENCIOSAS DE CONTEXTO ──

  /// Captura una foto silenciosa de contexto con estampado de telemetría.
  /// Respeta el umbral de batería mínimo para no agotar el dispositivo.
  /// Devuelve el resultado de la captura (rutas) o null si se omitió.
  static Future<Map<String, dynamic>?> captureSilentContextPhoto() async {
    if (!await isEnabled()) return null;

    final int minBattery = await minBatteryPercent();
    final int? level = await AegisBatteryService.refresh();
    if (level != null && level <= minBattery) {
      debugPrint('🔋 Batería baja ($level%): foto de contexto omitida.');
      return null;
    }

    try {
      final result = await TacticalCameraService.captureTelemetryPhoto();
      if (result != null) {
        AppLogger.info('📷 Foto de contexto silenciosa capturada.', tag: 'BlackBox');
      }
      return result;
    } catch (e) {
      AppLogger.warn('Captura de contexto fallida.', tag: 'BlackBox', error: e);
      return null;
    }
  }

  // ── CICLO DE MONITOREO ──

  static Future<void> startMonitoring() async {
    _photoTimer?.cancel();
    _packageTimer?.cancel();
    _photoTimer = null;
    _packageTimer = null;

    if (!await isEnabled()) {
      debugPrint('📦 Caja Negra AEGIS desactivada; monitoreo no iniciado.');
      return;
    }

    final int photoMin = await photoIntervalMinutes();
    final int packageMin = await packageIntervalMinutes();

    _packageTimer = Timer.periodic(Duration(minutes: packageMin <= 0 ? 15 : packageMin), (_) {
      unawaited(emitPackage());
    });
    _photoTimer = Timer.periodic(Duration(minutes: photoMin <= 0 ? 30 : photoMin), (_) {
      unawaited(captureSilentContextPhoto());
    });

    // Primer paquete pasado un corto retardo (deja asentarse GPS/batería).
    Timer(const Duration(seconds: 5), () => unawaited(emitPackage()));
    debugPrint('📦 Caja Negra AEGIS activa: foto c/$photoMin min, paquete c/$packageMin min.');
  }

  static void stopMonitoring() {
    _photoTimer?.cancel();
    _packageTimer?.cancel();
    _photoTimer = null;
    _packageTimer = null;
  }
}
