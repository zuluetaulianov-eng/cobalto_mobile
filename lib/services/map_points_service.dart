import '../services/app_logger.dart';
import '../services/cobalto_api_service.dart';
import '../services/gps_service.dart';
import '../services/local_db_service.dart';

/// Construcción de los marcadores geográficos del Mapa Táctico COBALTO:
/// operador GPS, nodo central, noticias SIGINT, reportes HUMINT, vuelos,
/// sismos y alertas, con mapeo por palabras clave tácticas.
class MapPointsService {
  // Mapeo Geográfico por Palabras Clave Tácticas
  static const Map<String, List<double>> geoCityCoordinates = {
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

  /// Reúne todos los marcadores dinámicos para inyectar en el mapa Leaflet.
  static Future<List<Map<String, dynamic>>> buildDynamicPoints() async {
    final dynamicPoints = <Map<String, dynamic>>[];

    // 0. Ubicación GPS en Vivo del Operador (telemetría del stream si es fresca)
    final TacticalSnapshot? snapshot = GpsService.lastSnapshot;
    final bool snapshotFresh = snapshot != null &&
        DateTime.now().toUtc().difference(snapshot.timestampUtc).inSeconds <= 60;
    if (snapshotFresh) {
      dynamicPoints.add({
        'lat': snapshot.lat,
        'lon': snapshot.lon,
        'title': '🛰️ OPERADOR (MI UBICACIÓN GPS)',
        'type': 'OPERATOR',
        'desc': snapshot.accuracyM != null
            ? 'Telemetría en vivo: precisión ±${snapshot.accuracyM!.round()} m, ${snapshot.speedKtsLabel}.'
            : 'Posición actual en tiempo real obtenida del sensor GPS del dispositivo.',
        'color': '#00FFAA'
      });
    } else {
      final currentPos = await GpsService.getCurrentPosition();
      if (currentPos != null) {
        dynamicPoints.add({
          'lat': currentPos.latitude,
          'lon': currentPos.longitude,
          'title': '🛰️ OPERADOR (MI UBICACIÓN GPS)',
          'type': 'OPERATOR',
          'desc': 'Posición actual obtenida del sensor GPS del dispositivo.',
          'color': '#00FFAA'
        });
      }
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

      for (final entry in geoCityCoordinates.entries) {
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
    await _appendRealtimePoints(dynamicPoints);

    // 5. Cargar Alertas Tácticas del Servidor
    await _appendAlertPoints(dynamicPoints);

    return dynamicPoints;
  }

  static Future<void> _appendRealtimePoints(List<Map<String, dynamic>> dynamicPoints) async {
    try {
      final realTimeData = await CobaltoApiService.fetchRealtime();
      if (realTimeData.isEmpty) return;

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
    } catch (e) {
      AppLogger.warn('Error cargando datos sísmicos/geográficos del mapa.', tag: 'Map', error: e);
    }
  }

  static Future<void> _appendAlertPoints(List<Map<String, dynamic>> dynamicPoints) async {
    try {
      final alertsList = await CobaltoApiService.fetchAlerts();
      for (final alert in alertsList) {
        if (alert is Map) {
          final title = alert['title'] ?? alert['rule'] ?? 'Alerta de Inteligencia';
          final desc = alert['description'] ?? alert['text'] ?? alert['summary'] ?? '';
          final textLower = '$title $desc'.toLowerCase();

          for (final entry in geoCityCoordinates.entries) {
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
  }

  /// Calcula los contadores por capa a partir de los puntos dinámicos.
  static Map<String, int> computeLayerCounts(List<Map<String, dynamic>> points) {
    return {
      'ALL': points.length,
      'ALERT': points.where((p) => p['type'] == 'ALERT').length,
      'NEWS': points.where((p) => p['type'] == 'NEWS').length,
      'FLIGHT': points.where((p) => p['type'] == 'FLIGHT').length,
      'QUAKE': points.where((p) => p['type'] == 'QUAKE').length,
      'CCTV': points.where((p) => p['type'] == 'CCTV').length,
    };
  }
}