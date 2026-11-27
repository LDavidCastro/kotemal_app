import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../domain/product.dart';
import 'widgets/product_image_viewer.dart';
import '../../../core/utils/image_focus_helper.dart';

class CustomizedProductResult {
  final double finalPrice;
  final String notes;
  final int quantity;

  /// Foto que debe mostrarse en el carrito (variante elegida o foto principal).
  final String? selectedImageUrl;

  CustomizedProductResult({
    required this.finalPrice,
    required this.notes,
    this.quantity = 1,
    this.selectedImageUrl,
  });
}

class ProductCustomizationDialog extends StatefulWidget {
  final Product product;
  final String? initialNotes;
  final int initialQuantity;

  const ProductCustomizationDialog({
    super.key,
    required this.product,
    this.initialNotes,
    this.initialQuantity = 1,
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
  List<dynamic> _variants = [];
  Map<String, dynamic>? _selectedVariant;

  final Set<String> _removedIngredients = {};
  final Set<int> _selectedExtraIds = {};
  double _extraTotal = 0.0;
  late int _quantity;

  bool get _isEditing => widget.initialNotes != null;

  /// Foto de la variante seleccionada, si tiene una propia; si no, la foto
  /// principal del producto.
  String? get _activeImageUrl {
    final variantImage = _selectedVariant?['image_url'];
    if (variantImage is String && variantImage.trim().isNotEmpty) {
      return variantImage;
    }
    final productImage = widget.product.imageUrl;
    if (productImage != null && productImage.isNotEmpty) return productImage;
    return null;
  }

  @override
  void initState() {
    super.initState();
    _quantity = widget.initialQuantity < 1 ? 1 : widget.initialQuantity;
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
      final variantsList = items.where((i) => i['type'] == 'variant').toList();

      Map<String, dynamic>? selectedVariant;
      if (variantsList.isNotEmpty) {
        if (widget.initialNotes != null && widget.initialNotes!.isNotEmpty) {
          final variantSections = widget.initialNotes!.split(' | ');
          for (final section in variantSections) {
            if (section.startsWith('OPCIÓN: ')) {
              final variantName = section.replaceFirst('OPCIÓN: ', '').trim();
              final match = variantsList.firstWhere(
                (v) => (v['name'] as String).trim() == variantName,
                orElse: () => null,
              );
              if (match != null) {
                selectedVariant = Map<String, dynamic>.from(match as Map);
                break;
              }
            }
          }
        }
        selectedVariant ??= Map<String, dynamic>.from(variantsList.first);
      }

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
          _variants = variantsList;
          _selectedVariant = selectedVariant;
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

  void _openImageViewer() {
    final imageUrl = _activeImageUrl;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      showProductImageViewer(
        context,
        imageUrl: imageUrl,
        title: widget.product.name,
      );
    }
  }

  void _changeQuantity(int delta) {
    setState(() {
      _quantity = (_quantity + delta).clamp(1, 99);
    });
  }

  String _buildNotes() {
    final notesParts = <String>[];
    if (_selectedVariant != null) {
      notesParts.add('OPCIÓN: ${_selectedVariant!['name']}');
    }
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
    return notesParts.join(' | ');
  }

  void _submit() {
    final basePrice = _selectedVariant != null
        ? (_selectedVariant!['price'] as num).toDouble()
        : widget.product.price;
    final finalPrice = basePrice + _extraTotal;

    Navigator.pop(
      context,
      CustomizedProductResult(
        finalPrice: finalPrice,
        notes: _buildNotes(),
        quantity: _isEditing ? 1 : _quantity,
        selectedImageUrl: _activeImageUrl,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final basePrice = _selectedVariant != null
        ? (_selectedVariant!['price'] as num).toDouble()
        : widget.product.price;
    final finalPrice = basePrice + _extraTotal;
    final totalLabel = _isEditing
        ? 'Q${finalPrice.toStringAsFixed(2)}'
        : 'Q${(finalPrice * _quantity).toStringAsFixed(2)}';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _buildHeader(basePrice),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        widget.product.name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      if (widget.product.description != null &&
                          widget.product.description!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4, bottom: 12),
                          child: Text(
                            widget.product.description!,
                            style: TextStyle(
                                fontSize: 14, color: Colors.grey.shade600),
                          ),
                        ),
                      if (_variants.isNotEmpty) _buildVariantsSection(),
                      if (_removables.isNotEmpty) _buildRemovablesSection(),
                      if (_extras.isNotEmpty) _buildExtrasSection(),
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
                        ),
                      const SizedBox(height: 100),
                    ],
                  ),
          ),
          _buildBottomBar(finalPrice, totalLabel),
        ],
      ),
    );
  }

  Widget _buildHeader(double basePrice) {
    final activeImageUrl = _activeImageUrl;
    final hasImage = activeImageUrl != null && activeImageUrl.isNotEmpty;

    return SizedBox(
      height: 185,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: hasImage
                ? SizedBox.expand(
                    key: ValueKey(activeImageUrl),
                    child: GestureDetector(
                      onTap: _openImageViewer,
                      child: Image.network(
                        stripImageFocus(activeImageUrl),
                        fit: BoxFit.cover,
                        alignment: parseImageFocus(activeImageUrl),
                        errorBuilder: (_, _, _) => _dialogPlaceholder(),
                      ),
                    ),
                  )
                : SizedBox.expand(
                    key: const ValueKey('placeholder'),
                    child: _dialogPlaceholder(),
                  ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.35),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.55),
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 12,
            child: Row(
              children: [
                if (hasImage)
                  CircleAvatar(
                    backgroundColor: Colors.black45,
                    radius: 18,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.zoom_in,
                          color: Colors.white, size: 20),
                      onPressed: _openImageViewer,
                    ),
                  ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: Colors.black45,
                  radius: 18,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon:
                        const Icon(Icons.close, color: Colors.white, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Base: Q${basePrice.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }

  Widget _buildVariantsSection() {
    return _buildSectionCard(
      title: 'Elige una opción',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.restaurant_menu,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                'Elige una opción',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Column(
            children: _variants.map((variant) {
              final id = variant['id'] as int;
              final name = variant['name'] as String;
              final price = (variant['price'] as num).toDouble();
              final isSelected = _selectedVariant?['id'] == id;

              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedVariant = Map<String, dynamic>.from(variant as Map);
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.surface
                        : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.secondary
                          : Colors.grey.shade300,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isSelected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: isSelected ? AppColors.secondary : Colors.grey,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          name,
                          style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.w600,
                            fontSize: 14,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      Text(
                        'Q${price.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: isSelected
                              ? AppColors.secondary
                              : Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildRemovablesSection() {
    return _buildSectionCard(
      title: 'Quitar ingredientes',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.remove_circle_outline,
                  size: 18, color: Colors.red.shade700),
              const SizedBox(width: 6),
              Text(
                'Quitar ingredientes',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Colors.red.shade900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _removables.map((item) {
              final name = item['name'] as String;
              final isRemoved = _removedIngredients.contains(name);

              return ChoiceChip(
                avatar: Icon(
                  isRemoved ? Icons.cancel : Icons.circle_outlined,
                  size: 18,
                  color: isRemoved ? Colors.red.shade700 : Colors.grey.shade600,
                ),
                label: Text(
                  isRemoved ? 'Sin $name' : name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isRemoved ? FontWeight.bold : FontWeight.w500,
                    color:
                        isRemoved ? Colors.red.shade800 : Colors.grey.shade800,
                  ),
                ),
                selected: isRemoved,
                selectedColor: Colors.red.shade50,
                backgroundColor: Colors.white,
                side: BorderSide(
                  color: isRemoved
                      ? Colors.red.shade300
                      : Colors.grey.shade300,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                onSelected: (_) {
                  setState(() {
                    if (isRemoved) {
                      _removedIngredients.remove(name);
                    } else {
                      _removedIngredients.add(name);
                    }
                  });
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildExtrasSection() {
    return _buildSectionCard(
      title: 'Agregar extras',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.add_circle_outline,
                  size: 18, color: Colors.green.shade700),
              const SizedBox(width: 6),
              Text(
                'Agregar extras',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Colors.green.shade900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Column(
            children: _extras.map((extra) {
              final id = extra['id'] as int;
              final name = extra['name'] as String;
              final price = (extra['price'] as num).toDouble();
              final isSelected = _selectedExtraIds.contains(id);

              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      _selectedExtraIds.remove(id);
                    } else {
                      _selectedExtraIds.add(id);
                    }
                    _recalcExtras();
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.green.shade50
                        : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color:
                          isSelected ? Colors.green.shade400 : Colors.grey.shade300,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isSelected
                            ? Icons.check_circle
                            : Icons.add_circle_outline,
                        color: isSelected
                            ? Colors.green.shade700
                            : Colors.grey.shade600,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          name,
                          style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.w600,
                            fontSize: 14,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.green.shade100
                              : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '+Q${price.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isSelected
                                ? Colors.green.shade900
                                : Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(double finalPrice, String totalLabel) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            if (!_isEditing) ...[
              Container(
                height: 46,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove, size: 18),
                      onPressed: () => _changeQuantity(-1),
                    ),
                    Text(
                      '$_quantity',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add, size: 18,
                          color: AppColors.secondary),
                      onPressed: () => _changeQuantity(1),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: SizedBox(
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.secondary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  onPressed: _submit,
                  child: Text(
                    _isEditing
                        ? 'Guardar · $totalLabel'
                        : 'Agregar al Carrito · $totalLabel',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dialogPlaceholder() {
    return Container(
      color: AppColors.surface,
      alignment: Alignment.center,
      child: const Icon(Icons.fastfood, size: 60, color: AppColors.secondary),
    );
  }
}
