import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/menu_provider.dart';
import '../domain/product.dart';
import '../../admin/presentation/cash_closing_screen.dart';
import '../../admin/presentation/orders_dashboard_screen.dart';
import '../../admin/presentation/product_edit_screen.dart';
import '../../admin/presentation/users_roles_screen.dart';
import '../../auth/presentation/auth_screen.dart';
import '../../auth/presentation/profile_screen.dart';
import '../../cart/presentation/cart_controller.dart';
import '../../cart/presentation/cart_screen.dart';
import '../../delivery/presentation/driver_orders_screen.dart';
import 'product_customization_dialog.dart';
import 'widgets/product_image_viewer.dart';
import '../../../core/utils/image_focus_helper.dart';

import '../../../core/models/reward_tier.dart';
import '../../../core/services/guest_orders_service.dart';
import '../../../core/services/order_background_monitor.dart';
import '../../orders/presentation/order_tracking_screen.dart';

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
      await OrderBackgroundMonitor.instance.refreshSession();
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

    await OrderBackgroundMonitor.instance.refreshSession();
  }

  String _formatOrderTime(dynamic createdAt) {
    final raw = createdAt?.toString();
    if (raw == null) return '--:--';

    final date = DateTime.tryParse(raw)?.toLocal();
    if (date == null) return '--:--';

    final hh = date.hour.toString().padLeft(2, '0');
    final mm = date.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'pendiente':
        return Colors.orange;
      case 'en cocina':
        return Colors.deepOrange;
      case 'listo':
        return Colors.green;
      case 'en camino':
        return Colors.blue;
      case 'entregado':
        return Colors.teal;
      case 'cancelado':
        return Colors.red;
      default:
        return Colors.blueGrey;
    }
  }

  Widget _buildStatusBadge(String label, String status) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  /// Despliega el modal de pedidos del día, tanto para invitados como para clientes registrados
  void _showOrdersModal(BuildContext context) async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    final bool isGuest = currentUser == null;

    final now = DateTime.now();
    final startOfDayIso =
        DateTime(now.year, now.month, now.day).toUtc().toIso8601String();

    List<int> guestOrderIds = [];
    if (isGuest) {
      guestOrderIds = await GuestOrdersService.getSavedOrderIds();
      if (!context.mounted) return;

      if (guestOrderIds.isEmpty) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Sin pedidos hoy'),
            content: const Text(
              'Aún no has realizado pedidos desde este dispositivo el día de hoy.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
        return;
      }
    }

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        // Solo pedidos realizados hoy, según si está autenticado o es invitado
        final ordersFuture = isGuest
            ? Supabase.instance.client
                .from('orders')
                .select('id, total, status, delivery_type, created_at')
                .inFilter('id', guestOrderIds)
                .gte('created_at', startOfDayIso)
                .order('id', ascending: false)
            : Supabase.instance.client
                .from('orders')
                .select('id, total, status, delivery_type, created_at')
                .eq('customer_id', currentUser.id)
                .gte('created_at', startOfDayIso)
                .order('id', ascending: false);

        return Container(
          height: MediaQuery.of(ctx).size.height * 0.72,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isGuest ? 'Pedidos de Hoy (Invitado)' : 'Pedidos de Hoy',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              if (isGuest)
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, size: 20, color: Colors.orange),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Pedidos guardados en este dispositivo. Inicia sesión para guardar tu historial en la nube y ganar puntos.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              const Divider(),
              Expanded(
                child: FutureBuilder(
                  future: ordersFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final orders = snapshot.data ?? [];
                    if (orders.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.receipt_long_outlined,
                                size: 48,
                                color: Colors.grey,
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'No tienes pedidos realizados hoy.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              if (!isGuest) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Puedes revisar tu historial completo en Mi Perfil -> Mis Pedidos.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      itemCount: orders.length,
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (context, index) {
                        final ord = orders[index];
                        final id = ord['id'] as int;
                        final total = ord['total'];
                        final rawStatus =
                            ord['status']?.toString().trim().toLowerCase() ??
                                'pendiente';
                        final st = rawStatus.toUpperCase();
                        final type = ord['delivery_type'] ?? 'domicilio';

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.deepOrange.shade100,
                            child: Icon(
                              type == 'domicilio'
                                  ? Icons.delivery_dining
                                  : (type == 'local'
                                      ? Icons.table_restaurant
                                      : Icons.takeout_dining),
                              color: Colors.deepOrange,
                            ),
                          ),
                          title: Text(
                            'Orden #$id - Q$total',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            'Hora: ${_formatOrderTime(ord['created_at'])}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildStatusBadge(st, rawStatus),
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_forward_ios, size: 14),
                            ],
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => OrderTrackingScreen(orderId: id),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPointsBanner(
    BuildContext context,
    int points,
    RewardTier reward,
  ) {
    return Material(
      color: Colors.amber.shade50,
      child: InkWell(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CartScreen()),
          );
          ref.invalidate(userPointsProvider);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.stars, color: Colors.amber, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '¡Tienes $points pts! Canjea hasta Q${reward.discountAmount.toStringAsFixed(0)} de descuento en tu carrito',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange.shade900,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, size: 18, color: Colors.orange),
            ],
          ),
        ),
      ),
    );
  }

  /// Banner de Modo Mostrador / Caja para el personal del restaurante.
  Widget _buildPosModeBanner(BuildContext context, WidgetRef ref) {
    final isPosMode = ref.watch(posModeProvider);

    if (!isPosMode) {
      return Material(
        color: Colors.grey.shade100,
        child: InkWell(
          onTap: () => ref.read(posModeProvider.notifier).state = true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(
                  Icons.point_of_sale,
                  size: 18,
                  color: Colors.blueGrey.shade700,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Atender cliente en mostrador',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: Colors.blueGrey.shade700,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.amber.shade100,
        border: Border(
          bottom: BorderSide(color: Colors.amber.shade400),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.storefront, size: 20, color: Colors.amber.shade900),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'MODO MOSTRADOR ACTIVO — Tomando pedido en caja',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: Colors.amber.shade900,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: Colors.amber.shade900,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onPressed: () => ref.read(posModeProvider.notifier).state = false,
            icon: const Icon(Icons.close, size: 16),
            label: const Text(
              'Salir',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final menuAsync = ref.watch(menuListProvider);
    final cartCount = ref.watch(cartCountProvider);
    final currentUser = Supabase.instance.client.auth.currentUser;
    final userPoints = ref.watch(userPointsProvider).valueOrNull ?? 0;
    final bestReward = RewardTier.bestAvailableFor(userPoints);
    final showPointsBanner =
        currentUser != null && userPoints >= 150 && bestReward != null;

    final isAdmin = _userRole == 'admin';
    final isKitchen = _userRole == 'cocinero';
    final isDriver = _userRole == 'repartidor';
    // Roles que pueden atender en mostrador/caja.
    final isPosStaff = isAdmin || _userRole == 'cocina' || isKitchen;

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

            if (isAdmin || isKitchen)
              IconButton(
                icon: const Icon(Icons.soup_kitchen_outlined),
                tooltip: 'Panel de Cocina',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const OrdersDashboardScreen(),
                    ),
                  );
                },
              ),

            if (isAdmin)
              IconButton(
                icon: const Icon(Icons.point_of_sale),
                tooltip: 'Cierre de Caja',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CashClosingScreen(),
                    ),
                  );
                },
              ),

            if (isAdmin || isDriver)
              IconButton(
                icon: const Icon(Icons.two_wheeler),
                tooltip: 'Rutas y Entregas',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DriverOrdersScreen(isAdmin: isAdmin),
                    ),
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
                ref.invalidate(userPointsProvider);
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
        body: Column(
          children: [
            if (isPosStaff) _buildPosModeBanner(context, ref),
            Expanded(
              child: menuAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (err, stack) => Center(child: Text('Error: $err')),
                data: (products) {
            return Column(
              children: [
                if (showPointsBanner)
                  _buildPointsBanner(context, userPoints, bestReward),
                Expanded(
                  child: TabBarView(
                    children: [
                      _ProductList(
                        products: products
                            .where((p) => p.category
                                .trim()
                                .toLowerCase()
                                .contains('comida'))
                            .toList(),
                        isAdmin: isAdmin,
                        onRefresh: () => ref.invalidate(menuListProvider),
                        maxRewardDiscount: showPointsBanner
                            ? bestReward.discountAmount
                            : null,
                      ),
                      _ProductList(
                        products: products
                            .where((p) => p.category
                                .trim()
                                .toLowerCase()
                                .contains('bebida'))
                            .toList(),
                        isAdmin: isAdmin,
                        onRefresh: () => ref.invalidate(menuListProvider),
                        maxRewardDiscount: showPointsBanner
                            ? bestReward.discountAmount
                            : null,
                      ),
                      _ProductList(
                        products: products
                            .where((p) => p.category
                                .trim()
                                .toLowerCase()
                                .contains('postre'))
                            .toList(),
                        isAdmin: isAdmin,
                        onRefresh: () => ref.invalidate(menuListProvider),
                        maxRewardDiscount: showPointsBanner
                            ? bestReward.discountAmount
                            : null,
                      ),
                    ],
                  ),
                ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
        bottomNavigationBar: _TodayOrdersBanner(
          key: ValueKey(currentUser?.id ?? 'guest'),
          userId: currentUser?.id,
          onOpenOrders: () => _showOrdersModal(context),
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
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const CartScreen(),
                          ),
                        );
                        ref.invalidate(userPointsProvider);
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
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ProductEditScreen(),
                        ),
                      );
                      ref.invalidate(menuListProvider);
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
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const CartScreen()),
                      );
                      ref.invalidate(userPointsProvider);
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
  final double? maxRewardDiscount;

  const _ProductList({
    required this.products,
    required this.isAdmin,
    required this.onRefresh,
    this.maxRewardDiscount,
  });

  Future<void> _handleProductTap(
      BuildContext context, WidgetRef ref, Product item) async {
    if (!item.isAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Este producto está agotado temporalmente.')),
      );
      return;
    }

    // Todos los productos (Comidas, Bebidas y Postres) abren el modal de
    // detalles para ver la foto ampliable, elegir variante, quitar
    // ingredientes, agregar extras y elegir cantidad.
    final CustomizedProductResult? result =
        await showModalBottomSheet<CustomizedProductResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.88,
        child: ClipRRect(
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24)),
          child: ProductCustomizationDialog(product: item),
        ),
      ),
    );

    if (result != null) {
      final cartNotifier = ref.read(cartProvider.notifier);
      for (var i = 0; i < result.quantity; i++) {
        cartNotifier.addProduct(
          item,
          notes: result.notes,
          customPrice: result.finalPrice,
          imageUrl: result.selectedImageUrl,
        );
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${result.quantity}x ${item.name} agregado al carrito.'),
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
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = products[index];
        final isAvailable = item.isAvailable;
        final isRewardEligible =
            maxRewardDiscount != null && item.price <= maxRewardDiscount!;

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
                    : (isSelected
                        ? Colors.deepOrange.shade400
                        : Colors.grey.shade200),
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: isAvailable ? () => _handleProductTap(context, ref, item) : null,
              onLongPress: isAdmin
                  ? () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ProductEditScreen(product: item),
                        ),
                      );
                      onRefresh();
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
                              ? GestureDetector(
                                  onTap: () => showProductImageViewer(
                                    context,
                                    imageUrl: item.imageUrl!,
                                    title: item.name,
                                  ),
                                  child: Stack(
                                    children: [
                                      Image.network(
                                        stripImageFocus(item.imageUrl!),
                                        width: 105,
                                        height: 105,
                                        fit: BoxFit.cover,
                                        alignment:
                                            parseImageFocus(item.imageUrl),
                                        errorBuilder: (_, _, _) => _defaultAvatar(item),
                                      ),
                                      Positioned(
                                        bottom: 6,
                                        right: 6,
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: Colors.black45,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: const Icon(
                                            Icons.zoom_in,
                                            size: 16,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : _defaultAvatar(item),
                        ),
                        if (isSelected)
                          Positioned(
                            top: 6,
                            left: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 3),
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
                                if (isRewardEligible) ...[
                                  const SizedBox(height: 2),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade50,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: Colors.green.shade200,
                                      ),
                                    ),
                                    child: Text(
                                      'Canjeable con puntos',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.green.shade800,
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 4),
                                Text(
                                  item.description ?? '',
                                  maxLines: isRewardEligible ? 1 : 2,
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
                                  item.hasVariants
                                      ? 'Desde Q${(item.minVariantPrice ?? item.price).toStringAsFixed(2)}'
                                      : 'Q${item.price.toStringAsFixed(2)}',
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
                                        icon: const Icon(Icons.edit_outlined,
                                            size: 20, color: Colors.blueGrey),
                                        visualDensity: VisualDensity.compact,
                                        tooltip: 'Editar opciones y foto',
                                        onPressed: () async {
                                          await Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  ProductEditScreen(product: item),
                                            ),
                                          );
                                          onRefresh();
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
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 6),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        onPressed: () =>
                                            _handleProductTap(context, ref, item),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(isSelected ? Icons.check : Icons.add,
                                                size: 16),
                                            const SizedBox(width: 4),
                                            Text(isSelected ? 'Agregar +' : 'Pedir'),
                                          ],
                                        ),
                                      )
                                    else
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade300,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Text(
                                          'No disponible',
                                          style: TextStyle(
                                              fontSize: 11, color: Colors.black54),
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

/// Banner reactivo de "Pedidos de Hoy" para clientes registrados e invitados.
///
/// Escucha en tiempo real los pedidos creados hoy del usuario actual o de los
/// IDs guardados por [GuestOrdersService] y ofrece acceso al modal de pedidos.
class _TodayOrdersBanner extends StatefulWidget {
  final String? userId;
  final VoidCallback onOpenOrders;

  const _TodayOrdersBanner({
    super.key,
    required this.userId,
    required this.onOpenOrders,
  });

  @override
  State<_TodayOrdersBanner> createState() => _TodayOrdersBannerState();
}

class _TodayOrdersBannerState extends State<_TodayOrdersBanner>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  StreamSubscription<List<Map<String, dynamic>>>? _subscription;
  Timer? _guestRefreshTimer;
  List<Map<String, dynamic>> _orders = const [];
  Set<int> _guestOrderIds = <int>{};

  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  late final Animation<double> _pulseScale = Tween<double>(
    begin: 1.0,
    end: 1.16,
  ).animate(
    CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
  );

  bool get _isGuest => widget.userId == null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void didUpdateWidget(covariant _TodayOrdersBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _bootstrap();
    } else if (_isGuest) {
      _refreshGuestIds(resubscribeIfChanged: true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isGuest) {
      _refreshGuestIds(resubscribeIfChanged: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _guestRefreshTimer?.cancel();
    _subscription?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _subscription?.cancel();
    _subscription = null;

    if (_isGuest) {
      await _refreshGuestIds();
    }

    _subscribe();

    _guestRefreshTimer?.cancel();
    if (_isGuest) {
      // Mantiene al día los IDs de invitado (por si se crea un pedido nuevo).
      _guestRefreshTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _refreshGuestIds(resubscribeIfChanged: true),
      );
    }
  }

  Future<void> _refreshGuestIds({bool resubscribeIfChanged = false}) async {
    if (!_isGuest) return;
    try {
      final ids = (await GuestOrdersService.getSavedOrderIds()).toSet();
      if (!mounted || _sameIds(ids, _guestOrderIds)) return;

      setState(() => _guestOrderIds = ids);
      if (resubscribeIfChanged) _subscribe();
    } catch (_) {}
  }

  bool _sameIds(Set<int> a, Set<int> b) =>
      a.length == b.length && a.containsAll(b);

  void _subscribe() {
    _subscription?.cancel();
    _subscription = null;

    final client = Supabase.instance.client;
    final now = DateTime.now();
    final startOfDayIso =
        DateTime(now.year, now.month, now.day).toUtc().toIso8601String();

    final base = client
        .from('orders')
        .stream(primaryKey: ['id'])
        .gte('created_at', startOfDayIso);

    if (!_isGuest) {
      _subscription = base
          .eq('customer_id', widget.userId!)
          .order('id', ascending: false)
          .listen(
            _onOrders,
            onError: (Object e) {
              debugPrint('Error en banner de pedidos de hoy: $e');
              if (mounted) setState(() {});
            },
          );
    } else if (_guestOrderIds.isNotEmpty) {
      _subscription = base
          .inFilter('id', _guestOrderIds.toList())
          .order('id', ascending: false)
          .listen(
            _onOrders,
            onError: (Object e) {
              debugPrint('Error en banner de pedidos de hoy (invitado): $e');
              if (mounted) setState(() {});
            },
          );
    } else {
      setState(() => _orders = const []);
    }
  }

  void _onOrders(List<Map<String, dynamic>> orders) {
    if (!mounted) return;
    setState(() => _orders = orders);
  }

  String _statusOf(Map<String, dynamic> order) =>
      (order['status'] ?? '').toString().trim().toLowerCase();

  String _statusLabel(String status) {
    switch (status) {
      case 'en cocina':
        return 'EN COCINA';
      case 'en camino':
        return 'EN CAMINO';
      case 'listo':
        return 'LISTO';
      case 'pendiente':
        return 'PENDIENTE';
      case 'entregado':
        return 'ENTREGADO';
      case 'cancelado':
        return 'CANCELADO';
      default:
        return status.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeOrders = _orders.where((ord) {
      final st = (ord['status'] ?? '').toString().trim().toLowerCase();
      return st != 'entregado' && st != 'cancelado' && st != 'cancelled';
    }).toList();

    if (activeOrders.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [_buildActiveBanner(activeOrders)],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveBanner(List<Map<String, dynamic>> activeOrders) {
    final first = activeOrders.first;
    final firstId = first['id'];
    final firstStatus = _statusLabel(_statusOf(first));

    final String mainText;
    final String subtitle;
    if (activeOrders.length == 1) {
      mainText = 'Orden #$firstId · $firstStatus';
      subtitle = 'Toca para seguir tu pedido en tiempo real';
    } else {
      mainText = 'Tienes ${activeOrders.length} pedidos hoy';
      subtitle = activeOrders
          .map((o) => '#${o['id']} ${_statusLabel(_statusOf(o))}')
          .join('  ·  ');
    }

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: widget.onOpenOrders,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.orange.shade600, Colors.amber.shade500],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.orange.withValues(alpha: 0.28),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  shape: BoxShape.circle,
                ),
                child: ScaleTransition(
                  scale: _pulseScale,
                  child: const Icon(
                    Icons.receipt_long,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mainText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Ver pedidos →',
                  style: TextStyle(
                    color: Colors.orange.shade900,
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


}