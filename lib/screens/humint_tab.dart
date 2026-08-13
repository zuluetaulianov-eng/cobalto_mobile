import 'package:flutter/material.dart';
import '../services/local_db_service.dart';
import '../services/cobalto_api_service.dart';

class HumintTab extends StatefulWidget {
  const HumintTab({super.key});

  @override
  State<HumintTab> createState() => _HumintTabState();
}

class _HumintTabState extends State<HumintTab> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _latController = TextEditingController(text: '10.4806');
  final TextEditingController _lngController = TextEditingController(text: '-66.9036');

  String _threatLevel = 'ELEVATED';
  bool _isSaving = false;
  bool _isSyncing = false;
  List<Map<String, dynamic>> _reports = [];

  final Map<String, Color> _threatColors = {
    'CRITICAL': const Color(0xFFFF2D55),
    'ELEVATED': const Color(0xFFFF9500),
    'MODERATE': const Color(0xFFFFCC00),
    'LOW': const Color(0xFF34C759),
  };

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    final list = await LocalDbService.getFieldReports();
    if (mounted) {
      setState(() => _reports = list);
    }
  }

  Future<void> _saveLocalReport() async {
    final title = _titleController.text.trim();
    final desc = _descController.text.trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Ingrese un título para el reporte.'),
          backgroundColor: Color(0xFFFF2D55),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    final report = {
      'id': 'humint_${DateTime.now().millisecondsSinceEpoch}',
      'title': title,
      'description': desc,
      'threat_level': _threatLevel,
      'lat': double.tryParse(_latController.text) ?? 0.0,
      'lng': double.tryParse(_lngController.text) ?? 0.0,
      'timestamp': DateTime.now().toIso8601String(),
      'synced': false,
    };

    await LocalDbService.saveFieldReport(report);

    // Intentar transmisión automática si hay conexión con el servidor PC
    final syncRes = await CobaltoApiService.sendHumintReport(report);
    if (syncRes['success'] == true) {
      report['synced'] = true;
      await LocalDbService.saveFieldReport(report);
    }

    _titleController.clear();
    _descController.clear();

    if (mounted) {
      setState(() => _isSaving = false);
      await _loadReports();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            syncRes['success'] == true
                ? '✅ Reporte guardado y sincronizado con el servidor.'
                : '💾 Reporte guardado localmente en la base de datos autónoma.',
          ),
          backgroundColor: syncRes['success'] == true ? const Color(0xFF00FFAA) : const Color(0xFF00E5FF),
        ),
      );
    }
  }

  Future<void> _syncPendingReports() async {
    setState(() => _isSyncing = true);

    int syncedCount = 0;
    for (final report in _reports) {
      if (report['synced'] == 0 || report['synced'] == false) {
        final res = await CobaltoApiService.sendHumintReport(report);
        if (res['success'] == true) {
          final mutable = Map<String, dynamic>.from(report);
          mutable['synced'] = true;
          await LocalDbService.saveFieldReport(mutable);
          syncedCount++;
        }
      }
    }

    await _loadReports();
    if (mounted) {
      setState(() => _isSyncing = false);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(syncedCount > 0
              ? '✅ $syncedCount reportes sincronizados con el servidor.'
              : 'ℹ️ No hay reportes pendientes o el servidor no está en línea.'),
          backgroundColor: const Color(0xFF00E5FF),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0B10),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '🎯 RECOLECCIÓN HUMINT DE CAMPO',
                  style: TextStyle(
                    color: Color(0xFF00E5FF),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    letterSpacing: 1,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _isSyncing ? null : _syncPendingReports,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF141824),
                    foregroundColor: const Color(0xFF00E5FF),
                    side: const BorderSide(color: Color(0xFF00E5FF)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  icon: _isSyncing
                      ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.sync, size: 14),
                  label: const Text('SYNC SERVIDOR', style: TextStyle(fontSize: 10, fontFamily: 'monospace')),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Formulario de Captura de Campo
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF141824),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _titleController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'Título del Evento / Avistamiento',
                      labelStyle: TextStyle(color: Colors.white54, fontSize: 12),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00E5FF))),
                    ),
                  ),
                  const SizedBox(height: 8),

                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _threatLevel,
                          dropdownColor: const Color(0xFF141824),
                          decoration: const InputDecoration(
                            labelText: 'Nivel de Amenaza',
                            labelStyle: TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                          style: TextStyle(
                            color: _threatColors[_threatLevel] ?? Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                          items: _threatColors.keys.map((level) {
                            return DropdownMenuItem(
                              value: level,
                              child: Text(level, style: TextStyle(color: _threatColors[level])),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _threatLevel = val);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _latController,
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
                          decoration: const InputDecoration(
                            labelText: 'Latitud GPS',
                            labelStyle: TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _lngController,
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
                          decoration: const InputDecoration(
                            labelText: 'Longitud GPS',
                            labelStyle: TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  TextField(
                    controller: _descController,
                    maxLines: 2,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: const InputDecoration(
                      labelText: 'Detalles / Observaciones Tácticas',
                      labelStyle: TextStyle(color: Colors.white54, fontSize: 11),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00E5FF))),
                    ),
                  ),
                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _saveLocalReport,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E5FF),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      icon: _isSaving
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.save),
                      label: const Text(
                        'GUARDAR REPORTE (AUTÓNOMO/SYNC)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, fontFamily: 'monospace'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            const Text(
              'HISTORIAL DE REPORTES EN EL DISPOSITIVO:',
              style: TextStyle(color: Colors.white54, fontSize: 10, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 6),

            // Lista de Reportes Guardados
            Expanded(
              child: _reports.isEmpty
                  ? const Center(
                      child: Text('No hay reportes HUMINT registrados.', style: TextStyle(color: Colors.white38, fontSize: 12)),
                    )
                  : ListView.builder(
                      itemCount: _reports.length,
                      itemBuilder: (context, index) {
                        final rep = _reports[index];
                        final isSynced = rep['synced'] == 1 || rep['synced'] == true;
                        final level = rep['threat_level'] ?? 'LOW';

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          color: const Color(0xFF141824),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                            side: BorderSide(color: _threatColors[level]?.withOpacity(0.5) ?? Colors.white10),
                          ),
                          child: ListTile(
                            dense: true,
                            title: Text(
                              rep['title'] ?? 'Sin título',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            subtitle: Text(
                              '${rep['description'] ?? ''}\nGPS: ${rep['lat']}, ${rep['lng']} | ${rep['timestamp']}',
                              style: const TextStyle(color: Colors.white70, fontSize: 10),
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _threatColors[level]?.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    level,
                                    style: TextStyle(color: _threatColors[level], fontSize: 9, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Icon(
                                  isSynced ? Icons.cloud_done : Icons.cloud_off,
                                  size: 14,
                                  color: isSynced ? const Color(0xFF00FFAA) : Colors.amber,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
