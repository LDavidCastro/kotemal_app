import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
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
  static Set<int> _activeOrderIds = <int>{};
  bool _isStarting = false;

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pushPosition(Position position) async {
    final activeIds = _activeOrderIds.toList();
    if (activeIds.isEmpty) return;

    try {
      debugPrint(
        'REPARTIDOR GPS -> Lat: ${position.latitude}, '
        'Lng: ${position.longitude}, pedidos: $activeIds',
      );
      await Supabase.instance.client.from('orders').update({
        'driver_latitude': position.latitude,
        'driver_longitude': position.longitude,
      }).inFilter('id', activeIds);
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

  Future<void> _startSharingLocation(Set<int> orderIds) async {
    if (orderIds.isEmpty) {
      _stopSharingLocation();
      return;
    }

    _activeOrderIds = {...orderIds};

    // El stream ya está activo: solo actualizamos los pedidos destino y
    // enviamos una posición inmediata para que todos reciban el GPS ya.
    if (_positionStream != null) {
      try {
        final current = await Geolocator.getCurrentPosition();
        await _pushPosition(current);
      } catch (_) {}
      if (mounted) setState(() {});
      return;
    }

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

      _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings)
          .listen(
        (position) => _pushPosition(position),
        onError: (Object e) => debugPrint('Error en stream GPS: $e'),
      );

      // Envía una posición inmediata para que los clientes vean al repartidor ya.
      try {
        final first = await Geolocator.getCurrentPosition();
        await _pushPosition(first);
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
    _activeOrderIds.clear();
    if (mounted) setState(() {});
  }

  void _removeActiveOrder(int orderId) {
    _activeOrderIds.remove(orderId);
    if (_activeOrderIds.isEmpty) {
      _stopSharingLocation();
    } else if (mounted) {
      setState(() {});
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

      await _startSharingLocation({..._activeOrderIds, orderId});
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

      _removeActiveOrder(orderId);

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

  Future<bool> _confirmCompleteDelivery(int orderId) async {
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
      return false;
    }

    if (!mounted) return false;

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

      if (!mounted || confirm != true) return false;

      try {
        await _supabase.from('orders').update({
          'status': 'entregado',
        }).eq('id', orderId);

        _removeActiveOrder(orderId);

        _snack('¡Pedido marcado como entregado!');
        return true;
      } catch (e) {
        _snack('Error al completar pedido: $e');
        return false;
      }
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

    if (!mounted || selectedMethod == null) return false;

    try {
      await _supabase.from('orders').update({
        'status': 'entregado',
        'payment_status': 'pagado',
        'payment_method': selectedMethod,
        'paid_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', orderId);

      _removeActiveOrder(orderId);

      _snack(
        '¡Pedido entregado y cobrado en '
        '${selectedMethod == 'efectivo' ? 'efectivo' : 'transferencia'}!',
      );
      return true;
    } catch (e) {
      _snack('Error al completar pedido: $e');
      return false;
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

      await _startSharingLocation({..._activeOrderIds, orderId});

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

  Future<void> _showContactOptions(String phone, String customerName) async {
    final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
    if (cleanPhone.isEmpty || phone == 'Sin número') return;

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
                'Contactar a $customerName ($phone)',
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
                  final waNumber =
                      cleanPhone.length == 8 ? '502$cleanPhone' : cleanPhone;
                  final uri = Uri.parse(
                    'https://wa.me/$waNumber?text=Hola%20${Uri.encodeComponent(customerName)},%20soy%20tu%20repartidor%20de%20K\'OTEMAL,%20voy%20en%20camino%20con%20tu%20pedido.',
                  );
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

            // Sincroniza la transmisión GPS con todos los pedidos activos.
            final myActiveIds = <int>{
              for (final o in allOrders)
                if (o['status'] == 'en camino' &&
                    o['delivery_type'] == 'domicilio' &&
                    o['delivery_driver_id'] == currentDriverId)
                  o['id'] as int,
            };
            if (snapshot.hasData) {
              if (myActiveIds.isNotEmpty) {
                final needsSync = _positionStream == null ||
                    !setEquals(_activeOrderIds, myActiveIds);
                if (needsSync && !_isStarting) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _startSharingLocation(myActiveIds);
                  });
                }
              } else if (_positionStream != null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _stopSharingLocation();
                });
              }
            }

            // Pestaña 1: Por entregar (Filtrado estricto: solo entregas a domicilio)
            final pendingOrders = allOrders.where((o) {
              final st = o['status'];
              final type = o['delivery_type'] ?? 'domicilio';
              final assignedId = o['delivery_driver_id'];
              return type == 'domicilio' &&
                  (st == 'en cocina' ||
                      st == 'listo' ||
                      st == 'en camino' ||
                      st == 'pendiente') &&
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

    final myAssignedWithGps = orders.where((o) {
      final assigned = o['delivery_driver_id'] == currentDriverId;
      final lat = o['delivery_latitude'];
      final lng = o['delivery_longitude'];
      return assigned && lat != null && lng != null;
    }).toList();

    final list = ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: orders.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final ord = orders[index];
        final orderId = ord['id'] as int;
        final status = ord['status'] as String;
        final phone = ord['customer_phone'] ?? 'Sin número';
        final rawCustomerName = (ord['customer_name'] ?? '').toString().trim();
        final customerName =
            rawCustomerName.isEmpty ? 'Sin nombre' : rawCustomerName;
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
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _showContactOptions(phone, customerName),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        child: Text(
                          'Orden #$orderId',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    Chip(
                      label: Text(
                        status == 'listo'
                            ? 'LISTO PARA RECOGER'
                            : status.toUpperCase(),
                        style: const TextStyle(fontSize: 11, color: Colors.white),
                      ),
                      backgroundColor: status == 'listo'
                          ? Colors.teal
                          : isDeliveredView
                              ? Colors.green
                              : (isMyOrder ? Colors.blue.shade700 : Colors.orange),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text('Cliente: $customerName',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                InkWell(
                  onTap: () => _showContactOptions(phone, customerName),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.phone_in_talk,
                          size: 16,
                          color: Colors.blue,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Teléfono: $phone',
                          style: const TextStyle(
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
                ),
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
                  if (_activeOrderIds.contains(orderId))
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

    if (isDeliveredView || myAssignedWithGps.isEmpty) {
      return list;
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade800,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _DriverRouteMapScreen(
                      orders: myAssignedWithGps,
                      onCompleteOrder: _confirmCompleteDelivery,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.map),
              label: Text(
                'Ver Mapa de Ruta (${myAssignedWithGps.length} pedido(s))',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
        Expanded(child: list),
      ],
    );
  }
}

class _DriverRouteMapScreen extends StatefulWidget {
  const _DriverRouteMapScreen({
    required this.orders,
    required this.onCompleteOrder,
  });

  final List<Map<String, dynamic>> orders;
  final Future<bool> Function(int orderId) onCompleteOrder;

  @override
  State<_DriverRouteMapScreen> createState() => _DriverRouteMapScreenState();
}

class _DriverRouteMapScreenState extends State<_DriverRouteMapScreen> {
  static const LatLng _storeLocation = LatLng(14.643973, -91.120232);

  final MapController _mapController = MapController();
  StreamSubscription<Position>? _driverStream;
  LatLng? _driverLocation;
  int? _selectedOrderId;
  bool _mapReady = false;

  late List<Map<String, dynamic>> _remainingOrders;
  List<LatLng> _routePoints = [];
  LatLng? _lastRoutedOrigin;
  int? _lastRoutedOrderId;
  int _etaMinutes = 0;
  double _distanceKm = 0;
  bool _isFetchingRoute = false;
  bool _manualSelection = false;

  @override
  void initState() {
    super.initState();
    _remainingOrders = List<Map<String, dynamic>>.from(widget.orders);
    _autoSelectNearest();
    _initDriverLocation();
  }

  @override
  void dispose() {
    _driverStream?.cancel();
    super.dispose();
  }

  Future<void> _initDriverLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition();
      _onDriverPosition(position);
    } catch (_) {}

    try {
      _driverStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen(
        _onDriverPosition,
        onError: (Object e) => debugPrint('Error en stream GPS del mapa: $e'),
      );
    } catch (e) {
      debugPrint('No se pudo iniciar el GPS del mapa: $e');
    }
  }

  Map<String, dynamic>? _findNearestOrder() {
    if (_remainingOrders.isEmpty) return null;

    final origin = _driverLocation ?? _storeLocation;
    Map<String, dynamic>? nearest;
    double? nearestDistance;

    for (final order in _remainingOrders) {
      final point = _orderPoint(order);
      if (point == null) continue;
      final distance = const Distance().as(LengthUnit.Meter, origin, point);
      if (nearestDistance == null || distance < nearestDistance) {
        nearestDistance = distance;
        nearest = order;
      }
    }

    return nearest;
  }

  void _autoSelectNearest() {
    if (_manualSelection) return;
    final nearest = _findNearestOrder();
    final nearestId = nearest?['id'] as int?;
    if (nearestId == null) return;
    _selectedOrderId = nearestId;
    _updateRouteToSelected();
  }

  Future<void> _updateRouteToSelected({bool force = false}) async {
    final selectedId = _selectedOrderId;
    if (selectedId == null) return;

    Map<String, dynamic>? selected;
    for (final order in _remainingOrders) {
      if (order['id'] == selectedId) {
        selected = order;
        break;
      }
    }
    if (selected == null) return;

    final destination = _orderPoint(selected);
    if (destination == null) return;

    final origin = _driverLocation ?? _storeLocation;

    if (!force &&
        _lastRoutedOrderId == selectedId &&
        _lastRoutedOrigin != null) {
      final movedMeters = const Distance().as(
        LengthUnit.Meter,
        _lastRoutedOrigin!,
        origin,
      );
      if (movedMeters <= 40) return;
    }

    if (_isFetchingRoute && !force) return;

    _isFetchingRoute = true;
    _lastRoutedOrigin = origin;
    _lastRoutedOrderId = selectedId;

    final result = await LocationService().getDrivingRoute(origin, destination);

    if (!mounted) return;

    if (_selectedOrderId != selectedId) {
      setState(() => _isFetchingRoute = false);
      return;
    }

    setState(() {
      _routePoints = result.points;
      _etaMinutes = result.durationMinutes;
      _distanceKm = result.distanceKm;
      _isFetchingRoute = false;
    });
  }

  void _selectOrder(int orderId) {
    setState(() {
      _manualSelection = true;
      _selectedOrderId = orderId;
    });
    _updateRouteToSelected(force: true);
  }

  void _onDriverPosition(Position position) {
    if (!mounted) return;
    final location = LatLng(position.latitude, position.longitude);
    final isFirstFix = _driverLocation == null;
    setState(() => _driverLocation = location);
    if (isFirstFix) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitAll());
      if (!_manualSelection) {
        final nearest = _findNearestOrder();
        setState(() => _selectedOrderId = nearest?['id'] as int?);
      }
    }
    _updateRouteToSelected();
  }

  Future<void> _markSelectedAsDelivered(int orderId) async {
    final completed = await widget.onCompleteOrder(orderId);
    if (!completed || !mounted) return;

    setState(() {
      _remainingOrders.removeWhere((order) => order['id'] == orderId);
      _selectedOrderId = null;
      _routePoints = [];
      _etaMinutes = 0;
      _distanceKm = 0;
      _lastRoutedOrderId = null;
    });

    if (_remainingOrders.isEmpty) {
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('¡Todas las entregas de la ruta fueron completadas!'),
        ),
      );
      return;
    }

    _manualSelection = false;
    final nearest = _findNearestOrder();
    setState(() => _selectedOrderId = nearest?['id'] as int?);
    _updateRouteToSelected(force: true);
  }

  void _fitAll() {
    if (!mounted || !_mapReady) return;
    try {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: _fitBounds(),
          padding: const EdgeInsets.all(60),
        ),
      );
    } catch (_) {}
  }

  LatLngBounds _fitBounds() {
    final points = <LatLng>[
      _storeLocation,
      for (final order in _remainingOrders)
        if (_orderPoint(order) != null) _orderPoint(order)!,
      ?_driverLocation,
    ];

    if (points.length == 1) {
      points.add(
        LatLng(
          points.first.latitude + 0.001,
          points.first.longitude + 0.001,
        ),
      );
    }

    return LatLngBounds.fromPoints(points);
  }

  LatLng? _orderPoint(Map<String, dynamic> order) {
    final lat = order['delivery_latitude'];
    final lng = order['delivery_longitude'];
    if (lat is num && lng is num) {
      return LatLng(lat.toDouble(), lng.toDouble());
    }
    return null;
  }

  String _customerName(Map<String, dynamic> order) {
    final raw = (order['customer_name'] ?? '').toString().trim();
    return raw.isEmpty ? 'Sin nombre' : raw;
  }

  Future<void> _openMaps(double? lat, double? lng) async {
    if (lat == null || lng == null) return;
    final url = Uri.parse(LocationService.getGoogleMapsUrl(lat, lng));
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _showContactOptions(String phone, String customerName) async {
    final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
    if (cleanPhone.isEmpty || phone == 'Sin número') return;

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
                'Contactar a $customerName ($phone)',
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
                  final waNumber =
                      cleanPhone.length == 8 ? '502$cleanPhone' : cleanPhone;
                  final uri = Uri.parse(
                    'https://wa.me/$waNumber?text=Hola%20${Uri.encodeComponent(customerName)},%20soy%20tu%20repartidor%20de%20K\'OTEMAL,%20voy%20en%20camino%20con%20tu%20pedido.',
                  );
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

  Widget _buildStoreMarker() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.orange, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 6,
          ),
        ],
      ),
      child: const CircleAvatar(
        radius: 18,
        backgroundColor: Colors.white,
        foregroundColor: Colors.orange,
        child: Icon(Icons.store),
      ),
    );
  }

  Widget _buildDriverMarker() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 6,
          ),
        ],
      ),
      child: const CircleAvatar(
        radius: 18,
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        child: Icon(Icons.two_wheeler),
      ),
    );
  }

  Widget _buildDeliveryMarker(Map<String, dynamic> order) {
    final orderId = order['id'];
    final isSelected = _selectedOrderId == orderId;
    final color = isSelected ? Colors.deepOrange.shade900 : Colors.deepOrange;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 130),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: isSelected ? color : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 4,
              ),
            ],
          ),
          child: Text(
            _customerName(order),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: isSelected ? Colors.white : Colors.black87,
            ),
          ),
        ),
        Stack(
          alignment: Alignment.topCenter,
          children: [
            Icon(Icons.location_pin, size: 46, color: color),
            Positioned(
              top: 8,
              child: Text(
                '#$orderId',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[
      Marker(
        point: _storeLocation,
        width: 70,
        height: 70,
        alignment: Alignment.center,
        child: _buildStoreMarker(),
      ),
    ];

    for (final order in _remainingOrders) {
      final point = _orderPoint(order);
      if (point == null) continue;
      final orderId = order['id'] as int;
      markers.add(
        Marker(
          point: point,
          width: 140,
          height: 84,
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () => _selectOrder(orderId),
            child: _buildDeliveryMarker(order),
          ),
        ),
      );
    }

    final driverLocation = _driverLocation;
    if (driverLocation != null) {
      markers.add(
        Marker(
          point: driverLocation,
          width: 60,
          height: 60,
          alignment: Alignment.center,
          child: _buildDriverMarker(),
        ),
      );
    }

    return markers;
  }

  Widget _buildSelectedOrderCard(BuildContext context) {
    Map<String, dynamic>? selected;
    for (final order in _remainingOrders) {
      if (order['id'] == _selectedOrderId) {
        selected = order;
        break;
      }
    }

    if (selected == null) return const SizedBox.shrink();

    final order = selected;
    final orderId = order['id'];
    final phone = (order['customer_phone'] ?? 'Sin número').toString();
    final notes = (order['delivery_notes'] ?? 'Sin referencias').toString();
    final total = order['total']?.toString() ?? '0.0';
    final lat = order['delivery_latitude'];
    final lng = order['delivery_longitude'];

    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Orden #$orderId',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _selectedOrderId = null),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Text(
              'Cliente: ${_customerName(order)}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text('Referencia: $notes'),
            const SizedBox(height: 4),
            Text(
              'Total: Q$total',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey.shade800,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => _openMaps(
                      lat is num ? lat.toDouble() : null,
                      lng is num ? lng.toDouble() : null,
                    ),
                    icon: const Icon(Icons.directions, size: 18),
                    label: const Text('Google Maps'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => _showContactOptions(
                      phone,
                      _customerName(order),
                    ),
                    icon: const Icon(Icons.chat, size: 18),
                    label: const Text('Contactar'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () => _markSelectedAsDelivered(orderId as int),
                icon: const Icon(Icons.check_circle),
                label: const Text(
                  'Entregado',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapa de Ruta'),
        backgroundColor: Colors.blue.shade800,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCameraFit: CameraFit.bounds(
                bounds: _fitBounds(),
                padding: const EdgeInsets.all(60),
              ),
              onMapReady: () {
                _mapReady = true;
                if (_driverLocation != null) _fitAll();
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.kotemal.app',
              ),
              if (_routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      strokeWidth: 5,
                      color: Colors.blue.shade700,
                    ),
                  ],
                ),
              MarkerLayer(markers: _buildMarkers()),
            ],
          ),
          if (_selectedOrderId != null && _etaMinutes > 0)
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.navigation,
                        color: Colors.blue.shade700,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Siguiente entrega: Orden #$_selectedOrderId · '
                          '~$_etaMinutes min '
                          '(${_distanceKm.toStringAsFixed(1)} km)',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_selectedOrderId != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: MediaQuery.of(context).padding.bottom + 12,
              child: _buildSelectedOrderCard(context),
            ),
        ],
      ),
    );
  }
}