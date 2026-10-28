import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_colors.dart';
import 'core/services/supabase_service.dart';
import 'features/menu/presentation/menu_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.initialize();
  runApp(const ProviderScope(child: KotemalApp()));
}

class KotemalApp extends StatelessWidget {
  const KotemalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "K'OTEMAL",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        scaffoldBackgroundColor: AppColors.background,
      ),
      home: const MenuScreen(),
    );
  }
}