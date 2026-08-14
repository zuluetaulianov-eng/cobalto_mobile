import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'notification_service.dart';

class GpsService {
  static Position? _lastKnownPosition;

  /// Obtiene la última posición conocida del operador
  static Position? get lastKnownPosition => _lastKnownPosition;

  /// Verifica permisos de GPS y obtiene la posición actual del operador
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
      return position;
    } catch (e) {
      debugPrint('⚠️ Error obteniendo posición GPS: $e');
      return null;
    }
  }

  /// Calcula la distancia en kilómetros entre dos coordenadas
  static double calculateDistanceInKm(
      double lat1, double lon1, double lat2, double lon2) {
    double distanceInMeters = Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
    return distanceInMeters / 1000.0;
  }

  /// Evalúa una geocerca de proximidad para un evento táctico
  static Future<void> evaluateGeofenceAlert({
    required double eventLat,
    required double eventLon,
    required String title,
    required String level,
    double radiusKm = 5.0,
  }) async {
    final operatorPos = await getCurrentPosition();
    if (operatorPos == null) return;

    final distanceKm = calculateDistanceInKm(
      operatorPos.latitude,
      operatorPos.longitude,
      eventLat,
      eventLon,
    );

    if (distanceKm <= radiusKm) {
      final String alertTitle = '🚨 PROXIMIDAD DE SEGURIDAD (${distanceKm.toStringAsFixed(1)} KM)';
      final String alertBody = '[$level] "$title" detectado cerca de su posición de campo.';

      await NotificationService.showAlertNotification(
        title: alertTitle,
        body: alertBody,
        level: level,
        deduplicationKey: 'geofence|$eventLat|$eventLon|$title',
        showFloatingOverlay: true,
      );
    }
  }
}
