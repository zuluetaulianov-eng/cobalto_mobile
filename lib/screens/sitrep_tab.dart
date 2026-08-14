import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/cobalto_api_service.dart';
import '../services/local_extractor_service.dart';
import '../services/sitrep_feed_service.dart';
import '../widgets/intel_details_sheet.dart';
import '../widgets/intel_share_sheet.dart';
import '../widgets/sitrep_news_card.dart';

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
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    _loadCacheAndFetch();
    // Programar refresco automático en segundo plano cada 45 segundos
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      _loadData();
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadCacheAndFetch() async {
    // 1. Cargar almacenamiento SQLite local (cobalto_edge.db) al instante
    final cachedNews = await SitrepFeedService.loadCachedLocalEntries();
    if (cachedNews.isNotEmpty) {
      setState(() {
        _news = cachedNews;
        _applyFilter();
        _isLoading = false;
      });
    }

    // 2. Obtener datos frescos del servidor / extracción directa
    await _loadData();
  }

  Future<void> _loadData() async {
    if (_news.isEmpty) setState(() => _isLoading = true);

    final combined = await SitrepFeedService.loadCombinedFeed();

    if (mounted) {
      setState(() {
        _news = combined;
        _applyFilter();
        _isLoading = false;
      });
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

    // 2. Ejecutar Extracción Directa Autónoma en el Teléfono (independiente)
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
    _filteredNews = SitrepFeedService.filterNews(_news, _searchQuery);
  }

  Future<void> _openLink(String? urlStr) async {
    if (urlStr == null || urlStr.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Esta fuente no incluye un enlace web externo directo.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final Uri uri = Uri.parse(urlStr);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ No se pudo abrir la URL: $urlStr'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _shareNewsModal(BuildContext context, Map<String, dynamic> item) {
    IntelShareSheet.show(context, item: item, onOpenLink: (url) => _openLink(url));
  }

  void _showDetailsModal(BuildContext context, Map<String, dynamic> item) {
    IntelDetailsSheet.show(
      context,
      item: item,
      onOpenLink: _openLink,
      onShare: _shareNewsModal,
    );
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
                          final item = Map<String, dynamic>.from(_filteredNews[index]);
                          final link = item['link'];

                          return SitrepNewsCard(
                            item: item,
                            onRead: () => _showDetailsModal(context, item),
                            onOpenWeb: () => _openLink(link),
                            onShare: () => _shareNewsModal(context, item),
                          );
                        },
                      ),
          ),
        ),
      ],
    );
  }
}
