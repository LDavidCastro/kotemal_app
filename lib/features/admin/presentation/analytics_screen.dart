import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/formatters.dart';

/// Pantalla de estadísticas y análisis operativo del restaurante.
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final _supabase = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  String _range = 'Últimos 7 días';

  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _profiles = [];
  List<Map<String, dynamic>> _products = [];

  static const _rangeOptions = [
    'Últimos 7 días',
    'Últimos 30 días',
    'Este Mes',
    'Todo el historial',
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  DateTimeRange? _dateRangeFor(String range) {
    final now = DateTime.now();
    switch (range) {
      case 'Últimos 7 días':
        return DateTimeRange(
          start: DateTime(now.year, now.month, now.day - 6),
          end: DateTime(now.year, now.month, now.day, 23, 59, 59),
        );
      case 'Últimos 30 días':
        return DateTimeRange(
          start: DateTime(now.year, now.month, now.day - 29),
          end: DateTime(now.year, now.month, now.day, 23, 59, 59),
        );
      case 'Este Mes':
        return DateTimeRange(
          start: DateTime(now.year, now.month, 1),
          end: DateTime(now.year, now.month, now.day, 23, 59, 59),
        );
      case 'Todo el historial':
        return null;
    }
    return null;
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final range = _dateRangeFor(_range);
      final startIso = range?.start.toUtc().toIso8601String();
      final endIso = range?.end.toUtc().toIso8601String();

      var ordersQuery = _supabase
          .from('orders')
          .select(
            'id, customer_id, customer_phone, total, delivery_type, '
            'payment_method, created_at, '
            'order_items(quantity, unit_price, notes, products(id, name, category))',
          )
          .eq('status', 'entregado');

      if (startIso != null) ordersQuery = ordersQuery.gte('created_at', startIso);
      if (endIso != null) ordersQuery = ordersQuery.lte('created_at', endIso);

      final results = await Future.wait([
        ordersQuery.order('created_at', ascending: false),
        _supabase.from('profiles').select('id, full_name, phone, points'),
        _supabase.from('products').select('id, name, category, is_available'),
      ]);

      if (!mounted) return;
      setState(() {
        _orders = (results[0] as List).cast<Map<String, dynamic>>();
        _profiles = (results[1] as List).cast<Map<String, dynamic>>();
        _products = (results[2] as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  DateTime? _parseLocal(Object? value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString())?.toLocal();
  }

  List<Map<String, dynamic>> get _orderItems {
    final items = <Map<String, dynamic>>[];
    for (final order in _orders) {
      final rawItems = order['order_items'];
      if (rawItems is! List) continue;
      for (final raw in rawItems) {
        if (raw is! Map) continue;
        items.add(Map<String, dynamic>.from(raw));
      }
    }
    return items;
  }

  double get _totalRevenue {
    return _orders.fold(0.0, (sum, o) => sum + ((o['total'] as num?)?.toDouble() ?? 0));
  }

  int get _totalOrders => _orders.length;

  double get _averageTicket => _totalOrders > 0 ? _totalRevenue / _totalOrders : 0;

  Map<String, double> get _channelDistribution {
    final counts = <String, int>{};
    for (final order in _orders) {
      final type = order['delivery_type']?.toString() ?? 'otro';
      counts[type] = (counts[type] ?? 0) + 1;
    }
    if (counts.isEmpty) return {};
    final total = counts.values.fold(0, (a, b) => a + b);
    return counts.map((key, value) => MapEntry(key, value / total));
  }

  double get _recurrentRate {
    if (_orders.isEmpty) return 0;
    final ids = <String?, int>{};
    for (final order in _orders) {
      final key = order['customer_id']?.toString() ?? order['customer_phone']?.toString();
      ids[key] = (ids[key] ?? 0) + 1;
    }
    final recurrents = ids.values.where((c) => c >= 2).length;
    final uniqueCustomers = ids.length;
    return uniqueCustomers > 0 ? recurrents / uniqueCustomers : 0;
  }

  String _customerName(Map<String, dynamic> order) {
    final customerId = order['customer_id']?.toString();
    final phone = order['customer_phone']?.toString();
    if (customerId != null) {
      final profile = _profiles.firstWhere(
        (p) => p['id']?.toString() == customerId,
        orElse: () => <String, dynamic>{},
      );
      final name = profile['full_name']?.toString().trim();
      if (name != null && name.isNotEmpty) return name;
    }
    if (phone != null && phone.isNotEmpty) return phone;
    return 'Invitado';
  }

  List<_CustomerSummary> get _topCustomers {
    final map = <String?, _CustomerSummary>{};
    for (final order in _orders) {
      final key = order['customer_id']?.toString() ?? order['customer_phone']?.toString();
      final existing = map[key];
      final name = _customerName(order);
      final phone = order['customer_phone']?.toString() ?? '';
      final total = (order['total'] as num?)?.toDouble() ?? 0;
      if (existing == null) {
        map[key] = _CustomerSummary(name: name, phone: phone, orders: 1, total: total);
      } else {
        map[key] = existing.copyWith(
          orders: existing.orders + 1,
          total: existing.total + total,
        );
      }
    }
    final list = map.values.toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    return list.take(10).toList();
  }

  List<_ProductSummary> get _productSales {
    final map = <String, _ProductSummary>{};

    // Sumar ventas reales.
    for (final item in _orderItems) {
      final product = item['products'];
      if (product is! Map) continue;
      final id = product['id']?.toString() ?? '';
      final name = product['name']?.toString() ?? 'Producto';
      final category = product['category']?.toString() ?? '';
      final quantity = (item['quantity'] as num?)?.toInt() ?? 1;
      final unitPrice = (item['unit_price'] as num?)?.toDouble() ?? 0;
      final existing = map[id];
      if (existing == null) {
        map[id] = _ProductSummary(
          id: id,
          name: name,
          category: category,
          quantity: quantity,
          revenue: quantity * unitPrice,
        );
      } else {
        map[id] = existing.copyWith(
          quantity: existing.quantity + quantity,
          revenue: existing.revenue + quantity * unitPrice,
        );
      }
    }

    // Incluir productos activos sin ventas para detectar baja rotación.
    for (final product in _products) {
      final id = product['id']?.toString() ?? '';
      if (id.isEmpty || map.containsKey(id)) continue;
      final isAvailable = product['is_available'] as bool? ?? true;
      if (!isAvailable) continue;
      map[id] = _ProductSummary(
        id: id,
        name: product['name']?.toString() ?? 'Producto',
        category: product['category']?.toString() ?? '',
        quantity: 0,
        revenue: 0,
      );
    }

    return map.values.toList();
  }

  List<_ProductSummary> get _top5Products {
    final list = _productSales.where((p) => p.quantity > 0).toList()
      ..sort((a, b) => b.quantity.compareTo(a.quantity));
    return list.take(5).toList();
  }

  List<_ProductSummary> get _bottom5Products {
    final list = _productSales.toList()
      ..sort((a, b) => a.quantity.compareTo(b.quantity));
    return list.take(5).toList();
  }

  Map<int, _HourSummary> get _hourlyDistribution {
    final map = <int, _HourSummary>{};
    for (final order in _orders) {
      final date = _parseLocal(order['created_at']);
      if (date == null) continue;
      final hour = date.hour;
      final total = (order['total'] as num?)?.toDouble() ?? 0;
      map[hour] = _HourSummary(
        hour: hour,
        orders: (map[hour]?.orders ?? 0) + 1,
        revenue: (map[hour]?.revenue ?? 0) + total,
      );
    }
    return map;
  }

  Map<int, _DaySummary> get _dailyDistribution {
    final map = <int, _DaySummary>{};
    for (var i = 1; i <= 7; i++) {
      map[i] = _DaySummary(dayIndex: i, orders: 0, revenue: 0);
    }
    for (final order in _orders) {
      final date = _parseLocal(order['created_at']);
      if (date == null) continue;
      final day = date.weekday;
      final total = (order['total'] as num?)?.toDouble() ?? 0;
      map[day] = _DaySummary(
        dayIndex: day,
        orders: (map[day]?.orders ?? 0) + 1,
        revenue: (map[day]?.revenue ?? 0) + total,
      );
    }
    return map;
  }

  List<_ExtraSummary> get _topExtras {
    final map = <String, int>{};
    for (final item in _orderItems) {
      final notes = item['notes']?.toString() ?? '';
      final upper = notes.toUpperCase();
      const prefix = 'CON EXTRA:';
      final idx = upper.indexOf(prefix);
      if (idx == -1) continue;
      final raw = notes.substring(idx + prefix.length).trim();
      // Tomar solo la parte antes de "->" o "|" para limpiar precios.
      final cleaned = raw
          .split(RegExp(r'[|]'))
          .first
          .replaceAll(RegExp(r'->.*'), '')
          .trim();
      if (cleaned.isNotEmpty) {
        map[cleaned] = (map[cleaned] ?? 0) + ((item['quantity'] as num?)?.toInt() ?? 1);
      }
    }
    final list = map.entries
        .map((e) => _ExtraSummary(name: e.key, count: e.value))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    return list.take(5).toList();
  }

  String _hourLabel(int hour) {
    final suffix = hour >= 12 ? 'PM' : 'AM';
    final display = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$display:00 $suffix';
  }

  String _dayLabel(int index) {
    const days = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];
    return days[index - 1];
  }

  String _channelLabel(String type) {
    switch (type) {
      case 'local':
        return 'En local';
      case 'para_llevar':
        return 'Para llevar';
      case 'domicilio':
        return 'Domicilio';
      default:
        return 'Otro';
    }
  }

  Color _channelColor(String type) {
    switch (type) {
      case 'local':
        return Colors.orange;
      case 'para_llevar':
        return Colors.blue;
      case 'domicilio':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  Widget _medal(int index) {
    if (index == 0) {
      return const Icon(Icons.emoji_events, color: Colors.amber, size: 20);
    }
    if (index == 1) {
      return const Icon(Icons.emoji_events, color: Colors.grey, size: 20);
    }
    if (index == 2) {
      return const Icon(Icons.emoji_events, color: Color(0xFFCD7F32), size: 20);
    }
    return CircleAvatar(
      radius: 10,
      backgroundColor: Colors.grey.shade200,
      child: Text(
        '${index + 1}',
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F9),
      appBar: AppBar(
        title: const Text('Estadísticas y Análisis'),
        backgroundColor: const Color(0xFFF7F7F9),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        titleTextStyle: const TextStyle(
          color: Colors.black87,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _buildContent(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text('Error al cargar estadísticas: $_error', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadData,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final topCustomers = _topCustomers;
    final topProducts = _top5Products;
    final bottomProducts = _bottom5Products;
    final hourly = _hourlyDistribution;
    final daily = _dailyDistribution;
    final extras = _topExtras;
    final channel = _channelDistribution;

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildRangeSelector(),
          const SizedBox(height: 20),
          _buildKpiSection(channel),
          const SizedBox(height: 20),
          _buildSectionTitle('Top 10 Clientes que Más Consumen'),
          const SizedBox(height: 10),
          _buildTopCustomersCard(topCustomers),
          const SizedBox(height: 20),
          _buildSectionTitle('Platillos Más Consumidos'),
          const SizedBox(height: 10),
          _buildProductRankingCard(topProducts, isTop: true),
          const SizedBox(height: 20),
          _buildSectionTitle('Platillos Menos Consumidos'),
          const SizedBox(height: 10),
          _buildProductRankingCard(bottomProducts, isTop: false),
          const SizedBox(height: 20),
          _buildSectionTitle('Horas Pico y Horas Bajas'),
          const SizedBox(height: 10),
          _buildHourlyCard(hourly),
          const SizedBox(height: 20),
          _buildSectionTitle('Rendimiento por Día de la Semana'),
          const SizedBox(height: 10),
          _buildDailyCard(daily),
          const SizedBox(height: 20),
          _buildSectionTitle('Top Extras Más Pedidos'),
          const SizedBox(height: 10),
          _buildExtrasCard(extras),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildRangeSelector() {
    return Card(
      color: Colors.white,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: _rangeOptions.map((range) {
            final selected = range == _range;
            return ChoiceChip(
              label: Text(range),
              selected: selected,
              selectedColor: Colors.deepPurple.shade100,
              backgroundColor: Colors.grey.shade100,
              labelStyle: TextStyle(
                color: selected ? Colors.deepPurple.shade800 : Colors.black87,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: selected ? Colors.deepPurple.shade300 : Colors.transparent,
                ),
              ),
              onSelected: (_) {
                if (_range == range) return;
                setState(() => _range = range);
                _loadData();
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
    );
  }

  Widget _buildKpiSection(Map<String, double> channel) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _KpiCard(
                label: 'Total Vendido',
                value: Formatters.currency(_totalRevenue),
                icon: Icons.attach_money,
                color: Colors.green,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _KpiCard(
                label: 'Órdenes Entregadas',
                value: '$_totalOrders',
                icon: Icons.receipt_long,
                color: Colors.deepPurple,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _KpiCard(
                label: 'Ticket Promedio',
                value: Formatters.currency(_averageTicket),
                icon: Icons.trending_up,
                color: Colors.teal,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _KpiCard(
                label: 'Clientes Recurrentes',
                value: '${(_recurrentRate * 100).toStringAsFixed(0)}%',
                icon: Icons.repeat,
                color: Colors.orange,
              ),
            ),
          ],
        ),
        if (channel.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildChannelDistributionCard(channel),
        ],
      ],
    );
  }

  Widget _buildChannelDistributionCard(Map<String, double> channel) {
    return Card(
      color: Colors.white,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Distribución por Canal',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...channel.entries.map((entry) {
              final percent = entry.value * 100;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(Icons.circle, size: 10, color: _channelColor(entry.key)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _channelLabel(entry.key),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    Text(
                      '${percent.toStringAsFixed(0)}%',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildTopCustomersCard(List<_CustomerSummary> customers) {
    if (customers.isEmpty) {
      return _EmptyCard(message: 'No hay clientes en este período.');
    }

    return Card(
      color: Colors.white,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: customers.asMap().entries.map((entry) {
            final index = entry.key;
            final customer = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  _medal(index),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          customer.name,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        Text(
                          '${customer.orders} pedido${customer.orders == 1 ? '' : 's'}',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    Formatters.currency(customer.total),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildProductRankingCard(List<_ProductSummary> products, {required bool isTop}) {
    if (products.isEmpty) {
      return _EmptyCard(message: 'No hay datos de platillos en este período.');
    }

    final maxQuantity = products.map((p) => p.quantity).fold(0, (a, b) => a > b ? a : b);

    return Card(
      color: Colors.white,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: products.asMap().entries.map((entry) {
            final index = entry.key;
            final product = entry.value;
            final progress = maxQuantity > 0 ? product.quantity / maxQuantity : 0.0;

            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: isTop ? Colors.green.shade50 : Colors.red.shade50,
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isTop ? Colors.green.shade800 : Colors.red.shade700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          product.name,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                      ),
                      Text(
                        '${product.quantity} uds',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isTop ? Colors.green : Colors.red,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: progress.toDouble(),
                      minHeight: 8,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation(
                        isTop ? Colors.green.shade400 : Colors.red.shade300,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Total generado: ${Formatters.currency(product.revenue)}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildHourlyCard(Map<int, _HourSummary> hourly) {
    final sortedHours = hourly.values.toList()
      ..sort((a, b) => a.hour.compareTo(b.hour));

    if (sortedHours.isEmpty) {
      return _EmptyCard(message: 'No hay datos de horarios en este período.');
    }

    final peak = sortedHours.reduce((a, b) => a.orders > b.orders ? a : b);
    final lowest = sortedHours.reduce((a, b) => a.orders < b.orders ? a : b);
    final maxOrders = peak.orders;

    return Card(
      color: Colors.white,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: sortedHours.map((hour) {
            final isPeak = hour.hour == peak.hour;
            final isLowest = hour.hour == lowest.hour && hour.orders < peak.orders;
            final progress = maxOrders > 0 ? hour.orders / maxOrders : 0.0;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 72,
                    child: Text(
                      _hourLabel(hour.hour),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: progress.toDouble(),
                        minHeight: 10,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation(
                          isPeak
                              ? Colors.green.shade500
                              : isLowest
                                  ? Colors.amber.shade500
                                  : Colors.deepPurple.shade200,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${hour.orders}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  if (isPeak) ...[
                    const SizedBox(width: 4),
                    _Badge(text: 'Pico', color: Colors.green),
                  ] else if (isLowest) ...[
                    const SizedBox(width: 4),
                    _Badge(text: 'Bajo', color: Colors.amber.shade700),
                  ],
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildDailyCard(Map<int, _DaySummary> daily) {
    final sortedDays = List<_DaySummary>.generate(
      7,
      (i) => daily[i + 1] ?? _DaySummary(dayIndex: i + 1, orders: 0, revenue: 0),
    );

    if (_orders.isEmpty) {
      return _EmptyCard(message: 'No hay datos por día en este período.');
    }

    final peak = sortedDays.reduce((a, b) => a.orders > b.orders ? a : b);
    final lowest = sortedDays.reduce((a, b) => a.orders < b.orders ? a : b);
    final maxOrders = peak.orders;

    return Card(
      color: Colors.white,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: sortedDays.map((day) {
            final isPeak = day.dayIndex == peak.dayIndex;
            final isLowest = day.dayIndex == lowest.dayIndex && day.orders < peak.orders;
            final progress = maxOrders > 0 ? day.orders / maxOrders : 0.0;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 84,
                    child: Text(
                      _dayLabel(day.dayIndex),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: progress.toDouble(),
                        minHeight: 10,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation(
                          isPeak
                              ? Colors.green.shade500
                              : isLowest
                                  ? Colors.amber.shade500
                                  : Colors.deepPurple.shade200,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${day.orders} ped.',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        Formatters.currency(day.revenue),
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                  if (isPeak) ...[
                    const SizedBox(width: 4),
                    _Badge(text: 'Mejor', color: Colors.green),
                  ] else if (isLowest) ...[
                    const SizedBox(width: 4),
                    _Badge(text: 'Bajo', color: Colors.amber.shade700),
                  ],
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildExtrasCard(List<_ExtraSummary> extras) {
    if (extras.isEmpty) {
      return _EmptyCard(message: 'No hay extras registrados en este período.');
    }

    final maxCount = extras.first.count;

    return Card(
      color: Colors.white,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: extras.asMap().entries.map((entry) {
            final index = entry.key;
            final extra = entry.value;
            final progress = maxCount > 0 ? extra.count / maxCount : 0.0;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: Colors.deepPurple.shade50,
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple.shade800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          extra.name,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: progress.toDouble(),
                            minHeight: 6,
                            backgroundColor: Colors.grey.shade200,
                            valueColor: AlwaysStoppedAnimation(Colors.deepPurple.shade300),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${extra.count}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 10),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String message;

  const _EmptyCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;

  const _Badge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}

class _CustomerSummary {
  final String name;
  final String phone;
  final int orders;
  final double total;

  const _CustomerSummary({
    required this.name,
    required this.phone,
    required this.orders,
    required this.total,
  });

  _CustomerSummary copyWith({int? orders, double? total}) {
    return _CustomerSummary(
      name: name,
      phone: phone,
      orders: orders ?? this.orders,
      total: total ?? this.total,
    );
  }
}

class _ProductSummary {
  final String id;
  final String name;
  final String category;
  final int quantity;
  final double revenue;

  const _ProductSummary({
    required this.id,
    required this.name,
    required this.category,
    required this.quantity,
    required this.revenue,
  });

  _ProductSummary copyWith({int? quantity, double? revenue}) {
    return _ProductSummary(
      id: id,
      name: name,
      category: category,
      quantity: quantity ?? this.quantity,
      revenue: revenue ?? this.revenue,
    );
  }
}

class _HourSummary {
  final int hour;
  final int orders;
  final double revenue;

  const _HourSummary({
    required this.hour,
    required this.orders,
    required this.revenue,
  });
}

class _DaySummary {
  final int dayIndex;
  final int orders;
  final double revenue;

  const _DaySummary({
    required this.dayIndex,
    required this.orders,
    required this.revenue,
  });
}

class _ExtraSummary {
  final String name;
  final int count;

  const _ExtraSummary({required this.name, required this.count});
}
