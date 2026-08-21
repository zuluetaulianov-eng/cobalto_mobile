import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/api_config.dart';
import '../services/aegis_zero_click_panic_service.dart';
import '../services/emergency_service.dart';
import '../services/network_discovery_service.dart';
import '../services/stealth_service.dart';
import '../services/dead_man_switch_service.dart';
import 'emergency_alarm_screen.dart';
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
  bool _alarmScreenOpen = false;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  Timer? _panicConfirmTimer;

  @override
  void initState() {
    super.initState();
    EmergencyService().addListener(_onEmergencyChanged);
    // Fase 5: pánico 0-clic (Volumen DOWN × 3).
    ZeroClickPanicService.attach();
    ZeroClickPanicService.onConfirmationRequired = _onZeroClickConfirmation;
    ZeroClickPanicService.onPanicTriggered = () {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🚨 PÁNICO 0-CLIC ACTUADO: SOS transmitido a la base.'),
          backgroundColor: Color(0xFFFF2D55),
          duration: Duration(seconds: 6),
        ),
      );
    };
  }

  @override
  void dispose() {
    EmergencyService().removeListener(_onEmergencyChanged);
    ZeroClickPanicService.detach();
    ZeroClickPanicService.onConfirmationRequired = null;
    ZeroClickPanicService.onPanicTriggered = null;
    _panicConfirmTimer?.cancel();
    super.dispose();
  }

  /// Muestra SnackBar de confirmación de pánico 0-clic con ventana de 3 s.
  void _onZeroClickConfirmation() {
    if (!mounted) return;
    _panicConfirmTimer?.cancel();
    int countdown = 3;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '⚡ PÁNICO 0-CLIC: SOS en $countdown s — toca CANCELAR para abortar.',
        ),
        backgroundColor: const Color(0xFFFF9500),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'CANCELAR',
          textColor: Colors.white,
          onPressed: () {
            _panicConfirmTimer?.cancel();
          },
        ),
      ),
    );
    _panicConfirmTimer = Timer(const Duration(seconds: 3), () {
      ZeroClickPanicService.firePanicConfirmed();
    });
  }

  void _onEmergencyChanged() {
    if (!mounted) return;
    final alarmActive = EmergencyService().alarmActive;
    if (alarmActive && !_alarmScreenOpen) {
      _alarmScreenOpen = true;
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const EmergencyAlarmScreen()))
          .then((_) => _alarmScreenOpen = false);
    }
  }

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

  // Navegación primaria (barra inferior / rail): los 5 módulos esenciales.
  // Los módulos secundarios quedan accesibles desde el cajón "MÓDULOS".
  static const List<int> _primaryTabIndices = [0, 1, 2, 6, 8];

  static const List<String> _navLabels = [
    'SitRep',
    'Mapa',
    'Alertas',
    'HUMINT',
    'Recon',
    'OFAC',
    'IA Chat',
    'Vivo',
    'Ajustes',
  ];

  static const List<IconData> _navIcons = [
    Icons.newspaper,
    Icons.map,
    Icons.warning_amber_rounded,
    Icons.my_location,
    Icons.build,
    Icons.saved_search,
    Icons.psychology,
    Icons.radar,
    Icons.settings,
  ];

  static int _primaryIndexOf(int tabIndex) => _primaryTabIndices.indexOf(tabIndex);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([StealthService(), DeadManSwitchService(), EmergencyService()]),
      builder: (context, _) {
        final stealth = StealthService();
        final deadMan = DeadManSwitchService();

        final isNVG = stealth.isStealthActive;
        final accent = stealth.accentColor;
        final bg = stealth.backgroundColor;
        final surface = stealth.surfaceColor;

        // ≥600 dp (tableta / apaisado): panel lateral tipo rail; en teléfono
        // se mantiene la barra inferior con solo 5 módulos esenciales.
        final bool useRail = MediaQuery.sizeOf(context).width >= 600;
        final int navPos = _primaryIndexOf(_currentIndex);
        final int navIndex = navPos < 0 ? 0 : navPos;

        // Franjas de estatus + ventana de módulos (apiladas sobre el body).
        final Widget moduleStack = Column(
          children: [
            _StatusStrip(isNVG: isNVG, accent: accent, surface: surface),
            if (deadMan.isActive && !deadMan.isEmergencyAlertActive)
              Container(
                width: double.infinity,
                color: const Color(0xFFFF9500).withOpacity(0.18),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                child: Row(
                  children: [
                    const Icon(Icons.monitor_heart, color: Color(0xFFFF9500), size: 14),
                    const SizedBox(width: 8),
                    Text(
                      '☠️ VIGILADO: CAÍDA + INMOVILIZACIÓN (${DeadManSwitchService.immobilizedMinutes} min)',
                      style: const TextStyle(
                        color: Color(0xFFFFB340),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
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
                        '🚨 ${deadMan.emergencyLabel}! TRANSMITIENDO SOS EN ${deadMan.countdownSeconds}s — TOQUE PARA CANCELAR',
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
              // Cualquier toque del operador restablece el contador de
              // inmovilidad y cancela la ventana SOS si está abierta.
              child: Listener(
                onPointerDown: (_) => deadMan.registerInteraction(),
                child: IndexedStack(
                  index: _currentIndex,
                  children: _tabs,
                ),
              ),
            ),
          ],
        );

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: surface,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.menu, color: Colors.white70, size: 20),
              tooltip: 'Todos los módulos',
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            ),
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
              _PanicHoldButton(
                onTriggered: () {
                  EmergencyService().triggerPanic();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('🚨 PÁNICO ACTUADO: SOS transmitido a la base.'),
                      backgroundColor: Color(0xFFFF2D55),
                    ),
                  );
                },
              ),
            ],
          ),
          drawer: _AppDrawer(
            labels: _navLabels,
            icons: _navIcons,
            currentIndex: _currentIndex,
            accent: accent,
            surface: surface,
            onModuleSelected: (index) {
              setState(() => _currentIndex = index);
              _scaffoldKey.currentState?.closeDrawer();
            },
          ),
          body: useRail
              ? Row(
                  children: [
                    NavigationRail(
                      backgroundColor: surface,
                      selectedIndex: navIndex,
                      onDestinationSelected: (pos) =>
                          setState(() => _currentIndex = _primaryTabIndices[pos]),
                      labelType: NavigationRailLabelType.all,
                      destinations: [
                        for (final int tabIndex in _primaryTabIndices)
                          NavigationRailDestination(
                            icon: Icon(_navIcons[tabIndex]),
                            selectedIcon: Icon(_navIcons[tabIndex], color: accent),
                            label: Text(_navLabels[tabIndex]),
                          ),
                      ],
                    ),
                    const VerticalDivider(thickness: 1, width: 1),
                    Expanded(child: moduleStack),
                  ],
                )
              : moduleStack,
          bottomNavigationBar: useRail
              ? null
              : BottomNavigationBar(
                  currentIndex: navIndex,
                  onTap: (pos) => setState(() => _currentIndex = _primaryTabIndices[pos]),
                  backgroundColor: surface,
                  selectedItemColor: accent,
                  unselectedItemColor: isNVG ? const Color(0xFF660000) : Colors.white60,
                  type: BottomNavigationBarType.fixed,
                  selectedFontSize: 12,
                  unselectedFontSize: 12,
                  selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
                  items: [
                    for (final int tabIndex in _primaryTabIndices)
                      BottomNavigationBarItem(
                        icon: Icon(_navIcons[tabIndex]),
                        label: _navLabels[tabIndex],
                      ),
                  ],
                ),
        );
      },
    );
  }
}

