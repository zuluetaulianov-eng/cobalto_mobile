import 'dart:async';
import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'app_logger.dart';
import 'gps_service.dart';
import 'local_db_service.dart';
import 'notification_service.dart';

/// Zona geográfica táctica (círculo con nombre, radio y nivel de amenaza).
class GeofenceZone {
  final String id;
  final String name;
  final double lat;
  final double lng;
  final double radiusKm;
  final String threatLevel;
  final bool isBase;
  final bool active;
  final String timestamp;

  const GeofenceZone({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.radiusKm,
    required this.threatLevel,
    required this.isBase,
    required this.active,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'lat': lat,
        'lng': lng,
        'radius_km': radiusKm,
        'threat_level': threatLevel,
        'is_base': isBase ? 1 : 0,
        'active': active ? 1 : 0,
        'timestamp': timestamp,
      };

  static GeofenceZone fromMap(Map<String, dynamic> m) => GeofenceZone(
        id: (m['id'] ?? '').toString(),
        name: (m['name'] ?? '').toString(),
        lat: (m['lat'] is num) ? (m['lat'] as num).toDouble() : 0.0,
        lng: (m['lng'] is num) ? (m['lng'] as num).toDouble() : 0.0,
        radiusKm: (m['radius_km'] is num) ? (m['radius_km'] as num).toDouble() : 1.0,
        threatLevel: (m['threat_level'] ?? 'ALTA').toString(),
        isBase: (m['is_base'] == 1 || m['is_base'] == true),
        active: (m['active'] == 1 || m['active'] == true),
        timestamp: (m['timestamp'] ?? '').toString(),
      );
}

/// Integración de geocercas: persistencia local (SQLite + fallback prefs),
/// monitoreo periódico configurable de la posición GPS y alertas automáticas
/// de entrada/salida de zona con deduplicación.
class GeofenceService {
  static const String _prefsKey = 'local_geofences';

  static const List<Map<String, String>> monitoringIntervals = [
    {'label': 'INSTANTÁNEO (CADA FIX)', 'value': '0'},
    {'label': '10 SEGUNDOS', 'value': '10'},
    {'label': '30 SEGUNDOS', 'value': '30'},
    {'label': '1 MINUTO', 'value': '60'},
    {'label': '5 MINUTOS', 'value': '300'},
    {'label': '30 MINUTOS', 'value': '1800'},
    {'label': '60 MINUTOS', 'value': '3600'},
  ];

  static const String _intervalPrefsKey = 'geofence_monitor_interval_seconds';
  static const String _monitoringEnabledKey = 'geofence_monitoring_enabled';

  static Timer? _monitorTimer;
  static bool _isMonitoring = false;
  static bool get isMonitoring => _isMonitoring;

  static final Set<String> _insideZones = {};
  static bool _wasAtBase = false;

  // ── Persistencia ──

  static Future<List<GeofenceZone>> getZones() async {
    try {
      final db = await LocalDbService.database;
      final rows = await db.query('geofences', orderBy: 'timestamp DESC');
      return rows.map(GeofenceZone.fromMap).toList();
    } catch (e) {
      AppLogger.warn('SQLite no disponible para geofences; usando fallback prefs.', tag: 'Geo', error: e);
      return _zonesFromPrefs();
    }
  }

  static Future<void> addZone({
    required String name,
    required double lat,
    required double lng,
    required double radiusKm,
    String threatLevel = 'ALTA',
    bool isBase = false,
    bool active = true,
  }) async {
    final zone = GeofenceZone(
      id: 'geo_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      lat: lat,
      lng: lng,
      radiusKm: radiusKm,
      threatLevel: threatLevel,
      isBase: isBase,
      active: active,
      timestamp: DateTime.now().toIso8601String(),
    );
    await _upsert(zone);
  }

  static Future<void> removeZone(String id) async {
    try {
      final db = await LocalDbService.database;
      await db.delete('geofences', where: 'id = ?', whereArgs: [id]);
    } catch (e) {
      AppLogger.warn('No se pudo borrar geocerca de SQLite.', tag: 'Geo', error: e);
    }
    _insideZones.remove(id);
    await _syncPrefsFromDb();
  }

  static Future<void> toggleZone(String id, bool active) async {
    final zones = await getZones();
    for (final z in zones) {
      if (z.id == id) {
        await _upsert(GeofenceZone(
          id: z.id,
          name: z.name,
          lat: z.lat,
          lng: z.lng,
          radiusKm: z.radiusKm,
          threatLevel: z.threatLevel,
          isBase: z.isBase,
          active: active,
          timestamp: z.timestamp,
        ));
        if (!active) _insideZones.remove(id);
        return;
      }
    }
  }

