class Product {
  final int id;
  final String name;
  final String category;
  final String? description;
  final double price;
  final String? imageUrl;
  final bool isAvailable;

  Product({
    required this.id,
    required this.name,
    required this.category,
    this.description,
    required this.price,
    this.imageUrl,
    required this.isAvailable,
  });

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'] as int,
      name: map['name'] as String,
      category: map['category'] as String,
      description: map['description'] as String?,
      price: (map['price'] as num).toDouble(),
      imageUrl: map['image_url'] as String?,
      isAvailable: map['is_available'] as bool? ?? true,
    );
  }
}