import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
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
          .update({
            'status': newStatus,
            // Nunca tocar delivery_driver_id ni delivery_type al cambiar estado.
          })
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

  // Modal para ver los productos detallados que ordenó el cliente
  Future<void> _showOrderDetailsModal(
    int orderId,
    Map<String, dynamic> order,
  ) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _OrderDetailsSheet(
        orderId: orderId,
        order: order,
        supabase: _supabase,
        onUpdateStatus: _updateStatus,
        onChoosePaymentMethod: _showPaymentMethodSheet,
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
            title: const Text(
              "K'OTEMAL - Panel de Cocina",
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: AppColors.secondary,
            foregroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
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
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              indicatorColor: Colors.white,
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

  /// Píldora suave para agrupar información secundaria de la tarjeta.
  Widget _buildInfoPill({
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
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.2,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }

  /// Distingue visualmente entre cliente registrado y cliente invitado.
  Widget _buildCustomerBadge({required bool isGuest}) {
    final foreground = isGuest
        ? const Color(0xFF757575)
        : const Color(0xFF9A6B1F);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isGuest ? const Color(0xFFF4F4F4) : const Color(0xFFFBF3DE),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isGuest ? const Color(0xFFE0E0E0) : const Color(0xFFEBD9AE),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isGuest ? Icons.person_outline : Icons.star_rounded,
            size: 13,
            color: foreground,
          ),
          const SizedBox(width: 4),
          Text(
            isGuest ? 'Invitado' : 'Suma puntos',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final orderId = order['id'] as int;
    final status = (order['status'] ?? 'pendiente') as String;
    final rawTotal = order['total'];
    final total = rawTotal is num
        ? rawTotal.toDouble()
        : double.tryParse(rawTotal?.toString() ?? '') ?? 0.0;
    final phone = (order['customer_phone'] ?? 'Sin número').toString();
    final notes = (order['delivery_notes'] ?? 'Sin referencias').toString();
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

    final hasRoute = deliveryType == 'domicilio' && lat != null && lng != null;
    final modeLabel = deliveryType == 'local'
        ? (tableNumber.isEmpty ? 'MESA' : 'MESA $tableNumber')
        : deliveryType == 'para_llevar'
            ? 'PARA LLEVAR'
            : 'A DOMICILIO';
    final modeIcon = deliveryType == 'local'
        ? Icons.table_restaurant
        : deliveryType == 'para_llevar'
            ? Icons.takeout_dining
            : Icons.delivery_dining;
    final hasNotes = notes.isNotEmpty && notes != 'Sin referencias';

    // Selector de estado tipo píldora, usado en el pie de la tarjeta.
    final statusSelector = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF3ECE4),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFD5C8BC)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: status,
          isDense: true,
          borderRadius: BorderRadius.circular(16),
          icon: const Icon(
            Icons.expand_more,
            size: 18,
            color: AppColors.primary,
          ),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
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
              // No se permite entregar sin cobrar: primero se elige el método.
              _showPaymentMethodSheet(orderId);
            } else {
              _updateStatus(orderId, val);
            }
          },
        ),
      ),
    );

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE6DDD4)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showOrderDetailsModal(orderId, order), // Tocar la tarjeta abre el detalle de productos
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
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
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF6EFEA),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Ver detalle ›',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF8C6D62),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _getStatusColor(status).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _getStatusColor(status).withValues(alpha: 0.6),
                          ),
                        ),
                        child: Text(
                          status.toUpperCase(),
                          style: TextStyle(
                            color: _getStatusColor(status),
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Q${total.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildInfoPill(
                    icon: modeIcon,
                    label: modeLabel,
                    background: const Color(0xFFFBF1EC),
                    border: const Color(0xFFEBD5C8),
                    foreground: AppColors.secondary,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    isGuest ? Icons.person_outline : Icons.person,
                    size: 16,
                    color: isGuest
                        ? const Color(0xFF9E9E9E)
                        : AppColors.secondary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      customerName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _buildCustomerBadge(isGuest: isGuest),
                ],
              ),
              const SizedBox(height: 8),

              // Teléfono clickeable para llamada o WhatsApp
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _showContactOptions(phone),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F8FB),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFDCE7F0)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.phone_in_talk,
                        size: 15,
                        color: Color(0xFF2F6690),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        phone,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF2F6690),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.chat_bubble_outline,
                        size: 15,
                        color: Color(0xFF3E9C5C),
                      ),
                    ],
                  ),
                ),
              ),

              if (hasNotes) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.sticky_note_2_outlined,
                      size: 15,
                      color: Color(0xFF8C6D62),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Referencia: $notes',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              const Divider(
                height: 1,
                thickness: 1,
                color: Color(0xFFE6DDD4),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    isPaid ? Icons.verified : Icons.payments_outlined,
                    size: 18,
                    color: isPaid
                        ? Colors.green.shade700
                        : Colors.orange.shade800,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      isPaid ? 'Pagado ($paymentLabel)' : 'Pago pendiente',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isPaid
                            ? Colors.green.shade700
                            : Colors.orange.shade800,
                      ),
                    ),
                  ),
                  if (_isAdmin && !isPaid)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.green.shade700,
                        side: BorderSide(color: Colors.green.shade400),
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: () => _showPaymentMethodSheet(orderId),
                      icon: const Icon(Icons.price_check, size: 16),
                      label: const Text('Marcar Pagado'),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (hasRoute) ...[
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF2F6690),
                        backgroundColor: const Color(0xFFF4F8FB),
                        side: const BorderSide(color: Color(0xFFDCE7F0)),
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: () => _openNavigation(lat, lng),
                      icon: const Icon(Icons.map_outlined, size: 16),
                      label: const Text('Ruta Maps'),
                    ),
                    const Spacer(),
                  ],
                  statusSelector,
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `true` si el platillo fue marcado como preparado dentro de sus notas.
bool _isItemPrepared(String? notes) => (notes ?? '').startsWith('[LISTO]');

