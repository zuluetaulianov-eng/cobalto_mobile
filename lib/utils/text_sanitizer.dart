/// Utilidad de limpieza de texto de COBALTO Mobile.
/// Purga etiquetas HTML, entidades XML/HTML, códigos de escape Unicode y
/// artefactos de JSON para garantizar una lectura limpia y legible en la UI.
class TextSanitizer {
  static String clean(String? rawInput) {
    if (rawInput == null || rawInput.isEmpty) return '';

    String text = rawInput.trim();

    // 1. Si el string contiene JSON embebido, intentar extraer el mensaje limpio
    if (text.startsWith('{') && text.contains('":')) {
      final titleMatch = RegExp(r'"(?:title|text|summary|message|headline)"\s*:\s*"([^"]+)"').firstMatch(text);
      if (titleMatch != null && titleMatch.group(1) != null) {
        text = titleMatch.group(1)!;
      }
    }

    // 2. Reemplazar entidades HTML habituales
    text = text
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&#8211;', '-')
        .replaceAll('&#8212;', '—')
        .replaceAll('&#8220;', '"')
        .replaceAll('&#8221;', '"')
        .replaceAll('&#8216;', "'")
        .replaceAll('&#8217;', "'");

    // 3. Reemplazar entidades numéricas decimales &#123;
    text = text.replaceAllMapped(RegExp(r'&#(\d+);'), (match) {
      final code = int.tryParse(match.group(1) ?? '');
      if (code != null && code > 0) return String.fromCharCode(code);
      return '';
    });

    // 4. Reemplazar entidades numéricas hex &#x1F600;
    text = text.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (match) {
      final code = int.tryParse(match.group(1) ?? '', radix: 16);
      if (code != null && code > 0) return String.fromCharCode(code);
      return '';
    });

    // 5. Reemplazar secuencias de escape de unicode raw ej. \u00e1
    text = text.replaceAllMapped(RegExp(r'\\u([0-9a-fA-F]{4})'), (match) {
      final code = int.tryParse(match.group(1) ?? '', radix: 16);
      if (code != null && code > 0) return String.fromCharCode(code);
      return match.group(0) ?? '';
    });

    // 6. Eliminar cualquier etiqueta HTML (<p>, <br/>, <div>, <a ...>, <span>, etc.)
    text = text.replaceAll(RegExp(r'<[^>]*>'), ' ');

    // 7. Limpiar escapes de barra invertida
    text = text
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\t', ' ')
        .replaceAll(r'\"', '"')
        .replaceAll(r"\'", "'");

    // 8. Normalizar espacios en blanco repetidos
    text = text.replaceAll(RegExp(r'[ \t]+'), ' ');
    text = text.replaceAll(RegExp(r'\n\s*\n'), '\n');

    return text.trim();
  }
}
