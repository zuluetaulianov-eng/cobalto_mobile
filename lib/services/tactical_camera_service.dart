import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'app_logger.dart';
import 'gps_service.dart';
import 'local_db_service.dart';
import 'telemetry_sync_service.dart';

class TacticalCameraService {
  static List<CameraDescription> _cameras = [];
  static CameraController? _controller;
  static bool _isInitializing = false;

  static CameraController? get controller => _controller;

  /// Inicializa la cámara del dispositivo
  static Future<bool> initCamera() async {
    if (_controller != null && _controller!.value.isInitialized) return true;
    if (_isInitializing) return false;

    _isInitializing = true;
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        debugPrint('⚠️ No se encontraron sensores de cámara.');
        _isInitializing = false;
        return false;
      }

      final firstCamera = _cameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );

      _controller = CameraController(
        firstCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _controller!.initialize();
      _isInitializing = false;
      return true;
    } catch (e) {
      debugPrint('⚠️ Error inicializando sensor de cámara: $e');
      _isInitializing = false;
      return false;
    }
  }

  /// Alterna el flash de la cámara (si el sensor lo soporta).
  static Future<void> toggleFlash() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final next = c.value.flashMode == FlashMode.off ? FlashMode.always : FlashMode.off;
    await c.setFlashMode(next);
  }

  /// Cicla la cámara entre sensores disponibles (trasera <-> delantera).
  static Future<CameraDescription?> switchCamera() async {
    if (_cameras.isEmpty) return null;
    if (_cameras.length < 2) return _cameras.first;

    final c = _controller;
    if (c == null) return null;
    final int currentIndex = _cameras.indexWhere((cam) => cam.lensDirection == c.description.lensDirection);
    final nextIndex = (currentIndex + 1) % _cameras.length;
    final next = _cameras[nextIndex];

    await c.dispose();
    _controller = CameraController(
      next,
      ResolutionPreset.high,
      enableAudio: false,
    );
    await _controller!.initialize();
    return next;
  }

  /// Liberar recursos de la cámara
  static Future<void> disposeCamera() async {
    if (_controller != null) {
      await _controller!.dispose();
      _controller = null;
    }
  }

  /// Enciende el flash fijo (linterna) como señal luminosa de localización.
  /// Best-effort: en algunos dispositivos requiere vista previa activa.
  static Future<bool> startTorch() async {
    final bool ok = await initCamera();
    if (!ok || _controller == null) return false;
    try {
      await _controller!.setFlashMode(FlashMode.always);
      return true;
    } catch (e) {
      debugPrint('⚠️ No se pudo activar la linterna: $e');
      return false;
    }
  }

  /// Apaga la linterna y libera el sensor.
  static Future<void> stopTorch() async {
    if (_controller != null && _controller!.value.isInitialized) {
      try {
        await _controller!.setFlashMode(FlashMode.off);
      } catch (e) {
        // Silencioso
      }
    }
    await disposeCamera();
  }

  /// Captura una fotografía y le estampa la telemetría GPS, UTC y Clasificación
  /// en un Isolate secundario. Genera además un sidecar forense (JSON con SHA-256,
  /// coordenadas, altitud, precisión, rumbo y velocidad) y registra el disparo
  /// como Reporte de Campo (FieldReport) local con intento de subida al nodo.
  ///
  /// Devuelve el mapa con la ruta de la imagen, el sidecar y el id del reporte,
  /// o `null` si la captura falla.
  static Future<Map<String, dynamic>?> captureTelemetryPhoto({
    double? lat,
    double? lon,
    TacticalSnapshot? telemetry,
    String classification = 'CONFIDENCIAL // COBALTO C4I',
  }) async {
    // Telemetría preferida: snapshot del stream; fallback a fix puntual.
    TacticalSnapshot? snapshot = telemetry ?? GpsService.lastSnapshot;
    if (snapshot == null) {
      final pos = await GpsService.getCurrentPosition();
      if (pos != null) snapshot = TacticalSnapshot.fromPosition(pos);
    }

    // Sin fix GPS: no estampar coordenadas falsas. El disparo puede continuar
    // con telemetría N/D en lugar de un fallback hardcodeado erróneo.
    final double latValue = snapshot?.lat ?? 0.0;
    final double lonValue = snapshot?.lon ?? 0.0;
    final bool hasFix = snapshot != null && (latValue != 0.0 || lonValue != 0.0);

    bool isReady = await initCamera();
    if (!isReady || _controller == null) return null;

    try {
      final XFile photoFile = await _controller!.takePicture();
      final bytes = await photoFile.readAsBytes();
      final String nowUtc =
          DateTime.now().toUtc().toIso8601String().replaceAll('T', ' ').substring(0, 19);

      // Procesamiento asíncrono en Isolate secundario mediante compute()
      final processedBytes = await compute(
        _processTelemetryPhotoIsolate,
        _TelemetryParams(
          bytes: bytes,
          lat: hasFix ? latValue : 0.0,
          lon: hasFix ? lonValue : 0.0,
          hasFix: hasFix,
          altitudeM: snapshot?.altitudeM,
          speedMps: snapshot?.speedMps,
          headingDeg: snapshot?.headingDeg,
          classification: classification,
          nowUtc: nowUtc,
        ),
      );

      if (processedBytes == null) return photoFile.path.isEmpty ? null : {'imagePath': photoFile.path};

      // ── Hash forense de la evidencia final (SHA-256) ──
      final String sha256Hex = sha256.convert(processedBytes).toString();

      final Directory dir = await getApplicationDocumentsDirectory();
      final String baseName = 'telemetry_${DateTime.now().millisecondsSinceEpoch}';
      final String imagePath = '${dir.path}/$baseName.jpg';
      final String sidecarPath = '${dir.path}/$baseName.json';

      final File savedFile = File(imagePath);
      await savedFile.writeAsBytes(processedBytes);

      // ── Sidecar forense JSON (cadena de custodia) ──
      final Map<String, dynamic> metadata = {
        'sha256': sha256Hex,
        'utc_zulu': nowUtc,
        'utc_ms': DateTime.now().toUtc().millisecondsSinceEpoch,
        'coordinates_valid': hasFix,
        'lat': hasFix ? latValue : null,
        'lon': hasFix ? lonValue : null,
        'altitude_m': snapshot?.altitudeM,
        'heading_deg': snapshot?.headingDeg,
        'speed_mps': snapshot?.speedMps,
        'accuracy_m': snapshot?.accuracyM,
        'classification': classification,
        'node': 'COBALTO-MOBILE-HUB',
        'image': '$baseName.jpg',
      };
      await File(sidecarPath).writeAsString(json.encode(metadata));

      // ── Registro del disparo como Reporte de Campo local ──
      final String reportId = 'taccam_${DateTime.now().millisecondsSinceEpoch}';
      final Map<String, dynamic> report = {
        'id': reportId,
        'title': '📷 EVIDENCIA FOTOGRÁFICA CON TELEMETRÍA',
        'description': hasFix
            ? 'Captura táctica con geotagging real [LAT ${latValue.toStringAsFixed(5)}, LON ${lonValue.toStringAsFixed(5)}] UTC ${nowUtc}Z - SHA256 ${sha256Hex.substring(0, 12)}...'
            : 'Captura táctica SIN FIJACIÓN GPS (telemetría no disponible) - SHA256 ${sha256Hex.substring(0, 12)}...',
        'threat_level': 'ELEVATED',
        'lat': hasFix ? latValue : 0.0,
        'lng': hasFix ? lonValue : 0.0,
        'image_path': imagePath,
        'timestamp': DateTime.now().toIso8601String(),
        'synced': false,
      };
      await LocalDbService.saveFieldReport(report);

      // ── Intento de subida inmediata; si es offline queda en cola ──
      await TelemetrySyncService.enqueueAndUpload(
        report: report,
        imagePath: imagePath,
        sidecarPath: sidecarPath,
      );

      debugPrint('📷 Fotografía de Telemetría guardada en Isolate: $imagePath');
      return {
        'imagePath': imagePath,
        'sidecarPath': sidecarPath,
        'reportId': reportId,
        'sha256': sha256Hex,
      };
    } catch (e) {
      AppLogger.warn('Error procesando estampado de telemetría.', tag: 'TacCam', error: e);
      return null;
    }
  }
}

