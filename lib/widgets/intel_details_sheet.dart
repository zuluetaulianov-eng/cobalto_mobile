import 'package:flutter/material.dart';

import '../utils/text_sanitizer.dart';
import 'video_player_sheet.dart';

/// Hoja inferior con el detalle completo de una entrada SitRep.
/// Recibe la entrada, un abridor de enlaces externos y el disparador de la
/// hoja de difusión.
class IntelDetailsSheet extends StatelessWidget {
  final Map<String, dynamic> item;
  final Future<void> Function(String? url) onOpenLink;
  final void Function(BuildContext context, Map<String, dynamic> item) onShare;

  const IntelDetailsSheet({
    super.key,
    required this.item,
    required this.onOpenLink,
    required this.onShare,
  });

  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> item,
    required Future<void> Function(String? url) onOpenLink,
    required void Function(BuildContext context, Map<String, dynamic> item) onShare,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0A0B10),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => IntelDetailsSheet(
        item: item,
        onOpenLink: onOpenLink,
        onShare: onShare,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = TextSanitizer.clean(item['title']?.toString() ?? 'Sin título');
    final source = item['source'] ?? 'Intel Hub';
    final summary = TextSanitizer.clean((item['summary'] ?? item['text'] ?? 'Sin contenido detallado registrado.').toString());
    final published = item['published'] ?? item['timestamp'] ?? '';
    final link = item['link'];
    final imageUrl = item['image'] ?? item['img'] ?? item['media_url'];
    final videoUrl = item['video'] ?? item['video_url'];
    final hasVideo = videoUrl != null && videoUrl.toString().trim().isNotEmpty;
    final matchedKw = item['keywords_matched'] is List ? List<String>.from(item['keywords_matched']) : [];

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (context, scrollController) {
        return SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white30,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              if (hasVideo) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF2D55).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFF2D55).withOpacity(0.4)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: const BoxDecoration(
                          color: Color(0xFFFF2D55),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'CONTENIDO EN VIDEO DISPONIBLE',
                              style: TextStyle(
                                color: Color(0xFFFF2D55),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              videoUrl.toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white38, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF2D55),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        onPressed: () {
                          VideoPlayerSheet.show(
                            context,
                            videoUrl: videoUrl.toString(),
                            title: title,
                          );
                        },
                        child: const Text(
                          'VER AHORA',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (imageUrl != null && imageUrl.toString().startsWith('http')) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    imageUrl.toString(),
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E5FF).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF00E5FF)),
                    ),
                    child: Text(
                      source.toString().toUpperCase(),
                      style: const TextStyle(
                        color: Color(0xFF00E5FF),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  Text(
                    published,
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  height: 1.3,
                ),
              ),
              if (matchedKw.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: matchedKw.map((kw) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.amber.withOpacity(0.4)),
                      ),
                      child: Text(
                        '#$kw',
                        style: const TextStyle(color: Colors.amber, fontSize: 10, fontFamily: 'monospace'),
                      ),
                    );
                  }).toList(),
                ),
              ],
              const Divider(color: Colors.white10, height: 28),
              Text(
                summary,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.87),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E5FF),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('ABRIR FUENTE WEB', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      onPressed: () => onOpenLink(link),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filledTonal(
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF141824),
                      foregroundColor: const Color(0xFF00E5FF),
                      side: const BorderSide(color: Color(0xFF00E5FF), width: 0.5),
                    ),
                    icon: const Icon(Icons.share),
                    onPressed: () => onShare(context, item),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}