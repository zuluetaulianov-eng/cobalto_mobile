import 'package:flutter/foundation.dart';

/// Logger centralizado de COBALTO.
/// En debug emite trazas clasificadas por severidad; en release conserva los
/// errores para diagnóstico. Nunca registra secretos ni datos sensibles.
class AppLogger {
  static const String _tag = 'COBALTO';

  static void info(String message, {String tag = _tag}) {
    if (kDebugMode) debugPrint('[INFO][$tag] $message');
  }

  static void warn(String message,
      {String tag = _tag, Object? error, StackTrace? stack}) {
    if (kDebugMode) debugPrint('⚠️ [WARN][$tag] $message');
    _logExtra(error, stack);
  }

  static void error(String message, {String tag = _tag, Object? error, StackTrace? stack}) {
    debugPrint('❌ [ERROR][$tag] $message');
    _logExtra(error, stack);
  }

  static void _logExtra(Object? error, StackTrace? stack) {
    if (error != null) debugPrint('   → $error');
    if (stack != null && kDebugMode) {
      final lines = stack.toString().split('\n').take(6).join('\n');
      debugPrint('   $lines');
    }
  }
}
