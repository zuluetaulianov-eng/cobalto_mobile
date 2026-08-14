import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/intel_card_export_service.dart';
import 'intel_export_success_dialog.dart';
import 'intel_preview_card.dart';

class IntelCardGeneratorDialog extends StatefulWidget {
  final Map<String, dynamic> newsItem;

  const IntelCardGeneratorDialog({super.key, required this.newsItem});

  static Future<void> show(BuildContext context, Map<String, dynamic> newsItem) async {
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => IntelCardGeneratorDialog(newsItem: newsItem),
    );
  }

  @override
  State<IntelCardGeneratorDialog> createState() => _IntelCardGeneratorDialogState();
}

class _IntelCardGeneratorDialogState extends State<IntelCardGeneratorDialog> {
  final GlobalKey _repaintKey = GlobalKey();
  IntelCardTheme _selectedTheme = IntelCardTheme.cyberDark;
  String _classification = 'OSINT FLASH REPORT';
  final TextEditingController _notesController = TextEditingController();
  bool _includeWatermark = true;
  bool _includeAnalystNote = false;
  bool _isGenerating = false;

  final List<String> _classifications = [
    'OSINT FLASH REPORT',
    'UNCLASSIFIED // FOUO',
    'ALERTA DE SEGURIDAD',
    'CONFIRMADO OSINT',
    'INFORMACIÓN EN DESARROLLO',
  ];

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Color get _primaryColor => IntelCardPalette.forTheme(_selectedTheme).primary;

  Future<void> _exportAndShareImage() async {
    setState(() => _isGenerating = true);
    final title = widget.newsItem['title'] ?? 'Reporte COBALTO OSINT';
    final link = widget.newsItem['link']?.toString() ?? '';

    try {
      // Esperar un momento para asegurar renderizado completo del canvas
      await Future.delayed(const Duration(milliseconds: 300));

      final Uint8List? pngBytes = await IntelCardExportService.renderPng(_repaintKey);
      if (pngBytes == null) {
        throw Exception('No se pudo obtener el canvas de la imagen.');
      }

      final String timestampName = 'cobalto_intel_${DateTime.now().millisecondsSinceEpoch}.png';

      // 1. Guardar en directorio temporal de la app para compartir por intent
      final String tempFilePath = await IntelCardExportService.saveToTempDirectory(pngBytes, timestampName);

      // 2. Guardar en almacenamiento público de Descargas / Fotos
      final String? publicFilePath = await IntelCardExportService.saveToPublicDirectory(pngBytes, timestampName);
      final String displayPath = publicFilePath ?? tempFilePath;

      if (!mounted) return;

      setState(() => _isGenerating = false);

      // 3. Abrir el menú nativo de Android para compartir la imagen PNG
      IntelCardExportService.sharePngFile(tempFilePath, title, link);

      // 4. Mostrar diálogo informativo con opciones adicionales
      IntelExportSuccessDialog.show(
        context,
        displayPath: displayPath,
        link: link,
        title: title,
        tempFilePath: tempFilePath,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isGenerating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ Error al generar imagen: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0A0B10),
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: _primaryColor.withOpacity(0.5), width: 1),
      ),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 750),
        child: Column(
          children: [
            // Cabecera del Editor
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF141824),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                border: Border(bottom: BorderSide(color: _primaryColor.withOpacity(0.3))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.palette_outlined, color: _primaryColor, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'GENERADOR DE FICHA GRÁFICA HD',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Opciones de Configuración Táctica
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  // Selector de Estilo Visual / Tema
                  const Text('TEMA VISUAL:', style: TextStyle(color: Colors.white54, fontSize: 11, fontFamily: 'monospace')),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _buildThemeChip('Cyber Dark', IntelCardTheme.cyberDark, const Color(0xFF00E5FF)),
                      const SizedBox(width: 6),
                      _buildThemeChip('Defcon Red', IntelCardTheme.defconRed, const Color(0xFFFF2D55)),
                      const SizedBox(width: 6),
                      _buildThemeChip('Tactical Gold', IntelCardTheme.tacticalGold, const Color(0xFFFFD60A)),
                      const SizedBox(width: 6),
                      _buildThemeChip('Militar', IntelCardTheme.militaryGreen, const Color(0xFF00FFAA)),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Clasificación / Membrete
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('CLASIFICACIÓN:', style: TextStyle(color: Colors.white54, fontSize: 11, fontFamily: 'monospace')),
                            const SizedBox(height: 4),
                            DropdownButtonFormField<String>(
                              value: _classification,
                              dropdownColor: const Color(0xFF141824),
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: const Color(0xFF141824),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: const BorderSide(color: Colors.white24),
                                ),
                              ),
                              items: _classifications.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                              onChanged: (val) {
                                if (val != null) setState(() => _classification = val);
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Switches de Personalización
                  Row(
                    children: [
                      FilterChip(
                        selected: _includeAnalystNote,
                        label: const Text('Añadir Nota de Analista', style: TextStyle(fontSize: 11)),
                        selectedColor: _primaryColor.withOpacity(0.2),
                        checkmarkColor: _primaryColor,
                        labelStyle: TextStyle(color: _includeAnalystNote ? _primaryColor : Colors.white70),
                        onSelected: (val) => setState(() => _includeAnalystNote = val),
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        selected: _includeWatermark,
                        label: const Text('Marca de Agua OSINT', style: TextStyle(fontSize: 11)),
                        selectedColor: _primaryColor.withOpacity(0.2),
                        checkmarkColor: _primaryColor,
                        labelStyle: TextStyle(color: _includeWatermark ? _primaryColor : Colors.white70),
                        onSelected: (val) => setState(() => _includeWatermark = val),
                      ),
                    ],
                  ),

                  if (_includeAnalystNote) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _notesController,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: InputDecoration(
                        hintText: 'Escribir apreciación / nota del operador...',
                        hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                        filled: true,
                        fillColor: const Color(0xFF141824),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: _primaryColor.withOpacity(0.5)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: _primaryColor),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],

                  const SizedBox(height: 16),
                  const Text(
                    'PREVISUALIZACIÓN DE LA FICHA (PNG HD):',
                    style: TextStyle(color: Colors.white54, fontSize: 11, fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 8),

                  // CANVAS DE RENDERIZADO (RepaintBoundary)
                  RepaintBoundary(
                    key: _repaintKey,
                    child: IntelPreviewCard(
                      newsItem: widget.newsItem,
                      theme: _selectedTheme,
                      classification: _classification,
                      includeAnalystNote: _includeAnalystNote,
                      includeWatermark: _includeWatermark,
                      analystNote: _notesController.text,
                    ),
                  ),
                ],
              ),
            ),

            // Botón de Acción Principal
            Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                color: Color(0xFF141824),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(15)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryColor,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: _isGenerating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                            )
                          : const Icon(Icons.download, size: 18),
                      label: Text(
                        _isGenerating ? 'GENERANDO PNG HD...' : 'GENERAR Y GUARDAR FICHA PNG',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'monospace'),
                      ),
                      onPressed: _isGenerating ? null : _exportAndShareImage,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeChip(String label, IntelCardTheme theme, Color color) {
    final isSelected = _selectedTheme == theme;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedTheme = theme),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.2) : const Color(0xFF141824),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: isSelected ? color : Colors.white10),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? color : Colors.white60,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }
}
