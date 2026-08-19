import 'dart:async';

import 'package:flutter/material.dart';

import '../services/aegis_triage_service.dart';

/// Pantalla de Triaje de Primeros Auxilios AEGIS (FASE 4).
///
/// 100% offline: no depende de red ni de servidor.
/// Flujo: selección de protocolo → pasos secuenciales con bifurcaciones →
/// metrónomo RCP integrado → regreso al índice.
class AegisTriageScreen extends StatefulWidget {
  const AegisTriageScreen({super.key});

  @override
  State<AegisTriageScreen> createState() => _AegisTriageScreenState();
}

class _AegisTriageScreenState extends State<AegisTriageScreen> {
  String? _activeProtocol;
  List<TriageStep>? _steps;
  int _stepIndex = 0;
  final List<int> _history = []; // Historial de índices para "Atrás".

  @override
  void dispose() {
    AegisTriageService.stopMetronome();
    AegisTriageService.stopSpeaking();
    super.dispose();
  }

  void _startProtocol(String id) {
    final steps = AegisTriageService.getProtocol(id);
    if (steps == null) return;
    setState(() {
      _activeProtocol = id;
      _steps = steps;
      _stepIndex = 0;
      _history.clear();
    });
    AegisTriageService.stopMetronome();
    _speakCurrentStep(steps[0]);
  }

  void _resetToIndex() {
    AegisTriageService.stopMetronome();
    AegisTriageService.stopSpeaking();
    setState(() {
      _activeProtocol = null;
      _steps = null;
      _stepIndex = 0;
      _history.clear();
    });
  }

  void _nextStep() {
    final steps = _steps;
    if (steps == null) return;
    final current = steps[_stepIndex];
    // Si hay opciones en el paso actual, no se puede "siguiente" directo.
    if (current.options != null) return;
    final nextIndex = _stepIndex + 1;
    if (nextIndex >= steps.length) return;
    _history.add(_stepIndex);
    AegisTriageService.stopMetronome();
    setState(() => _stepIndex = nextIndex);
    _speakCurrentStep(steps[nextIndex]);
  }

  void _prevStep() {
    if (_history.isEmpty) {
      _resetToIndex();
      return;
    }
    AegisTriageService.stopMetronome();
    setState(() => _stepIndex = _history.removeLast());
    if (_steps != null) _speakCurrentStep(_steps![_stepIndex]);
  }

  void _chooseOption(TriageOption option) {
    final steps = _steps;
    if (steps == null) return;
    final targetIndex = steps.indexWhere((s) => s.id == option.nextId);
    if (targetIndex < 0) return;
    _history.add(_stepIndex);
    AegisTriageService.stopMetronome();
    setState(() => _stepIndex = targetIndex);
    _speakCurrentStep(steps[targetIndex]);
  }

  void _speakCurrentStep(TriageStep step) {
    AegisTriageService.speak('${step.title}. ${step.instruction}');
  }

  // ── METRÓNOMO ──

  bool _metronomeRunning = false;
  Timer? _metroUiTimer;

  void _toggleMetronome() async {
    if (_metronomeRunning) {
      AegisTriageService.stopMetronome();
      _metroUiTimer?.cancel();
      setState(() => _metronomeRunning = false);
    } else {
      await AegisTriageService.startMetronome();
      setState(() => _metronomeRunning = true);
      // El botón late visualmente mientras el metrónomo corre.
      _metroUiTimer = Timer.periodic(const Duration(milliseconds: 545), (_) {
        if (mounted && _metronomeRunning) setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = _steps;
    final hasActiveProtocol = _activeProtocol != null && steps != null;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0B10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF10131D),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white70),
          onPressed: hasActiveProtocol ? _resetToIndex : () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            const Icon(Icons.medical_services, color: Color(0xFFFF2D55), size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hasActiveProtocol
                    ? AegisTriageService.availableProtocols
                        .firstWhere(
                          (p) => p['id'] == _activeProtocol,
                          orElse: () => {'title': 'TRIAJE'},
                        )['title']!
                        .toUpperCase()
                    : 'TRIAJE DE PRIMEROS AUXILIOS',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          // Indicador offline
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF00FFAA).withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF00FFAA).withOpacity(0.4)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wifi_off, size: 10, color: Color(0xFF00FFAA)),
                SizedBox(width: 4),
                Text(
                  'OFFLINE',
                  style: TextStyle(
                    color: Color(0xFF00FFAA),
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: hasActiveProtocol
          ? _buildStepView(steps)
          : _buildProtocolIndex(),
    );
  }

