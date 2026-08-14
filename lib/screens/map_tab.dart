import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/app_logger.dart';
import '../services/local_db_service.dart';
import '../services/cobalto_api_service.dart';
import '../services/gps_service.dart';

class MapTab extends StatefulWidget {
  const MapTab({super.key});

  @override
  State<MapTab> createState() => _MapTabState();
}

class _MapTabState extends State<MapTab> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _isSatelliteMode = false;
  String _activeLayer = 'ALL';
  Timer? _refreshTimer;

  // Contadores dinámicos por capa
  Map<String, int> _layerCounts = {
    'ALL': 0,
    'ALERT': 0,
    'NEWS': 0,
    'FLIGHT': 0,
    'QUAKE': 0,
    'CCTV': 0,
  };

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
      border-radius: 8px; font-family: monospace; font-size: 11px;
      box-shadow: 0 4px 15px rgba(0, 229, 255, 0.25);
      padding: 4px;
    }
    .leaflet-popup-tip { background: #141824; }
    
    /* Animación de Radar Pulsante en CSS */
    @keyframes pulseRing {
      0% { transform: scale(0.3); opacity: 0.9; }
      80% { transform: scale(1.8); opacity: 0.1; }
      100% { transform: scale(2.2); opacity: 0; }
    }
    .pulse-marker-critical {
      width: 24px; height: 24px;
      border-radius: 50%;
      background: rgba(255, 45, 85, 0.4);
      border: 2px solid #FF2D55;
      animation: pulseRing 1.8s infinite ease-out;
    }
    .pulse-marker-quake {
      width: 24px; height: 24px;
      border-radius: 50%;
      background: rgba(255, 149, 0, 0.4);
      border: 2px solid #FF9500;
      animation: pulseRing 2s infinite ease-out;
    }
    .pulse-marker-operator {
      width: 28px; height: 28px;
      border-radius: 50%;
      background: rgba(0, 255, 170, 0.4);
      border: 2px solid #00FFAA;
      animation: pulseRing 1.4s infinite ease-out;
    }
  </style>
</head>
<body>
  <div id="map"></div>
  <script>
    var map = L.map('map', { zoomControl: false }).setView([10.4806, -66.9036], 5);
    
    // Capa 1: Modo Oscuro Vectorial (CartoDB Dark)
    var darkTileLayer = L.tileLayer('https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png', {
      maxZoom: 18,
      subdomains: 'abcd',
      attribution: 'CartoDB Dark | COBALTO C4I'
    });

    // Capa 2: Modo Satelital HD (Esri World Imagery)
    var satTileLayer = L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}', {
      maxZoom: 18,
      attribution: 'Esri Satellite | COBALTO C4I'
    });

    darkTileLayer.addTo(map);
    L.control.zoom({ position: 'bottomright' }).addTo(map);

    var markersGroup = L.layerGroup().addTo(map);
    var pulsesGroup = L.layerGroup().addTo(map);
    var currentFilter = 'ALL';

    var allPoints = [];

    function centerMap(lat, lon, zoom) {
      map.flyTo([lat, lon], zoom || 14);
    }

    function setTileMode(isSat) {
      if (isSat) {
        map.removeLayer(darkTileLayer);
        satTileLayer.addTo(map);
      } else {
        map.removeLayer(satTileLayer);
        darkTileLayer.addTo(map);
      }
    }

    function filterPoints(type) {
      currentFilter = type;
      markersGroup.clearLayers();
      pulsesGroup.clearLayers();

      allPoints.forEach(function(p) {
        if (type === 'ALL' || p.type === type) {
          // Anillos pulsantes para Alerta, Sismo u Operador GPS
          if (p.type === 'ALERT' || p.type === 'QUAKE' || p.type === 'OPERATOR') {
            var pulseClass = 'pulse-marker-critical';
            if (p.type === 'QUAKE') pulseClass = 'pulse-marker-quake';
            if (p.type === 'OPERATOR') pulseClass = 'pulse-marker-operator';

            var pulseIcon = L.divIcon({
              className: pulseClass,
              iconSize: [28, 28],
              iconAnchor: [14, 14]
            });
            var pulseMarker = L.marker([p.lat, p.lon], { icon: pulseIcon, interactive: false });
            pulsesGroup.addLayer(pulseMarker);
          }

          var marker = L.circleMarker([p.lat, p.lon], {
            radius: p.type === 'BASE' ? 10 : 7,
            fillColor: p.color || '#00E5FF',
            color: '#ffffff',
            weight: 2,
            opacity: 1,
            fillOpacity: 0.9
          });

          marker.pointData = p;

          var html = "<div style='padding:4px;'>" +
                     "<strong style='color:" + (p.color || '#00E5FF') + "; font-size:12px;'>" + p.title + "</strong><br/>" +
                     "<div style='color:#ddd; margin-top:4px; margin-bottom:6px; line-height:1.3;'>" + p.desc + "</div>" +
                     "<div style='border-top:1px solid #333; padding-top:4px; color:#888; font-size:9px; display:flex; justify-content:space-between;'>" +
                       "<span>📍 " + p.lat.toFixed(4) + ", " + p.lon.toFixed(4) + "</span>" +
                       "<span style='color:#00E5FF; font-weight:bold;'>TOCA PARA ABRIR</span>" +
                     "</div>" +
                     "</div>";

          marker.bindPopup(html, { maxWidth: 260 });

          marker.on('click', function(e) {
            if (window.FlutterBridge && e.target.pointData) {
              window.FlutterBridge.postMessage(JSON.stringify(e.target.pointData));
            }
          });

          markersGroup.addLayer(marker);
        }
      });
    }

    function updatePoints(newPoints) {
      if (Array.isArray(newPoints)) {
        allPoints = newPoints;
        filterPoints(currentFilter);
      }
    }
  </script>
