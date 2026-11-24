import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/formatters.dart';

const _ordersWithItemsSelect =
    'id, total, payment_method, paid_at, delivery_type, customer_phone, '
    'order_items(quantity, unit_price, notes, products(name))';

String _paymentLabel(Object? method) {
  switch (method?.toString()) {
    case 'efectivo':
      return 'Efectivo';
    case 'transferencia':
      return 'Transferencia';
    default:
      return method?.toString() ?? 'Sin método';
  }
}

String _deliveryLabel(Object? type) {
  switch (type?.toString()) {
    case 'local':
      return 'En local';
    case 'para_llevar':
      return 'Para llevar';
    case 'domicilio':
      return 'Domicilio';
    default:
      return 'Sin modalidad';
  }
}

DateTime? _parseDate(Object? value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

DateTime _closureCutoff(Map<String, dynamic> closure) {
  return _parseDate(
        closure['closed_at'] ?? closure['created_at'] ?? closure['closure_date'],
      ) ??
      DateTime.now();
}

String _fileDate(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}$month$day';
}

String _shortDate(DateTime value) => Formatters.dateTime(value).split(' ').first;

Future<List<Map<String, dynamic>>> _fetchOrdersWithItems(
  List<Object?> orderIds,
) async {
  if (orderIds.isEmpty) return [];

  final data = await Supabase.instance.client
      .from('orders')
      .select(_ordersWithItemsSelect)
      .inFilter('id', orderIds)
      .order('paid_at', ascending: true);

  return (data as List).cast<Map<String, dynamic>>();
}

String _orderDishes(Map<String, dynamic> order) {
  final items = order['order_items'];
  if (items is! List || items.isEmpty) return 'Sin platillos';

  final dishes = <String>[];
  for (final raw in items) {
    final item = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final quantity = (item['quantity'] as num?)?.toInt() ?? 1;
    final product = item['products'];
    final productName = product is Map
        ? (product['name']?.toString() ?? 'Producto')
        : 'Producto';
    final notes = item['notes']?.toString().trim() ?? '';

    dishes.add(
      '${quantity}x $productName${notes.isEmpty ? '' : ' ($notes)'}',
    );
  }

  return dishes.join(' | ');
}

String _csvCell(Object? value) {
  final text = value?.toString() ?? '';
  if (text.contains(RegExp(r'[",\n\r]'))) {
    return '"${text.replaceAll('"', '""')}"';
  }
  return text;
}

String _buildCsv(
  List<Map<String, dynamic>> orders,
  _ReportStats stats,
) {
  final buffer = StringBuffer('\uFEFF');
  buffer.writeln(
    'Orden,Fecha_Hora,Modalidad,Telefono,Metodo_Pago,Total_Q,Platillos',
  );

  for (final order in orders) {
    final paidAt = _parseDate(order['paid_at']);
    final total = (order['total'] as num?)?.toDouble() ?? 0;

    buffer.writeln(
      [
        '#${order['id']}',
        paidAt != null ? Formatters.dateTime(paidAt) : '',
        _deliveryLabel(order['delivery_type']),
        order['customer_phone']?.toString() ?? '',
        _paymentLabel(order['payment_method']),
        total.toStringAsFixed(2),
        _orderDishes(order),
      ].map(_csvCell).join(','),
    );
  }

  buffer.writeln('');
  buffer.writeln(
    [
      'TOTAL_EFECTIVO',
      '',
      '',
      '',
      '',
      stats.cash.toStringAsFixed(2),
      '',
    ].map(_csvCell).join(','),
  );
  buffer.writeln(
    [
      'TOTAL_TRANSFERENCIA',
      '',
      '',
      '',
      '',
      stats.transfer.toStringAsFixed(2),
      '',
    ].map(_csvCell).join(','),
  );
  buffer.writeln(
    [
      'TOTAL_GENERAL',
      '',
      '',
      '',
      '',
      stats.revenue.toStringAsFixed(2),
      '',
    ].map(_csvCell).join(','),
  );

  return buffer.toString();
}

