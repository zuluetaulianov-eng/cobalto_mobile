import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/intel_card_export_service.dart';

/// Diálogo de confirmación tras exportar la ficha PNG, con acciones de
/// re-compartir, copiar enlace y envío directo a Telegram / WhatsApp.
class IntelExportSuccessDialog extends StatelessWidget {
  final String displayPath;
  final String link;
  final String title;
  final String tempFilePath;

  const IntelExportSuccessDialog({
    super.key,
    required this.displayPath,
    required this.link,
    required this.title,
    required this.tempFilePath,
  });

  static Future<void> show(
    BuildContext context, {
    required String displayPath,
    required String link,
    required String title,
    required String tempFilePath,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => IntelExportSuccessDialog(
        displayPath: displayPath,
        link: link,
        title: title,
        tempFilePath: tempFilePath,
      ),
    );
  }

  void _share(BuildContext context) {
    Navigator.pop(context);
    IntelCardExportService.sharePngFile(tempFilePath, title, link);
  }

  void _copyLink(BuildContext context) {
    Navigator.pop(context);
    final copyText = link.isNotEmpty ? '$title\nFuente: $link' : title;
    Clipboard.setData(ClipboardData(text: copyText));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('📋 Título y Enlace copiados al portapapeles.'),
        backgroundColor: Color(0xFF00E5FF),
      ),
    );
  }

  Future<void> _openExternal(BuildContext context, Uri uri) async {
    Navigator.pop(context);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF141824),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFF00E5FF), width: 0.5),
      ),
      title: const Row(
        children: [
          Icon(Icons.check_circle, color: Color(0xFF00FFAA), size: 22),
          SizedBox(width: 8),
          Text(
            'FICHA PNG EXPORTADA',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
            ),
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
                  const Text(
                    '📁 RUTA PÚBLICA EN TU ANDROID:',
                    style: TextStyle(color: Colors.white54, fontSize: 9, fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 3),
                  SelectableText(
                    displayPath,
                    style: const TextStyle(
                      color: Color(0xFF00E5FF),
                      fontSize: 11,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (link.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    const Text(
                      '🔗 ENLACE ADJUNTO:',
                      style: TextStyle(color: Colors.white54, fontSize: 9, fontFamily: 'monospace'),
                    ),
                    SelectableText(
                      link,
                      style: const TextStyle(color: Colors.amber, fontSize: 10, fontFamily: 'monospace'),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
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
                onPressed: () => _share(context),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CERRAR', style: TextStyle(color: Colors.white54, fontFamily: 'monospace')),
        ),
        IconButton(
          icon: const Icon(Icons.send, color: Color(0xFF00FFAA)),
          tooltip: 'Compartir Enlace en Telegram',
          onPressed: () => _openExternal(context, IntelCardExportService.telegramShareUri(link, title)),
        ),
        IconButton(
          icon: const Icon(Icons.chat_bubble_outline, color: Color(0xFF25D366)),
          tooltip: 'Compartir Enlace en WhatsApp',
          onPressed: () => _openExternal(context, IntelCardExportService.whatsappShareUri(link, title)),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF141824),
            foregroundColor: const Color(0xFF00E5FF),
            side: const BorderSide(color: Color(0xFF00E5FF), width: 0.5),
          ),
          icon: const Icon(Icons.copy, size: 14),
          label: const Text('COPIAR LINK', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
          onPressed: () => _copyLink(context),
        ),
      ],
    );
  }
}
