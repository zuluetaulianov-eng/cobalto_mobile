import 'dart:async';
import 'package:flutter/widgets.dart';

import 'gps_service.dart';

/// Gestión de poder táctica: vigila el ciclo de vida de la app y suspende los
/// sensores de mayor consumo cuando el terminal pasa a segundo plano o la
/// pantalla se apaga, restaurándolos al volver al primer plano.
///
/// El flujo de telemetría GPS continua (el de mayor gasto de batería) se pausa
/// en background; los servicios de seguridad (dead-man, heartbeat) permanecen
/// activos porque son parte de la protección del operador.
class PowerManagementService with WidgetsBindingObserver {
  static final PowerManagementService _instance = PowerManagementService._internal();
  factory PowerManagementService() => _instance;
  PowerManagementService._internal();

  bool _appInForeground = true;
  bool get appInForeground => _appInForeground;

  /// Registra el observador de ciclo de vida (llamar tras ensureInitialized).
  void attach() {
    WidgetsBinding.instance.addObserver(this);
  }

  void detach() {
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bool foreground = state == AppLifecycleState.resumed;
    if (foreground == _appInForeground) return;
    _appInForeground = foreground;

    if (!foreground) {
      // Segundo plano / pausa / oculto: liberar el stream GPS continuo.
      debugPrint('🔋 Ahorro de energía: GPS en segundo plano suspendido.');
      unawaited(GpsService.stopTracking());
    } else {
      // Primer plano: restaurar telemetría continua.
      debugPrint('🔋 Ahorro de energía: GPS restaurado en primer plano.');
      unawaited(GpsService.startTracking());
    }
  }
}