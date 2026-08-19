import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'config/api_config.dart';
import 'screens/boot_screen.dart';
import 'services/aegis_battery_service.dart';
import 'services/aegis_black_box_service.dart';
import 'services/aegis_checkin_service.dart';
import 'services/aegis_early_warning_service.dart';
import 'services/aegis_emergency_kit_service.dart';
import 'services/aegis_mesh_transport_service.dart';
import 'services/aegis_survival_map_service.dart';
import 'services/gps_service.dart';
import 'services/notification_service.dart';
import 'services/power_management_service.dart';
import 'services/telemetry_sync_service.dart';
import 'services/voice_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiConfig.loadConfig();
  await NotificationService.init();
  // Acciones de notificación (check-in "Estoy a salvo" desde lockscreen).
  NotificationService.onCheckInAction = AegisCheckInService.checkIn;
  await VoiceService.loadSilentMode();
  // Telemetría continua: stream GPS compartido para mapa, HUD, geocercas y SOS.
  try {
    await GpsService.startTracking();
  } catch (e) {
    // El arranque no debe bloquearse si el GPS no está disponible aún.
  }
  // Batería en la telemetría compartida (paquete de caja negra AEGIS).
  AegisBatteryService.startMonitoring();
  // Recordatorio de mantenimiento del kit de emergencia (cada 6 meses).
  await AegisEmergencyKitService.checkAndSchedule();
  // Alerta temprana AEGIS: USGS directo + algoritmo P/S + geocerca (Fase 2).
  AegisEarlyWarningService.startMonitoring();
  // Caja Negra AEGIS (Fase 3): paquetes cifrados + fotos silenciosas.
  try {
    await AegisBlackBoxService.retryPending();
  } catch (e) {
    // La cola se reintenta en el siguiente arranque.
  }
  await AegisBlackBoxService.startMonitoring();
  // Mapa colaborativo de supervivencia AEGIS (Fase 4): tabla CRDT.
  try {
    await AegisSurvivalMapService.ensureTable();
  } catch (e) {
    // No bloquea el arranque si SQLite falla temporalmente.
  }
  // Red Mesh de Transporte Ciego AEGIS (Fase 6b): tabla de deduplicación.
  try {
    await AegisMeshTransportService.ensureTable();
  } catch (e) {
    // No bloquea el arranque.
  }
  // Reintenta subidas fotográficas de telemetría que quedaron sin enlace.
  try {
    await TelemetrySyncService.retryPending();
  } catch (e) {
    // Silencioso: la cola se reintenta en el siguiente arranque.
  }
  PowerManagementService().attach();
  runApp(const CobaltoApp());
}

class CobaltoApp extends StatelessWidget {
  const CobaltoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'COBALTO HUB Mobile',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0B10),
        primaryColor: const Color(0xFF00E5FF),
        textTheme: GoogleFonts.robotoMonoTextTheme(
          ThemeData.dark().textTheme,
        ),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFFB388FF),
          surface: Color(0xFF141824),
          error: Color(0xFFFF2D55),
        ),
      ),
      home: const BootScreen(),
    );
  }
}
