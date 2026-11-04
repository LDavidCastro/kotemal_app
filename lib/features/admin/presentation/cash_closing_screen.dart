import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/formatters.dart';

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
  Map<String, dynamic>? _todayClosure;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  DateTime get _dayStart {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime get _dayEnd => _dayStart.add(const Duration(days: 1));

  String get _dateOnly {
    final day = _dayStart;
    final month = day.month.toString().padLeft(2, '0');
    final dayOfMonth = day.day.toString().padLeft(2, '0');
    return '${day.year}-$month-$dayOfMonth';
  }

  Future<void> _loadSummary() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _supabase
            .from('orders')
            .select('id, total, payment_method, paid_at')
            .eq('payment_status', 'pagado')
            .gte('paid_at', _dayStart.toUtc().toIso8601String())
            .lt('paid_at', _dayEnd.toUtc().toIso8601String())
            .order('paid_at', ascending: false),
        _supabase
            .from('cash_register_closures')
            .select()
            .eq('closure_date', _dateOnly)
            .order('id', ascending: false)
            .limit(1)
            .maybeSingle(),
      ]);

      final orders = (results[0] as List).cast<Map<String, dynamic>>();
      final todayClosure = results[1] as Map<String, dynamic>?;

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
        _todayClosure = todayClosure;
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

  Future<void> _closeCashRegister() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes iniciar sesión como administrador.')),
      );
      return;
    }

    if (_todayClosure != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La caja de hoy ya fue cerrada.')),
      );
      return;
    }

    if (_paidOrders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay pagos registrados hoy para cerrar.')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar Caja de Hoy'),
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

    setState(() => _closing = true);

    try {
      final inserted = await _supabase
          .from('cash_register_closures')
          .insert({
            'closed_by': user.id,
            'closure_date': _dateOnly,
            'total_orders': _paidOrders.length,
            'total_cash': _cashTotal,
            'total_transfer': _transferTotal,
            'total_revenue': _revenueTotal,
            'notes': 'Cierre generado desde la aplicación.',
          })
          .select()
          .single();

      if (!mounted) return;
      setState(() => _todayClosure = inserted);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Caja cerrada correctamente.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cerrar la caja: $e')),
      );
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  void _openHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const _ClosureHistoryScreen(),
      ),
    );
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
          'Resumen del ${Formatters.dateTime(_dayStart).split(' ').first}',
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
                    Text('Total del día', style: TextStyle(fontSize: 16)),
                    SizedBox(height: 4),
                    Text(
                      'Órdenes pagadas',
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
        if (_todayClosure != null)
          _buildClosedBanner(_todayClosure!)
        else
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
              label: Text(_closing ? 'Cerrando...' : 'Cerrar Caja de Hoy'),
            ),
          ),
        const SizedBox(height: 24),
        const Text(
          'Órdenes pagadas hoy',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (_paidOrders.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'Aún no hay órdenes pagadas hoy.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          )
        else
          ..._paidOrders.map(_buildOrderTile),
      ],
    );
  }

  Widget _buildClosedBanner(Map<String, dynamic> closure) {
    final totalOrders = (closure['total_orders'] ?? 0) as num;
    final totalCash = (closure['total_cash'] ?? 0).toDouble();
    final totalTransfer = (closure['total_transfer'] ?? 0).toDouble();
    final totalRevenue = (closure['total_revenue'] ?? 0).toDouble();
    final closureDate = DateTime.tryParse(
      closure['closure_date']?.toString() ?? '',
    );

    return Card(
      color: Colors.green.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.green.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '✓ Caja ya cerrada para este día',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade800,
                    ),
                  ),
                ),
              ],
            ),
            if (closureDate != null) ...[
              const SizedBox(height: 4),
              Text(
                'Fecha de cierre: ${Formatters.dateTime(closureDate).split(' ').first}',
                style: const TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ],
            const Divider(height: 20),
            _buildClosureRow('Total de órdenes', '$totalOrders'),
            _buildClosureRow('Efectivo', Formatters.currency(totalCash)),
            _buildClosureRow(
              'Transferencia',
              Formatters.currency(totalTransfer),
            ),
            _buildClosureRow(
              'Total ingresado',
              Formatters.currency(totalRevenue),
              bold: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClosureRow(String label, String value, {bool bold = false}) {
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

  Widget _buildOrderTile(Map<String, dynamic> order) {
    final id = order['id'];
    final total = (order['total'] ?? 0).toDouble();
    final method = order['payment_method'];
    final paidAt = order['paid_at'] != null
        ? DateTime.tryParse(order['paid_at'].toString())
        : null;
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
          '${isCash ? 'Efectivo' : 'Transferencia'}'
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

class _ClosureHistoryScreen extends StatefulWidget {
  const _ClosureHistoryScreen();

  @override
  State<_ClosureHistoryScreen> createState() => _ClosureHistoryScreenState();
}

class _ClosureHistoryScreenState extends State<_ClosureHistoryScreen> {
  final _supabase = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _closuresFuture;

  @override
  void initState() {
    super.initState();
    _closuresFuture = _loadClosures();
  }

  Future<List<Map<String, dynamic>>> _loadClosures() async {
    final data = await _supabase
        .from('cash_register_closures')
        .select()
        .order('closure_date', ascending: false)
        .order('id', ascending: false);

    return (data as List).cast<Map<String, dynamic>>();
  }

  void _reload() {
    setState(() {
      _closuresFuture = _loadClosures();
    });
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
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _closuresFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.red),
                    const SizedBox(height: 12),
                    Text(
                      'Error al cargar el historial: ${snapshot.error}',
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

          final closures = snapshot.data ?? [];

          if (closures.isEmpty) {
            return const Center(
              child: Text(
                'Aún no hay cierres registrados.',
                style: TextStyle(color: Colors.grey),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: closures.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) =>
                _buildClosureCard(closures[index]),
          );
        },
      ),
    );
  }

  Widget _buildClosureCard(Map<String, dynamic> closure) {
    final totalOrders = (closure['total_orders'] ?? 0) as num;
    final totalCash = (closure['total_cash'] ?? 0).toDouble();
    final totalTransfer = (closure['total_transfer'] ?? 0).toDouble();
    final totalRevenue = (closure['total_revenue'] ?? 0).toDouble();
    final closureDate = DateTime.tryParse(
      closure['closure_date']?.toString() ?? '',
    );
    final dateLabel = closureDate != null
        ? Formatters.dateTime(closureDate).split(' ').first
        : (closure['closure_date']?.toString() ?? 'Sin fecha');

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          ],
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
