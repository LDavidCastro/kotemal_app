import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/product.dart';

final menuListProvider = FutureProvider<List<Product>>((ref) async {
  final response = await Supabase.instance.client
      .from('products')
      .select()
      .eq('is_available', true)
      .order('category', ascending: true);

  return (response as List<dynamic>)
      .map((item) => Product.fromMap(item as Map<String, dynamic>))
      .toList();
});