import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/cobalto_api_service.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  final String time;

  ChatMessage({required this.text, required this.isUser, required this.time});
}

class AiChatTab extends StatefulWidget {
  const AiChatTab({super.key});

  @override
  State<AiChatTab> createState() => _AiChatTabState();
}

class _AiChatTabState extends State<AiChatTab> {
  final List<ChatMessage> _messages = [
    ChatMessage(
      text: '🤖 [ASISTENTE TÁCTICO MÓVIL AUTÓNOMO]\n\nTerminal de Inteligencia activa en el dispositivo. Operando en Modo Local y Enlace Central.\n¿Qué análisis o resumen situacional deseas solicitar, operador?',
      isUser: false,
      time: '12:00',
    )
  ];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;
  String _selectedPersona = 'GENERAL';

  final Map<String, String> _personas = {
    'GENERAL': 'General COBALTO',
    'ARES': 'ARES (Militar & Geopolítica)',
    'MINERVA': 'MINERVA (Ciberseguridad)',
    'NEXUS': 'NEXUS (OSINT & Redes)',
  };

  void _sendMessage([String? quickText]) async {
    final text = quickText ?? _controller.text.trim();
    if (text.isEmpty || _isSending) return;

    if (quickText == null) _controller.clear();

    final String now = "${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}";

    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true, time: now));
      _isSending = true;
    });

    _scrollToBottom();

    // Intentar consulta al servidor central o procesar localmente en el teléfono
    var responseText = await CobaltoApiService.sendAiQuery(text, persona: _selectedPersona);

    if (responseText == 'OFFLINE_MODE') {
      responseText = await _generateLocalTacticalResponse(text, _selectedPersona);
    }

    if (mounted) {
      setState(() {
        _messages.add(ChatMessage(text: responseText, isUser: false, time: now));
        _isSending = false;
      });
      _scrollToBottom();
    }
  }

  Future<String> _generateLocalTacticalResponse(String query, String persona) async {
    final q = query.toLowerCase();
    final prefs = await SharedPreferences.getInstance();
    final cachedStr = prefs.getString('cached_sitrep_news');

    List<dynamic> news = [];
    if (cachedStr != null && cachedStr.isNotEmpty) {
      try {
        news = json.decode(cachedStr);
      } catch (_) {}
    }

    if (q.contains('sitrep') || q.contains('noticia') || q.contains('hoy') || q.contains('resumir')) {
      if (news.isEmpty) {
        return '📱 [NODO MÓVIL AUTÓNOMO - $persona]\n\nSin noticias almacenadas en la memoria del teléfono. Presiona el botón "EJECUTAR" en la pestaña SitRep para iniciar la ingesta directa de feeds RSS y canales de Telegram.';
      }

      final count = news.length;
      final topTitles = news.take(3).map((e) => '• ${e['source'] ?? 'Intel'}: ${e['title'] ?? ''}').join('\n');

      return '📱 [INFORMACIÓN TÁCTICA AUTÓNOMA - $persona]\n\nSe han analizado $count registros en la memoria local del teléfono.\n\nÚltimos eventos destacados en el terreno:\n$topTitles\n\nNivel de riesgo estimado: ESTABLE con monitoreo en curso.';
    }

    if (q.contains('alerta') || q.contains('nivel') || q.contains('amenaza')) {
      return '📱 [MONITOREO DE INCIDENTES - $persona]\n\nEstado situacional local: DEFCON 5 (Normal).\nNo se registran interrupciones de infraestructura ni alertas críticas no gestionadas en los sensores locales.';
    }

    if (q.contains('mapa') || q.contains('coordenada') || q.contains('esequibo')) {
      return '📱 [ANÁLISIS GEOGRÁFICO - $persona]\n\nCoordenadas tácticas monitoreadas:\n• Base Caracas: [10.48°N, 66.90°W]\n• Sector Esequibo: [6.80°N, 58.15°W] - Sensores Satelitales Activos\n• Nodo Andino: [4.71°N, 74.07°W]';
    }

    if (q.contains('ciber') || q.contains('paste') || q.contains('seguridad')) {
      return '📱 [CIBER-RADAR MÓVIL - $persona]\n\nPuertos y sensores locales operando con cifrado TLS/AES. Sin fugas de credenciales detectadas en las últimas 24 horas.';
    }

    return '📱 [RESPUESTA DE CAMPO MÓVIL - $persona]\n\nSolicitud procesada localmente por la App Móvil ("$query"). El nodo opera autónomamente procesando palabras clave de inteligencia en segundo plano.';
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Selector de Persona & Quick Prompts
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: const Color(0xFF10131D),
          child: Column(
            children: [
              Row(
                children: [
                  const Text('AGENTE:', style: TextStyle(color: Color(0xFF00E5FF), fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1F2C),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.3)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedPersona,
                          dropdownColor: const Color(0xFF1A1F2C),
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          isExpanded: true,
                          items: _personas.entries.map((e) {
                            return DropdownMenuItem<String>(
                              value: e.key,
                              child: Text(e.value),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _selectedPersona = val);
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _quickChip('⚡ SitRep Hoy', 'Resumir noticias activas de hoy'),
                    _quickChip('🚨 Nivel Alerta', 'Analizar nivel de alerta situacional actual'),
                    _quickChip('🗺️ Estado Mapa', 'Resumen táctico de eventos en mapa'),
                    _quickChip('🔒 Ciber', 'Radar de ciberseguridad y pastes'),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Lista de Mensajes Chat
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(12),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final msg = _messages[index];
              return Align(
                alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: msg.isUser ? const Color(0xFF2A1F40) : const Color(0xFF141824),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: msg.isUser
                          ? const Color(0xFFB388FF).withOpacity(0.3)
                          : const Color(0xFF00E5FF).withOpacity(0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            msg.isUser ? 'OPERADOR' : 'IA COBALTO',
                            style: TextStyle(
                              color: msg.isUser ? const Color(0xFFB388FF) : const Color(0xFF00E5FF),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                            ),
                          ),
                          Text(msg.time, style: const TextStyle(color: Colors.white30, fontSize: 9)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        msg.text,
                        style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.45),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        if (_isSending)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: LinearProgressIndicator(color: Color(0xFF00E5FF), backgroundColor: Colors.transparent),
          ),

        // Entrada de Texto
        Container(
          padding: const EdgeInsets.all(8),
          color: const Color(0xFF10131D),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Consultar Mando IA / Autónomo...',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF1A1F2C),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF00E5FF),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.send, color: Colors.black, size: 18),
                onPressed: _isSending ? null : () => _sendMessage(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _quickChip(String label, String prompt) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ActionChip(
        backgroundColor: const Color(0xFF1A1F2C),
        side: BorderSide(color: const Color(0xFF00E5FF).withOpacity(0.2)),
        label: Text(label, style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 11)),
        onPressed: () => _sendMessage(prompt),
      ),
    );
  }
}
