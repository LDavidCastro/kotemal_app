import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_colors.dart';
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
  final Color color;

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
      color: AppColors.secondary,
    ),
  ];

  @override
  void initState() {
    super.initState();
    // En Modo Mostrador el nombre debe quedar limpio para escribir el del
    // cliente que llegó al local (no el del cajero/admin).
    if (!ref.read(posModeProvider)) {
      _loadUserProfile();
    }
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
    final isPosMode = ref.read(posModeProvider);
    final cartItems = ref.read(cartProvider);
    final subtotal = ref.read(cartTotalProvider);
    final selectedReward = ref.read(selectedRewardProvider);

    // En caja no se canjean puntos: el cliente del mostrador no tiene cuenta.
    final reward = !isPosMode &&
            selectedReward != null &&
            subtotal >= selectedReward.minFoodSubtotal
        ? selectedReward
        : null;
    final total = (subtotal - (reward?.discountAmount ?? 0))
        .clamp(0.0, double.infinity)
        .toDouble();

    if (cartItems.isEmpty) return;

    // En Modo Mostrador solo existen las modalidades presenciales.
    final deliveryType =
        isPosMode && _selectedDeliveryType == 'domicilio'
            ? 'local'
            : _selectedDeliveryType;

    if (deliveryType == 'local' &&
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

    if (!isPosMode && _phoneController.text.trim().isEmpty) {
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
      final deviceId = !isPosMode && currentUser == null
          ? await DeviceIdService.getDeviceId()
          : null;
      final phone = _phoneController.text.trim();

      final orderResponse = await supabase.from('orders').insert({
        // Las ventas de caja no se mezclan con el historial del cajero/admin.
        'customer_id': isPosMode ? null : currentUser?.id,
        'customer_name': _nameController.text.trim(),
        'total': total,
        'status': 'pendiente',
        'delivery_type': deliveryType,
        'table_number': deliveryType == 'local'
            ? _tableController.text.trim()
            : null,
        'delivery_notes': _notesController.text.trim(),
        'customer_phone':
            (isPosMode && phone.isEmpty) ? 'Mostrador' : phone,
        'guest_device_id': deviceId,
        'platform': isPosMode
            ? 'pos_local'
            : (kIsWeb ? 'web' : defaultTargetPlatform.name),
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

      // El pedido de mostrador no se guarda como pedido del dispositivo.
      if (!isPosMode && currentUser == null) {
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

      if (!mounted) return;

      if (isPosMode) {
        // Deja el mostrador listo para el siguiente cliente.
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green.shade700,
            content: Text(
              '✓ Orden #$orderId enviada a cocina',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else {
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

  _DeliveryOption _optionFor(String deliveryType) => _options.firstWhere(
        (o) => o.type == deliveryType,
        orElse: () => _options.first,
      );

  String _confirmButtonLabel(String deliveryType) {
    switch (deliveryType) {
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
    final isPosMode = ref.watch(posModeProvider);
    final subtotal = ref.watch(cartTotalProvider);
    final selectedReward = ref.watch(selectedRewardProvider);
    final appliedReward = !isPosMode &&
            selectedReward != null &&
            subtotal >= selectedReward.minFoodSubtotal
        ? selectedReward
        : null;
    final total = (subtotal - (appliedReward?.discountAmount ?? 0))
        .clamp(0.0, double.infinity)
        .toDouble();

    // En Modo Mostrador solo se ofrecen las modalidades presenciales.
    final deliveryType =
        isPosMode && _selectedDeliveryType == 'domicilio'
            ? 'local'
            : _selectedDeliveryType;
    final options = isPosMode
        ? _options.where((o) => o.type != 'domicilio').toList()
        : _options;
    final activeColor = _optionFor(deliveryType).color;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppColors.logoBackground,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.primary,
        title: const Text(
          '¿Cómo deseas tu pedido?',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
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
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            ...options.map((option) => _buildOptionCard(option, deliveryType)),
            const SizedBox(height: 28),
            _buildForm(activeColor, deliveryType, isPosMode),
            const SizedBox(height: 24),
            if (deliveryType != 'domicilio')
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
                          '${_confirmButtonLabel(deliveryType)} (Q${total.toStringAsFixed(2)})',
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
                    _confirmButtonLabel(deliveryType),
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

  Widget _buildOptionCard(_DeliveryOption option, String selectedType) {
    final isSelected = selectedType == option.type;
    final baseColor = option.color;

    return GestureDetector(
      onTap: () => setState(() => _selectedDeliveryType = option.type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? baseColor.withAlpha(20) : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? baseColor : AppColors.border,
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
                color: isSelected ? baseColor.withAlpha(30) : AppColors.border.withAlpha(60),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Icon(
                option.icon,
                color: isSelected ? baseColor : AppColors.textSecondary,
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
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    option.subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
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
                  color: isSelected ? baseColor : AppColors.border,
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

  InputDecoration _fieldDecoration({
    required String label,
    String? hint,
    required IconData icon,
    required Color activeColor,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: AppColors.primary),
      prefixIcon: Icon(icon, color: AppColors.primary),
      filled: true,
      fillColor: AppColors.surface,
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: activeColor, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: AppColors.inputBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  Widget _buildForm(Color activeColor, String deliveryType, bool isPosMode) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            decoration: _fieldDecoration(
              label: isPosMode
                  ? 'Nombre del cliente *'
                  : 'Nombre de quien recibe / ordena *',
              hint: 'Ej. Juan Pérez',
              icon: Icons.person_outline,
              activeColor: activeColor,
            ),
          ),
          const SizedBox(height: 14),
          if (deliveryType == 'local') ...[
            TextField(
              controller: _tableController,
              decoration: _fieldDecoration(
                label: 'Número o Nombre de Mesa *',
                hint: 'Ej. Mesa 3 / Barra',
                icon: Icons.pin,
                activeColor: activeColor,
              ),
            ),
            const SizedBox(height: 14),
          ],
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: _fieldDecoration(
              label: isPosMode
                  ? 'Teléfono de contacto (opcional)'
                  : 'Teléfono de contacto *',
              hint: isPosMode
                  ? 'Si se deja vacío se guarda "Mostrador"'
                  : null,
              icon: Icons.phone,
              activeColor: activeColor,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _notesController,
            decoration: _fieldDecoration(
              label: 'Instrucciones adicionales (opcional)',
              hint: 'Ej. Servir sin hielo, cubiertos extra',
              icon: Icons.note_alt_outlined,
              activeColor: activeColor,
            ),
          ),
        ],
      ),
    );
  }
}
