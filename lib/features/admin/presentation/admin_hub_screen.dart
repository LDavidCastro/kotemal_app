import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'analytics_screen.dart';
import 'cash_closing_screen.dart';
import 'expenses_screen.dart';
import 'orders_dashboard_screen.dart';
import 'product_edit_screen.dart';
import 'users_roles_screen.dart';
import '../../delivery/presentation/driver_orders_screen.dart';

/// Hub centralizado de gestión operativa y administrativa.
///
/// Muestra únicamente las secciones a las que el usuario tiene permiso,
/// según las banderas que recibe desde [MenuScreen].
class AdminHubScreen extends StatefulWidget {
  final bool isAdmin;
  final bool canViewKitchen;
  final bool canViewDriver;
  final bool canViewCashClosing;
  final bool canViewExpenses;
  final bool canViewUsers;
  final bool canViewAnalytics;
  final bool canManageMenu;

  const AdminHubScreen({
    super.key,
    this.isAdmin = false,
    required this.canViewKitchen,
    required this.canViewDriver,
    required this.canViewCashClosing,
    required this.canViewExpenses,
    required this.canViewUsers,
    required this.canViewAnalytics,
    required this.canManageMenu,
  });

  @override
  State<AdminHubScreen> createState() => _AdminHubScreenState();
}

class _AdminHubScreenState extends State<AdminHubScreen> {
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  String _fullName = '';
  String _role = 'cliente';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final res = await _supabase
          .from('profiles')
          .select('full_name, role')
          .eq('id', user.id)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _isLoading = false;
          _fullName = (res?['full_name'] ?? '').toString();
          _role = (res?['role'] ?? 'cliente').toString();
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String get _roleLabel {
    switch (_role) {
      case 'admin':
        return 'Administrador';
      case 'cocinero':
      case 'cocina':
        return 'Cocina';
      case 'repartidor':
        return 'Repartidor';
      default:
        return 'Cliente';
    }
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Buenos días';
    if (hour < 18) return 'Buenas tardes';
    return 'Buenas noches';
  }

  List<_HubOption> _buildOptions(BuildContext context) {
    return [
      if (widget.canViewKitchen)
        _HubOption(
          title: 'Panel de Cocina',
          description:
              'Recibe comandas en tiempo real, cambia estados a listo y gestiona tiempos.',
          icon: Icons.soup_kitchen,
          color: const Color(0xFFC25229),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const OrdersDashboardScreen()),
          ),
        ),
      if (widget.canViewDriver)
        _HubOption(
          title: 'Rutas y Entregas',
          description:
              'Toma pedidos a domicilio, comparte GPS en vivo y marca entregas.',
          icon: Icons.two_wheeler,
          color: const Color(0xFF4B2618),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DriverOrdersScreen(isAdmin: widget.isAdmin),
            ),
          ),
        ),
      if (widget.canViewCashClosing)
        _HubOption(
          title: 'Cierre de Caja',
          description:
              'Revisa ventas del día en efectivo y transferencia, y registra el arqueo.',
          icon: Icons.point_of_sale,
          color: const Color(0xFF2E7D4F),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CashClosingScreen()),
          ),
        ),
      if (widget.canViewExpenses)
        _HubOption(
          title: 'Registro de Gastos',
          description:
              'Anota compras de insumos, gas o pagos del día y descuéntalos del cierre.',
          icon: Icons.receipt_long,
          color: Colors.amber.shade800,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ExpensesScreen()),
          ),
        ),
      if (widget.canViewUsers)
        _HubOption(
          title: 'Usuarios y Permisos',
          description:
              'Asigna roles y controla qué pantallas puede ver cada miembro del equipo.',
          icon: Icons.manage_accounts,
          color: Colors.indigo,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const UsersRolesScreen()),
          ),
        ),
      if (widget.canViewAnalytics)
        _HubOption(
          title: 'Estadísticas y Análisis',
          description:
              'Top 10 clientes, platillos más y menos vendidos, horas pico y días fuertes.',
          icon: Icons.insights,
          color: Colors.deepPurple,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AnalyticsScreen()),
          ),
        ),
      if (widget.canManageMenu)
        _HubOption(
          title: 'Gestión de Menú',
          description:
              'Crea nuevos platillos, sube fotos por variante y marca productos agotados.',
          icon: Icons.restaurant_menu,
          color: Colors.purple.shade700,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ProductEditScreen()),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final options = _buildOptions(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF3ECE4),
      appBar: AppBar(
        title: const Text("Panel de Control"),
        centerTitle: true,
        backgroundColor: const Color(0xFFE9E1D9),
        foregroundColor: const Color(0xFF4B2618),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF4B2618)),
        titleTextStyle: const TextStyle(
          color: Color(0xFF4B2618),
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$_greeting${_fullName.isNotEmpty ? ', $_fullName' : ''}',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF4B2618),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFC25229).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color:
                              const Color(0xFFC25229).withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        _roleLabel,
                        style: const TextStyle(
                          color: Color(0xFFC25229),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 28),
              if (options.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Text(
                      'No tienes accesos operativos asignados.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF6E574F)),
                    ),
                  ),
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 600;
                    return GridView.count(
                      crossAxisCount: isWide ? 2 : 1,
                      childAspectRatio: isWide ? 3.0 : 2.6,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      children:
                          options.map((o) => _HubCard(option: o)).toList(),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HubOption {
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _HubOption({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}

class _HubCard extends StatelessWidget {
  final _HubOption option;

  const _HubCard({required this.option});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFFAF6F1),
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE2D8CE)),
      ),
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: option.onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: option.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Icon(option.icon, color: option.color, size: 34),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      option.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF4B2618),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      option.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF6E574F),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF8C6D62)),
            ],
          ),
        ),
      ),
    );
  }
}
