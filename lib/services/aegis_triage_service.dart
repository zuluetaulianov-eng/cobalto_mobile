import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_logger.dart';

/// Paso de triaje de primeros auxilios offline.
class TriageStep {
  final String id;
  final String title;
  final String instruction;
  final String? tip;
  final bool hasCprMetronome; // Si true, activa el metrónomo 100-120 BPM.
  final List<TriageOption>? options; // Bifurcación de decisión (null = lineal).

  const TriageStep({
    required this.id,
    required this.title,
    required this.instruction,
    this.tip,
    this.hasCprMetronome = false,
    this.options,
  });
}

class TriageOption {
  final String label;
  final String nextId; // ID del siguiente paso.
  const TriageOption({required this.label, required this.nextId});
}

/// TRIAJE DE PRIMEROS AUXILIOS AEGIS (FASE 4).
///
/// Guías offline de primeros auxilios con:
///  - TTS (Text-to-Speech) via flutter_tts para instrucciones manos libres.
///  - Metrónomo de RCP a 100-120 BPM (Timer periódico + TTS).
///  - Flujo de decisión árbol: bifurcación por condición del paciente.
///  - 100% offline: ningún protocolo depende de conectividad.
class AegisTriageService {
  static const String _ttsEnabledKey = 'aegis_triage_tts_enabled';
  static const String _metronomeRunningKey = 'aegis_triage_metro_running';

  // Metrónomo: 110 BPM nominal (rango 100-120 según AHA).
  static const int _bpmNominal = 110;
  static const Duration _bpmInterval = Duration(milliseconds: 545); // 60000/110

  static FlutterTts? _tts;
  static Timer? _metronomeTimer;
  static bool _metronomeActive = false;
  static bool get isMetronomeActive => _metronomeActive;

  /// Todos los protocolos disponibles offline.
  static const Map<String, List<TriageStep>> _protocols = {
    'cpr_adult': _cprAdult,
    'choking_adult': _chokingAdult,
    'bleeding': _bleedingControl,
    'unconscious': _unconscious,
    'shock': _shockProtocol,
    'burns': _burnsProtocol,
    'fracture': _fractureProtocol,
  };

  static List<TriageStep>? getProtocol(String id) => _protocols[id];

  static List<Map<String, String>> get availableProtocols => const [
        {'id': 'cpr_adult', 'title': 'RCP Adulto', 'emoji': '💗', 'category': 'CRÍTICO'},
        {'id': 'choking_adult', 'title': 'Atragantamiento Adulto', 'emoji': '🫁', 'category': 'CRÍTICO'},
        {'id': 'unconscious', 'title': 'Persona Inconsciente', 'emoji': '🧠', 'category': 'CRÍTICO'},
        {'id': 'bleeding', 'title': 'Control de Hemorragia', 'emoji': '🩸', 'category': 'GRAVE'},
        {'id': 'shock', 'title': 'Choque / Shock', 'emoji': '⚡', 'category': 'GRAVE'},
        {'id': 'burns', 'title': 'Quemaduras', 'emoji': '🔥', 'category': 'MODERADO'},
        {'id': 'fracture', 'title': 'Fracturas / Inmovilización', 'emoji': '🦴', 'category': 'MODERADO'},
      ];

  // ── TTS (TEXT-TO-SPEECH) ──

  static Future<void> _initTts() async {
    _tts ??= FlutterTts();
    await _tts!.setLanguage('es-ES');
    await _tts!.setSpeechRate(0.45); // Lento y claro para situaciones de estrés.
    await _tts!.setVolume(1.0);
    await _tts!.setPitch(1.0);
  }

