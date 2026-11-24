import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/device_id_service.dart';
import '../../../core/services/guest_orders_service.dart';
import '../presentation/cart_controller.dart';
import '../../delivery/presentation/delivery_screen.dart';
import '../../orders/presentation/order_tracking_screen.dart';

class _DeliveryOption {
  final String type;
  final String title;
  final String subtitle;
  final IconData icon;
  final MaterialColor color;

  const _DeliveryOption({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}

class CheckoutTypeScreen extends ConsumerStatefulWidget {
  const CheckoutTypeScreen({super.key});

  @override
  ConsumerState<CheckoutTypeScreen> createState() => _CheckoutTypeScreenState();
}

class _CheckoutTypeScreenState extends ConsumerState<CheckoutTypeScreen> {
  String _selectedDeliveryType = 'local';
  final _nameController = TextEditingController();
  final _tableController = TextEditingController();
  final _phoneController = TextEditingController();
  final _notesController = TextEditingController();
  bool _isSending = false;

  static const List<_DeliveryOption> _options = [
    _DeliveryOption(
      type: 'local',
      title: 'Comer en el local',
      subtitle: 'Disfruta tu comida en nuestras mesas',
      icon: Icons.table_restaurant,
      color: Colors.indigo,
    ),
    _DeliveryOption(
      type: 'para_llevar',
      title: 'Para llevar',
      subtitle: 'Pasa a recoger tu orden en mostrador',
      icon: Icons.takeout_dining,
      color: Colors.teal,
    ),
    _DeliveryOption(
      type: 'domicilio',
      title: 'A domicilio',
      subtitle: 'Te lo llevamos hasta tu dirección',
      icon: Icons.two_wheeler,
      color: Colors.deepOrange,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _tableController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
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

  Future<void> _submitOnSiteOrder() async {
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

    if (cartItems.isEmpty) return;

    if (_selectedDeliveryType == 'local' &&
        _tableController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Por favor indica tu número o nombre de mesa.')),
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
            content: Text('Ingresa tu número de teléfono de contacto.')),
      );
      return;
    }

    setState(() => _isSending = true);

    try {
      final supabase = Supabase.instance.client;
      final currentUser = supabase.auth.currentUser;
      final deviceId = await DeviceIdService.getDeviceId();

      final orderResponse = await supabase.from('orders').insert({
        'customer_id': currentUser?.id,
        'customer_name': _nameController.text.trim(),
        'total': total,
        'status': 'pendiente',
        'delivery_type': _selectedDeliveryType,
        'table_number': _selectedDeliveryType == 'local'
            ? _tableController.text.trim()
            : null,
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
      if (mounted) setState(() => _isSending = false);
    }
  }

  _DeliveryOption get _activeOption => _options.firstWhere(
        (o) => o.type == _selectedDeliveryType,
        orElse: () => _options.first,
      );

  String get _confirmButtonLabel {
    switch (_selectedDeliveryType) {
      case 'local':
        return 'Confirmar Pedido en Mesa';
      case 'para_llevar':
        return 'Confirmar Pedido para Llevar';
      case 'domicilio':
        return 'Elegir Ubicación en Mapa';
      default:
        return 'Confirmar Pedido';
    }
  }

  @override
  Widget build(BuildContext context) {
    final subtotal = ref.watch(cartTotalProvider);
    final selectedReward = ref.watch(selectedRewardProvider);
    final appliedReward = selectedReward != null &&
            subtotal >= selectedReward.minFoodSubtotal
        ? selectedReward
        : null;
    final total = (subtotal - (appliedReward?.discountAmount ?? 0))
        .clamp(0.0, double.infinity)
        .toDouble();

    final activeColor = _activeOption.color;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F9),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFFF7F7F9),
        foregroundColor: Colors.black87,
        title: const Text(
          '¿Cómo deseas tu pedido?',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Selecciona una modalidad',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 16),
            ..._options.map((option) => _buildOptionCard(option)),
            const SizedBox(height: 28),
            _buildForm(activeColor),
            const SizedBox(height: 24),
            if (_selectedDeliveryType != 'domicilio')
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: activeColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  onPressed: _isSending ? null : _submitOnSiteOrder,
                  child: _isSending
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : Text(
                          '$_confirmButtonLabel (Q${total.toStringAsFixed(2)})',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: activeColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DeliveryScreen(
                          initialName: _nameController.text.trim(),
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.map_outlined),
                  label: Text(
                    _confirmButtonLabel,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionCard(_DeliveryOption option) {
    final isSelected = _selectedDeliveryType == option.type;
    final baseColor = option.color;

    return GestureDetector(
      onTap: () => setState(() => _selectedDeliveryType = option.type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? baseColor.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? baseColor : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: isSelected ? baseColor.shade100 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Icon(
                option.icon,
                color: isSelected ? baseColor.shade700 : Colors.grey.shade600,
                size: 28,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? baseColor.shade900 : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    option.subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: isSelected ? baseColor : Colors.transparent,
                border: Border.all(
                  color: isSelected ? baseColor : Colors.grey.shade400,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: isSelected
                  ? const Icon(Icons.check, color: Colors.white, size: 18)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(Color activeColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Nombre de quien recibe / ordena *',
              hintText: 'Ej. Juan Pérez',
              prefixIcon: const Icon(Icons.person_outline),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: activeColor, width: 1.5),
                borderRadius: BorderRadius.circular(12),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(12),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (_selectedDeliveryType == 'local') ...[
            TextField(
              controller: _tableController,
              decoration: InputDecoration(
                labelText: 'Número o Nombre de Mesa *',
                hintText: 'Ej. Mesa 3 / Barra',
                prefixIcon: const Icon(Icons.pin),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: activeColor, width: 1.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(12),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'Teléfono de contacto *',
              prefixIcon: const Icon(Icons.phone),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: activeColor, width: 1.5),
                borderRadius: BorderRadius.circular(12),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(12),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _notesController,
            decoration: InputDecoration(
              labelText: 'Instrucciones adicionales (opcional)',
              hintText: 'Ej. Servir sin hielo, cubiertos extra',
              prefixIcon: const Icon(Icons.note_alt_outlined),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: activeColor, width: 1.5),
                borderRadius: BorderRadius.circular(12),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(12),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
