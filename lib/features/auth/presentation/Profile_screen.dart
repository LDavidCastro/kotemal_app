import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/update_service.dart';
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
            const SizedBox(height: 14),

            // Sección para comprobar y descargar actualizaciones
            const _AppUpdateSection(),

            const SizedBox(height: 20),

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

class _AppUpdateSection extends StatefulWidget {
  const _AppUpdateSection();

  @override
  State<_AppUpdateSection> createState() => _AppUpdateSectionState();
}

class _AppUpdateSectionState extends State<_AppUpdateSection> {
  bool _isChecking = false;
  AppUpdateInfo? _updateInfo;
  String? _downloadProgress;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() => _isChecking = true);
    final info = await UpdateService.checkForUpdate();
    if (mounted) {
      setState(() {
        _updateInfo = info;
        _isChecking = false;
      });
    }
  }

  void _startUpdate(String apkUrl) {
    try {
      UpdateService.downloadAndInstall(apkUrl).listen((OtaEvent event) {
        setState(() {
          if (event.status == OtaStatus.DOWNLOADING) {
            _downloadProgress = 'Descargando actualización: ${event.value}%';
          } else if (event.status == OtaStatus.INSTALLING) {
            _downloadProgress = 'Abriendo instalador del sistema...';
          } else {
            _downloadProgress = null;
          }
        });
      }, onError: (e) {
        setState(() => _downloadProgress = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al descargar actualización: $e')),
        );
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo iniciar la descarga: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.system_update, color: Colors.deepOrange),
                const SizedBox(width: 8),
                const Text(
                  'Versión del Sistema',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_isChecking)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    tooltip: 'Buscar actualizaciones',
                    onPressed: _check,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Versión actual: v${_updateInfo?.currentVersion ?? '1.0.0'}',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
            ),
            const SizedBox(height: 10),

            if (_downloadProgress != null) ...[
              LinearProgressIndicator(color: Colors.deepOrange, backgroundColor: Colors.orange.shade100),
              const SizedBox(height: 6),
              Text(_downloadProgress!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ] else if (_updateInfo != null && _updateInfo!.hasUpdate && _updateInfo!.downloadUrl != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '¡Nueva versión v${_updateInfo!.latestVersion} disponible!',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade900),
                    ),
                    if (_updateInfo!.releaseNotes != null && _updateInfo!.releaseNotes!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(_updateInfo!.releaseNotes!, style: const TextStyle(fontSize: 12)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.download),
                  label: const Text('Descargar e Instalar Actualización'),
                  onPressed: () => _startUpdate(_updateInfo!.downloadUrl!),
                ),
              ),
            ] else if (!_isChecking) ...[
              const Text(
                '✓ Cuentas con la versión más reciente.',
                style: TextStyle(color: Colors.green, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
      ),
    );
  }
}