  /// Marca una zona existente como perímetro de base (la única que genera
  /// alertas de presencia/ausencia del operador).
  static Future<void> markAsBase(String id) async {
    final zones = await getZones();
    for (final z in zones) {
      if (z.id == id) {
        // Desmarcar cualquier otra zona como base
        for (final other in zones) {
          if (other.isBase) {
            await _upsert(GeofenceZone(
              id: other.id,
              name: other.name,
              lat: other.lat,
              lng: other.lng,
              radiusKm: other.radiusKm,
              threatLevel: other.threatLevel,
              isBase: false,
              active: other.active,
              timestamp: other.timestamp,
            ));
          }
        }
        await _upsert(GeofenceZone(
          id: z.id,
          name: z.name,
          lat: z.lat,
          lng: z.lng,
          radiusKm: z.radiusKm,
          threatLevel: z.threatLevel,
          isBase: true,
          active: z.active,
          timestamp: z.timestamp,
        ));
        return;
      }
    }
  }

  static Future<void> _upsert(GeofenceZone zone) async {
    try {
      final db = await LocalDbService.database;
      await db.insert(
        'geofences',
        zone.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      AppLogger.warn('SQLite no disponible para insert de geocerca; usando prefs.', tag: 'Geo', error: e);
    }
    await _syncPrefsFromDb();
  }

  static Future<List<GeofenceZone>> _zonesFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_prefsKey);
    if (str == null || str.isEmpty) return [];
    try {
      final decoded = jsonDecode(str) as List;
      return decoded
          .map((e) => GeofenceZone.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      AppLogger.warn('Cache prefs de geofences corrupto.', tag: 'Geo', error: e);
      return [];
    }
  }

  static Future<void> _syncPrefsFromDb() async {
    try {
      final zones = await getZones();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(zones.map((z) => z.toMap()).toList()));
    } catch (e) {
      AppLogger.warn('No se pudo sincronizar geofences a prefs.', tag: 'Geo', error: e);
    }
  }

