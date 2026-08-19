import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';

import 'gps_service.dart';

/// Monitor de poder AEGIS: lectura periódica del nivel de batería del
/// dispositivo e inyección en la telemetría compartida ([GpsService.telemetry]).
///
/// El nivel de batería es un dato de supervivencia crítico (el paquete de
/// "caja negra" debe informar cuánta autonomía le queda al operador), así
/// que se mantiene fresco en el snapshot táctico sin depender de un fix GPS.
class AegisBatteryService {
  static final Battery _battery = Battery();
  static Timer? _timer;

  static int? _lastLevel;
  static int? get lastLevel => _lastLevel;

  static bool _monitoring = false;
  static bool get isMonitoring => _monitoring;

  /// Lee el nivel actual de batería y lo inyecta en el snapshot compartido.
  /// Devuelve el porcentaje (0-100) o null si el sensor no responde.
  static Future<int?> refresh() async {
    int? level;
    try {
      final raw = await _battery.batteryLevel;
      if (raw >= 0) level = raw;
    } catch (e) {
      debugPrint('⚠️ Error leyendo nivel de batería: $e');
      return _lastLevel;
    }

    if (level == null) return _lastLevel;
    if (level == _lastLevel) return level;
    _lastLevel = level;

    final TacticalSnapshot? current = GpsService.lastSnapshot;
    if (current != null) {
      GpsService.telemetry.value = current.copyWith(batteryLevel: level);
    }
    return level;
  }

  /// Arranca el muestreo periódico (cada 60 s; el GPS usa 5 m de filtro,
  /// así que la batería no necesita más frecuencia).
  static void startMonitoring({Duration interval = const Duration(seconds: 60)}) {
    if (_monitoring) return;
    _monitoring = true;
    refresh();
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => refresh());
    debugPrint('🔋 Monitor de batería AEGIS iniciado.');
  }

  /// Detiene el muestreo periódico de batería.
  static void stopMonitoring() {
    _monitoring = false;
    _timer?.cancel();
    _timer = null;
    debugPrint('🔋 Monitor de batería AEGIS detenido.');
  }
}
