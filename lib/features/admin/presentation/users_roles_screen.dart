import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UsersRolesScreen extends StatefulWidget {
  const UsersRolesScreen({super.key});

  @override
  State<UsersRolesScreen> createState() => _UsersRolesScreenState();
}

class _UsersRolesScreenState extends State<UsersRolesScreen> {
  final _supabase = Supabase.instance.client;

  Future<void> _updateUserRole(String userId, String newRole) async {
    try {
      await _supabase
          .from('profiles')
          .update({'role': newRole})
          .eq('id', userId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Rol actualizado a $newRole')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cambiar rol: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Usuarios y Roles'),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _supabase.from('profiles').stream(primaryKey: ['id']),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final users = snapshot.data ?? [];

          if (users.isEmpty) {
            return const Center(child: Text('No hay usuarios registrados.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: users.length,
            separatorBuilder: (_, _) => const Divider(),
            itemBuilder: (context, index) {
              final user = users[index];
              final userId = user['id'] as String;
              final name = user['full_name'] ?? 'Sin nombre';
              final phone = user['phone'] ?? 'Sin teléfono';
              final currentRole = (user['role'] ?? 'cliente') as String;
              final points = user['points'] ?? 0;

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: currentRole == 'admin'
                      ? Colors.red.shade100
                      : currentRole == 'repartidor'
                          ? Colors.blue.shade100
                          : currentRole == 'cocinero'
                              ? Colors.amber.shade100
                              : Colors.grey.shade200,
                  child: Icon(
                    currentRole == 'admin'
                        ? Icons.security
                        : currentRole == 'repartidor'
                            ? Icons.two_wheeler
                            : currentRole == 'cocinero'
                                ? Icons.restaurant
                                : Icons.person,
                    color: Colors.black87,
                  ),
                ),
                title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('Tel: $phone | Puntos: $points'),
                trailing: DropdownButton<String>(
                  value: currentRole,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 'cliente', child: Text('Cliente')),
                    DropdownMenuItem(value: 'cocinero', child: Text('Cocinero')),
                    DropdownMenuItem(value: 'repartidor', child: Text('Repartidor')),
                    DropdownMenuItem(value: 'admin', child: Text('Administrador')),
                  ],
                  onChanged: (newRole) {
                    if (newRole != null && newRole != currentRole) {
                      _updateUserRole(userId, newRole);
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}