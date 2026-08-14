import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';
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

  int _countdownSeconds = 15;
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
    _countdownSeconds = 15;
    notifyListeners();

    StealthService().triggerHapticPattern(DEFCONLevel.critical);

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

  /// Simula el envío de alerta SOS automática a la base táctica
  void _sendAutomaticSOS() {
    // Alerta SOS activada por falta de respuesta del operador
    StealthService().triggerHapticPattern(DEFCONLevel.critical);
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
