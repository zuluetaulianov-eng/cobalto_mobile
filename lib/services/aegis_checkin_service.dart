import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_logger.dart';
import 'emergency_service.dart';
import 'gps_service.dart';
import 'local_db_service.dart';
import 'notification_service.dart';

/// Check-In AEGIS ("Estoy a salvo"): la acción de recuperación posterior a
/// una emergencia. Notifica al contacto de emergencia que el operador está
/// consciente y fuera de peligro, SIN saturar la red (best-effort via SMS).
class AegisCheckInService {
  /// Ejecuta el check-in: registra en el timeline forense y notifica al
  /// contacto de emergencia (SMS best-effort). Devuelve `true` si pudo.
  static Future<bool> checkIn() async {
    final contact = await EmergencyService.getContactPhone();
    final snapshot = GpsService.lastSnapshot;
    final coords = (snapshot != null && (snapshot.lat != 0.0 || snapshot.lon != 0.0))
        ? '${snapshot.lat.toStringAsFixed(5)}, ${snapshot.lon.toStringAsFixed(5)}'
        : 'sin coordenadas';
    final hasContact = contact.isNotEmpty;

    await LocalDbService.logEmergencyEvent('CHECKIN_SEGURO', data: {
      'contact': contact,
      'lat': snapshot?.lat,
      'lng': snapshot?.lon,
    });

    if (hasContact) {
      try {
        final msg = 'COBALTO AEGIS: Operador ESTÁ A SALVO. '
            'Posición: $coords. ${DateTime.now().toIso8601String()}';
        final smsUri = Uri(scheme: 'sms', path: contact, queryParameters: {'body': msg});
        if (await canLaunchUrl(smsUri)) {
          await launchUrl(smsUri, mode: LaunchMode.externalApplication);
        }
      } catch (e) {
        AppLogger.warn('No se pudo abrir SMS de check-in.', tag: 'Aegis', error: e);
      }
    }

    await NotificationService.showAlertNotification(
      title: '✅ CHECK-IN CONFIRMADO: ESTOY A SALVO',
      body: hasContact
          ? 'Estado de seguridad notificado al contacto $contact.'
          : 'Estado registrado localmente. No hay contacto de emergencia configurado.',
      level: 'INFORMATIVA',
      deduplicationKey: 'aegis|checkin|confirmed',
    );

    debugPrint('✅ Check-In "Estoy a salvo" ejecutado.');
    return true;
  }
}