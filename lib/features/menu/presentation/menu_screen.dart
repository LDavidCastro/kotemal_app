import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/menu_provider.dart';
import '../domain/product.dart';
import '../../admin/presentation/orders_dashboard_screen.dart';
import '../../admin/presentation/product_edit_screen.dart';
import '../../admin/presentation/users_roles_screen.dart';
import '../../auth/presentation/auth_screen.dart';
import '../../auth/presentation/profile_screen.dart';
import '../../cart/presentation/cart_controller.dart';
import '../../cart/presentation/cart_screen.dart';
import '../../delivery/presentation/driver_orders_screen.dart';
import 'product_customization_dialog.dart';

class MenuScreen extends ConsumerStatefulWidget {
  const MenuScreen({super.key});

  @override
  ConsumerState<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends ConsumerState<MenuScreen> {
  String _userRole = 'cliente';

  @override
  void initState() {
    super.initState();
    _checkRole();
  }

  Future<void> _checkRole() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _userRole = 'cliente');
      return;
    }

    try {
      final res = await Supabase.instance.client
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();

      if (mounted && res != null && res['role'] != null) {
        setState(() => _userRole = res['role'] as String);
      }
    } catch (_) {
      if (mounted) setState(() => _userRole = 'cliente');
    }
  }

  @override
  Widget build(BuildContext context) {
    final menuAsync = ref.watch(menuListProvider);
    final cartCount = ref.watch(cartCountProvider);
    final currentUser = Supabase.instance.client.auth.currentUser;

    final isAdmin = _userRole == 'admin';
    final isKitchen = _userRole == 'admin' || _userRole == 'cocinero';
    final isDriver = _userRole == 'admin' || _userRole == 'repartidor';

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("K'OTEMAL - Menú"),
          centerTitle: true,
          actions: [
            if (isAdmin)
              IconButton(
                icon: const Icon(Icons.manage_accounts),
                tooltip: 'Asignar Roles',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const UsersRolesScreen()),
                  );
                },
              ),
            if (isKitchen)
              IconButton(
                icon: const Icon(Icons.receipt_long_outlined),
                tooltip: 'Panel de Cocina',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const OrdersDashboardScreen()),
                  );
                },
              ),
            if (isDriver)
              IconButton(
                icon: const Icon(Icons.two_wheeler),
                tooltip: 'Rutas y Entregas',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const DriverOrdersScreen()),
                  );
                },
              ),
            IconButton(
              icon: const Icon(Icons.person_outline),
              tooltip: currentUser != null ? 'Mi Perfil' : 'Iniciar Sesión',
              onPressed: () async {
                if (currentUser != null) {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                  );
                } else {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AuthScreen()),
                  );
                }
                _checkRole();
              },
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(icon: Icon(Icons.lunch_dining), text: 'Comidas'),
              Tab(icon: Icon(Icons.local_cafe), text: 'Bebidas'),
              Tab(icon: Icon(Icons.cake), text: 'Postres'),
            ],
          ),
        ),
        body: menuAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, stack) => Center(child: Text('Error: $err')),
          data: (products) {
            return TabBarView(
              children: [
                _ProductList(
                  products: products
                      .where((p) => p.category.trim().toLowerCase().contains('comida'))
                      .toList(),
                  isAdmin: isAdmin,
                  onRefresh: () => ref.refresh(menuListProvider),
                ),
                _ProductList(
                  products: products
                      .where((p) => p.category.trim().toLowerCase().contains('bebida'))
                      .toList(),
                  isAdmin: isAdmin,
                  onRefresh: () => ref.refresh(menuListProvider),
                ),
                _ProductList(
                  products: products
                      .where((p) => p.category.trim().toLowerCase().contains('postre'))
                      .toList(),
                  isAdmin: isAdmin,
                  onRefresh: () => ref.refresh(menuListProvider),
                ),
              ],
            );
          },
        ),
        floatingActionButton: isAdmin
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (cartCount > 0) ...[
                    FloatingActionButton.extended(
                      heroTag: 'btn_cart',
                      backgroundColor: Colors.deepOrange,
                      foregroundColor: Colors.white,
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const CartScreen()),
                        );
                      },
                      icon: const Icon(Icons.shopping_bag_outlined),
                      label: Text('Ver Carrito ($cartCount)'),
                    ),
                    const SizedBox(height: 12),
                  ],
                  FloatingActionButton.extended(
                    heroTag: 'btn_add_product',
                    backgroundColor: Colors.blue.shade800,
                    foregroundColor: Colors.white,
                    onPressed: () async {
                      final created = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ProductEditScreen(),
                        ),
                      );
                      if (created == true) {
                        ref.refresh(menuListProvider);
                      }
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Nuevo Platillo'),
                  ),
                ],
              )
            : (cartCount > 0
                ? FloatingActionButton.extended(
                    heroTag: 'btn_cart',
                    backgroundColor: Colors.deepOrange,
                    foregroundColor: Colors.white,
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const CartScreen()),
                      );
                    },
                    icon: const Icon(Icons.shopping_bag_outlined),
                    label: Text('Ver Carrito ($cartCount)'),
                  )
                : null),
      ),
    );
  }
}

