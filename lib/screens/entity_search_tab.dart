import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/app_logger.dart';

class EntitySearchTab extends StatefulWidget {
  const EntitySearchTab({super.key});

  @override
  State<EntitySearchTab> createState() => _EntitySearchTabState();
}

class _EntitySearchTabState extends State<EntitySearchTab> {
  final TextEditingController _queryController = TextEditingController();
  bool _isSearching = false;
  List<Map<String, dynamic>> _results = [];
  String _activeFilter = 'ALL';

  final List<Map<String, dynamic>> _knownEntities = [
    {
      'name': 'OFAC SDN: PDVSA (Petróleos de Venezuela S.A.)',
      'type': 'ENTIDAD SANCIONADA',
      'program': 'VENEZUELA-EO13884',
      'details': 'Sancionado por el Departamento del Tesoro de EE. UU.',
    },
    {
      'name': 'OFAC SDN: BANCO CENTRAL DE VENEZUELA',
      'type': 'ENTIDAD FINANCIERA SANCIONADA',
      'program': 'VENEZUELA-EO13850',
      'details': 'Restricción de operaciones financieras internacionales.',
    },
    {
      'name': 'Billetera Cripto (BTC): 1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa',
      'type': 'CRIPTO WALLET (BTC)',
      'program': 'SATOSHI_GENESIS',
      'details': 'Wallet de génesis de Bitcoin. Sin bloqueos registrados.',
    },
  ];

  @override
  void initState() {
    super.initState();
    _results = List.from(_knownEntities);
  }

  Future<void> _performSearch() async {
    final q = _queryController.text.trim().toLowerCase();
    setState(() => _isSearching = true);

    await Future.delayed(const Duration(milliseconds: 300));

    final filtered = _knownEntities.where((item) {
      final name = item['name'].toString().toLowerCase();
      final type = item['type'].toString().toLowerCase();
      final details = item['details'].toString().toLowerCase();

      final matchesQuery = q.isEmpty || name.contains(q) || type.contains(q) || details.contains(q);
      final matchesFilter = _activeFilter == 'ALL' ||
          (_activeFilter == 'OFAC' && type.contains('SANCIONADA')) ||
          (_activeFilter == 'CRIPTO' && type.contains('CRIPTO'));

      return matchesQuery && matchesFilter;
    }).toList();

    // Si es una wallet Bitcoin ingresada directamente, consultar Blockchain API
    if (q.startsWith('1') || q.startsWith('3') || q.startsWith('bc1')) {
      try {
        final res = await http.get(Uri.parse('https://blockchain.info/rawaddr/$q')).timeout(const Duration(seconds: 5));
        if (res.statusCode == 200) {
          final data = json.decode(res.body);
          final balance = (data['final_balance'] ?? 0) / 100000000;
          filtered.insert(0, {
            'name': 'Billetera BTC: $q',
            'type': 'CRIPTO WALLET (BTC)',
            'program': 'VERIFICACIÓN EN VIVO',
            'details': 'Balance en cadena: $balance BTC | Total Tx: ${data['n_tx'] ?? 0}',
          });
        }
      } catch (e) {
        AppLogger.warn('Fallo la consulta blockchain para $q.', tag: 'OFAC', error: e);
      }
    }

    if (mounted) {
      setState(() {
        _results = filtered;
        _isSearching = false;
      });
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
            const Text(
              '🔍 ENTIDADES, SANCIÓNES OFAC & WALLETS CRIPTO',
              style: TextStyle(
                color: Color(0xFF00E5FF),
                fontSize: 12,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 10),

            // Buscador
            TextField(
              controller: _queryController,
              onChanged: (_) => _performSearch(),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Buscar entidad, persona o wallet (BTC/ETH)...',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF00E5FF)),
                filled: true,
                fillColor: const Color(0xFF141824),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF00E5FF)),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Filtros rápidos
            Row(
              children: [
                _filterChip('TODOS', 'ALL'),
                const SizedBox(width: 6),
                _filterChip('🏛️ SANCIONES OFAC', 'OFAC'),
                const SizedBox(width: 6),
                _filterChip('₿ CRIPTO WALLETS', 'CRIPTO'),
              ],
            ),

            const SizedBox(height: 12),

            // Lista de Resultados
            Expanded(
              child: _isSearching
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)))
                  : _results.isEmpty
                      ? const Center(
                          child: Text('Sin coincidencias encontradas.', style: TextStyle(color: Colors.white38, fontSize: 12)),
                        )
                      : ListView.builder(
                          itemCount: _results.length,
                          itemBuilder: (context, index) {
                            final item = _results[index];
                            final isOfac = item['type'].toString().contains('SANCIONADA');

                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              color: const Color(0xFF141824),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(color: isOfac ? Colors.red.withOpacity(0.5) : const Color(0xFF00E5FF).withOpacity(0.3)),
                              ),
                              child: ListTile(
                                leading: Icon(
                                  isOfac ? Icons.gavel : Icons.account_balance_wallet,
                                  color: isOfac ? Colors.red : const Color(0xFF00E5FF),
                                ),
                                title: Text(
                                  item['name'].toString(),
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Text(
                                      '${item['type']} [${item['program']}]',
                                      style: TextStyle(
                                        color: isOfac ? Colors.redAccent : const Color(0xFF00FFAA),
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      item['details'].toString(),
                                      style: const TextStyle(color: Colors.white70, fontSize: 11),
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

  Widget _filterChip(String label, String code) {
    final isSelected = _activeFilter == code;
    return GestureDetector(
      onTap: () {
        setState(() => _activeFilter = code);
        _performSearch();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00E5FF) : const Color(0xFF141824),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isSelected ? const Color(0xFF00E5FF) : Colors.white10),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}
