import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/reward_tier.dart';
import '../../../core/services/order_alert_service.dart';
import '../../../core/widgets/alert_settings_sheet.dart';
import '../../../core/widgets/app_update_card.dart';
import '../../../core/utils/formatters.dart';
import '../../orders/presentation/order_tracking_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  Map<String, dynamic>? _profileData;
  String? _userEmail;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    _userEmail = user.email;

    try {
      final data = await _supabase
          .from('profiles')
          .select('full_name, phone, role, points')
          .eq('id', user.id)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _profileData = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar perfil: $e')),
        );
      }
    }
  }

  Future<void> _signOut() async {
    await _supabase.auth.signOut();
    if (mounted) Navigator.pop(context, true);
  }

  String _alertStatusLabel(OrderAlertService service) {
    if (!service.soundEnabled) return 'Silenciado';

    final mode = switch (service.alertMode) {
      'voz' => 'Solo Voz',
      'tono' => 'Solo Tono',
      _ => 'Tono + Voz',
    };

    final name = service.selectedVoiceName;
    String? voice;
    if (name != null) {
      for (final item in service.availableVoices) {
        if (item['name']?.toLowerCase() == name.toLowerCase()) {
          voice = item['label'];
          break;
        }
      }
    }
    voice ??= name;

    if (voice == null || voice.isEmpty) return mode;
    return '$mode · $voice';
  }

  String _deliveryTypeLabel(dynamic type) {
    switch (type?.toString()) {
      case 'local':
        return 'En local';
      case 'para_llevar':
        return 'Para llevar';
      case 'domicilio':
        return 'Domicilio';
      default:
        return type?.toString() ?? 'No especificada';
    }
  }

  String _formatOrderDate(dynamic createdAt) {
    final raw = createdAt?.toString();
    if (raw == null) return 'Fecha desconocida';

    final date = DateTime.tryParse(raw)?.toLocal();
    if (date == null) return 'Fecha desconocida';

    return Formatters.dateTime(date);
  }

  void _showMyOrdersModal() {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(ctx).size.height * 0.7,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Historial de Pedidos',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Divider(),
              Expanded(
                child: FutureBuilder(
                  future: _supabase
                      .from('orders')
                      .select('id, total, status, delivery_type, created_at')
                      .eq('customer_id', user.id)
                      .order('id', ascending: false),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final orders = snapshot.data ?? [];
                    if (orders.isEmpty) {
                      return const Center(child: Text('No tienes pedidos aún.'));
                    }
                    return ListView.separated(
                      itemCount: orders.length,
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (context, index) {
                        final ord = orders[index];
                        final id = ord['id'] as int;
                        final total = (ord['total'] as num?) ?? 0;
                        final st = ord['status'];
                        final type = _deliveryTypeLabel(ord['delivery_type']);
                        final date = _formatOrderDate(ord['created_at']);

                        return ListTile(
                          isThreeLine: true,
                          leading: const Icon(Icons.delivery_dining, color: AppColors.secondary),
                          title: Text('Orden #$id', style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(
                            '$date · $type\nTotal: ${Formatters.currency(total)} · Estado: ${st.toString().toUpperCase()}',
                          ),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
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

  int _historyDelta(Map<String, dynamic> entry) {
    final raw = entry['points'] ??
        entry['points_change'] ??
        entry['points_delta'] ??
        entry['amount'];
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  String _historyDescription(Map<String, dynamic> entry) {
    final raw = entry['description'] ??
        entry['reason'] ??
        entry['concept'] ??
        entry['type'];
    final text = raw?.toString().trim();
    if (text == null || text.isEmpty) return 'Movimiento de puntos';
    return text;
  }

  void _showRewardsModal() {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    final points = (_profileData?['points'] as num?)?.toInt() ?? 0;
    final unlocked = RewardTier.bestAvailableFor(points);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(ctx).size.height * 0.85,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      "Recompensas K'OTEMAL",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              Text(
                unlocked == null
                    ? '$points puntos disponibles · Aún no desbloqueas descuentos'
                    : '$points puntos disponibles · ${Formatters.currency(unlocked.discountAmount)} de descuento desbloqueado',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 8),
              for (final tier in kRewardTiers)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    points >= tier.pointsRequired
                        ? Icons.check_circle
                        : Icons.lock_outline,
                    color: points >= tier.pointsRequired
                        ? Colors.green
                        : Colors.grey,
                  ),
                  title: Text(
                    tier.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${tier.pointsRequired} pts · compra mínima ${Formatters.currency(tier.minFoodSubtotal)}',
                  ),
                ),
              const Divider(),
              const Text(
                'Historial reciente',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: FutureBuilder(
                  future: _supabase
                      .from('rewards_history')
                      .select()
                      .eq('customer_id', user.id)
                      .order('created_at', ascending: false)
                      .limit(20),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    }
                    if (snapshot.hasError) {
                      return const Center(
                        child: Text(
                          'No se pudo cargar el historial de movimientos.',
                        ),
                      );
                    }
                    final history = snapshot.data ?? [];
                    if (history.isEmpty) {
                      return const Center(
                        child: Text('Aún no tienes movimientos de puntos.'),
                      );
                    }
                    return ListView.separated(
                      itemCount: history.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final entry = history[index];
                        final delta = _historyDelta(entry);
                        final isPositive = delta >= 0;

                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            isPositive
                                ? Icons.add_circle_outline
                                : Icons.remove_circle_outline,
                            color: isPositive ? Colors.green : Colors.red,
                          ),
                          title: Text(_historyDescription(entry)),
                          subtitle: Text(
                            _formatOrderDate(entry['created_at']),
                          ),
                          trailing: Text(
                            isPositive ? '+$delta pts' : '$delta pts',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color:
                                  isPositive ? Colors.green : Colors.red,
                            ),
                          ),
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mi Perfil')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final name = _profileData?['full_name'] ?? 'Usuario K\'OTEMAL';
    final phone = _profileData?['phone'] ?? 'Sin número';
    final role = (_profileData?['role'] ?? 'cliente').toString().toUpperCase();
    final points = (_profileData?['points'] as num?)?.toInt() ?? 0;
    final unlockedReward = RewardTier.bestAvailableFor(points);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Información de Perfil',
          style: TextStyle(color: AppColors.primary),
        ),
        backgroundColor: AppColors.logoBackground,
        foregroundColor: AppColors.primary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Center(
              child: CircleAvatar(
                radius: 45,
                backgroundColor: AppColors.surface,
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : 'U',
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: AppColors.secondary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              name,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            Text(
              _userEmail ?? '',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 10),
            Chip(
              label: Text(
                'ROL: $role',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: AppColors.primary,
                ),
              ),
              backgroundColor: AppColors.surface,
              side: const BorderSide(color: AppColors.border),
            ),
            const SizedBox(height: 20),

            Card(
              color: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
                side: const BorderSide(color: AppColors.border),
              ),
              child: ListTile(
                leading: const Icon(Icons.stars, color: Colors.amber, size: 36),
                title: const Text(
                  'Puntos K\'OTEMAL',
                  style: TextStyle(color: AppColors.primary),
                ),
                subtitle: Text(
                  unlockedReward == null
                      ? '$points puntos acumulados · Aún no desbloqueas descuentos'
                      : '$points puntos acumulados · ${Formatters.currency(unlockedReward.discountAmount)} de descuento desbloqueado',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.primary),
                onTap: _showRewardsModal,
              ),
            ),
            const SizedBox(height: 10),

            Card(
              color: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
                side: const BorderSide(color: AppColors.border),
              ),
              child: ListTile(
                leading: const Icon(Icons.phone, color: AppColors.secondary),
                title: const Text(
                  'Teléfono',
                  style: TextStyle(color: AppColors.primary),
                ),
                subtitle: Text(
                  phone,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ),
            const SizedBox(height: 10),

            Card(
              color: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
                side: const BorderSide(color: AppColors.border),
              ),
              child: ListTile(
                leading: const Icon(Icons.receipt_long, color: AppColors.secondary),
                title: const Text(
                  'Mis Pedidos',
                  style: TextStyle(color: AppColors.primary),
                ),
                subtitle: const Text(
                  'Consultar estado y ver ruta en el mapa',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.primary),
                onTap: _showMyOrdersModal,
              ),
            ),
            const SizedBox(height: 10),

            Card(
              color: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
                side: const BorderSide(color: AppColors.border),
              ),
              child: ListenableBuilder(
                listenable: OrderAlertService.instance,
                builder: (context, _) {
                  final service = OrderAlertService.instance;
                  return ListTile(
                    leading: const Icon(
                      Icons.notifications_active_outlined,
                      color: AppColors.secondary,
                    ),
                    title: const Text(
                      'Alertas y Sonidos',
                      style: TextStyle(color: AppColors.primary),
                    ),
                    subtitle: Text(
                      _alertStatusLabel(service),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.primary),
                    onTap: () => showAlertSettingsSheet(context),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),

            // Tarjeta de actualización, completamente oculta en la Web
            if (!kIsWeb) ...[
              const AppUpdateCard(
                backgroundColor: AppColors.surface,
                accentColor: AppColors.secondary,
              ),
              const SizedBox(height: 20),
            ],

            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.secondary,
                  side: const BorderSide(color: AppColors.secondary),
                ),
                onPressed: _signOut,
                icon: const Icon(Icons.logout),
                label: const Text('Cerrar Sesión'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}