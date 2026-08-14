import 'package:flutter/material.dart';

import '../services/local_auth_service.dart';

/// Resultado de la operación de edición de credenciales.
enum OperatorEditResult { changed, cancelled, error }

/// Diálogo táctico para editar el nombre de usuario o la contraseña del
/// operador local. Requiere la contraseña actual como verificación.
class OperatorCredentialsDialog extends StatefulWidget {
  final bool editingUsername;
  final String currentUsername;

  const OperatorCredentialsDialog({
    super.key,
    required this.editingUsername,
    required this.currentUsername,
  });

  static Future<OperatorEditResult> show(
    BuildContext context, {
    required bool editingUsername,
    required String currentUsername,
  }) async {
    return await showDialog<OperatorEditResult>(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => OperatorCredentialsDialog(
        editingUsername: editingUsername,
        currentUsername: currentUsername,
      ),
    ) ??
        OperatorEditResult.cancelled;
  }

  @override
  State<OperatorCredentialsDialog> createState() => _OperatorCredentialsDialogState();
}

class _OperatorCredentialsDialogState extends State<OperatorCredentialsDialog> {
  final TextEditingController _currentPass = TextEditingController();
  final TextEditingController _newUsername = TextEditingController();
  final TextEditingController _newPass = TextEditingController();
  final TextEditingController _confirmPass = TextEditingController();

  bool _isBusy = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    if (widget.editingUsername) {
      _newUsername.text = widget.currentUsername;
    }
  }

  @override
  void dispose() {
    _currentPass.dispose();
    _newUsername.dispose();
    _newPass.dispose();
    _confirmPass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final current = _currentPass.text;
    if (current.isEmpty) {
      setState(() => _error = 'Debe ingresar la contraseña actual.');
      return;
    }

    setState(() {
      _isBusy = true;
      _error = '';
    });

    try {
      if (widget.editingUsername) {
        await LocalAuthService.changeUsername(_newUsername.text.trim(), current);
      } else {
        final newPass = _newPass.text;
        final confirm = _confirmPass.text;
        if (newPass.isEmpty) {
          throw ArgumentError('La nueva contraseña no puede estar vacía.');
        }
        if (newPass != confirm) {
          throw ArgumentError('Las contraseñas no coinciden.');
        }
        await LocalAuthService.changePassword(newPass, current);
      }
      if (mounted) Navigator.of(context).pop(OperatorEditResult.changed);
    } catch (e) {
      setState(() {
        _isBusy = false;
        _error = e is ArgumentError
            ? e.message.toString()
            : (e is StateError ? e.message.toString() : 'No se pudo actualizar: $e');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.editingUsername ? 'CAMBIAR NOMBRE DE OPERADOR' : 'CAMBIAR CONTRASEÑA';

    return AlertDialog(
      backgroundColor: const Color(0xFF141824),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF00E5FF),
          fontSize: 13,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Operador actual: ${widget.currentUsername}',
              style: const TextStyle(color: Colors.white54, fontSize: 11, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 12),
            _field(_currentPass, 'CONTRASEÑA ACTUAL', obscure: true, icon: Icons.lock_outline),
            const SizedBox(height: 10),
            if (widget.editingUsername) ...[
              _field(_newUsername, 'NUEVO NOMBRE DE OPERADOR', icon: Icons.person_outline),
            ] else ...[
              _field(_newPass, 'NUEVA CONTRASEÑA', obscure: true, icon: Icons.lock_outline),
              const SizedBox(height: 10),
              _field(_confirmPass, 'CONFIRMAR NUEVA CONTRASEÑA', obscure: true, icon: Icons.lock_outline),
            ],
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                _error,
                style: const TextStyle(color: Color(0xFFFF2D55), fontSize: 10, fontFamily: 'monospace'),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isBusy ? null : () => Navigator.of(context).pop(OperatorEditResult.cancelled),
          child: const Text('CANCELAR', style: TextStyle(color: Colors.white54, fontFamily: 'monospace')),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00E5FF),
            foregroundColor: Colors.black,
          ),
          onPressed: _isBusy ? null : _submit,
          child: _isBusy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
              : const Text('CONFIRMAR', style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace')),
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool obscure = false,
    required IconData icon,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      autofocus: true,
      style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 10),
        prefixIcon: Icon(icon, color: const Color(0xFF00E5FF), size: 16),
        filled: true,
        fillColor: const Color(0xFF0A0B10),
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF00E5FF), width: 0.3),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF00E5FF), width: 0.3),
        ),
      ),
    );
  }
}