import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../menu/domain/product.dart';

class ProductEditScreen extends StatefulWidget {
  final Product? product; // Si es null, estamos CREANDO un producto nuevo

  const ProductEditScreen({super.key, this.product});

  @override
  State<ProductEditScreen> createState() => _ProductEditScreenState();
}

class _ProductEditScreenState extends State<ProductEditScreen> {
  final _supabase = Supabase.instance.client;

  late TextEditingController _nameController;
  late TextEditingController _descController;
  late TextEditingController _priceController;

  final _extraNameController = TextEditingController();
  final _extraPriceController = TextEditingController();
  final _removableController = TextEditingController();

  String _category = 'Comidas';
  bool _isAvailable = true;
  String? _imageUrl;
  bool _isUploading = false;
  bool _isSaving = false;

  List<Map<String, dynamic>> _customizations = [];
  int? _createdProductId;

  bool get isEditing => widget.product != null || _createdProductId != null;
  int? get currentProductId => widget.product?.id ?? _createdProductId;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.product?.name ?? '');
    _descController = TextEditingController(text: widget.product?.description ?? '');
    _priceController = TextEditingController(
      text: widget.product != null ? widget.product!.price.toStringAsFixed(2) : '',
    );
    _category = widget.product?.category ?? 'Comidas';
    _isAvailable = widget.product?.isAvailable ?? true;
    _imageUrl = widget.product?.imageUrl;

    if (widget.product != null) {
      _loadCustomizations();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _priceController.dispose();
    _extraNameController.dispose();
    _extraPriceController.dispose();
    _removableController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomizations() async {
    if (currentProductId == null) return;
    try {
      final res = await _supabase
          .from('product_customizations')
          .select()
          .eq('product_id', currentProductId!);
      if (mounted) {
        setState(() => _customizations = List<Map<String, dynamic>>.from(res));
      }
    } catch (_) {}
  }

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (picked == null) return;

    setState(() => _isUploading = true);
    try {
      final file = File(picked.path);
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';

      await _supabase.storage.from('menu-images').upload(fileName, file);
      final publicUrl = _supabase.storage.from('menu-images').getPublicUrl(fileName);

      if (isEditing && currentProductId != null) {
        await _supabase.from('products').update({'image_url': publicUrl}).eq('id', currentProductId!);
      }

      setState(() => _imageUrl = publicUrl);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Foto lista y vinculada ✓')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al subir imagen: $e')));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  // Guardar o Actualizar Datos Principales
  Future<void> _saveProductData() async {
    final name = _nameController.text.trim();
    final price = double.tryParse(_priceController.text.trim());

    if (name.isEmpty || price == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa un nombre y precio válidos.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      if (isEditing && currentProductId != null) {
        // Actualizar producto existente
        await _supabase.from('products').update({
          'name': name,
          'description': _descController.text.trim(),
          'price': price,
          'category': _category,
          'is_available': _isAvailable,
          if (_imageUrl != null) 'image_url': _imageUrl,
        }).eq('id', currentProductId!);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Producto actualizado exitosamente.')),
          );
          Navigator.pop(context, true);
        }
      } else {
        // Insertar producto nuevo
        final res = await _supabase.from('products').insert({
          'name': name,
          'description': _descController.text.trim(),
          'price': price,
          'category': _category,
          'is_available': _isAvailable,
          'image_url': _imageUrl,
        }).select('id').single();

        final newId = res['id'] as int;
        setState(() {
          _createdProductId = newId;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('¡Producto creado! Ahora puedes agregarle ingredientes y extras.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // Eliminar Producto Definitivamente
  Future<void> _deleteProduct() async {
    if (currentProductId == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar producto?'),
        content: Text('¿Seguro que deseas eliminar permanentemente "${_nameController.text}"? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isSaving = true);
    try {
      await _supabase.from('products').delete().eq('id', currentProductId!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Producto eliminado del menú.')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al eliminar: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _addCustomization({required String name, required String type, double price = 0.0}) async {
    if (currentProductId == null || name.trim().isEmpty) return;
    await _supabase.from('product_customizations').insert({
      'product_id': currentProductId,
      'name': name.trim(),
      'type': type,
      'price': price,
    });
    _loadCustomizations();
  }

  Future<void> _deleteCustomization(int id) async {
    await _supabase.from('product_customizations').delete().eq('id', id);
    _loadCustomizations();
  }

  @override
  Widget build(BuildContext context) {
    final removables = _customizations.where((c) => c['type'] == 'removable').toList();
    final extras = _customizations.where((c) => c['type'] == 'extra').toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Editar Producto' : 'Nuevo Producto'),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
        actions: [
          if (isEditing)
            IconButton(
              icon: const Icon(Icons.delete_forever),
              tooltip: 'Eliminar producto',
              onPressed: _isSaving ? null : _deleteProduct,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Selector de Foto
            Center(
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _imageUrl != null && _imageUrl!.isNotEmpty
                        ? Image.network(_imageUrl!, width: double.infinity, height: 170, fit: BoxFit.cover)
                        : Container(
                            width: double.infinity,
                            height: 170,
                            color: Colors.grey.shade200,
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_a_photo, size: 40, color: Colors.grey),
                                SizedBox(height: 6),
                                Text('Toca para agregar foto', style: TextStyle(color: Colors.grey)),
                              ],
                            ),
                          ),
                  ),
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: FloatingActionButton.small(
                      backgroundColor: Colors.deepOrange,
                      foregroundColor: Colors.white,
                      onPressed: _isUploading ? null : _pickAndUploadImage,
                      child: _isUploading
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.camera_alt),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 2. Interruptor de Disponibilidad (Agotado / Disponible)
            Card(
              color: _isAvailable ? Colors.green.shade50 : Colors.red.shade50,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child: SwitchListTile(
                title: Text(
                  _isAvailable ? 'PRODUCTO DISPONIBLE' : 'PRODUCTO AGOTADO / DESACTIVADO',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _isAvailable ? Colors.green.shade800 : Colors.red.shade800,
                  ),
                ),
                subtitle: Text(
                  _isAvailable
                      ? 'Los clientes pueden pedirlo en el menú'
                      : 'Oculto o bloqueado para los clientes',
                  style: const TextStyle(fontSize: 12),
                ),
                value: _isAvailable,
                activeColor: Colors.green,
                onChanged: (val) => setState(() => _isAvailable = val),
              ),
            ),
            const SizedBox(height: 14),

            // 3. Campos Principales
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Nombre del Platillo / Bebida *', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _priceController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Precio (Q) *', prefixText: 'Q ', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _category,
                    decoration: const InputDecoration(labelText: 'Categoría', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'Comidas', child: Text('Comidas')),
                      DropdownMenuItem(value: 'Bebidas', child: Text('Bebidas')),
                      DropdownMenuItem(value: 'Postres', child: Text('Postres')),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _category = val);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _descController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Descripción / Ingredientes base',
                hintText: 'Ej. Carne marinada, frijoles y queso derretido',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // Botón de guardar datos principales
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
                onPressed: _isSaving ? null : _saveProductData,
                icon: const Icon(Icons.save),
                label: Text(_isSaving ? 'Guardando...' : (isEditing ? 'Guardar Cambios' : 'Crear Producto')),
              ),
            ),

            // 4. Sección de Ingredientes y Extras (Solo visible si ya tiene ID creado)
            if (isEditing) ...[
              const Divider(height: 36),
              const Text('1. Ingredientes que el cliente puede QUITAR:', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _removableController,
                      decoration: const InputDecoration(hintText: 'Ej. Cebolla, Tomate'),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle, color: Colors.green, size: 28),
                    onPressed: () {
                      _addCustomization(name: _removableController.text, type: 'removable');
                      _removableController.clear();
                    },
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                children: removables.map((r) => Chip(
                  label: Text(r['name']),
                  onDeleted: () => _deleteCustomization(r['id']),
                )).toList(),
              ),
              const SizedBox(height: 20),

              const Text('2. Extras con COSTO ADICIONAL:', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _extraNameController,
                      decoration: const InputDecoration(hintText: 'Ej. Queso extra'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _extraPriceController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(hintText: 'Precio Q'),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle, color: Colors.deepOrange, size: 28),
                    onPressed: () {
                      final price = double.tryParse(_extraPriceController.text) ?? 0.0;
                      _addCustomization(name: _extraNameController.text, type: 'extra', price: price);
                      _extraNameController.clear();
                      _extraPriceController.clear();
                    },
                  ),
                ],
              ),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: extras.length,
                itemBuilder: (ctx, i) {
                  final ex = extras[i];
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(ex['name']),
                    subtitle: Text('+Q${(ex['price'] as num).toStringAsFixed(2)}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _deleteCustomization(ex['id']),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}