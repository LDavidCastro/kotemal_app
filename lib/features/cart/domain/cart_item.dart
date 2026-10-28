import '../../menu/domain/product.dart';

class CartItem {
  final Product product;
  int quantity;
  String? notes;

  CartItem({
    required this.product,
    this.quantity = 1,
    this.notes,
  });

  double get subtotal => product.price * quantity;
}