Future<void> _shareWhatsAppSummary({
  required List<Map<String, dynamic>> orders,
  required DateTime cutoff,
  Object? closureId,
  String? notes,
  _ReportStats? stats,
}) async {
  final report = stats ?? _ReportStats.fromOrders(orders);

  final buffer = StringBuffer()
    ..writeln('*📊 REPORTE DE CIERRE DE CAJA - K\'OTEMAL*')
    ..writeln()
    ..writeln('📅 Fecha/hora del corte: ${Formatters.dateTime(cutoff)}')
    ..writeln(
      closureId != null ? '🆔 Cierre: #$closureId' : '🆔 Corte en curso',
    )
    ..writeln()
    ..writeln('🧾 Total de órdenes cerradas: ${report.totalOrders}')
    ..writeln()
    ..writeln('*Métodos de pago*')
    ..writeln('💵 Efectivo: ${Formatters.currency(report.cash)}')
    ..writeln('🏦 Transferencia: ${Formatters.currency(report.transfer)}')
    ..writeln()
    ..writeln('*Modalidades*')
    ..writeln(
      '🍽️ En local: ${report.localCount} '
      '(${Formatters.currency(report.localTotal)})',
    )
    ..writeln(
      '🥡 Para llevar: ${report.takeawayCount} '
      '(${Formatters.currency(report.takeawayTotal)})',
    )
    ..writeln(
      '🛵 Domicilio: ${report.deliveryCount} '
      '(${Formatters.currency(report.deliveryTotal)})',
    )
    ..writeln()
    ..writeln('*💰 TOTAL RECAUDADO: ${Formatters.currency(report.revenue)}*');

  final trimmedNotes = notes?.trim() ?? '';
  if (trimmedNotes.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('📝 Notas del cierre: $trimmedNotes');
  }

  final uri = Uri.parse(
    'https://wa.me/?text=${Uri.encodeComponent(buffer.toString())}',
  );
  final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!launched) {
    throw Exception('No se pudo abrir WhatsApp.');
  }
}

Future<void> _exportExcelCsv({
  required List<Map<String, dynamic>> orders,
  required DateTime cutoff,
  _ReportStats? stats,
}) async {
  final report = stats ?? _ReportStats.fromOrders(orders);
  final csv = _buildCsv(orders, report);
  final fileName = 'cierre_kotemal_${_fileDate(cutoff)}.csv';

  final file = XFile.fromData(
    Uint8List.fromList(utf8.encode(csv)),
    mimeType: 'text/csv',
    name: fileName,
  );

  await SharePlus.instance.share(
    ShareParams(
      files: [file],
      fileNameOverrides: [fileName],
      subject: 'Cierre de caja K\'OTEMAL',
      title: 'Detalle del cierre de caja',
      text: 'Detalle del cierre de caja K\'OTEMAL.',
    ),
  );
}

class CashClosingScreen extends StatefulWidget {
  const CashClosingScreen({super.key});

  @override
  State<CashClosingScreen> createState() => _CashClosingScreenState();
}

class _CashClosingScreenState extends State<CashClosingScreen> {
  final _supabase = Supabase.instance.client;

  bool _loading = true;
  bool _closing = false;
  String? _error;
  List<Map<String, dynamic>> _paidOrders = [];
  double _cashTotal = 0;
  double _transferTotal = 0;
  double _revenueTotal = 0;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  String get _dateOnly {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final dayOfMonth = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$dayOfMonth';
  }

  Future<void> _loadSummary() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await _supabase
          .from('orders')
          .select('id, total, payment_method, paid_at, delivery_type')
          .eq('payment_status', 'pagado')
          .isFilter('closure_id', null)
          .order('paid_at', ascending: false);

      final orders = (data as List).cast<Map<String, dynamic>>();

      var cash = 0.0;
      var transfer = 0.0;
      for (final order in orders) {
        final total = (order['total'] ?? 0).toDouble();
        final method = order['payment_method'];
        if (method == 'efectivo') {
          cash += total;
        } else if (method == 'transferencia') {
          transfer += total;
        }
      }

