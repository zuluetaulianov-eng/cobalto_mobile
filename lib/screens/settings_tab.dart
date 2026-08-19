import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../services/aegis_black_box_service.dart';
import '../services/aegis_early_warning_service.dart';
import '../services/aegis_emergency_kit_service.dart';
import '../services/aegis_mesh_crypto_service.dart';
import '../services/aegis_mesh_transport_service.dart';
import '../services/aegis_survivor_profile_service.dart';
import '../services/crypto_vault_service.dart';
import '../services/dead_man_switch_service.dart';
import '../services/emergency_service.dart';
import 'aegis_triage_screen.dart';
import '../services/gps_service.dart';
import '../services/local_auth_service.dart';
import '../services/notification_service.dart';
import '../services/settings_persistence_service.dart';
import '../services/stealth_service.dart';
import '../services/tactical_camera_service.dart';
import '../services/voice_service.dart';
import '../services/widget_service.dart';
import '../widgets/geofence_manager_sheet.dart';
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
  bool _voiceAnnounceEnabled = false;
  bool _silentModeEnabled = false;
  late final TextEditingController _impactThresholdController =
      TextEditingController(text: DeadManSwitchService.impactThreshold.toStringAsFixed(1));
  late final TextEditingController _immobilizedController =
      TextEditingController(text: DeadManSwitchService.immobilizedMinutes.toString());
  late final TextEditingController _emergencyContactController = TextEditingController();
  late final TextEditingController _duressController = TextEditingController();
  late final TextEditingController _heartbeatIntervalController = TextEditingController(text: '5');
  bool _heartbeatEnabled = false;
  bool _hasDuressCode = false;

  // AEGIS: Perfil de sobreviviente + Kit de emergencia + Check-In.
  String _survivorBloodType = '';
  final TextEditingController _survivorAllergiesController = TextEditingController();
  final TextEditingController _survivorConditionsController = TextEditingController();
  String _kitReminderLabel = 'PENDIENTE';
  List<Map<String, dynamic>> _kitInventory = [];
  int _pendingBlackBox = 0;

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
    final voiceAnnounce = await SettingsPersistenceService.isVoiceAnnounceEnabled();
    final silentMode = await SettingsPersistenceService.isSilentModeEnabled();
    await VoiceService.loadSilentMode();
    final contact = await EmergencyService.getContactPhone();
    final heartbeatEnabled = await EmergencyService.isHeartbeatEnabled();
    final heartbeatMinutes = await EmergencyService.getHeartbeatMinutes();
    final hasDuress = await LocalAuthService.hasDuressCode();

    // AEGIS: sobreviviente + kit.
    final profile = await AegisSurvivorProfileService.loadProfile();
    final bloodType = profile['blood_type']?.toString() ?? '';
    final allergies = profile['allergies']?.toString() ?? '';
    final conditions = profile['medical_conditions']?.toString() ?? '';
    final kitReminder = await AegisEmergencyKitService.checkAndSchedule();
    final kitItems = await AegisEmergencyKitService.getInventory();
    final int pendingBlackBoxFresh = await AegisBlackBoxService.pendingCount();

    if (mounted) {
      setState(() {
        _keywords = result.keywords;
        _sources = result.sources;
        _isConnected = result.connected;
        _operatorUsername = operatorName;
        _voiceAnnounceEnabled = voiceAnnounce;
        _silentModeEnabled = silentMode;
        _emergencyContactController.text = contact;
        _heartbeatEnabled = heartbeatEnabled;
        _heartbeatIntervalController.text = heartbeatMinutes.toString();
        _hasDuressCode = hasDuress;
        _survivorBloodType = bloodType;
        _survivorAllergiesController.text = allergies;
        _survivorConditionsController.text = conditions;
        _kitReminderLabel = kitReminder;
        _kitInventory = kitItems;
        _pendingBlackBox = pendingBlackBoxFresh;
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

        const SettingsSectionTitle('🔔 PRUEBA DE NOTIFICACIONES Y VOZ'),
        const SizedBox(height: 6),
        TacticalActionButton(
          icon: Icons.notifications_active,
          label: 'ENVIAR NOTIFICACIÓN A BARRA DE ESTADO',
          color: const Color(0xFF00E5FF),
          onPressed: _testNotification,
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(
            '🔊 ANUNCIAR ALERTAS POR VOZ (TTS)',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
          ),
          subtitle: const Text(
            'Al llegar una notificación CRÍTICA/ALTA, COBALTO la pronuncia por el altavoz.',
            style: TextStyle(fontSize: 10, color: Colors.white54),
          ),
          value: _voiceAnnounceEnabled,
          activeTrackColor: const Color(0xFFBF5AF2),
          onChanged: (value) async {
            setState(() => _voiceAnnounceEnabled = value);
            await SettingsPersistenceService.saveVoiceAnnounceEnabled(value);
            if (value) {
              await VoiceService.speakAlert(
                title: 'ANUNCIO POR VOZ ACTIVADO',
                body: 'Las alertas tácticas serán pronunciadas por el canal auditivo.',
                level: 'ALTA',
              );
            }
          },
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(
            '🔇 MODO SILENCIO (MUTE TÁCTICO)',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
          ),
          subtitle: const Text(
            'Suprime toda lectura por voz. Prioridad: no interrumpe dictado STT en curso.',
            style: TextStyle(fontSize: 10, color: Colors.white54),
          ),
          value: _silentModeEnabled,
          activeTrackColor: const Color(0xFFFF2D55),
          onChanged: (value) async {
            setState(() => _silentModeEnabled = value);
            await VoiceService.setSilentMode(value);
          },
        ),
        const SizedBox(height: 8),
        TacticalActionButton(
          icon: Icons.my_location,
          label: 'PROBAR SENSORES GPS Y OBTENER POSICIÓN',
          color: const Color(0xFFFF9500),
          onPressed: _testGeofence,
        ),
        const SizedBox(height: 8),
        TacticalActionButton(
          icon: Icons.radar,
          label: 'GESTIONAR GEOCERCAS Y MONITOREO GPS',
          color: const Color(0xFF00FFAA),
          onPressed: _openGeofenceManager,
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
          icon: Icons.sos,
          label: '🚨 EMERGENCIA INMINENTE: HACER SONAR ALARMA DE RESCATE',
          color: const Color(0xFFFF2D55),
          onPressed: _triggerImminentEmergency,
        ),
        const SizedBox(height: 8),
        const SettingsSectionTitle('☠️ CALIBRACIÓN MONITOR HOMBRE MUERTO'),
        const SizedBox(height: 6),
        ListenableBuilder(
          listenable: DeadManSwitchService(),
          builder: (context, _) {
            final service = DeadManSwitchService();
            return SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                '☠️ VIGILANCIA HOMBRE MUERTO (ARMAR/DESARMAR)',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
              ),
              subtitle: const Text(
                'Detecta caída, inmovilización o arrastre y dispara SOS con alarma sonora.',
                style: TextStyle(fontSize: 10, color: Colors.white54),
              ),
              value: service.isActive,
              activeTrackColor: const Color(0xFFFF9500),
              onChanged: (value) async {
                await service.setEnabled(value);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      value
                          ? '🚨 VIGILANCIA HOMBRE MUERTO ARMADA.'
                          : '⏸️ Vigilancia de hombre muerto desarmada.',
                    ),
                    backgroundColor: value ? const Color(0xFFFF9500) : const Color(0xFF8E8E93),
                  ),
                );
              },
            );
          },
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _impactThresholdController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  labelText: 'UMBRAL IMPACTO (m/s²)',
                  labelStyle: const TextStyle(color: Colors.white38, fontSize: 10),
                  filled: true,
                  fillColor: const Color(0xFF141824),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _immobilizedController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  labelText: 'INMOVILIDAD (min)',
                  labelStyle: const TextStyle(color: Colors.white38, fontSize: 10),
                  filled: true,
                  fillColor: const Color(0xFF141824),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TacticalActionButton(
          icon: Icons.tune,
          label: 'APLICAR CALIBRACIÓN DE DETECCIÓN',
          color: const Color(0xFF00E5FF),
          onPressed: _applyDeadManCalibration,
        ),
        const SizedBox(height: 16),

        const SettingsSectionTitle('🆘 PLAN DE EMERGENCIA Y CONTACTO'),
        const SizedBox(height: 6),
        TextField(
          controller: _emergencyContactController,
          keyboardType: TextInputType.phone,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: InputDecoration(
            labelText: '📞 CONTACTO DE EMERGENCIA (teléfono)',
            labelStyle: const TextStyle(color: Colors.white38, fontSize: 10),
            hintText: '+58 412 000 0000',
            hintStyle: const TextStyle(color: Colors.white24, fontSize: 11),
            filled: true,
            fillColor: const Color(0xFF141824),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 6),
        TacticalActionButton(
          icon: Icons.save,
          label: 'GUARDAR CONTACTO DE EMERGENCIA (SMS/LLAMADA)',
          color: const Color(0xFFFF9500),
          onPressed: _saveEmergencyContact,
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(
            '📡 HEARTBEAT DE TELEMETRÍA (BEACON)',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
          ),
          subtitle: const Text(
            'Publica la posición periódicamente. La base detecta pérdida del operador si el latido cesa.',
            style: TextStyle(fontSize: 10, color: Colors.white54),
          ),
          value: _heartbeatEnabled,
          activeTrackColor: const Color(0xFF00E5FF),
          onChanged: (value) async {
            setState(() => _heartbeatEnabled = value);
            await EmergencyService.setHeartbeatEnabled(value);
          },
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _heartbeatIntervalController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  labelText: 'INTERVALO HEARTBEAT (min)',
                  labelStyle: const TextStyle(color: Colors.white38, fontSize: 10),
                  filled: true,
                  fillColor: const Color(0xFF141824),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _applyHeartbeatInterval,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E5FF).withOpacity(0.2),
                  foregroundColor: const Color(0xFF00E5FF),
                  side: const BorderSide(color: Color(0xFF00E5FF)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.timer, size: 16),
                label: const Text('APLICAR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _duressController,
                obscureText: true,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  labelText: _hasDuressCode ? '🔐 CÓDIGO DE COACCIÓN (configurado)' : '🔐 CÓDIGO DE COACCIÓN (PIN falso)',
                  labelStyle: const TextStyle(color: Colors.white38, fontSize: 10),
                  hintText: 'Si te obligan: este PIN entra y dispara SOS silencioso',
                  hintStyle: const TextStyle(color: Colors.white24, fontSize: 10),
                  filled: true,
                  fillColor: const Color(0xFF141824),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _applyDuressCode,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFBF5AF2).withOpacity(0.2),
                foregroundColor: const Color(0xFFBF5AF2),
                side: const BorderSide(color: Color(0xFFBF5AF2)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(Icons.lock, size: 16),
              label: const Text('SETEAR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
            ),
          ],
        ),
        if (_hasDuressCode) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _clearDuressCode,
              child: const Text(
                'Eliminar código de coacción',
                style: TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace'),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),

        const SettingsSectionTitle('🫀 PERFIL DE SOBREVIVIENTE (AEGIS)'),
        const SizedBox(height: 6),
        const Text(
          'Datos médicos críticos cifrados en reposo (AES-256-GCM). '
          'Viajan en el paquete de caja negra hacia los equipos de rescate.',
          style: TextStyle(color: Colors.white54, fontSize: 10),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF141824),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white10),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _survivorBloodType.isEmpty ? null : _survivorBloodType,
              dropdownColor: const Color(0xFF141824),
              isExpanded: true,
              hint: const Text('TIPO DE SANGRE', style: TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'monospace')),
              items: const [
                'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-', 'DESCONOCIDO',
              ].map((t) {
                return DropdownMenuItem(
                  value: t,
                  child: Text('🩸 $t', style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace')),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _survivorBloodType = val);
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _survivorAllergiesController,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: InputDecoration(
            labelText: 'ALERGIAS',
            labelStyle: const TextStyle(color: Colors.white38, fontSize: 10),
            hintText: 'Ej. penicilina, maní',
            hintStyle: const TextStyle(color: Colors.white24, fontSize: 10),
            filled: true,
            fillColor: const Color(0xFF141824),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _survivorConditionsController,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: InputDecoration(
            labelText: 'CONDICIONES MÉDICAS',
            labelStyle: const TextStyle(color: Colors.white38, fontSize: 10),
            hintText: 'Ej. hipertensión, diabetes',
            hintStyle: const TextStyle(color: Colors.white24, fontSize: 10),
            filled: true,
            fillColor: const Color(0xFF141824),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 6),
        TacticalActionButton(
          icon: Icons.save,
          label: 'GUARDAR PERFIL DE SOBREVIVIENTE (CIFRADO)',
          color: const Color(0xFF30D158),
          onPressed: _saveSurvivorProfile,
        ),
        const SizedBox(height: 16),

        const SettingsSectionTitle('🛡️ CHECK-IN "ESTOY A SALVO" (AEGIS)'),
        const SizedBox(height: 6),
        const Text(
          'Notificación persistente post-emergencia para confirmar tu estado '
          'desde la pantalla de bloqueo sin abrir la app.',
          style: TextStyle(color: Colors.white54, fontSize: 10),
        ),
        const SizedBox(height: 8),
        TacticalActionButton(
          icon: Icons.verified_user,
          label: 'ENVIAR CHECK-IN DE PRUEBA (NOTIFICACIÓN PERSISTENTE)',
          color: const Color(0xFF00E5FF),
          onPressed: _testCheckIn,
        ),
        const SizedBox(height: 16),

        const SettingsSectionTitle('🎒 KIT DE EMERGENCIA (AEGIS)'),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF141824),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF00FFAA).withOpacity(0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.update, color: Color(0xFF00FFAA), size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'PRÓXIMA REVISIÓN: $_kitReminderLabel',
                  style: const TextStyle(color: Color(0xFF00FFAA), fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        ..._kitInventory.map((item) {
          return CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: const Color(0xFF00FFAA),
            value: item['checked'] == true,
            title: Text(
              item['label'].toString(),
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
            onChanged: (_) => _toggleKitItem(item['label'].toString()),
          );
        }),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: TacticalActionButton(
                icon: Icons.refresh,
                label: 'REINICIAR CHECKLIST',
                color: const Color(0xFFFF9500),
                onPressed: _resetKitInventory,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TacticalActionButton(
                icon: Icons.schedule,
                label: 'REPROGRAMAR CICLO',
                color: const Color(0xFF00E5FF),
                onPressed: _resetKitReminder,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        const SettingsSectionTitle('🌋 ALERTA TEMPRANA DE SISMO (AEGIS)'),
        const SizedBox(height: 6),
        const Text(
          'Sensores globales sin servidor: feed directo USGS (fallback al hub), '
          'algoritmo P/S con ventana de anticipación y sirena local por escala. '
          'La geocerca activa aviso si el epicentro cae dentro del radio.',
          style: TextStyle(color: Colors.white54, fontSize: 10),
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder<AegisQuakeAlert?>(
          valueListenable: AegisEarlyWarningService.lastAlert,
          builder: (context, alert, _) {
            final text = alert == null
                ? 'SIN ALERTAS ACTIVAS · MONITOREO CADA 10 MIN'
                : 'ÚLTIMA: ${alert.nivel} · ${alert.distanceKm.round()} km · '
                    'P ~${alert.pArrivalS}s / S ~${alert.sArrivalS}s · '
                    '${alert.event.place}';
            return Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF141824),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: (alert?.nivel == 'CRÍTICA' ? const Color(0xFFFF2D55) : const Color(0xFFFF9500))
                      .withOpacity(0.4),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.waves, color: Color(0xFFFF9500), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      text,
                      style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        TacticalActionButton(
          icon: Icons.travel_explore,
          label: 'PROBAR CICLO DE ALERTA TEMPRANA (POLL NOW)',
          color: const Color(0xFFFF9500),
          onPressed: _testEarlyWarning,
        ),
        const SizedBox(height: 16),

        const SettingsSectionTitle('📦 CAJA NEGRA AEGIS'),
        const SizedBox(height: 6),
        const Text(
          'Paquete cifrado AES-256 (batería + GPS + tipo de sangre) enviado a '
          'la base con cola de reintento offline. Fotos silenciosas de contexto '
          'con estampado de telemetría. Grabación de audio: APLAZADA.',
          style: TextStyle(color: Colors.white54, fontSize: 10),
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder<Map<String, dynamic>?>(
          valueListenable: AegisBlackBoxService.lastPackage,
          builder: (context, pkg, _) {
            final text = pkg == null
                ? 'SIN PAQUETE EMITIDO AUN'
                : 'ÚLTIMO: #${pkg['seq']} · ${pkg['created_utc'] ?? ''} · '
                    'SHA256 ${pkg['hash_sha256']?.toString().substring(0, 12) ?? ''}…';
            return Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF141824),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFB388FF).withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.inventory_2, color: Color(0xFFB388FF), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      text,
                      style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TacticalActionButton(
                icon: Icons.camera_alt,
                label: 'FOTO DE CONTEXTO',
                color: const Color(0xFF00FFAA),
                onPressed: _testSilentPhoto,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TacticalActionButton(
                icon: Icons.send_to_mobile,
                label: 'EMITIR PAQUETE CIFRADO',
                color: const Color(0xFFB388FF),
                onPressed: _emitBlackBox,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            'PAQUETES PENDIENTES DE ENLACE: $_pendingBlackBox',
            style: const TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace'),
          ),
        ),
        const SizedBox(height: 16),

        const SettingsSectionTitle('🩺 TRIAJE Y SEGURIDAD MESH (AEGIS)'),
        const SizedBox(height: 6),
        TacticalActionButton(
          icon: Icons.medical_services,
          label: 'ABRIR TRIAJE DE PRIMEROS AUXILIOS OFFLINE (7 PROTOCOLOS)',
          color: const Color(0xFFFF2D55),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AegisTriageScreen()),
            );
          },
        ),
        const SizedBox(height: 8),
        FutureBuilder<Map<String, String>>(
          future: AegisMeshCryptoService.getIdentityInfo(),
          builder: (context, snapshot) {
            final info = snapshot.data;
            final fp = info?['fingerprint'] ?? 'Generando clave...';
            final nid = info?['node_id'] ?? '';
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
                  const Row(
                    children: [
                      Icon(Icons.fingerprint, color: Color(0xFF00E5FF), size: 16),
                      SizedBox(width: 8),
                      Text(
                        'IDENTIDAD MESH PKI (Ed25519 / X25519)',
                        style: TextStyle(
                          color: Color(0xFF00E5FF),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'HUELLA TOFU: $fp',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'NODE ID: ${nid.length > 20 ? '${nid.substring(0, 20)}…' : nid}',
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 9,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        StatefulBuilder(
          builder: (context, setMeshState) {
            final isRunning = AegisMeshTransportService.isRunning;
            final peers = AegisMeshTransportService.activePeersCount;
            return Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF141824),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isRunning ? const Color(0xFF00FFAA).withOpacity(0.4) : Colors.white10,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.hub,
                            color: isRunning ? const Color(0xFF00FFAA) : Colors.white38,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isRunning ? 'RED MESH ACTIVA (P2P)' : 'RED MESH DETENIDA',
                            style: TextStyle(
                              color: isRunning ? const Color(0xFF00FFAA) : Colors.white54,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                      Switch(
                        value: isRunning,
                        activeColor: const Color(0xFF00FFAA),
                        onChanged: (val) async {
                          if (val) {
                            await AegisMeshTransportService.startMesh();
                          } else {
                            await AegisMeshTransportService.stopMesh();
                          }
                          setMeshState(() {});
                        },
                      ),
                    ],
                  ),
                  if (isRunning) ...[
                    const Divider(color: Colors.white12, height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'PEERS CONECTADOS: $peers',
                          style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'monospace'),
                        ),
                        FutureBuilder<int>(
                          future: AegisMeshTransportService.getStoredPacketsCount(),
                          builder: (context, snapshot) {
                            return Text(
                              'STORED: ${snapshot.data ?? 0} PKTS',
                              style: const TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace'),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            );
          },
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
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🔔 Notificación enviada a la barra de estado.'),
        backgroundColor: Color(0xFF00E5FF),
      ),
    );
  }

  Future<void> _testGeofence() async {
    final pos = await GpsService.getCurrentPosition();
    if (pos != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🛰️ GPS Activo: ${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}. Sensor operativo.'),
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

  void _openGeofenceManager() {
    showGeofenceManager(context);
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
    final result = await TacticalCameraService.captureTelemetryPhoto(
      telemetry: GpsService.lastSnapshot,
      classification: 'CONFIDENCIAL // OPERADOR C4I',
    );

    if (!mounted) return;
    final String shaPrefix = (result?['sha256'] as String? ?? '');
    final String hashShort = shaPrefix.length > 8 ? shaPrefix.substring(0, 8) : shaPrefix;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result != null
              ? '📷 Fotografía estampada con telemetría y SHA256 $hashShort.'
              : '⚠️ No se pudo inicializar la cámara o permiso denegado.',
        ),
        backgroundColor: result != null ? const Color(0xFF00E5FF) : const Color(0xFFFF2D55),
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

  void _triggerImminentEmergency() {
    // Abre la pantalla de alarma con sirena sonora al máximo volumen y
    // transmite SOS a la base (sin escalada externa para no tapar la alarma).
    EmergencyService().triggerRescueSignal();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🚨 ALARMA DE RESCATE ACTIVADA: TOQUE LA PANTALLA O PULSE CANCELAR PARA DETENER.'),
        backgroundColor: Color(0xFFFF2D55),
      ),
    );
  }

  Future<void> _applyDeadManCalibration() async {
    final service = DeadManSwitchService();

    final double? impact = double.tryParse(_impactThresholdController.text.trim());
    final int? immob = int.tryParse(_immobilizedController.text.trim());

    if (impact == null || impact <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Umbral de impacto inválido (debe ser > 0 m/s²).'),
          backgroundColor: Color(0xFFFF2D55),
        ),
      );
      return;
    }
    if (immob == null || immob < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Ventana de inmovilización inválida (debe ser ≥ 1 min).'),
          backgroundColor: Color(0xFFFF2D55),
        ),
      );
      return;
    }

    await service.setImpactThreshold(impact);
    await service.setImmobilizedMinutes(immob);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Calibración aplicada: impacto > 0 m/s² e inmovilidad persistida.'),
        backgroundColor: Color(0xFF00FFAA),
      ),
    );
  }

  Future<void> _saveEmergencyContact() async {
    final phone = _emergencyContactController.text.trim();
    await EmergencyService.setContactPhone(phone);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(phone.isNotEmpty
            ? '✅ Contacto de emergencia guardado: $phone.'
            : 'ℹ️ Contacto de emergencia vacío (escalada SMS/llamada desactivada).'),
        backgroundColor: phone.isNotEmpty ? const Color(0xFF00FFAA) : const Color(0xFF8E8E93),
      ),
    );
  }

  Future<void> _applyHeartbeatInterval() async {
    final minutes = int.tryParse(_heartbeatIntervalController.text.trim());
    if (minutes == null || minutes < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Intervalo de heartbeat inválido (debe ser ≥ 1 min).'),
          backgroundColor: Color(0xFFFF2D55),
        ),
      );
      return;
    }
    await EmergencyService.setHeartbeatMinutes(minutes);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Intervalo de heartbeat actualizado.'),
        backgroundColor: Color(0xFF00FFAA),
      ),
    );
  }

  Future<void> _applyDuressCode() async {
    final code = _duressController.text;
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Ingrese el código de coacción a configurar.'),
          backgroundColor: Color(0xFFFF2D55),
        ),
      );
      return;
    }
    final ok = await LocalAuthService.setDuressCode(code);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Código de coacción demasiado corto (mínimo 4 caracteres).'),
          backgroundColor: Color(0xFFFF2D55),
        ),
      );
      return;
    }
    _duressController.clear();
    setState(() => _hasDuressCode = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🔐 Código de coacción configurado. Usarlo en el login dispara SOS silencioso.'),
        backgroundColor: Color(0xFFBF5AF2),
      ),
    );
  }

  Future<void> _clearDuressCode() async {
    await LocalAuthService.clearDuressCode();
    if (!mounted) return;
    setState(() => _hasDuressCode = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('ℹ️ Código de coacción eliminado.'),
        backgroundColor: Color(0xFF8E8E93),
      ),
    );
  }

  // ── AEGIS: PERFIL DE SOBREVIVIENTE ──

  Future<void> _saveSurvivorProfile() async {
    await AegisSurvivorProfileService.saveProfile(
      bloodType: _survivorBloodType,
      allergies: _survivorAllergiesController.text.trim(),
      medicalConditions: _survivorConditionsController.text.trim(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Perfil de sobreviviente guardado (cifrado AES-256).'),
        backgroundColor: Color(0xFF00FFAA),
      ),
    );
  }

  // ── AEGIS: KIT DE EMERGENCIA ──

  Future<void> _toggleKitItem(String label) async {
    final items = _kitInventory;
    for (final item in items) {
      if (item['label'] == label) item['checked'] = !(item['checked'] == true);
    }
    setState(() => _kitInventory = List.from(items));
    await AegisEmergencyKitService.saveInventory(items);
  }

  Future<void> _resetKitInventory() async {
    await AegisEmergencyKitService.resetInventory();
    final fresh = await AegisEmergencyKitService.getInventory();
    if (!mounted) return;
    setState(() => _kitInventory = fresh);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🎒 Inventario del kit restablecido al estándar.'),
        backgroundColor: Color(0xFF00E5FF),
      ),
    );
  }

  Future<void> _resetKitReminder() async {
    await AegisEmergencyKitService.resetReminderTimer();
    final label = await AegisEmergencyKitService.checkAndSchedule();
    if (!mounted) return;
    setState(() => _kitReminderLabel = label);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🔄 Ciclo de mantenimiento del kit reprogramado.'),
        backgroundColor: Color(0xFF00FFAA),
      ),
    );
  }

  // ── AEGIS: CHECK-IN "ESTOY A SALVO" (RECUPERACIÓN) ──

  Future<void> _testCheckIn() async {
    await NotificationService.showCheckInNotification();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🛡️ Notificación de Check-In persistente enviada.'),
        backgroundColor: Color(0xFF00E5FF),
      ),
    );
  }

  // ── AEGIS: ALERTA TEMPRANA (SISMO) ──

  Future<void> _testEarlyWarning() async {
    final alert = await AegisEarlyWarningService.pollNow();
    if (!mounted) return;
    final message = alert == null
        ? '🌋 Ciclo ejecutado. Sin sismo en la geocerca o sin fix GPS.'
        : '🌋 Alerta [${alert.nivel}] a ${alert.distanceKm.round()} km '
            '(ondas S en ~${alert.sArrivalS} s).';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFFF9500),
      ),
    );
  }

  // ── AEGIS: CAJA NEGRA ──

  Future<void> _testSilentPhoto() async {
    final result = await AegisBlackBoxService.captureSilentContextPhoto();
    if (!mounted) return;
    final message = result == null
        ? '📷 Captura omitida (caja negra off o batería baja).'
        : '📷 Foto de contexto silenciosa guardada y estampada.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF00FFAA),
      ),
    );
  }

  Future<void> _emitBlackBox() async {
    final envelope = await AegisBlackBoxService.emitPackage();
    final pending = await AegisBlackBoxService.pendingCount();
    if (!mounted) return;
    setState(() => _pendingBlackBox = pending);
    final message = envelope == null
        ? '📦 Caja negra desactivada: paquete no emitido.'
        : '📦 Paquete AEGIS #${envelope['seq']} emitido '
            '(enviado o encolado · pendientes: $_pendingBlackBox).';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFB388FF),
      ),
    );
  }
}