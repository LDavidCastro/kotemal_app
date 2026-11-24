class Product {
  final int id;
  final String name;
  final String category;
  final String? description;
  final double price;
  final String? imageUrl;
  final bool isAvailable;
  final bool hasVariants;
  final double? minVariantPrice;

  Product({
    required this.id,
    required this.name,
    required this.category,
    this.description,
    required this.price,
    this.imageUrl,
    required this.isAvailable,
    this.hasVariants = false,
    this.minVariantPrice,
  });

  factory Product.fromMap(Map<String, dynamic> map) {
    var hasVariants = false;
    double? minVariantPrice;

    final rawCustomizations = map['product_customizations'];
    if (rawCustomizations is List) {
      final activeVariants = rawCustomizations
          .whereType<Map>()
          .where(
            (c) =>
                c['type'] == 'variant' && (c['is_available'] ?? true) == true,
          )
          .toList();

      if (activeVariants.isNotEmpty) {
        hasVariants = true;

        final prices = activeVariants
            .map((c) => c['price'])
            .whereType<num>()
            .map((p) => p.toDouble())
            .toList();

        if (prices.isNotEmpty) {
          minVariantPrice = prices.reduce((a, b) => a < b ? a : b);
        }
      }
    }

    return Product(
      id: map['id'] as int,
      name: map['name'] as String,
      category: map['category'] as String,
      description: map['description'] as String?,
      price: (map['price'] as num).toDouble(),
      imageUrl: map['image_url'] as String?,
      isAvailable: map['is_available'] as bool? ?? true,
      hasVariants: hasVariants,
      minVariantPrice: minVariantPrice,
    );
  }
}
