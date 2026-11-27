import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/constants/app_colors.dart';
import 'core/navigation/app_navigator.dart';
import 'core/services/customer_order_notification_service.dart';
import 'core/services/order_background_monitor.dart';
import 'core/services/supabase_service.dart';
import 'features/menu/presentation/menu_screen.dart';
import 'features/orders/presentation/order_tracking_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.initialize();
  await CustomerOrderNotificationService.instance.init();

  // Al tocar una notificación de pedido, abre su seguimiento.
  CustomerOrderNotificationService.instance.onOrderTap = (orderId) {
    final navigator = appNavigatorKey.currentState;
    if (navigator == null) return;
    navigator.push(
      MaterialPageRoute(
        builder: (_) => OrderTrackingScreen(orderId: orderId),
      ),
    );
  };

  runApp(const ProviderScope(child: KotemalApp()));

  await OrderBackgroundMonitor.instance.start();
  Supabase.instance.client.auth.onAuthStateChange.listen((_) {
    OrderBackgroundMonitor.instance.refreshSession();
  });
}

class KotemalApp extends StatelessWidget {
  const KotemalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "K'OTEMAL",
      navigatorKey: appNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          secondary: AppColors.secondary,
        ),
        scaffoldBackgroundColor: AppColors.background,
      ),
      home: const MenuScreen(),
    );
  }
}
