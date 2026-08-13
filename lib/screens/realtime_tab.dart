import 'package:flutter/material.dart';
import '../services/cobalto_api_service.dart';

class RealtimeTab extends StatefulWidget {
  const RealtimeTab({super.key});

  @override
  State<RealtimeTab> createState() => _RealtimeTabState();
}

class _RealtimeTabState extends State<RealtimeTab> {
  Map<String, dynamic> _rtData = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final data = await CobaltoApiService.fetchRealtime();
    if (mounted) {
      setState(() {
        _rtData = data;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: const Color(0xFF00E5FF),
      backgroundColor: const Color(0xFF0A0B10),
      onRefresh: _loadData,
      child: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _buildSectionHeader('✈️ RASTREO DE VUELOS EN TIEMPO REAL'),
                ..._buildFlightCards(),
                const SizedBox(height: 16),
                _buildSectionHeader('🌐 EVENTOS TÁCTICOS Y CLIMA (USGS / FIRMS)'),
                ..._buildEventCards(),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF00E5FF),
          fontSize: 11,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
          letterSpacing: 1,
        ),
      ),
    );
  }

  List<Widget> _buildFlightCards() {
    final flightData = _rtData['flight_data'];
    if (flightData == null || flightData['flights'] == null || (flightData['flights'] as List).isEmpty) {
      return [
        const Card(
          color: Color(0xFF141824),
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Text('Sin anomalías de vuelo registradas.', style: TextStyle(color: Colors.white54, fontSize: 12)),
          ),
        )
      ];
    }

    final List flights = flightData['flights'];
    return flights.map((f) {
      final isEmergency = f['is_emergency'] == true;
      final callsign = f['callsign'] ?? f['icao'] ?? 'VUELO';
      final altitude = f['altitude'] ?? 'N/A';
      final speed = f['speed'] ?? 'N/A';

      return Card(
        color: const Color(0xFF141824),
        margin: const EdgeInsets.only(bottom: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: isEmergency ? Colors.red : Colors.white10),
        ),
        child: ListTile(
          leading: Icon(
            Icons.flight,
            color: isEmergency ? Colors.red : const Color(0xFF00E5FF),
          ),
          title: Text(
            callsign.toString(),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
          ),
          subtitle: Text(
            'Altitud: $altitude | Vel: $speed',
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ),
      );
    }).toList();
  }

  List<Widget> _buildEventCards() {
    final eventsData = _rtData['events_data'];
    if (eventsData == null) {
      return [
        const Card(
          color: Color(0xFF141824),
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Text('Sin eventos tácticos en este momento.', style: TextStyle(color: Colors.white54, fontSize: 12)),
          ),
        )
      ];
    }

    List<Widget> list = [];
    final quakes = eventsData['earthquakes'] as List? ?? [];
    for (var q in quakes) {
      final title = q['title'] ?? 'Sismo detectado';
      final mag = q['mag'] ?? 'N/A';
      list.add(
        Card(
          color: const Color(0xFF141824),
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: const Icon(Icons.waves, color: Colors.orange),
            title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 13)),
            subtitle: Text('Magnitud: $mag', style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ),
        ),
      );
    }

    if (list.isEmpty) {
      list.add(
        const Card(
          color: Color(0xFF141824),
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Text('Sensores sísmicos y climáticos normales.', style: TextStyle(color: Colors.white54, fontSize: 12)),
          ),
        ),
      );
    }

    return list;
  }
}
