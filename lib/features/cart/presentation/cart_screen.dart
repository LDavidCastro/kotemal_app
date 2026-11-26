import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/reward_tier.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/image_focus_helper.dart';
import '../../menu/presentation/product_customization_dialog.dart';
import '../../menu/presentation/widgets/product_image_viewer.dart';
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
    final CustomizedProductResult? result =
        await showModalBottomSheet<CustomizedProductResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.88,
        child: ClipRRect(
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24)),
          child: ProductCustomizationDialog(
            product: item.product,
            initialNotes: item.notes,
            initialQuantity: item.quantity,
          ),
        ),
      ),
    );

    if (result != null) {
      ref.read(cartProvider.notifier).editCustomization(
            index,
            newNotes: result.notes.isNotEmpty ? result.notes : null,
            newUnitPrice: result.finalPrice,
            newImageUrl: result.selectedImageUrl,
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

  Future<void> _confirmClearCart(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.delete_sweep, color: Colors.deepOrange),
            SizedBox(width: 10),
            Text('Vaciar carrito'),
          ],
        ),
        content: const Text(
          '¿Seguro que quieres eliminar todos los artículos de tu pedido?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepOrange,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Vaciar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      ref.read(cartProvider.notifier).clearCart();
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

  List<String> _parseNotes(String? notes) {
    if (notes == null || notes.trim().isEmpty) return [];
    return notes.split(' | ').where((s) => s.trim().isNotEmpty).toList();
  }

  Widget _buildNoteChip(String section) {
    if (section.startsWith('OPCIÓN: ')) {
      final value = section.replaceFirst('OPCIÓN: ', '').trim();
      return Chip(
        avatar: const Icon(Icons.restaurant_menu, size: 16, color: Colors.deepOrange),
        label: Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        ),
        backgroundColor: Colors.orange.shade50,
        side: BorderSide(color: Colors.orange.shade200),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );
    }

    if (section.startsWith('SIN: ')) {
      final value = section.replaceFirst('SIN: ', '').trim();
      return Chip(
        avatar: Icon(Icons.remove_circle_outline, size: 16, color: Colors.red.shade700),
        label: Text(
          value,
          style: TextStyle(fontSize: 12, color: Colors.red.shade800),
        ),
        backgroundColor: Colors.red.shade50,
        side: BorderSide(color: Colors.red.shade200),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );
    }

    if (section.startsWith('CON EXTRA: ')) {
      final value = section.replaceFirst('CON EXTRA: ', '').trim();
      return Chip(
        avatar: Icon(Icons.add_circle_outline, size: 16, color: Colors.green.shade700),
        label: Text(
          value,
          style: TextStyle(fontSize: 12, color: Colors.green.shade800),
        ),
        backgroundColor: Colors.green.shade50,
        side: BorderSide(color: Colors.green.shade200),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );
    }

    return Chip(
      avatar: Icon(Icons.notes, size: 16, color: Colors.grey.shade700),
      label: Text(
        section.trim(),
        style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
      ),
      backgroundColor: Colors.amber.shade50,
      side: BorderSide(color: Colors.amber.shade200),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartItems = ref.watch(cartProvider);
    final total = ref.watch(cartTotalProvider);
    final itemCount = ref.watch(cartCountProvider);
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
      backgroundColor: const Color(0xFFF7F7F9),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFFF7F7F9),
        foregroundColor: Colors.black87,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Mi Pedido',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            if (itemCount > 0)
              Text(
                '$itemCount artículo${itemCount == 1 ? '' : 's'}',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
        actions: [
          if (cartItems.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Vaciar carrito',
              onPressed: () => _confirmClearCart(context, ref),
            ),
        ],
      ),
      body: cartItems.isEmpty
          ? _buildEmptyState(context)
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
                      final noteSections = _parseNotes(item.notes);
                      final imageUrl = item.displayImageUrl;
                      final hasImage = imageUrl != null && imageUrl.isNotEmpty;

                      return Card(
                        elevation: 0,
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  GestureDetector(
                                    onTap: hasImage
                                        ? () => showProductImageViewer(
                                              context,
                                              imageUrl: imageUrl,
                                              title: item.product.name,
                                            )
                                        : null,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: hasImage
                                          ? Image.network(
                                              stripImageFocus(imageUrl),
                                              width: 76,
                                              height: 76,
                                              fit: BoxFit.cover,
                                              alignment:
                                                  parseImageFocus(imageUrl),
                                              errorBuilder: (_, _, _) => _avatar(item),
                                            )
                                          : _avatar(item),
                                    ),
                                  ),
                                  const SizedBox(width: 14),

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
                                        const SizedBox(height: 2),
                                        Text(
                                          'Q${item.unitPrice.toStringAsFixed(2)} c/u',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        _buildQuantityPill(ref, item),
                                      ],
                                    ),
                                  ),

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

                              if (isCustomized && noteSections.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: noteSections
                                      .map((section) => _buildNoteChip(section))
                                      .toList(),
                                ),
                              ],

                              const SizedBox(height: 12),
                              const Divider(height: 1),
                              const SizedBox(height: 10),

                              SizedBox(
                                width: double.infinity,
                                child: TextButton.icon(
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    visualDensity: VisualDensity.compact,
                                    foregroundColor: Colors.blue.shade800,
                                    alignment: Alignment.centerLeft,
                                  ),
                                  icon: const Icon(Icons.edit, size: 18),
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
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                _buildSummary(
                  context,
                  ref,
                  total: total,
                  totalToPay: totalToPay,
                  discount: discount,
                  userPoints: userPoints,
                  appliedReward: appliedReward,
                  pointsToEarn: pointsToEarn,
                ),
              ],
            ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 52,
              backgroundColor: Colors.orange.shade50,
              child: Icon(
                Icons.shopping_bag_outlined,
                size: 48,
                color: Colors.orange.shade700,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Tu carrito está vacío',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Descubre los platillos de K\'OTEMAL y arma tu pedido.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.restaurant_menu),
              label: const Text(
                'Volver al Menú',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuantityPill(WidgetRef ref, CartItem item) {
    return Container(
      height: 34,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(20),
        color: Colors.white,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
              onTap: () => ref.read(cartProvider.notifier).updateQuantity(
                item.product.id,
                item.quantity - 1,
                notes: item.notes,
              ),
              child: Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                child: Icon(
                  item.quantity == 1 ? Icons.delete_outline : Icons.remove,
                  size: 18,
                  color: item.quantity == 1 ? Colors.red : Colors.black87,
                ),
              ),
            ),
          ),
          Container(
            constraints: const BoxConstraints(minWidth: 32),
            alignment: Alignment.center,
            child: Text(
              '${item.quantity}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(20)),
              onTap: () => ref.read(cartProvider.notifier).updateQuantity(
                item.product.id,
                item.quantity + 1,
                notes: item.notes,
              ),
              child: Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                child: const Icon(
                  Icons.add,
                  size: 18,
                  color: Colors.deepOrange,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(
    BuildContext context,
    WidgetRef ref, {
    required double total,
    required double totalToPay,
    required double discount,
    required int userPoints,
    required RewardTier? appliedReward,
    required int pointsToEarn,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (userPoints >= 150) ...[
              _buildRewardCard(ref, userPoints, total, appliedReward),
              const SizedBox(height: 14),
            ],
            if (appliedReward != null) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Subtotal artículos',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                  ),
                  Text(
                    Formatters.currency(total),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Descuento por puntos',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.green.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '-${Formatters.currency(discount)}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.green.shade800,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1),
              ),
            ] else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Subtotal artículos',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                  ),
                  Text(
                    Formatters.currency(total),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total a pagar',
                  style: TextStyle(
                    fontSize: 18,
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
            if (pointsToEarn > 0) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.stars, size: 16, color: Colors.green),
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
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepOrange,
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
                      builder: (_) => const CheckoutTypeScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.arrow_forward),
                label: const Text(
                  'Continuar con el Pedido',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatar(CartItem item) {
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Text(
        item.product.name.isNotEmpty ? item.product.name[0].toUpperCase() : '?',
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.deepOrange,
          fontSize: 28,
        ),
      ),
    );
  }
}