  static Future<void> clearAllZones() async {
    try {
      final db = await LocalDbService.database;
      await db.delete('geofences');
    } catch (e) {
      AppLogger.warn('No se pudieron borrar las geocercas.', tag: 'Geo', error: e);
    }
    _insideZones.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  // ── Monitoreo ──

  static Future<int> getMonitoringIntervalSeconds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_intervalPrefsKey) ?? 60;
  }

  static Future<void> saveMonitoringIntervalSeconds(int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_intervalPrefsKey, seconds);
    if (_isMonitoring) restartMonitoring();
  }

  static Future<bool> isMonitoringEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_monitoringEnabledKey) ?? false;
  }

  static Future<void> setMonitoringEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_monitoringEnabledKey, enabled);
    if (enabled) {
      startMonitoring();
    } else {
      stopMonitoring();
    }
  }

  /// Arranca el temporizador de monitoreo con el intervalo configurado.
  static void startMonitoring({int? intervalSeconds}) {
    if (_isMonitoring) return;
    _isMonitoring = true;

    final int seconds = intervalSeconds ?? 60;
    if (seconds <= 0) {
      // Modo instantáneo: evaluar una vez y, si hay zonas, forzar un fix corto.
      _evaluateAllZonesFiring();
      _monitorTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        _evaluateAllZonesFiring();
      });
      return;
    }

    _monitorTimer = Timer.periodic(Duration(seconds: seconds), (_) {
      _evaluateAllZonesFiring();
    });
  }

  static void stopMonitoring() {
    _isMonitoring = false;
    _monitorTimer?.cancel();
    _monitorTimer = null;
    _insideZones.clear();
    _wasAtBase = false;
  }

  static void restartMonitoring() {
    final wasMonitoring = _isMonitoring;
    stopMonitoring();
    if (wasMonitoring) startMonitoring();
  }

  /// Evaluación completa: posición actual vs todas las geocercas activas.
  static Future<void> _evaluateAllZonesFiring() =>
      synchronizedEvaluation();

  static Future<void> synchronizedEvaluation() async {
    if (_isMonitoring == false) return;
    try {
      final zones = await getZones();
      final activeZones = zones.where((z) => z.active).toList();
      if (activeZones.isEmpty) return;

      // Reutilizar la telemetría del stream si es reciente (≤45s); solo en ese
      // caso se abre un fix puntual nuevo, reduciendo el gasto de batería.
      final TacticalSnapshot? snapshot = GpsService.lastSnapshot;
      final bool snapshotFresh = snapshot != null &&
          DateTime.now().toUtc().difference(snapshot.timestampUtc).inSeconds <= 45;

      final Position? pos = snapshotFresh
          ? Position(
              latitude: snapshot.lat,
              longitude: snapshot.lon,
              timestamp: snapshot.timestampUtc,
              accuracy: snapshot.accuracyM ?? 0.0,
              altitude: snapshot.altitudeM ?? 0.0,
              heading: snapshot.headingDeg ?? 0.0,
              speed: snapshot.speedMps ?? 0.0,
              speedAccuracy: snapshot.speedAccuracyMps ?? 0.0,
              altitudeAccuracy: 0.0,
              headingAccuracy: 0.0,
              isMocked: false,
              floor: null,
            )
          : await GpsService.getCurrentPosition();
      if (pos == null) return;

      for (final zone in activeZones) {
        final distanceKm = GpsService.calculateDistanceInKm(
          pos.latitude, pos.longitude, zone.lat, zone.lng);

        final bool inside = distanceKm <= zone.radiusKm;
        final bool wasInside = _insideZones.contains(zone.id);

        // Transición de ENTRADA a zona
        if (inside && !wasInside) {
          _insideZones.add(zone.id);
          await _notifyZoneEntry(zone, distanceKm);
        }
        // Transición de SALIDA de zona
        if (!inside && wasInside) {
          _insideZones.remove(zone.id);
          await _notifyZoneExit(zone, distanceKm);
        }
      }

      // Alerta de base (opcional): avisar si el operador entra/sale del perímetro base.
      final baseZone = activeZones.where((z) => z.isBase).toList();
      if (baseZone.isNotEmpty) {
        final base = baseZone.first;
        final inBase = GpsService.calculateDistanceInKm(
          pos.latitude, pos.longitude, base.lat, base.lng) <= base.radiusKm;
        if (inBase != _wasAtBase) {
          _wasAtBase = inBase;
          await _notifyBaseStatus(base, inBase);
        }
      }
    } catch (e) {
      AppLogger.warn('Error en la evaluación de geocercas.', tag: 'Geo', error: e);
    }
  }

  static Future<void> _notifyZoneEntry(GeofenceZone zone, double distanceKm) async {
    final dedupeKey = 'geofence|enter|${zone.id}';
    final title = '🚨 ZONA TÁCTICA: ${zone.name}';
    final body = 'Ha ingresado a la zona "${zone.name}" (radio ${zone.radiusKm} km, '
        'distancia actual ${distanceKm.toStringAsFixed(2)} km). Nivel de amenaza: ${zone.threatLevel}.';

    await NotificationService.showAlertNotification(
      title: title,
      body: body,
      level: zone.threatLevel,
      deduplicationKey: dedupeKey,
    );

    await LocalDbService.saveFieldReport({
      'title': '🚨 INGRESO A GEOCERCA: ${zone.name}',
      'description': 'Entrada a zona táctica con nivel ${zone.threatLevel}. Distancia al centro: ${distanceKm.toStringAsFixed(2)} km.',
      'threat_level': zone.threatLevel,
      'lat': zone.lat,
      'lng': zone.lng,
    });
  }

  static Future<void> _notifyZoneExit(GeofenceZone zone, double distanceKm) async {
    final dedupeKey = 'geofence|exit|${zone.id}';
    final title = 'ℹ️ SALIDA DE ZONA: ${zone.name}';
    final body = 'Ha abandonado la zona "${zone.name}" (distancia actual '
        '${distanceKm.toStringAsFixed(2)} km al centro).';

    await NotificationService.showAlertNotification(
      title: title,
      body: body,
      level: 'INFORMATIVA',
      deduplicationKey: dedupeKey,
    );

    await LocalDbService.saveFieldReport({
      'title': 'ℹ️ SALIDA DE GEOCERCA: ${zone.name}',
      'description': 'Salida de la zona táctica.',
      'threat_level': 'LOW',
      'lat': zone.lat,
      'lng': zone.lng,
    });
  }

  static Future<void> _notifyBaseStatus(GeofenceZone base, bool inBase) async {
    if (inBase) {
      await NotificationService.showAlertNotification(
        title: '🛡️ OPERADOR PRESENTE EN BASE',
        body: 'Ha regresado al perímetro de seguridad de la base "${base.name}".',
        level: 'INFORMATIVA',
        deduplicationKey: 'geofence|base|in',
      );
    } else {
      await NotificationService.showAlertNotification(
        title: '⚠️ OPERADOR FUERA DEL PERÍMETRO DE BASE',
        body: 'Usted se ha alejado del perímetro de seguridad de la base "${base.name}". Verifique su ubicación.',
        level: 'ALTA',
        deduplicationKey: 'geofence|base|out',
      );
    }
  }
}