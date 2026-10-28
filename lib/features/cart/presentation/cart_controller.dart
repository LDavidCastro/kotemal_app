import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../menu/domain/product.dart';

class CartItem {
  final Product product;
  final int quantity;
  final String? notes; // Ej: "SIN: Cebolla | CON EXTRA: Queso extra"
  final double unitPrice;

  CartItem({
    required this.product,
    this.quantity = 1,
    this.notes,
    double? unitPrice,
  }) : unitPrice = unitPrice ?? product.price;

  double get subtotal => unitPrice * quantity;

  CartItem copyWith({
    Product? product,
    int? quantity,
    String? notes,
    double? unitPrice,
  }) {
    return CartItem(
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
      notes: notes ?? this.notes,
      unitPrice: unitPrice ?? this.unitPrice,
    );
  }
}

class CartNotifier extends StateNotifier<List<CartItem>> {
  CartNotifier() : super([]);

  void addProduct(Product product, {String? notes, double? customPrice}) {
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
        existing.copyWith(quantity: existing.quantity + 1),
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
        ),
      ];
    }
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
  }

  // Método para editar los ingredientes y precio sin borrar el elemento
  void editCustomization(
    int index, {
    required String? newNotes,
    required double newUnitPrice,
  }) {
    if (index < 0 || index >= state.length) return;

    final existing = state[index];
    final updated = existing.copyWith(
      notes: newNotes,
      unitPrice: newUnitPrice,
    );

    state = [
      ...state.sublist(0, index),
      updated,
      ...state.sublist(index + 1),
    ];
  }

  void clearCart() => state = [];
}

final cartProvider = StateNotifierProvider<CartNotifier, List<CartItem>>((ref) {
  return CartNotifier();
});

final cartTotalProvider = Provider<double>((ref) {
  final cart = ref.watch(cartProvider);
  return cart.fold(0.0, (sum, item) => sum + item.subtotal);
});

final cartCountProvider = Provider<int>((ref) {
  final cart = ref.watch(cartProvider);
  return cart.fold(0, (count, item) => count + item.quantity);
});