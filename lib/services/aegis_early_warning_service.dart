import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_logger.dart';
import 'cobalto_api_service.dart';
import 'gps_service.dart';
import 'local_db_service.dart';
import 'notification_service.dart';
import 'voice_service.dart';

/// Sismo global normalizado desde el hub COBALTO o el feed directo USGS.
class AegisQuakeEvent {
  final String id;
  final double lat;
  final double lon;
  final double? mag;
  final String place;
  final DateTime timeUtc;
  final bool tsunamiAlert;
  final String alertLevel;

  const AegisQuakeEvent({
    required this.id,
    required this.lat,
    required this.lon,
    required this.mag,
    required this.place,
    required this.timeUtc,
    required this.tsunamiAlert,
    required this.alertLevel,
  });
}

/// Alerta temprana de sismo ya evaluada contra la posición del operador.
class AegisQuakeAlert {
  final AegisQuakeEvent event;
  final double distanceKm;
  final String nivel; // CRÍTICA | ALTA | MEDIA
  final int pArrivalS;
  final int sArrivalS;

  const AegisQuakeAlert({
    required this.event,
    required this.distanceKm,
    required this.nivel,
    required this.pArrivalS,
    required this.sArrivalS,
  });
}

/// ALERTA TEMPRANA AEGIS (FASE 2): sensores globales sin depender del servidor.
///
///  - **Fetch directo USGS**: fallback cuando el hub COBALTO (`fetchRealtime`)
///    no responde. El feed `2.5_day` cubre sismos M≥2.5 de las últimas 24 h.
///  - **Algoritmo P/S**: con la distancia al epicentro estima cuándo llegan las
///    ondas P (temblor leve) y S (sacudida fuerte) -> ventana de anticipación.
///  - **Sirena intrusiva LOCAL**: sin servidor, por nivel/escala (CRÍTICA/ALTA)
///    con sonido de alarma acotado + notificación de máxima prioridad + TTS.
///  - **Geocerca automática**: dispara solo si el epicentro cae en el radio
///    configurado de la posición actual del operador y supera la magnitud mínima.
class AegisEarlyWarningService {
  static const String _usgsFeedUrl =
      'https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/2.5_day.geojson';

  static const String _seenIdsKey = 'aegis_ew_seen_ids';
  static const String _enabledKey = 'aegis_ew_enabled';
  static const String _radiusKmKey = 'aegis_ew_radius_km';
  static const String _minMagKey = 'aegis_ew_min_mag';
  static const String _pollMinutesKey = 'aegis_ew_poll_minutes';

  /// Velocidades de propagación sísmicas típicas de la corteza continental.
  static const double pWaveKmS = 6.0;
  static const double sWaveKmS = 3.5;

  static Timer? _monitorTimer;

  /// Última alerta temprana disparada (para monitoreo/UI futura).
  static final ValueNotifier<AegisQuakeAlert?> lastAlert =
      ValueNotifier<AegisQuakeAlert?>(null);

