import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_logger.dart';
import 'local_db_service.dart';

class LocalExtractorService {
  static const List<Map<String, String>> defaultRssSources = [
    // Internacional & Geopolítica
    {'name': 'BBC Mundo', 'url': 'https://feeds.bbci.co.uk/mundo/rss.xml'},
    {'name': 'El País América', 'url': 'https://feeds.elpais.com/mrss-s/pages/ep/site/elpais.com/section/america/portada'},
    {'name': 'EuropaPress Internacional', 'url': 'https://www.europapress.es/rss/rss.aspx?ch=00066'},
    {'name': 'Al Jazeera English', 'url': 'https://www.aljazeera.com/xml/rss/all.xml'},
    {'name': 'CNN en Español', 'url': 'https://rss.cnn.com/rss/edition_americas.rss'},
    {'name': 'The Guardian World', 'url': 'https://www.theguardian.com/world/rss'},
    {'name': 'France 24 LatAm', 'url': 'https://www.france24.com/es/am%C3%A9rica-latina/rss'},
    // Ciberseguridad & OSINT
    {'name': 'Security Affairs (Cyber)', 'url': 'https://securityaffairs.com/feed'},
    {'name': 'Defense News', 'url': 'https://www.defensenews.com/arc/outboundfeeds/rss/?outputType=xml'},
    {'name': 'Krebs on Security', 'url': 'https://krebsonsecurity.com/feed/'},
    {'name': 'Bellingcat OSINT', 'url': 'https://www.bellingcat.com/feed/'},
    {'name': 'Insight Crime', 'url': 'https://insightcrime.org/feed/'},
    {'name': 'Hacker News Cyber', 'url': 'https://hnrss.org/frontpage'},
    // Región & Fuentes Locales
    {'name': 'El Nacional', 'url': 'https://www.elnacional.com/feed/'},
    {'name': 'El Estímulo', 'url': 'https://elestimulo.com/feed/'},
    {'name': 'Runrun.es', 'url': 'https://runrun.es/feed/'},
    {'name': 'Efecto Cocuyo', 'url': 'https://efectococuyo.com/feed/'},
    {'name': 'La Patilla', 'url': 'https://www.lapatilla.com/feed/'},
    {'name': 'Banca y Negocios', 'url': 'https://www.bancaynegocios.com/feed/'},
    {'name': 'VenCERT Alertas', 'url': 'https://vencert.suscerte.gob.ve/category/alertas/feed/'},
    // Canales de Telegram Públicos
    {'name': 'Venevisión (Telegram)', 'url': 'https://t.me/s/noticierovenevision'},
    {'name': 'Noticias Caracol (Telegram)', 'url': 'https://t.me/s/NoticiasCaracol'},
  ];

