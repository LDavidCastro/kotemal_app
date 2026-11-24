import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/reward_tier.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/image_focus_helper.dart';
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

  Widget _buildRewardCard(
    WidgetRef ref,
    int points,
    double subtotal,
    RewardTier? applied,
  ) {
    final bestByPoints = RewardTier.bestAvailableFor(points);
    final missingSubtotalTier =
        bestByPoints != null && subtotal < bestByPoints.minFoodSubtotal
            ? bestByPoints
            : null;

    return Card(
      elevation: 0,
      color: Colors.amber.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.amber.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.stars, color: Colors.amber, size: 22),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    "Canjear Puntos K'OTEMAL",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                Text(
                  '$points pts',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final tier in kRewardTiers)
                  _buildRewardChip(ref, tier, points, subtotal, applied),
              ],
            ),
            if (missingSubtotalTier != null) ...[
              const SizedBox(height: 8),
              Text(
                'Agrega ${Formatters.currency(missingSubtotalTier.minFoodSubtotal - subtotal)} más para usar este cupón de ${Formatters.currency(missingSubtotalTier.discountAmount)}.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.orange.shade900,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRewardChip(
    WidgetRef ref,
    RewardTier tier,
    int points,
    double subtotal,
    RewardTier? applied,
  ) {
    final enoughPoints = points >= tier.pointsRequired;
    final enoughSubtotal = subtotal >= tier.minFoodSubtotal;
    final canSelect = enoughPoints && enoughSubtotal;
    final selected = applied?.pointsRequired == tier.pointsRequired;

    final label = enoughPoints
        ? 'Q${tier.discountAmount.toStringAsFixed(0)} · ${tier.pointsRequired} pts'
        : 'Faltan ${tier.pointsRequired - points} pts';

    return ChoiceChip(
      label: Text(label),
      selected: selected,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      selectedColor: Colors.green.shade100,
      labelStyle: TextStyle(
        fontSize: 11,
        color: canSelect ? Colors.green.shade900 : Colors.grey.shade600,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      ),
      avatar: enoughPoints
          ? null
          : Icon(
              Icons.lock_outline,
              size: 14,
              color: Colors.grey.shade500,
            ),
      onSelected: canSelect
          ? (value) {
              ref.read(selectedRewardProvider.notifier).state =
                  value ? tier : null;
            }
          : null,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartItems = ref.watch(cartProvider);
    final total = ref.watch(cartTotalProvider);
    final userPoints = ref.watch(userPointsProvider).valueOrNull ?? 0;
    final selectedReward = ref.watch(selectedRewardProvider);

    final appliedReward = selectedReward != null &&
            total >= selectedReward.minFoodSubtotal
        ? selectedReward
        : null;
    final discount = appliedReward?.discountAmount ?? 0;
    final discountedTotal = total - discount;
    final totalToPay = discountedTotal < 0 ? 0.0 : discountedTotal;
    final pointsToEarn = (totalToPay * 0.5).round();

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
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
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
                                            stripImageFocus(item.product.imageUrl!),
                                            width: 50,
                                            height: 50,
                                            fit: BoxFit.cover,
                                            alignment: parseImageFocus(
                                                item.product.imageUrl),
                                            errorBuilder: (_, _, _) => _avatar(item),
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
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 10,
                        offset: const Offset(0, -3),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (userPoints >= 150) ...[
                          _buildRewardCard(ref, userPoints, total, appliedReward),
                          const SizedBox(height: 12),
                        ],
                        if (appliedReward != null) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Subtotal:'),
                              Text(Formatters.currency(total)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Descuento por puntos (-${appliedReward.pointsRequired} pts):',
                                  style: TextStyle(
                                    color: Colors.green.shade800,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(
                                '-${Formatters.currency(discount)}',
                                style: TextStyle(
                                  color: Colors.green.shade800,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Total a pagar:',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                Formatters.currency(totalToPay),
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.stars,
                                  size: 16,
                                  color: Colors.green,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Ganarás +$pointsToEarn puntos al recibir tu pedido',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.green.shade800,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Total:',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                Formatters.currency(totalToPay),
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ],
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