  static Future<bool> isTtsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_ttsEnabledKey) ?? true;
  }

  static Future<void> setTtsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_ttsEnabledKey, enabled);
    if (!enabled) await stopSpeaking();
  }

  /// Vocaliza una instrucción de triaje si TTS está habilitado.
  static Future<void> speak(String text) async {
    if (!await isTtsEnabled()) return;
    try {
      await _initTts();
      await _tts!.stop();
      await _tts!.speak(text);
    } catch (e) {
      AppLogger.warn('TTS no disponible.', tag: 'Triage', error: e);
    }
  }

  static Future<void> stopSpeaking() async {
    try {
      await _tts?.stop();
    } catch (e) {
      // Silencioso.
    }
  }

  // ── METRÓNOMO DE RCP ──

  /// Inicia el metrónomo de RCP a [_bpmNominal] BPM.
  /// Emite "UNO" cada pulso por TTS + vibración de reloj.
  static Future<void> startMetronome() async {
    if (_metronomeActive) return;
    _metronomeActive = true;
    try {
      await _initTts();
      int count = 0;
      _metronomeTimer = Timer.periodic(_bpmInterval, (_) async {
        count++;
        // Cada 30 compresiones (ciclo AHA): recordar "SOPLO" (en soporte vital básico).
        if (count % 30 == 0) {
          try {
            await _tts!.speak('Soplo. Soplo.');
            count = 0;
          } catch (e) {
            // Ignorar.
          }
        } else {
          try {
            await _tts!.speak(count.toString());
          } catch (e) {
            // Ignorar.
          }
        }
      });
      debugPrint('💗 Metrónomo RCP iniciado a $_bpmNominal BPM.');
    } catch (e) {
      _metronomeActive = false;
      AppLogger.warn('Metrónomo RCP no disponible.', tag: 'Triage', error: e);
    }
  }

  static void stopMetronome() {
    _metronomeTimer?.cancel();
    _metronomeTimer = null;
    _metronomeActive = false;
    _tts?.stop();
    debugPrint('💗 Metrónomo RCP detenido.');
  }

  static void dispose() {
    stopMetronome();
    _tts?.stop();
    _tts = null;
  }

  // ── PROTOCOLOS OFFLINE ──

  static const List<TriageStep> _cprAdult = [
    TriageStep(
      id: 'cpr_1',
      title: '1. Verifica Seguridad',
      instruction: 'Asegúrate de que la escena es segura para ti y para la víctima antes de acercarte.',
      tip: 'Nunca pongas en riesgo tu propia vida.',
    ),
    TriageStep(
      id: 'cpr_2',
      title: '2. Verifica Respuesta',
      instruction: 'Sacude los hombros de la víctima firmemente y pregunta en voz alta: "¿Estás bien?".',
      options: [
        TriageOption(label: 'Responde / Se mueve', nextId: 'cpr_end_ok'),
        TriageOption(label: 'No responde', nextId: 'cpr_3'),
      ],
    ),
    TriageStep(
      id: 'cpr_3',
      title: '3. Llama Ayuda',
      instruction: 'Grita pidiendo ayuda. Pide a alguien que llame a los servicios de emergencia. '
          'Si estás solo, llama tú mismo antes de iniciar RCP (o activa el altavoz).',
    ),
    TriageStep(
      id: 'cpr_4',
      title: '4. Verifica Respiración',
      instruction: 'Inclina la cabeza hacia atrás y levanta el mentón. '
          'Observa, escucha y siente si hay respiración normal durante máximo 10 segundos.',
      options: [
        TriageOption(label: 'Respira con normalidad', nextId: 'cpr_recovery'),
        TriageOption(label: 'No respira / jadea', nextId: 'cpr_5'),
      ],
    ),
    TriageStep(
      id: 'cpr_5',
      title: '5. Inicia Compresiones',
      instruction: 'Coloca el talón de una mano en el centro del pecho (esternón). '
          'Entrelaza la otra mano encima. Mantén los brazos rectos.\n\n'
          'Comprime FUERTE y RÁPIDO: 5-6 cm de profundidad, '
          '100-120 veces por minuto. '
          'Deja que el pecho se eleve completamente entre compresiones.',
      hasCprMetronome: true,
      tip: 'Cuenta en voz alta. Cambia de reanimador cada 2 minutos si es posible.',
    ),
    TriageStep(
      id: 'cpr_6',
      title: '6. Ventilaciones de Rescate',
      instruction: 'Tras 30 compresiones: inclina la cabeza, cierra la nariz, '
          'cubre la boca y sopla 2 veces (1 segundo cada una). '
          'El pecho debe elevarse.\n\nRepite ciclo: 30 compresiones + 2 ventilaciones.',
      tip: 'Si no sabes o no puedes hacer ventilaciones, continúa solo con compresiones.',
    ),
    TriageStep(
      id: 'cpr_recovery',
      title: 'Posición Lateral de Seguridad',
      instruction: 'La víctima respira. Colócala en posición lateral de seguridad: '
          'gira hacia un lado, brazo superior doblado bajo la cabeza, '
          'rodilla superior doblada hacia adelante. Vigila la respiración.',
    ),
    TriageStep(
      id: 'cpr_end_ok',
      title: '✅ Víctima Consciente',
      instruction: 'La víctima responde. Mantenla cómoda y cálida. '
          'No le des de comer ni beber. Vigila su estado hasta que llegue la ayuda.',
    ),
  ];

  static const List<TriageStep> _chokingAdult = [
    TriageStep(
      id: 'chk_1',
      title: '1. Confirma Atragantamiento',
      instruction: 'Pregunta: "¿Te estás atragantando?". Si no puede hablar, toser ni respirar, actúa de inmediato.',
      options: [
        TriageOption(label: 'Puede toser fuerte', nextId: 'chk_cough'),
        TriageOption(label: 'No puede toser / cianosis', nextId: 'chk_2'),
      ],
    ),
    TriageStep(
      id: 'chk_cough',
      title: 'Anima a Toser',
      instruction: 'Si puede toser, aliéntala a seguir tosiendo con fuerza. No interfieras. Vigila.',
    ),
    TriageStep(
      id: 'chk_2',
      title: '2. Golpes en la Espalda',
      instruction: 'Inclina a la víctima hacia adelante. '
          'Da 5 golpes fuertes entre los omóplatos con el talón de tu mano.',
      options: [
        TriageOption(label: 'El objeto salió', nextId: 'chk_end_ok'),
        TriageOption(label: 'No salió', nextId: 'chk_3'),
      ],
    ),
    TriageStep(
      id: 'chk_3',
      title: '3. Compresiones Abdominales (Heimlich)',
      instruction: 'Párate detrás de la víctima. Rodea su cintura con tus brazos. '
          'Coloca el puño entre el ombligo y el esternón. '
          'Con la otra mano, da 5 empujes FUERTES hacia adentro y hacia arriba.',
      options: [
        TriageOption(label: 'El objeto salió', nextId: 'chk_end_ok'),
        TriageOption(label: 'Sigue bloqueado', nextId: 'chk_4'),
      ],
    ),
    TriageStep(
      id: 'chk_4',
      title: '4. Repite / Inconsciente',
      instruction: 'Repite ciclos: 5 golpes espalda + 5 Heimlich. '
          'Si la víctima pierde el conocimiento, bájala al suelo suavemente '
          'e inicia RCP de inmediato. Busca el objeto en la boca antes de ventilar.',
    ),
    TriageStep(
      id: 'chk_end_ok',
      title: '✅ Vía Aérea Despejada',
      instruction: 'El objeto salió. Verifica que la víctima respira normalmente. '
          'Aunque se vea bien, debe ser evaluada médicamente (las compresiones pueden causar lesiones internas).',
    ),
  ];

  static const List<TriageStep> _bleedingControl = [
    TriageStep(
      id: 'bleed_1',
      title: '1. Protégete',
      instruction: 'Usa guantes si los tienes. Si no, usa bolsas plásticas o '
          'capas de tela para no exponerte a la sangre de la víctima.',
    ),
    TriageStep(
      id: 'bleed_2',
      title: '2. Presión Directa',
      instruction: 'Aplica presión FIRME y CONTINUA sobre la herida con un paño limpio o gasa. '
          'No levantes para revisar: si el paño se empapa, añade más encima SIN quitar el primero.',
      tip: 'La presión debe ser continua al menos 10-15 minutos.',
    ),
    TriageStep(
      id: 'bleed_3',
      title: '3. Evaluación',
      instruction: '¿La hemorragia es en extremidad con sangrado masivo y no cede?',
      options: [
        TriageOption(label: 'Sangrado controlado', nextId: 'bleed_end_ok'),
        TriageOption(label: 'Sangrado masivo en extremidad', nextId: 'bleed_tourniquet'),
      ],
    ),
    TriageStep(
      id: 'bleed_tourniquet',
      title: '4. Torniquete (Extremidades)',
      instruction: 'Aplica torniquete 5-8 cm por encima de la herida, NO sobre articulación. '
          'Aprieta hasta que cese el sangrado. '
          'ANOTA LA HORA de aplicación (crítico para el médico).\n\n'
          '⚠️ SOLO en hemorragia masiva en extremidad que no cede a presión directa.',
      tip: 'Un torniquete puede causar daño si se aplica incorrectamente. Solo como último recurso.',
    ),
    TriageStep(
      id: 'bleed_end_ok',
      title: '✅ Hemorragia Controlada',
      instruction: 'Mantén la presión. Eleva el miembro si es posible y no hay fractura. '
          'Abriga a la víctima (previene shock). Espera asistencia médica.',
    ),
  ];

  static const List<TriageStep> _unconscious = [
    TriageStep(
      id: 'unc_1',
      title: '1. Seguridad y Respuesta',
      instruction: 'Asegura la escena. Llama a la víctima y sacude los hombros.',
      options: [
        TriageOption(label: 'Responde', nextId: 'unc_end_responds'),
        TriageOption(label: 'No responde', nextId: 'unc_2'),
      ],
    ),
    TriageStep(
      id: 'unc_2',
      title: '2. Pide Ayuda',
      instruction: 'Activa servicios de emergencia. Si hay alguien, que llame mientras tú actúas.',
    ),
    TriageStep(
      id: 'unc_3',
      title: '3. Vía Aérea',
      instruction: 'Inclina la cabeza, levanta el mentón. Verifica si respira (máx. 10 s).',
      options: [
        TriageOption(label: 'Respira normalmente', nextId: 'unc_lateral'),
        TriageOption(label: 'No respira', nextId: 'unc_cpr'),
      ],
    ),
    TriageStep(
      id: 'unc_lateral',
      title: 'Posición Lateral de Seguridad',
      instruction: 'Gira a la víctima de lado para evitar aspiración. '
          'Vigila respiración continua hasta que llegue la ayuda.',
    ),
    TriageStep(
      id: 'unc_cpr',
      title: 'Inicia RCP',
      instruction: 'La víctima no respira. Inicia RCP inmediatamente (protocolo RCP Adulto).',
      hasCprMetronome: true,
    ),
    TriageStep(
      id: 'unc_end_responds',
      title: '✅ Víctima Responde',
      instruction: 'Mantenla tranquila, cómoda y cálida. Investiga la causa del desmayo '
          'antes de que intente levantarse. Busca atención médica.',
    ),
  ];

  static const List<TriageStep> _shockProtocol = [
    TriageStep(
      id: 'shock_1',
      title: '1. Reconoce el Shock',
      instruction: 'Signos: piel pálida/fría/húmeda, pulso rápido y débil, '
          'respiración rápida, confusión, sed intensa, labios azulados.',
    ),
    TriageStep(
      id: 'shock_2',
      title: '2. Posición Antishock',
      instruction: 'Acuesta a la víctima boca arriba. '
          'Eleva las piernas 30 cm si NO hay lesión en cabeza, cuello, espalda o piernas. '
          'NO muevas a la víctima si sospechas trauma espinal.',
    ),
    TriageStep(
      id: 'shock_3',
      title: '3. Calienta y Controla',
      instruction: 'Cúbre a la víctima con una manta. Controla hemorragias si las hay. '
          'No le des agua ni comida. Vigila la respiración. '
          'Tranquilízala y mantén la calma.',
    ),
    TriageStep(
      id: 'shock_4',
      title: '4. Vigilancia Continua',
      instruction: 'Monitorea: respiración, pulso y nivel de consciencia. '
          'Si pierde el conocimiento, inicia protocolo de persona inconsciente. '
          'El shock es una emergencia que requiere atención médica urgente.',
    ),
  ];

  static const List<TriageStep> _burnsProtocol = [
    TriageStep(
      id: 'burns_1',
      title: '1. Aleja del Peligro',
      instruction: 'Retira a la víctima de la fuente de calor. Protégete tú también. '
          'Apaga las llamas con una manta o haciéndola rodar.',
    ),
    TriageStep(
      id: 'burns_2',
      title: '2. Enfría la Quemadura',
      instruction: 'Aplica agua fría (no helada) sobre la zona quemada durante 10-20 minutos. '
          '⚠️ NO uses hielo, mantequilla, cremas ni pasta de dientes.',
    ),
    TriageStep(
      id: 'burns_3',
      title: '3. Evalúa la Extensión',
      instruction: 'Quemaduras graves: en cara, manos, pies, genitales, articulaciones, '
          'o que cubran más del 1% del cuerpo (palma de la mano = ~1%).',
      options: [
        TriageOption(label: 'Quemadura leve / superficial', nextId: 'burns_minor'),
        TriageOption(label: 'Quemadura grave / profunda', nextId: 'burns_major'),
      ],
    ),
    TriageStep(
      id: 'burns_minor',
      title: 'Quemadura Leve',
      instruction: 'Cubre con gasa no adherente estéril. '
          'Vigila infección en los próximos días. '
          'NO revientes ampollas.',
    ),
    TriageStep(
      id: 'burns_major',
      title: 'Quemadura Grave - Emergencia',
      instruction: 'Cubre con paño limpio no adherente. NO retires ropa pegada. '
          'Abriga a la víctima contra el shock. '
          'Emergencia médica: activa servicios de rescate de inmediato.',
    ),
  ];

  static const List<TriageStep> _fractureProtocol = [
    TriageStep(
      id: 'frac_1',
      title: '1. Reconoce la Fractura',
      instruction: 'Signos: dolor intenso, deformidad visible, hinchazón, '
          'incapacidad de mover el miembro, chasquido audible.',
    ),
    TriageStep(
      id: 'frac_2',
      title: '2. No Muevas Sin Inmovilizar',
      instruction: 'No intentes alinear o "enderezar" el hueso. '
          'Inmoviliza el miembro en la posición en que está.',
    ),
    TriageStep(
      id: 'frac_3',
      title: '3. Inmoviliza',
      instruction: 'Usa tablillas improvisadas (ramas, cartón, revista). '
          'Extiende la tablilla más allá de las articulaciones superior e inferior a la fractura. '
          'Fija con tiras de tela. No muy apretado: verifica circulación.',
    ),
    TriageStep(
      id: 'frac_4',
      title: '4. Elevación y Hielo',
      instruction: 'Eleva el miembro por encima del nivel del corazón si es posible. '
          'Aplica hielo envuelto en paño (nunca directo) en ciclos de 20 min.',
      tip: 'Toda fractura expuesta (hueso visible) es una emergencia médica urgente.',
    ),
    TriageStep(
      id: 'frac_5',
      title: '5. Vigila Circulación',
      instruction: 'Verifica debajo de la inmovilización: '
          'color de la piel, temperatura, sensibilidad y pulso distal. '
          'Si hay entumecimiento o palidez extrema, afloja el vendaje.',
    ),
  ];
}
