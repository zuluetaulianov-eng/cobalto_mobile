import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'intel_card_generator_dialog.dart';

/// Hoja inferior para difundir un reporte OSINT (ficha PNG, copiar enlace,
/// Telegram y WhatsApp).
class IntelShareSheet extends StatelessWidget {
  final Map<String, dynamic> item;
  final Future<void> Function(String url) onOpenLink;

  const IntelShareSheet({super.key, required this.item, required this.onOpenLink});

  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> item,
    required Future<void> Function(String url) onOpenLink,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141824),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => IntelShareSheet(item: item, onOpenLink: onOpenLink),
    );
  }

  void _copyToClipboard(BuildContext context, String title, String? link) {
    final textToCopy = link != null && link.isNotEmpty ? '$title\nFuente: $link' : title;
    Clipboard.setData(ClipboardData(text: textToCopy));
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('📋 Reporte OSINT copiado al portapapeles.'),
        backgroundColor: Color(0xFF00E5FF),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = item['title'] ?? 'Reporte COBALTO OSINT';
    final link = item['link']?.toString() ?? '';
    final source = item['source'] ?? 'Intel Hub';

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.share, color: Color(0xFF00E5FF), size: 22),
              SizedBox(width: 10),
              Text(
                'DIFUNDIR REPORTE OSINT',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF00E5FF).withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.4)),
            ),
            child: ListTile(
              leading: const Icon(Icons.image_outlined, color: Color(0xFF00E5FF), size: 28),
              title: const Text(
                'GENERAR FICHA GRÁFICA HD (PNG)',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'monospace'),
              ),
              subtitle: const Text('Exporta infografía personalizada con QR y notas', style: TextStyle(color: Colors.white70, fontSize: 11)),
              onTap: () {
                Navigator.pop(context);
                IntelCardGeneratorDialog.show(context, item);
              },
            ),
          ),
          const SizedBox(height: 10),
          ListTile(
            leading: const Icon(Icons.copy, color: Color(0xFF00E5FF)),
            title: const Text('Copiar Texto y Enlace', style: TextStyle(color: Colors.white)),
            onTap: () => _copyToClipboard(context, title, link),
          ),
          ListTile(
            leading: const Icon(Icons.send, color: Color(0xFF00FFAA)),
            title: const Text('Compartir por Telegram', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              final tgUrl = 'https://t.me/share/url?url=${Uri.encodeComponent(link)}&text=${Uri.encodeComponent('[$source] $title')}';
              onOpenLink(tgUrl);
            },
          ),
          ListTile(
            leading: const Icon(Icons.chat_bubble_outline, color: Color(0xFF25D366)),
            title: const Text('Compartir por WhatsApp', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              final waUrl = 'https://wa.me/?text=${Uri.encodeComponent('[$source] $title\n$link')}';
              onOpenLink(waUrl);
            },
          ),
        ],
      ),
    );
  }
}