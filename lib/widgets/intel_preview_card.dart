import 'package:flutter/material.dart';

/// Temas visuales para la ficha de inteligencia.
enum IntelCardTheme {
  cyberDark,
  defconRed,
  tacticalGold,
  militaryGreen,
}

/// Paleta de colores derivada del tema seleccionado.
class IntelCardPalette {
  final Color primary;
  final Color background;

  const IntelCardPalette({required this.primary, required this.background});

  static IntelCardPalette forTheme(IntelCardTheme theme) {
    switch (theme) {
      case IntelCardTheme.cyberDark:
        return const IntelCardPalette(
          primary: Color(0xFF00E5FF),
          background: Color(0xFF0A0B10),
        );
      case IntelCardTheme.defconRed:
        return const IntelCardPalette(
          primary: Color(0xFFFF2D55),
          background: Color(0xFF140508),
        );
      case IntelCardTheme.tacticalGold:
        return const IntelCardPalette(
          primary: Color(0xFFFFD60A),
          background: Color(0xFF12141A),
        );
      case IntelCardTheme.militaryGreen:
        return const IntelCardPalette(
          primary: Color(0xFF00FFAA),
          background: Color(0xFF08120B),
        );
    }
  }
}

/// Contenido de la ficha infográfica de inteligencia (renderizada en PNG HD).
/// Es un widget puro: recibe los datos y las opciones de renderizado.
class IntelPreviewCard extends StatelessWidget {
  final Map<String, dynamic> newsItem;
  final IntelCardTheme theme;
  final String classification;
  final bool includeAnalystNote;
  final bool includeWatermark;
  final String analystNote;

  const IntelPreviewCard({
    super.key,
    required this.newsItem,
    required this.theme,
    required this.classification,
    required this.includeAnalystNote,
    required this.includeWatermark,
    this.analystNote = '',
  });

  @override
  Widget build(BuildContext context) {
    final palette = IntelCardPalette.forTheme(theme);
    final title = newsItem['title'] ?? 'Sin título';
    final source = newsItem['source'] ?? 'Intel Hub';
    final summary = newsItem['summary'] ?? newsItem['text'] ?? '';
    final published = newsItem['published'] ??
        newsItem['timestamp'] ??
        DateTime.now().toIso8601String().substring(0, 16);
    final link = newsItem['link']?.toString() ?? '';
    final imageUrl =
        newsItem['image'] ?? newsItem['img'] ?? newsItem['media_url'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.primary, width: 1.5),
        boxShadow: [
          BoxShadow(color: palette.primary.withOpacity(0.15), blurRadius: 10),
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
                      color: palette.primary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(Icons.shield, color: Colors.black, size: 14),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'COBALTO OSINT',
                    style: TextStyle(
                      color: palette.primary,
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
                  color: palette.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: palette.primary.withOpacity(0.5)),
                ),
                child: Text(
                  classification,
                  style: TextStyle(
                    color: palette.primary,
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
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 9,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                  ),
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
              style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.4),
            ),
          ],

          // Nota del Analista (si aplica)
          if (includeAnalystNote && analystNote.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: palette.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border(left: BorderSide(color: palette.primary, width: 3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'APRECIACIÓN DEL ANALISTA:',
                    style: TextStyle(
                      color: palette.primary,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    analystNote,
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),
          Divider(color: palette.primary.withOpacity(0.3), height: 1),
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
                    if (includeWatermark)
                      Text(
                        'COBALTO VERIFIED INTEL // AUTONOMOUS OSINT SYSTEM',
                        style: TextStyle(
                          color: palette.primary.withOpacity(0.7),
                          fontSize: 8,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.qr_code_2, color: Colors.white54, size: 28),
            ],
          ),
        ],
      ),
    );
  }
}
