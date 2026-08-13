import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/cobalto_api_service.dart';
import '../services/local_extractor_service.dart';

import '../services/local_db_service.dart';

class SitrepTab extends StatefulWidget {
  const SitrepTab({super.key});

  @override
  State<SitrepTab> createState() => _SitrepTabState();
}

class _SitrepTabState extends State<SitrepTab> {
  List<dynamic> _news = [];
  List<dynamic> _filteredNews = [];
  bool _isLoading = true;
  bool _isExtracting = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadCacheAndFetch();
  }

  Future<void> _loadCacheAndFetch() async {
    // 1. Cargar almacenamiento SQLite local (cobalto_edge.db)
    final localDbNews = await LocalDbService.getEntries();
    if (localDbNews.isNotEmpty) {
      setState(() {
        _news = localDbNews;
        _applyFilter();
        _isLoading = false;
      });
    }

    // 2. Intentar obtener datos frescos del servidor o extracción directa
    await _loadData();
  }

  Future<void> _loadData() async {
    if (_news.isEmpty) setState(() => _isLoading = true);
    var data = await CobaltoApiService.fetchNews();

    // Si el servidor no retorna datos (offline o apagado), ejecutar extracción directa en el teléfono
    if (data.isEmpty) {
      final localExtracted = await LocalExtractorService.extractDirectlyOnDevice();
      if (localExtracted.isNotEmpty) {
        data = localExtracted;
      } else {
        // Reintentar leer almacenamiento SQLite local
        data = await LocalDbService.getEntries();
      }
    }

    if (mounted) {
      if (data.isNotEmpty) {
        setState(() {
          _news = data;
          _applyFilter();
          _isLoading = false;
        });

        // Guardar en caché local
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cached_sitrep_news', json.encode(data));
      } else {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _triggerExtraction() async {
    setState(() => _isExtracting = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('⚡ Ejecutando extracción de fuentes OSINT directamente en el móvil...'),
        backgroundColor: Color(0xFF00E5FF),
        duration: Duration(seconds: 3),
      ),
    );

    // 1. Intentar servidor si está activo
    await CobaltoApiService.triggerExtraction();

    // 2. Ejecutar Extracción Directa Autónoma en el Teléfono (100% independiente)
    final localNews = await LocalExtractorService.extractDirectlyOnDevice();

    if (!mounted) return;

    setState(() => _isExtracting = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(localNews.isNotEmpty
            ? '✅ Extracción completada en el móvil: ${localNews.length} entradas procesadas.'
            : '✅ Extracción finalizada.'),
        backgroundColor: const Color(0xFF00FFAA),
        duration: const Duration(seconds: 4),
      ),
    );

    await _loadData();
  }

  void _applyFilter() {
    if (_searchQuery.isEmpty) {
      _filteredNews = List.from(_news);
    } else {
      final q = _searchQuery.toLowerCase();
      _filteredNews = _news.where((item) {
        final title = (item['title'] ?? '').toString().toLowerCase();
        final summary = (item['summary'] ?? '').toString().toLowerCase();
        final source = (item['source'] ?? '').toString().toLowerCase();
        return title.contains(q) || summary.contains(q) || source.contains(q);
      }).toList();
    }
  }

  Future<void> _openLink(String? urlStr) async {
    if (urlStr == null || urlStr.isEmpty) return;
    final Uri uri = Uri.parse(urlStr);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Barra Superior de Controles (Búsqueda + Botón Forzar Extracción/Scraper)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: const Color(0xFF0A0B10),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Filtrar SitRep / Noticias...',
                        hintStyle: const TextStyle(color: Colors.white38),
                        prefixIcon: const Icon(Icons.search, color: Color(0xFF00E5FF), size: 20),
                        filled: true,
                        fillColor: const Color(0xFF141824),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFF00E5FF), width: 0.3),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFF00E5FF), width: 1),
                        ),
                      ),
                      onChanged: (val) {
                        setState(() {
                          _searchQuery = val;
                          _applyFilter();
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E5FF),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: _isExtracting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                          )
                        : const Icon(Icons.bolt, size: 18),
                    label: Text(
                      _isExtracting ? 'SCRAPING...' : 'EJECUTAR',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                    ),
                    onPressed: _isExtracting ? null : _triggerExtraction,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'NOTICIAS REGISTRADAS: ${_filteredNews.length}',
                    style: const TextStyle(color: Colors.white54, fontSize: 10, fontFamily: 'monospace'),
                  ),
                  const Text(
                    'PULL TO REFRESH ⬇️',
                    style: TextStyle(color: Color(0xFF00E5FF), fontSize: 9, fontFamily: 'monospace'),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Lista Principal de Entradas SITREP
        Expanded(
          child: RefreshIndicator(
            color: const Color(0xFF00E5FF),
            backgroundColor: const Color(0xFF0A0B10),
            onRefresh: _loadData,
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF00E5FF)),
                  )
                : _filteredNews.isEmpty
                    ? SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: Container(
                          height: 350,
                          alignment: Alignment.center,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.newspaper, size: 48, color: Colors.white24),
                              const SizedBox(height: 12),
                              Text(
                                _searchQuery.isEmpty
                                    ? 'Sin noticias activas en el caché'
                                    : 'No hay resultados para "$_searchQuery"',
                                style: const TextStyle(color: Colors.white54, fontSize: 13),
                              ),
                              const SizedBox(height: 14),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF00E5FF).withOpacity(0.15),
                                  foregroundColor: const Color(0xFF00E5FF),
                                  side: const BorderSide(color: Color(0xFF00E5FF)),
                                ),
                                icon: const Icon(Icons.play_arrow),
                                label: const Text('FORZAR EXTRACCIÓN AHORA'),
                                onPressed: _triggerExtraction,
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        itemCount: _filteredNews.length,
                        itemBuilder: (context, index) {
                          final item = _filteredNews[index];
                          final title = item['title'] ?? 'Sin título';
                          final source = item['source'] ?? 'Intel Hub';
                          final summary = item['summary'] ?? item['text'] ?? '';
                          final published = item['published'] ?? item['timestamp'] ?? '';
                          final link = item['link'];

                          final imageUrl = item['image'] ?? item['img'] ?? item['media_url'];

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            color: const Color(0xFF141824),
                            clipBehavior: Clip.antiAlias,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: const BorderSide(color: Colors.white10),
                            ),
                            child: InkWell(
                              onTap: () => _openLink(link),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (imageUrl != null && imageUrl.toString().startsWith('http'))
                                    Container(
                                      height: 140,
                                      width: double.infinity,
                                      color: Colors.black26,
                                      child: Image.network(
                                        imageUrl.toString(),
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                                      ),
                                    ),
                                  Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF00E5FF).withOpacity(0.15),
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.3)),
                                              ),
                                              child: Text(
                                                source.toString().toUpperCase(),
                                                style: const TextStyle(
                                                  color: Color(0xFF00E5FF),
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                  fontFamily: 'monospace',
                                                ),
                                              ),
                                            ),
                                            Text(
                                              published,
                                              style: const TextStyle(
                                                color: Colors.white38,
                                                fontSize: 10,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          title,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        if (summary.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Text(
                                            summary,
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12,
                                              height: 1.4,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ),
      ],
    );
  }
}
