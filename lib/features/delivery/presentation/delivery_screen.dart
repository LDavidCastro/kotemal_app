import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/device_id_service.dart';
import '../../../core/services/guest_orders_service.dart';
import '../../../core/services/location_service.dart';
import '../../auth/presentation/auth_screen.dart';
import '../../cart/presentation/cart_controller.dart';
import '../../orders/presentation/order_tracking_screen.dart';

class DeliveryScreen extends ConsumerStatefulWidget {
  const DeliveryScreen({super.key, this.initialName});

  final String? initialName;

  @override
  ConsumerState<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends ConsumerState<DeliveryScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  // Coordenadas base del local en Sololá
  LatLng _selectedLocation = const LatLng(14.643973, -91.120232);
  bool _isLoadingGps = false;
  bool _isSendingOrder = false;
  bool _isLocationConfirmed = false;

  @override
  void initState() {
    super.initState();
    final initialName = widget.initialName?.trim() ?? '';
    if (initialName.isNotEmpty) {
      _nameController.text = initialName;
    }
    _loadUserProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('full_name, phone')
          .eq('id', user.id)
          .maybeSingle();

      if (mounted && profile != null) {
        final fullName = (profile['full_name'] ?? '').toString().trim();
        final phone = (profile['phone'] ?? '').toString().trim();
        if (fullName.isNotEmpty && _nameController.text.trim().isEmpty) {
          _nameController.text = fullName;
        }
        if (phone.isNotEmpty && _phoneController.text.trim().isEmpty) {
          _phoneController.text = phone;
        }
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
          _isLocationConfirmed = true;
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
    final subtotal = ref.read(cartTotalProvider);
    final selectedReward = ref.read(selectedRewardProvider);

    final reward = selectedReward != null &&
            subtotal >= selectedReward.minFoodSubtotal
        ? selectedReward
        : null;
    final total = (subtotal - (reward?.discountAmount ?? 0))
        .clamp(0.0, double.infinity)
        .toDouble();

    if (cartItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El carrito está vacío.')),
      );
      return;
    }

    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingresa el nombre de quien recibe u ordena el pedido.'),
        ),
      );
      return;
    }

    if (_phoneController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Ingresa un número de teléfono de contacto.')),
      );
      return;
    }

    if (!_isLocationConfirmed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Debes presionar "Obtener Mi GPS" o mover el pin hasta tu dirección antes de enviar.',
          ),
          backgroundColor: Colors.deepOrange,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() => _isSendingOrder = true);

    try {
      final supabase = Supabase.instance.client;
      final currentUser = supabase.auth.currentUser;
      final deviceId = await DeviceIdService.getDeviceId();

      final orderResponse = await supabase.from('orders').insert({
        'customer_id': currentUser?.id,
        'customer_name': _nameController.text.trim(),
        'total': total,
        'status': 'pendiente',
        'delivery_type': 'domicilio',
        'delivery_latitude': _selectedLocation.latitude,
        'delivery_longitude': _selectedLocation.longitude,
        'delivery_notes': _notesController.text.trim(),
        'customer_phone': _phoneController.text.trim(),
        'guest_device_id': currentUser == null ? deviceId : null,
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
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

      if (currentUser == null) {
        await GuestOrdersService.saveOrderId(orderId);
      }

      if (reward != null && currentUser != null) {
        try {
          await supabase.rpc('redeem_order_points', params: {
            'p_order_id': orderId,
            'p_points_to_redeem': reward.pointsRequired,
            'p_food_subtotal': subtotal,
          });
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Pedido creado, pero no se pudo canjear la recompensa: $e',
                ),
              ),
            );
          }
        }
      }

      ref.read(selectedRewardProvider.notifier).state = null;
      ref.read(cartProvider.notifier).clearCart();
      ref.invalidate(userPointsProvider);

      if (mounted) {
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
      appBar: AppBar(
        elevation: 0,
        title: const Text('Ubicación de Entrega'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
      ),
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
                      if (mounted) _loadUserProfile();
                    },
                    child: const Text('Entrar',
                        style: TextStyle(fontWeight: FontWeight.bold)),
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
                          _isLocationConfirmed = true;
                        });
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.kotemal.app',
                    ),
                  ],
                ),
                _buildCenterPin(),
                _buildStatusBanner(),
                Positioned(
                  top: 16,
                  right: 16,
                  child: FloatingActionButton.extended(
                    elevation: 6,
                    backgroundColor:
                        _isLocationConfirmed ? Colors.green : Colors.white,
                    foregroundColor:
                        _isLocationConfirmed ? Colors.white : Colors.black87,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    onPressed: _isLoadingGps ? null : _getCurrentLocation,
                    icon: _isLoadingGps
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            _isLocationConfirmed
                                ? Icons.gps_fixed
                                : Icons.my_location,
                            color: _isLocationConfirmed
                                ? Colors.white
                                : Colors.deepOrange,
                          ),
                    label: Text(
                      _isLocationConfirmed ? 'GPS Actualizado' : 'Obtener Mi GPS',
                      style: TextStyle(
                        color: _isLocationConfirmed
                            ? Colors.white
                            : Colors.black87,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          _buildBottomPanel(user),
        ],
      ),
    );
  }

  Widget _buildStatusBanner() {
    return Positioned(
      top: 16,
      left: 16,
      right: 152,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _isLocationConfirmed
              ? Colors.green.shade50
              : Colors.amber.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _isLocationConfirmed
                ? Colors.green.shade600
                : Colors.amber.shade700,
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              _isLocationConfirmed ? Icons.check_circle : Icons.touch_app,
              color: _isLocationConfirmed
                  ? Colors.green.shade700
                  : Colors.amber.shade800,
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _isLocationConfirmed
                    ? 'Ubicación de entrega confirmada ✓'
                    : 'Presiona "Obtener Mi GPS" o mueve el mapa hasta tu casa',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _isLocationConfirmed
                      ? Colors.green.shade900
                      : Colors.amber.shade900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterPin() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Text(
              'Entregar aquí',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),
          const SizedBox(height: 2),
          const Icon(
            Icons.location_on,
            size: 48,
            color: Colors.deepOrange,
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildBottomPanel(User? user) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: _inputDecoration(
                label: 'Nombre de quien recibe / ordena *',
                hint: 'Ej. Juan Pérez',
                icon: Icons.person_outline,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: _inputDecoration(
                label: 'Teléfono de contacto *',
                icon: Icons.phone,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              maxLines: 2,
              decoration: _inputDecoration(
                label: 'Referencia de la casa',
                hint: 'Ej. Portón negro frente a la escuela',
                icon: Icons.home_outlined,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isLocationConfirmed
                      ? Colors.deepOrange
                      : Colors.amber.shade100,
                  foregroundColor: _isLocationConfirmed
                      ? Colors.white
                      : Colors.amber.shade900,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                onPressed: _isSendingOrder ? null : _submitOrder,
                icon: _isSendingOrder
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : Icon(
                        _isLocationConfirmed
                            ? Icons.check_circle_outline
                            : Icons.location_off,
                        color: _isLocationConfirmed
                            ? Colors.white
                            : Colors.amber.shade900,
                      ),
                label: Text(
                  _isSendingOrder
                      ? 'Enviando pedido...'
                      : _isLocationConfirmed
                          ? 'Confirmar Pedido a Domicilio'
                          : 'Confirma tu ubicación para continuar',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _isLocationConfirmed
                        ? Colors.white
                        : Colors.amber.shade900,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    String? hint,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFFF7F7F9),
      prefixIcon: Icon(icon, color: Colors.deepOrange),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.deepOrange, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    );
  }
}
