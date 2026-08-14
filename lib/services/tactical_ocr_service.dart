import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Servicio de Reconocimiento Óptico de Caracteres (OCR Táctico) 100% Offline.
/// Extrae automáticamente texto, números de serie, placas o coordenadas de fotos de campo.
class TacticalOcrService {
  static final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  /// Procesa una imagen guardada localmente y extrae bloques de texto
  static Future<TacticalOcrResult> processImage(String imagePath) async {
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);

      List<String> detectedLines = [];
      List<String> potentialCoordinates = [];
      List<String> potentialPlatesOrCodes = [];

      for (TextBlock block in recognizedText.blocks) {
        for (TextLine line in block.lines) {
          final text = line.text.trim();
          if (text.isNotEmpty) {
            detectedLines.add(text);

            // Patrones tácticos (Ej. Coordenadas Lat/Lon o Códigos de Placa/Serial)
            if (RegExp(r'[-+]?\d{1,3}\.\d{4,}').hasMatch(text)) {
              potentialCoordinates.add(text);
            }
            if (RegExp(r'^[A-Z0-9]{5,12}$', caseSensitive: false).hasMatch(text.replaceAll(RegExp(r'\s+'), ''))) {
              potentialPlatesOrCodes.add(text);
            }
          }
        }
      }

      return TacticalOcrResult(
        fullText: recognizedText.text,
        lines: detectedLines,
        coordinates: potentialCoordinates,
        detectedCodes: potentialPlatesOrCodes,
        isSuccess: true,
      );
    } catch (e) {
      return TacticalOcrResult(
        fullText: '',
        lines: [],
        coordinates: [],
        detectedCodes: [],
        isSuccess: false,
        error: e.toString(),
      );
    }
  }

  /// Libera recursos del motor ML Kit
  static void dispose() {
    _textRecognizer.close();
  }
}

class TacticalOcrResult {
  final String fullText;
  final List<String> lines;
  final List<String> coordinates;
  final List<String> detectedCodes;
  final bool isSuccess;
  final String? error;

  TacticalOcrResult({
    required this.fullText,
    required this.lines,
    required this.coordinates,
    required this.detectedCodes,
    required this.isSuccess,
    this.error,
  });
}