class _ProductList extends ConsumerWidget {
  final List<Product> products;
  final bool isAdmin;
  final VoidCallback onRefresh;

  const _ProductList({
    required this.products,
    required this.isAdmin,
    required this.onRefresh,
  });

  Future<void> _handleProductTap(BuildContext context, WidgetRef ref, Product item) async {
    if (!item.isAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este producto está agotado temporalmente.')),
      );
      return;
    }

    final cat = item.category.trim().toLowerCase();
    final bool canCustomize = cat.contains('comida') || cat.contains('postre');

    if (canCustomize) {
      final CustomizedProductResult? result = await showDialog<CustomizedProductResult>(
        context: context,
        builder: (_) => ProductCustomizationDialog(product: item),
      );

      if (result != null) {
        ref.read(cartProvider.notifier).addProduct(
              item,
              notes: result.notes,
              customPrice: result.finalPrice,
            );
        if (context.mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${item.name} agregado al carrito.'),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      }
    } else {
      ref.read(cartProvider.notifier).addProduct(item);
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Agregado: ${item.name}'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (products.isEmpty) {
      return const Center(child: Text('No hay productos disponibles.'));
    }

    final cartItems = ref.watch(cartProvider);

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: products.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = products[index];
        final isAvailable = item.isAvailable;

        final int itemCountInCart = cartItems
            .where((ci) => ci.product.id == item.id)
            .fold(0, (sum, ci) => sum + ci.quantity);

        final bool isSelected = itemCountInCart > 0;

        return Opacity(
          opacity: isAvailable ? 1.0 : 0.6,
          child: Card(
            elevation: isSelected ? 3 : 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: !isAvailable
                    ? Colors.grey.shade400
                    : (isSelected ? Colors.deepOrange.shade400 : Colors.grey.shade200),
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: isAvailable ? () => _handleProductTap(context, ref, item) : null,
              onLongPress: isAdmin
                  ? () async {
                      final updated = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProductEditScreen(product: item),
                        ),
                      );
                      if (updated == true) onRefresh();
                    }
                  : null,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                              ? Image.network(
                                  item.imageUrl!,
                                  width: 105,
                                  height: 105,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => _defaultAvatar(item),
                                )
                              : _defaultAvatar(item),
                        ),
                        if (isSelected)
                          Positioned(
                            top: 6,
                            left: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.deepOrange,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 4,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Text(
                                'x$itemCountInCart',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        if (!isAvailable)
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black45,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Center(
                                child: Text(
                                  'AGOTADO',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: SizedBox(
                        height: 105,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    decoration: isAvailable
                                        ? TextDecoration.none
                                        : TextDecoration.lineThrough,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  item.description ?? '',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'Q${item.price.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: isAvailable ? Colors.green : Colors.grey,
                                  ),
                                ),
                                Row(
                                  children: [
                                    if (isAdmin)
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined, size: 20, color: Colors.blueGrey),
                                        visualDensity: VisualDensity.compact,
                                        tooltip: 'Editar opciones y foto',
                                        onPressed: () async {
                                          final updated = await Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => ProductEditScreen(product: item),
                                            ),
                                          );
                                          if (updated == true) onRefresh();
                                        },
                                      ),
                                    if (isAvailable)
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: isSelected
                                              ? Colors.deepOrange
                                              : Colors.orange.shade50,
                                          foregroundColor: isSelected
                                              ? Colors.white
                                              : Colors.deepOrange,
                                          elevation: isSelected ? 2 : 0,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        onPressed: () => _handleProductTap(context, ref, item),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(isSelected ? Icons.check : Icons.add, size: 16),
                                            const SizedBox(width: 4),
                                            Text(isSelected ? 'Agregar +' : 'Pedir'),
                                          ],
                                        ),
                                      )
                                    else
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade300,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Text(
                                          'No disponible',
                                          style: TextStyle(fontSize: 11, color: Colors.black54),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _defaultAvatar(Product item) {
    return Container(
      width: 105,
      height: 105,
      color: Colors.orange.shade100,
      alignment: Alignment.center,
      child: Text(
        item.name.isNotEmpty ? item.name.substring(0, 1).toUpperCase() : '?',
        style: const TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: Colors.deepOrange,
        ),
      ),
    );
  }
}