import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/account_manager_service.dart';
import '../../../core/widgets/app_update_card.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _isLogin = true;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberAccount = true;

  List<SavedAccount> _savedAccounts = [];

  @override
  void initState() {
    super.initState();
    _loadSavedAccounts();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedAccounts() async {
    final accounts = await AccountManagerService.getSavedAccounts();
    if (mounted) {
      setState(() => _savedAccounts = accounts);
    }
  }

  void _selectSavedAccount(SavedAccount account) {
    setState(() {
      _emailController.text = account.email;
      _passwordController.text = account.password;
      _isLogin = true;
    });
    // Inicia sesión automáticamente con la cuenta seleccionada
    _submit();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor completa correo y contraseña.')),
      );
      return;
    }

    setState(() => _isLoading = true);
    final supabase = Supabase.instance.client;

    try {
      if (_isLogin) {
        final res = await supabase.auth.signInWithPassword(
          email: email,
          password: password,
        );

        if (_rememberAccount && res.user != null) {
          // Obtener el rol o nombre para la etiqueta rápida
          final profile = await supabase
              .from('profiles')
              .select('role, full_name')
              .eq('id', res.user!.id)
              .maybeSingle();

          final role = profile?['role']?.toString().toUpperCase() ?? 'CLIENTE';
          final name = profile?['full_name']?.toString() ?? email.split('@')[0];

          await AccountManagerService.saveAccount(
            SavedAccount(
              email: email,
              password: password,
              label: '$name ($role)',
            ),
          );
        }
      } else {
        final res = await supabase.auth.signUp(
          email: email,
          password: password,
        );

        final userId = res.user?.id;
        if (userId != null) {
          await supabase.from('profiles').upsert({
            'id': userId,
            'full_name': _nameController.text.trim().isEmpty
                ? 'Cliente K\'OTEMAL'
                : _nameController.text.trim(),
            'phone': _phoneController.text.trim(),
            'role': 'cliente',
            'points': 0,
          });

          if (_rememberAccount) {
            await AccountManagerService.saveAccount(
              SavedAccount(
                email: email,
                password: password,
                label: '${_nameController.text.trim()} (CLIENTE)',
              ),
            );
          }
        }
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openForgotPasswordDialog() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => _ForgotPasswordDialog(
        initialEmail: _emailController.text.trim(),
      ),
    );

    if (result == null || !mounted) return;

    setState(() {
      _emailController.text = result['email'] ?? '';
      _passwordController.text = result['password'] ?? '';
      _isLogin = true;
    });
    await _loadSavedAccounts();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Contraseña actualizada correctamente.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE9E1D9),
      appBar: AppBar(
        title: Text(
          _isLogin ? 'Iniciar Sesión' : 'Crear Cuenta',
          style: const TextStyle(color: Color(0xFF4B2618)),
        ),
        backgroundColor: const Color(0xFFE9E1D9),
        foregroundColor: const Color(0xFF4B2618),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Listado de Cuentas Rápidas si existen
            if (_isLogin && _savedAccounts.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Acceso Rápido (Cuentas Guardadas):',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF4B2618),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 52,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _savedAccounts.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final acc = _savedAccounts[index];
                    return InputChip(
                      avatar: CircleAvatar(
                        backgroundColor: const Color(0xFFC25229),
                        child: Text(
                          acc.label.isNotEmpty ? acc.label[0].toUpperCase() : 'U',
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                      label: Text(acc.label, style: const TextStyle(color: Color(0xFF4B2618))),
                      backgroundColor: const Color(0xFFFAF6F1),
                      side: const BorderSide(color: Color(0xFFD5C8BC)),
                      onPressed: () => _selectSavedAccount(acc),
                      onDeleted: () async {
                        await AccountManagerService.removeAccount(acc.email);
                        _loadSavedAccounts();
                      },
                      deleteIconColor: const Color(0xFF4B2618),
                    );
                  },
                ),
              ),
              const Divider(height: 24),
            ],

            Container(
              height: 120,
              alignment: Alignment.center,
              child: ClipOval(
                child: Image.asset(
                  'assets/images/logo.png',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return const Icon(Icons.stars_rounded, size: 60, color: Color(0xFFC25229));
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isLogin
                  ? 'Inicia sesión para gestionar pedidos y puntos'
                  : 'Regístrate y gana puntos por cada compra',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF4B2618),
              ),
            ),
            const SizedBox(height: 20),
            if (!_isLogin) ...[
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Nombre completo',
                  labelStyle: const TextStyle(color: Color(0xFF4B2618)),
                  prefixIcon: const Icon(Icons.person, color: Color(0xFF4B2618)),
                  border: const OutlineInputBorder(),
                  enabledBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFFD5C8BC)),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFFC25229)),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFFAF6F1),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Teléfono',
                  labelStyle: const TextStyle(color: Color(0xFF4B2618)),
                  prefixIcon: const Icon(Icons.phone, color: Color(0xFF4B2618)),
                  border: const OutlineInputBorder(),
                  enabledBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFFD5C8BC)),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFFC25229)),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFFAF6F1),
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Correo Electrónico',
                labelStyle: const TextStyle(color: Color(0xFF4B2618)),
                prefixIcon: const Icon(Icons.email, color: Color(0xFF4B2618)),
                border: const OutlineInputBorder(),
                enabledBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFD5C8BC)),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFC25229)),
                ),
                filled: true,
                fillColor: const Color(0xFFFAF6F1),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Contraseña',
                labelStyle: const TextStyle(color: Color(0xFF4B2618)),
                prefixIcon: const Icon(Icons.lock, color: Color(0xFF4B2618)),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                    color: const Color(0xFF4B2618),
                  ),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
                border: const OutlineInputBorder(),
                enabledBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFD5C8BC)),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFC25229)),
                ),
                filled: true,
                fillColor: const Color(0xFFFAF6F1),
              ),
            ),
            if (_isLogin) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _openForgotPasswordDialog,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFC25229),
                  ),
                  child: const Text('¿Olvidaste tu contraseña?'),
                ),
              ),
            ],
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Recordar esta cuenta para acceso rápido',
                style: TextStyle(fontSize: 13, color: Color(0xFF4B2618)),
              ),
              value: _rememberAccount,
              activeColor: const Color(0xFFC25229),
              checkColor: Colors.white,
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (val) => setState(() => _rememberAccount = val ?? true),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC25229),
                  foregroundColor: Colors.white,
                ),
                onPressed: _isLoading ? null : _submit,
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(_isLogin ? 'Ingresar' : 'Registrarme'),
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _isLogin = !_isLogin),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFC25229),
              ),
              child: Text(
                _isLogin
                    ? '¿No tienes cuenta? Regístrate aquí'
                    : '¿Ya tienes cuenta? Inicia sesión',
              ),
            ),

            // Mostrar la tarjeta de actualización solo en Android/iOS (Oculta en Web)[cite: 8, 10]
            if (!kIsWeb) ...[
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 10),
              const AppUpdateCard(
                backgroundColor: Color(0xFFFAF6F1),
                accentColor: Color(0xFFC25229),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ForgotPasswordDialog extends StatefulWidget {
  const _ForgotPasswordDialog({required this.initialEmail});

  final String initialEmail;

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  late final TextEditingController _emailController;
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();

  int _step = 1;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _error;
  String _sentEmail = '';

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Ingresa tu correo electrónico.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      if (!mounted) return;
      setState(() {
        _sentEmail = email;
        _step = 2;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resetPassword() async {
    final code = _codeController.text.trim();
    final newPassword = _passwordController.text;

    if (code.length != 6) {
      setState(() => _error = 'El código debe tener 6 dígitos.');
      return;
    }
    if (newPassword.length < 6) {
      setState(() => _error = 'La contraseña debe tener al menos 6 caracteres.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await Supabase.instance.client.auth.verifyOTP(
        email: _sentEmail,
        token: code,
        type: OtpType.recovery,
      );
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: newPassword),
      );
      await AccountManagerService.updatePassword(_sentEmail, newPassword);

      if (!mounted) return;
      Navigator.pop(context, {
        'email': _sentEmail,
        'password': newPassword,
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _step == 1 ? 'Recuperar contraseña' : 'Código de verificación',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_step == 1) ...[
              const Text(
                'Ingresa tu correo y te enviaremos un código de 6 dígitos.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Correo electrónico',
                  labelStyle: const TextStyle(color: Color(0xFF4B2618)),
                  prefixIcon: const Icon(Icons.email, color: Color(0xFF4B2618)),
                  border: const OutlineInputBorder(),
                  enabledBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFFD5C8BC)),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFFC25229)),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFFAF6F1),
                ),
              ),
            ] else ...[
              Text('Enviamos un código de 6 dígitos a $_sentEmail.'),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _isLoading ? null : _sendCode,
                  child: const Text('Reenviar código'),
                ),
              ),
              TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(
                  labelText: 'Código de 6 dígitos',
                  labelStyle: const TextStyle(color: Color(0xFF4B2618)),
                  prefixIcon: const Icon(Icons.pin, color: Color(0xFF4B2618)),
                  border: const OutlineInputBorder(),
                  enabledBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFFD5C8BC)),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFFC25229)),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFFAF6F1),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Nueva contraseña',
                  labelStyle: const TextStyle(color: Color(0xFF4B2618)),
                  prefixIcon: const Icon(Icons.lock, color: Color(0xFF4B2618)),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                      color: const Color(0xFF4B2618),
                    ),
                    onPressed: () => setState(
                      () => _obscurePassword = !_obscurePassword,
                    ),
                  ),
                  border: const OutlineInputBorder(),
                  enabledBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFFD5C8BC)),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFFC25229)),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFFAF6F1),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        if (_step == 1)
          ElevatedButton(
            onPressed: _isLoading ? null : _sendCode,
            child: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Enviar código de 6 dígitos'),
          )
        else
          ElevatedButton(
            onPressed: _isLoading ? null : _resetPassword,
            child: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Restablecer contraseña'),
          ),
      ],
    );
  }
}