import 'package:flutter/material.dart';

/// Hoja inferior con los detalles de un marcador del Mapa Táctico.
class MapMarkerDetailsSheet extends StatelessWidget {
  final Map<String, dynamic> item;

  const MapMarkerDetailsSheet({super.key, required this.item});

  static Future<void> show(BuildContext context, Map<String, dynamic> item) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141824),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => MapMarkerDetailsSheet(item: item),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = item['title'] ?? 'Detalles del Evento';
    final desc = item['desc'] ?? '';
    final lat = item['lat'];
    final lon = item['lon'];
    final colorHex = item['color'] ?? '#00E5FF';

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Color(int.parse(colorHex.replaceAll('#', '0xFF'))),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
          if (item['type'] == 'CCTV') ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF2D55).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFFFF2D55), width: 0.8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.fiber_manual_record, color: Color(0xFFFF2D55), size: 8),
                      SizedBox(width: 4),
                      Text(
                        'LIVE STREAM OSIRIS',
                        style: TextStyle(color: Color(0xFFFF2D55), fontSize: 9, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                if (item['source'] != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD60A).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFFFFD60A), width: 0.8),
                    ),
                    child: Text(
                      'FUENTE: ${item['source']}',
                      style: const TextStyle(color: Color(0xFFFFD60A), fontSize: 9, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: 10),
          Text(
            desc,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          if (item['feed_url'] != null && item['feed_url'].toString().isNotEmpty) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                  Image.network(
                    item['feed_url'],
                    height: 170,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        height: 150,
                        color: Colors.black45,
                        child: const Center(
                          child: CircularProgressIndicator(color: Color(0xFFFFD60A), strokeWidth: 2),
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        height: 130,
                        width: double.infinity,
                        color: const Color(0xFF10131D),
                        padding: const EdgeInsets.all(12),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.videocam_off_outlined, color: Color(0xFFFF2D55), size: 28),
                            SizedBox(height: 6),
                            Text(
                              'TRANSMISIÓN NO DISPONIBLE EN ESTE MOMENTO',
                              style: TextStyle(color: Color(0xFFFF2D55), fontSize: 10, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Text(
                        'C4I CAM ENGINE',
                        style: TextStyle(color: Color(0xFF00E5FF), fontSize: 8, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black45,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white10),
            ),
            child: Text(
              'COORDENADAS: ${lat.toString()} , ${lon.toString()}',
              style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 10, fontFamily: 'monospace'),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: item['type'] == 'CCTV' ? const Color(0xFFFFD60A) : const Color(0xFF00E5FF),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('ENTENDIDO', style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}