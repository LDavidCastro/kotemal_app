import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UsersRolesScreen extends StatefulWidget {
  const UsersRolesScreen({super.key});

  @override
  State<UsersRolesScreen> createState() => _UsersRolesScreenState();
}

class _UsersRolesScreenState extends State<UsersRolesScreen> {
  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();

  List<Map<String, dynamic>> _allUsers = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _searchQuery = '';

  static const _tabs = ['Clientes', 'Repartidores', 'Cocineros', 'Admins'];

  static const List<String> _allModules = [
    'cocina',
    'rutas',
    'cierre_caja',
    'gastos',
    'usuarios',
    'menu',
  ];

  static const Map<String, String> _moduleLabels = {
    'cocina': 'Panel de Cocina',
    'rutas': 'Rutas y Entregas',
    'cierre_caja': 'Cierre de Caja',
    'gastos': 'Registro de Gastos',
    'usuarios': 'Usuarios y Permisos',
    'menu': 'Gestión de Menú',
  };

  List<String> _parseModules(dynamic value) {
    if (value == null) return const [];
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return const [];
  }

  List<String> _defaultModulesForRole(String role, List<String>? current) {
    final existing = current ?? const [];
    switch (role) {
      case 'admin':
        return List<String>.from(_allModules);
      case 'cliente':
        return const [];
      case 'cocinero':
        return existing.isEmpty ? const ['cocina'] : List<String>.from(existing);
      case 'repartidor':
        return existing.isEmpty ? const ['rutas'] : List<String>.from(existing);
      default:
        return const [];
    }
  }

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers({
    bool showSpinner = true,
    bool allowRetry = true,
  }) async {
    if (showSpinner) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final data = await _supabase
          .from('profiles')
          .select('id, full_name, phone, role, points, allowed_modules')
          .order('full_name', ascending: true);

      if (!mounted) return;
      setState(() {
        _allUsers = List<Map<String, dynamic>>.from(data);
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (_) {
      if (!mounted) return;

      if (allowRetry) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        if (!mounted) return;
        await _loadUsers(showSpinner: showSpinner, allowRetry: false);
        return;
      }

      setState(() {
        _isLoading = false;
        _errorMessage =
            'No se pudieron cargar los usuarios. Revisa tu conexión e inténtalo de nuevo.';
      });
    }
  }

  Future<void> _updateUserRole(String userId, String newRole) async {
    final index = _allUsers.indexWhere((user) => user['id'] == userId);
    final previousUser = index >= 0
        ? Map<String, dynamic>.from(_allUsers[index])
        : <String, dynamic>{};

    final updatedModules = _defaultModulesForRole(
      newRole,
      _parseModules(previousUser['allowed_modules']),
    );

    if (index >= 0) {
      setState(() {
        _allUsers[index] = {
          ..._allUsers[index],
          'role': newRole,
          'allowed_modules': updatedModules,
        };
      });
    }

    try {
      await _supabase.from('profiles').update({
        'role': newRole,
        'allowed_modules': updatedModules,
      }).eq('id', userId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rol actualizado a $newRole')),
      );
      await _loadUsers(showSpinner: false);
    } catch (e) {
      if (!mounted) return;

      if (index >= 0) {
        setState(() {
          _allUsers[index] = previousUser;
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cambiar rol: $e')),
      );
    }
  }

  Future<void> _updateAllowedModules(
    String userId,
    String module,
    bool enabled,
  ) async {
    final index = _allUsers.indexWhere((user) => user['id'] == userId);
    if (index < 0) return;

    final currentModules = _parseModules(_allUsers[index]['allowed_modules']);
    final updatedModules = List<String>.from(currentModules);
    if (enabled) {
      if (!updatedModules.contains(module)) updatedModules.add(module);
    } else {
      updatedModules.remove(module);
    }

    final previousModules = List<String>.from(currentModules);

    setState(() {
      _allUsers[index] = {
        ..._allUsers[index],
        'allowed_modules': updatedModules,
      };
    });

    try {
      await _supabase.from('profiles').update({
        'allowed_modules': updatedModules,
      }).eq('id', userId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_moduleLabels[module]} ${enabled ? 'activado' : 'desactivado'}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _allUsers[index] = {
          ..._allUsers[index],
          'allowed_modules': previousModules,
        };
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al actualizar permiso: $e')),
      );
    }
  }

  String _normalizeRole(String? role) {
    switch (role) {
      case 'admin':
        return 'admin';
      case 'repartidor':
        return 'repartidor';
      case 'cocinero':
      case 'cocina':
        return 'cocinero';
      default:
        return 'cliente';
    }
  }

  int _roleIndex(String? role) {
    switch (role) {
      case 'repartidor':
        return 1;
      case 'cocinero':
      case 'cocina':
        return 2;
      case 'admin':
        return 3;
      default:
        return 0;
    }
  }

  int _countForRole(int roleIndex) {
    return _allUsers
        .where((user) => _roleIndex(user['role'] as String?) == roleIndex)
        .length;
  }

  List<Map<String, dynamic>> _usersForRole(int roleIndex) {
    final query = _searchQuery.trim().toLowerCase();

    return _allUsers.where((user) {
      if (_roleIndex(user['role'] as String?) != roleIndex) return false;
      if (query.isEmpty) return true;

      final name = (user['full_name'] ?? '').toString().toLowerCase();
      final phone = (user['phone'] ?? '').toString().toLowerCase();
      return name.contains(query) || phone.contains(query);
    }).toList();
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'admin':
        return Colors.red;
      case 'repartidor':
        return Colors.blue;
      case 'cocinero':
        return Colors.amber.shade700;
      default:
        return Colors.grey;
    }
  }

  IconData _roleIcon(String role) {
    switch (role) {
      case 'admin':
        return Icons.security;
      case 'repartidor':
        return Icons.two_wheeler;
      case 'cocinero':
        return Icons.restaurant;
      default:
        return Icons.person;
    }
  }

  @override
  Widget build(BuildContext context) {
    final counts = List<int>.generate(_tabs.length, _countForRole);

    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Gestión de Usuarios y Roles'),
          backgroundColor: Colors.deepOrange,
          foregroundColor: Colors.white,
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              for (var i = 0; i < _tabs.length; i++)
                Tab(text: '${_tabs[i]} (${counts[i]})'),
            ],
          ),
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return _buildError();
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _searchQuery = value),
            decoration: InputDecoration(
              hintText: 'Buscar por nombre o teléfono',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: 'Limpiar búsqueda',
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    ),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        Expanded(
          child: TabBarView(
            children: [
              for (var i = 0; i < _tabs.length; i++) _buildUserList(i),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(_errorMessage!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadUsers,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserList(int roleIndex) {
    final users = _usersForRole(roleIndex);

    return RefreshIndicator(
      onRefresh: () => _loadUsers(showSpinner: false),
      child: users.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(height: MediaQuery.sizeOf(context).height * 0.2),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      _searchQuery.trim().isEmpty
                          ? 'No hay usuarios en este rol.'
                          : 'Sin resultados para "$_searchQuery".',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: users.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) => _buildUserCard(users[index]),
            ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final userId = user['id'] as String;
    final name = (user['full_name'] ?? 'Sin nombre').toString();
    final phone = (user['phone'] ?? 'Sin teléfono').toString();
    final points = user['points'] ?? 0;
    final role = _normalizeRole(user['role'] as String?);
    final color = _roleColor(role);
    final modules = _parseModules(user['allowed_modules']);
    final isAdmin = role == 'admin';

    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        controlAffinity: ListTileControlAffinity.leading,
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.18),
          child: Icon(_roleIcon(role), color: color),
        ),
        title: Text(
          name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text('Tel: $phone | Puntos: $points'),
        trailing: DropdownButton<String>(
          value: role,
          underline: const SizedBox(),
          items: const [
            DropdownMenuItem(value: 'cliente', child: Text('Cliente')),
            DropdownMenuItem(value: 'cocinero', child: Text('Cocinero')),
            DropdownMenuItem(value: 'repartidor', child: Text('Repartidor')),
            DropdownMenuItem(value: 'admin', child: Text('Administrador')),
          ],
          onChanged: (newRole) {
            if (newRole != null && newRole != role) {
              _updateUserRole(userId, newRole);
            }
          },
        ),
        children: [
          if (isAdmin)
            const ListTile(
              leading: Icon(Icons.lock_open, color: Colors.green),
              title: Text('Acceso total por rol Administrador'),
            )
          else
            ..._allModules.map((module) {
              return SwitchListTile(
                dense: true,
                title: Text(_moduleLabels[module]!),
                value: modules.contains(module),
                onChanged: (enabled) =>
                    _updateAllowedModules(userId, module, enabled),
              );
            }),
        ],
      ),
    );
  }
}
