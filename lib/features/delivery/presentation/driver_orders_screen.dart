import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/services/location_service.dart';

class DriverOrdersScreen extends StatefulWidget {
  const DriverOrdersScreen({super.key});

  @override
  State<DriverOrdersScreen> createState() => _DriverOrdersScreenState();
}

class _DriverOrdersScreenState extends State<DriverOrdersScreen> {
  final _supabase = Supabase.instance.client;
  StreamSubscription<Position>? _positionStream;
  int? _activeOrderId;

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  void _startSharingLocation(int orderId) {
    setState(() => _activeOrderId = orderId);

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    _positionStream?.cancel();
    _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings)
        .listen((Position position) async {
      await _supabase.from('orders').update({
        'driver_latitude': position.latitude,
        'driver_longitude': position.longitude,
      }).eq('id', orderId);
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ubicación en tiempo real activada para el cliente.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _stopSharingLocation() {
    _positionStream?.cancel();
    if (mounted) {
      setState(() => _activeOrderId = null);
    }
  }

  Future<void> _takeOrder(int orderId) async {
    final driverId = _supabase.auth.currentUser?.id;
    if (driverId == null) return;

    try {
      await _supabase.from('orders').update({
        'delivery_driver_id': driverId,
        'status': 'en camino',
      }).eq('id', orderId);

      _startSharingLocation(orderId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al tomar pedido: $e')),
        );
      }
    }
  }

  Future<void> _releaseOrder(int orderId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Soltar pedido'),
        content: const Text(
          '¿Deseas deseleccionar este pedido para que otro repartidor pueda llevarlo?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Soltar Pedido', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (!mounted || confirm != true) return;

    try {
      await _supabase.from('orders').update({
        'delivery_driver_id': null,
        'status': 'en cocina',
      }).eq('id', orderId);

      _stopSharingLocation();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pedido devuelto a la lista general.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al soltar pedido: $e')),
        );
      }
    }
  }

  Future<void> _confirmCompleteDelivery(int orderId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar Entrega'),
        content: const Text('¿Confirmas que ya entregaste este pedido al cliente?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No, aún no'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, Entregado', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (!mounted || confirm != true) return;

    try {
      await _supabase.from('orders').update({
        'status': 'entregado',
      }).eq('id', orderId);

      _stopSharingLocation();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('¡Pedido marcado como entregado!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al completar pedido: $e')),
        );
      }
    }
  }

  Future<void> _revertToOnTheWay(int orderId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reactivar Pedido'),
        content: const Text(
          '¿Marcaste este pedido como entregado por error? Volverá a estar "En camino".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reactivar Entrega'),
          ),
        ],
      ),
    );

    if (!mounted || confirm != true) return;

    final driverId = _supabase.auth.currentUser?.id;
    try {
      await _supabase.from('orders').update({
        'delivery_driver_id': driverId,
        'status': 'en camino',
      }).eq('id', orderId);

      _startSharingLocation(orderId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('El pedido vuelve a estar en camino.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al reactivar pedido: $e')),
        );
      }
    }
  }

  Future<void> _openMaps(double? lat, double? lng) async {
    if (lat == null || lng == null) return;
    final url = Uri.parse(LocationService.getGoogleMapsUrl(lat, lng));
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentDriverId = _supabase.auth.currentUser?.id;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Rutas y Entregas'),
          backgroundColor: Colors.blue.shade800,
          foregroundColor: Colors.white,
          bottom: const TabBar(
            indicatorColor: Colors.white,
            tabs: [
              Tab(icon: Icon(Icons.delivery_dining), text: 'Por Entregar'),
              Tab(icon: Icon(Icons.check_circle_outline), text: 'Entregados'),
            ],
          ),
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

            final allOrders = snapshot.data ?? [];

            // Pestaña 1: Por entregar (Filtrado estricto: solo entregas a domicilio)
            final pendingOrders = allOrders.where((o) {
              final st = o['status'];
              final type = o['delivery_type'] ?? 'domicilio';
              final assignedId = o['delivery_driver_id'];
              return type == 'domicilio' &&
                  (st == 'en cocina' || st == 'en camino' || st == 'pendiente') &&
                  (assignedId == null || assignedId == currentDriverId);
            }).toList();

            // Pestaña 2: Entregados (solo a domicilio completados)
            final deliveredOrders = allOrders.where((o) {
              final type = o['delivery_type'] ?? 'domicilio';
              return type == 'domicilio' && o['status'] == 'entregado';
            }).toList();

            return TabBarView(
              children: [
                _buildOrderList(pendingOrders, currentDriverId, isDeliveredView: false),
                _buildOrderList(deliveredOrders, currentDriverId, isDeliveredView: true),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildOrderList(
    List<Map<String, dynamic>> orders,
    String? currentDriverId, {
    required bool isDeliveredView,
  }) {
    if (orders.isEmpty) {
      return Center(
        child: Text(
          isDeliveredView
              ? 'No hay pedidos entregados aún.'
              : 'No hay pedidos pendientes de entrega.',
          style: const TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: orders.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final ord = orders[index];
        final orderId = ord['id'] as int;
        final status = ord['status'] as String;
        final phone = ord['customer_phone'] ?? 'Sin número';
        final notes = ord['delivery_notes'] ?? 'Sin referencias';
        final total = ord['total']?.toString() ?? '0.0';
        final lat = ord['delivery_latitude'] as double?;
        final lng = ord['delivery_longitude'] as double?;
        final assignedId = ord['delivery_driver_id'];
        final isMyOrder = assignedId == currentDriverId;

        return Card(
          elevation: 3,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Orden #$orderId',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Chip(
                      label: Text(
                        status.toUpperCase(),
                        style: const TextStyle(fontSize: 11, color: Colors.white),
                      ),
                      backgroundColor: isDeliveredView
                          ? Colors.green
                          : (isMyOrder ? Colors.blue.shade700 : Colors.orange),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text('Teléfono: $phone'),
                Text('Referencia: $notes'),
                Text('Total: Q$total',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                const SizedBox(height: 12),
                if (!isDeliveredView) ...[
                  Row(
                    children: [
                      if (lat != null && lng != null)
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey.shade800,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => _openMaps(lat, lng),
                          icon: const Icon(Icons.directions, size: 16),
                          label: const Text('Maps'),
                        ),
                      const Spacer(),
                      if (!isMyOrder)
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade700,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => _takeOrder(orderId),
                          icon: const Icon(Icons.delivery_dining),
                          label: const Text('Llevar este Pedido'),
                        )
                      else ...[
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                          onPressed: () => _releaseOrder(orderId),
                          child: const Text('Soltar'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => _confirmCompleteDelivery(orderId),
                          icon: const Icon(Icons.check_circle),
                          label: const Text('Entregado'),
                        ),
                      ],
                    ],
                  ),
                  if (isMyOrder && _activeOrderId == orderId)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          Icon(Icons.satellite_alt, size: 16, color: Colors.green),
                          SizedBox(width: 6),
                          Text('Compartiendo ubicación con el cliente...',
                              style: TextStyle(fontSize: 12, color: Colors.green)),
                        ],
                      ),
                    ),
                ],
                if (isDeliveredView)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: Colors.orange.shade800),
                      onPressed: () => _revertToOnTheWay(orderId),
                      icon: const Icon(Icons.undo, size: 18),
                      label: const Text('¿Entregado por error? Reactivar'),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}