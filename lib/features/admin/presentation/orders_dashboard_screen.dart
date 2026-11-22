import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/order_alert_service.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/alert_settings_sheet.dart';

class OrdersDashboardScreen extends StatefulWidget {
  const OrdersDashboardScreen({super.key});

  @override
  State<OrdersDashboardScreen> createState() => _OrdersDashboardScreenState();
}

class _OrdersDashboardScreenState extends State<OrdersDashboardScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  late final TabController _tabController;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    OrderAlertService.instance.init();
    _checkRole();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _navigateToStatusTab(String status) {
    final index = switch (status) {
      'pendiente' => 0,
      'en cocina' => 1,
      'listo' => 2,
      'en camino' => 3,
      'entregado' || 'cancelado' => 4,
      _ => null,
    };

    if (index != null && _tabController.index != index) {
      _tabController.animateTo(index);
    }
  }

  Future<void> _checkRole() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      final res = await _supabase
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();

      if (mounted && res != null && res['role'] == 'admin') {
        setState(() => _isAdmin = true);
      }
    } catch (_) {
      // Si falla la consulta se mantiene el modo no-admin.
    }
  }

  Future<void> _updateStatus(int orderId, String newStatus) async {
    try {
      await _supabase
          .from('orders')
          .update({'status': newStatus})
          .eq('id', orderId);

      if (!mounted) return;
      _navigateToStatusTab(newStatus);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al actualizar estado: $e')),
        );
      }
    }
  }

  Future<void> _markAsPaid(int orderId, String method) async {
    try {
      await _supabase.from('orders').update({
        'status': 'entregado',
        'payment_status': 'pagado',
        'payment_method': method,
        'paid_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', orderId);

      if (!mounted) return;
      _navigateToStatusTab('entregado');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Orden #$orderId cobrada y entregada '
            '(${method == 'efectivo' ? 'Efectivo' : 'Transferencia'}).',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al registrar el pago: $e')),
        );
      }
    }
  }

  Future<void> _showPaymentMethodSheet(int orderId) async {
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'MÃ©todo de pago - Orden #$orderId',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  child: Icon(Icons.payments),
                ),
                title: const Text('Efectivo'),
                onTap: () {
                  Navigator.pop(ctx);
                  _markAsPaid(orderId, 'efectivo');
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  child: Icon(Icons.account_balance),
                ),
                title: const Text('Transferencia'),
                onTap: () {
                  Navigator.pop(ctx);
                  _markAsPaid(orderId, 'transferencia');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openNavigation(double? lat, double? lng) async {
    if (lat == null || lng == null) return;
    final url = Uri.parse(LocationService.getGoogleMapsUrl(lat, lng));
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  // MenÃº de opciones de contacto: Llamada telefÃ³nica o WhatsApp
  Future<void> _showContactOptions(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'\D'), ''); // Elimina espacios o guiones
    if (cleanPhone.isEmpty) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Contactar al Cliente ($phone)',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  child: Icon(Icons.call),
                ),
                title: const Text('Llamar por TelÃ©fono'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final uri = Uri.parse('tel:$cleanPhone');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri);
                  }
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  child: Icon(Icons.chat),
                ),
                title: const Text('Escribir por WhatsApp'),
                onTap: () async {
                  Navigator.pop(ctx);
                  // Prefijo de Guatemala (+502) si tiene 8 dÃ­gitos
                  final waNumber = cleanPhone.length == 8 ? '502$cleanPhone' : cleanPhone;
                  final uri = Uri.parse('https://wa.me/$waNumber?text=Hola,%20nos%20comunicamos%20de%20K\'OTEMAL%20sobre%20su%20pedido.');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Modal para ver los productos detallados que ordenÃ³ el cliente
  Future<void> _showOrderDetailsModal(
    int orderId,
    Map<String, dynamic> order,
  ) async {
    final deliveryType = (order['delivery_type'] ?? 'domicilio') as String;
    final tableNumber = order['table_number']?.toString() ?? '';
    final status = (order['status'] ?? 'pendiente') as String;
    final paymentStatus = (order['payment_status'] ?? 'pendiente') as String;
    final deliveryNotes = (order['delivery_notes'] ?? '').toString().trim();
    final rawCustomerName = (order['customer_name'] ?? '').toString().trim();
    final customerName =
        rawCustomerName.isEmpty ? 'Cliente sin nombre' : rawCustomerName;
    final hasDeliveryNotes =
        deliveryNotes.isNotEmpty && deliveryNotes != 'Sin referencias';
    final createdAt = order['created_at'] != null
        ? DateTime.tryParse(order['created_at'].toString())
        : null;

    final modeLabel = deliveryType == 'local'
        ? 'MESA #$tableNumber'
        : deliveryType == 'para_llevar'
            ? 'PARA LLEVAR'
            : 'DOMICILIO';
    final modeIcon = deliveryType == 'local'
        ? Icons.table_restaurant
        : deliveryType == 'para_llevar'
            ? Icons.takeout_dining
            : Icons.delivery_dining;

    String? nextStatus;
    String nextLabel = '';
    IconData nextIcon = Icons.arrow_forward;
    if (status == 'pendiente') {
      nextStatus = 'en cocina';
      nextLabel = 'Enviar a Cocina';
      nextIcon = Icons.soup_kitchen;
    } else if (status == 'en cocina') {
      nextStatus = 'listo';
      nextLabel = 'Marcar Listo';
      nextIcon = Icons.check_circle_outline;
    } else if (status == 'listo') {
      if (deliveryType == 'domicilio') {
        nextStatus = 'en camino';
        nextLabel = 'Marcar En Camino';
        nextIcon = Icons.two_wheeler;
      } else {
        nextStatus = 'entregado';
        nextLabel = 'Marcar Entregado';
        nextIcon = Icons.check_circle;
      }
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Color(0xFFFFFBF5),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 5,
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Orden #$orderId',
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.person,
                                    size: 18,
                                    color: Colors.deepOrange,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      customerName,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  _buildComandaBadge(
                                    icon: modeIcon,
                                    label: modeLabel,
                                    background: Colors.deepOrange.shade50,
                                    border: Colors.deepOrange.shade200,
                                    foreground: Colors.deepOrange.shade900,
                                  ),
                                  if (createdAt != null)
                                    _buildComandaBadge(
                                      icon: Icons.schedule,
                                      label: Formatters.dateTime(createdAt),
                                      background: Colors.grey.shade100,
                                      border: Colors.grey.shade300,
                                      foreground: Colors.grey.shade800,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    if (hasDeliveryNotes) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.amber.shade400),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.sticky_note_2,
                              size: 20,
                              color: Colors.amber.shade900,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                deliveryNotes,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.amber.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    Expanded(
                      child: FutureBuilder<List<Map<String, dynamic>>>(
                        future: _supabase
                            .from('order_items')
                            .select(
                              'quantity, unit_price, notes, '
                              'products(name, category)',
                            )
                            .eq('order_id', orderId),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }

                          if (snapshot.hasError) {
                            return Center(
                              child: Text('Error: ${snapshot.error}'),
                            );
                          }

                          final items = snapshot.data ?? [];

                          if (items.isEmpty) {
                            return const Center(
                              child: Text(
                                'No hay detalles registrados para esta orden.',
                              ),
                            );
                          }

                          return ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            itemCount: items.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, i) =>
                                _buildComandaItem(items[i]),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 10,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total a cobrar',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          Formatters.currency(
                            num.tryParse(order['total']?.toString() ?? '') ?? 0,
                          ),
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                    if (nextStatus != null) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepOrange,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () async {
                            Navigator.pop(ctx);
                            if (nextStatus == 'entregado' &&
                                paymentStatus != 'pagado') {
                              await _showPaymentMethodSheet(orderId);
                            } else {
                              await _updateStatus(orderId, nextStatus!);
                            }
                          },
                          icon: Icon(nextIcon),
                          label: Text(
                            nextLabel,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComandaBadge({
    required IconData icon,
    required String label,
    required Color background,
    required Color border,
    required Color foreground,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComandaItem(Map<String, dynamic> item) {
    final qty = (item['quantity'] as num?) ?? 1;
    final unitPrice = (item['unit_price'] ?? 0.0).toDouble();
    final subtotal = qty.toDouble() * unitPrice;
    final rawNotes = (item['notes'] ?? '').toString().trim();
    final prod = item['products'] as Map<String, dynamic>?;
    final name = prod?['name']?.toString() ?? 'Producto';
    final category = prod?['category']?.toString() ?? '';

    final removed = <String>[];
    final extras = <String>[];
    final observations = <String>[];

    if (rawNotes.isNotEmpty) {
      for (final section in rawNotes.split(' | ')) {
        final trimmed = section.trim();
        if (trimmed.isEmpty) continue;

        if (trimmed.startsWith('SIN: ')) {
          removed.addAll(
            trimmed
                .replaceFirst('SIN: ', '')
                .split(',')
                .map((value) => value.trim())
                .where((value) => value.isNotEmpty),
          );
        } else if (trimmed.startsWith('CON EXTRA: ')) {
          extras.addAll(
            trimmed
                .replaceFirst('CON EXTRA: ', '')
                .split(',')
                .map((value) => value.trim())
                .where((value) => value.isNotEmpty),
          );
        } else {
          observations.add(trimmed);
        }
      }
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.deepOrange,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${qty}x',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (category.isNotEmpty)
                      Text(
                        category,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                Formatters.currency(subtotal),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade800,
                ),
              ),
            ],
          ),
          if (removed.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildComandaNotesSection(
              title: 'SIN',
              icon: Icons.remove_circle_outline,
              items: removed,
              background: Colors.red.shade50,
              border: Colors.red.shade200,
              foreground: Colors.red.shade800,
            ),
          ],
          if (extras.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildComandaNotesSection(
              title: 'CON / EXTRAS',
              icon: Icons.add_circle_outline,
              items: extras,
              background: Colors.green.shade50,
              border: Colors.green.shade200,
              foreground: Colors.green.shade800,
            ),
          ],
          if (observations.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.edit_note,
                    size: 18,
                    color: Colors.orange.shade900,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      observations.join(' | '),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildComandaNotesSection({
    required String title,
    required IconData icon,
    required List<String> items,
    required Color background,
    required Color border,
    required Color foreground,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: foreground),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: foreground,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: items
                .map(
                  (label) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 13, color: foreground),
                        const SizedBox(width: 4),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: foreground,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pendiente':
        return Colors.orange;
      case 'en cocina':
        return Colors.blue;
      case 'listo':
        return Colors.teal;
      case 'en camino':
        return Colors.purple;
      case 'entregado':
        return Colors.green;
      case 'cancelado':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _supabase
          .from('orders')
          .stream(primaryKey: ['id'])
          .order('id', ascending: false),
      builder: (context, snapshot) {
        final allOrders = snapshot.data ?? [];

        final now = DateTime.now();
        final start = DateTime(now.year, now.month, now.day);
        final end = start.add(const Duration(days: 1));
        bool createdToday(Map<String, dynamic> order) {
          final raw = order['created_at'];
          if (raw == null) return false;
          final createdAt = DateTime.tryParse(raw.toString())?.toLocal();
          return createdAt != null &&
              !createdAt.isBefore(start) &&
              createdAt.isBefore(end);
        }

        final pendientes =
            allOrders.where((o) => o['status'] == 'pendiente').toList();
        final enCocina =
            allOrders.where((o) => o['status'] == 'en cocina').toList();
        final listos =
            allOrders.where((o) => o['status'] == 'listo').toList();
        final enCamino = allOrders
            .where((o) => o['status'] == 'en camino' && createdToday(o))
            .toList();
        final historialHoy = allOrders
            .where((o) =>
                (o['status'] == 'entregado' || o['status'] == 'cancelado') &&
                createdToday(o))
            .toList();

        return Scaffold(
          appBar: AppBar(
            title: const Text("K'OTEMAL - Panel de Cocina"),
            backgroundColor: Colors.deepOrange,
            foregroundColor: Colors.white,
            actions: [
              ListenableBuilder(
                listenable: OrderAlertService.instance,
                builder: (context, _) {
                  final soundEnabled = OrderAlertService.instance.soundEnabled;
                  return IconButton(
                    tooltip: soundEnabled
                        ? 'Silenciar alertas'
                        : 'Activar alertas',
                    icon: Icon(
                      soundEnabled ? Icons.volume_up : Icons.volume_off,
                    ),
                    onPressed: () =>
                        OrderAlertService.instance.toggleSound(),
                  );
                },
              ),
              IconButton(
                tooltip: 'Configurar alertas',
                icon: const Icon(Icons.record_voice_over),
                onPressed: () => showAlertSettingsSheet(context),
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(
                  icon: const Icon(Icons.receipt_long),
                  text: 'Pendientes (${pendientes.length})',
                ),
                Tab(
                  icon: const Icon(Icons.soup_kitchen),
                  text: 'En Cocina (${enCocina.length})',
                ),
                Tab(
                  icon: const Icon(Icons.check_circle_outline),
                  text: 'Listos (${listos.length})',
                ),
                Tab(
                  icon: const Icon(Icons.two_wheeler),
                  text: 'En Camino (${enCamino.length})',
                ),
                Tab(
                  icon: const Icon(Icons.history),
                  text: 'Historial (${historialHoy.length})',
                ),
              ],
            ),
          ),
          body: snapshot.connectionState == ConnectionState.waiting
              ? const Center(child: CircularProgressIndicator())
              : snapshot.hasError
                  ? Center(child: Text('Error: ${snapshot.error}'))
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildOrdersList(
                          pendientes,
                          'No hay pedidos pendientes.',
                        ),
                        _buildOrdersList(
                          enCocina,
                          'No hay pedidos en cocina.',
                        ),
                        _buildOrdersList(
                          listos,
                          'No hay pedidos listos para entregar.',
                        ),
                        _buildOrdersList(
                          enCamino,
                          'No hay pedidos en camino hoy.',
                        ),
                        _buildOrdersList(
                          historialHoy,
                          'No hay pedidos en el historial de hoy.',
                        ),
                      ],
                    ),
        );
      },
    );
  }

  Widget _buildOrdersList(
    List<Map<String, dynamic>> orders,
    String emptyMessage,
  ) {
    if (orders.isEmpty) {
      return Center(
        child: Text(
          emptyMessage,
          style: const TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: orders.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _buildOrderCard(orders[index]),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final orderId = order['id'] as int;
    final status = (order['status'] ?? 'pendiente') as String;
    final total = (order['total'] ?? 0.0).toString();
    final phone = order['customer_phone'] ?? 'Sin nÃºmero';
    final notes = order['delivery_notes'] ?? 'Sin referencias';
    final rawCustomerName = (order['customer_name'] ?? '').toString().trim();
    final customerName =
        rawCustomerName.isEmpty ? 'Cliente sin nombre' : rawCustomerName;
    final isGuest = order['customer_id'] == null;
    final lat = order['delivery_latitude'] as double?;
    final lng = order['delivery_longitude'] as double?;
    final deliveryType = (order['delivery_type'] ?? 'domicilio') as String;
    final tableNumber = order['table_number']?.toString() ?? '';
    final paymentStatus = (order['payment_status'] ?? 'pendiente') as String;
    final paymentMethod = order['payment_method'] as String?;
    final isPaid = paymentStatus == 'pagado';
    final paymentLabel = paymentMethod == 'efectivo'
        ? 'Efectivo'
        : paymentMethod == 'transferencia'
            ? 'Transferencia'
            : 'Sin mÃ©todo';

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showOrderDetailsModal(orderId, order), // Tocar la tarjeta abre el detalle de productos
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        'Orden #$orderId',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.touch_app, size: 16, color: Colors.grey),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getStatusColor(status).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _getStatusColor(status)),
                    ),
                    child: Text(
                      status.toUpperCase(),
                      style: TextStyle(
                        color: _getStatusColor(status),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(),
              Row(
                children: [
                  Icon(
                    deliveryType == 'local'
                        ? Icons.table_restaurant
                        : deliveryType == 'para_llevar'
                            ? Icons.takeout_dining
                            : Icons.delivery_dining,
                    size: 18,
                    color: Colors.deepOrange,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    deliveryType == 'local'
                        ? 'MESA: $tableNumber (Consumo en Local)'
                        : deliveryType == 'para_llevar'
                            ? 'PARA LLEVAR (Mostrador)'
                            : 'A DOMICILIO (Delivery)',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // TelÃ©fono clickeable para llamada o WhatsApp
              InkWell(
                onTap: () => _showContactOptions(phone),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.phone_in_talk, size: 16, color: Colors.blue),
                    const SizedBox(width: 6),
                    Text(
                      phone,
                      style: const TextStyle(
                        fontSize: 15,
                        color: Colors.blue,
                        decoration: TextDecoration.underline,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.chat, size: 16, color: Colors.green),
                  ],
                ),
              ),

              if (notes.isNotEmpty && notes != 'Sin referencias') ...[
                const SizedBox(height: 6),
                Text('Detalles / Referencia: $notes', style: const TextStyle(color: Colors.black87)),
              ],
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    isGuest ? Icons.person_outline : Icons.person,
                    size: 18,
                    color: isGuest ? Colors.grey : Colors.amber.shade800,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      customerName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    isGuest ? 'Cliente Invitado' : 'Cliente Registrado (Suma Puntos)',
                    style: TextStyle(
                      color: isGuest ? Colors.grey.shade700 : Colors.amber.shade900,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Total: Q$total',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    isPaid ? Icons.verified : Icons.payments_outlined,
                    size: 18,
                    color: isPaid ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      isPaid ? 'Pagado ($paymentLabel)' : 'Pago pendiente',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isPaid ? Colors.green : Colors.orange,
                      ),
                    ),
                  ),
                  if (_isAdmin && !isPaid)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.green,
                        side: const BorderSide(color: Colors.green),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () => _showPaymentMethodSheet(orderId),
                      icon: const Icon(Icons.price_check, size: 18),
                      label: const Text('Marcar Pagado'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (deliveryType == 'domicilio' && lat != null && lng != null)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => _openNavigation(lat, lng),
                      icon: const Icon(Icons.directions, size: 18),
                      label: const Text('Ruta Maps'),
                    ),
                  const Spacer(),
                  DropdownButton<String>(
                    value: status,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 'pendiente', child: Text('Pendiente')),
                      DropdownMenuItem(value: 'en cocina', child: Text('En cocina')),
                      DropdownMenuItem(value: 'listo', child: Text('Listo')),
                      DropdownMenuItem(value: 'en camino', child: Text('En camino')),
                      DropdownMenuItem(value: 'entregado', child: Text('Entregado')),
                      DropdownMenuItem(value: 'cancelado', child: Text('Cancelado')),
                    ],
                    onChanged: (val) {
                      if (val == null || val == status) return;

                      if (val == 'entregado' && paymentStatus != 'pagado') {
                        // No se permite entregar sin cobrar: primero se elige el mÃ©todo.
                        _showPaymentMethodSheet(orderId);
                      } else {
                        _updateStatus(orderId, val);
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
