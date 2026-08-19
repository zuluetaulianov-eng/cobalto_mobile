import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/api_config.dart';
import 'aegis_battery_service.dart';
import 'app_logger.dart';
import 'cobalto_api_service.dart';
import 'gps_service.dart';
import 'local_db_service.dart';
import 'notification_service.dart';
import 'stealth_service.dart';
import 'tactical_camera_service.dart';
import 'telemetry_sync_service.dart';
import 'voice_service.dart';

/// Orquestador de emergencias COBALTO.
///
/// Centraliza las respuestas de contingencia del operador:
///  - **Pánico manual**: SOS inmediato con telemetría, notificación, voz y
///    foto de contexto; activa la pantalla de alarma.
///  - **Coacción (duress)**: login con la contraseña de coacción que dispara
///    un SOS silencioso camuflado (sin alerta visual).
///  - **Heartbeat**: latido de telemetría periódico para que la base detecte
///    la pérdida del operador.
///  - **Escalada**: si el SOS no tiene ACK del servidor, intenta SMS y llamada
///    al contacto de emergencia configurado.
class EmergencyService extends ChangeNotifier {
  static final EmergencyService _instance = EmergencyService._internal();
  factory EmergencyService() => _instance;
  EmergencyService._internal();

  bool _alarmActive = false;
  bool get alarmActive => _alarmActive;

  String _alarmReason = '';
  String get alarmReason => _alarmReason;

  Timer? _heartbeatTimer;

  static const String _contactKey = 'emergency_contact_phone';
  static const String _hbEnabledKey = 'heartbeat_enabled';
  static const String _hbMinutesKey = 'heartbeat_minutes';

  static int _heartbeatMinutes = 5;

  // ── CONFIGURACIÓN PERSISTENTE ──