class _TelemetryParams {
  final Uint8List bytes;
  final double lat;
  final double lon;
  final bool hasFix;
  final double? altitudeM;
  final double? speedMps;
  final double? headingDeg;
  final String classification;
  final String nowUtc;

  _TelemetryParams({
    required this.bytes,
    required this.lat,
    required this.lon,
    required this.hasFix,
    required this.altitudeM,
    required this.speedMps,
    required this.headingDeg,
    required this.classification,
    required this.nowUtc,
  });
}

Uint8List? _processTelemetryPhotoIsolate(_TelemetryParams params) {
  final img.Image? decodedImage = img.decodeImage(params.bytes);
  if (decodedImage == null) return null;

  final int width = decodedImage.width;
  final int height = decodedImage.height;
  final int bannerHeight = (height * 0.12).toInt().clamp(90, 220);

  final img.Image canvas = img.Image(width: width, height: height + bannerHeight);
  img.compositeImage(canvas, decodedImage, dstX: 0, dstY: 0);

  img.fillRect(
    canvas,
    x1: 0,
    y1: height,
    x2: width,
    y2: height + bannerHeight,
    color: img.ColorRgb8(10, 11, 16),
  );

  img.drawLine(
    canvas,
    x1: 0,
    y1: height,
    x2: width,
    y2: height,
    color: img.ColorRgb8(0, 229, 255),
    thickness: 4,
  );

  final String coordsLine = params.hasFix
      ? 'LAT: ${params.lat.toStringAsFixed(5)}  LON: ${params.lon.toStringAsFixed(5)}'
      : 'TELEMETRIA GPS: SIN FIJACION (NO DISPONIBLE)';

  final String telemetryLine1 = '$coordsLine | UTC: ${params.nowUtc} ZULU';
  final String telemetryLine2 = _buildMotionLine(params);
  final String telemetryLine3 = 'CLASIFICACION: ${params.classification} | NODO: COBALTO-MOBILE-HUB';

  img.drawString(
    canvas,
    telemetryLine1,
    font: img.arial24,
    x: 20,
    y: height + 12,
    color: params.hasFix ? img.ColorRgb8(0, 255, 170) : img.ColorRgb8(255, 45, 85),
  );

  if (telemetryLine2.isNotEmpty) {
    img.drawString(
      canvas,
      telemetryLine2,
      font: img.arial14,
      x: 20,
      y: height + (bannerHeight ~/ 2) - 8,
      color: img.ColorRgb8(0, 229, 255),
    );
  }

  img.drawString(
    canvas,
    telemetryLine3,
    font: img.arial14,
    x: 20,
    y: height + bannerHeight - 30,
    color: img.ColorRgb8(255, 255, 255),
  );

  return Uint8List.fromList(img.encodeJpg(canvas, quality: 85));
}

String _buildMotionLine(_TelemetryParams params) {
  final parts = <String>[];
  if (params.altitudeM != null) parts.add('ALT: ${params.altitudeM!.round()} m');
  if (params.speedMps != null) parts.add('VEL: ${(params.speedMps! * 1.943844).toStringAsFixed(1)} KT');
  if (params.headingDeg != null) parts.add('RUMBO: ${params.headingDeg!.round()}°');
  return parts.join(' | ');
}