/// Cajón de navegación con TODOS los módulos y filtro de búsqueda táctico en vivo.
class _AppDrawer extends StatefulWidget {
  final List<String> labels;
  final List<IconData> icons;
  final int currentIndex;
  final Color accent;
  final Color surface;
  final ValueChanged<int> onModuleSelected;

  const _AppDrawer({
    required this.labels,
    required this.icons,
    required this.currentIndex,
    required this.accent,
    required this.surface,
    required this.onModuleSelected,
  });

  @override
  State<_AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<_AppDrawer> {
  final TextEditingController _searchController = TextEditingController();
  String _filter = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<int> filteredIndices = [];
    for (int i = 0; i < widget.labels.length; i++) {
      if (_filter.isEmpty || widget.labels[i].toLowerCase().contains(_filter.toLowerCase())) {
        filteredIndices.add(i);
      }
    }

    return Drawer(
      backgroundColor: widget.surface,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              color: widget.accent.withOpacity(0.08),
              child: Row(
                children: [
                  const Icon(Icons.linear_scale, color: Colors.white70, size: 16),
                  const SizedBox(width: 10),
                  Text(
                    'MÓDULOS COBALTO C4I',
                    style: TextStyle(
                      color: widget.accent,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            // BUSCADOR RÁPIDO DE MÓDULOS
            Padding(
              padding: const EdgeInsets.all(10.0),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: '🔍 Buscar módulo...',
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.black26,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: widget.accent.withOpacity(0.3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: widget.accent.withOpacity(0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: widget.accent),
                  ),
                ),
                onChanged: (val) {
                  setState(() => _filter = val.trim());
                },
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: filteredIndices.length,
                itemBuilder: (context, idx) {
                  final i = filteredIndices[idx];
                  final bool selected = i == widget.currentIndex;
                  return ListTile(
                    leading: Icon(widget.icons[i], color: selected ? widget.accent : Colors.white54),
                    title: Text(
                      widget.labels[i],
                      style: TextStyle(
                        color: selected ? widget.accent : Colors.white,
                        fontSize: 14,
                        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    selected: selected,
                    selectedTileColor: widget.accent.withOpacity(0.12),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      widget.onModuleSelected(i);
                    },
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

/// Franja de estado táctica compacta: conmutador de sigilo (NVG), respuesta háptica
/// y Chip de Enlace LAN / Autodescubrimiento Zero-Conf en vivo.
class _StatusStrip extends StatefulWidget {
  final bool isNVG;
  final Color accent;
  final Color surface;

  const _StatusStrip({required this.isNVG, required this.accent, required this.surface});

  @override
  State<_StatusStrip> createState() => _StatusStripState();
}

class _StatusStripState extends State<_StatusStrip> {
  bool _isDiscovering = false;

  Future<void> _handleQuickDiscovery() async {
    HapticFeedback.mediumImpact();
    setState(() => _isDiscovering = true);

    final result = await NetworkDiscoveryService.discoverHub(autoApply: true);

    if (!mounted) return;
    setState(() => _isDiscovering = false);

    final messenger = ScaffoldMessenger.of(context);
    if (result.success && result.hubUrl != null) {
      final host = result.hubUrl!.replaceAll('http://', '').replaceAll(':8083', '');
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '✅ HUB COBALTO ENCONTRADO EN LAN: $host',
            style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          ),
          backgroundColor: const Color(0xFF00E5FF),
        ),
      );
    } else {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('📱 MODO AUTÓNOMO LOCAL (HUB no detectado en LAN)'),
          backgroundColor: Color(0xFFFF9500),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final String currentHost = ApiConfig.baseUrl.replaceAll('http://', '').replaceAll(':8083', '');
    final bool hasHost = currentHost.isNotEmpty && currentHost != 'localhost';

    return Container(
      width: double.infinity,
      color: widget.isNVG ? widget.surface.withOpacity(0.4) : widget.surface,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              HapticFeedback.selectionClick();
              StealthService().toggleStealth();
            },
            icon: Icon(
              widget.isNVG ? Icons.wb_sunny : Icons.visibility_off,
              color: widget.isNVG ? const Color(0xFFFF1E1E) : Colors.white70,
              size: 18,
            ),
            tooltip: 'Conmutar Modo Sigilo (NVG)',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
          ),
          Text(
            widget.isNVG ? 'SIGILO NVG ACTIVO' : 'MODO C4I NOMINAL',
            style: TextStyle(
              color: widget.isNVG ? const Color(0xFFFF6666) : widget.accent,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          // CHIP INTERACTIVO DE ENLACE RED / HUB PC
          GestureDetector(
            onTap: _isDiscovering ? null : _handleQuickDiscovery,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _isDiscovering
                    ? const Color(0xFFFF9500).withOpacity(0.2)
                    : (hasHost ? widget.accent.withOpacity(0.12) : Colors.white10),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: _isDiscovering
                      ? const Color(0xFFFF9500)
                      : (hasHost ? widget.accent.withOpacity(0.4) : Colors.white24),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isDiscovering)
                    const SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFFFF9500)),
                    )
                  else
                    Icon(
                      hasHost ? Icons.wifi : Icons.wifi_off,
                      size: 11,
                      color: hasHost ? widget.accent : Colors.white54,
                    ),
                  const SizedBox(width: 4),
                  Text(
                    _isDiscovering
                        ? 'BUSCANDO HUB...'
                        : (hasHost ? 'HUB: $currentHost' : '📱 AUTÓNOMO'),
                    style: TextStyle(
                      color: hasHost ? widget.accent : Colors.white70,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Botón de pánico con retención de 3 segundos (anti-activación accidental).
/// Mientras se mantiene pulsado muestra la cuenta regresiva de armado.
class _PanicHoldButton extends StatefulWidget {
  final VoidCallback onTriggered;

  const _PanicHoldButton({required this.onTriggered});

  @override
  State<_PanicHoldButton> createState() => _PanicHoldButtonState();
}

class _PanicHoldButtonState extends State<_PanicHoldButton> {
  static const int _holdSeconds = 3;
  bool _pressed = false;
  double _progress = 0.0;

  void _startHold() {
    setState(() {
      _pressed = true;
      _progress = 0.0;
    });
    _tick();
  }

  void _tick() async {
    while (_pressed && mounted && _progress < 1.0) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (!mounted) return;
      setState(() {
        _progress = (_progress + 0.05 / _holdSeconds).clamp(0.0, 1.0);
      });
    }
    if (_pressed && mounted && _progress >= 1.0) {
      widget.onTriggered();
    }
  }

  void _cancelHold() {
    if (!mounted) return;
    setState(() {
      _pressed = false;
      _progress = 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Mantener 3s para PÁNICO',
      child: GestureDetector(
        onTapDown: (_) => _startHold(),
        onTapUp: (_) => _cancelHold(),
        onTapCancel: _cancelHold,
        child: Container(
          margin: const EdgeInsets.only(right: 8),
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _pressed ? const Color(0xFFFF2D55) : const Color(0xFF1E293B),
            border: Border.all(color: const Color(0xFFFF2D55), width: 1.5),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (_pressed)
                CircularProgressIndicator(
                  value: _progress,
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              const Icon(Icons.sos, color: Color(0xFFFF2D55), size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

