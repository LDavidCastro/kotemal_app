import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../orders/presentation/order_tracking_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  Map<String, dynamic>? _profileData;
  String? _userEmail;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    _userEmail = user.email;

    try {
      final data = await _supabase
          .from('profiles')
          .select('full_name, phone, role, points')
          .eq('id', user.id)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _profileData = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar perfil: $e')),
        );
      }
    }
  }

  Future<void> _signOut() async {
    await _supabase.auth.signOut();
    if (mounted) Navigator.pop(context, true);
  }

  void _showMyOrdersModal() {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(ctx).size.height * 0.7,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Mis Pedidos Recientes',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Divider(),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _supabase
                      .from('orders')
                      .select('id, total, status, created_at')
                      .eq('customer_id', user.id)
                      .order('id', ascending: false),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final orders = snapshot.data ?? [];
                    if (orders.isEmpty) {
                      return const Center(child: Text('No tienes pedidos aún.'));
                    }
                    return ListView.separated(
                      itemCount: orders.length,
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (context, index) {
                        final ord = orders[index];
                        final id = ord['id'] as int;
                        final total = ord['total'];
                        final st = ord['status'];

                        return ListTile(
                          leading: const Icon(Icons.delivery_dining, color: Colors.deepOrange),
                          title: Text('Orden #$id - Q$total', style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('Estado: ${st.toString().toUpperCase()}'),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: () {
                            Navigator.pop(ctx);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => OrderTrackingScreen(orderId: id),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mi Perfil')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final name = _profileData?['full_name'] ?? 'Usuario K\'OTEMAL';
    final phone = _profileData?['phone'] ?? 'Sin número';
    final role = (_profileData?['role'] ?? 'cliente').toString().toUpperCase();
    final points = _profileData?['points'] ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Información de Perfil'),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Center(
              child: CircleAvatar(
                radius: 45,
                backgroundColor: Colors.deepOrange.shade100,
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : 'U',
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.deepOrange,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            Text(_userEmail ?? '', style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
            const SizedBox(height: 10),
            Chip(
              label: Text('ROL: $role', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              backgroundColor: Colors.orange.shade50,
            ),
            const SizedBox(height: 20),

            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              child: ListTile(
                leading: const Icon(Icons.stars, color: Colors.amber, size: 36),
                title: const Text('Puntos K\'OTEMAL'),
                subtitle: Text('$points Puntos acumulados'),
              ),
            ),
            const SizedBox(height: 10),

            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              child: ListTile(
                leading: const Icon(Icons.phone, color: Colors.deepOrange),
                title: const Text('Teléfono'),
                subtitle: Text(phone),
              ),
            ),
            const SizedBox(height: 10),

            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              child: ListTile(
                leading: const Icon(Icons.receipt_long, color: Colors.blue),
                title: const Text('Mis Pedidos'),
                subtitle: const Text('Consultar estado y ver ruta en el mapa'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: _showMyOrdersModal,
              ),
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                ),
                onPressed: _signOut,
                icon: const Icon(Icons.logout),
                label: const Text('Cerrar Sesión'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}