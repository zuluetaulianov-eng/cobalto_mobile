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

  /// Captura una fotografía y le estampa la telemetría GPS, UTC y Clasificación
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

      final img.Image? decodedImage = img.decodeImage(bytes);
      if (decodedImage == null) return photoFile.path;

      // Crear lienzo con banner de telemetría inferior
      final int width = decodedImage.width;
      final int height = decodedImage.height;
      final int bannerHeight = (height * 0.12).toInt().clamp(80, 200);

      final img.Image canvas = img.Image(width: width, height: height + bannerHeight);
      img.compositeImage(canvas, decodedImage, dstX: 0, dstY: 0);

      // Fondo negro de la barra de telemetría
      img.fillRect(
        canvas,
        x1: 0,
        y1: height,
        x2: width,
        y2: height + bannerHeight,
        color: img.ColorRgb8(10, 11, 16),
      );

      // Línea divisoria cian
      img.drawLine(
        canvas,
        x1: 0,
        y1: height,
        x2: width,
        y2: height,
        color: img.ColorRgb8(0, 229, 255),
        thickness: 4,
      );

      final String nowUtc = DateTime.now().toUtc().toIso8601String().replaceAll('T', ' ').substring(0, 19);
      final String telemetryLine1 = 'LAT: ${lat.toStringAsFixed(5)}  LON: ${lon.toStringAsFixed(5)} | UTC: $nowUtc ZULU';
      final String telemetryLine2 = 'CLASIFICACION: $classification | NODO: COBALTO-MOBILE-HUB';

      // Dibujar texto con fuente incorporada
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

      final encodedJpg = img.encodeJpg(canvas, quality: 90);
      final Directory dir = await getApplicationDocumentsDirectory();
      final String fileName = 'telemetry_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final File savedFile = File('${dir.path}/$fileName');
      await savedFile.writeAsBytes(encodedJpg);

      debugPrint('📷 Fotografía de Telemetría guardada en: ${savedFile.path}');
      return savedFile.path;
    } catch (e) {
      debugPrint('⚠️ Error procesando estampado de telemetría: $e');
      return null;
    }
  }
}
