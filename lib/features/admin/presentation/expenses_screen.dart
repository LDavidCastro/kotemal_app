import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/formatters.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  final _supabase = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _expenses = [];
  double _totalExpenses = 0;
  double _cashExpenses = 0;
  double _transferExpenses = 0;

  static const List<String> _baseCategories = [
    'Insumos / Cocina',
    'Gas / Servicios',
    'Empaques / Desechables',
    'Reparto / Gasolina',
    'Personal / Varios',
  ];

  List<String> get _categories => const [..._baseCategories, 'Otra...'];

  @override
  void initState() {
    super.initState();
    _loadExpenses();
  }

  Future<void> _loadExpenses() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await _supabase
          .from('expenses')
          .select(
            'id, category, description, amount, payment_method, created_at, '
            'registered_by_name',
          )
          .isFilter('closure_id', null)
          .order('created_at', ascending: false);

      final expenses = (data as List).cast<Map<String, dynamic>>();
      _updateTotals(expenses);

      if (!mounted) return;
      setState(() {
        _expenses = expenses;
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

  void _updateTotals(List<Map<String, dynamic>> expenses) {
    var total = 0.0;
    var cash = 0.0;
    var transfer = 0.0;

    for (final expense in expenses) {
      final amount = (expense['amount'] ?? 0).toDouble();
      final method = expense['payment_method']?.toString();
      total += amount;
      if (method == 'efectivo') {
        cash += amount;
      } else if (method == 'transferencia') {
        transfer += amount;
      }
    }

    _totalExpenses = total;
    _cashExpenses = cash;
    _transferExpenses = transfer;
  }

  Future<void> _deleteExpense(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar gasto'),
        content: const Text(
          '¿Seguro que deseas eliminar este gasto? Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      await _supabase.from('expenses').delete().eq('id', id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gasto eliminado')),
      );
      await _loadExpenses();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al eliminar gasto: $e')),
      );
    }
  }

  Future<void> _openAddExpenseDialog() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddExpenseSheet(
        onSaved: _loadExpenses,
        categories: _categories,
      ),
    );
  }

  String _formatTime(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return '--:--';
    final hh = date.hour.toString().padLeft(2, '0');
    final mm = date.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'Insumos / Cocina':
        return Icons.restaurant;
      case 'Gas / Servicios':
        return Icons.local_gas_station;
      case 'Empaques / Desechables':
        return Icons.takeout_dining;
      case 'Reparto / Gasolina':
        return Icons.delivery_dining;
      case 'Personal / Varios':
      default:
        return(Icons.receipt_long);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F9),
      appBar: AppBar(
        title: const Text('Registro de Gastos'),
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
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.amber.shade800,
        foregroundColor: Colors.white,
        onPressed: _openAddExpenseDialog,
        icon: const Icon(Icons.add),
        label: const Text('Registrar Gasto'),
      ),
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
            Text('Error al cargar gastos: $_error', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadExpenses,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return RefreshIndicator(
      onRefresh: _loadExpenses,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSummaryCard(),
          const SizedBox(height: 20),
          Row(
            children: [
              const Icon(Icons.list_alt, color: Colors.black54),
              const SizedBox(width: 8),
              const Text(
                'Gastos del turno abierto',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                '${_expenses.length} registro(s)',
                style: const TextStyle(color: Colors.black54, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_expenses.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  'No hay gastos registrados en este turno.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else
            ..._expenses.map(_buildExpenseTile),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Card(
      color: Colors.white,
      elevation: 1.5,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.account_balance_wallet, color: Colors.amber),
                SizedBox(width: 8),
                Text(
                  'Resumen del turno abierto',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total de gastos',
                  style: TextStyle(fontSize: 14),
                ),
                Text(
                  Formatters.currency(_totalExpenses),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildSummaryItem(
                    'Efectivo',
                    _cashExpenses,
                    Icons.payments,
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSummaryItem(
                    'Transferencia',
                    _transferExpenses,
                    Icons.account_balance,
                    Colors.blue,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(
    String label,
    double amount,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 2),
          Text(
            Formatters.currency(amount),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseTile(Map<String, dynamic> expense) {
    final id = expense['id'] as int;
    final category = expense['category']?.toString() ?? 'Otros';
    final description = expense['description']?.toString() ?? '';
    final amount = (expense['amount'] ?? 0).toDouble();
    final method = expense['payment_method']?.toString() ?? 'efectivo';
    final isCash = method == 'efectivo';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(_categoryIcon(category), color: Colors.amber.shade800),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description.isNotEmpty ? description : 'Sin descripción',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isCash
                              ? Colors.green.withValues(alpha: 0.12)
                              : Colors.blue.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isCash ? 'Efectivo' : 'Transferencia',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isCash ? Colors.green : Colors.blue,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatTime(expense['created_at']),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Por: ${expense['registered_by_name']?.toString().trim().isNotEmpty == true ? expense['registered_by_name'] : '—'}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '-${Formatters.currency(amount)}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => _deleteExpense(id),
                  tooltip: 'Eliminar gasto',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AddExpenseSheet extends StatefulWidget {
  final VoidCallback onSaved;
  final List<String> categories;

  const _AddExpenseSheet({
    required this.onSaved,
    required this.categories,
  });

  @override
  State<_AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<_AddExpenseSheet> {
  final _supabase = Supabase.instance.client;
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  final _customCategoryController = TextEditingController();
  final _registeredByController = TextEditingController();

  String _category = 'Insumos / Cocina';
  String _paymentMethod = 'efectivo';
  bool _saving = false;
  bool _loadingName = true;

  @override
  void initState() {
    super.initState();
    _loadRegisteredByName();
  }

  Future<void> _loadRegisteredByName() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _loadingName = false);
      return;
    }

    try {
      final data = await _supabase
          .from('profiles')
          .select('full_name')
          .eq('id', user.id)
          .maybeSingle();

      final name = data?['full_name']?.toString().trim() ?? '';
      if (mounted) {
        setState(() {
          _registeredByController.text = name;
          _loadingName = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingName = false);
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    _customCategoryController.dispose();
    _registeredByController.dispose();
    super.dispose();
  }

  String get _finalCategory {
    if (_category == 'Otra...') {
      return _customCategoryController.text.trim();
    }
    return _category;
  }

  Future<void> _save() async {
    final description = _descriptionController.text.trim();
    final amountText = _amountController.text.trim().replaceAll(',', '');
    final amount = double.tryParse(amountText);
    final registeredBy = _registeredByController.text.trim();
    final finalCategory = _finalCategory;

    if (description.isEmpty) {
      _showError('La descripción es obligatoria.');
      return;
    }
    if (amount == null || amount <= 0) {
      _showError('Ingresa un monto válido mayor a 0.');
      return;
    }
    if (registeredBy.isEmpty) {
      _showError('El campo "Registrado por" es obligatorio.');
      return;
    }
    if (finalCategory.isEmpty) {
      _showError('La categoría es obligatoria.');
      return;
    }

    final user = _supabase.auth.currentUser;
    if (user == null) {
      _showError('Debes iniciar sesión para registrar un gasto.');
      return;
    }

    setState(() => _saving = true);

    try {
      await _supabase.from('expenses').insert({
        'category': finalCategory,
        'description': description,
        'amount': amount,
        'payment_method': _paymentMethod,
        'created_by': user.id,
        'registered_by_name': registeredBy,
      });

      if (!mounted) return;
      Navigator.pop(context);
      widget.onSaved();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gasto registrado')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showError('Error al registrar gasto: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final isCustomCategory = _category == 'Otra...';

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Registrar Gasto',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: const InputDecoration(
              labelText: 'Categoría',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: widget.categories
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _category = value);
            },
          ),
          if (isCustomCategory) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _customCategoryController,
              decoration: const InputDecoration(
                labelText: 'Escribe la categoría *',
                hintText: 'Ej. Limpieza, Mantenimiento',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              textCapitalization: TextCapitalization.sentences,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Escribe la categoría';
                }
                return null;
              },
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _descriptionController,
            decoration: const InputDecoration(
              labelText: 'Descripción',
              hintText: 'Ej. Compra de tortillas y verdura',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountController,
            decoration: const InputDecoration(
              labelText: 'Monto (Q)',
              prefixText: 'Q ',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _registeredByController,
            decoration: const InputDecoration(
              labelText: 'Registrado por *',
              hintText: 'Ej. David Castro',
              border: OutlineInputBorder(),
              isDense: true,
              suffixIcon: SizedBox(
                width: 24,
                height: 24,
                child: Center(child: Icon(Icons.person_outline, size: 20)),
              ),
            ),
            textCapitalization: TextCapitalization.words,
            enabled: !_loadingName,
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'efectivo',
                label: Text('Efectivo'),
                icon: Icon(Icons.payments),
              ),
              ButtonSegment(
                value: 'transferencia',
                label: Text('Transferencia'),
                icon: Icon(Icons.account_balance),
              ),
            ],
            selected: {_paymentMethod},
            onSelectionChanged: (selected) {
              if (selected.isNotEmpty) {
                setState(() => _paymentMethod = selected.first);
              }
            },
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber.shade800,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _saving || _loadingName ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Guardar Gasto'),
          ),
        ],
      ),
    );
  }
}