  // ── CONFIGURACIÓN PERSISTENTE ──

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? true;
  }

  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
    if (enabled) {
      await startMonitoring();
    } else {
      stopMonitoring();
    }
  }

  static Future<double> radiusKm() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_radiusKmKey) ?? 200.0;
  }

  static Future<void> setRadiusKm(double km) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_radiusKmKey, km);
  }

  static Future<double> minMag() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_minMagKey) ?? 4.0;
  }

  static Future<void> setMinMag(double mag) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_minMagKey, mag);
  }

  static Future<int> pollMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_pollMinutesKey) ?? 10;
  }

  static Future<void> setPollMinutes(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_pollMinutesKey, minutes);
    if (_monitorTimer != null) {
      await startMonitoring();
    }
  }

  // ── ALGORITMO P/S (ONDAS SÍSMICAS) ──

  /// Tiempos de llegada (segundos) de las ondas P y S a [distanceKm] km del
  /// epicentro. La ventana de anticipación = llegada de S (sacudida fuerte).
  static ({int pArrivalS, int sArrivalS}) computeArrivals(double distanceKm) {
    final int p = (distanceKm / pWaveKmS).ceil();
    final int s = (distanceKm / sWaveKmS).ceil();
    return (pArrivalS: p, sArrivalS: s);
  }

  /// Clasifica la amenaza por magnitud y distancia (escala de COLUMNA).
  static String classifyThreat(double mag, double distanceKm) {
    if (mag >= 7.0) {
      if (distanceKm <= 100) return 'CRÍTICA';
      if (distanceKm <= 300) return 'ALTA';
      return 'INFO';
    }
    if (mag >= 6.0) {
      if (distanceKm <= 120) return 'CRÍTICA';
      if (distanceKm <= 250) return 'ALTA';
      return 'INFO';
    }
    if (mag >= 5.0) {
      if (distanceKm <= 150) return 'ALTA';
      if (distanceKm <= 300) return 'MEDIA';
      return 'INFO';
    }
    if (mag >= 4.0) {
      if (distanceKm <= 120) return 'MEDIA';
      return 'INFO';
    }
    return 'INFO';
  }

  /// Geocerca: ¿el epicentro está dentro del radio y supera la magnitud mínima?
  static bool withinFence({
    required double distanceKm,
    required double radiusKm,
    required double mag,
    required double minMag,
  }) {
    return distanceKm <= radiusKm && mag >= minMag;
  }

  static int _priority(String nivel) {
    switch (nivel) {
      case 'CRÍTICA':
        return 3;
      case 'ALTA':
        return 2;
      case 'MEDIA':
        return 1;
      default:
        return 0;
    }
  }

  // ── BUZÓN DE SENSORES: HUB COBALTO O USGS DIRECTO ──

  /// Intenta primero el hub COBALTO; si el listado llega vacío, hace el
  /// fetch DIRECTO a USGS (modo sin servidor).
  static Future<List<AegisQuakeEvent>> fetchQuakes() async {
    try {
      final hub = await CobaltoApiService.fetchRealtime();
      final events = hub['events_data'];
      final parsed = _parseHubEarthquakes(events);
      if (parsed.isNotEmpty) return parsed;
    } catch (e) {
      AppLogger.warn('Hub sin realtime; despliegue a USGS directo.', tag: 'EW', error: e);
    }
    return _fetchUsgsDirect();
  }

  static List<AegisQuakeEvent> _parseHubEarthquakes(dynamic eventsData) {
    if (eventsData is! Map || eventsData['earthquakes'] is! List) return const [];
    final List<AegisQuakeEvent> out = [];
    for (final q in eventsData['earthquakes'] as List) {
      if (q is! Map) continue;
      final double? lat = (q['lat'] ?? q['latitude'])?.toDouble();
      final double? lon = (q['lon'] ?? q['longitude'] ?? q['lng'])?.toDouble();
      if (lat == null || lon == null) continue;
      out.add(AegisQuakeEvent(
        id: 'hub|${lat.toStringAsFixed(3)}|${lon.toStringAsFixed(3)}|${q['time']}',
        lat: lat,
        lon: lon,
        mag: (q['mag'] ?? q['magnitude'])?.toDouble(),
        place: q['title']?.toString() ?? 'Sismo detectado',
        timeUtc: DateTime.tryParse(q['time']?.toString() ?? '')?.toUtc() ?? DateTime.now().toUtc(),
        tsunamiAlert: q['tsunami'] == true || q['tsunami'] == 1,
        alertLevel: q['alert']?.toString() ?? 'green',
      ));
    }
    return out;
  }

  static Future<List<AegisQuakeEvent>> _fetchUsgsDirect() async {
    try {
      final res = await http
          .get(Uri.parse(_usgsFeedUrl))
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return const [];

      final data = json.decode(res.body);
      final features = data is Map ? data['features'] : null;
      if (features is! List) return const [];

      final List<AegisQuakeEvent> out = [];
      for (final f in features) {
        if (f is! Map) continue;
        final props = f['properties'];
        final geom = f['geometry'];
        if (props is! Map || geom is! Map) continue;
        final coords = geom['coordinates'];
        if (coords is! List || coords.length < 2) continue;
        final double? lon = coords[0]?.toDouble();
        final double? lat = coords[1]?.toDouble();
        final double? mag = props['mag']?.toDouble();
        if (lat == null || lon == null || mag == null) continue;

        final int? timeMs = props['time'] is num ? (props['time'] as num).toInt() : null;
        out.add(AegisQuakeEvent(
          id: f['id']?.toString() ?? 'usgs|$lat|$lon',
          lat: lat,
          lon: lon,
          mag: mag,
          place: props['place']?.toString() ?? 'Sismo detectado',
          timeUtc: timeMs != null
              ? DateTime.fromMillisecondsSinceEpoch(timeMs, isUtc: true)
              : DateTime.now().toUtc(),
          tsunamiAlert: props['tsunami'] == 1,
          alertLevel: props['alert']?.toString() ?? 'green',
        ));
      }
      return out;
    } catch (e) {
      AppLogger.warn('USGS directo no disponible.', tag: 'EW', error: e);
      return const [];
    }
  }

  // ── ANÁLISIS + GEOcerca + SIRENA ──

  /// Ciclo completo de monitoreo. Devuelve la alerta disparada (si hubo) para
  /// monitoreo/pruebas. No lanza excepciones.
  static Future<AegisQuakeAlert?> pollNow() async {
    try {
      if (!await isEnabled()) return null;

      final quakes = await fetchQuakes();
      if (quakes.isEmpty) return null;

      // Posición del operador: la telemetría compartida o una fijación puntual.
      final snapshot = await _freshPosition();
      if (snapshot == null) {
        debugPrint('⚠️ [EW] Sin fix GPS: geocerca sismica omitida.');
        return null;
      }

      final radius = await radiusKm();
      final minMagVal = await minMag();

      AegisQuakeAlert? best;
      for (final q in quakes) {
        final double km = GpsService.calculateDistanceInKm(
          snapshot.lat, snapshot.lon, q.lat, q.lon,
        );
        final mag = q.mag ?? 0;
        if (!withinFence(distanceKm: km, radiusKm: radius, mag: mag, minMag: minMagVal)) {
          continue;
        }
        final nivel = classifyThreat(mag, km);
        if (nivel == 'INFO') continue;

        final arrivals = computeArrivals(km);
        final alert = AegisQuakeAlert(
          event: q,
          distanceKm: km,
          nivel: nivel,
          pArrivalS: arrivals.pArrivalS,
          sArrivalS: arrivals.sArrivalS,
        );
        // Prioriza por nivel (y por cercanía en empate).
        if (best == null ||
            _priority(alert.nivel) > _priority(best.nivel) ||
            (_priority(alert.nivel) == _priority(best.nivel) &&
                alert.distanceKm < best.distanceKm)) {
          best = alert;
        }
      }

      if (best == null) return null;
      await _fireAlert(best);
      return best;
    } catch (e) {
      AppLogger.warn('Ciclo de alerta temprana fallido.', tag: 'EW', error: e);
      return null;
    }
  }

  static Future<TacticalSnapshot?> _freshPosition() async {
    final cached = GpsService.lastSnapshot;
    if (cached != null &&
        DateTime.now().toUtc().difference(cached.timestampUtc).inSeconds <= 120) {
      return cached;
    }
    try {
      await GpsService.getCurrentPosition();
    } catch (e) {
      // Sin fix puntual: se conserva lo que haya.
    }
    return GpsService.lastSnapshot;
  }

  /// Deduplicación por id de evento persistido (top N acotado).
  static Future<bool> _markSeen(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getStringList(_seenIdsKey) ?? [];
    if (seen.contains(id)) return false;
    seen.add(id);
    if (seen.length > 100) seen.removeRange(0, seen.length - 100);
    await prefs.setStringList(_seenIdsKey, seen);
    return true;
  }

  /// Dispara la sirena intrusiva LOCAL por nivel/escala y registra el evento.
  static Future<void> _fireAlert(AegisQuakeAlert alert) async {
    final bool isNew = await _markSeen('${alert.event.id}|${alert.nivel}');
    if (!isNew) return;

    final q = alert.event;
    final String tsunami = q.tsunamiAlert ? ' ⚠️ ALERTA DE TSUNAMI POSIBLE.' : '';
    final String body =
        'SISMO M${q.mag?.toStringAsFixed(1) ?? 'N/D'} · ${alert.distanceKm.round()} km '
        'de tu posición.\nEpicentro: ${q.place}.\n'
        'Ondas P (temblor leve) en ~${alert.pArrivalS} s · '
        'Ondas S (sacudida fuerte) en ~${alert.sArrivalS} s.$tsunami';

    await NotificationService.showAlertNotification(
      title: '🌋 ALERTA TEMPRANA DE SISMO [${alert.nivel}]',
      body: body,
      level: alert.nivel,
      deduplicationKey: 'aegis|ew|${alert.event.id}',
    );

    // Sirena intrusiva local sin servidor: duración según la escala.
    final int sirenMs = switch (alert.nivel) {
      'CRÍTICA' => 8000,
      'ALTA' => 5000,
      _ => 3000,
    };
    _soundLocalSiren(milliseconds: sirenMs);
    unawaited(VoiceService.speakAlert(
      title: 'Alerta temprana de sismo',
      body: 'Magnitud ${q.mag?.toStringAsFixed(1) ?? 'desconocida'}. '
          'Sacudida fuerte estimada en ${alert.sArrivalS} segundos.',
      level: alert.nivel,
    ));

    lastAlert.value = alert;
    await LocalDbService.logEmergencyEvent('ALERTA_TEMPRANA_SISMO', data: {
      'mag': q.mag,
      'distance_km': alert.distanceKm,
      'nivel': alert.nivel,
      'p_arrival_s': alert.pArrivalS,
      's_arrival_s': alert.sArrivalS,
      'place': q.place,
      'tsunami': q.tsunamiAlert,
      'source': q.id,
    });
    AppLogger.info('🌋 Alerta temprana [${alert.nivel}] a ${alert.distanceKm.round()} km.', tag: 'EW');
  }

  /// Sonido de alarma local acotado (se auto-detiene). Best-effort: si el
  /// dispositivo no expone tono de alarma, la vibración de la notificación basta.
  static void _soundLocalSiren({int milliseconds = 5000}) {
    try {
      final player = FlutterRingtonePlayer();
      player.playAlarm(asAlarm: true, looping: true, volume: 1.0);
      Timer(Duration(milliseconds: milliseconds), player.stop);
    } catch (e) {
      AppLogger.warn('Sirena local no disponible.', tag: 'EW', error: e);
    }
  }

  // ── CICLO DE MONITOREO ──

  /// Arranca el monitoreo periódico de alerta temprana (best-effort). El primer
  /// ciclo se ejecuta pasado un corto retardo para dejar asentarse el GPS.
  static Future<void> startMonitoring() async {
    _monitorTimer?.cancel();
    _monitorTimer = null;
    if (!await isEnabled()) {
      debugPrint('🌋 Alerta temprana desactivada; monitoreo no iniciado.');
      return;
    }
    final mins = await pollMinutes();
    final interval = mins <= 0 ? 10 : mins;
    _monitorTimer = Timer.periodic(Duration(minutes: interval), (_) {
      unawaited(pollNow());
    });
    Timer(const Duration(seconds: 3), () => unawaited(pollNow()));
    debugPrint('🌋 Monitoreo de alerta temprana sismica iniciado (c/$interval min).');
  }

  static void stopMonitoring() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
  }
}