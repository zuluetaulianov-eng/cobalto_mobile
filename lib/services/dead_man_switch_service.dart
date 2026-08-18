import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'emergency_service.dart';
import 'gps_service.dart';
import 'local_db_service.dart';
import 'notification_service.dart';
import 'stealth_service.dart';
import 'tactical_camera_service.dart';
import 'telemetry_sync_service.dart';
import 'voice_service.dart';

/// Monitor Táctico de Hombre Muerto (Dead Man's Switch).
///
/// Vigila dos condiciones de peligro:
///  - **IMPACTO/CAÍDA**: aceleración brusca (fuerza G alta) que sugiere una
///    caída o pérdida de conciencia del operador.
///  - **INMOVILIZACIÓN**: ausencia prolongada de movimiento (magnitud ~1G
///    constante) y de interacción con la pantalla durante una ventana
///    configurable.
///
/// Al detectar cualquiera de ambas abre una ventana de respuesta de
/// [emergencyCountdownSeconds] s; si el operador no reacciona (toca pantalla),
/// se transmite la señal SOS a la base con telemetría y se registra localmente.
class DeadManSwitchService extends ChangeNotifier {
  static final DeadManSwitchService _instance = DeadManSwitchService._internal();
  factory DeadManSwitchService() => _instance;
  DeadManSwitchService._internal();

  StreamSubscription<UserAccelerometerEvent>? _accelSubscription;
  Timer? _housekeepingTimer;
  bool _isActive = false;
  bool get isActive => _isActive;

  bool _isEmergencyAlertActive = false;
  bool get isEmergencyAlertActive => _isEmergencyAlertActive;

  String _emergencyLabel = '';
  String get emergencyLabel => _emergencyLabel;

  // Cuenta regresiva estándar para respuesta del operador antes de emitir la señal SOS.
  static const int emergencyCountdownSeconds = 30;

  int _countdownSeconds = emergencyCountdownSeconds;
  int get countdownSeconds => _countdownSeconds;
  Timer? _countdownTimer;

  // Configuración persistente (umbrales ajustables en el terreno).
  static double _impactThreshold = 28.0; // m/s^2 (~2.8G libre + gravedad)
  static int _immobilizedMinutes = 5; // minutos sin movimiento ni interacción
  static const double _stillThreshold = 1.5; // por debajo = operador quieto (user accel sin gravedad)

  static const String _enabledKey = 'deadman_monitoring_enabled';
  static const String _impactKey = 'deadman_impact_threshold';
  static const String _immobKey = 'deadman_immobilized_minutes';

  static double get impactThreshold => _impactThreshold;
  static int get immobilizedMinutes => _immobilizedMinutes;

  DateTime _lastProcessedTime = DateTime.now();
  DateTime _lastMotionTime = DateTime.now();
  DateTime _lastInteractionTime = DateTime.now();

  // Acumuladores para la detección de ARRASTRE/TRANSPORTE (movimiento sostenido
  // de baja magnitud y poca variación).
  double _windowMagSum = 0.0;
  int _windowSampleCount = 0;
  int _transportStreak = 0;

