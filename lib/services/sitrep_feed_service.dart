import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'cobalto_api_service.dart';
import 'local_extractor_service.dart';
import 'local_db_service.dart';
import '../utils/text_sanitizer.dart';

/// Lógica del feed SitRep: obtención combinada (servidor + SQLite + extracción
/// local con deduplicación) y filtrado por relevancia/búsqueda.
class SitrepFeedService {
  static const String _cacheKey = 'cached_sitrep_news';

  /// Carga solo las noticias cacheadas en SQLite local (para arranque inmediato).
  static Future<List<Map<String, dynamic>>> loadCachedLocalEntries() async {
    return LocalDbService.getEntries();
  }

  /// Carga y combina las noticias de servidor, SQLite local y, si no hay nada,
  /// extracción directa en el dispositivo. Persiste el resultado en prefs.
  static Future<List<Map<String, dynamic>>> loadCombinedFeed() async {
    final localEntries = await LocalDbService.getEntries();
    final remoteNews = await CobaltoApiService.fetchNews();

    final combined = <Map<String, dynamic>>[];
    final seenTitles = <String>{};

    // Noticias del servidor primero (si existen)
    if (remoteNews.isNotEmpty) {
      final castedRemote = List<Map<String, dynamic>>.from(remoteNews);
      for (final item in castedRemote) {
        final cleanItem = Map<String, dynamic>.from(item);
        cleanItem['title'] = TextSanitizer.clean(item['title']?.toString());
        cleanItem['summary'] = TextSanitizer.clean((item['summary'] ?? item['text'])?.toString());
        final title = cleanItem['title']?.toString() ?? '';
        if (title.isNotEmpty && !seenTitles.contains(title)) {
          seenTitles.add(title);
          combined.add(cleanItem);
        }
      }
      // Guardar noticias remotas en la BD local SQLite para modo offline
      await LocalDbService.insertEntries(combined);
    }

    // Noticias locales de SQLite que no estén duplicadas
    for (final item in localEntries) {
      final cleanItem = Map<String, dynamic>.from(item);
      cleanItem['title'] = TextSanitizer.clean(item['title']?.toString());
      cleanItem['summary'] = TextSanitizer.clean((item['summary'] ?? item['text'])?.toString());
      final title = cleanItem['title']?.toString() ?? '';
      if (title.isNotEmpty && !seenTitles.contains(title)) {
        seenTitles.add(title);
        combined.add(cleanItem);
      }
    }

    // Si todo sigue vacío, intentar extracción directa local en el teléfono
    if (combined.isEmpty) {
      final localExtracted = await LocalExtractorService.extractDirectlyOnDevice();
      for (final item in localExtracted) {
        final title = item['title']?.toString() ?? '';
        if (title.isNotEmpty && !seenTitles.contains(title)) {
          seenTitles.add(title);
          combined.add(item);
        }
      }
    }

    // Respaldar caché en SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, json.encode(combined));

    return combined;
  }

  /// Filtra las entradas por título/resumen/fuente según la consulta.
  static List<Map<String, dynamic>> filterNews(
      List<dynamic> news, String searchQuery) {
    if (searchQuery.isEmpty) {
      return List<Map<String, dynamic>>.from(news);
    }
    final q = searchQuery.toLowerCase();
    final result = <Map<String, dynamic>>[];
    for (final item in news) {
      if (item is! Map) continue;
      final title = (item['title'] ?? '').toString().toLowerCase();
      final summary = (item['summary'] ?? '').toString().toLowerCase();
      final source = (item['source'] ?? '').toString().toLowerCase();
      if (title.contains(q) || summary.contains(q) || source.contains(q)) {
        result.add(Map<String, dynamic>.from(item));
      }
    }
    return result;
  }
}