/// Quita el prefijo `[LISTO]` de las notas para que el parser de
/// `OPCIÓN:`, `SIN:` y `CON EXTRA:` siga funcionando igual que siempre.
String _cleanItemNotes(String? notes) {
  final raw = notes ?? '';
  if (raw.startsWith('[LISTO] ')) return raw.substring('[LISTO] '.length);
  if (raw.startsWith('[LISTO]')) return raw.substring('[LISTO]'.length);
  return raw;
}

/// Alterna el prefijo `[LISTO]` conservando intactas las notas originales.
String _toggleItemPreparedNotes(String? notes, bool prepared) {
  final cleaned = _cleanItemNotes(notes).trim();
  if (!prepared) return cleaned;
  return cleaned.isEmpty ? '[LISTO]' : '[LISTO] $cleaned';
}

/// Modal de detalle de una orden con verificación platillo por platillo.
class _OrderDetailsSheet extends StatefulWidget {
  final int orderId;
  final Map<String, dynamic> order;
  final SupabaseClient supabase;
  final Future<void> Function(int orderId, String newStatus) onUpdateStatus;
  final Future<void> Function(int orderId) onChoosePaymentMethod;

  const _OrderDetailsSheet({
    required this.orderId,
    required this.order,
    required this.supabase,
    required this.onUpdateStatus,
    required this.onChoosePaymentMethod,
  });

  @override
  State<_OrderDetailsSheet> createState() => _OrderDetailsSheetState();
}

class _OrderDetailsSheetState extends State<_OrderDetailsSheet> {
  List<Map<String, dynamic>>? _items;
  String? _itemsError;
  final Set<int> _savingItemIds = {};

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    try {
      final res = await widget.supabase
          .from('order_items')
          .select('id, quantity, unit_price, notes, products(name, category)')
          .eq('order_id', widget.orderId);

      if (!mounted) return;
      setState(() {
        _items = List<Map<String, dynamic>>.from(res);
        _itemsError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _itemsError = e.toString());
    }
  }

  int get _totalCount => _items?.length ?? 0;

  int get _preparedCount => (_items ?? [])
      .where((item) => _isItemPrepared(item['notes']?.toString()))
      .length;

  Future<void> _toggleItemPrepared(int index) async {
    final items = _items;
    if (items == null || index < 0 || index >= items.length) return;

    final item = items[index];
    final itemId = item['id'] as int?;
    if (itemId == null || _savingItemIds.contains(itemId)) return;

    final previousNotes = item['notes']?.toString();
    final willBePrepared = !_isItemPrepared(previousNotes);
    final newNotes = _toggleItemPreparedNotes(previousNotes, willBePrepared);

    // Actualización optimista para respuesta inmediata en cocina.
    setState(() {
      items[index] = {...item, 'notes': newNotes};
      _savingItemIds.add(itemId);
    });

    try {
      await widget.supabase
          .from('order_items')
          .update({'notes': newNotes})
          .eq('id', itemId);
    } catch (e) {
      if (!mounted) return;
      setState(() => items[index] = item);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo actualizar el platillo: $e')),
      );
    } finally {
      if (mounted) setState(() => _savingItemIds.remove(itemId));
    }
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