  static Future<String> getContactPhone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_contactKey) ?? '';
  }

  static Future<void> setContactPhone(String phone) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_contactKey, phone.trim());
  }

  static Future<int> getHeartbeatMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_hbMinutesKey) ?? 5;
  }

  static Future<void> setHeartbeatMinutes(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_hbMinutesKey, minutes);
    _heartbeatMinutes = minutes;
    if (isHeartbeatRunning) startHeartbeat();
  }

  static Future<bool> isHeartbeatEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_hbEnabledKey) ?? false;
  }

  static Future<void> setHeartbeatEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hbEnabledKey, enabled);
    if (enabled) {
      if (!isHeartbeatRunning) {
        _heartbeatMinutes = await getHeartbeatMinutes();
        startHeartbeat();
      }
    } else {
      stopHeartbeat();
    }
  }

  static bool get isHeartbeatRunning => EmergencyService()._heartbeatTimer != null;

  /// Carga la configuración de emergencia persistida al arrancar.
  Future<void> initFromPrefs() async {
    _heartbeatMinutes = await getHeartbeatMinutes();
    if (await isHeartbeatEnabled()) startHeartbeat();
  }

  // ── HEARTBEAT (BEACON DE TELEMETRÍA) ──

  /// Publica periódicamente la posición del operador. La base detecta pérdida
  /// cuando el latido deja de llegar.
  static void startHeartbeat() {
    final service = _instance;
    service._heartbeatTimer?.cancel();
    service._heartbeatTimer =
        Timer.periodic(Duration(minutes: _heartbeatMinutes), (_) {
      service._publishHeartbeat();
    });
    // Latido inmediato inicial para fijar el ancla de tiempo.
    service._publishHeartbeat();
    debugPrint('📡 Heartbeat de telemetría iniciado ($_heartbeatMinutes min).');
  }

  static void stopHeartbeat() {
    _instance._heartbeatTimer?.cancel();
    _instance._heartbeatTimer = null;
    debugPrint('📡 Heartbeat de telemetría detenido.');
  }

  Future<void> _publishHeartbeat() async {
    final TacticalSnapshot? snapshot = GpsService.lastSnapshot;
    final int battery = AegisBatteryService.lastLevel ?? snapshot?.batteryLevel ?? 100;
    final String rawUsername = ApiConfig.username.trim();
    final String opName = rawUsername.isNotEmpty ? rawUsername : 'Operador Terreno';
    final String cleanCode = opName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
    final String opId = 'OP-${cleanCode.isEmpty ? "ALPHA-1" : cleanCode}';

    final Map<String, dynamic> beat = {
      'operator_id': opId,
      'operator_name': opName,
      'latitude': snapshot?.lat ?? 0.0,
      'longitude': snapshot?.lon ?? 0.0,
      'altitude': snapshot?.altitudeM ?? 0.0,
      'battery_level': battery,
      'status': _alarmActive ? 'SOS' : 'PATROL',
      'network_type': '4G',
      'device_model': 'Cobalto Mobile',
      'unit_group': 'ALPHA',
    };
    unawaited(CobaltoApiService.sendHeartbeat(beat));
  }

  // ── PÁNICO MANUAL ──

  /// Snapshot lo más fresco posible: usa la telemetría del stream si es
  /// reciente (<=45 s), o fuerza una fijación puntual si está obsoleta o nula
  /// (por ejemplo, al llegar un SOS estando la app en segundo plano, donde el
  /// stream continuo puede estar suspendido por ahorro de batería).
  Future<TacticalSnapshot?> _freshSnapshot() async {
    final TacticalSnapshot? cached = GpsService.lastSnapshot;
    if (cached != null &&
        DateTime.now().toUtc().difference(cached.timestampUtc).inSeconds <= 45) {
      return cached;
    }
    try {
      await GpsService.getCurrentPosition();
    } catch (e) {
      // Sin fix puntual disponible: se conserva cualquier snapshot previo.
    }
    return GpsService.lastSnapshot;
  }

  /// Dispara un SOS inmediato por decisión del operador (botón de pánico).
  Future<void> triggerPanic() async {
    activateAlarm('PÁNICO MANUAL ACTUADO');

    final TacticalSnapshot? snapshot = await _freshSnapshot();
    final Map<String, dynamic> panicData = {
      'type': 'sos',
      'severity': 'CRITICAL',
      'alert': 'MANUAL PANIC - OPERADOR REQUIERE ASISTENCIA INMEDIATA',
      'timestamp': DateTime.now().toIso8601String(),
      'lat': snapshot?.lat,
      'lng': snapshot?.lon,
      'accuracy_m': snapshot?.accuracyM,
      'source': 'manual_panic',
    };

    StealthService().triggerHapticPattern(DEFCONLevel.critical);
    await NotificationService.showAlertNotification(
      title: '🚨 PÁNICO MANUAL ACTUADO',
      body: 'Operador solicita asistencia inmediata. Transmitiendo SOS con telemetría.',
      level: 'CRÍTICA',
      deduplicationKey: 'panic|manual',
    );
    VoiceService.speakAlert(
      title: 'Pánico manual actuado',
      body: 'Señal SOS transmitida a la base con telemetría.',
      level: 'CRÍTICA',
    );
    await LocalDbService.logEmergencyEvent('PANIC_MANUAL', data: panicData);

    final ok = await TelemetrySyncService.enqueueAndSendSos(panicData);
    if (!ok) {
      // Sin ACK del servidor: escalar a SMS/llamada del contacto.
      await escalateToContact('PÁNICO COBALTO. Operador requiere asistencia en ${_formatCoords(snapshot)}.');
    }

    captureContextPhoto();
  }

  /// EMERGENCIA INMINENTE — Alarma de rescate local ruidosa.
  ///
  /// Pensada para casos donde el operador NO puede gritar ni operar la
  /// pantalla (p. ej. atrapado bajo escombros): abre la pantalla de alarma con
  /// la sirena sonora al máximo volumen para que los rescatistas lo
  /// localicen, transmite un SOS a la base con la posición fresca, pero NO
  /// escala a SMS/llamada (evita que apps externas tapen la pantalla de alarma).
  Future<void> triggerRescueSignal() async {
    activateAlarm('EMERGENCIA INMINENTE // ALARMA DE RESCATE LOCAL');

    final TacticalSnapshot? snapshot = await _freshSnapshot();
    final Map<String, dynamic> rescueData = {
      'type': 'sos',
      'severity': 'CRITICAL',
      'alert': 'RESCUE ALARM - OPERADOR ATRAPADO, NO PUEDE GRITAR, POSICIÓN REQUIERE RESCATE',
      'timestamp': DateTime.now().toIso8601String(),
      'lat': snapshot?.lat,
      'lng': snapshot?.lon,
      'accuracy_m': snapshot?.accuracyM,
      'source': 'rescue_alarm',
    };

    StealthService().triggerHapticPattern(DEFCONLevel.critical);
    VoiceService.speakAlert(
      title: 'Alarma de rescate activada',
      body: 'Sirena sonando al máximo volumen. Posición transmitida.',
      level: 'CRÍTICA',
    );
    await LocalDbService.logEmergencyEvent('RESCUE_ALARM', data: rescueData);

    // SOS a la base sin escalada externa (la sirena local es la prioridad).
    await TelemetrySyncService.enqueueAndSendSos(rescueData);
  }

  /// SOS silencioso de coacción: el operador ingresa con la contraseña de
  /// coacción; la app entra con normalidad aparente pero transmite en secreto.
  Future<void> triggerDuress() async {
    final TacticalSnapshot? snapshot = await _freshSnapshot();
    final Map<String, dynamic> duressData = {
      'type': 'sos',
      'severity': 'CRITICAL',
      'alert': 'DURESS COERCION - OPERADOR BAJO COACCIÓN (SILENCIOSO)',
      'timestamp': DateTime.now().toIso8601String(),
      'lat': snapshot?.lat,
      'lng': snapshot?.lon,
      'source': 'duress_login',
    };

    // Vibración mínima como señal personal; sin alerta visual ni auditiva.
    StealthService().triggerHapticPattern(DEFCONLevel.info);
    await LocalDbService.logEmergencyEvent('DURESS_COERCION_DETECTADA', data: duressData);

    final ok = await TelemetrySyncService.enqueueAndSendSos(duressData);
    if (!ok) {
      await escalateToContact('COACCIÓN SOBRE OPERADOR COBALTO. Posición: ${_formatCoords(snapshot)}.');
    }
  }

  // ── ESTADO DE ALARMA (PANTALLA) ──

  /// Activa la pantalla de alarma (usada por pánico manual y monitor dead-man).
  void activateAlarm(String reason) {
    _alarmActive = true;
    _alarmReason = reason;
    notifyListeners();
  }

  /// Cancela la pantalla de alarma.
  void cancelAlarm() {
    _alarmActive = false;
    _alarmReason = '';
    notifyListeners();
  }

  // ── ESCALADA A CONTACTO (SMS / LLAMADA) ──

  /// Intenta alertar al contacto de emergencia vía SMS y luego llamada.
  /// Es "best-effort": en Android abre la app de SMS/marcador (el envío
  /// automático real depende de los permisos del sistema).
  Future<void> escalateToContact(String message) async {
    final contact = await getContactPhone();
    if (contact.isEmpty) return;

    await LocalDbService.logEmergencyEvent('ESCALADA_AL_CONTACTO', data: {'phone': contact});

    try {
      final smsUri = Uri(
        scheme: 'sms',
        path: contact,
        queryParameters: {'body': message},
      );
      if (await canLaunchUrl(smsUri)) {
        await launchUrl(smsUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      AppLogger.warn('No se pudo abrir SMS de emergencia.', tag: 'Emergency', error: e);
    }

    try {
      final telUri = Uri(scheme: 'tel', path: contact);
      if (await canLaunchUrl(telUri)) {
        await launchUrl(telUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      AppLogger.warn('No se pudo abrir la llamada de emergencia.', tag: 'Emergency', error: e);
    }
  }

  Future<void> captureContextPhoto() async {
    unawaited(TacticalCameraService.captureTelemetryPhoto(
      telemetry: GpsService.lastSnapshot,
      classification: 'CONFIDENCIAL // COBALTO CONTEXTO SOS',
    ));
  }

  String _formatCoords(TacticalSnapshot? snapshot) {
    if (snapshot == null || (snapshot.lat == 0.0 && snapshot.lon == 0.0)) {
      return 'sin coordenadas';
    }
    return '${snapshot.lat.toStringAsFixed(5)}, ${snapshot.lon.toStringAsFixed(5)}';
  }

  @override
  void dispose() {
    stopHeartbeat();
    super.dispose();
  }
}