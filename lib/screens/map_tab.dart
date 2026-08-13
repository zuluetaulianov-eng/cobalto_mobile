import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class MapTab extends StatefulWidget {
  const MapTab({super.key});

  @override
  State<MapTab> createState() => _MapTabState();
}

class _MapTabState extends State<MapTab> {
  late final WebViewController _controller;
  bool _isLoading = true;
  String _activeLayer = 'ALL';

  @override
  void initState() {
    super.initState();
    _initWebMap();
  }

  void _initWebMap() {
    const htmlContent = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <title>COBALTO Map</title>
  <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
  <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
  <style>
    html, body, #map {
      margin: 0; padding: 0; width: 100%; height: 100%;
      background-color: #0A0B10; font-family: monospace; color: #fff;
    }
    .leaflet-popup-content-wrapper {
      background: #141824; color: #fff; border: 1px solid #00E5FF;
      border-radius: 6px; font-family: monospace; font-size: 11px;
    }
    .leaflet-popup-tip { background: #141824; }
  </style>
</head>
<body>
  <div id="map"></div>
  <script>
    var map = L.map('map', { zoomControl: false }).setView([10.4806, -66.9036], 5);
    
    L.tileLayer('https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png', {
      maxZoom: 18,
      subdomains: 'abcd',
      attribution: 'CartoDB Dark Matter | COBALTO C4I'
    }).addTo(map);

    L.control.zoom({ position: 'bottomright' }).addTo(map);

    var markersGroup = L.layerGroup().addTo(map);

    var allPoints = [
      { lat: 10.4806, lon: -66.9036, title: '📌 Caracas (Centro Operativo C4I)', type: 'BASE', desc: 'Nodo Central de Inteligencia', color: '#00FFAA' },
      { lat: 6.8013, lon: -58.1551, title: '⚠️ Región Esequibo (Despliegue)', type: 'ALERT', desc: 'Monitoreo Satelital de Tropas', color: '#FF2D55' },
      { lat: 4.7110, lon: -74.0721, title: '📰 Bogotá (Nodo Andino)', type: 'NEWS', desc: 'Feed Transfronterizo OSINT', color: '#00E5FF' },
      { lat: 12.1165, lon: -68.9335, title: '🎥 Willemstad (CCTV Caribe)', type: 'CCTV', desc: 'Sensores Tráfico Marítimo', color: '#FFD60A' },
      { lat: 11.2000, lon: -64.5000, title: '🌋 Sensor Sísmico USGS (Mar Caribe)', type: 'QUAKE', desc: 'Mag 4.2 M - Prof. 10km', color: '#FF9500' }
    ];

    function filterPoints(type) {
      markersGroup.clearLayers();
      allPoints.forEach(function(p) {
        if (type === 'ALL' || p.type === type) {
          var marker = L.circleMarker([p.lat, p.lon], {
            radius: 8,
            fillColor: p.color,
            color: '#ffffff',
            weight: 2,
            opacity: 1,
            fillOpacity: 0.9
          });
          marker.bindPopup("<strong style='color:" + p.color + ";'>" + p.title + "</strong><br/><span style='color:#aaa;'>" + p.desc + "</span><br/><small style='color:#666;'>Coordenadas: " + p.lat + ", " + p.lon + "</small>");
          markersGroup.addLayer(marker);
        }
      });
    }

    filterPoints('ALL');
  </script>
</body>
</html>
''';

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0A0B10))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
        ),
      )
      ..loadHtmlString(htmlContent);
  }

  void _filterLayer(String layerId) {
    setState(() => _activeLayer = layerId);
    _controller.runJavaScript("filterPoints('$layerId');");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0B10),
      body: Stack(
        children: [
          // Mapa Leaflet Webview Interactivo
          WebViewWidget(controller: _controller),

          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(color: Color(0xFF00E5FF)),
            ),

          // Barra Superior Flotante de Filtros de Capas
          Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF10131D).withOpacity(0.9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.4)),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _layerChip('TODAS', 'ALL', Icons.map),
                    const SizedBox(width: 6),
                    _layerChip('📌 ALERTA', 'ALERT', Icons.warning_amber),
                    const SizedBox(width: 6),
                    _layerChip('📰 NOTICIAS', 'NEWS', Icons.newspaper),
                    const SizedBox(width: 6),
                    _layerChip('🌋 SISMOS', 'QUAKE', Icons.waves),
                    const SizedBox(width: 6),
                    _layerChip('🎥 CCTV', 'CCTV', Icons.videocam),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _layerChip(String label, String code, IconData icon) {
    final isSelected = _activeLayer == code;
    return GestureDetector(
      onTap: () => _filterLayer(code),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00E5FF) : const Color(0xFF141824),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isSelected ? const Color(0xFF00E5FF) : Colors.white10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 12, color: isSelected ? Colors.black : const Color(0xFF00E5FF)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.black : Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
