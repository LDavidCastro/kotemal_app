import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kotemal_app/main.dart';

void main() {
  testWidgets("muestra la pantalla inicial de K'OTEMAL", (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: KotemalApp()));

    expect(find.text("K'OTEMAL"), findsOneWidget);
    expect(find.text('Comida local, entregada a tu puerta.'), findsOneWidget);
  });
}
