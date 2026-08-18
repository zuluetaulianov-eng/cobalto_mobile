import 'package:flutter/material.dart';

import '../services/geofence_service.dart';
import '../services/gps_service.dart';

/// Gestor táctico de geocercas: alta/edición de zonas, perímetro de base,
/// monitoreo configurable y persistencia local.
class GeofenceManagerSheet extends StatefulWidget {
  const GeofenceManagerSheet({super.key});

  @override
  State<GeofenceManagerSheet> createState() => _GeofenceManagerSheetState();
}

class _GeofenceManagerSheetState extends State<GeofenceManagerSheet> {
  List<GeofenceZone> _zones = [];
  bool _isLoading = true;
  bool _isMonitoringEnabled = false;
  int _intervalSeconds = 60;
  String _gpsStatus = '';

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _radiusController = TextEditingController(text: '5');
  String _selectedThreat = 'ALTA';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _radiusController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final zones = await GeofenceService.getZones();
    final enabled = await GeofenceService.isMonitoringEnabled();
    final interval = await GeofenceService.getMonitoringIntervalSeconds();
    if (mounted) {
      setState(() {
        _zones = zones;
        _isMonitoringEnabled = enabled;
        _intervalSeconds = interval;
        _isLoading = false;
      });
    }
  }

  Future<void> _addZoneUsingGps() async {
    setState(() => _gpsStatus = 'Obteniendo posición GPS...');
    final pos = await GpsService.getCurrentPosition();
    if (pos == null) {
      setState(() => _gpsStatus = '⚠️ No se pudo obtener GPS. Verifica permisos y servicios.');
      return;
    }

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _gpsStatus = '⚠️ Ingrese un nombre para la zona.');
      return;
    }

    final radius = double.tryParse(_radiusController.text.trim()) ?? 5.0;

    await GeofenceService.addZone(
      name: name,
      lat: pos.latitude,
      lng: pos.longitude,
      radiusKm: radius,
      threatLevel: _selectedThreat,
    );

    _nameController.clear();
    await _load();
    setState(() {
      _gpsStatus = '✅ Zona creada en su ubicación: ${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}';
    });
  }

  Future<void> _setAsBase(GeofenceZone zone) async {
    await GeofenceService.markAsBase(zone.id);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🛡️ Zona marcada como PERÍMETRO DE BASE.'),
          backgroundColor: Color(0xFF00FFAA),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0E111A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF00E5FF).withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  '🗺️ GESTIÓN DE GEOCERCAS Y MONITOREO GPS',
                  style: TextStyle(
                    color: Color(0xFF00E5FF),
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    letterSpacing: 1,
                  ),
                ),
              ),
              const Divider(color: Colors.white12),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)))
                    : ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.all(12),
                        children: [
                          _buildMonitorCard(),
                          const SizedBox(height: 16),
                          _buildNewZoneCard(),
                          const SizedBox(height: 16),
                          _buildZonesList(),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMonitorCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF141824),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _isMonitoringEnabled ? const Color(0xFF00FFAA) : Colors.white10,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              '📡 MONITOREO DE GEOCERCAS',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
            ),
            subtitle: Text(
              _isMonitoringEnabled
                  ? 'Evaluando posición GPS periódicamente.'
                  : 'Desactivado. Use "Guardar" para reactivar según lo configurado.',
              style: const TextStyle(fontSize: 10, color: Colors.white54),
            ),
            value: _isMonitoringEnabled,
            activeTrackColor: const Color(0xFF00FFAA),
            onChanged: (value) async {
              setState(() => _isMonitoringEnabled = value);
              await GeofenceService.setMonitoringEnabled(value);
            },
          ),
          const SizedBox(height: 6),
          const Text(
            'FRECUENCIA DE EVALUACIÓN:',
            style: TextStyle(color: Colors.white54, fontSize: 10, fontFamily: 'monospace'),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<int>(
            value: _intervalSeconds,
            dropdownColor: const Color(0xFF141824),
            style: const TextStyle(color: Colors.white, fontSize: 12),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF0E111A),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            ),
            items: GeofenceService.monitoringIntervals
                .map((i) => DropdownMenuItem<int>(
                      value: int.parse(i['value']!),
                      child: Text(i['label']!, style: const TextStyle(fontSize: 12)),
                    ))
                .toList(),
            onChanged: (value) async {
              if (value == null) return;
              setState(() => _intervalSeconds = value);
              await GeofenceService.saveMonitoringIntervalSeconds(value);
            },
          ),
          const SizedBox(height: 6),
          Text(
            '⚠️ El intervalo aplica al monitoreo: 0 = instantáneo (cada fix corto), 10s–60s para reacción rápida, 1–60 min para ahorro de batería.',
            style: const TextStyle(color: Colors.white38, fontSize: 9),
          ),
        ],
      ),
    );
  }

  Widget _buildNewZoneCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF141824),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '➕ CREAR NUEVA ZONA (EN MI UBICACIÓN GPS)',
            style: TextStyle(color: Color(0xFF00E5FF), fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _nameController,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
            decoration: InputDecoration(
              labelText: 'NOMBRE DE LA ZONA (ej: Zona Roja Este)',
              labelStyle: const TextStyle(color: Colors.white54, fontSize: 11),
              filled: true,
              fillColor: const Color(0xFF0E111A),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _radiusController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    labelText: 'RADIO (KM)',
                    labelStyle: const TextStyle(color: Colors.white54, fontSize: 11),
                    filled: true,
                    fillColor: const Color(0xFF0E111A),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedThreat,
                  dropdownColor: const Color(0xFF141824),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    labelText: 'NIVEL',
                    labelStyle: const TextStyle(color: Colors.white54, fontSize: 11),
                    filled: true,
                    fillColor: const Color(0xFF0E111A),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'CRÍTICA', child: Text('CRÍTICA', style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(value: 'ALTA', child: Text('ALTA', style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(value: 'MEDIA', child: Text('MEDIA', style: TextStyle(fontSize: 12))),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _selectedThreat = value);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: _addZoneUsingGps,
            icon: const Icon(Icons.gps_fixed, size: 16),
            label: const Text(
              'CREAR ZONA EN MI POSICIÓN ACTUAL',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E5FF).withOpacity(0.2),
              foregroundColor: const Color(0xFF00E5FF),
              side: const BorderSide(color: Color(0xFF00E5FF)),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
          if (_gpsStatus.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_gpsStatus, style: const TextStyle(color: Colors.white70, fontSize: 10)),
          ],
        ],
      ),
    );
  }

  Widget _buildZonesList() {
    if (_zones.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text(
            'Sin geocercas configuradas.\nCree una zona con su ubicación GPS actual.',
            style: TextStyle(color: Colors.white38, fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ZONAS ACTIVAS (${_zones.length}):',
          style: const TextStyle(color: Colors.white54, fontSize: 11, fontFamily: 'monospace'),
        ),
        const SizedBox(height: 6),
        ..._zones.map((zone) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF141824),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: zone.threatLevel == 'CRÍTICA'
                      ? const Color(0xFFFF2D55).withOpacity(0.5)
                      : const Color(0xFF00E5FF).withOpacity(0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${zone.isBase ? '🛡️ ' : '📍 '}${zone.name}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      Text(
                        '[${zone.threatLevel}]',
                        style: TextStyle(
                          color: zone.threatLevel == 'CRÍTICA' ? const Color(0xFFFF2D55) : const Color(0xFF00E5FF),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Centro: ${zone.lat.toStringAsFixed(4)}, ${zone.lng.toStringAsFixed(4)} | Radio: ${zone.radiusKm} km',
                    style: const TextStyle(color: Colors.white54, fontSize: 10),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('ACTIVA', style: TextStyle(fontSize: 10, fontFamily: 'monospace')),
                          value: zone.active,
                          dense: true,
                          activeTrackColor: const Color(0xFF00FFAA),
                          onChanged: (value) async {
                            await GeofenceService.toggleZone(zone.id, value);
                            await _load();
                          },
                        ),
                      ),
                      if (!zone.isBase)
                        IconButton(
                          icon: const Icon(Icons.shield_outlined, color: Color(0xFF00FFAA), size: 18),
                          tooltip: 'Marcar como BASE',
                          onPressed: () => _setAsBase(zone),
                        ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Color(0xFFFF2D55), size: 18),
                        tooltip: 'Eliminar zona',
                        onPressed: () async {
                          await GeofenceService.removeZone(zone.id);
                          await _load();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            )),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: () async {
            await GeofenceService.clearAllZones();
            await _load();
          },
          icon: const Icon(Icons.delete_sweep, size: 16),
          label: const Text(
            'ELIMINAR TODAS LAS ZONAS',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF2D55).withOpacity(0.2),
            foregroundColor: const Color(0xFFFF2D55),
            side: const BorderSide(color: Color(0xFFFF2D55)),
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
        ),
      ],
    );
  }
}

/// Abre el gestor de geocercas desde Ajustes.
Future<void> showGeofenceManager(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const GeofenceManagerSheet(),
  );
}
