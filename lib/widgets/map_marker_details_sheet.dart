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
          const SizedBox(height: 10),
          Text(
            desc,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
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
                    backgroundColor: const Color(0xFF00E5FF),
                    foregroundColor: Colors.black,
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