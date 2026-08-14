import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

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

  /// Liberar recursos de la cámara
  static Future<void> disposeCamera() async {
    if (_controller != null) {
      await _controller!.dispose();
      _controller = null;
    }
  }

  /// Captura una fotografía y le estampa la telemetría GPS, UTC y Clasificación en un Isolate secundario
  static Future<String?> captureTelemetryPhoto({
    required double lat,
    required double lon,
    String classification = 'CONFIDENCIAL // COBALTO C4I',
  }) async {
    bool isReady = await initCamera();
    if (!isReady || _controller == null) return null;

    try {
      final XFile photoFile = await _controller!.takePicture();
      final bytes = await photoFile.readAsBytes();
      final String nowUtc = DateTime.now().toUtc().toIso8601String().replaceAll('T', ' ').substring(0, 19);

      // Procesamiento asíncrono en Isolate secundario mediante compute()
      final processedBytes = await compute(
        _processTelemetryPhotoIsolate,
        _TelemetryParams(bytes: bytes, lat: lat, lon: lon, classification: classification, nowUtc: nowUtc),
      );

      if (processedBytes == null) return photoFile.path;

      final Directory dir = await getApplicationDocumentsDirectory();
      final String fileName = 'telemetry_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final File savedFile = File('${dir.path}/$fileName');
      await savedFile.writeAsBytes(processedBytes);

      debugPrint('📷 Fotografía de Telemetría guardada en Isolate: ${savedFile.path}');
      return savedFile.path;
    } catch (e) {
      debugPrint('⚠️ Error procesando estampado de telemetría: $e');
      return null;
    }
  }
}

class _TelemetryParams {
  final Uint8List bytes;
  final double lat;
  final double lon;
  final String classification;
  final String nowUtc;

  _TelemetryParams({
    required this.bytes,
    required this.lat,
    required this.lon,
    required this.classification,
    required this.nowUtc,
  });
}

Uint8List? _processTelemetryPhotoIsolate(_TelemetryParams params) {
  final img.Image? decodedImage = img.decodeImage(params.bytes);
  if (decodedImage == null) return null;

  final int width = decodedImage.width;
  final int height = decodedImage.height;
  final int bannerHeight = (height * 0.12).toInt().clamp(80, 200);

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

  final String telemetryLine1 = 'LAT: ${params.lat.toStringAsFixed(5)}  LON: ${params.lon.toStringAsFixed(5)} | UTC: ${params.nowUtc} ZULU';
  final String telemetryLine2 = 'CLASIFICACION: ${params.classification} | NODO: COBALTO-MOBILE-HUB';

  img.drawString(
    canvas,
    telemetryLine1,
    font: img.arial24,
    x: 20,
    y: height + 15,
    color: img.ColorRgb8(0, 255, 170),
  );

  img.drawString(
    canvas,
    telemetryLine2,
    font: img.arial14,
    x: 20,
    y: height + bannerHeight - 30,
    color: img.ColorRgb8(255, 255, 255),
  );

  return Uint8List.fromList(img.encodeJpg(canvas, quality: 85));
}
