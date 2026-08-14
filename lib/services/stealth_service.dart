import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Servicio para gestión de Modo Sigilo y Visión Nocturna (NVG).
/// Optimizado para bajo perfil fotónico y alertas silenciosas hápticas.
class StealthService extends ChangeNotifier {
  static final StealthService _instance = StealthService._internal();
  factory StealthService() => _instance;
  StealthService._internal();

  bool _isStealthActive = false;
  bool get isStealthActive => _isStealthActive;

  /// Alterna el modo sigilo
  void toggleStealth() {
    _isStealthActive = !_isStealthActive;
    if (_isStealthActive) {
      triggerHapticPattern(DEFCONLevel.stealthOn);
    } else {
      HapticFeedback.mediumImpact();
    }
    notifyListeners();
  }

  /// Colores del tema según el modo activo
  Color get backgroundColor => _isStealthActive ? const Color(0xFF080000) : const Color(0xFF0F172A);
  Color get surfaceColor => _isStealthActive ? const Color(0xFF1F0000) : const Color(0xFF1E293B);
  Color get accentColor => _isStealthActive ? const Color(0xFFFF1E1E) : const Color(0xFF00E5FF);
  Color get textColor => _isStealthActive ? const Color(0xFFFF6B6B) : Colors.white;
  Color get subtextColor => _isStealthActive ? const Color(0xFF993333) : Colors.grey;

  /// Emite patrones hápticos de vibración en código Morse/pulsos según nivel de alerta
  Future<void> triggerHapticPattern(DEFCONLevel level) async {
    switch (level) {
      case DEFCONLevel.stealthOn:
        await HapticFeedback.heavyImpact();
        await Future.delayed(const Duration(milliseconds: 100));
        await HapticFeedback.heavyImpact();
        break;
      case DEFCONLevel.critical:
        // Patrón SOS / Crítico (... --- ...)
        for (int i = 0; i < 3; i++) {
          await HapticFeedback.vibrate();
          await Future.delayed(const Duration(milliseconds: 100));
        }
        await Future.delayed(const Duration(milliseconds: 250));
        for (int i = 0; i < 3; i++) {
          await HapticFeedback.heavyImpact();
          await Future.delayed(const Duration(milliseconds: 200));
        }
        break;
      case DEFCONLevel.warning:
        await HapticFeedback.mediumImpact();
        await Future.delayed(const Duration(milliseconds: 150));
        await HapticFeedback.mediumImpact();
        break;
      case DEFCONLevel.info:
        await HapticFeedback.lightImpact();
        break;
    }
  }
}

enum DEFCONLevel { stealthOn, info, warning, critical }
