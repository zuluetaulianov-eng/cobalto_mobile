import 'package:flutter/material.dart';
import '../config/api_config.dart';
import '../services/cobalto_api_service.dart';
import 'main_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  late TextEditingController _urlController;
  late TextEditingController _userController;
  late TextEditingController _passController;
  late AnimationController _ringController;

  bool _isLoggingIn = false;
  String _errorMsg = '';

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: ApiConfig.baseUrl);
    _userController = TextEditingController(text: ApiConfig.username);
    _passController = TextEditingController(text: ApiConfig.password);

    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _userController.dispose();
    _passController.dispose();
    _ringController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final url = _urlController.text.trim();
    final user = _userController.text.trim();
    final pass = _passController.text.trim();

    if (url.isEmpty || user.isEmpty || pass.isEmpty) {
      setState(() => _errorMsg = 'Por favor complete todos los campos.');
      return;
    }

    setState(() {
      _isLoggingIn = true;
      _errorMsg = '';
    });

    // Guardar URL y credenciales de conexión
    await ApiConfig.saveConfig(url, user, pass);

    // Intentar Login contra backend FastAPI (/api/login)
    final res = await CobaltoApiService.login(user, pass);

    if (mounted) {
      if (res['success'] == true) {
        // Redirigir a la interfaz principal
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainScreen()),
        );
      } else {
        setState(() {
          _isLoggingIn = false;
          _errorMsg = res['error'] ?? 'Acceso denegado. Verifique servidor y credenciales.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0B10),
      body: Stack(
        children: [
          // Gradiente Radial de Fondo Ciberpunk
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.2),
                radius: 0.9,
                colors: [
                  Color(0x1800E5FF),
                  Colors.transparent,
                ],
              ),
            ),
          ),

          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Anillo Giratorio del Login Ciberpunk Web
                  RotationTransition(
                    turns: _ringController,
                    child: Container(
                      width: 48,
                      height: 48,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF00E5FF),
                          width: 2,
                        ),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF00E5FF),
                          backgroundColor: Colors.transparent,
                        ),
                      ),
                    ),
                  ),

                  // Títulos Tácticos
                  const Text(
                    'COBALTO HUB',
                    style: TextStyle(
                      color: Color(0xFF00E5FF),
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'v9.0 — ACCESO RESTRINGIDO TÁCTICO',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                      letterSpacing: 2,
                      fontFamily: 'monospace',
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Formulario de Inicio de Sesión
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141824),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF00E5FF).withOpacity(0.2),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00E5FF).withOpacity(0.05),
                          blurRadius: 15,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // URL Servidor / Zrok
                        _buildInputField(
                          controller: _urlController,
                          label: 'URL SERVIDOR / IP LOCAL',
                          icon: Icons.dns_outlined,
                        ),
                        const SizedBox(height: 8),

                        // Chips de selección rápida de Servidor
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _buildPresetChip('📡 Wi-Fi Local', ApiConfig.presetLanUrl),
                              const SizedBox(width: 6),
                              _buildPresetChip('📱 Emulador', ApiConfig.presetEmulatorUrl),
                              const SizedBox(width: 6),
                              _buildPresetChip('💻 Localhost', ApiConfig.presetLocalhostUrl),
                              const SizedBox(width: 6),
                              _buildPresetChip('🌐 Zrok', ApiConfig.presetZrokUrl),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Usuario
                        _buildInputField(
                          controller: _userController,
                          label: 'USUARIO OPERADOR',
                          icon: Icons.person_outline,
                        ),
                        const SizedBox(height: 14),

                        // Contraseña
                        _buildInputField(
                          controller: _passController,
                          label: 'CONTRASEÑA DE ACCESO',
                          icon: Icons.lock_outline,
                          obscureText: true,
                        ),

                        if (_errorMsg.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF2D55).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFFF2D55).withOpacity(0.4)),
                            ),
                            child: Text(
                              _errorMsg,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFFFF2D55),
                                fontSize: 11,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(height: 22),

                        // Botón de Ingreso Ciberpunk
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00E5FF),
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            elevation: 4,
                          ),
                          onPressed: _isLoggingIn ? null : _handleLogin,
                          child: _isLoggingIn
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black,
                                  ),
                                )
                              : const Text(
                                  'INGRESAR AL SISTEMA',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    letterSpacing: 2,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                        ),
                      ],
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

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 10,
            fontFamily: 'monospace',
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscureText,
          style: const TextStyle(
            color: Color(0xFF00E5FF),
            fontSize: 13,
            fontFamily: 'monospace',
          ),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: const Color(0xFF00E5FF), size: 18),
            filled: true,
            fillColor: const Color(0xFF0A0B10),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: const Color(0xFF00E5FF).withOpacity(0.2)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFF00E5FF), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPresetChip(String label, String url) {
    final bool isSelected = _urlController.text.trim() == url;
    return InkWell(
      onTap: () {
        setState(() {
          _urlController.text = url;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00E5FF).withOpacity(0.2) : const Color(0xFF0A0B10),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? const Color(0xFF00E5FF) : const Color(0xFF00E5FF).withOpacity(0.2),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? const Color(0xFF00E5FF) : Colors.white70,
            fontSize: 9,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}
