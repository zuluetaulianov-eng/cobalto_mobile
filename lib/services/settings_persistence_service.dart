import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import 'cobalto_api_service.dart';
import 'local_extractor_service.dart';

/// Persistencia y carga de los ajustes tácticos de la app (enlace, palabras
/// clave, fuentes, Ollama, parámetros y caché).
class SettingsPersistenceService {
  /// Carga palabras clave y fuentes locales, y prueba la conexión con la base.
  static Future<({List<String> keywords, List<Map<String, String>> sources, bool? connected})>
      loadSettings() async {
    final kw = await LocalExtractorService.getLocalKeywords();
    final src = await LocalExtractorService.getActiveSources();
    final isOk = await CobaltoApiService.testConnection();
    return (
      keywords: List<String>.from(kw),
      sources: List<Map<String, String>>.from(src),
      connected: isOk,
    );
  }

  static Future<void> saveKeywords(List<String> keywords) async {
    await LocalExtractorService.saveLocalKeywords(keywords);
  }

  static Future<void> addSource(String name, String url) async {
    await LocalExtractorService.addCustomSource(name, url);
  }

  static Future<void> removeSource(String url) async {
    await LocalExtractorService.removeCustomSource(url);
  }

  /// Guarda URL/credenciales, configuración Ollama y, si hay conexión,
  /// sincroniza el payload de sistema con la Base PC.
  static Future<bool> saveAll({
    required String url,
    required String user,
    required String pass,
    required String ollamaHost,
    required String ollamaModel,
    required List<String> keywords,
    required int maxAgeHours,
    required int defconLevel,
  }) async {
    await ApiConfig.saveConfig(url, user, pass);
    await ApiConfig.saveOllamaConfig(ollamaHost, ollamaModel);
    await saveKeywords(keywords);

    final isOk = await CobaltoApiService.testConnection();
    if (isOk) {
      await CobaltoApiService.saveSystemConfig({
        'KEYWORDS': keywords,
        'ENTRY_MAX_AGE_HOURS': maxAgeHours,
        'DEFCON_LEVEL': defconLevel,
      });
    }
    return isOk;
  }

  static Future<void> clearSitrepCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cached_sitrep_news');
  }
}