import 'package:cobalto_mobile/services/dead_man_switch_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cuenta regresiva SOS estándar es de 30 segundos', () {
    // Alineado con el README: ventana de respuesta de 30s antes de transmitir.
    expect(DeadManSwitchService.emergencyCountdownSeconds, 30);
  });

  test('estado inicial del servicio es inactivo', () {
    final service = DeadManSwitchService();
    expect(service.isActive, isFalse);
    expect(service.isEmergencyAlertActive, isFalse);
    expect(service.countdownSeconds, DeadManSwitchService.emergencyCountdownSeconds);
  });

  test('cancelEmergency es seguro sin emergencia activa', () {
    final service = DeadManSwitchService();
    final instance = DeadManSwitchService();

    service.cancelEmergency();
    expect(service.isEmergencyAlertActive, isFalse);
    expect(instance, same(service), reason: 'El servicio es singleton');
  });
}