import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/services/location_service.dart';

class OrdersDashboardScreen extends StatefulWidget {
  const OrdersDashboardScreen({super.key});

  @override
  State<OrdersDashboardScreen> createState() => _OrdersDashboardScreenState();
}

class _OrdersDashboardScreenState extends State<OrdersDashboardScreen> {
  final _supabase = Supabase.instance.client;

  Future<void> _updateStatus(int orderId, String newStatus) async {
    try {
      await _supabase
          .from('orders')
          .update({'status': newStatus})
          .eq('id', orderId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al actualizar estado: $e')),
        );
      }
    }
  }

  Future<void> _openNavigation(double? lat, double? lng) async {
    if (lat == null || lng == null) return;
    final url = Uri.parse(LocationService.getGoogleMapsUrl(lat, lng));
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  // Menú de opciones de contacto: Llamada telefónica o WhatsApp
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
                title: const Text('Llamar por Teléfono'),
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
                  // Prefijo de Guatemala (+502) si tiene 8 dígitos
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
  Future<void> _showOrderDetailsModal(int orderId, Map<String, dynamic> order) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.75,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Comanda: Orden #$orderId',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _supabase
                    .from('order_items')
                    .select('quantity, unit_price, notes, products(name, category)')
                    .eq('order_id', orderId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }

                  final items = snapshot.data ?? [];

                  if (items.isEmpty) {
                    return const Center(child: Text('No hay detalles registrados para esta orden.'));
                  }

                  return ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (context, i) {
                      final it = items[i];
                      final qty = it['quantity'] ?? 1;
                      final price = (it['unit_price'] ?? 0.0).toDouble();
                      final notes = it['notes'] as String?;
                      final prod = it['products'] as Map<String, dynamic>?;
                      final name = prod?['name'] ?? 'Producto';
                      final category = prod?['category'] ?? '';

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: Colors.deepOrange.shade100,
                          child: Text(
                            '$qty',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.deepOrange,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (category.isNotEmpty)
                              Text('Categoría: $category', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            if (notes != null && notes.isNotEmpty)
                              Text('Nota: $notes', style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        trailing: Text(
                          'Q${(qty * price).toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total a Cobrar:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text(
                  'Q${order['total']?.toString() ?? '0.00'}',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pendiente':
        return Colors.orange;
      case 'en cocina':
        return Colors.blue;
      case 'en camino':
        return Colors.purple;
      case 'entregado':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("K'OTEMAL - Panel de Cocina"),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _supabase
            .from('orders')
            .stream(primaryKey: ['id'])
            .order('id', ascending: false),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final orders = snapshot.data ?? [];

          if (orders.isEmpty) {
            return const Center(
              child: Text(
                'No hay pedidos registrados aún.',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: orders.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final order = orders[index];
              final orderId = order['id'] as int;
              final status = (order['status'] ?? 'pendiente') as String;
              final total = (order['total'] ?? 0.0).toString();
              final phone = order['customer_phone'] ?? 'Sin número';
              final notes = order['delivery_notes'] ?? 'Sin referencias';
              final isGuest = order['customer_id'] == null;
              final lat = order['delivery_latitude'] as double?;
              final lng = order['delivery_longitude'] as double?;
              final deliveryType = (order['delivery_type'] ?? 'domicilio') as String;
              final tableNumber = order['table_number']?.toString() ?? '';

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
                                color: _getStatusColor(status).withOpacity(0.15),
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
                        
                        // Teléfono clickeable para llamada o WhatsApp
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
                              isGuest ? Icons.person_outline : Icons.stars,
                              size: 16,
                              color: isGuest ? Colors.grey : Colors.amber.shade800,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isGuest ? 'Cliente Invitado' : 'Cliente Registrado (Suma Puntos)',
                              style: TextStyle(
                                color: isGuest ? Colors.grey.shade700 : Colors.amber.shade900,
                                fontSize: 13,
                                fontWeight: isGuest ? FontWeight.normal : FontWeight.bold,
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
                                DropdownMenuItem(value: 'en camino', child: Text('En camino')),
                                DropdownMenuItem(value: 'entregado', child: Text('Entregado')),
                              ],
                              onChanged: (val) {
                                if (val != null && val != status) {
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
            },
          );
        },
      ),
    );
  }
}