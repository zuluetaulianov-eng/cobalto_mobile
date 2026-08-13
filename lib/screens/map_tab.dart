import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/local_db_service.dart';
import '../services/cobalto_api_service.dart';

class MapTab extends StatefulWidget {
  const MapTab({super.key});

  @override
  State<MapTab> createState() => _MapTabState();
}

class _MapTabState extends State<MapTab> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _isRefreshing = false;
  String _activeLayer = 'ALL';
  Timer? _refreshTimer;

  // Mapeo Geográfico por Palabras Clave Tácticas
  static const Map<String, List<double>> _geoCityCoordinates = {
    'caracas': [10.4806, -66.9036],
    'zulia': [10.6427, -71.6125],
    'maracaibo': [10.6427, -71.6125],
    'esequibo': [6.8013, -58.1551],
    'guyana': [6.8013, -58.1551],
    'tachira': [7.7669, -72.2250],
    'san cristobal': [7.7669, -72.2250],
    'valencia': [10.1620, -68.0077],
    'carabobo': [10.1620, -68.0077],
    'barquisimeto': [10.0647, -69.3570],
    'lara': [10.0647, -69.3570],
    'bogota': [4.7110, -74.0721],
    'colombia': [4.7110, -74.0721],
    'curazao': [12.1165, -68.9335],
    'willemstad': [12.1165, -68.9335],
    'miami': [25.7617, -80.1918],
    'washington': [38.9072, -77.0369],
    'eeuu': [38.9072, -77.0369],
    'trinidad': [10.6918, -61.2225],
  };

  @override
  void initState() {
    super.initState();
    _initWebMap();
    // Refresco automático periódico cada 30 segundos
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _loadDynamicMarkersIntoMap();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
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
    var currentFilter = 'ALL';

    var allPoints = [
      { lat: 10.4806, lon: -66.9036, title: '📌 Caracas (Centro Operativo C4I)', type: 'BASE', desc: 'Nodo Central de Inteligencia', color: '#00FFAA' },
      { lat: 6.8013, lon: -58.1551, title: '⚠️ Región Esequibo (Despliegue)', type: 'ALERT', desc: 'Monitoreo Satelital de Tropas', color: '#FF2D55' },
      { lat: 4.7110, lon: -74.0721, title: '📰 Bogotá (Nodo Andino)', type: 'NEWS', desc: 'Feed Transfronterizo OSINT', color: '#00E5FF' },
      { lat: 12.1165, lon: -68.9335, title: '🎥 Willemstad (CCTV Caribe)', type: 'CCTV', desc: 'Sensores Tráfico Marítimo', color: '#FFD60A' },
      { lat: 11.2000, lon: -64.5000, title: '🌋 Sensor Sísmico USGS (Mar Caribe)', type: 'QUAKE', desc: 'Mag 4.2 M - Prof. 10km', color: '#FF9500' }
    ];

    function filterPoints(type) {
      currentFilter = type;
      markersGroup.clearLayers();
      allPoints.forEach(function(p) {
        if (type === 'ALL' || p.type === type) {
          var marker = L.circleMarker([p.lat, p.lon], {
            radius: 8,
            fillColor: p.color || '#00E5FF',
            color: '#ffffff',
            weight: 2,
            opacity: 1,
            fillOpacity: 0.9
          });
          var html = "<strong style='color:" + (p.color || '#00E5FF') + ";'>" + p.title + "</strong><br/>" +
                     "<span style='color:#ccc;'>" + p.desc + "</span><br/>" +
                     "<small style='color:#666;'>Coordenadas: " + p.lat.toFixed(4) + ", " + p.lon.toFixed(4) + "</small>";
          marker.bindPopup(html);
          markersGroup.addLayer(marker);
        }
      });
    }

    function updatePoints(newPoints) {
      if (Array.isArray(newPoints) && newPoints.length > 0) {
        allPoints = newPoints;
        filterPoints(currentFilter);
      }
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
          onPageFinished: (_) async {
            if (mounted) {
              setState(() => _isLoading = false);
              await _loadDynamicMarkersIntoMap();
            }
          },
        ),
      )
      ..loadHtmlString(htmlContent);
  }

  Future<void> _loadDynamicMarkersIntoMap() async {
    if (!mounted) return;
    setState(() => _isRefreshing = true);

    final List<Map<String, dynamic>> dynamicPoints = [];

    // 1. Añadir Nodo Central Fijo
    dynamicPoints.add({
      'lat': 10.4806,
      'lon': -66.9036,
      'title': '📌 Caracas (Centro Operativo C4I)',
      'type': 'BASE',
      'desc': 'Nodo Central de Inteligencia COBALTO',
      'color': '#00FFAA'
    });

    // 2. Cargar Noticias de Inteligencia (SQLite local o Servidor)
    List<Map<String, dynamic>> newsList = await LocalDbService.getEntries();
    if (newsList.isEmpty) {
      final remoteNews = await CobaltoApiService.fetchNews();
      if (remoteNews.isNotEmpty) {
        newsList = List<Map<String, dynamic>>.from(remoteNews);
      }
    }

    for (final news in newsList) {
      final title = news['title']?.toString() ?? '';
      final summary = news['summary']?.toString() ?? '';
      final textLower = '$title $summary'.toLowerCase();

      // Encontrar ciudad o región por palabras clave
      for (final entry in _geoCityCoordinates.entries) {
        if (textLower.contains(entry.key)) {
          final coords = entry.value;
          final double latShift = ((title.hashCode % 10) - 5) * 0.015;
          final double lonShift = (((title.hashCode ~/ 10) % 10) - 5) * 0.015;

          final bool isCritical = textLower.contains('alerta') || textLower.contains('conflicto') || textLower.contains('ciberataque');

          dynamicPoints.add({
            'lat': coords[0] + latShift,
            'lon': coords[1] + lonShift,
            'title': '📰 ${news['source'] ?? 'SITREP'}: ${title.length > 50 ? '${title.substring(0, 50)}...' : title}',
            'type': isCritical ? 'ALERT' : 'NEWS',
            'desc': summary.length > 90 ? '${summary.substring(0, 90)}...' : summary,
            'color': isCritical ? '#FF2D55' : '#00E5FF',
          });
          break;
        }
      }
    }

    // 3. Cargar Reportes HUMINT de Campo grabados por los operadores
    final fieldReports = await LocalDbService.getFieldReports();
    for (final rep in fieldReports) {
      final lat = rep['lat'] is num ? (rep['lat'] as num).toDouble() : 0.0;
      final lng = rep['lng'] is num ? (rep['lng'] as num).toDouble() : 0.0;

      if (lat != 0.0 && lng != 0.0) {
        final level = rep['threat_level'] ?? 'ELEVATED';
        String color = '#FF9500';
        if (level == 'CRITICAL') color = '#FF2D55';
        if (level == 'LOW') color = '#00FFAA';

        dynamicPoints.add({
          'lat': lat,
          'lon': lng,
          'title': '🎯 HUMINT: ${rep['title'] ?? 'Reporte de Campo'}',
          'type': 'ALERT',
          'desc': '${rep['description'] ?? ''} [Nivel: $level]',
          'color': color,
        });
      }
    }

    // 4. Cargar Datos en Tiempo Real (Vuelos OpenSky y Sismos USGS)
    try {
      final realTimeData = await CobaltoApiService.fetchRealtime();
      if (realTimeData.isNotEmpty) {
        // Vuelos
        final flightData = realTimeData['flight_data'];
        if (flightData is Map && flightData['flights'] is List) {
          final List flights = flightData['flights'];
          for (var f in flights) {
            if (f is Map) {
              final double? lat = (f['lat'] ?? f['latitude'])?.toDouble();
              final double? lon = (f['lon'] ?? f['longitude'] ?? f['lng'])?.toDouble();
              if (lat != null && lon != null && lat != 0.0 && lon != 0.0) {
                final isEmerg = f['is_emergency'] == true;
                final callsign = f['callsign'] ?? f['icao'] ?? 'VUELO';
                dynamicPoints.add({
                  'lat': lat,
                  'lon': lon,
                  'title': '✈️ Vuelo: $callsign',
                  'type': 'FLIGHT',
                  'desc': 'Altitud: ${f['altitude'] ?? 'N/A'} | Vel: ${f['speed'] ?? 'N/A'}',
                  'color': isEmerg ? '#FF2D55' : '#00E5FF',
                });
              }
            }
          }
        }

        // Sismos USGS
        final eventsData = realTimeData['events_data'];
        if (eventsData is Map && eventsData['earthquakes'] is List) {
          final List quakes = eventsData['earthquakes'];
          for (var q in quakes) {
            if (q is Map) {
              final double? lat = (q['lat'] ?? q['latitude'])?.toDouble();
              final double? lon = (q['lon'] ?? q['longitude'] ?? q['lng'])?.toDouble();
              if (lat != null && lon != null && lat != 0.0 && lon != 0.0) {
                final mag = q['mag'] ?? 'N/A';
                final title = q['title'] ?? 'Sismo detectado';
                dynamicPoints.add({
                  'lat': lat,
                  'lon': lon,
                  'title': '🌋 Sismo: Mag $mag',
                  'type': 'QUAKE',
                  'desc': title.toString(),
                  'color': '#FF9500',
                });
              }
            }
          }
        }
      }
    } catch (_) {}

    // 5. Cargar Alertas Tácticas del Servidor
    try {
      final alertsList = await CobaltoApiService.fetchAlerts();
      for (final alert in alertsList) {
        if (alert is Map) {
          final title = alert['title'] ?? alert['rule'] ?? 'Alerta de Inteligencia';
          final desc = alert['description'] ?? alert['text'] ?? alert['summary'] ?? '';
          final textLower = '$title $desc'.toLowerCase();

          for (final entry in _geoCityCoordinates.entries) {
            if (textLower.contains(entry.key)) {
              final coords = entry.value;
              final double latShift = ((title.hashCode % 7) - 3) * 0.012;
              final double lonShift = (((title.hashCode ~/ 7) % 7) - 3) * 0.012;

              dynamicPoints.add({
                'lat': coords[0] + latShift,
                'lon': coords[1] + lonShift,
                'title': '🚨 ALERTA: $title',
                'type': 'ALERT',
                'desc': desc.length > 90 ? '${desc.substring(0, 90)}...' : desc,
                'color': '#FF2D55',
              });
              break;
            }
          }
        }
      }
    } catch (_) {}

    if (dynamicPoints.isNotEmpty) {
      final jsonStr = json.encode(dynamicPoints);
      await _controller.runJavaScript('updatePoints($jsonStr);');
    }

    if (mounted) {
      setState(() => _isRefreshing = false);
    }
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

          // Barra Superior Flotante de Filtros de Capas y Botón de Recarga
          Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: Row(
              children: [
                Expanded(
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
                          _layerChip('✈️ VUELOS', 'FLIGHT', Icons.flight),
                          const SizedBox(width: 6),
                          _layerChip('🌋 SISMOS', 'QUAKE', Icons.waves),
                          const SizedBox(width: 6),
                          _layerChip('🎥 CCTV', 'CCTV', Icons.videocam),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF10131D).withOpacity(0.9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.4)),
                  ),
                  child: IconButton(
                    icon: _isRefreshing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00E5FF)),
                          )
                        : const Icon(Icons.refresh, color: Color(0xFF00E5FF), size: 18),
                    onPressed: _isRefreshing ? null : _loadDynamicMarkersIntoMap,
                    tooltip: 'Refrescar mapa táctico',
                  ),
                ),
              ],
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

