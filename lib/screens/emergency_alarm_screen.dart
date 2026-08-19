import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

import '../services/app_logger.dart';
import '../services/dead_man_switch_service.dart';
import '../services/emergency_service.dart';
import '../services/gps_service.dart';
import '../services/local_db_service.dart';
import '../services/notification_service.dart';
import '../services/tactical_camera_service.dart';

/// Pantalla táctica de alarma (SIRENA DE LOCALIZACIÓN).
/// Efecto estroboscópico rojo, patrón háptico SOS continuo, cuenta regresiva
/// del monitor de hombre muerto, telemetría en vivo y linterna opcional.
/// Se cierra automáticamente si el operador cancela la ventana.
class EmergencyAlarmScreen extends StatefulWidget {
  const EmergencyAlarmScreen({super.key});

  @override
  State<EmergencyAlarmScreen> createState() => _EmergencyAlarmScreenState();
}

class _EmergencyAlarmScreenState extends State<EmergencyAlarmScreen>
    with WidgetsBindingObserver {
  Timer? _strobeTimer;
  Timer? _hapticTimer;
  Timer? _morseTimer;
  bool _strobeOn = true;
  bool _torchOn = false;
  bool _sirenMuted = false;
  bool _morseActive = false;
  int _morseStep = 0;

  /// Patrón MORSE de SOS con el flash de linterna (unidad base = 200 ms):
  ///  S = 3 puntos(...)   O = 3 rayas(---)   S = 3 puntos(...)
  ///  Estructura (onMs, offMs): punto=200, raya=600, intra-letra=200,
  ///  entre-letras=600, fin de palabra=1400 (reinicio del bucle).
  static const List<(int, int)> _morseSosPattern = [
    (200, 200), (200, 200), (200, 600),
    (600, 200), (600, 200), (600, 600),
    (200, 200), (200, 200), (200, 1400),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startSiren();
    // Estroboscopio rojo (~2.5 Hz) para máxima visibilidad.
    _strobeTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted) setState(() => _strobeOn = !_strobeOn);
    });
    // Patrón háptico SOS continuo de localización.
    _hapticTimer = Timer.periodic(const Duration(milliseconds: 900), (_) async {
      await HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 120));
      await HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 120));
      await HapticFeedback.heavyImpact();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _strobeTimer?.cancel();
    _hapticTimer?.cancel();
    _morseTimer?.cancel();
    FlutterRingtonePlayer().stop();
    if (_torchOn || _morseActive) {
      TacticalCameraService.stopTorch();
    }
    super.dispose();
  }

  /// Hace sonar la sirena de alarma del sistema a máximo volumen en bucle,
  /// para que los equipos de rescate localicen al operador sin necesidad de
  /// que este grite. Best-effort: si el dispositivo no expone tono de alarma,
  /// el estrobo y los hápticos se mantienen.
  void _startSiren() {
    try {
      FlutterRingtonePlayer().playAlarm(asAlarm: true, looping: true, volume: 1.0);
    } catch (e) {
      AppLogger.warn('No se pudo iniciar la sirena de alarma.', tag: 'Alarm', error: e);
    }
  }

  void _toggleSiren() {
    setState(() => _sirenMuted = !_sirenMuted);
    if (_sirenMuted) {
      FlutterRingtonePlayer().stop();
    } else {
      _startSiren();
    }
  }

  Future<void> _toggleTorch() async {
    if (_morseActive) {
      _stopMorse();
      setState(() => _morseActive = false);
    }
    final bool on = !_torchOn;
    await TacticalCameraService.disposeCamera();
    final bool ok = on ? await TacticalCameraService.startTorch() : false;
    if (mounted) {
      setState(() => _torchOn = ok);
    }
    if (on && !ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Linterna no soportada en este sensor.'),
          backgroundColor: Color(0xFFFF2D55),
        ),
      );
    }
  }

  /// Activa/desactiva la BALIZA DE RESCATE MORSE: el flash de la cámara
  /// parpadea el patrón SOS (···−−−···) en bucle continuo. Optimiza la
  /// visibilidad a distancia con consumo acotado (flash solo en los pulsos).
  Future<void> _toggleMorse() async {
    if (_morseActive) {
      _stopMorse();
      if (mounted) setState(() => _morseActive = false);
      return;
    }
    final bool ok = await TacticalCameraService.setTorch(true);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Flash no soportado: baliza morse no disponible.'),
          backgroundColor: Color(0xFFFF2D55),
        ),
      );
      return;
    }
    setState(() {
      _morseActive = true;
      if (_torchOn) _torchOn = false;
    });
    _startMorseLoop();
  }

  void _startMorseLoop() {
    _morseStep = 0;
    _morsePulseOn();
  }

  void _morsePulseOn() {
    if (!mounted || !_morseActive) return;
    final step = _morseSosPattern[_morseStep];
    unawaited(TacticalCameraService.setTorch(true));
    _morseTimer?.cancel();
    _morseTimer = Timer(Duration(milliseconds: step.$1), _morsePulseOff);
  }

  void _morsePulseOff() {
    if (!mounted || !_morseActive) return;
    final step = _morseSosPattern[_morseStep];
    unawaited(TacticalCameraService.setTorch(false));
    _morseTimer?.cancel();
    _morseTimer = Timer(Duration(milliseconds: step.$2), () {
      if (!mounted || !_morseActive) return;
      _morseStep = (_morseStep + 1) % _morseSosPattern.length;
      _morsePulseOn();
    });
  }

  void _stopMorse() {
    _morseActive = false;
    _morseTimer?.cancel();
    _morseTimer = null;
    unawaited(TacticalCameraService.stopTorch());
  }

  void _cancelAndClose() {
    final deadMan = DeadManSwitchService();
    if (deadMan.isEmergencyAlertActive) {
      deadMan.cancelEmergency();
    }
    EmergencyService().cancelAlarm();
    LocalDbService.logEmergencyEvent('ALARMA_CANCELADA_POR_OPERADOR');
    // Fase de RECUPERACIÓN: ofrecer el check-in "Estoy a salvo" (lockscreen).
    unawaited(NotificationService.showCheckInNotification());
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([EmergencyService(), DeadManSwitchService()]),
      builder: (context, _) {
        final emergency = EmergencyService();
        if (!emergency.alarmActive && !DeadManSwitchService().isEmergencyAlertActive) {
          // Ya se canceló desde otro punto; cerrar la capa de alarma.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          });
        }

        final reason = emergency.alarmReason.isNotEmpty
            ? emergency.alarmReason
            : DeadManSwitchService().emergencyLabel;
        final snapshot = GpsService.lastSnapshot;
        final bool fixed = snapshot != null && (snapshot.lat != 0.0 || snapshot.lon != 0.0);

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            // El "atrás" del sistema no debe cerrar un SOS por accidente:
            // solo la cancelación explícita del operador lo detiene.
            if (!didPop && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('🚨 PARA DETENER LA ALARMA PULSE "SOY OPERADOR / CANCELAR".'),
                  backgroundColor: Color(0xFFFF2D55),
                ),
              );
            }
          },
          child: Scaffold(
          backgroundColor: _strobeOn ? const Color(0xFFFF2D55) : const Color(0xFF5A0A14),
          body: SafeArea(
            child: Stack(
              children: [
                Column(
                  children: [
                const Spacer(),
                const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 72),
                const SizedBox(height: 8),
                const Text(
                  'SOS',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 64,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 6,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  reason,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                if (DeadManSwitchService().isEmergencyAlertActive) ...[
                  Text(
                    'VENTANA DE RESPUESTA: ${DeadManSwitchService().countdownSeconds}s',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'TOQUE LA PANTALLA O PULSE CANCELAR PARA DETENER',
                    style: TextStyle(color: Colors.white, fontSize: 10, fontFamily: 'monospace'),
                  ),
                ],
                const SizedBox(height: 20),
                Text(
                  fixed
                      ? '📍 ${snapshot.lat.toStringAsFixed(5)}, ${snapshot.lon.toStringAsFixed(5)}'
                      : '📍 SIN FIJACIÓN GPS',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _alarmAction(
                      icon: _torchOn ? Icons.flash_on : Icons.flash_off,
                      label: _torchOn ? 'LINTERNA ON' : 'LINTERNA',
                      onTap: _toggleTorch,
                    ),
                    _alarmAction(
                      icon: _morseActive ? Icons.radio_button_checked : Icons.rss_feed,
                      label: _morseActive ? 'BALIZA MORSE ON' : 'BALIZA MORSE SOS',
                      onTap: _toggleMorse,
                      highlight: _morseActive,
                    ),
                    _alarmAction(
                      icon: Icons.check_circle,
                      label: 'SOY OPERADOR / CANCELAR',
                      onTap: _cancelAndClose,
                      highlight: true,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                  ],
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    icon: Icon(
                      _sirenMuted ? Icons.volume_off : Icons.volume_up,
                      color: Colors.white,
                      size: 22,
                    ),
                    tooltip: _sirenMuted
                        ? 'Activar sirena'
                        : 'Silenciar sirena (estrobo y vibración continúan)',
                    onPressed: _toggleSiren,
                  ),
                ),
              ],
            ),
          ),
          ),
        );
      },
    );
  }

  Widget _alarmAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool highlight = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: highlight ? Colors.white : Colors.black.withOpacity(0.45),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        child: Column(
          children: [
            Icon(icon, color: highlight ? const Color(0xFFFF2D55) : Colors.white, size: 26),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: highlight ? const Color(0xFFFF2D55) : Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}