import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../presentation/cart_controller.dart';
import '../../delivery/presentation/delivery_screen.dart';
import '../../orders/presentation/order_tracking_screen.dart';

class CheckoutTypeScreen extends ConsumerStatefulWidget {
  const CheckoutTypeScreen({super.key});

  @override
  ConsumerState<CheckoutTypeScreen> createState() => _CheckoutTypeScreenState();
}

class _CheckoutTypeScreenState extends ConsumerState<CheckoutTypeScreen> {
  // Opciones: 'local', 'para_llevar', 'domicilio'
  String _selectedDeliveryType = 'local';
  final _tableController = TextEditingController();
  final _phoneController = TextEditingController();
  final _notesController = TextEditingController();
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _loadUserPhone();
  }

  @override
  void dispose() {
    _tableController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
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

  Future<void> _submitOnSiteOrder() async {
    final cartItems = ref.read(cartProvider);
    final total = ref.read(cartTotalProvider);

    if (cartItems.isEmpty) return;

    if (_selectedDeliveryType == 'local' && _tableController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor indica tu número o nombre de mesa.')),
      );
      return;
    }

    if (_phoneController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa tu número de teléfono de contacto.')),
      );
      return;
    }

    setState(() => _isSending = true);

    try {
      final supabase = Supabase.instance.client;
      final currentUser = supabase.auth.currentUser;

      // Inserción sin necesidad de GPS
      final orderResponse = await supabase.from('orders').insert({
        'customer_id': currentUser?.id,
        'total': total,
        'status': 'pendiente',
        'delivery_type': _selectedDeliveryType,
        'table_number': _selectedDeliveryType == 'local' ? _tableController.text.trim() : null,
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

  @override
  Widget build(BuildContext context) {
    final total = ref.watch(cartTotalProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('¿Cómo deseas tu pedido?'),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Selecciona una modalidad:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // Opción 1: Comer en el Local
            _buildOptionCard(
              type: 'local',
              title: 'Comer en el Local',
              subtitle: 'Estás en K\'OTEMAL y te lo llevamos a la mesa',
              icon: Icons.table_restaurant,
            ),
            const SizedBox(height: 12),

            // Opción 2: Para Llevar / Recoger
            _buildOptionCard(
              type: 'para_llevar',
              title: 'Para Llevar (Pick-up)',
              subtitle: 'Pasa a recogerlo directamente al mostrador',
              icon: Icons.takeout_dining,
            ),
            const SizedBox(height: 12),

            // Opción 3: A Domicilio
            _buildOptionCard(
              type: 'domicilio',
              title: 'A Domicilio (Delivery)',
              subtitle: 'Te lo enviamos con un repartidor a tu ubicación',
              icon: Icons.delivery_dining,
            ),
            const SizedBox(height: 24),

            // Formulario según la opción seleccionada
            if (_selectedDeliveryType == 'local') ...[
              TextField(
                controller: _tableController,
                decoration: const InputDecoration(
                  labelText: 'Número o Nombre de Mesa *',
                  hintText: 'Ej. Mesa 3 / Barra',
                  prefixIcon: Icon(Icons.pin),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
            ],

            if (_selectedDeliveryType != 'domicilio') ...[
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Teléfono de contacto *',
                  prefixIcon: Icon(Icons.phone),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Instrucciones adicionales (opcional)',
                  hintText: 'Ej. Servir sin hielo, cubiertos extra',
                  prefixIcon: Icon(Icons.note_alt_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrange,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _isSending ? null : _submitOnSiteOrder,
                  child: _isSending
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          'Confirmar Pedido (Q${total.toStringAsFixed(2)})',
                          style: const TextStyle(fontSize: 16),
                        ),
                ),
              ),
            ] else ...[
              // Si elige Domicilio, se muestra el botón para abrir el mapa
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const DeliveryScreen()),
                    );
                  },
                  icon: const Icon(Icons.map_outlined),
                  label: const Text(
                    'Continuar a fijar Ubicación GPS',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOptionCard({
    required String type,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final isSelected = _selectedDeliveryType == type;

    return Card(
      elevation: isSelected ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? Colors.deepOrange : Colors.grey.shade300,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: ListTile(
        onTap: () => setState(() => _selectedDeliveryType = type),
        leading: CircleAvatar(
          backgroundColor: isSelected ? Colors.deepOrange.shade100 : Colors.grey.shade100,
          foregroundColor: isSelected ? Colors.deepOrange : Colors.black87,
          child: Icon(icon),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: Radio<String>(
          value: type,
          groupValue: _selectedDeliveryType,
          activeColor: Colors.deepOrange,
          onChanged: (val) {
            if (val != null) setState(() => _selectedDeliveryType = val);
          },
        ),
      ),
    );
  }
}