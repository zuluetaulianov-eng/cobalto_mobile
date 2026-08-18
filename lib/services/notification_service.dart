import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'settings_persistence_service.dart';
import 'voice_service.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static bool _isInitialized = false;
  static final Set<String> _sentAlertKeys = {};

  /// Inicializa el servicio de notificaciones locales de sistema
  static Future<void> init() async {
    if (_isInitialized) return;

    try {
      const AndroidInitializationSettings androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const DarwinInitializationSettings iosSettings =
          DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const InitializationSettings initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _notificationsPlugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          debugPrint('Notificación interactuada: ${response.payload}');
        },
      );

      // Solicitar permiso en Android 13+ (API 33+)
      final androidImplementation =
          _notificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidImplementation != null) {
        await androidImplementation.requestNotificationsPermission();
      }

      _isInitialized = true;
      debugPrint('🔔 Service NotificationService initialized successfully.');
    } catch (e) {
      debugPrint('⚠️ Error initializing NotificationService: $e');
    }
  }

  /// Dispara una notificación de Alerta Táctica del Sistema en la barra de estado
  static Future<void> showAlertNotification({
    required String title,
    required String body,
    String level = 'ALTA',
    String? deduplicationKey,
  }) async {
    await init();

    final key = deduplicationKey ?? '$title|$body';
    if (_sentAlertKeys.contains(key)) {
      return; // Prevenir notificaciones duplicadas idénticas
    }
    _sentAlertKeys.add(key);

    // Mantener historial de claves acotado
    if (_sentAlertKeys.length > 100) {
      _sentAlertKeys.remove(_sentAlertKeys.first);
    }

    final int notificationId = DateTime.now().millisecondsSinceEpoch.remainder(100000);
    final String channelId = 'cobalto_critical_alerts';
    final String channelName = 'COBALTO - Alertas de Inteligencia';
    final String channelDesc = 'Notificaciones de máxima prioridad para alertas OSINT y DEFCON';

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDesc,
      importance: Importance.max,
      priority: Priority.high,
      ticker: '🚨 ALERTA DE SEGURIDAD COBALTO',
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: '🚨 [$level] $title',
        summaryText: 'COBALTO OSINT INTEL',
      ),
      enableVibration: true,
      playSound: true,
      icon: '@mipmap/ic_launcher',
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      await _notificationsPlugin.show(
        id: notificationId,
        title: '🚨 [$level] $title',
        body: body,
        notificationDetails: notificationDetails,
        payload: 'alert_tap',
      );

      // Anuncio por voz (TTS) de alertas CRÍTICA/ALTA si está activado en Ajustes.
      final bool announceByVoice = await SettingsPersistenceService.isVoiceAnnounceEnabled();
      if (announceByVoice && (level.contains('CRÍTICA') || level.contains('ALTA'))) {
        unawaited(VoiceService.speakAlert(title: title, body: body, level: level));
      }
    } catch (e) {
      debugPrint('⚠️ Error al mostrar notificación táctica: $e');
    }
  }

  /// Dispara una notificación informativa general
  static Future<void> showGeneralNotification({
    required String title,
    required String body,
  }) async {
    await init();

    final int notificationId = DateTime.now().millisecondsSinceEpoch.remainder(100000);

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'cobalto_general_updates',
      'COBALTO - Actualizaciones General',
      channelDescription: 'Notificaciones informativas de actualización SitRep',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@mipmap/ic_launcher',
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
    );

    try {
      await _notificationsPlugin.show(
        id: notificationId,
        title: title,
        body: body,
        notificationDetails: notificationDetails,
      );
    } catch (e) {
      debugPrint('⚠️ Error al mostrar notificación general: $e');
    }
  }
}

