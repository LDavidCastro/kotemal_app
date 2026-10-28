import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OrderTrackingScreen extends StatefulWidget {
  final int orderId;
  const OrderTrackingScreen({super.key, required this.orderId});

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen> {
  final _supabase = Supabase.instance.client;
  // Local K'OTEMAL (Sololá)
  final LatLng _restaurantLocation = const LatLng(14.643973, -91.120232);

  int _getDeliveryStatusStep(String status) {
    switch (status) {
      case 'pendiente':
        return 0;
      case 'en cocina':
        return 1;
      case 'en camino':
        return 2;
      case 'entregado':
        return 3;
      default:
        return 0;
    }
  }

  int _getOnSiteStatusStep(String status) {
    switch (status) {
      case 'pendiente':
        return 0;
      case 'en cocina':
        return 1;
      case 'entregado':
        return 2;
      default:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("K'OTEMAL - Orden #${widget.orderId}"),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _supabase
            .from('orders')
            .stream(primaryKey: ['id'])
            .eq('id', widget.orderId),
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          final order = snapshot.data!.first;
          final status = (order['status'] ?? 'pendiente') as String;
          final deliveryType = (order['delivery_type'] ?? 'domicilio') as String;
          final tableNumber = order['table_number']?.toString() ?? '';
          final total = order['total']?.toString() ?? '0.0';
          final isDelivery = deliveryType == 'domicilio';

          // VISTA 1: Pedidos en Local o Para Llevar (Sin Mapa)
          if (!isDelivery) {
            final onSiteStep = _getOnSiteStatusStep(status);
            final isReady = status == 'entregado';

            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  const Spacer(),
                  // Icono representativo
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: isReady ? Colors.green.shade100 : Colors.orange.shade100,
                    child: Icon(
                      isReady
                          ? Icons.check_circle
                          : (deliveryType == 'local' ? Icons.table_restaurant : Icons.takeout_dining),
                      size: 60,
                      color: isReady ? Colors.green : Colors.deepOrange,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '¡Pedido Registrado con Éxito!',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    deliveryType == 'local'
                        ? 'Consumo en mesa: $tableNumber'
                        : 'Pedido para recoger en mostrador',
                    style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: isReady ? Colors.green.shade50 : Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isReady ? Colors.green : Colors.amber.shade800),
                    ),
                    child: Text(
                      isReady ? '¡TU PEDIDO ESTÁ LISTO!' : 'ESTADO: ${status.toUpperCase()}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isReady ? Colors.green.shade800 : Colors.amber.shade900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),

                  // Barra de progreso de cocina
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _StatusIcon(icon: Icons.receipt, label: 'Recibido', active: onSiteStep >= 0),
                      _StatusLine(active: onSiteStep >= 1),
                      _StatusIcon(icon: Icons.soup_kitchen, label: 'En Cocina', active: onSiteStep >= 1),
                      _StatusLine(active: onSiteStep >= 2),
                      _StatusIcon(
                        icon: deliveryType == 'local' ? Icons.restaurant : Icons.shopping_bag,
                        label: deliveryType == 'local' ? 'Servido' : 'Listo',
                        active: onSiteStep >= 2,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Mensaje orientador para el comensal
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Icon(
                            isReady ? Icons.notifications_active : Icons.hourglass_top,
                            color: isReady ? Colors.green : Colors.deepOrange,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              deliveryType == 'local'
                                  ? (isReady
                                      ? 'Tu comida ya está lista y será servida en tu mesa.'
                                      : 'Tu orden se está preparando en la cocina. Enseguida te la llevamos a la mesa.')
                                  : (isReady
                                      ? '¡Ya puedes pasar al mostrador a retirar tu comida!'
                                      : 'Tu orden está en preparación. Te avisaremos cuando puedas recogerla.'),
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Total: Q$total', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const Spacer(),

                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepOrange,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                      child: const Text('Volver al Menú Principal'),
                    ),
                  ),
                ],
              ),
            );
          }

          // VISTA 2: Pedidos A Domicilio (Con Mapa y Repartidor)
          final lat = order['delivery_latitude'] as double? ?? 14.643973;
          final lng = order['delivery_longitude'] as double? ?? -91.120232;
          final clientLocation = LatLng(lat, lng);

          final driverLat = order['driver_latitude'] as double?;
          final driverLng = order['driver_longitude'] as double?;
          final driverLocation = (driverLat != null && driverLng != null)
              ? LatLng(driverLat, driverLng)
              : null;

          final currentStep = _getDeliveryStatusStep(status);

          return Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.orange.shade50,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _StatusIcon(icon: Icons.receipt, label: 'Recibido', active: currentStep >= 0),
                        _StatusLine(active: currentStep >= 1),
                        _StatusIcon(icon: Icons.soup_kitchen, label: 'En cocina', active: currentStep >= 1),
                        _StatusLine(active: currentStep >= 2),
                        _StatusIcon(icon: Icons.two_wheeler, label: 'En camino', active: currentStep >= 2),
                        _StatusLine(active: currentStep >= 3),
                        _StatusIcon(icon: Icons.home, label: 'Entregado', active: currentStep >= 3),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'ESTADO: ${status.toUpperCase()}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepOrange),
                    ),
                    if (status == 'en camino' && driverLocation != null)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          '🏍️ ¡El repartidor va en camino! Puedes ver su avance en el mapa.',
                          style: TextStyle(fontSize: 12, color: Colors.blueAccent, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: clientLocation,
                    initialZoom: 14,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.kotemal.app',
                    ),
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: [
                            driverLocation ?? _restaurantLocation,
                            clientLocation,
                          ],
                          strokeWidth: 4,
                          color: Colors.blueAccent,
                        ),
                      ],
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _restaurantLocation,
                          width: 45,
                          height: 45,
                          child: const Icon(Icons.store, color: Colors.deepOrange, size: 38),
                        ),
                        Marker(
                          point: clientLocation,
                          width: 45,
                          height: 45,
                          child: const Icon(Icons.location_on, color: Colors.red, size: 40),
                        ),
                        if (driverLocation != null && status == 'en camino')
                          Marker(
                            point: driverLocation,
                            width: 45,
                            height: 45,
                            child: const CircleAvatar(
                              backgroundColor: Colors.blue,
                              child: Icon(Icons.two_wheeler, color: Colors.white, size: 26),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  height: 45,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                    child: const Text('Volver al Menú Principal'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;

  const _StatusIcon({
    required this.icon,
    required this.label,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: active ? Colors.deepOrange : Colors.grey.shade300,
          foregroundColor: Colors.white,
          child: Icon(icon, size: 20),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
            color: active ? Colors.black87 : Colors.grey,
          ),
        ),
      ],
    );
  }
}

class _StatusLine extends StatelessWidget {
  final bool active;
  const _StatusLine({required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 25,
      height: 3,
      color: active ? Colors.deepOrange : Colors.grey.shade300,
    );
  }
}