  /// Carga configuración persistida y reactiva el monitor si estaba activo.
  Future<void> initFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _impactThreshold = prefs.getDouble(_impactKey) ?? 28.0;
    _immobilizedMinutes = prefs.getInt(_immobKey) ?? 5;
    final enabled = prefs.getBool(_enabledKey) ?? false;
    if (enabled) startMonitoring();
  }

  /// Activa o desactiva el monitor y persiste la decisión.
  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
    if (enabled) {
      startMonitoring();
    } else {
      stopMonitoring();
    }
  }

  /// Ajusta el umbral de impacto (m/s^2) persistiéndolo en el dispositivo.
  Future<void> setImpactThreshold(double value) async {
    _impactThreshold = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_impactKey, value);
    notifyListeners();
  }

  /// Ajusta la ventana de inmovilización en minutos, persistiéndola.
  Future<void> setImmobilizedMinutes(int value) async {
    _immobilizedMinutes = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_immobKey, value);
    notifyListeners();
  }

  /// Registra interacción del operador (toque en pantalla). Restablece el
  /// contador de inmovilidad y, si hay una ventana SOS abierta, la cancela
  /// automáticamente (el operador está consciente).
  void registerInteraction() {
    _lastInteractionTime = DateTime.now();
    if (_isEmergencyAlertActive) {
      LocalDbService.logEmergencyEvent('VENTANA_CANCELADA_POR_TOQUE');
      _cancelEmergency();
      EmergencyService().cancelAlarm();
      notifyListeners();
    }
  }

  /// Inicia la vigilancia de acelerómetro e inmovilización.
  void startMonitoring() {
    if (_isActive) return;
    _isActive = true;
    _lastMotionTime = DateTime.now();
    _lastInteractionTime = DateTime.now();
    notifyListeners();

    _accelSubscription =
        userAccelerometerEventStream().listen((UserAccelerometerEvent event) {
      final now = DateTime.now();
      if (now.difference(_lastProcessedTime).inMilliseconds < 100) return;
      _lastProcessedTime = now;

      double totalAcceleration =
          sqrt(event.x * event.x + event.y * event.y + event.z * event.z);

      // Acumular muestra para la ventana de análisis de transporte/arrastre.
      _windowMagSum += totalAcceleration;
      _windowSampleCount++;

      // Hay movimiento (supera el ruido base de reposo).
      if (totalAcceleration > _stillThreshold) {
        _lastMotionTime = now;
      }

      // IMPACTO/CAÍDA: aceleración brusca.
      if (totalAcceleration > _impactThreshold && !_isEmergencyAlertActive) {
        _triggerEmergencyCountdown('CAÍDA/IMPACTO DETECTADO');
      }
    });

    // INMOVILIZACIÓN (sin movimiento ni interacción) y ARRASTRE/TRANSPORTE
    // (movimiento de baja magnitud, constante y poco variado).
    _housekeepingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      final now = DateTime.now();
      if (_isEmergencyAlertActive) {
        _windowMagSum = 0.0;
        _windowSampleCount = 0;
        _transportStreak = 0;
        return;
      }

      // INMOVILIZACIÓN: quietud absoluta durante N minutos.
      final bool quietLongEnough =
          now.difference(_lastMotionTime).inMinutes >= _immobilizedMinutes &&
          now.difference(_lastInteractionTime).inMinutes >= _immobilizedMinutes;
      if (quietLongEnough) {
        _triggerEmergencyCountdown('OPERADOR INMOVILIZADO');
        _windowMagSum = 0.0;
        _windowSampleCount = 0;
        _transportStreak = 0;
        return;
      }

      // ARRASTRE/TRANSPORTE: promedio de aceleración en banda (por encima del
      // reposo pero muy por debajo de un impacto) durante ≥ 2 ventanas (~1 min),
      // sin picos bruscos.
      if (_windowSampleCount > 0) {
        final double avgMag = _windowMagSum / _windowSampleCount;
        const double transportLowBand = _stillThreshold + 1.5;
        final double transportHighBand = _impactThreshold / 2.0;
        if (avgMag > transportLowBand && avgMag < transportHighBand) {
          _transportStreak++;
        } else {
          _transportStreak = 0;
        }
      } else {
        _transportStreak = 0;
      }
      _windowMagSum = 0.0;
      _windowSampleCount = 0;

      if (_transportStreak >= 2) {
        _triggerEmergencyCountdown('POSIBLE ARRASTRE/TRANSPORTE');
        _transportStreak = 0;
      }
    });
  }

  /// Detiene la vigilancia de acelerómetro.
  void stopMonitoring() {
    _isActive = false;
    _accelSubscription?.cancel();
    _accelSubscription = null;
    _housekeepingTimer?.cancel();
    _housekeepingTimer = null;
    _cancelEmergency();
    notifyListeners();
  }

  /// Inicia la cuenta regresiva de alerta de emergencia.
  void _triggerEmergencyCountdown(String label) {
    _isEmergencyAlertActive = true;
    _emergencyLabel = label;
    _countdownSeconds = emergencyCountdownSeconds;
    notifyListeners();

    EmergencyService().activateAlarm(label);
    LocalDbService.logEmergencyEvent('DETECCION_EMERGENCIA', data: {'label': label});

    StealthService().triggerHapticPattern(DEFCONLevel.critical);
    NotificationService.showAlertNotification(
      title: '$label — VENTANA SOS ABIERTA',
      body: 'Respuesta automática de emergencia en ${emergencyCountdownSeconds}s. Toque la pantalla para cancelar.',
      level: 'CRÍTICA',
      deduplicationKey: 'deadman|countdown',
    );
    VoiceService.speakAlert(
      title: label,
      body: 'Respuesta automática de emergencia en $emergencyCountdownSeconds segundos. Toque la pantalla para cancelar.',
      level: 'CRÍTICA',
    );

    // Evidencia de contexto: foto del entorno al momento de la detección.
    unawaited(TacticalCameraService.captureTelemetryPhoto(
      telemetry: GpsService.lastSnapshot,
      classification: 'CONFIDENCIAL // COBALTO CONTEXTO SOS',
    ));

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdownSeconds > 1) {
        _countdownSeconds--;
        notifyListeners();
      } else {
        _countdownSeconds = 0;
        _countdownTimer?.cancel();
        _sendAutomaticSOS();
        notifyListeners();
      }
    });
  }

  /// Transmite la señal SOS a la base (con reintento en cola) y queda
  /// registrada localmente de forma cifrada.
  Future<void> _sendAutomaticSOS() async {
    StealthService().triggerHapticPattern(DEFCONLevel.critical);

    // Telemetría instantánea del stream; fallback a fix puntual si no hay.
    final TacticalSnapshot? snapshot = GpsService.lastSnapshot;
    final Position? pos = await GpsService.getCurrentPosition();

    final double lat = snapshot?.lat ?? pos?.latitude ?? 0.0;
    final double lon = snapshot?.lon ?? pos?.longitude ?? 0.0;

    final Map<String, dynamic> sosData = {
      'type': 'sos',
      'severity': 'CRITICAL',
      'alert': 'OPERATOR DOWN - $_emergencyLabel - DROP/LOSS OF CONSCIOUSNESS',
      'timestamp': DateTime.now().toIso8601String(),
      'lat': lat,
      'lng': lon,
      'accuracy_m': snapshot?.accuracyM,
      'source': 'dead_man_switch',
    };

    await NotificationService.showAlertNotification(
      title: 'SEÑAL SOS TRANSMITIDA',
      body: 'Pérdida de respuesta del operador. Coordenadas: '
          '${lat != 0.0 ? '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}' : 'no disponibles'}.',
      level: 'CRÍTICA',
      deduplicationKey: 'deadman|sos',
    );
    VoiceService.speakAlert(
      title: 'SEÑAL SOS TRANSMITIDA',
      body: 'Pérdida de respuesta del operador. Coordenadas enviadas a la base.',
      level: 'CRÍTICA',
    );

    // Registro local cifrado (reporte de campo CRITICAL) para disponibilidad offline.
    await LocalDbService.saveFieldReport({
      'title': '🚨 SOS AUTOMÁTICO (DeadManSwitch)',
      'description': 'OPERATOR DOWN - $_emergencyLabel - Pérdida de respuesta durante ${emergencyCountdownSeconds}s.',
      'threat_level': 'CRITICAL',
      'lat': lat,
      'lng': lon,
    });

    // Transmisión a la base con cola de reintento si no hay enlace.
    final bool ack = await TelemetrySyncService.enqueueAndSendSos(sosData);
    await LocalDbService.logEmergencyEvent(
      ack ? 'SOS_TRANSMITIDO_BASE' : 'SOS_SIN_ACK_AL_CONTACTO',
      data: sosData,
    );

    if (!ack) {
      await EmergencyService().escalateToContact(
        'OPERADOR COBALTO SIN RESPUESTA. Coordenadas: '
        '${lat != 0.0 ? '$lat, $lon' : 'no disponibles'} ($_emergencyLabel).',
      );
    }
  }

  /// Cancela manualmente la alerta de emergencia (Operador Consciente).
  void cancelEmergency() {
    _cancelEmergency();
    LocalDbService.logEmergencyEvent('VENTANA_CANCELADA_MANUAL');
    EmergencyService().cancelAlarm();
    notifyListeners();
  }

  void _cancelEmergency() {
    _isEmergencyAlertActive = false;
    _emergencyLabel = '';
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _transportStreak = 0;
  }

  @override
  void dispose() {
    stopMonitoring();
    super.dispose();
  }
}