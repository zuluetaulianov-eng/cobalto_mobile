import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ReconTab extends StatefulWidget {
  const ReconTab({super.key});

  @override
  State<ReconTab> createState() => _ReconTabState();
}

class _ReconTabState extends State<ReconTab> {
  final TextEditingController _targetController = TextEditingController(text: '8.8.8.8');
  String _selectedTool = 'IP_GEOLOC';
  bool _isExecuting = false;
  Map<String, dynamic>? _resultData;
  String? _errorMessage;

  final Map<String, String> _tools = {
    'IP_GEOLOC': '🌐 Geolocalización de IP (País, ISP, Coordenadas)',
    'DNS_LOOKUP': '🔍 Consulta DNS (Registros A, MX, NS, TXT)',
    'WHOIS_RDAP': '📋 Consulta WHOIS / RDAP de Dominio o IP',
    'CVE_SEARCH': '🛡️ Búsqueda de Vulnerabilidades CVE (NIST NVD)',
  };

  Future<void> _runReconTool() async {
    final target = _targetController.text.trim();
    if (target.isEmpty) return;

    setState(() {
      _isExecuting = true;
      _resultData = null;
      _errorMessage = null;
    });

    try {
      if (_selectedTool == 'IP_GEOLOC') {
        final res = await http.get(Uri.parse('http://ip-api.com/json/$target')).timeout(const Duration(seconds: 7));
        if (res.statusCode == 200) {
          _resultData = json.decode(res.body);
        } else {
          _errorMessage = 'Error en respuesta HTTP: ${res.statusCode}';
        }
      } else if (_selectedTool == 'DNS_LOOKUP') {
        final res = await http.get(Uri.parse('https://dns.google/resolve?name=$target&type=A')).timeout(const Duration(seconds: 7));
        if (res.statusCode == 200) {
          _resultData = json.decode(res.body);
        } else {
          _errorMessage = 'Fallo en la resolución DNS.';
        }
      } else if (_selectedTool == 'WHOIS_RDAP') {
        final res = await http.get(Uri.parse('https://rdap.org/ip/$target')).timeout(const Duration(seconds: 7));
        if (res.statusCode == 200) {
          _resultData = json.decode(res.body);
        } else {
          _errorMessage = 'No se encontraron datos RDAP/WHOIS para $target.';
        }
      } else if (_selectedTool == 'CVE_SEARCH') {
        final res = await http.get(Uri.parse('https://services.nvd.nist.gov/rest/json/cves/2.0?keywordSearch=$target')).timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          _resultData = json.decode(res.body);
        } else {
          _errorMessage = 'Fallo al consultar la base de datos NVD CVE.';
        }
      }
    } catch (e) {
      _errorMessage = 'Excepción al ejecutar la herramienta: $e';
    } finally {
      if (mounted) {
        setState(() => _isExecuting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0B10),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🛠️ HERRAMIENTAS DE RECONOCIMIENTO OSINT (RECON)',
              style: TextStyle(
                color: Color(0xFF00E5FF),
                fontSize: 12,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 10),

            // Selector de Herramientas
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF141824),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.3)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedTool,
                  dropdownColor: const Color(0xFF141824),
                  isExpanded: true,
                  items: _tools.entries.map((e) {
                    return DropdownMenuItem<String>(
                      value: e.key,
                      child: Text(
                        e.value,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedTool = val);
                  },
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Campo de Entrada (IP, Dominio o CVE)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _targetController,
                    style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Ingrese IP, Dominio o palabra...',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF141824),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF00E5FF)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isExecuting ? null : _runReconTool,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E5FF),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: _isExecuting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : const Text(
                          'EJECUTAR',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, fontFamily: 'monospace'),
                        ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            const Text(
              'RESULTADOS DE INTELIGENCIA:',
              style: TextStyle(color: Colors.white54, fontSize: 10, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 6),

            // Panel de Resultados
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF141824),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white10),
                ),
                child: _errorMessage != null
                    ? Text(
                        '⚠️ $_errorMessage',
                        style: const TextStyle(color: Color(0xFFFF2D55), fontSize: 12),
                      )
                    : _resultData == null
                        ? const Center(
                            child: Text(
                              'Seleccione una herramienta e ingrese un objetivo para comenzar el reconocimiento.',
                              style: TextStyle(color: Colors.white38, fontSize: 12),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : SingleChildScrollView(
                            child: SelectableText(
                              const JsonEncoder.withIndent('  ').convert(_resultData),
                              style: const TextStyle(
                                color: Color(0xFF00FFAA),
                                fontSize: 11,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
