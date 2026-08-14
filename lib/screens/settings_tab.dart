import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../services/cobalto_api_service.dart';
import '../services/local_extractor_service.dart';
import '../services/notification_service.dart';
import '../services/gps_service.dart';
import '../services/voice_service.dart';
import '../services/crypto_vault_service.dart';
import '../services/tactical_camera_service.dart';
import '../services/widget_service.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // 1. Enlace & Servidor
  late TextEditingController _urlController;
  late TextEditingController _userController;
  late TextEditingController _passController;
  String _autoSyncInterval = '30';
  bool _useAutonomousMode = true;

  // 2. Palabras Clave (Chips)
  List<String> _keywords = [];
  final TextEditingController _newKeywordController = TextEditingController();

  // 3. Fuentes RSS/Telegram
  List<Map<String, String>> _sources = [];
  final TextEditingController _newSrcNameController = TextEditingController();
  final TextEditingController _newSrcUrlController = TextEditingController();

  // 4. Motor IA & Ollama
  late TextEditingController _ollamaHostController;
  String _selectedOllamaModel = 'llama3.2';

  // 5. Parámetros Situacionales
  late TextEditingController _maxAgeHoursController;
  late TextEditingController _defconController;

  bool _isSaving = false;
  bool? _isConnected;
  String _statusMessage = 'Cargando ajustes tácticos...';

  final List<String> _ollamaModels = [
    'llama3.2',
    'mistral',
    'deepseek-r1',
    'gemma:2b',
    'llama3.1',
    'codellama',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);

    _urlController = TextEditingController(text: ApiConfig.baseUrl);
    _userController = TextEditingController(text: ApiConfig.username);
    _passController = TextEditingController(text: ApiConfig.password);

    _ollamaHostController = TextEditingController(text: ApiConfig.ollamaHost);
    _selectedOllamaModel = ApiConfig.ollamaModel;

    _maxAgeHoursController = TextEditingController(text: '48');
    _defconController = TextEditingController(text: '5');

    _loadAllSettings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAllSettings() async {
    final kw = await LocalExtractorService.getLocalKeywords();
    final src = await LocalExtractorService.getActiveSources();
    final isOk = await CobaltoApiService.testConnection();

    if (mounted) {
      setState(() {
        _keywords = List.from(kw);
        _sources = List.from(src);
        _isConnected = isOk;
        _statusMessage = isOk
            ? 'Sincronizado con Estación Base PC'
            : 'Modo Autónomo Local (Dispositivo)';
      });
    }
  }

  // --- MÉTODOS DE PALABRAS CLAVE ---
  void _addKeyword() {
    final text = _newKeywordController.text.trim().toLowerCase();
    if (text.isNotEmpty && !_keywords.contains(text)) {
      setState(() {
        _keywords.add(text);
        _newKeywordController.clear();
      });
      LocalExtractorService.saveLocalKeywords(_keywords);
    }
  }

  void _removeKeyword(String word) {
    setState(() {
      _keywords.remove(word);
    });
    LocalExtractorService.saveLocalKeywords(_keywords);
  }

  void _resetKeywordsDefault() async {
    final defaults = ['inteligencia', 'conflicto', 'seguridad', 'ciberataque', 'defensa', 'alerta', 'defcon', 'militar', 'sanciones', 'dolar', 'venezuela'];
    setState(() => _keywords = List.from(defaults));
    await LocalExtractorService.saveLocalKeywords(_keywords);
  }

  // --- MÉTODOS DE FUENTES ---
  void _addNewSource() async {
    final name = _newSrcNameController.text.trim();
    final url = _newSrcUrlController.text.trim();

    if (name.isNotEmpty && url.isNotEmpty) {
      await LocalExtractorService.addCustomSource(name, url);
      _newSrcNameController.clear();
      _newSrcUrlController.clear();
      _loadAllSettings();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Fuente "$name" añadida a la App'), backgroundColor: const Color(0xFF00FFAA)),
        );
      }
    }
  }

  void _removeSource(String url) async {
    await LocalExtractorService.removeCustomSource(url);
    _loadAllSettings();
  }

  // --- GUARDADO GENERAL ---
  Future<void> _saveAllSettings() async {
    setState(() => _isSaving = true);

    await ApiConfig.saveConfig(
      _urlController.text.trim(),
      _userController.text.trim(),
      _passController.text.trim(),
    );

    await ApiConfig.saveOllamaConfig(
      _ollamaHostController.text.trim(),
      _selectedOllamaModel,
    );

    await LocalExtractorService.saveLocalKeywords(_keywords);

    final isOk = await CobaltoApiService.testConnection();
    if (isOk) {
      Map<String, dynamic> payload = {
        'KEYWORDS': _keywords,
        'ENTRY_MAX_AGE_HOURS': int.tryParse(_maxAgeHoursController.text) ?? 48,
        'DEFCON_LEVEL': int.tryParse(_defconController.text) ?? 5,
      };
      await CobaltoApiService.saveSystemConfig(payload);
    }

    if (mounted) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isOk ? '✅ Ajustes sincronizados con la Base PC' : '📱 Ajustes guardados en el Teléfono'),
          backgroundColor: const Color(0xFF00FFAA),
        ),
      );
    }
  }

  Future<void> _clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cached_sitrep_news');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('🧹 Caché SitRep vaciado correctamente'), backgroundColor: Color(0xFF00E5FF)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0B10),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Container(
          color: const Color(0xFF10131D),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            indicatorColor: const Color(0xFF00E5FF),
            labelColor: const Color(0xFF00E5FF),
            unselectedLabelColor: Colors.white38,
            labelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
            tabs: const [
              Tab(icon: Icon(Icons.wifi, size: 16), text: 'ENLACE'),
              Tab(icon: Icon(Icons.style, size: 16), text: 'PALABRAS'),
              Tab(icon: Icon(Icons.rss_feed, size: 16), text: 'FUENTES'),
              Tab(icon: Icon(Icons.psychology, size: 16), text: 'OLLAMA IA'),
              Tab(icon: Icon(Icons.tune, size: 16), text: 'PARÁMETROS'),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          // Banner de Estado
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: const Color(0xFF141824),
            child: Row(
              children: [
                Icon(
                  _isConnected == true ? Icons.check_circle : Icons.cell_tower,
                  color: _isConnected == true ? const Color(0xFF00FFAA) : const Color(0xFFFF9500),
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _statusMessage,
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'monospace'),
                  ),
                ),
              ],
            ),
          ),

          // Sub-Pestañas
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildLinkTab(),
                _buildKeywordsTab(),
                _buildSourcesTab(),
                _buildOllamaTab(),
                _buildParametersTab(),
              ],
            ),
          ),

          // Botón Guardar Flotante Inferior
          Container(
            padding: const EdgeInsets.all(10),
            color: const Color(0xFF10131D),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveAllSettings,
                icon: _isSaving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : const Icon(Icons.save, size: 18),
                label: Text(
                  _isSaving ? 'GUARDANDO...' : 'GUARDAR CONFIGURACIÓN TÁCTICA',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, fontFamily: 'monospace'),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E5FF),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- SUB-PESTAÑA 1: MODO ENLACE ---
  Widget _buildLinkTab() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _sectionTitle('📡 MODO OPERATIVO DE ENLACE'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _modeTile(
                '📱 MODO AUTÓNOMO',
                'Operar solo en el teléfono sin servidor.',
                _useAutonomousMode,
                () => setState(() => _useAutonomousMode = true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _modeTile(
                '📡 ENLACE PC',
                'Conectar con la PC Estación Base.',
                !_useAutonomousMode,
                () => setState(() => _useAutonomousMode = false),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _sectionTitle('⏱️ FRECUENCIA DE EXTRACCIÓN AUTOMÁTICA'),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF141824),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white10),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _autoSyncInterval,
              dropdownColor: const Color(0xFF141824),
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: '15', child: Text('⏱️ Cada 15 Minutos (Alta Intensidad)', style: TextStyle(color: Colors.white, fontSize: 12))),
                DropdownMenuItem(value: '30', child: Text('⏱️ Cada 30 Minutos (Recomendado)', style: TextStyle(color: Colors.white, fontSize: 12))),
                DropdownMenuItem(value: '60', child: Text('⏱️ Cada 1 Hora', style: TextStyle(color: Colors.white, fontSize: 12))),
                DropdownMenuItem(value: '120', child: Text('⏱️ Cada 2 Horas', style: TextStyle(color: Colors.white, fontSize: 12))),
                DropdownMenuItem(value: '0', child: Text('⏹️ Solo Manual (Bajo demanda)', style: TextStyle(color: Colors.white, fontSize: 12))),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _autoSyncInterval = val);
              },
            ),
          ),
        ),
        if (!_useAutonomousMode) ...[
          const SizedBox(height: 14),
          _sectionTitle('💻 DIRECCIÓN Y CREDENCIALES DE BASE (PC)'),
          const SizedBox(height: 6),
          _textField(_urlController, 'Dirección IP o Servidor Central', Icons.link),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _textField(_userController, 'Usuario', Icons.person)),
              const SizedBox(width: 8),
              Expanded(child: _textField(_passController, 'Contraseña', Icons.lock, obscureText: true)),
            ],
          ),
        ],
      ],
    );
  }

  // --- SUB-PESTAÑA 2: PALABRAS CLAVE (CHIPS INTERACTIVOS) ---
  Widget _buildKeywordsTab() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _sectionTitle('🔍 PALABRAS CLAVE DE INTELIGENCIA (CHIPS TÁCTICOS)'),
        const SizedBox(height: 6),
        const Text(
          'Las noticias y alertas serán evaluadas en vivo contra estas palabras clave.',
          style: TextStyle(color: Colors.white54, fontSize: 11),
        ),
        const SizedBox(height: 10),

        // Campo para Agregar Palabra Clave
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _newKeywordController,
                style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText: 'Añadir palabra clave...',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: const Color(0xFF141824),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                ),
                onSubmitted: (_) => _addKeyword(),
              ),
            ),
            const SizedBox(width: 6),
            ElevatedButton(
              onPressed: _addKeyword,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E5FF),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('+ AGREGAR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, fontFamily: 'monospace')),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Chips Desplegados
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF141824),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.3)),
          ),
          child: _keywords.isEmpty
              ? const Text('Sin palabras clave registradas.', style: TextStyle(color: Colors.white38, fontSize: 11))
              : Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _keywords.map((word) {
                    return Chip(
                      backgroundColor: const Color(0xFF00E5FF).withOpacity(0.12),
                      side: BorderSide(color: const Color(0xFF00E5FF).withOpacity(0.4)),
                      label: Text(
                        word.toUpperCase(),
                        style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                      ),
                      deleteIcon: const Icon(Icons.close, size: 14, color: Color(0xFFFF2D55)),
                      onDeleted: () => _removeKeyword(word),
                    );
                  }).toList(),
                ),
        ),
        const SizedBox(height: 10),

        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _resetKeywordsDefault,
            icon: const Icon(Icons.refresh, size: 14, color: Colors.white54),
            label: const Text('RESTAURAR DEFECTO', style: TextStyle(color: Colors.white54, fontSize: 10, fontFamily: 'monospace')),
          ),
        ),
      ],
    );
  }

  // --- SUB-PESTAÑA 3: FUENTES DE INGESTA (RSS & TELEGRAM) ---
  Widget _buildSourcesTab() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _sectionTitle('📰 FUENTES DE INGESTA (RSS & TELEGRAM PÚBLICO)'),
        const SizedBox(height: 6),
        const Text(
          'Puedes agregar tus propios canales de Telegram (t.me/s/canal) o feeds RSS.',
          style: TextStyle(color: Colors.white54, fontSize: 11),
        ),
        const SizedBox(height: 10),

        // Formulario Agregar Fuente
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF141824),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            children: [
              _textField(_newSrcNameController, 'Nombre de la Fuente (Ej. Canal X)', Icons.label),
              const SizedBox(height: 6),
              _textField(_newSrcUrlController, 'URL (RSS xml o t.me/s/nombre_canal)', Icons.link),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _addNewSource,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('AÑADIR NUEVA FUENTE DE EXTRACCIÓN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00FFAA),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        _sectionTitle('LISTA DE FUENTES ACTIVAS (${_sources.length}):'),
        const SizedBox(height: 6),

        ..._sources.map((src) {
          final isTg = src['url']!.contains('t.me/s/');
          return Card(
            margin: const EdgeInsets.only(bottom: 6),
            color: const Color(0xFF141824),
            child: ListTile(
              dense: true,
              leading: Icon(
                isTg ? Icons.send : Icons.rss_feed,
                color: isTg ? const Color(0xFF00E5FF) : Colors.orange,
                size: 18,
              ),
              title: Text(src['name']!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
              subtitle: Text(src['url']!, style: const TextStyle(color: Colors.white38, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 16),
                onPressed: () => _removeSource(src['url']!),
              ),
            ),
          );
        }),
      ],
    );
  }

  // --- SUB-PESTAÑA 4: MOTOR IA & OLLAMA ---
  Widget _buildOllamaTab() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _sectionTitle('🤖 CONFIGURACIÓN DE OLLAMA & IA LOCAL'),
        const SizedBox(height: 6),
        const Text(
          'Configura la dirección del servidor Ollama para inferencia local RAG.',
          style: TextStyle(color: Colors.white54, fontSize: 11),
        ),
        const SizedBox(height: 10),

        _textField(_ollamaHostController, 'Host Ollama (Ej. http://192.168.1.50:11434)', Icons.dns),
        const SizedBox(height: 12),

        _sectionTitle('MODELO OLLAMA SELECCIONADO:'),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF141824),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white10),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedOllamaModel,
              dropdownColor: const Color(0xFF141824),
              isExpanded: true,
              items: _ollamaModels.map((m) {
                return DropdownMenuItem(
                  value: m,
                  child: Text('🧠 $m', style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace')),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedOllamaModel = val);
              },
            ),
          ),
        ),
      ],
    );
  }

  // --- SUB-PESTAÑA 5: PARÁMETROS & CACHÉ ---
  Widget _buildParametersTab() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _sectionTitle('⚙️ PARÁMETROS DE RELEVANCIA Y DEFCON'),
        const SizedBox(height: 8),

        _textField(_defconController, 'Nivel DEFCON Inicial (1 al 5)', Icons.shield),
        const SizedBox(height: 10),

        _textField(_maxAgeHoursController, 'Antigüedad Máxima de Noticias (Horas)', Icons.hourglass_bottom),
        const SizedBox(height: 16),

        _sectionTitle('🔔 PRUEBA DE NOTIFICACIONES Y BURBUJA FLOTANTE'),
        const SizedBox(height: 6),
        ElevatedButton.icon(
          onPressed: () async {
            await NotificationService.showAlertNotification(
              title: 'CIBERATAQUE DETECTADO (PRUEBA)',
              body: 'Notificación de alerta táctica recibida con éxito en la barra de estado de Android.',
              level: 'CRÍTICA',
              showFloatingOverlay: false,
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('🔔 Notificación enviada a la barra de estado.'),
                  backgroundColor: Color(0xFF00E5FF),
                ),
              );
            }
          },
          icon: const Icon(Icons.notifications_active, size: 18),
          label: const Text('ENVIAR NOTIFICACIÓN A BARRA DE ESTADO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00E5FF).withOpacity(0.2),
            foregroundColor: const Color(0xFF00E5FF),
            side: const BorderSide(color: Color(0xFF00E5FF)),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed: () async {
            await NotificationService.showFloatingBubble(
              title: 'INCIDENTE CRÍTICO OSINT',
              body: 'Superposición táctica activada sobre el sistema Android. Toca CERRAR HUD para ocultar.',
              level: 'DEFCON 2',
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('🫧 Ventana / HUD flotante activada sobre pantalla.'),
                  backgroundColor: Color(0xFF00FFAA),
                ),
              );
            }
          },
          icon: const Icon(Icons.bubble_chart, size: 18),
          label: const Text('DESPLEGAR BURBUJA / HUD FLOTANTE (OVERLAY)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00FFAA).withOpacity(0.2),
            foregroundColor: const Color(0xFF00FFAA),
            side: const BorderSide(color: Color(0xFF00FFAA)),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed: () async {
            final pos = await GpsService.getCurrentPosition();
            if (pos != null) {
              await GpsService.evaluateGeofenceAlert(
                eventLat: pos.latitude + 0.01,
                eventLon: pos.longitude + 0.01,
                title: 'INCIDENTE DE PROXIMIDAD (PRUEBA)',
                level: 'CRÍTICA',
                radiusKm: 15.0,
              );
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('🛰️ GPS Activo: ${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}. Geocerca verificada.'),
                    backgroundColor: const Color(0xFF00FFAA),
                  ),
                );
              }
            } else {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('⚠️ No se pudo obtener la posición GPS. Revisa permisos.'),
                    backgroundColor: Color(0xFFFF2D55),
                  ),
                );
              }
            }
          },
          icon: const Icon(Icons.my_location, size: 18),
          label: const Text('PROBAR GEOCERCA Y SENSORES GPS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF9500).withOpacity(0.2),
            foregroundColor: const Color(0xFFFF9500),
            side: const BorderSide(color: Color(0xFFFF9500)),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed: () async {
            await VoiceService.speakAlert(
              title: 'PRUEBA DE SINTETIZADOR DE VOZ',
              body: 'El canal auditivo militar de COBALTO se encuentra completamente activo y listo para operarse con manos libres.',
              level: 'DEFCON 1',
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('🔊 Reproduciendo lectura por voz sintética militar.'),
                  backgroundColor: Color(0xFF00E5FF),
                ),
              );
            }
          },
          icon: const Icon(Icons.record_voice_over, size: 18),
          label: const Text('PROBAR SINTETIZADOR Y LECTURA DE VOZ (TTS)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFBF5AF2).withOpacity(0.2),
            foregroundColor: const Color(0xFFBF5AF2),
            side: const BorderSide(color: Color(0xFFBF5AF2)),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed: () async {
            final vaultStatus = await CryptoVaultService.checkVaultStatus();
            if (mounted) {
              final isSecure = vaultStatus['secure'] == true;
              final algo = vaultStatus['key_algorithm'] ?? 'AES-256';
              final bits = vaultStatus['key_bits'] ?? 256;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    isSecure
                        ? '🔒 Bóveda de Datos Cifrada Activa [$algo / $bits-bits]. Clave protegida en Android KeyStore.'
                        : '⚠️ Bóveda local operando en modo fallback.',
                  ),
                  backgroundColor: isSecure ? const Color(0xFF00FFAA) : const Color(0xFFFF9500),
                ),
              );
            }
          },
          icon: const Icon(Icons.security, size: 18),
          label: const Text('VERIFICAR BÓVEDA CIFRADA (AES-256 / KEYSTORE)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF30D158).withOpacity(0.2),
            foregroundColor: const Color(0xFF30D158),
            side: const BorderSide(color: Color(0xFF30D158)),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed: () async {
            final pos = await GpsService.getCurrentPosition();
            final lat = pos?.latitude ?? 10.4806;
            final lon = pos?.longitude ?? -66.9036;

            final photo = await TacticalCameraService.captureTelemetryPhoto(
              lat: lat,
              lon: lon,
              classification: 'CONFIDENCIAL // OPERADOR C4I',
            );

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    photo != null
                        ? '📷 Fotografía estampada con telemetría GPS [$lat, $lon].'
                        : '⚠️ No se pudo inicializar la cámara o permiso denegado.',
                  ),
                  backgroundColor: photo != null ? const Color(0xFF00E5FF) : const Color(0xFFFF2D55),
                ),
              );
            }
          },
          icon: const Icon(Icons.camera_alt, size: 18),
          label: const Text('PROBAR CÁMARA TÁCTICA Y TELEMETRÍA GPS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF64D2FF).withOpacity(0.2),
            foregroundColor: const Color(0xFF64D2FF),
            side: const BorderSide(color: Color(0xFF64D2FF)),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed: () async {
            await WidgetService.syncWidgetFromLocalDb();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('📱 Widget Nativo de Android actualizado con inteligencia SitRep local.'),
                  backgroundColor: Color(0xFF00FFAA),
                ),
              );
            }
          },
          icon: const Icon(Icons.widgets, size: 18),
          label: const Text('PROBAR ACTUALIZACIÓN DE WIDGET DE PANTALLA DE INICIO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF5E5CE6).withOpacity(0.2),
            foregroundColor: const Color(0xFF5E5CE6),
            side: const BorderSide(color: Color(0xFF5E5CE6)),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
        const SizedBox(height: 16),

        _sectionTitle('🧹 LIMPIEZA DE MEMORIA LOCAL'),
        const SizedBox(height: 6),
        ElevatedButton.icon(
          onPressed: _clearCache,
          icon: const Icon(Icons.delete_sweep, size: 18),
          label: const Text('VACIAR CACHÉ SITREP DEL TELÉFONO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF2D55).withOpacity(0.2),
            foregroundColor: const Color(0xFFFF2D55),
            side: const BorderSide(color: Color(0xFFFF2D55)),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ],
    );
  }

  // --- COMPONENTES VISUALES ---
  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFF00E5FF),
        fontSize: 11,
        fontWeight: FontWeight.bold,
        fontFamily: 'monospace',
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _modeTile(String title, String desc, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00E5FF).withOpacity(0.15) : const Color(0xFF141824),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? const Color(0xFF00E5FF) : Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(color: isSelected ? const Color(0xFF00E5FF) : Colors.white, fontWeight: FontWeight.bold, fontSize: 11, fontFamily: 'monospace')),
            const SizedBox(height: 3),
            Text(desc, style: const TextStyle(color: Colors.white54, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _textField(TextEditingController controller, String label, IconData icon, {bool obscureText = false}) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 11),
        prefixIcon: Icon(icon, color: const Color(0xFF00E5FF), size: 16),
        filled: true,
        fillColor: const Color(0xFF141824),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
      ),
    );
  }
}
