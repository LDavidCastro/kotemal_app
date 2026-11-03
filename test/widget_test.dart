import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kotemal_app/features/cart/presentation/cart_screen.dart';

void main() {
  testWidgets('muestra el carrito vacío sin requerir Supabase', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: CartScreen()),
      ),
    );

    expect(find.text('Mi Pedido'), findsOneWidget);
    expect(find.text('Tu carrito está vacío.'), findsOneWidget);
  });
}
