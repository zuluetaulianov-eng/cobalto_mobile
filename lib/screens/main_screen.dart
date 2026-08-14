import 'package:flutter/material.dart';
import '../services/stealth_service.dart';
import '../services/dead_man_switch_service.dart';
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
    return ListenableBuilder(
      listenable: Listenable.merge([StealthService(), DeadManSwitchService()]),
      builder: (context, _) {
        final stealth = StealthService();
        final deadMan = DeadManSwitchService();

        final isNVG = stealth.isStealthActive;
        final accent = stealth.accentColor;
        final bg = stealth.backgroundColor;
        final surface = stealth.surfaceColor;

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: surface,
            elevation: 0,
            title: Row(
              children: [
                Icon(isNVG ? Icons.visibility_off : Icons.bolt, color: accent, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isNVG ? '[NVG] ${_titles[_currentIndex]}' : _titles[_currentIndex],
                    style: TextStyle(
                      color: stealth.textColor,
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
              IconButton(
                icon: Icon(
                  isNVG ? Icons.wb_sunny : Icons.visibility_off,
                  color: isNVG ? const Color(0xFFFF1E1E) : Colors.white70,
                  size: 20,
                ),
                tooltip: 'Conmutar Modo Sigilo (NVG)',
                onPressed: () => stealth.toggleStealth(),
              ),
              Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: accent.withOpacity(0.3)),
                ),
                child: Text(
                  isNVG ? 'NVG COBALTO' : 'COBALTO C4I',
                  style: TextStyle(
                    color: accent,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              if (deadMan.isEmergencyAlertActive)
                Container(
                  width: double.infinity,
                  color: const Color(0xFFFF2D55),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      const Icon(Icons.warning, color: Colors.white, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '🚨 CAÍDA DETECTADA! TRANSMITIENDO SOS EN ${deadMan.countdownSeconds}s',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () => deadMan.cancelEmergency(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFFFF2D55),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        ),
                        child: const Text(
                          'CANCELAR SOS',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: IndexedStack(
                  index: _currentIndex,
                  children: _tabs,
                ),
              ),
            ],
          ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) => setState(() => _currentIndex = index),
            backgroundColor: surface,
            selectedItemColor: accent,
            unselectedItemColor: isNVG ? const Color(0xFF660000) : Colors.white38,
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
      },
    );
  }
}

