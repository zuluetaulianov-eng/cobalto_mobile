import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'app_logger.dart';
import 'package:speech_to_text/speech_to_text.dart';

class VoiceService {
  static final SpeechToText _speechToText = SpeechToText();
  static final FlutterTts _flutterTts = FlutterTts();

  static bool _isSpeechInitialized = false;
  static bool _isTtsInitialized = false;
  static bool _isListening = false;
  static bool _isSpeaking = false;

  static bool get isListening => _isListening;
  static bool get isSpeaking => _isSpeaking;

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

  /// Inicializa el sintetizador de voz auditivo (TTS)
  static Future<void> initTts() async {
    if (_isTtsInitialized) return;
    try {
      await _flutterTts.setLanguage('es-ES');
      await _flutterTts.setPitch(1.0);
      await _flutterTts.setSpeechRate(0.48); // Velocidad clara táctica militar

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

  /// Lee auditivamente por altavoz una alerta táctica
  static Future<void> speakAlert({
    required String title,
    required String body,
    String level = 'ALTA',
  }) async {
    await initTts();
    if (_isSpeaking) {
      await stopSpeech();
    }

    final String message = 'Atención Operador. Alerta táctica nivel $level. $title. $body';
    try {
      await _flutterTts.speak(message);
    } catch (e) {
      debugPrint('⚠️ Error al reproducir audio TTS: $e');
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