</body>
</html>
''';

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0A0B10))
      ..addJavaScriptChannel(
        'FlutterBridge',
        onMessageReceived: (JavaScriptMessage message) {
          try {
            final Map<String, dynamic> data = json.decode(message.message);
            _showMarkerDetailsBottomSheet(data);
          } catch (e) {
            AppLogger.warn('Mensaje JS del mapa no descifrable.', tag: 'Map', error: e);
          }
        },
      )
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

  void _toggleSatelliteMode() {
    setState(() => _isSatelliteMode = !_isSatelliteMode);
    _controller.runJavaScript("setTileMode($_isSatelliteMode);");
  }

  Future<void> _centerOnOperator() async {
    final pos = await GpsService.getCurrentPosition();
    if (pos != null) {
      _controller.runJavaScript('centerMap(${pos.latitude}, ${pos.longitude}, 14);');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📍 Mapa centrado en la ubicación GPS del operador (${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)})'),
            backgroundColor: const Color(0xFF00FFAA),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ No se pudo obtener la posición GPS. Verifica los permisos de ubicación.'),
            backgroundColor: Color(0xFFFF2D55),
          ),
        );
      }
    }
  }

  Future<void> _loadDynamicMarkersIntoMap() async {
    if (!mounted) return;
    setState(() => _isRefreshing = true);

    final List<Map<String, dynamic>> dynamicPoints = [];

    // 0. Ubicación GPS en Vivo del Operador
    final currentPos = await GpsService.getCurrentPosition();
    if (currentPos != null) {
      dynamicPoints.add({
        'lat': currentPos.latitude,
        'lon': currentPos.longitude,
        'title': '🛰️ OPERADOR (MI UBICACIÓN GPS)',
        'type': 'OPERATOR',
        'desc': 'Posición actual en tiempo real obtenida del sensor GPS del dispositivo.',
        'color': '#00FFAA'
      });
    }

    // 1. Añadir Nodo Central Fijo
    dynamicPoints.add({
      'lat': 10.4806,
      'lon': -66.9036,
      'title': '📌 CARACAS (C4I CENTRAL)',
      'type': 'BASE',
      'desc': 'Nodo Central de Mando e Inteligencia COBALTO',
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

      for (final entry in _geoCityCoordinates.entries) {
        if (textLower.contains(entry.key)) {
          final coords = entry.value;
          final double latShift = ((title.hashCode % 10) - 5) * 0.015;
          final double lonShift = (((title.hashCode ~/ 10) % 10) - 5) * 0.015;

          final bool isCritical = textLower.contains('alerta') || textLower.contains('conflicto') || textLower.contains('ciberataque');

          dynamicPoints.add({
            'lat': coords[0] + latShift,
            'lon': coords[1] + lonShift,
            'title': '📰 ${news['source'] ?? 'SITREP'}: ${title.length > 45 ? '${title.substring(0, 45)}...' : title}',
            'type': isCritical ? 'ALERT' : 'NEWS',
            'desc': summary.length > 90 ? '${summary.substring(0, 90)}...' : summary,
            'color': isCritical ? '#FF2D55' : '#00E5FF',
            'link': news['link'],
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
          'desc': '${rep['description'] ?? ''} [Threat Level: $level]',
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
                  'title': '✈️ VUELO: $callsign',
                  'type': 'FLIGHT',
                  'desc': 'Altitud: ${f['altitude'] ?? 'N/A'} | Vel: ${f['speed'] ?? 'N/A'} kts',
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
                  'title': '🌋 SISMO: MAG $mag M',
                  'type': 'QUAKE',
                  'desc': title.toString(),
                  'color': '#FF9500',
                });
              }
            }
          }
        }
      }
    } catch (e) {
      AppLogger.warn('Error cargando datos sísmicos/geográficos del mapa.', tag: 'Map', error: e);
    }

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
    } catch (e) {
      AppLogger.warn('Error cargando alertas tácticas en el mapa.', tag: 'Map', error: e);
    }

    // Actualizar contadores
    final newCounts = {
      'ALL': dynamicPoints.length,
      'ALERT': dynamicPoints.where((p) => p['type'] == 'ALERT').length,
      'NEWS': dynamicPoints.where((p) => p['type'] == 'NEWS').length,
      'FLIGHT': dynamicPoints.where((p) => p['type'] == 'FLIGHT').length,
      'QUAKE': dynamicPoints.where((p) => p['type'] == 'QUAKE').length,
      'CCTV': dynamicPoints.where((p) => p['type'] == 'CCTV').length,
    };

    if (dynamicPoints.isNotEmpty) {
      final jsonStr = json.encode(dynamicPoints);
      await _controller.runJavaScript('updatePoints($jsonStr);');
    }

    if (mounted) {
      setState(() {
        _layerCounts = newCounts;
        _isRefreshing = false;
      });
    }
  }

  void _filterLayer(String layerId) {
    setState(() => _activeLayer = layerId);
    _controller.runJavaScript("filterPoints('$layerId');");
  }

  void _showMarkerDetailsBottomSheet(Map<String, dynamic> item) {
    final title = item['title'] ?? 'Detalles del Evento';
    final desc = item['desc'] ?? '';
    final lat = item['lat'];
    final lon = item['lon'];
    final colorHex = item['color'] ?? '#00E5FF';

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141824),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Padding(
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
      ),
    );
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

          // Barra Superior Flotante Optimizada para Móvil
          Positioned(
            top: 10,
            left: 8,
            right: 8,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10131D).withOpacity(0.92),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.4)),
                      boxShadow: const [
                        BoxShadow(color: Colors.black54, blurRadius: 8),
                      ],
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _layerChip('TODAS', 'ALL', Icons.map),
                          const SizedBox(width: 5),
                          _layerChip('🚨 ALERTAS', 'ALERT', Icons.warning_amber),
                          const SizedBox(width: 5),
                          _layerChip('📰 NOTICIAS', 'NEWS', Icons.newspaper),
                          const SizedBox(width: 5),
                          _layerChip('✈️ VUELOS', 'FLIGHT', Icons.flight),
                          const SizedBox(width: 5),
                          _layerChip('🌋 SISMOS', 'QUAKE', Icons.waves),
                          const SizedBox(width: 5),
                          _layerChip('🎥 CCTV', 'CCTV', Icons.videocam),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                
                // Botón Mi Ubicación GPS
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF10131D).withOpacity(0.92),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF00FFAA).withOpacity(0.6)),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.my_location, color: Color(0xFF00FFAA), size: 18),
                    onPressed: _centerOnOperator,
                    tooltip: 'Centrar en mi ubicación GPS',
                  ),
                ),
                const SizedBox(width: 4),

                // Conmutador de Mapa Satelital / Vectorial
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF10131D).withOpacity(0.92),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _isSatelliteMode ? const Color(0xFFFFD60A) : const Color(0xFF00E5FF).withOpacity(0.4),
                    ),
                  ),
                  child: IconButton(
                    icon: Icon(
                      _isSatelliteMode ? Icons.satellite_alt : Icons.map_outlined,
                      color: _isSatelliteMode ? const Color(0xFFFFD60A) : const Color(0xFF00E5FF),
                      size: 18,
                    ),
                    onPressed: _toggleSatelliteMode,
                    tooltip: _isSatelliteMode ? 'Cambiar a Mapa Oscuro Vectorial' : 'Cambiar a Mapa Satelital HD',
                  ),
                ),
                const SizedBox(width: 4),

                // Botón de Recarga
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF10131D).withOpacity(0.92),
                    borderRadius: BorderRadius.circular(10),
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

          // Sello Flotante Táctico Inferior Izquierdo
          Positioned(
            bottom: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF10131D).withOpacity(0.85),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFF00FFAA),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _isSatelliteMode ? 'SATELLITE HD // LIVE' : 'C4I DARK RADAR // LIVE',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 9,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _layerChip(String label, String code, IconData icon) {
    final isSelected = _activeLayer == code;
    final count = _layerCounts[code] ?? 0;

    return GestureDetector(
      onTap: () => _filterLayer(code),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
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
              '$label ($count)',
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
