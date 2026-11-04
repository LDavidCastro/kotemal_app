import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
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
  // Estáticos: la transmisión sigue viva aunque se cierre/reconstruya esta pantalla.
  static StreamSubscription<Position>? _positionStream;
  static int? _activeOrderId;
  bool _isStarting = false;

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pushPosition(int orderId, Position position) async {
    try {
      debugPrint('REPARTIDOR GPS -> Lat: ${position.latitude}, Lng: ${position.longitude}');
      await Supabase.instance.client.from('orders').update({
        'driver_latitude': position.latitude,
        'driver_longitude': position.longitude,
      }).eq('id', orderId);
    } catch (e) {
      debugPrint('Error enviando GPS a Supabase: $e');
    }
  }

  Future<bool> _ensureTrackingPermissions() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      _snack('Activa el GPS del teléfono para compartir tu ubicación.');
      await Geolocator.openLocationSettings();
      return false;
    }

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied) {
      _snack('Se necesita el permiso de ubicación para repartir.');
      return false;
    }
    if (perm == LocationPermission.deniedForever) {
      _snack('Permiso de ubicación bloqueado. Actívalo en Ajustes de la app.');
      await Geolocator.openAppSettings();
      return false;
    }

    // Android 13+: sin este permiso la notificación del servicio no se muestra.
    await Permission.notification.request();

    // Evita que el ahorro de batería mate la transmisión con la pantalla apagada.
    if (!await Permission.ignoreBatteryOptimizations.isGranted) {
      await Permission.ignoreBatteryOptimizations.request();
    }
    return true;
  }

  Future<void> _startSharingLocation(int orderId) async {
    if (_isStarting) return;
    _isStarting = true;
    try {
      if (!await _ensureTrackingPermissions()) return;

      late LocationSettings locationSettings;

      if (defaultTargetPlatform == TargetPlatform.android) {
        locationSettings = AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
          intervalDuration: const Duration(seconds: 5),
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationText: "Transmitiendo ruta de entrega en tiempo real al cliente",
            notificationTitle: "K'OTEMAL Reparto Activo",
            enableWakeLock: true,
            setOngoing: true,
            notificationIcon: AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
          ),
        );
      } else {
        locationSettings = const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        );
      }

      await _positionStream?.cancel();
      _activeOrderId = orderId;
      _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings)
          .listen(
        (position) => _pushPosition(orderId, position),
        onError: (Object e) => debugPrint('Error en stream GPS: $e'),
      );

      // Envía una posición inmediata para que el cliente vea al repartidor ya.
      try {
        final first = await Geolocator.getCurrentPosition();
        await _pushPosition(orderId, first);
      } catch (_) {}

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Compartiendo ubicación (funciona con pantalla apagada) ✓'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } finally {
      _isStarting = false;
    }
  }

  void _stopSharingLocation() {
    _positionStream?.cancel();
    _positionStream = null;
    _activeOrderId = null;
    if (mounted) setState(() {});
  }

  Future<void> _takeOrder(int orderId) async {
    final driverId = _supabase.auth.currentUser?.id;
    if (driverId == null) return;

    try {
      await _supabase.from('orders').update({
        'delivery_driver_id': driverId,
        'status': 'en camino',
      }).eq('id', orderId);

      await _startSharingLocation(orderId);
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
    String? paymentStatus;
    try {
      final order = await _supabase
          .from('orders')
          .select('payment_status')
          .eq('id', orderId)
          .maybeSingle();
      paymentStatus = order?['payment_status'] as String?;
    } catch (e) {
      _snack('Error al consultar el pago del pedido: $e');
      return;
    }

    if (!mounted) return;

    // Pedido ya pagado: solo se confirma la entrega.
    if (paymentStatus == 'pagado') {
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

        _snack('¡Pedido marcado como entregado!');
      } catch (e) {
        _snack('Error al completar pedido: $e');
      }
      return;
    }

    // Pedido sin pagar: se registra el método de cobro y se marca como pagado.
    final selectedMethod = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Registrar Pago'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('¿Cómo cobraste este pedido?'),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.green.shade800,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () => Navigator.pop(ctx, 'efectivo'),
              icon: const Icon(Icons.payments),
              label: const Text('Efectivo'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.blue.shade800,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () => Navigator.pop(ctx, 'transferencia'),
              icon: const Icon(Icons.account_balance),
              label: const Text('Transferencia'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );

    if (!mounted || selectedMethod == null) return;

    try {
      await _supabase.from('orders').update({
        'status': 'entregado',
        'payment_status': 'pagado',
        'payment_method': selectedMethod,
        'paid_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', orderId);

      _stopSharingLocation();

      _snack(
        '¡Pedido entregado y cobrado en '
        '${selectedMethod == 'efectivo' ? 'efectivo' : 'transferencia'}!',
      );
    } catch (e) {
      _snack('Error al completar pedido: $e');
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

      await _startSharingLocation(orderId);

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

            // Reanudar / detener la transmisión según el estado real en la BD.
            if (snapshot.hasData) {
              Map<String, dynamic>? myOnTheWay;
              for (final o in allOrders) {
                if (o['status'] == 'en camino' &&
                    o['delivery_type'] == 'domicilio' &&
                    o['delivery_driver_id'] == currentDriverId) {
                  myOnTheWay = o;
                  break;
                }
              }
              if (myOnTheWay != null && _positionStream == null && !_isStarting) {
                final id = myOnTheWay['id'] as int;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _positionStream == null) _startSharingLocation(id);
                });
              } else if (myOnTheWay == null && _positionStream != null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _stopSharingLocation();
                });
              }
            }

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
        final paymentStatus = (ord['payment_status'] ?? 'pendiente') as String;
        final paymentMethod = ord['payment_method'] as String?;
        final isPaid = paymentStatus == 'pagado';
        final paymentLabel = paymentMethod == 'efectivo'
            ? 'Pagado (Efectivo)'
            : paymentMethod == 'transferencia'
                ? 'Pagado (Transferencia)'
                : 'Pagado';

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
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: (isPaid ? Colors.green : Colors.orange).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: isPaid ? Colors.green : Colors.orange),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isPaid ? Icons.verified : Icons.payments_outlined,
                        size: 15,
                        color: isPaid ? Colors.green : Colors.orange,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isPaid ? paymentLabel : 'Pago pendiente',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isPaid ? Colors.green.shade800 : Colors.orange.shade900,
                        ),
                      ),
                    ],
                  ),
                ),
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