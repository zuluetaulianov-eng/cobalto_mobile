import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_logger.dart';
import 'emergency_service.dart';

/// PÁNICO 0-CLIC AEGIS (FASE 5): dispara el SOS sin tocar la pantalla.
///
/// **Disparador implementado**: Volumen DOWN × 3 en ≤ 2 segundos.
///
/// **Descartado**: Botón de encendido × 5 — no accesible de forma fiable
/// via SDK; AccessibilityService es frágil y matado por OEMs
/// (Xiaomi/Huawei/Oppo). Documentado como riesgo R-FASE5.
///
/// ## Integración
/// 1. Llama [ZeroClickPanicService.attach()] dentro del `State` de la pantalla
///    principal (o en cualquier widget raíz con `Focus`).
/// 2. El widget raíz debe tener `focusNode` con `canRequestFocus = true` y
///    escuchar `KeyDownEvent` via `HardwareKeyboard.instance.addHandler`.
/// 3. Llama [ZeroClickPanicService.dispose()] en el `dispose` del widget.
///
/// ## Flujo de confirmación
/// Por seguridad, al tercer toque de VOL_DOWN se muestra una notificación
/// de advertencia + confirmación visual (callback [onConfirmationRequired]).
/// Si el callback no está conectado (background), el SOS se dispara directo.
class ZeroClickPanicService {
  static const String _enabledKey = 'aegis_zero_click_enabled';
  static const String _pressesKey = 'aegis_zero_click_presses'; // count en prefs (debug)
  static const int _targetPresses = 3;
  static const Duration _window = Duration(seconds: 2);

  static bool _handlerAttached = false;
  static int _pressCount = 0;
  static DateTime? _firstPressAt;
  static Timer? _resetTimer;

  /// Callback invocado cuando se necesita confirmación visual antes del SOS.
  /// Si es null, el SOS se dispara inmediatamente tras el tercer toque.
  static void Function()? onConfirmationRequired;

  /// Callback invocado cuando el SOS se dispara (para actualizar la UI).
  static void Function()? onPanicTriggered;

  // ── CONFIGURACIÓN ──

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? true;
  }

  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
    if (!enabled) _reset();
    debugPrint('⚡ Pánico 0-clic ${enabled ? 'ACTIVADO' : 'DESACTIVADO'}.');
  }

  // ── MANEJO DE TECLAS ──

  /// Registra el handler de teclado global.
  /// Seguro para llamar múltiples veces (idempotente).
  static void attach() {
    if (_handlerAttached) return;
    HardwareKeyboard.instance.addHandler(_handleKey);
    _handlerAttached = true;
    debugPrint('⚡ ZeroClick: handler de teclado registrado.');
  }

  static void detach() {
    if (!_handlerAttached) return;
    HardwareKeyboard.instance.removeHandler(_handleKey);
    _handlerAttached = false;
    _reset();
  }

  static bool _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final logical = event.logicalKey;
    if (logical != LogicalKeyboardKey.audioVolumeDown) return false;

    _onVolumeDown();
    // Retornamos FALSE: no consumimos el evento; el sistema sigue bajando el volumen.
    // Esto es intencional: no queremos que el operador note comportamiento anómalo.
    return false;
  }

  static void _onVolumeDown() {
    final now = DateTime.now();

    if (_pressCount == 0 || _firstPressAt == null) {
      _firstPressAt = now;
      _pressCount = 1;
    } else {
      final elapsed = now.difference(_firstPressAt!);
      if (elapsed > _window) {
        // Ventana expirada: reinicia la secuencia.
        _firstPressAt = now;
        _pressCount = 1;
      } else {
        _pressCount++;
      }
    }

    _resetTimer?.cancel();
    _resetTimer = Timer(_window, _reset);

    debugPrint('⚡ VOL_DOWN: $_pressCount/$_targetPresses');

    if (_pressCount >= _targetPresses) {
      _reset();
      _triggerOrConfirm();
    }
  }

  static void _reset() {
    _pressCount = 0;
    _firstPressAt = null;
    _resetTimer?.cancel();
    _resetTimer = null;
  }

  static Future<void> _triggerOrConfirm() async {
    final enabled = await isEnabled();
    if (!enabled) return;

    AppLogger.warn('⚡ Pánico 0-clic VOL_DOWN×3 detectado.', tag: 'ZeroClick');

    if (onConfirmationRequired != null) {
      // Con UI activa: dar 3 segundos de ventana de cancelación.
      onConfirmationRequired!();
    } else {
      // Background / sin UI: SOS directo.
      await _firePanic();
    }
  }

  /// Dispara el SOS. Puede llamarse desde la UI tras confirmación.
  static Future<void> firePanicConfirmed() async {
    final enabled = await isEnabled();
    if (!enabled) return;
    await _firePanic();
  }

  static Future<void> _firePanic() async {
    onPanicTriggered?.call();
    AppLogger.warn('🚨 Pánico 0-clic CONFIRMADO → EmergencyService.triggerPanic()', tag: 'ZeroClick');
    await EmergencyService().triggerPanic();
  }

  static void dispose() {
    detach();
  }
}