  Widget _buildItemsList() {
    if (_itemsError != null) {
      return Center(child: Text('Error: $_itemsError'));
    }

    final items = _items;
    if (items == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (items.isEmpty) {
      return const Center(
        child: Text('No hay detalles registrados para esta orden.'),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 14),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final itemId = items[i]['id'] as int?;
        final isSaving = itemId != null && _savingItemIds.contains(itemId);
        return _buildComandaItem(
          items[i],
          isSaving: isSaving,
          onToggle: itemId == null || isSaving
              ? null
              : () => _toggleItemPrepared(i),
        );
      },
    );
  }

  Widget _buildPreparedProgress() {
    final total = _totalCount;
    final prepared = _preparedCount;
    final allDone = total > 0 && prepared == total;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: allDone ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: allDone ? Colors.green.shade400 : Colors.orange.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                allDone ? Icons.check_circle : Icons.kitchen,
                size: 18,
                color: allDone ? Colors.green.shade700 : Colors.orange.shade800,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Preparados: $prepared de $total platillos',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color:
                        allDone ? Colors.green.shade800 : Colors.orange.shade900,
                  ),
                ),
              ),
              if (allDone)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'TODO LISTO',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : prepared / total,
              minHeight: 8,
              backgroundColor: Colors.white,
              valueColor: AlwaysStoppedAnimation<Color>(
                allDone ? Colors.green : Colors.orange,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComandaItem(
    Map<String, dynamic> item, {
    required bool isSaving,
    required VoidCallback? onToggle,
  }) {
    final qty = (item['quantity'] as num?) ?? 1;
    final unitPrice = (item['unit_price'] ?? 0.0).toDouble();
    final subtotal = qty.toDouble() * unitPrice;
    final isPrepared = _isItemPrepared(item['notes']?.toString());
    final rawNotes = _cleanItemNotes(item['notes']?.toString()).trim();
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

    final accentColor =
        isPrepared ? Colors.green.shade700 : Colors.red.shade700;
    final backgroundColor =
        isPrepared ? Colors.green.shade50 : Colors.red.shade50;
    final borderColor =
        isPrepared ? Colors.green.shade500 : Colors.red.shade300;

    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onToggle,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
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
                      color: isPrepared
                          ? Colors.green.shade600
                          : AppColors.secondary,
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
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isPrepared
                                ? Colors.grey.shade600
                                : Colors.black87,
                            decoration: isPrepared
                                ? TextDecoration.lineThrough
                                : TextDecoration.none,
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
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: isPrepared
                                  ? 'Marcar como pendiente'
                                  : 'Marcar como preparado',
                              onPressed: onToggle,
                              icon: isSaving
                                  ? SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: accentColor,
                                      ),
                                    )
                                  : Icon(
                                      isPrepared
                                          ? Icons.check_circle
                                          : Icons.radio_button_unchecked,
                                      color: accentColor,
                                      size: 24,
                                    ),
                            ),
                            const SizedBox(width: 6),
                            _buildComandaBadge(
                              icon: isPrepared ? Icons.check : Icons.schedule,
                              label: isPrepared ? 'LISTO' : 'PENDIENTE',
                              background: isPrepared
                                  ? Colors.green.shade100
                                  : Colors.red.shade100,
                              border: borderColor,
                              foreground: accentColor,
                            ),
                          ],
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
        ),
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

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final orderId = widget.orderId;
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

    final showProgress = _items != null && _items!.isNotEmpty;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
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
                                  color: AppColors.secondary,
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
                                  background: AppColors.surface,
                                  border: AppColors.border,
                                  foreground: AppColors.secondary,
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
                        onPressed: () => Navigator.pop(context),
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
                  if (showProgress) ...[
                    const SizedBox(height: 12),
                    _buildPreparedProgress(),
                    const SizedBox(height: 4),
                  ],
                  Expanded(child: _buildItemsList()),
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
                          Navigator.pop(context);
                          if (nextStatus == 'entregado' &&
                              paymentStatus != 'pagado') {
                            await widget.onChoosePaymentMethod(orderId);
                          } else {
                            await widget.onUpdateStatus(orderId, nextStatus!);
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
    );
  }
}