  static Future<List<Map<String, String>>> getActiveSources() async {
    final prefs = await SharedPreferences.getInstance();
    final customStr = prefs.getString('local_custom_sources');
    List<Map<String, String>> sources = List.from(defaultRssSources);

    if (customStr != null && customStr.isNotEmpty) {
      try {
        final decoded = json.decode(customStr);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map && item.containsKey('name') && item.containsKey('url')) {
              sources.add({
                'name': item['name'].toString(),
                'url': item['url'].toString(),
              });
            }
          }
        }
      } catch (e) {
        AppLogger.warn('Fuentes personalizadas corruptas; se ignoran.', tag: 'Extractor', error: e);
      }
    }
    return sources;
  }

  static Future<void> addCustomSource(String name, String url) async {
    final prefs = await SharedPreferences.getInstance();
    final customStr = prefs.getString('local_custom_sources');
    List<dynamic> list = [];
    if (customStr != null && customStr.isNotEmpty) {
      try {
        list = json.decode(customStr);
      } catch (e) {
        AppLogger.warn('Fuentes personalizadas corruptas al añadir.', tag: 'Extractor', error: e);
      }
    }
    list.add({'name': name, 'url': url});
    await prefs.setString('local_custom_sources', json.encode(list));
  }

  static Future<void> removeCustomSource(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final customStr = prefs.getString('local_custom_sources');
    if (customStr != null && customStr.isNotEmpty) {
      try {
        List<dynamic> list = json.decode(customStr);
        list.removeWhere((item) => item['url'] == url);
        await prefs.setString('local_custom_sources', json.encode(list));
      } catch (e) {
        AppLogger.warn('Fuentes personalizadas corruptas al eliminar.', tag: 'Extractor', error: e);
      }
    }
  }

  static Future<List<String>> getLocalKeywords() async {
    final prefs = await SharedPreferences.getInstance();
    final kw = prefs.getStringList('local_keywords');
    if (kw != null && kw.isNotEmpty) return kw;
    return ['inteligencia', 'conflicto', 'seguridad', 'ciberataque', 'defensa', 'alerta', 'defcon', 'militar', 'sanciones', 'dolar', 'venezuela'];
  }

  static Future<void> saveLocalKeywords(List<String> keywords) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('local_keywords', keywords);
  }

  static Future<List<Map<String, dynamic>>> extractDirectlyOnDevice() async {
    final List<Map<String, dynamic>> extracted = [];
    final sources = await getActiveSources();
    final keywords = await getLocalKeywords();

    for (final src in sources) {
      try {
        final url = src['url']!;
        if (url.contains('t.me/s/')) {
          final tgItems = await _scrapeTelegramChannel(url, src['name']!, keywords);
          extracted.addAll(tgItems);
        } else {
          final response = await http.get(
            Uri.parse(url),
            headers: {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.0',
            },
          ).timeout(const Duration(seconds: 8));

          if (response.statusCode == 200) {
            final items = _parseRssXml(response.body, src['name']!, keywords);
            extracted.addAll(items);
          }
        }
      } catch (e) {
        AppLogger.warn('Fuente fallida en extracción local: ${src['name']}', tag: 'Extractor', error: e);
      }
    }

    if (extracted.isNotEmpty) {
      // Ordenar por novedades
      extracted.sort((a, b) => (b['published'] ?? '').compareTo(a['published'] ?? ''));

      // Guardar en la base de datos local SQLite (cobalto_edge.db) + SharedPreferences fallback
      await LocalDbService.insertEntries(extracted);
    }

    return extracted;
  }

  static Future<List<Map<String, dynamic>>> _scrapeTelegramChannel(String url, String sourceName, List<String> keywords) async {
    final List<Map<String, dynamic>> items = [];
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.0',
          'Accept-Language': 'es-ES,es;q=0.9',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final html = response.body;
        final msgMatches = RegExp(r'<div class="tgme_widget_message_text[^"]*">([\s\S]*?)<\/div>', caseSensitive: false).allMatches(html);
        final photoMatches = RegExp(r"background-image:url\('(.*?)'\)", caseSensitive: false).allMatches(html);
        final photosList = photoMatches.map((m) => m.group(1) ?? '').where((u) => u.isNotEmpty).toList();

        int photoIdx = 0;
        for (final match in msgMatches) {
          final rawText = match.group(1) ?? '';
          final cleanMsg = _cleanText(rawText);
          if (cleanMsg.length > 10) {
            final title = cleanMsg.length > 90 ? '${cleanMsg.substring(0, 90)}...' : cleanMsg;
            final fullText = cleanMsg.toLowerCase();
            final matchedKw = keywords.where((kw) => fullText.contains(kw.toLowerCase())).toList();

            String? imgUrl;
            if (photoIdx < photosList.length) {
              imgUrl = photosList[photoIdx];
              photoIdx++;
            }

            items.add({
              'title': title,
              'source': sourceName,
              'summary': cleanMsg,
              'published': DateTime.now().toIso8601String().substring(0, 16),
              'link': url,
              'image': imgUrl,
              'timestamp': DateTime.now().toIso8601String(),
              'keywords_matched': matchedKw,
              'relevance_score': matchedKw.length * 10 + 60,
              'type': 'telegram',
            });
          }
        }
      }
    } catch (e) {
      AppLogger.warn('Error scrapeando canal Telegram $sourceName.', tag: 'Extractor', error: e);
    }
    return items;
  }

  static List<Map<String, dynamic>> _parseRssXml(String xmlContent, String sourceName, List<String> keywords) {
    final List<Map<String, dynamic>> items = [];
    final itemMatches = RegExp(r'<item[\s\S]*?<\/item>', caseSensitive: false).allMatches(xmlContent);

    for (final match in itemMatches) {
      final block = match.group(0) ?? '';

      final title = _cleanText(_extractTag(block, 'title'));
      final link = _extractTag(block, 'link');
      final description = _cleanText(_extractTag(block, 'description'));
      final pubDate = _extractTag(block, 'pubDate');

      // Extraer imagen destacada si existe en el feed RSS
      String? image;
      final mediaMatch = RegExp('url=["\'](https?://[^"\']+\\.(?:jpg|jpeg|png|webp|gif))["\']', caseSensitive: false).firstMatch(block);
      if (mediaMatch != null) {
        image = mediaMatch.group(1);
      }

      if (title.isNotEmpty) {
        final String fullText = '$title $description'.toLowerCase();
        final matchedKw = keywords.where((kw) => fullText.contains(kw.toLowerCase())).toList();

        items.add({
          'title': title,
          'source': sourceName,
          'summary': description,
          'published': pubDate.isNotEmpty ? pubDate : DateTime.now().toIso8601String().substring(0, 16),
          'link': link,
          'image': image,
          'timestamp': DateTime.now().toIso8601String(),
          'keywords_matched': matchedKw,
          'relevance_score': matchedKw.length * 10 + 50,
        });
      }
    }
    return items;
  }

  static String _extractTag(String block, String tagName) {
    final match = RegExp(
      '<$tagName(?:\\s+[^>]*)?>([\\s\\S]*?)</$tagName>',
      caseSensitive: false,
    ).firstMatch(block);
    if (match != null) {
      var content = match.group(1) ?? '';
      if (content.startsWith('<![CDATA[')) {
        content = content.replaceAll('<![CDATA[', '').replaceAll(']]>', '');
      }
      return content.trim();
    }
    return '';
  }

  static String _cleanText(String htmlText) {
    var cleaned = htmlText.replaceAll(RegExp(r'<[^>]*>'), '');
    cleaned = cleaned
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ');
    return cleaned.trim();
  }
}
