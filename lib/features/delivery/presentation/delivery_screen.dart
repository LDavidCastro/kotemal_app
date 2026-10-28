import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/location_service.dart';
import '../../auth/presentation/auth_screen.dart';
import '../../cart/presentation/cart_controller.dart';
import '../../orders/presentation/order_tracking_screen.dart';

class DeliveryScreen extends ConsumerStatefulWidget {
  const DeliveryScreen({super.key});

  @override
  ConsumerState<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends ConsumerState<DeliveryScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  // Coordenadas base del local en Sololá
  LatLng _selectedLocation = const LatLng(14.643973, -91.120232);
  bool _isLoadingGps = false;
  bool _isSendingOrder = false;
  bool _hasCapturedGps = false; // Control de verificación de GPS

  @override
  void initState() {
    super.initState();
    _loadUserPhone();
  }

  @override
  void dispose() {
    _notesController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadUserPhone() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('phone')
          .eq('id', user.id)
          .maybeSingle();

      if (mounted && profile != null && profile['phone'] != null) {
        _phoneController.text = profile['phone'] as String;
      }
    }
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isLoadingGps = true);
    try {
      final position = await LocationService().getCurrentLocation();
      final newPos = LatLng(position.latitude, position.longitude);
      if (mounted) {
        setState(() {
          _selectedLocation = newPos;
          _hasCapturedGps = true;
        });
        _mapController.move(newPos, 16);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ubicación GPS capturada con éxito ✓'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingGps = false);
    }
  }

  Future<void> _submitOrder() async {
    final cartItems = ref.read(cartProvider);
    final total = ref.read(cartTotalProvider);

    if (cartItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El carrito está vacío.')),
      );
      return;
    }

    if (_phoneController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa un número de teléfono de contacto.')),
      );
      return;
    }

    // Validación estricta: Si no ha presionado el botón GPS
    if (!_hasCapturedGps) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text('Verificar Ubicación'),
            ],
          ),
          content: const Text(
            'Aún no has presionado el botón para detectar tu ubicación GPS actual.\n\n'
            '¿Deseas activar el GPS ahora para mayor precisión o enviar con la ubicación actual del mapa?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx, false);
              },
              child: const Text('ACTIVAR MI GPS'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('ENVIAR ASÍ'),
            ),
          ],
        ),
      );

      if (!mounted) return;

      if (confirm == false) {
        _getCurrentLocation();
        return;
      }

      if (confirm != true) return;
    }

    setState(() => _isSendingOrder = true);

    try {
      final supabase = Supabase.instance.client;
      final currentUser = supabase.auth.currentUser;

      final orderResponse = await supabase.from('orders').insert({
        'customer_id': currentUser?.id,
        'total': total,
        'status': 'pendiente',
        'delivery_type': 'domicilio',
        'delivery_latitude': _selectedLocation.latitude,
        'delivery_longitude': _selectedLocation.longitude,
        'delivery_notes': _notesController.text.trim(),
        'customer_phone': _phoneController.text.trim(),
      }).select('id').single();

      final orderId = orderResponse['id'] as int;

      final itemsToInsert = cartItems.map((item) => {
        'order_id': orderId,
        'product_id': item.product.id,
        'quantity': item.quantity,
        'unit_price': item.product.price,
        'notes': item.notes ?? '',
      }).toList();

      await supabase.from('order_items').insert(itemsToInsert);

      ref.read(cartProvider.notifier).clearCart();

      if (mounted) {
        // Redirige al cliente a la pantalla de seguimiento en vivo
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => OrderTrackingScreen(orderId: orderId),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al enviar pedido: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingOrder = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Ubicación de Entrega')),
      body: Column(
        children: [
          if (user == null)
            Container(
              color: Colors.amber.shade100,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.stars, color: Colors.orange),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Pidiendo como invitado. Inicia sesión para ganar puntos.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AuthScreen()),
                      );
                      if (mounted) _loadUserPhone();
                    },
                    child: const Text('Entrar', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),

          Expanded(
            flex: 5,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _selectedLocation,
                    initialZoom: 15,
                    onPositionChanged: (camera, hasGesture) {
                      if (hasGesture && camera.center != null) {
                        setState(() {
                          _selectedLocation = camera.center!;
                          _hasCapturedGps = true;
                        });
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.kotemal.app',
                    ),
                  ],
                ),
                const Center(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 35),
                    child: Icon(Icons.location_on, size: 45, color: Colors.deepOrange),
                  ),
                ),
                Positioned(
                  top: 16,
                  right: 16,
                  child: FloatingActionButton.extended(
                    backgroundColor: _hasCapturedGps ? Colors.green : Colors.white,
                    foregroundColor: _hasCapturedGps ? Colors.white : Colors.black87,
                    onPressed: _isLoadingGps ? null : _getCurrentLocation,
                    icon: _isLoadingGps
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            _hasCapturedGps ? Icons.check_circle : Icons.my_location,
                          ),
                    label: Text(_hasCapturedGps ? 'GPS Listo' : 'Obtener Mi GPS'),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            flex: 4,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Número de Teléfono *',
                      prefixIcon: Icon(Icons.phone),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _notesController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Referencia de la casa',
                      hintText: 'Ej. Portón negro frente a la escuela',
                      prefixIcon: Icon(Icons.home_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepOrange,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _isSendingOrder ? null : _submitOrder,
                      child: _isSendingOrder
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(
                              user != null
                                  ? 'Confirmar Pedido (Registrado)'
                                  : 'Confirmar Pedido (Invitado)',
                              style: const TextStyle(fontSize: 16),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}