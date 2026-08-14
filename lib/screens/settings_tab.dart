import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../services/crypto_vault_service.dart';
import '../services/dead_man_switch_service.dart';
import '../services/gps_service.dart';
import '../services/local_auth_service.dart';
import '../services/notification_service.dart';
import '../services/settings_persistence_service.dart';
import '../services/stealth_service.dart';
import '../services/tactical_camera_service.dart';
import '../services/voice_service.dart';
import '../services/widget_service.dart';
import '../widgets/operator_credentials_dialog.dart';
import '../widgets/settings_components.dart';

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
  String _operatorUsername = '';

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
    final result = await SettingsPersistenceService.loadSettings();
    final operatorName = await LocalAuthService.getUsername() ?? '';

    if (mounted) {
      setState(() {
        _keywords = result.keywords;
        _sources = result.sources;
        _isConnected = result.connected;
        _operatorUsername = operatorName;
        _statusMessage = result.connected == true
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
      SettingsPersistenceService.saveKeywords(_keywords);
    }
  }

  void _removeKeyword(String word) {
    setState(() {
      _keywords.remove(word);
    });
    SettingsPersistenceService.saveKeywords(_keywords);
  }

  Future<void> _resetKeywordsDefault() async {
    const defaults = ['inteligencia', 'conflicto', 'seguridad', 'ciberataque', 'defensa', 'alerta', 'defcon', 'militar', 'sanciones', 'dolar', 'venezuela'];
    setState(() => _keywords = List.from(defaults));
    await SettingsPersistenceService.saveKeywords(_keywords);
  }

  // --- MÉTODOS DE FUENTES ---
  Future<void> _addNewSource() async {
    final name = _newSrcNameController.text.trim();
    final url = _newSrcUrlController.text.trim();

    if (name.isNotEmpty && url.isNotEmpty) {
      await SettingsPersistenceService.addSource(name, url);
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

  Future<void> _removeSource(String url) async {
    await SettingsPersistenceService.removeSource(url);
    _loadAllSettings();
  }

  // --- EDICIÓN DE OPERADOR LOCAL ---

  Widget _buildOperatorCard() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF141824),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.badge_outlined, color: Color(0xFF00E5FF), size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _operatorUsername.isEmpty ? 'Sin operador registrado' : 'Operador: $_operatorUsername',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TacticalActionButton(
                  icon: Icons.person,
                  label: 'CAMBIAR NOMBRE',
                  color: const Color(0xFF00E5FF),
                  onPressed: _operatorUsername.isEmpty ? null : () => _editOperatorUsername(),
                  enabled: _operatorUsername.isNotEmpty,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TacticalActionButton(
                  icon: Icons.password,
                  label: 'CAMBIAR CLAVE',
                  color: const Color(0xFF00FFAA),
                  onPressed: _operatorUsername.isEmpty ? null : () => _editOperatorPassword(),
                  enabled: _operatorUsername.isNotEmpty,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _editOperatorUsername() async {
    final result = await OperatorCredentialsDialog.show(
      context,
      editingUsername: true,
      currentUsername: _operatorUsername,
    );
    if (result == OperatorEditResult.changed) {
      final newName = await LocalAuthService.getUsername() ?? '';
      await ApiConfig.saveConfig(
        ApiConfig.baseUrl,
        newName,
        ApiConfig.password,
        token: ApiConfig.authToken,
      );
      await _loadAllSettings();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Nombre de operador actualizado.'),
            backgroundColor: Color(0xFF00FFAA),
          ),
        );
      }
    }
  }

  Future<void> _editOperatorPassword() async {
    final result = await OperatorCredentialsDialog.show(
      context,
      editingUsername: false,
      currentUsername: _operatorUsername,
    );
    if (result == OperatorEditResult.changed) {
      await _loadAllSettings();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Contraseña de operador actualizada.'),
            backgroundColor: Color(0xFF00FFAA),
          ),
        );
      }
    }
  }

  // --- GUARDADO GENERAL ---
  Future<void> _saveAllSettings() async {
    setState(() => _isSaving = true);

    final isOk = await SettingsPersistenceService.saveAll(
      url: _urlController.text.trim(),
      user: _userController.text.trim(),
      pass: _passController.text.trim(),
      ollamaHost: _ollamaHostController.text.trim(),
      ollamaModel: _selectedOllamaModel,
      keywords: _keywords,
      maxAgeHours: int.tryParse(_maxAgeHoursController.text) ?? 48,
      defconLevel: int.tryParse(_defconController.text) ?? 5,
    );

    if (!mounted) return;
    setState(() => _isSaving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isOk ? '✅ Ajustes sincronizados con la Base PC' : '📱 Ajustes guardados en el Teléfono'),
        backgroundColor: const Color(0xFF00FFAA),
      ),
    );
  }

  Future<void> _clearCache() async {
    await SettingsPersistenceService.clearSitrepCache();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('🧹 Caché SitRep vaciado correctamente'), backgroundColor: Color(0xFF00E5FF)),
    );
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
        const SettingsSectionTitle('🪪 OPERADOR LOCAL (ACCESO A LA APP)'),
        const SizedBox(height: 6),
        _buildOperatorCard(),
        const SizedBox(height: 16),
        const SettingsSectionTitle('📡 MODO OPERATIVO DE ENLACE'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: SettingsModeTile(
                title: '📱 MODO AUTÓNOMO',
                description: 'Operar solo en el teléfono sin servidor.',
                isSelected: _useAutonomousMode,
                onTap: () => setState(() => _useAutonomousMode = true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SettingsModeTile(
                title: '📡 ENLACE PC',
                description: 'Conectar con la PC Estación Base.',
                isSelected: !_useAutonomousMode,
                onTap: () => setState(() => _useAutonomousMode = false),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const SettingsSectionTitle('⏱️ FRECUENCIA DE EXTRACCIÓN AUTOMÁTICA'),
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
          const SettingsSectionTitle('💻 DIRECCIÓN Y CREDENCIALES DE BASE (PC)'),
          const SizedBox(height: 6),
          SettingsTextField(_urlController, label: 'Dirección IP o Servidor Central', icon: Icons.link),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: SettingsTextField(_userController, label: 'Usuario', icon: Icons.person)),
              const SizedBox(width: 8),
              Expanded(child: SettingsTextField(_passController, label: 'Contraseña', icon: Icons.lock, obscureText: true)),
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
        const SettingsSectionTitle('🔍 PALABRAS CLAVE DE INTELIGENCIA (CHIPS TÁCTICOS)'),
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
        const SettingsSectionTitle('📰 FUENTES DE INGESTA (RSS & TELEGRAM PÚBLICO)'),
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
              SettingsTextField(_newSrcNameController, label: 'Nombre de la Fuente (Ej. Canal X)', icon: Icons.label),
              const SizedBox(height: 6),
              SettingsTextField(_newSrcUrlController, label: 'URL (RSS xml o t.me/s/nombre_canal)', icon: Icons.link),
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

        SettingsSectionTitle('LISTA DE FUENTES ACTIVAS (${_sources.length}):'),
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
        const SettingsSectionTitle('🤖 CONFIGURACIÓN DE OLLAMA & IA LOCAL'),
        const SizedBox(height: 6),
        const Text(
          'Configura la dirección del servidor Ollama para inferencia local RAG.',
          style: TextStyle(color: Colors.white54, fontSize: 11),
        ),
        const SizedBox(height: 10),

        SettingsTextField(_ollamaHostController, label: 'Host Ollama (Ej. http://192.168.1.50:11434)', icon: Icons.dns),
        const SizedBox(height: 12),

        const SettingsSectionTitle('MODELO OLLAMA SELECCIONADO:'),
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
        const SettingsSectionTitle('⚙️ PARÁMETROS DE RELEVANCIA Y DEFCON'),
        const SizedBox(height: 8),

        SettingsTextField(_defconController, label: 'Nivel DEFCON Inicial (1 al 5)', icon: Icons.shield),
        const SizedBox(height: 10),

        SettingsTextField(_maxAgeHoursController, label: 'Antigüedad Máxima de Noticias (Horas)', icon: Icons.hourglass_bottom),
        const SizedBox(height: 16),

        const SettingsSectionTitle('🔔 PRUEBA DE NOTIFICACIONES Y BURBUJA FLOTANTE'),
        const SizedBox(height: 6),
        TacticalActionButton(
          icon: Icons.notifications_active,
          label: 'ENVIAR NOTIFICACIÓN A BARRA DE ESTADO',
          color: const Color(0xFF00E5FF),
          onPressed: _testNotification,
        ),
        const SizedBox(height: 8),
        TacticalActionButton(
          icon: Icons.bubble_chart,
          label: 'DESPLEGAR BURBUJA / HUD FLOTANTE (OVERLAY)',
          color: const Color(0xFF00FFAA),
          onPressed: _testFloatingBubble,
        ),
        const SizedBox(height: 8),
        TacticalActionButton(
          icon: Icons.my_location,
          label: 'PROBAR GEOCERCA Y SENSORES GPS',
          color: const Color(0xFFFF9500),
          onPressed: _testGeofence,
        ),
        const SizedBox(height: 8),
        TacticalActionButton(
          icon: Icons.record_voice_over,
          label: 'PROBAR SINTETIZADOR Y LECTURA DE VOZ (TTS)',
          color: const Color(0xFFBF5AF2),
          onPressed: _testVoice,
        ),
        const SizedBox(height: 8),
        TacticalActionButton(
          icon: Icons.security,
          label: 'VERIFICAR BÓVEDA CIFRADA (AES-256 / KEYSTORE)',
          color: const Color(0xFF30D158),
          onPressed: _testVault,
        ),
        const SizedBox(height: 8),
        TacticalActionButton(
          icon: Icons.camera_alt,
          label: 'PROBAR CÁMARA TÁCTICA Y TELEMETRÍA GPS',
          color: const Color(0xFF64D2FF),
          onPressed: _testTacticalCamera,
        ),
        const SizedBox(height: 8),
        TacticalActionButton(
          icon: Icons.widgets,
          label: 'PROBAR ACTUALIZACIÓN DE WIDGET DE PANTALLA DE INICIO',
          color: const Color(0xFF5E5CE6),
          onPressed: _testWidgetSync,
        ),
        const SizedBox(height: 8),
        TacticalActionButton(
          icon: Icons.visibility_off,
          label: 'CONMUTAR MODO SIGILO / VISIÓN NOCTURNA (NVG)',
          color: const Color(0xFFFF3B30),
          onPressed: _toggleStealth,
        ),
        const SizedBox(height: 8),
        TacticalActionButton(
          icon: Icons.warning_amber_rounded,
          label: 'PROBAR MONITOR HOMBRE MUERTO / INMOVILIDAD (SOS)',
          color: const Color(0xFFFF9500),
          onPressed: _toggleDeadManSwitch,
        ),
        const SizedBox(height: 16),

        const SettingsSectionTitle('🧹 LIMPIEZA DE MEMORIA LOCAL'),
        const SizedBox(height: 6),
        TacticalActionButton(
          icon: Icons.delete_sweep,
          label: 'VACIAR CACHÉ SITREP DEL TELÉFONO',
          color: const Color(0xFFFF2D55),
          onPressed: _clearCache,
        ),
      ],
    );
  }

  // --- ACCIONES DE PRUEBA TÁCTICA (PARÁMETROS) ---
  Future<void> _testNotification() async {
    await NotificationService.showAlertNotification(
      title: 'CIBERATAQUE DETECTADO (PRUEBA)',
      body: 'Notificación de alerta táctica recibida con éxito en la barra de estado de Android.',
      level: 'CRÍTICA',
      showFloatingOverlay: false,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🔔 Notificación enviada a la barra de estado.'),
        backgroundColor: Color(0xFF00E5FF),
      ),
    );
  }

  Future<void> _testFloatingBubble() async {
    await NotificationService.showFloatingBubble(
      title: 'INCIDENTE CRÍTICO OSINT',
      body: 'Superposición táctica activada sobre el sistema Android. Toca CERRAR HUD para ocultar.',
      level: 'DEFCON 2',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🫧 Ventana / HUD flotante activada sobre pantalla.'),
        backgroundColor: Color(0xFF00FFAA),
      ),
    );
  }

  Future<void> _testGeofence() async {
    final pos = await GpsService.getCurrentPosition();
    if (pos != null) {
      await GpsService.evaluateGeofenceAlert(
        eventLat: pos.latitude + 0.01,
        eventLon: pos.longitude + 0.01,
        title: 'INCIDENTE DE PROXIMIDAD (PRUEBA)',
        level: 'CRÍTICA',
        radiusKm: 15.0,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🛰️ GPS Activo: ${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}. Geocerca verificada.'),
          backgroundColor: const Color(0xFF00FFAA),
        ),
      );
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ No se pudo obtener la posición GPS. Revisa permisos.'),
          backgroundColor: Color(0xFFFF2D55),
        ),
      );
    }
  }

  Future<void> _testVoice() async {
    await VoiceService.speakAlert(
      title: 'PRUEBA DE SINTETIZADOR DE VOZ',
      body: 'El canal auditivo militar de COBALTO se encuentra completamente activo y listo para operarse con manos libres.',
      level: 'DEFCON 1',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🔊 Reproduciendo lectura por voz sintética militar.'),
        backgroundColor: Color(0xFF00E5FF),
      ),
    );
  }

  Future<void> _testVault() async {
    final vaultStatus = await CryptoVaultService.checkVaultStatus();
    if (!mounted) return;
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

  Future<void> _testTacticalCamera() async {
    final pos = await GpsService.getCurrentPosition();
    final lat = pos?.latitude ?? 10.4806;
    final lon = pos?.longitude ?? -66.9036;

    final photo = await TacticalCameraService.captureTelemetryPhoto(
      lat: lat,
      lon: lon,
      classification: 'CONFIDENCIAL // OPERADOR C4I',
    );

    if (!mounted) return;
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

  Future<void> _testWidgetSync() async {
    await WidgetService.syncWidgetFromLocalDb();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('📱 Widget Nativo de Android actualizado con inteligencia SitRep local.'),
        backgroundColor: Color(0xFF00FFAA),
      ),
    );
  }

  void _toggleStealth() {
    StealthService().toggleStealth();
    final isActive = StealthService().isStealthActive;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isActive ? '🥷 MODO SIGILO Y VISIÓN NOCTURNA (NVG) ACTIVADO.' : '☀️ MODO C4I ESTÁNDAR RESTAURADO.'),
        backgroundColor: isActive ? const Color(0xFFFF1E1E) : const Color(0xFF00E5FF),
      ),
    );
  }

  void _toggleDeadManSwitch() {
    final service = DeadManSwitchService();
    if (service.isActive) {
      service.stopMonitoring();
    } else {
      service.startMonitoring();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(service.isActive ? '🚨 MONITOR HOMBRE MUERTO ACTIVADO (Detección de Caídas).' : '⏸️ Monitor de hombre muerto pausado.'),
        backgroundColor: service.isActive ? const Color(0xFFFF9500) : const Color(0xFF8E8E93),
      ),
    );
  }
}