  // ── ÍNDICE DE PROTOCOLOS ──

  Widget _buildProtocolIndex() {
    final protocols = AegisTriageService.availableProtocols;
    final criticals = protocols.where((p) => p['category'] == 'CRÍTICO').toList();
    final graves = protocols.where((p) => p['category'] == 'GRAVE').toList();
    final moderados = protocols.where((p) => p['category'] == 'MODERADO').toList();

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // Banner de aviso
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFF2D55).withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFFF2D55).withOpacity(0.4)),
          ),
          child: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFFF9500), size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'GUÍAS DE PRIMEROS AUXILIOS OFFLINE\n'
                  'Estas guías NO sustituyen atención médica profesional. '
                  'Son apoyo en situaciones sin acceso médico inmediato.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontFamily: 'monospace',
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _sectionHeader('⚠️ EMERGENCIAS CRÍTICAS', const Color(0xFFFF2D55)),
        const SizedBox(height: 8),
        ...criticals.map((p) => _protocolCard(p)),
        const SizedBox(height: 16),
        _sectionHeader('🔴 SITUACIONES GRAVES', const Color(0xFFFF9500)),
        const SizedBox(height: 8),
        ...graves.map((p) => _protocolCard(p)),
        const SizedBox(height: 16),
        _sectionHeader('🟡 SITUACIONES MODERADAS', const Color(0xFFFFD60A)),
        const SizedBox(height: 8),
        ...moderados.map((p) => _protocolCard(p)),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _sectionHeader(String title, Color color) {
    return Row(
      children: [
        Container(width: 3, height: 20, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _protocolCard(Map<String, String> p) {
    final categoryColor = switch (p['category']) {
      'CRÍTICO' => const Color(0xFFFF2D55),
      'GRAVE' => const Color(0xFFFF9500),
      _ => const Color(0xFFFFD60A),
    };
    return GestureDetector(
      onTap: () => _startProtocol(p['id']!),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF141824),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: categoryColor.withOpacity(0.35)),
        ),
        child: Row(
          children: [
            Text(p['emoji']!, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p['title']!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: categoryColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      p['category']!,
                      style: TextStyle(color: categoryColor, fontSize: 9, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: categoryColor.withOpacity(0.7), size: 22),
          ],
        ),
      ),
    );
  }

  // ── VISTA DE PASO ──

  Widget _buildStepView(List<TriageStep> steps) {
    final step = steps[_stepIndex];
    final isLast = _stepIndex == steps.length - 1;
    final hasOptions = step.options != null && step.options!.isNotEmpty;
    final total = steps.length;

    return Column(
      children: [
        // Barra de progreso
        LinearProgressIndicator(
          value: ((_stepIndex + 1) / total).clamp(0.0, 1.0),
          backgroundColor: Colors.white12,
          color: const Color(0xFF00E5FF),
          minHeight: 3,
        ),

        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              // Contador de paso
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'PASO ${_stepIndex + 1} / $total',
                    style: const TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace'),
                  ),
                  if (step.hasCprMetronome)
                    Text(
                      '💗 RCP 100-120 BPM',
                      style: TextStyle(
                        color: _metronomeRunning ? const Color(0xFFFF2D55) : Colors.white38,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // Título del paso
              Text(
                step.title,
                style: const TextStyle(
                  color: Color(0xFF00E5FF),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 14),

              // Instrucción principal
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF141824),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.2)),
                ),
                child: Text(
                  step.instruction,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.6,
                    fontFamily: 'monospace',
                  ),
                ),
              ),

              // TIP
              if (step.tip != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9500).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFF9500).withOpacity(0.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.lightbulb_outline, color: Color(0xFFFF9500), size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          step.tip!,
                          style: const TextStyle(color: Color(0xFFFFD60A), fontSize: 12, fontFamily: 'monospace', height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // METRÓNOMO RCP
              if (step.hasCprMetronome) ...[
                const SizedBox(height: 16),
                _buildMetronomeButton(),
              ],

              // OPCIONES DE BIFURCACIÓN
              if (hasOptions) ...[
                const SizedBox(height: 20),
                const Text(
                  '¿QUÉ OBSERVAS?',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                ...step.options!.map((option) => _buildOptionButton(option)),
              ],

              const SizedBox(height: 20),

              // TTS — leer instrucción
              GestureDetector(
                onTap: () => _speakCurrentStep(step),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.volume_up, color: Colors.white38, size: 16),
                      SizedBox(width: 6),
                      Text(
                        'LEER EN VOZ ALTA',
                        style: TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Navegación inferior
        if (!hasOptions)
          _buildNavBar(isLast),
      ],
    );
  }

  Widget _buildMetronomeButton() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: _metronomeRunning
            ? const Color(0xFFFF2D55).withOpacity(0.15)
            : const Color(0xFF141824),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _metronomeRunning ? const Color(0xFFFF2D55) : const Color(0xFFFF2D55).withOpacity(0.4),
          width: _metronomeRunning ? 2 : 1,
        ),
        boxShadow: _metronomeRunning
            ? [BoxShadow(color: const Color(0xFFFF2D55).withOpacity(0.3), blurRadius: 12, spreadRadius: 2)]
            : [],
      ),
      child: ListTile(
        leading: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Icon(
            _metronomeRunning ? Icons.pause_circle_filled : Icons.play_circle_filled,
            color: const Color(0xFFFF2D55),
            size: 36,
            key: ValueKey(_metronomeRunning),
          ),
        ),
        title: Text(
          _metronomeRunning ? '⏸ DETENER METRÓNOMO RCP' : '💗 INICIAR METRÓNOMO 110 BPM',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
        subtitle: Text(
          _metronomeRunning
              ? 'Contando compresiones... 30 + 2 soplos'
              : 'Guía el ritmo de compresiones torácicas',
          style: const TextStyle(color: Colors.white54, fontSize: 10),
        ),
        onTap: _toggleMetronome,
      ),
    );
  }

  Widget _buildOptionButton(TriageOption option) {
    return GestureDetector(
      onTap: () => _chooseOption(option),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF00E5FF).withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.5)),
        ),
        child: Row(
          children: [
            const Icon(Icons.chevron_right, color: Color(0xFF00E5FF), size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                option.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavBar(bool isLast) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF10131D),
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        children: [
          // ATRÁS
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _prevStep,
              icon: const Icon(Icons.arrow_back, size: 16),
              label: Text(_history.isEmpty ? 'PROTOCOLOS' : 'ATRÁS'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Colors.white24),
                padding: const EdgeInsets.symmetric(vertical: 12),
                textStyle: const TextStyle(fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // SIGUIENTE / FIN
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: isLast ? _resetToIndex : _nextStep,
              icon: Icon(isLast ? Icons.check_circle : Icons.arrow_forward, size: 16),
              label: Text(isLast ? 'FINALIZAR PROTOCOLO' : 'SIGUIENTE PASO'),
              style: ElevatedButton.styleFrom(
                backgroundColor: isLast ? const Color(0xFF00FFAA) : const Color(0xFF00E5FF),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 12),
                textStyle: const TextStyle(fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
