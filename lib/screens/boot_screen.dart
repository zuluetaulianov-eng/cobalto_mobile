import 'dart:async';

import 'package:flutter/material.dart';
import '../config/api_config.dart';
import '../services/aegis_battery_service.dart';
import '../services/aegis_black_box_service.dart';
import '../services/aegis_checkin_service.dart';
import '../services/aegis_early_warning_service.dart';
import '../services/aegis_emergency_kit_service.dart';
import '../services/cobalto_api_service.dart';
import '../services/dead_man_switch_service.dart';
import '../services/emergency_service.dart';
import '../services/geofence_service.dart';
import '../services/gps_service.dart';
import '../services/notification_service.dart';
import '../services/power_management_service.dart';
import '../services/telemetry_sync_service.dart';
import '../services/voice_service.dart';
import 'login_screen.dart';

import 'package:shared_preferences/shared_preferences.dart';

class BootScreen extends StatefulWidget {
  const BootScreen({super.key});

  @override
  State<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<BootScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  final List<String> _logs = [];
  final bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _runBootSequence();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _addLog(String msg) {
    if (mounted) {
      setState(() {
        _logs.add(msg);
      });
    }
  }

  Future<void> _runBootSequence() async {
    _addLog('[+] CARGANDO PARÁMETROS LOCALES DE CONFIGURACIÓN...');
    await ApiConfig.loadConfig();

    _addLog('[+] MODOS Y SERVICIOS TÁCTICOS ACTIVADOS.');

    // Inicializar servicios en paralelo de forma asíncrona sin bloquear la pantalla
    unawaited(_initBackgroundServices());

    // Transición ultra-rápida a la pantalla de login (150ms)
    await Future.delayed(const Duration(milliseconds: 150));
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  Future<void> _initBackgroundServices() async {
    try {
      // 1. Notificaciones locales & acciones desde lockscreen
      NotificationService.init().then((_) {
        NotificationService.onCheckInAction = AegisCheckInService.checkIn;
      });

      // 2. Voz silenciosa & GPS tracking
      VoiceService.loadSilentMode();
      GpsService.startTracking();

      // 3. Monitores AEGIS (Batería, Alerta temprana, Kit de emergencia)
      AegisBatteryService.startMonitoring();
      AegisEarlyWarningService.startMonitoring();
      AegisEmergencyKitService.checkAndSchedule();
      AegisBlackBoxService.startMonitoring();
      PowerManagementService().attach();

      // 4. Verificación no bloqueante de conexión al servidor Central
      CobaltoApiService.testConnection().then((isOk) {
        if (isOk) {
          SharedPreferences.getInstance().then((prefs) {
            final cachedStr = prefs.getString('cached_sitrep_news');
            if (cachedStr == null || cachedStr.isEmpty || cachedStr == '[]') {
              CobaltoApiService.fetchNews();
            }
          });
        }
      });

      // 5. Reactivar geocercas
      final geoMonitoring = await GeofenceService.isMonitoringEnabled();
      if (geoMonitoring) {
        final interval = await GeofenceService.getMonitoringIntervalSeconds();
        GeofenceService.startMonitoring(intervalSeconds: interval);
      }

      // 6. Reactivar Hombre Muerto
      await DeadManSwitchService().initFromPrefs();

      // 7. Servicio de Emergencia & Heartbeat
      await EmergencyService().initFromPrefs();

      // 8. Reintentos de cola en segundo plano
      await TelemetrySyncService.retryPending();
      await TelemetrySyncService.retryPendingSos();
      await AegisBlackBoxService.retryPending();
    } catch (_) {
      // Manejo silencioso de servicios de fondo
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0B10),
      body: Stack(
        children: [
          // Fondo Radial Ciberpunk
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.2),
                radius: 0.8,
                colors: [
                  Color(0x1500E5FF),
                  Colors.transparent,
                ],
              ),
            ),
          ),

          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Anillo Giratorio Ciberpunk (Mismo diseño que el login Web)
                  RotationTransition(
                    turns: _animController,
                    child: Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _hasError ? const Color(0xFFFF2D55) : const Color(0xFF00E5FF),
                          width: 2,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _hasError ? const Color(0xFFFF2D55) : const Color(0xFF00E5FF),
                          backgroundColor: Colors.transparent,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),
                  const Text(
                    'COBALTO HUB v9.0',
                    style: TextStyle(
                      color: Color(0xFF00E5FF),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'SISTEMA DE INTELIGENCIA Y MANDO TÁCTICO',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 9,
                      letterSpacing: 2,
                      fontFamily: 'monospace',
                    ),
                  ),

                  const SizedBox(height: 36),

                  // Caja Terminal de Boot Sequence
                  Container(
                    width: double.infinity,
                    height: 140,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141824),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _hasError ? const Color(0xFFFF2D55).withOpacity(0.4) : const Color(0xFF00E5FF).withOpacity(0.3),
                      ),
                    ),
                    child: ListView.builder(
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        final log = _logs[index];
                        final isErr = log.startsWith('[-]');
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            log,
                            style: TextStyle(
                              color: isErr ? const Color(0xFFFF2D55) : const Color(0xFF00FFAA),
                              fontSize: 10,
                              fontFamily: 'monospace',
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
