import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/cobalto_api_service.dart';
import '../services/local_extractor_service.dart';
import '../services/local_db_service.dart';
import '../widgets/intel_card_generator_dialog.dart';

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

    // 1. Obtener noticias locales guardadas en SQLite
    final localEntries = await LocalDbService.getEntries();

    // 2. Intentar consultar noticias frescas del servidor
    final remoteNews = await CobaltoApiService.fetchNews();

    final List<Map<String, dynamic>> combined = [];
    final Set<String> seenTitles = {};

    // Agregar noticias del servidor primero (si existen)
    if (remoteNews.isNotEmpty) {
      final List<Map<String, dynamic>> castedRemote = List<Map<String, dynamic>>.from(remoteNews);
      for (final item in castedRemote) {
        final title = item['title']?.toString() ?? '';
        if (title.isNotEmpty && !seenTitles.contains(title)) {
          seenTitles.add(title);
          combined.add(item);
        }
      }
      // Guardar noticias remotas en la BD local SQLite para modo offline
      await LocalDbService.insertEntries(castedRemote);
    }

    // Agregar noticias locales de SQLite que no estén duplicadas
    for (final item in localEntries) {
      final title = item['title']?.toString() ?? '';
      if (title.isNotEmpty && !seenTitles.contains(title)) {
        seenTitles.add(title);
        combined.add(item);
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

    if (mounted) {
      setState(() {
        _news = combined;
        _applyFilter();
        _isLoading = false;
      });

      // Respaldar caché en SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_sitrep_news', json.encode(combined));
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

  void _copyToClipboard(String title, String? link) {
    final textToCopy = link != null && link.isNotEmpty ? '$title\nFuente: $link' : title;
    Clipboard.setData(ClipboardData(text: textToCopy));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('📋 Reporte OSINT copiado al portapapeles.'),
        backgroundColor: Color(0xFF00E5FF),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _shareNewsModal(BuildContext context, Map<String, dynamic> item) {
    final title = item['title'] ?? 'Reporte COBALTO OSINT';
    final link = item['link']?.toString() ?? '';
    final source = item['source'] ?? 'Intel Hub';

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141824),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Icons.share, color: Color(0xFF00E5FF), size: 22),
                  SizedBox(width: 10),
                  Text(
                    'DIFUNDIR REPORTE OSINT',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF00E5FF).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.4)),
                ),
                child: ListTile(
                  leading: const Icon(Icons.image_outlined, color: Color(0xFF00E5FF), size: 28),
                  title: const Text(
                    'GENERAR FICHA GRÁFICA HD (PNG)',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'monospace'),
                  ),
                  subtitle: const Text('Exporta infografía personalizada con QR y notas', style: TextStyle(color: Colors.white70, fontSize: 11)),
                  onTap: () {
                    Navigator.pop(context);
                    IntelCardGeneratorDialog.show(context, item);
                  },
                ),
              ),
              const SizedBox(height: 10),
              ListTile(
                leading: const Icon(Icons.copy, color: Color(0xFF00E5FF)),
                title: const Text('Copiar Texto y Enlace', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _copyToClipboard(title, link);
                },
              ),
              ListTile(
                leading: const Icon(Icons.send, color: Color(0xFF00FFAA)),
                title: const Text('Compartir por Telegram', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  final tgUrl = 'https://t.me/share/url?url=${Uri.encodeComponent(link)}&text=${Uri.encodeComponent('[$source] $title')}';
                  _openLink(tgUrl);
                },
              ),
              ListTile(
                leading: const Icon(Icons.chat_bubble_outline, color: Color(0xFF25D366)),
                title: const Text('Compartir por WhatsApp', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  final waUrl = 'https://wa.me/?text=${Uri.encodeComponent('[$source] $title\n$link')}';
                  _openLink(waUrl);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showDetailsModal(BuildContext context, Map<String, dynamic> item) {
    final title = item['title'] ?? 'Sin título';
    final source = item['source'] ?? 'Intel Hub';
    final summary = item['summary'] ?? item['text'] ?? 'Sin contenido detallado registrado.';
    final published = item['published'] ?? item['timestamp'] ?? '';
    final link = item['link'];
    final imageUrl = item['image'] ?? item['img'] ?? item['media_url'];
    final matchedKw = item['keywords_matched'] is List ? List<String>.from(item['keywords_matched']) : [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0A0B10),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          minChildSize: 0.4,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.white30,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  if (imageUrl != null && imageUrl.toString().startsWith('http')) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        imageUrl.toString(),
                        height: 180,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E5FF).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF00E5FF)),
                        ),
                        child: Text(
                          source.toString().toUpperCase(),
                          style: const TextStyle(
                            color: Color(0xFF00E5FF),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      Text(
                        published,
                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      height: 1.3,
                    ),
                  ),
                  if (matchedKw.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: matchedKw.map((kw) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.amber.withOpacity(0.4)),
                          ),
                          child: Text(
                            '#$kw',
                            style: const TextStyle(color: Colors.amber, fontSize: 10, fontFamily: 'monospace'),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  const Divider(color: Colors.white10, height: 28),
                  Text(
                    summary,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.87),
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00E5FF),
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: const Icon(Icons.open_in_new, size: 18),
                          label: const Text('ABRIR FUENTE WEB', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          onPressed: () => _openLink(link),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton.filledTonal(
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFF141824),
                          foregroundColor: const Color(0xFF00E5FF),
                          side: const BorderSide(color: Color(0xFF00E5FF), width: 0.5),
                        ),
                        icon: const Icon(Icons.share),
                        onPressed: () => _shareNewsModal(context, item),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
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
                              onTap: () => _showDetailsModal(context, Map<String, dynamic>.from(item)),
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
                                  const Divider(height: 1, color: Colors.white10),
                                  // Barra Táctica de Acciones en el Pie de la Tarjeta
                                  Container(
                                    color: const Color(0xFF0F121C),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        TextButton.icon(
                                          style: TextButton.styleFrom(
                                            foregroundColor: const Color(0xFF00E5FF),
                                            padding: const EdgeInsets.symmetric(horizontal: 8),
                                          ),
                                          icon: const Icon(Icons.article_outlined, size: 16),
                                          label: const Text(
                                            'LEER',
                                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                                          ),
                                          onPressed: () => _showDetailsModal(context, Map<String, dynamic>.from(item)),
                                        ),
                                        Row(
                                          children: [
                                            TextButton.icon(
                                              style: TextButton.styleFrom(
                                                foregroundColor: Colors.white70,
                                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                              ),
                                              icon: const Icon(Icons.open_in_new, size: 15),
                                              label: const Text(
                                                'ABRIR WEB',
                                                style: TextStyle(fontSize: 10, fontFamily: 'monospace'),
                                              ),
                                              onPressed: () => _openLink(link),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.share_outlined, size: 18, color: Color(0xFF00FFAA)),
                                              tooltip: 'Difundir Noticia',
                                              onPressed: () => _shareNewsModal(context, Map<String, dynamic>.from(item)),
                                            ),
                                          ],
                                        ),
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
