import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../config/api_config.dart';
import '../utils/text_sanitizer.dart';
import 'app_logger.dart';
import 'settings_persistence_service.dart';
import 'package:speech_to_text/speech_to_text.dart';

class VoiceService {
  static final SpeechToText _speechToText = SpeechToText();
  static final FlutterTts _flutterTts = FlutterTts();

  static bool _isSpeechInitialized = false;
  static bool _isTtsInitialized = false;
  static bool _isListening = false;
  static bool _isSpeaking = false;
  static bool _silentMode = false;

  static bool get isListening => _isListening;
  static bool get isSpeaking => _isSpeaking;
  static bool get silentMode => _silentMode;

  /// Carga el modo silencio (mute táctico) persistido en el dispositivo.
  static Future<void> loadSilentMode() async {
    _silentMode = await SettingsPersistenceService.isSilentModeEnabled();
  }

  /// Activa/desactiva el modo silencio: ninguna alerta se pronuncia.
  static Future<void> setSilentMode(bool enabled) async {
    _silentMode = enabled;
    await SettingsPersistenceService.saveSilentModeEnabled(enabled);
    if (enabled && _isSpeaking) {
      await stopSpeech();
    }
    if (enabled && _isListening) {
      await stopListening();
    }
  }

  /// Inicializa el motor de Reconocimiento de Voz (STT)
  static Future<bool> initSpeech() async {
    if (_isSpeechInitialized) return true;
    try {
      _isSpeechInitialized = await _speechToText.initialize(
        onStatus: (status) {
          debugPrint('🎙️ Estado STT: $status');
          if (status == 'done' || status == 'notListening') {
            _isListening = false;
          }
        },
        onError: (error) {
          debugPrint('⚠️ Error STT: $error');
          _isListening = false;
        },
      );
      return _isSpeechInitialized;
    } catch (e) {
      debugPrint('⚠️ Excepción inicializando STT: $e');
      return false;
    }
  }

  /// Inicializa el sintetizador de voz auditivo (TTS) con modulación táctica
  static Future<void> initTts() async {
    if (_isTtsInitialized) return;
    try {
      await _flutterTts.setLanguage('es-ES');
      await _flutterTts.setPitch(0.92); // Timbre autoritario tipo C4I
      await _flutterTts.setSpeechRate(0.50); // Cadencia militar clara y firme

      _flutterTts.setStartHandler(() {
        _isSpeaking = true;
      });

      _flutterTts.setCompletionHandler(() {
        _isSpeaking = false;
      });

      _flutterTts.setErrorHandler((msg) {
        _isSpeaking = false;
        debugPrint('⚠️ Error TTS: $msg');
      });

      _isTtsInitialized = true;
    } catch (e) {
      debugPrint('⚠️ Excepción inicializando TTS: $e');
    }
  }

  /// Inicia la escucha por micrófono para dictar texto en español
  static Future<void> startListening({
    required Function(String text, bool isFinal) onResult,
    VoidCallback? onListeningStarted,
  }) async {
    bool available = await initSpeech();
    if (!available) {
      debugPrint('⚠️ El sensor de micrófono STT no está disponible.');
      return;
    }

    // Guard mutuo: el micrófono y el altavoz no pueden operar a la vez.
    if (_isSpeaking) {
      await stopSpeech();
    }

    _isListening = true;
    if (onListeningStarted != null) onListeningStarted();

    try {
      await _speechToText.listen(
        localeId: 'es_ES',
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
        onResult: (result) {
          onResult(result.recognizedWords, result.finalResult);
        },
      );
    } catch (e) {
      _isListening = false;
      debugPrint('⚠️ Error al escuchar voz: $e');
    }
  }

  /// Detiene la escucha del micrófono
  static Future<void> stopListening() async {
    if (_isListening) {
      await _speechToText.stop();
      _isListening = false;
    }
  }

  /// Lee auditivamente por altavoz una alerta táctica acotada.
  /// Respeta el modo silencio, aplica el prefijo configurado y evita monólogos extensos.
  static Future<void> speakAlert({
    required String title,
    required String body,
    String level = 'ALTA',
  }) async {
    if (_silentMode) return;
    if (_isListening) return;

    await initTts();
    if (_isSpeaking) {
      await stopSpeech();
    }

    // Micro-señal táctica háptica previa a la voz
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {}

    final cleanTitle = TextSanitizer.clean(title);
    final cleanBody = TextSanitizer.clean(body);

    final prefixMode = await SettingsPersistenceService.getVoicePrefixMode();
    final username = ApiConfig.username.isNotEmpty ? ApiConfig.username : 'Operador';

    String intro = '';
    switch (prefixMode) {
      case 'direct':
        intro = '';
        break;
      case 'tactical':
        intro = 'Novedad nivel $level. ';
        break;
      case 'operator':
        intro = '$username, ';
        break;
      case 'short':
      default:
        intro = 'Alerta COBALTO. ';
        break;
    }

    // Acotar el cuerpo del mensaje (máximo 80 caracteres adicionales) para evitar lecturas infinitas
    String bodyExcerpt = '';
    if (cleanBody.isNotEmpty && cleanTitle.length < 60) {
      bodyExcerpt = cleanBody.length > 80 ? '${cleanBody.substring(0, 80)}...' : cleanBody;
    }

    final String message = '$intro$cleanTitle${bodyExcerpt.isNotEmpty ? '. $bodyExcerpt' : ''}';
    try {
      await _flutterTts.speak(message);
    } catch (e) {
      debugPrint('⚠️ Error al reproducir audio TTS: $e');
    }
  }

  /// Lee en voz alta un texto libre (ej: respuesta del asistente IA),
  /// respetando modo silencio y sin colisionar con el micrófono.
  static Future<void> speakText(String text) async {
    if (_silentMode) return;
    if (_isListening) return;

    await initTts();
    if (_isSpeaking) {
      await stopSpeech();
    }
    try {
      await _flutterTts.speak(text);
    } catch (e) {
      debugPrint('⚠️ Error al reproducir texto TTS: $e');
    }
  }

  /// Detiene cualquier reproducción de voz actual
  static Future<void> stopSpeech() async {
    try {
      await _flutterTts.stop();
      _isSpeaking = false;
    } catch (e) {
      AppLogger.warn('No se pudo detener la reproducción TTS.', tag: 'Voice', error: e);
    }
  }
}
