import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/app_logger.dart';
import '../services/cobalto_api_service.dart';
import '../services/local_extractor_service.dart';
import '../services/notification_service.dart';
import '../services/voice_service.dart';

class AlertsTab extends StatefulWidget {
  const AlertsTab({super.key});

  @override
  State<AlertsTab> createState() => _AlertsTabState();
}

class _AlertsTabState extends State<AlertsTab> {
  List<dynamic> _alerts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAlerts();
  }

  Future<void> _loadAlerts() async {
    setState(() => _isLoading = true);
    var data = await CobaltoApiService.fetchAlerts();

    // Si la API del servidor no responde o está offline, evaluar alertas críticas locales
    if (data.isEmpty) {
      data = await _evaluateLocalAlerts();
    }

    if (mounted) {
      setState(() {
        _alerts = data;
        _isLoading = false;
      });

      // Si hay alertas críticas encontradas, notificar a la barra de estado de Android
      if (data.isNotEmpty) {
        final topAlert = data.first;
        final title = topAlert['title'] ?? topAlert['name'] ?? 'Alerta de Seguridad Táctica';
        final summary = topAlert['summary'] ?? topAlert['description'] ?? 'Incidente detectado por COBALTO';
        final level = (topAlert['level'] ?? topAlert['severity'] ?? 'ALTA').toString();

        await NotificationService.showAlertNotification(
          title: title.toString(),
          body: summary.toString(),
          level: level,
        );
      }
    }
  }

  Future<List<Map<String, dynamic>>> _evaluateLocalAlerts() async {
    final List<Map<String, dynamic>> localAlerts = [];
    final prefs = await SharedPreferences.getInstance();
    final cachedStr = prefs.getString('cached_sitrep_news');

    List<dynamic> news = [];
    if (cachedStr != null && cachedStr.isNotEmpty) {
      try {
        news = json.decode(cachedStr);
      } catch (e) {
        AppLogger.warn('Cache sitrep corrupto en alerts.', tag: 'Alerts', error: e);
      }
    }

    if (news.isEmpty) {
      // Extraer si no hay caché
      news = await LocalExtractorService.extractDirectlyOnDevice();
    }

    final criticalTerms = [
      'ciberataque', 'ransomware', 'apagón', 'militar', 'sanciones',
      'explosión', 'defcon', 'terrorismo', 'ataque', 'alerta', 'conflicto', 'urgente'
    ];

    for (final item in news) {
      final title = (item['title'] ?? '').toString();
      final summary = (item['summary'] ?? '').toString();
      final fullText = '$title $summary'.toLowerCase();

      final List matched = (item['keywords_matched'] is List) ? item['keywords_matched'] : [];
      final hasCriticalTerm = criticalTerms.any((term) => fullText.contains(term));

      if (matched.isNotEmpty || hasCriticalTerm) {
        String severity = 'ALTA';
        if (fullText.contains('ransomware') || fullText.contains('apagón') || fullText.contains('defcon') || fullText.contains('explosión')) {
          severity = 'CRÍTICA';
        } else if (fullText.contains('ciberataque') || fullText.contains('militar') || fullText.contains('sanciones')) {
          severity = 'ALTA';
        } else {
          severity = 'URGENTE';
        }

        localAlerts.add({
          'title': title,
          'level': severity,
          'summary': summary.isNotEmpty ? summary : 'Incidente detectado por filtro táctico de palabras clave.',
          'timestamp': item['published'] ?? item['timestamp'] ?? '',
          'source': item['source'] ?? 'Local OSINT Filter',
        });
      }
    }

    return localAlerts;
  }

  Color _getAlertColor(String level) {
    final l = level.toUpperCase();
    if (l.contains('CRÍTICO') || l.contains('ALTA')) return const Color(0xFFFF2D55);
    if (l.contains('URGENTE') || l.contains('MEDIA')) return const Color(0xFFFF9500);
    if (l.contains('CYBER')) return const Color(0xFF00E5FF);
    return const Color(0xFFFFD60A);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: const Color(0xFFFF2D55),
      backgroundColor: const Color(0xFF0A0B10),
      onRefresh: _loadAlerts,
      child: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF2D55)),
            )
          : _alerts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.shield_outlined, size: 54, color: Color(0xFF00FFAA)),
                      SizedBox(height: 12),
                      Text(
                        'NINGUNA ALERTA CRÍTICA ACTIVA',
                        style: TextStyle(
                          color: Color(0xFF00FFAA),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          letterSpacing: 1,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Los sensores operan dentro de parámetros normales.',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _alerts.length,
                  itemBuilder: (context, index) {
                    final alert = _alerts[index];
                    final title = alert['title'] ?? alert['name'] ?? 'Alerta de Seguridad';
                    final level = alert['level'] ?? alert['severity'] ?? 'ATENCIÓN';
                    final desc = alert['summary'] ?? alert['description'] ?? '';
                    final time = alert['timestamp'] ?? alert['published'] ?? '';
                    final color = _getAlertColor(level.toString());

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      color: const Color(0xFF141824),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: color.withOpacity(0.4), width: 1),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border(left: BorderSide(color: color, width: 4)),
                        ),
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: color.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: color.withOpacity(0.4)),
                                  ),
                                  child: Text(
                                    level.toString().toUpperCase(),
                                    style: TextStyle(
                                      color: color,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                                Row(
                                  children: [
                                    IconButton(
                                      constraints: const BoxConstraints(),
                                      padding: const EdgeInsets.all(4),
                                      icon: const Icon(Icons.volume_up, color: Color(0xFF00E5FF), size: 18),
                                      onPressed: () {
                                        VoiceService.speakAlert(
                                          title: title,
                                          body: desc,
                                          level: level.toString(),
                                        );
                                      },
                                      tooltip: 'Escuchar alerta por voz',
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      time,
                                      style: const TextStyle(color: Colors.white38, fontSize: 10),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (desc.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                desc,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
