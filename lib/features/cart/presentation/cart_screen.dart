import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../menu/presentation/product_customization_dialog.dart';
import 'cart_controller.dart';
import 'checkout_type_screen.dart';

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  Future<void> _editItemCustomization(
    BuildContext context,
    WidgetRef ref,
    int index,
    CartItem item,
  ) async {
    // Enviamos item.notes para precargar las opciones actuales
    final CustomizedProductResult? result = await showDialog<CustomizedProductResult>(
      context: context,
      builder: (_) => ProductCustomizationDialog(
        product: item.product,
        initialNotes: item.notes, // <--- AQUÍ SE ENVÍA LO QUE YA ESTABA SELECCIONADO
      ),
    );

    if (result != null) {
      ref.read(cartProvider.notifier).editCustomization(
            index,
            newNotes: result.notes.isNotEmpty ? result.notes : null,
            newUnitPrice: result.finalPrice,
          );

      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Opciones de "${item.product.name}" actualizadas ✓'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartItems = ref.watch(cartProvider);
    final total = ref.watch(cartTotalProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Pedido'),
        actions: [
          if (cartItems.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Vaciar carrito',
              onPressed: () => ref.read(cartProvider.notifier).clearCart(),
            ),
        ],
      ),
      body: cartItems.isEmpty
          ? const Center(
              child: Text(
                'Tu carrito está vacío.',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: cartItems.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final item = cartItems[index];
                      final isCustomized = item.notes != null && item.notes!.isNotEmpty;

                      return Card(
                        elevation: 1.5,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Imagen o avatar
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: item.product.imageUrl != null &&
                                            item.product.imageUrl!.isNotEmpty
                                        ? Image.network(
                                            item.product.imageUrl!,
                                            width: 50,
                                            height: 50,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => _avatar(item),
                                          )
                                        : _avatar(item),
                                  ),
                                  const SizedBox(width: 12),

                                  // Nombre y precio unitario
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.product.name,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          'Q${item.unitPrice.toStringAsFixed(2)} c/u',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Subtotal
                                  Text(
                                    'Q${item.subtotal.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                    ),
                                  ),
                                ],
                              ),

                              // Notas de personalización de ingredientes / extras
                              if (isCustomized) ...[
                                const SizedBox(height: 8),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.orange.shade200),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.tune,
                                        size: 16,
                                        color: Colors.deepOrange,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          item.notes!,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.deepOrange,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],

                              const SizedBox(height: 8),
                              const Divider(height: 10),

                              // Acciones: Botón de editar opciones y contador
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  // Modificar ingredientes sin salir
                                  TextButton.icon(
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      visualDensity: VisualDensity.compact,
                                      foregroundColor: Colors.blue.shade800,
                                    ),
                                    icon: const Icon(Icons.edit, size: 16),
                                    label: Text(
                                      isCustomized ? 'Modificar opciones' : 'Personalizar',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                    onPressed: () => _editItemCustomization(
                                      context,
                                      ref,
                                      index,
                                      item,
                                    ),
                                  ),

                                  // Contador de cantidad (+ / -)
                                  Row(
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.remove_circle_outline),
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () => ref
                                            .read(cartProvider.notifier)
                                            .updateQuantity(
                                              item.product.id,
                                              item.quantity - 1,
                                              notes: item.notes,
                                            ),
                                      ),
                                      Text(
                                        '${item.quantity}',
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.add_circle_outline),
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () => ref
                                            .read(cartProvider.notifier)
                                            .updateQuantity(
                                              item.product.id,
                                              item.quantity + 1,
                                              notes: item.notes,
                                            ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 10,
                        offset: const Offset(0, -3),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Total:',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Q${total.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ],
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
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const CheckoutTypeScreen(),
                                ),
                              );
                            },
                            child: const Text(
                              'Continuar Pedido',
                              style: TextStyle(fontSize: 16),
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

  Widget _avatar(CartItem item) {
    return Container(
      width: 50,
      height: 50,
      color: Colors.orange.shade100,
      alignment: Alignment.center,
      child: Text(
        item.product.name.isNotEmpty ? item.product.name[0].toUpperCase() : '?',
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.deepOrange,
          fontSize: 20,
        ),
      ),
    );
  }
}