import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/reward_tier.dart';
import '../../menu/domain/product.dart';

class CartItem {
  final Product product;
  final int quantity;
  final String? notes; // Ej: "SIN: Cebolla | CON EXTRA: Queso extra"
  final double unitPrice;

  /// Foto de la variante elegida (puede incluir `#focus=x,y`). Si es null se
  /// usa la foto principal de [product].
  final String? imageUrl;

  CartItem({
    required this.product,
    this.quantity = 1,
    this.notes,
    double? unitPrice,
    this.imageUrl,
  }) : unitPrice = unitPrice ?? product.price;

  double get subtotal => unitPrice * quantity;

  /// Foto efectiva a mostrar en el carrito.
  String? get displayImageUrl =>
      (imageUrl != null && imageUrl!.isNotEmpty) ? imageUrl : product.imageUrl;

  CartItem copyWith({
    Product? product,
    int? quantity,
    String? notes,
    double? unitPrice,
    String? imageUrl,
  }) {
    return CartItem(
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
      notes: notes ?? this.notes,
      unitPrice: unitPrice ?? this.unitPrice,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }
}

class CartNotifier extends StateNotifier<List<CartItem>> {
  CartNotifier(this._ref) : super([]);

  final Ref _ref;

  double get _subtotal =>
      state.fold(0.0, (sum, item) => sum + item.subtotal);

  void _validateSelectedReward() {
    final reward = _ref.read(selectedRewardProvider);
    if (reward == null) return;

    if (state.isEmpty || _subtotal < reward.minFoodSubtotal) {
      _ref.read(selectedRewardProvider.notifier).state = null;
    }
  }

  void addProduct(
    Product product, {
    String? notes,
    double? customPrice,
    String? imageUrl,
  }) {
    final finalPrice = customPrice ?? product.price;
    final itemNotes = notes ?? '';

    // Si coincide el producto y las mismas notas, se suma cantidad; si tiene personalización distinta, se agrega por separado
    final index = state.indexWhere(
      (item) => item.product.id == product.id && (item.notes ?? '') == itemNotes,
    );

    if (index >= 0) {
      final existing = state[index];
      state = [
        ...state.sublist(0, index),
        CartItem(
          product: existing.product,
          quantity: existing.quantity + 1,
          notes: existing.notes,
          unitPrice: existing.unitPrice,
          imageUrl: imageUrl ?? existing.imageUrl,
        ),
        ...state.sublist(index + 1),
      ];
    } else {
      state = [
        ...state,
        CartItem(
          product: product,
          quantity: 1,
          notes: itemNotes.isNotEmpty ? itemNotes : null,
          unitPrice: finalPrice,
          imageUrl: imageUrl,
        ),
      ];
    }

    _validateSelectedReward();
  }

  void updateQuantity(int productId, int quantity, {String? notes}) {
    if (quantity <= 0) {
      state = state.where((item) {
        if (item.product.id != productId) return true;
        if (notes != null && item.notes != notes) return true;
        return false;
      }).toList();
    } else {
      state = state.map((item) {
        if (item.product.id == productId && (notes == null || item.notes == notes)) {
          return item.copyWith(quantity: quantity);
        }
        return item;
      }).toList();
    }

    _validateSelectedReward();
  }

  // Método para editar los ingredientes y precio sin borrar el elemento
  void editCustomization(
    int index, {
    required String? newNotes,
    required double newUnitPrice,
    String? newImageUrl,
  }) {
    if (index < 0 || index >= state.length) return;

    final existing = state[index];
    final updated = CartItem(
      product: existing.product,
      quantity: existing.quantity,
      notes: newNotes,
      unitPrice: newUnitPrice,
      imageUrl: newImageUrl,
    );

    state = [
      ...state.sublist(0, index),
      updated,
      ...state.sublist(index + 1),
    ];

    _validateSelectedReward();
  }

  void clearCart() {
    state = [];
    _ref.read(selectedRewardProvider.notifier).state = null;
  }
}

final cartProvider = StateNotifierProvider<CartNotifier, List<CartItem>>((ref) {
  return CartNotifier(ref);
});

final selectedRewardProvider = StateProvider<RewardTier?>((ref) => null);

final userPointsProvider = FutureProvider.autoDispose<int>((ref) async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return 0;

  final data = await Supabase.instance.client
      .from('profiles')
      .select('points')
      .eq('id', user.id)
      .maybeSingle();

  return (data?['points'] as num?)?.toInt() ?? 0;
});

final cartTotalProvider = Provider<double>((ref) {
  final cart = ref.watch(cartProvider);
  return cart.fold(0.0, (sum, item) => sum + item.subtotal);
});

final cartCountProvider = Provider<int>((ref) {
  final cart = ref.watch(cartProvider);
  return cart.fold(0, (count, item) => count + item.quantity);
});