      if (!mounted) return;
      setState(() {
        _paidOrders = orders;
        _cashTotal = cash;
        _transferTotal = transfer;
        _revenueTotal = cash + transfer;
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

  Future<void> _runReportAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo generar el reporte: $e')),
      );
    }
  }

  Future<void> _shareActiveSummary() async {
    if (_paidOrders.isEmpty) return;

    await _runReportAction(
      () => _shareWhatsAppSummary(
        orders: _paidOrders,
        cutoff: DateTime.now(),
      ),
    );
  }

  Future<void> _exportActiveCsv() async {
    if (_paidOrders.isEmpty) return;

    await _runReportAction(() async {
      final orders = await _fetchOrdersWithItems(
        _paidOrders.map((order) => order['id']).toList(),
      );
      await _exportExcelCsv(orders: orders, cutoff: DateTime.now());
    });
  }

  Future<void> _closeCashRegister() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes iniciar sesión como administrador.')),
      );
      return;
    }

    if (_paidOrders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay órdenes abiertas para cerrar.')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar Caja'),
        content: Text(
          'Se registrará un cierre con ${_paidOrders.length} orden(es) pagada(s) '
          'por un total de ${Formatters.currency(_revenueTotal)}.\n\n'
          'Efectivo: ${Formatters.currency(_cashTotal)}\n'
          'Transferencia: ${Formatters.currency(_transferTotal)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepOrange,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cerrar Caja'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final closedOrders = List<Map<String, dynamic>>.from(_paidOrders);
    final closedOrderIds = closedOrders.map((order) => order['id']).toList();
    final closedRevenue = _revenueTotal;
    const closureNotes = 'Cierre generado desde la aplicación.';

    setState(() => _closing = true);

    try {
      final inserted = await _supabase
          .from('cash_register_closures')
          .insert({
            'closed_by': user.id,
            'closure_date': _dateOnly,
            'total_orders': closedOrders.length,
            'total_cash': _cashTotal,
            'total_transfer': _transferTotal,
            'total_revenue': _revenueTotal,
            'notes': closureNotes,
          })
          .select('id')
          .single();

      final newClosureId = inserted['id'];

      if (closedOrderIds.isNotEmpty) {
        await _supabase
            .from('orders')
            .update({'closure_id': newClosureId})
            .inFilter('id', closedOrderIds);
      }

      if (!mounted) return;
      setState(() => _closing = false);
      await _loadSummary();
      if (!mounted) return;

      final action = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Caja cerrada'),
          content: Text(
            'Se cerró la caja con ${closedOrders.length} orden(es) '
            'por ${Formatters.currency(closedRevenue)}.\n\n'
            '¿Qué deseas hacer ahora?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'history'),
              child: const Text('Ver historial'),
            ),
            TextButton.icon(
              onPressed: () => Navigator.pop(ctx, 'excel'),
              icon: const Icon(Icons.table_view, size: 18),
              label: const Text('Excel'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, 'whatsapp'),
              icon: const Icon(Icons.chat, size: 18),
              label: const Text('WhatsApp'),
            ),
          ],
        ),
      );

      if (!mounted || action == null) return;

      if (action == 'whatsapp') {
        await _runReportAction(
          () => _shareWhatsAppSummary(
            orders: closedOrders,
            cutoff: DateTime.now(),
            closureId: newClosureId,
            notes: closureNotes,
          ),
        );
      } else if (action == 'excel') {
        await _runReportAction(() async {
          final orders = await _fetchOrdersWithItems(closedOrderIds);
          await _exportExcelCsv(orders: orders, cutoff: DateTime.now());
        });
      } else if (action == 'history') {
        await _openHistory();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _closing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cerrar la caja: $e')),
      );
    }
  }

  Future<void> _openHistory() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const _ClosureHistoryScreen(),
      ),
    );
    if (!mounted) return;
    await _loadSummary();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cierre de Caja'),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Historial de Cierres',
            onPressed: _openHistory,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _loading ? null : _loadSummary,
          ),
        ],
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
            Text('Error al cargar el resumen: $_error', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadSummary,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Caja activa',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                title: 'Efectivo',
                amount: _cashTotal,
                icon: Icons.payments,
                color: Colors.green,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryCard(
                title: 'Transferencia',
                amount: _transferTotal,
                icon: Icons.account_balance,
                color: Colors.blue,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          color: Colors.deepOrange.shade50,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.deepOrange.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total de la caja', style: TextStyle(fontSize: 16)),
                    SizedBox(height: 4),
                    Text(
                      'Órdenes abiertas',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      Formatters.currency(_revenueTotal),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepOrange,
                      ),
                    ),
                    Text(
                      '${_paidOrders.length} orden(es)',
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        if (_paidOrders.isNotEmpty)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _closing ? null : _closeCashRegister,
              icon: _closing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.lock_clock),
              label: Text(_closing ? 'Cerrando...' : 'Cerrar Caja'),
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.green.shade700,
                  side: BorderSide(color: Colors.green.shade400),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: _paidOrders.isEmpty ? null : _shareActiveSummary,
                icon: const Icon(Icons.chat),
                label: const Text('Resumen WhatsApp'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.teal.shade700,
                  side: BorderSide(color: Colors.teal.shade400),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: _paidOrders.isEmpty ? null : _exportActiveCsv,
                icon: const Icon(Icons.table_view),
                label: const Text('Detalle Excel'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Text(
          'Órdenes en caja activa',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (_paidOrders.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'No hay órdenes pendientes de cierre.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          )
        else
          ..._paidOrders.map(_buildOrderTile),
      ],
    );
  }

  Widget _buildOrderTile(Map<String, dynamic> order) {
    final id = order['id'];
    final total = (order['total'] ?? 0).toDouble();
    final method = order['payment_method'];
    final paidAt = _parseDate(order['paid_at']);
    final isCash = method == 'efectivo';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isCash ? Colors.green.shade100 : Colors.blue.shade100,
          child: Icon(
            isCash ? Icons.payments : Icons.account_balance,
            color: isCash ? Colors.green : Colors.blue,
          ),
        ),
        title: Text('Orden #$id'),
        subtitle: Text(
          '${_paymentLabel(method)} · ${_deliveryLabel(order['delivery_type'])}'
          '${paidAt != null ? ' · ${Formatters.dateTime(paidAt)}' : ''}',
        ),
        trailing: Text(
          Formatters.currency(total),
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final double amount;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.title,
    required this.amount,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontSize: 13, color: Colors.black54)),
            const SizedBox(height: 4),
            Text(
              Formatters.currency(amount),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportStats {
  const _ReportStats({
    required this.totalOrders,
    required this.cash,
    required this.transfer,
    required this.localCount,
    required this.localTotal,
    required this.takeawayCount,
    required this.takeawayTotal,
    required this.deliveryCount,
    required this.deliveryTotal,
  });

  final int totalOrders;
  final double cash;
  final double transfer;
  final int localCount;
  final double localTotal;
  final int takeawayCount;
  final double takeawayTotal;
  final int deliveryCount;
  final double deliveryTotal;

  double get revenue => cash + transfer;

  factory _ReportStats.fromOrders(List<Map<String, dynamic>> orders) {
    var cash = 0.0;
    var transfer = 0.0;
    var localCount = 0;
    var localTotal = 0.0;
    var takeawayCount = 0;
    var takeawayTotal = 0.0;
    var deliveryCount = 0;
    var deliveryTotal = 0.0;

    for (final order in orders) {
      final total = (order['total'] as num?)?.toDouble() ?? 0;
      final method = order['payment_method']?.toString();
      final deliveryType = order['delivery_type']?.toString();

      if (method == 'efectivo') {
        cash += total;
      } else if (method == 'transferencia') {
        transfer += total;
      }

      if (deliveryType == 'local') {
        localCount++;
        localTotal += total;
      } else if (deliveryType == 'para_llevar') {
        takeawayCount++;
        takeawayTotal += total;
      } else if (deliveryType == 'domicilio') {
        deliveryCount++;
        deliveryTotal += total;
      }
    }

    return _ReportStats(
      totalOrders: orders.length,
      cash: cash,
      transfer: transfer,
      localCount: localCount,
      localTotal: localTotal,
      takeawayCount: takeawayCount,
      takeawayTotal: takeawayTotal,
      deliveryCount: deliveryCount,
      deliveryTotal: deliveryTotal,
    );
  }

  factory _ReportStats.fromClosure(Map<String, dynamic> closure) {
    return _ReportStats(
      totalOrders: (closure['total_orders'] as num?)?.toInt() ?? 0,
      cash: (closure['total_cash'] as num?)?.toDouble() ?? 0,
      transfer: (closure['total_transfer'] as num?)?.toDouble() ?? 0,
      localCount: 0,
      localTotal: 0,
      takeawayCount: 0,
      takeawayTotal: 0,
      deliveryCount: 0,
      deliveryTotal: 0,
    );
  }
}

class _HistoryTotals {
  const _HistoryTotals({
    required this.closures,
    required this.orders,
    required this.cash,
    required this.transfer,
    required this.revenue,
  });

  final int closures;
  final int orders;
  final double cash;
  final double transfer;
  final double revenue;

  factory _HistoryTotals.fromClosures(List<Map<String, dynamic>> closures) {
    var orders = 0;
    var cash = 0.0;
    var transfer = 0.0;
    var revenue = 0.0;

    for (final closure in closures) {
      orders += (closure['total_orders'] as num?)?.toInt() ?? 0;
      cash += (closure['total_cash'] as num?)?.toDouble() ?? 0;
      transfer += (closure['total_transfer'] as num?)?.toDouble() ?? 0;
      revenue += (closure['total_revenue'] as num?)?.toDouble() ?? 0;
    }

    return _HistoryTotals(
      closures: closures.length,
      orders: orders,
      cash: cash,
      transfer: transfer,
      revenue: revenue,
    );
  }
}

class _ClosureHistoryScreen extends StatefulWidget {
  const _ClosureHistoryScreen();

  @override
  State<_ClosureHistoryScreen> createState() => _ClosureHistoryScreenState();
}

class _ClosureHistoryScreenState extends State<_ClosureHistoryScreen> {
  final _supabase = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _closures = [];

  @override
  void initState() {
    super.initState();
    _loadClosures();
  }

  Future<void> _loadClosures() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await _supabase
          .from('cash_register_closures')
          .select()
          .order('closure_date', ascending: false)
          .order('id', ascending: false);

      if (!mounted) return;
      setState(() {
        _closures = (data as List).cast<Map<String, dynamic>>();
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

  void _reload() {
    _loadClosures();
  }

  Future<void> _runReportAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo generar el reporte: $e')),
      );
    }
  }

  Future<void> _shareAllHistoryWhatsApp() async {
    if (_closures.isEmpty) return;

    await _runReportAction(() async {
      final totals = _HistoryTotals.fromClosures(_closures);

      DateTime? oldest;
      DateTime? newest;
      for (final closure in _closures) {
        final date = _parseDate(closure['closure_date']);
        if (date == null) continue;
        if (oldest == null || date.isBefore(oldest)) oldest = date;
        if (newest == null || date.isAfter(newest)) newest = date;
      }

      final rangeLabel = oldest != null && newest != null
          ? '${_shortDate(oldest)} al ${_shortDate(newest)}'
          : 'Sin fechas registradas';

      final buffer = StringBuffer()
        ..writeln('*📊 HISTORIAL CONSOLIDADO DE CAJA - K\'OTEMAL*')
        ..writeln()
        ..writeln('📅 Rango de fechas: $rangeLabel')
        ..writeln(
          '🧾 Total de cierres: ${totals.closures} | '
          'Total de órdenes: ${totals.orders}',
        )
        ..writeln()
        ..writeln('💵 Efectivo acumulado: ${Formatters.currency(totals.cash)}')
        ..writeln(
          '🏦 Transferencia acumulada: ${Formatters.currency(totals.transfer)}',
        )
        ..writeln()
        ..writeln(
          '*💰 TOTAL GENERAL RECAUDADO: ${Formatters.currency(totals.revenue)}*',
        )
        ..writeln()
        ..writeln('*Desglose por corte:*');

      for (final closure in _closures) {
        final date = _parseDate(closure['closure_date']);
        final dateLabel = date != null
            ? _shortDate(date)
            : (closure['closure_date']?.toString() ?? 'Sin fecha');
        final orders = (closure['total_orders'] as num?)?.toInt() ?? 0;
        final total = (closure['total_revenue'] as num?)?.toDouble() ?? 0;

        buffer.writeln(
          '• Cierre #${closure['id']} ($dateLabel): '
          '$orders órd. - ${Formatters.currency(total)}',
        );
      }

      final uri = Uri.parse(
        'https://wa.me/?text=${Uri.encodeComponent(buffer.toString())}',
      );
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw Exception('No se pudo abrir WhatsApp.');
      }
    });
  }

  Future<void> _exportAllHistoryExcelCsv() async {
    if (_closures.isEmpty) return;

    await _runReportAction(() async {
      final data = await _supabase
          .from('orders')
          .select(
            'id, closure_id, created_at, delivery_type, customer_phone, '
            'payment_method, total, '
            'order_items(quantity, unit_price, notes, products(name))',
          )
          .not('closure_id', 'is', null)
          .order('closure_id', ascending: true)
          .order('id', ascending: true);

      final orders = (data as List).cast<Map<String, dynamic>>();
      final totals = _HistoryTotals.fromClosures(_closures);

      final buffer = StringBuffer('\uFEFF');
      buffer.writeln(
        'Cierre_ID,Fecha_Cierre,Total_Ordenes,Efectivo_Q,'
        'Transferencia_Q,Total_Q,Notas',
      );

      for (final closure in _closures) {
        final date = _parseDate(closure['closure_date']);
        buffer.writeln(
          [
            closure['id'],
            date != null
                ? _shortDate(date)
                : (closure['closure_date']?.toString() ?? ''),
            (closure['total_orders'] as num?)?.toInt() ?? 0,
            ((closure['total_cash'] as num?)?.toDouble() ?? 0)
                .toStringAsFixed(2),
            ((closure['total_transfer'] as num?)?.toDouble() ?? 0)
                .toStringAsFixed(2),
            ((closure['total_revenue'] as num?)?.toDouble() ?? 0)
                .toStringAsFixed(2),
            closure['notes']?.toString() ?? '',
          ].map(_csvCell).join(','),
        );
      }

      buffer.writeln(
        [
          'TOTAL_ACUMULADO',
          '',
          totals.orders,
          totals.cash.toStringAsFixed(2),
          totals.transfer.toStringAsFixed(2),
          totals.revenue.toStringAsFixed(2),
          '',
        ].map(_csvCell).join(','),
      );
      buffer.writeln();

      buffer.writeln(
        'Cierre_ID,Orden,Fecha_Hora,Modalidad,Telefono,Metodo_Pago,'
        'Total_Q,Platillos',
      );

      for (final order in orders) {
        final createdAt = _parseDate(order['created_at']);
        final total = (order['total'] as num?)?.toDouble() ?? 0;

        buffer.writeln(
          [
            order['closure_id'],
            '#${order['id']}',
            createdAt != null ? Formatters.dateTime(createdAt) : '',
            _deliveryLabel(order['delivery_type']),
            order['customer_phone']?.toString() ?? '',
            _paymentLabel(order['payment_method']),
            total.toStringAsFixed(2),
            _orderDishes(order),
          ].map(_csvCell).join(','),
        );
      }

      final fileName =
          'historial_cierres_kotemal_${_fileDate(DateTime.now())}.csv';
      final file = XFile.fromData(
        Uint8List.fromList(utf8.encode(buffer.toString())),
        mimeType: 'text/csv',
        name: fileName,
      );

      await SharePlus.instance.share(
        ShareParams(
          files: [file],
          fileNameOverrides: [fileName],
          subject: 'Historial consolidado de caja K\'OTEMAL',
          title: 'Historial consolidado de caja',
          text: 'Historial consolidado de cierres de caja K\'OTEMAL.',
        ),
      );
    });
  }

  Future<void> _openClosureDetail(Map<String, dynamic> closure) async {
    final reopened = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _ClosureDetailView(closure: closure),
      ),
    );

    if (!mounted) return;
    if (reopened == true) _reload();
  }

  Future<void> _reopenClosure(Map<String, dynamic> closure) async {
    final closureId = closure['id'];

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reabrir cierre'),
        content: const Text(
          '¿Reabrir este cierre? Las órdenes volverán a la caja activa '
          'para que puedas agregar pedidos de última hora.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepOrange,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reabrir'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      await _supabase
          .from('cash_register_closures')
          .delete()
          .eq('id', closureId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cierre reabierto. Las órdenes volvieron a la caja activa.'),
        ),
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al reabrir el cierre: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de Cierres'),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _reload,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildHistoryError()
              : _buildHistoryContent(),
    );
  }

  Widget _buildHistoryError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(
              'Error al cargar el historial: $_error',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _reload,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryContent() {
    final totals = _HistoryTotals.fromClosures(_closures);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildAccumulatedCard(totals),
        const SizedBox(height: 16),
        if (_closures.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'Aún no hay cierres registrados.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          )
        else
          ..._closures.map(
            (closure) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildClosureCard(closure),
            ),
          ),
      ],
    );
  }

  Widget _buildAccumulatedCard(_HistoryTotals totals) {
    return Card(
      color: Colors.deepOrange.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.deepOrange.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.summarize, color: Colors.deepOrange),
                SizedBox(width: 8),
                Text(
                  'Resumen acumulado',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 20),
            _buildHistoryRow('Cierres registrados', '${totals.closures}'),
            _buildHistoryRow('Total de órdenes', '${totals.orders}'),
            _buildHistoryRow(
              'Efectivo acumulado',
              Formatters.currency(totals.cash),
            ),
            _buildHistoryRow(
              'Transferencia acumulada',
              Formatters.currency(totals.transfer),
            ),
            _buildHistoryRow(
              'Total general recaudado',
              Formatters.currency(totals.revenue),
              bold: true,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.green.shade700,
                      side: BorderSide(color: Colors.green.shade400),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed:
                        _closures.isEmpty ? null : _shareAllHistoryWhatsApp,
                    icon: const Icon(Icons.chat),
                    label: const Text('Resumen WhatsApp'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.teal.shade700,
                      side: BorderSide(color: Colors.teal.shade400),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed:
                        _closures.isEmpty ? null : _exportAllHistoryExcelCsv,
                    icon: const Icon(Icons.table_view),
                    label: const Text('Detalle Excel'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClosureCard(Map<String, dynamic> closure) {
    final totalOrders = (closure['total_orders'] ?? 0) as num;
    final totalCash = (closure['total_cash'] ?? 0).toDouble();
    final totalTransfer = (closure['total_transfer'] ?? 0).toDouble();
    final totalRevenue = (closure['total_revenue'] ?? 0).toDouble();
    final closureDate = _parseDate(closure['closure_date']);
    final dateLabel = closureDate != null
        ? Formatters.dateTime(closureDate).split(' ').first
        : (closure['closure_date']?.toString() ?? 'Sin fecha');

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openClosureDetail(closure),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.event, size: 18, color: Colors.deepOrange),
                      const SizedBox(width: 6),
                      Text(
                        dateLabel,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '$totalOrders orden(es)',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
              const Divider(height: 20),
              _buildHistoryRow('Total de órdenes', '$totalOrders'),
              _buildHistoryRow('Efectivo', Formatters.currency(totalCash)),
              _buildHistoryRow(
                'Transferencia',
                Formatters.currency(totalTransfer),
              ),
              _buildHistoryRow(
                'Total ingresado',
                Formatters.currency(totalRevenue),
                bold: true,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _reopenClosure(closure),
                  icon: const Icon(Icons.undo, size: 18),
                  label: const Text('Reabrir cierre'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.deepOrange,
                  ),
                ),
              ),
              const Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Tocar para ver pedidos y reportes ›',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.deepOrange,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              color: bold ? Colors.green.shade800 : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

class _ClosureDetailView extends StatefulWidget {
  const _ClosureDetailView({required this.closure});

  final Map<String, dynamic> closure;

  @override
  State<_ClosureDetailView> createState() => _ClosureDetailViewState();
}

class _ClosureDetailViewState extends State<_ClosureDetailView> {
  final _supabase = Supabase.instance.client;

  bool _loading = true;
  bool _reopening = false;
  String? _error;
  List<Map<String, dynamic>> _orders = [];

  DateTime get _cutoff => _closureCutoff(widget.closure);

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await _supabase
          .from('orders')
          .select(_ordersWithItemsSelect)
          .eq('closure_id', widget.closure['id'])
          .order('paid_at', ascending: true);

      if (!mounted) return;
      setState(() {
        _orders = (data as List).cast<Map<String, dynamic>>();
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

  Future<void> _runReportAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo generar el reporte: $e')),
      );
    }
  }

  _ReportStats get _stats => _orders.isNotEmpty
      ? _ReportStats.fromOrders(_orders)
      : _ReportStats.fromClosure(widget.closure);

  Future<void> _shareSummary() async {
    await _runReportAction(
      () => _shareWhatsAppSummary(
        orders: _orders,
        cutoff: _cutoff,
        closureId: widget.closure['id'],
        notes: widget.closure['notes']?.toString(),
        stats: _stats,
      ),
    );
  }

  Future<void> _exportCsv() async {
    await _runReportAction(
      () => _exportExcelCsv(
        orders: _orders,
        cutoff: _cutoff,
        stats: _stats,
      ),
    );
  }

  Future<void> _reopen() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reabrir cierre'),
        content: const Text(
          '¿Reabrir este cierre? Las órdenes volverán a la caja activa '
          'para que puedas agregar pedidos de última hora.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepOrange,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reabrir'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _reopening = true);

    try {
      await _supabase
          .from('cash_register_closures')
          .delete()
          .eq('id', widget.closure['id']);

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _reopening = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al reabrir el cierre: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle del cierre'),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _loading ? null : _loadOrders,
          ),
        ],
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
            Text(
              'Error al cargar las órdenes del cierre: $_error',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadOrders,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final stats = _stats;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildHeaderCard(stats),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade600,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _shareSummary,
            icon: const Icon(Icons.chat),
            label: const Text('Enviar Resumen WhatsApp'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade600,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _exportCsv,
            icon: const Icon(Icons.table_view),
            label: const Text('Exportar Detalle Excel'),
          ),
        ),
        const SizedBox(height: 16),
        _buildModalityCard(stats),
        const SizedBox(height: 16),
        const Text(
          'Órdenes incluidas en este cierre',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (_orders.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Text(
                'No se encontraron órdenes para este cierre.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          )
        else
          ..._orders.map(_buildOrderCard),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.deepOrange,
            side: BorderSide(color: Colors.deepOrange.shade300),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: _reopening ? null : _reopen,
          icon: const Icon(Icons.undo),
          label: Text(_reopening ? 'Reabriendo...' : 'Reabrir cierre'),
        ),
      ],
    );
  }

  Widget _buildHeaderCard(_ReportStats stats) {
    final closureDate = _cutoff;
    final totalOrders =
        (widget.closure['total_orders'] as num?)?.toInt() ?? stats.totalOrders;
    final totalCash =
        (widget.closure['total_cash'] as num?)?.toDouble() ?? stats.cash;
    final totalTransfer =
        (widget.closure['total_transfer'] as num?)?.toDouble() ?? stats.transfer;
    final totalRevenue =
        (widget.closure['total_revenue'] as num?)?.toDouble() ?? stats.revenue;
    final notes = widget.closure['notes']?.toString().trim() ?? '';

    return Card(
      color: Colors.deepOrange.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.deepOrange.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cierre #${widget.closure['id']}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text('Fecha del corte: ${Formatters.dateTime(closureDate)}'),
            Text('Órdenes cerradas: $totalOrders'),
            const Divider(height: 20),
            _buildDetailRow('Efectivo', Formatters.currency(totalCash)),
            _buildDetailRow(
              'Transferencia',
              Formatters.currency(totalTransfer),
            ),
            _buildDetailRow(
              'Total recaudado',
              Formatters.currency(totalRevenue),
              bold: true,
            ),
            if (notes.isNotEmpty) ...[
              const Divider(height: 20),
              Text('Notas: $notes', style: const TextStyle(fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              color: bold ? Colors.green.shade800 : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModalityCard(_ReportStats stats) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Desglose por modalidad',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const Divider(height: 20),
            _buildModalityRow('🍽️ En local', stats.localCount, stats.localTotal),
            _buildModalityRow(
              '🥡 Para llevar',
              stats.takeawayCount,
              stats.takeawayTotal,
            ),
            _buildModalityRow(
              '🛵 Domicilio',
              stats.deliveryCount,
              stats.deliveryTotal,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModalityRow(String label, int count, double total) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('$label ($count)', style: const TextStyle(fontSize: 13)),
          Text(
            Formatters.currency(total),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final paidAt = _parseDate(order['paid_at']);
    final total = (order['total'] as num?)?.toDouble() ?? 0;
    final isCash = order['payment_method'] == 'efectivo';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor:
                      isCash ? Colors.green.shade100 : Colors.blue.shade100,
                  child: Icon(
                    isCash ? Icons.payments : Icons.account_balance,
                    size: 18,
                    color: isCash ? Colors.green : Colors.blue,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Orden #${order['id']}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${_paymentLabel(order['payment_method'])} · '
                        '${_deliveryLabel(order['delivery_type'])}'
                        '${paidAt != null ? ' · ${Formatters.dateTime(paidAt)}' : ''}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  Formatters.currency(total),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            Text(
              _orderDishes(order),
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
