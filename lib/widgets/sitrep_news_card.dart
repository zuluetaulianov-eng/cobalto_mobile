import 'package:flutter/material.dart';

/// Tarjeta de una entrada SitRep en el feed. Widget puro: recibe la entrada y
/// callbacks de acción, sin conocer detalles del estado de la pestaña.
class SitrepNewsCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onRead;
  final VoidCallback onOpenWeb;
  final VoidCallback onShare;

  const SitrepNewsCard({
    super.key,
    required this.item,
    required this.onRead,
    required this.onOpenWeb,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final title = item['title'] ?? 'Sin título';
    final source = item['source'] ?? 'Intel Hub';
    final summary = item['summary'] ?? item['text'] ?? '';
    final published = item['published'] ?? item['timestamp'] ?? '';
    final imageUrl = item['image'] ?? item['img'] ?? item['media_url'];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: const Color(0xFF141824),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Colors.white10),
      ),
      child: InkWell(
        onTap: onRead,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (imageUrl != null && imageUrl.toString().startsWith('http'))
              Container(
                height: 140,
                width: double.infinity,
                color: Colors.black26,
                child: Image.network(
                  imageUrl.toString(),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E5FF).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.3)),
                        ),
                        child: Text(
                          source.toString().toUpperCase(),
                          style: const TextStyle(
                            color: Color(0xFF00E5FF),
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      Text(
                        published,
                        style: const TextStyle(color: Colors.white38, fontSize: 10),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (summary.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      summary,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
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
            const Divider(height: 1, color: Colors.white10),
            // Barra Táctica de Acciones en el Pie de la Tarjeta
            Container(
              color: const Color(0xFF0F121C),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF00E5FF),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(Icons.article_outlined, size: 16),
                    label: const Text(
                      'LEER',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                    ),
                    onPressed: onRead,
                  ),
                  Row(
                    children: [
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white70,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        icon: const Icon(Icons.open_in_new, size: 15),
                        label: const Text(
                          'ABRIR WEB',
                          style: TextStyle(fontSize: 10, fontFamily: 'monospace'),
                        ),
                        onPressed: onOpenWeb,
                      ),
                      IconButton(
                        icon: const Icon(Icons.share_outlined, size: 18, color: Color(0xFF00FFAA)),
                        tooltip: 'Difundir Noticia',
                        onPressed: onShare,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
