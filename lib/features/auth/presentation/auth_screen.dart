import 'package:flutter/material.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isLogin ? 'Iniciar Sesión' : 'Crear Cuenta'),
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
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 52,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _savedAccounts.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final acc = _savedAccounts[index];
                    return InputChip(
                      avatar: CircleAvatar(
                        backgroundColor: Colors.deepOrange,
                        child: Text(
                          acc.label.isNotEmpty ? acc.label[0].toUpperCase() : 'U',
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                      label: Text(acc.label),
                      onPressed: () => _selectSavedAccount(acc),
                      onDeleted: () async {
                        await AccountManagerService.removeAccount(acc.email);
                        _loadSavedAccounts();
                      },
                      deleteIconColor: Colors.grey,
                    );
                  },
                ),
              ),
              const Divider(height: 24),
            ],

            const Icon(Icons.stars_rounded, size: 60, color: Colors.deepOrange),
            const SizedBox(height: 8),
            Text(
              _isLogin
                  ? 'Inicia sesión para gestionar pedidos y puntos'
                  : 'Regístrate y gana puntos por cada compra',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            if (!_isLogin) ...[
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nombre completo',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Teléfono',
                  prefixIcon: Icon(Icons.phone),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Correo Electrónico',
                prefixIcon: Icon(Icons.email),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Contraseña',
                prefixIcon: const Icon(Icons.lock),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                    color: Colors.grey.shade600,
                  ),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Recordar esta cuenta para acceso rápido', style: TextStyle(fontSize: 13)),
              value: _rememberAccount,
              activeColor: Colors.deepOrange,
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (val) => setState(() => _rememberAccount = val ?? true),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepOrange,
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
              child: Text(
                _isLogin
                    ? '¿No tienes cuenta? Regístrate aquí'
                    : '¿Ya tienes cuenta? Inicia sesión',
              ),
            ),

            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 10),

            // Tarjeta de actualización accesible para usuarios no registrados / cerrados
            const AppUpdateCard(),
          ],
        ),
      ),
    );
  }
}