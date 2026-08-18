import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Snapshot de telemetría GPS táctica del operador en un instante dado.
class TacticalSnapshot {
  final double lat;
  final double lon;

  /// Altitud en metros (MSL).
  final double? altitudeM;

  /// Rumbo/azimut en grados (0=N, 90=E).
  final double? headingDeg;

  /// Velocidad del desplazamiento en metros/segundo.
  final double? speedMps;

  /// Precisión horizontal del fix en metros.
  final double? accuracyM;

  /// Precisión de la velocidad en m/s.
  final double? speedAccuracyMps;

  /// Marca de tiempo UTC del fix.
  final DateTime timestampUtc;

  const TacticalSnapshot({
    required this.lat,
    required this.lon,
    this.altitudeM,
    this.headingDeg,
    this.speedMps,
    this.accuracyM,
    this.speedAccuracyMps,
    required this.timestampUtc,
  });

  factory TacticalSnapshot.fromPosition(Position p) => TacticalSnapshot(
        lat: p.latitude,
        lon: p.longitude,
        altitudeM: p.altitude,
        headingDeg: p.heading,
        speedMps: p.speed,
        accuracyM: p.accuracy,
        speedAccuracyMps: p.speedAccuracy,
        timestampUtc: p.timestamp,
      );

  String get speedKtsLabel {
    if (speedMps == null) return 'N/D';
    return '${(speedMps! * 1.943844).toStringAsFixed(1)} KT';
  }

  String get headingLabel {
    if (headingDeg == null) return 'N/D';
    final List<String> cardinals = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final int index = ((headingDeg! + 22.5) % 360 ~/ 45).toInt();
    return '${headingDeg!.round()}° ${cardinals[index]}';
  }
}

/// Sensor GPS táctico: verificación de permisos, posición puntual y
/// seguimiento de telemetría continua (stream) compartido por toda la app
/// a través del [ValueNotifier] [telemetry].
class GpsService {
  static Position? _lastKnownPosition;

  static bool _tracking = false;
  static StreamSubscription<Position>? _streamSub;

  /// Última posición conocida obtenida (snapshot previo).
  static Position? get lastKnownPosition => _lastKnownPosition;

  /// Última fijación de telemetría completa (stream o puntual).
  static TacticalSnapshot? get lastSnapshot => telemetry.value;

  /// Estado del seguimiento continuo GPS.
  static bool get isTracking => _tracking;

  /// Telemetría en vivo: escúchalo con ValueListenableBuilder para actualizar
  /// mapas, HUD de cámara, geocercas y el interruptor de hombre muerto.
  static final ValueNotifier<TacticalSnapshot?> telemetry =
      ValueNotifier<TacticalSnapshot?>(null);

  /// Verifica permisos de GPS y obtiene la posición actual del operador.
  /// Actualiza la telemetría compartida si el fix es válido.
  static Future<Position?> getCurrentPosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('⚠️ Servicio de ubicación GPS desactivado.');
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('⚠️ Permiso de ubicación GPS denegado.');
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('⚠️ Permiso de ubicación denegado permanentemente.');
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      _lastKnownPosition = position;
      telemetry.value = TacticalSnapshot.fromPosition(position);
      return position;
    } catch (e) {
      debugPrint('⚠️ Error obteniendo posición GPS: $e');
      return null;
    }
  }

  /// Inicia el seguimiento continuo de telemetría táctico.
  /// El stream usa [distanceFilter] para ahorrar batería (un fix nuevo solo
  /// cuando el operador se mueve más de 5 metros o pasa el intervalo).
  static Future<bool> startTracking() async {
    if (_tracking) return true;

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return false;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission != LocationPermission.whileInUse &&
            permission != LocationPermission.always) {
          debugPrint('⚠️ Sin permiso GPS para seguimiento continuo.');
          return false;
        }
      }
      if (permission == LocationPermission.deniedForever) return false;

      // Fix inmediato inicial.
      final initial = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      _lastKnownPosition = initial;
      telemetry.value = TacticalSnapshot.fromPosition(initial);

      _streamSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen(
        (position) {
          _lastKnownPosition = position;
          telemetry.value = TacticalSnapshot.fromPosition(position);
        },
        onError: (Object e) =>
            debugPrint('⚠️ Error en stream de telemetría GPS: $e'),
      );

      _tracking = true;
      debugPrint('🛰️ Seguimiento de telemetría GPS iniciado.');
      return true;
    } catch (e) {
      debugPrint('⚠️ Error iniciando seguimiento GPS: $e');
      return false;
    }
  }

  /// Detiene el seguimiento continuo de telemetría.
  static Future<void> stopTracking() async {
    await _streamSub?.cancel();
    _streamSub = null;
    _tracking = false;
    debugPrint('🛰️ Seguimiento de telemetría GPS detenido.');
  }

  /// Calcula la distancia en kilómetros entre dos coordenadas.
  static double calculateDistanceInKm(
      double lat1, double lon1, double lat2, double lon2) {
    double distanceInMeters = Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
    return distanceInMeters / 1000.0;
  }
}