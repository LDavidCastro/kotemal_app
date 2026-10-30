import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/product.dart';

class CustomizedProductResult {
  final double finalPrice;
  final String notes;

  CustomizedProductResult({required this.finalPrice, required this.notes});
}

class ProductCustomizationDialog extends StatefulWidget {
  final Product product;
  final String? initialNotes;

  const ProductCustomizationDialog({
    super.key,
    required this.product,
    this.initialNotes,
  });

  @override
  State<ProductCustomizationDialog> createState() =>
      _ProductCustomizationDialogState();
}

class _ProductCustomizationDialogState
    extends State<ProductCustomizationDialog> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  String? _errorMessage;

  List<dynamic> _removables = [];
  List<dynamic> _extras = [];

  final Set<String> _removedIngredients = {};
  final Set<int> _selectedExtraIds = {};
  double _extraTotal = 0.0;

  @override
  void initState() {
    super.initState();
    _loadCustomizations();
  }

  Future<void> _loadCustomizations() async {
    try {
      final session = _supabase.auth.currentSession;
      debugPrint(
        'PERSONALIZACIONES -> productId=${widget.product.id} '
        'session=${session == null ? "ANON" : "AUTH(${session.user.id})"}',
      );

      final res = await _supabase
          .from('product_customizations')
          .select()
          .eq('product_id', widget.product.id)
          .eq('is_available', true);

      debugPrint('PERSONALIZACIONES -> filas=${res.length}');

      final items = List<dynamic>.from(res);
      final removablesList =
          items.where((i) => i['type'] == 'removable').toList();
      final extrasList = items.where((i) => i['type'] == 'extra').toList();

      if (widget.initialNotes != null && widget.initialNotes!.isNotEmpty) {
        final sections = widget.initialNotes!.split(' | ');
        for (var section in sections) {
          if (section.startsWith('SIN: ')) {
            final sinParts = section.replaceFirst('SIN: ', '').split(', ');
            for (var name in sinParts) {
              _removedIngredients.add(name.trim());
            }
          } else if (section.startsWith('CON EXTRA: ')) {
            final extraParts =
                section.replaceFirst('CON EXTRA: ', '').split(', ');
            for (var extraName in extraParts) {
              final match = extrasList.firstWhere(
                (e) => (e['name'] as String).trim() == extraName.trim(),
                orElse: () => {},
              );
              if (match.isNotEmpty) {
                _selectedExtraIds.add(match['id'] as int);
              }
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _removables = removablesList;
          _extras = extrasList;
          _isLoading = false;
        });
        _recalcExtras();
      }
    } on PostgrestException catch (e) {
      debugPrint(
        'PERSONALIZACIONES PostgrestException -> code=${e.code} '
        'message=${e.message} details=${e.details} hint=${e.hint}',
      );
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = '${e.code}: ${e.message}';
        });
      }
    } catch (e, st) {
      debugPrint('PERSONALIZACIONES error inesperado: $e\n$st');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _recalcExtras() {
    double sum = 0.0;
    for (var extra in _extras) {
      if (_selectedExtraIds.contains(extra['id'])) {
        sum += (extra['price'] as num).toDouble();
      }
    }
    setState(() => _extraTotal = sum);
  }

  @override
  Widget build(BuildContext context) {
    final finalPrice = widget.product.price + _extraTotal;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 600),
        child: Column(
          children: [
            Stack(
              children: [
                SizedBox(
                  height: 160,
                  width: double.infinity,
                  child: widget.product.imageUrl != null &&
                          widget.product.imageUrl!.isNotEmpty
                      ? Image.network(
                          widget.product.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _dialogPlaceholder(),
                        )
                      : _dialogPlaceholder(),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: CircleAvatar(
                    backgroundColor: Colors.black54,
                    radius: 16,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.close, color: Colors.white, size: 18),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 8,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Base: Q${widget.product.price.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text(
                          widget.product.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (widget.product.description != null &&
                            widget.product.description!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 8),
                            child: Text(
                              widget.product.description!,
                              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                            ),
                          ),
                        const Divider(),
                        if (_removables.isNotEmpty) ...[
                          const Text(
                            'Quitar ingredientes:',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          ..._removables.map((item) {
                            final name = item['name'] as String;
                            final isRemoved = _removedIngredients.contains(name);
                            return CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                'Sin $name',
                                style: TextStyle(
                                  color: isRemoved ? Colors.red : Colors.black87,
                                  fontWeight: isRemoved
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              value: isRemoved,
                              activeColor: Colors.red,
                              onChanged: (val) {
                                setState(() {
                                  if (val == true) {
                                    _removedIngredients.add(name);
                                  } else {
                                    _removedIngredients.remove(name);
                                  }
                                });
                              },
                            );
                          }),
                          const Divider(),
                        ],
                        if (_extras.isNotEmpty) ...[
                          const Text(
                            'Agregar extras:',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          ..._extras.map((extra) {
                            final id = extra['id'] as int;
                            final name = extra['name'] as String;
                            final price = (extra['price'] as num).toDouble();
                            final isSelected = _selectedExtraIds.contains(id);

                            return CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text('$name (+Q${price.toStringAsFixed(2)})'),
                              value: isSelected,
                              activeColor: Colors.deepOrange,
                              onChanged: (val) {
                                setState(() {
                                  if (val == true) {
                                    _selectedExtraIds.add(id);
                                  } else {
                                    _selectedExtraIds.remove(id);
                                  }
                                  _recalcExtras();
                                });
                              },
                            );
                          }),
                        ],
                        if (_errorMessage != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: Text(
                                'No se pudieron cargar las personalizaciones:\n$_errorMessage',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),
                          )
                        else if (_removables.isEmpty && _extras.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: Text(
                                'Este producto no cuenta con personalizaciones adicionales.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 6,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Total producto:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        Text(
                          'Q${finalPrice.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      final notesParts = <String>[];
                      if (_removedIngredients.isNotEmpty) {
                        notesParts.add('SIN: ${_removedIngredients.join(', ')}');
                      }
                      if (_selectedExtraIds.isNotEmpty) {
                        final extraNames = _extras
                            .where((e) => _selectedExtraIds.contains(e['id']))
                            .map((e) => e['name'])
                            .join(', ');
                        notesParts.add('CON EXTRA: $extraNames');
                      }

                      Navigator.pop(
                        context,
                        CustomizedProductResult(
                          finalPrice: finalPrice,
                          notes: notesParts.join(' | '),
                        ),
                      );
                    },
                    child: const Text('Agregar', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dialogPlaceholder() {
    return Container(
      color: Colors.orange.shade100,
      alignment: Alignment.center,
      child: Icon(Icons.fastfood, size: 60, color: Colors.deepOrange.shade300),
    );
  }
}