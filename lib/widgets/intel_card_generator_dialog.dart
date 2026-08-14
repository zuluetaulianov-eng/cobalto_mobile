import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

enum IntelCardTheme {
  cyberDark,
  defconRed,
  tacticalGold,
  militaryGreen,
}

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

  Color get _primaryColor {
    switch (_selectedTheme) {
      case IntelCardTheme.cyberDark:
        return const Color(0xFF00E5FF);
      case IntelCardTheme.defconRed:
        return const Color(0xFFFF2D55);
      case IntelCardTheme.tacticalGold:
        return const Color(0xFFFFD60A);
      case IntelCardTheme.militaryGreen:
        return const Color(0xFF00FFAA);
    }
  }

  Color get _backgroundColor {
    switch (_selectedTheme) {
      case IntelCardTheme.cyberDark:
        return const Color(0xFF0A0B10);
      case IntelCardTheme.defconRed:
        return const Color(0xFF140508);
      case IntelCardTheme.tacticalGold:
        return const Color(0xFF12141A);
      case IntelCardTheme.militaryGreen:
        return const Color(0xFF08120B);
    }
  }

  Future<String?> _saveToPublicDirectory(Uint8List bytes, String filename) async {
    try {
      Directory? targetDir;
      if (Platform.isAndroid) {
        final downloadsDir = Directory('/storage/emulated/0/Download');
        if (await downloadsDir.exists()) {
          targetDir = downloadsDir;
        } else {
          final picturesDir = Directory('/storage/emulated/0/Pictures');
          if (await picturesDir.exists()) {
            targetDir = picturesDir;
          } else {
            targetDir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
          }
        }
      } else {
        targetDir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      }

      final String savePath = '${targetDir.path}/$filename';
      final File savedFile = File(savePath);
      await savedFile.writeAsBytes(bytes);
      return savePath;
    } catch (e) {
      debugPrint("Error al guardar en carpeta pública: $e");
      return null;
    }
  }

  Future<void> _sharePngFile(String filePath, String title, String link) async {
    final caption = link.isNotEmpty
        ? '🚨 [COBALTO OSINT] - $title\n\n🔗 Fuente original:\n$link'
        : '🚨 [COBALTO OSINT] - $title';

    await Share.shareXFiles(
      [XFile(filePath, mimeType: 'image/png', name: 'cobalto_intel_report.png')],
      text: caption,
      subject: title,
    );
  }

  Future<void> _exportAndShareImage() async {
    setState(() => _isGenerating = true);
    final title = widget.newsItem['title'] ?? 'Reporte COBALTO OSINT';
    final link = widget.newsItem['link']?.toString() ?? '';

    try {
      // Esperar un momento para asegurar renderizado completo del canvas
      await Future.delayed(const Duration(milliseconds: 300));

      RenderRepaintBoundary? boundary = _repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception("No se pudo obtener el canvas de la imagen.");
      }

      // Renderizar imagen PNG HD (pixelRatio 3.0 para alta nitidez)
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception("Error convirtiendo imagen a PNG.");

      final Uint8List pngBytes = byteData.buffer.asUint8List();
      final String timestampName = 'cobalto_intel_${DateTime.now().millisecondsSinceEpoch}.png';

      // 1. Guardar en directorio de la app para compartir directo por intent
      final tempDir = await getTemporaryDirectory();
      final String tempFilePath = '${tempDir.path}/$timestampName';
      final File tempFile = File(tempFilePath);
      await tempFile.writeAsBytes(pngBytes);

      // 2. Guardar en almacenamiento público de Descargas / Fotos (accesible para el usuario en Android)
      final String? publicFilePath = await _saveToPublicDirectory(pngBytes, timestampName);
      final String displayPath = publicFilePath ?? tempFilePath;

      if (!mounted) return;

      setState(() => _isGenerating = false);

      // 3. Abrir de inmediato el menú nativo de Android de compartir la imagen PNG a Redes Sociales
      _sharePngFile(tempFilePath, title, link);

      // 4. Mostrar diálogo informativo con opciones adicionales
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF141824),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFF00E5FF), width: 0.5),
          ),
          title: Row(
            children: const [
              Icon(Icons.check_circle, color: Color(0xFF00FFAA), size: 22),
              SizedBox(width: 8),
              Text(
                'FICHA PNG EXPORTADA',
                style: TextStyle(color: Colors.white, fontSize: 14, fontFamily: 'monospace', fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '✅ La imagen PNG HD ha sido guardada en la carpeta pública de Descargas de tu teléfono y está lista para enviarse a redes sociales.',
                  style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('📁 RUTA PÚBLICA EN TU ANDROID:', style: TextStyle(color: Colors.white54, fontSize: 9, fontFamily: 'monospace')),
                      const SizedBox(height: 3),
                      SelectableText(
                        displayPath,
                        style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.w600),
                      ),
                      if (link.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        const Text('🔗 ENLACE ADJUNTO:', style: TextStyle(color: Colors.white54, fontSize: 9, fontFamily: 'monospace')),
                        SelectableText(
                          link,
                          style: const TextStyle(color: Colors.amber, fontSize: 10, fontFamily: 'monospace'),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                // Botón principal destacado para re-compartir la IMAGEN PNG
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E5FF),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.share, size: 18),
                    label: const Text(
                      'ENVIAR IMAGEN PNG A RED SOCIAL',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _sharePngFile(tempFilePath, title, link);
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('CERRAR', style: TextStyle(color: Colors.white54, fontFamily: 'monospace')),
            ),
            IconButton(
              icon: const Icon(Icons.send, color: Color(0xFF00FFAA)),
              tooltip: 'Compartir Enlace en Telegram',
              onPressed: () async {
                Navigator.pop(ctx);
                final caption = '🚨 [COBALTO OSINT] - $title\n\n🔗 Fuente original:\n$link';
                final tgUrl = 'https://t.me/share/url?url=${Uri.encodeComponent(link)}&text=${Uri.encodeComponent(caption)}';
                final Uri uri = Uri.parse(tgUrl);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.chat_bubble_outline, color: Color(0xFF25D366)),
              tooltip: 'Compartir Enlace en WhatsApp',
              onPressed: () async {
                Navigator.pop(ctx);
                final caption = '🚨 [COBALTO OSINT] - $title\n\n🔗 Fuente original:\n$link';
                final waUrl = 'https://wa.me/?text=${Uri.encodeComponent(caption)}';
                final Uri uri = Uri.parse(waUrl);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF141824),
                foregroundColor: const Color(0xFF00E5FF),
                side: const BorderSide(color: Color(0xFF00E5FF), width: 0.5),
              ),
              icon: const Icon(Icons.copy, size: 14),
              label: const Text('COPIAR LINK', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
              onPressed: () {
                Navigator.pop(ctx);
                final copyText = link.isNotEmpty ? '$title\nFuente: $link' : title;
                Clipboard.setData(ClipboardData(text: copyText));
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('📋 Título y Enlace copiados al portapapeles.'),
                      backgroundColor: Color(0xFF00E5FF),
                    ),
                  );
                }
              },
            ),
          ],
        ),
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
    final title = widget.newsItem['title'] ?? 'Sin título';
    final source = widget.newsItem['source'] ?? 'Intel Hub';
    final summary = widget.newsItem['summary'] ?? widget.newsItem['text'] ?? '';
    final published = widget.newsItem['published'] ?? widget.newsItem['timestamp'] ?? DateTime.now().toIso8601String().substring(0, 16);
    final link = widget.newsItem['link']?.toString() ?? '';
    final imageUrl = widget.newsItem['image'] ?? widget.newsItem['img'] ?? widget.newsItem['media_url'];

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
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _backgroundColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _primaryColor, width: 1.5),
                        boxShadow: [
                          BoxShadow(color: _primaryColor.withOpacity(0.15), blurRadius: 10),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Encabezado Táctico
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: _primaryColor,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Icon(Icons.shield, color: Colors.black, size: 14),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'COBALTO OSINT',
                                    style: TextStyle(
                                      color: _primaryColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      fontFamily: 'monospace',
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _primaryColor.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: _primaryColor.withOpacity(0.5)),
                                ),
                                child: Text(
                                  _classification,
                                  style: TextStyle(
                                    color: _primaryColor,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Imagen destacada (si existe)
                          if (imageUrl != null && imageUrl.toString().startsWith('http')) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                imageUrl.toString(),
                                height: 130,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],

                          // Metadatos
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white10,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'FUENTE: ${source.toString().toUpperCase()}',
                                  style: const TextStyle(color: Colors.white70, fontSize: 9, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                                ),
                              ),
                              Text(
                                published,
                                style: const TextStyle(color: Colors.white38, fontSize: 9, fontFamily: 'monospace'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // Título Principal
                          Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              height: 1.3,
                            ),
                          ),
                          if (summary.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              summary,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                height: 1.4,
                              ),
                            ),
                          ],

                          // Nota del Analista (si aplica)
                          if (_includeAnalystNote && _notesController.text.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: _primaryColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                                border: Border(left: BorderSide(color: _primaryColor, width: 3)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'APRECIACIÓN DEL ANALISTA:',
                                    style: TextStyle(color: _primaryColor, fontSize: 9, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _notesController.text,
                                    style: const TextStyle(color: Colors.white, fontSize: 11, fontStyle: FontStyle.italic),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: 12),
                          Divider(color: _primaryColor.withOpacity(0.3), height: 1),
                          const SizedBox(height: 8),

                          // Pie de Ficha & Verificación
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (link.isNotEmpty)
                                      Text(
                                        'VERIFICACIÓN: ${link.length > 35 ? "${link.substring(0, 35)}..." : link}',
                                        style: const TextStyle(color: Colors.white38, fontSize: 8, fontFamily: 'monospace'),
                                      ),
                                    if (_includeWatermark)
                                      Text(
                                        'COBALTO VERIFIED INTEL // AUTONOMOUS OSINT SYSTEM',
                                        style: TextStyle(color: _primaryColor.withOpacity(0.7), fontSize: 8, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                                      ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.qr_code_2, color: Colors.white54, size: 28),
                            ],
                          ),
                        ],
                      ),
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
