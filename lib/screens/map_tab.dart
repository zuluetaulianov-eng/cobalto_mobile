import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../config/map_html_content.dart';
import '../services/app_logger.dart';
import '../services/geofence_service.dart';
import '../services/gps_service.dart';
import '../services/aegis_survival_map_service.dart';
import '../services/map_points_service.dart';
import '../widgets/map_marker_details_sheet.dart';

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
    'SURVIVAL_POI': 0, // Fase 4: POIs colaborativos de supervivencia.
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
      ..loadHtmlString(kMapHtmlContent);
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

    final dynamicPoints = await MapPointsService.buildDynamicPoints();

    // Fase 4: agregar POIs CRDT de supervivencia.
    try {
      final survivalPoints = await AegisSurvivalMapService.buildSurvivalMapPoints();
      dynamicPoints.addAll(survivalPoints);
    } catch (e) {
      AppLogger.warn('No se pudieron cargar POIs de supervivencia.', tag: 'Map', error: e);
    }

    // Dibujar las geocercas tácticas activas sobre el mapa Leaflet
    final zones = await GeofenceService.getZones();
    if (zones.isNotEmpty) {
      final zonesJson = json.encode(
        zones.map((z) => {
          'lat': z.lat,
          'lng': z.lng,
          'radiusKm': z.radiusKm,
          'threatLevel': z.threatLevel,
        }).toList(),
      );
      await _controller.runJavaScript('updateGeofences($zonesJson);');
    } else {
      await _controller.runJavaScript('updateGeofences([]);');
    }

    // Actualizar contadores (incluyendo SURVIVAL_POI).
    final newCounts = MapPointsService.computeLayerCounts(dynamicPoints);
    newCounts['SURVIVAL_POI'] =
        dynamicPoints.where((p) => p['type'] == 'SURVIVAL_POI').length;

    // Siempre actualizar (incluso lista vacía) para limpiar marcadores stale.
    final jsonStr = json.encode(dynamicPoints);
    await _controller.runJavaScript('updatePoints($jsonStr);');

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
    MapMarkerDetailsSheet.show(context, item);
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
                          _layerChip('📍 SUPERVIVENCIA', 'SURVIVAL_POI', Icons.local_hospital),
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