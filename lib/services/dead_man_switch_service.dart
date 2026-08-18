import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'cobalto_api_service.dart';
import 'gps_service.dart';
import 'local_db_service.dart';
import 'notification_service.dart';
import 'stealth_service.dart';

/// Monitor Táctico de Hombre Muerto (Dead Man's Switch).
/// Monitorea inercia y aceleración para detectar caídas bruscas o pérdida de conciencia.
class DeadManSwitchService extends ChangeNotifier {
  static final DeadManSwitchService _instance = DeadManSwitchService._internal();
  factory DeadManSwitchService() => _instance;
  DeadManSwitchService._internal();

  StreamSubscription<UserAccelerometerEvent>? _accelSubscription;
  bool _isActive = false;
  bool get isActive => _isActive;

  bool _isEmergencyAlertActive = false;
  bool get isEmergencyAlertActive => _isEmergencyAlertActive;

  // Cuenta regresiva estándar para respuesta del operador antes de emitir la señal SOS.
  static const int emergencyCountdownSeconds = 30;

  int _countdownSeconds = emergencyCountdownSeconds;
  int get countdownSeconds => _countdownSeconds;
  Timer? _countdownTimer;

  // Umbrales de detección de impacto (G-force > 3.2G = impacto brusco)
  static const double _impactThreshold = 28.0; // m/s^2 (~2.8G libre + gravedad)

  DateTime _lastProcessedTime = DateTime.now();

  /// Inicia la vigilancia de acelerómetro
  void startMonitoring() {
    if (_isActive) return;
    _isActive = true;
    notifyListeners();

    _accelSubscription = userAccelerometerEventStream().listen((UserAccelerometerEvent event) {
      final now = DateTime.now();
      if (now.difference(_lastProcessedTime).inMilliseconds < 100) return; // Muestreo limitado a 10Hz (evita saturar CPU)
      _lastProcessedTime = now;

      double totalAcceleration = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      if (totalAcceleration > _impactThreshold && !_isEmergencyAlertActive) {
        _triggerEmergencyCountdown();
      }
    });
  }

  /// Detiene la vigilancia de acelerómetro
  void stopMonitoring() {
    _isActive = false;
    _accelSubscription?.cancel();
    _accelSubscription = null;
    _cancelEmergency();
    notifyListeners();
  }

  /// Inicia la cuenta regresiva de alerta de emergencia
  void _triggerEmergencyCountdown() {
    _isEmergencyAlertActive = true;
    _countdownSeconds = emergencyCountdownSeconds;
    notifyListeners();

    StealthService().triggerHapticPattern(DEFCONLevel.critical);
    NotificationService.showAlertNotification(
      title: 'CAÍDA DETECTADA — VENTANA SOS ABIERTA',
      body: 'Respuesta automática de emergencia en ${emergencyCountdownSeconds}s. Cancele si está consciente.',
      level: 'CRÍTICA',
      deduplicationKey: 'deadman|countdown',
      showFloatingOverlay: false,
    );

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

  /// Transmite la señal SOS a la base táctica (si hay enlace) y queda registrada localmente.
  Future<void> _sendAutomaticSOS() async {
    StealthService().triggerHapticPattern(DEFCONLevel.critical);

    final position = await GpsService.getCurrentPosition();
    final Map<String, dynamic> sosData = {
      'type': 'sos',
      'severity': 'CRITICAL',
      'alert': 'OPERATOR DOWN - DROP/LOSS OF CONSCIOUSNESS',
      'timestamp': DateTime.now().toIso8601String(),
      'lat': position?.latitude ?? 0.0,
      'lng': position?.longitude ?? 0.0,
      'source': 'dead_man_switch',
    };

    await NotificationService.showAlertNotification(
      title: 'SEÑAL SOS TRANSMITIDA',
      body: 'Pérdida de respuesta del operador. Coordenadas: '
          '${position != null ? '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}' : 'no disponibles'}.',
      level: 'CRÍTICA',
      deduplicationKey: 'deadman|sos',
      showFloatingOverlay: false,
    );

    // Registro local cifrado (reporte de campo CRITICAL) para disponibilidad offline.
    await LocalDbService.saveFieldReport({
      'title': '🚨 SOS AUTOMÁTICO (DeadManSwitch)',
      'description': 'OPERATOR DOWN - Pérdida de respuesta durante ${emergencyCountdownSeconds}s.',
      'threat_level': 'CRITICAL',
      'lat': position?.latitude ?? 0.0,
      'lng': position?.longitude ?? 0.0,
    });

    // Transmisión a la base (fire-and-forget; no bloquea la UI).
    unawaited(CobaltoApiService.sendSosSignal(sosData));
  }

  /// Cancela manualmente la alerta de emergencia (Operador Consciente)
  void cancelEmergency() {
    _cancelEmergency();
    notifyListeners();
  }

  void _cancelEmergency() {
    _isEmergencyAlertActive = false;
    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  @override
  void dispose() {
    stopMonitoring();
    super.dispose();
  }
}
