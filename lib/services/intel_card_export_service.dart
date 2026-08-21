import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Lógica de exportación de la ficha infográfica COBALTO:
/// renderizado a PNG, persistencia en almacenamiento público/temporal y
/// compartición por intents nativos y enlaces sociales.
class IntelCardExportService {
  /// Renderiza el [RepaintBoundary] indicado a bytes PNG (HD).
  /// Devuelve null si el canvas no está disponible o falla la conversión.
  static Future<Uint8List?> renderPng(
    GlobalKey repaintKey, {
    double pixelRatio = 2.0,
  }) async {
    final boundary =
        repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;

    final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
    final ByteData? byteData =
        await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return null;
    return byteData.buffer.asUint8List();
  }

  /// Guarda los bytes en la carpeta pública de Descargas / Fotos (Android)
  /// o en Downloads del sistema. Devuelve la ruta guardada o null si falla.
  static Future<String?> saveToPublicDirectory(
      Uint8List bytes, String filename) async {
    try {
      Directory? targetDir;
      if (Platform.isAndroid) {
        final downloadsDir = Directory('/storage/emulated/0/Download');
        if (await downloadsDir.exists()) {
          targetDir = downloadsDir;
        } else {
          final picturesDir = Directory('/storage/emulated/0/Pictures');
          if (await picturesDir.exists()) {
            targetDir = picturesDir;
          } else {
            targetDir =
                await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
          }
        }
      } else {
        targetDir =
            await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      }

      final File savedFile = File('${targetDir.path}/$filename');
      await savedFile.writeAsBytes(bytes);
      return savedFile.path;
    } catch (e) {
      debugPrint('⚠️ Error al guardar en carpeta pública: $e');
      return null;
    }
  }

  /// Guarda los bytes en el directorio temporal de la app.
  static Future<String> saveToTempDirectory(Uint8List bytes, String filename) async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$filename');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  /// Abre el menú nativo de compartición para el archivo PNG.
  static Future<void> sharePngFile(String filePath, String title, String link) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(filePath, mimeType: 'image/png', name: 'cobalto_intel_report.png')],
        text: buildCaption(title, link),
        subject: title,
      ),
    );
  }

  /// Construye la leyenda táctica estándar de la ficha.
  static String buildCaption(String title, String link) {
    return link.isNotEmpty
        ? '🚨 [COBALTO OSINT] - $title\n\n🔗 Fuente original:\n$link'
        : '🚨 [COBALTO OSINT] - $title';
  }

  /// URI de compartición en Telegram.
  static Uri telegramShareUri(String link, String title) {
    final caption = buildCaption(title, link);
    return Uri.parse(
        'https://t.me/share/url?url=${Uri.encodeComponent(link)}&text=${Uri.encodeComponent(caption)}');
  }

  /// URI de compartición en WhatsApp.
  static Uri whatsappShareUri(String link, String title) {
    final caption = buildCaption(title, link);
    return Uri.parse('https://wa.me/?text=${Uri.encodeComponent(caption)}');
  }
}
