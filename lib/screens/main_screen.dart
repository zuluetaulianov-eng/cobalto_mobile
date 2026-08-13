import 'package:flutter/material.dart';
import 'sitrep_tab.dart';
import 'map_tab.dart';
import 'alerts_tab.dart';
import 'humint_tab.dart';
import 'recon_tab.dart';
import 'entity_search_tab.dart';
import 'ai_chat_tab.dart';
import 'realtime_tab.dart';
import 'settings_tab.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  final List<Widget> _tabs = const [
    SitrepTab(),
    MapTab(),
    AlertsTab(),
    HumintTab(),
    ReconTab(),
    EntitySearchTab(),
    AiChatTab(),
    RealtimeTab(),
    SettingsTab(),
  ];

  final List<String> _titles = const [
    '📰 SITREP GLOBAL',
    '🗺️ MAPA TÁCTICO UNIFICADO',
    '⚠️ GESTIÓN DE INCIDENTES',
    '🎯 RECOLECCIÓN HUMINT DE CAMPO',
    '🛠️ RECON TOOLKIT (OSINT)',
    '🔍 ENTIDADES & SANCIÓNES OFAC',
    '🤖 IA COBALTO DEBATE',
    '📡 TELEMETRÍA EN VIVO',
    '⚙️ MODO DE OPERACIÓN MÓVIL',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0B10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF10131D),
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.bolt, color: Color(0xFF00E5FF), size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _titles[_currentIndex],
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  letterSpacing: 0.5,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF00E5FF).withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.3)),
            ),
            child: const Text(
              'COBALTO C4I',
              style: TextStyle(
                color: Color(0xFF00E5FF),
                fontSize: 9,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: _tabs,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        backgroundColor: const Color(0xFF0A0B10),
        selectedItemColor: const Color(0xFF00E5FF),
        unselectedItemColor: Colors.white38,
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 8,
        unselectedFontSize: 8,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.newspaper),
            label: 'SitRep',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map),
            label: 'Mapa',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.warning_amber_rounded),
            label: 'Alertas',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.my_location),
            label: 'HUMINT',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.build),
            label: 'Recon',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.saved_search),
            label: 'OFAC',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.psychology),
            label: 'IA Chat',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.radar),
            label: 'Vivo',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Ajustes',
          ),
        ],
      ),
    );
  }
}

