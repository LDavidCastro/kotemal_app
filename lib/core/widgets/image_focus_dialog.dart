import 'package:flutter/material.dart';

import '../utils/image_focus_helper.dart';

/// Diálogo para elegir el punto de enfoque de la foto de un producto.
///
/// No recorta ni modifica el archivo: solo devuelve el [Alignment] elegido
/// (de -1.0 a 1.0 en cada eje), que luego se guarda como `#focus=x,y` en la URL.
/// Devuelve `null` si el usuario cancela.
class ImageFocusDialog extends StatefulWidget {
  final String imageUrl;
  final String title;
  final Alignment initialAlignment;

  const ImageFocusDialog({
    super.key,
    required this.imageUrl,
    required this.title,
    this.initialAlignment = Alignment.center,
  });

  @override
  State<ImageFocusDialog> createState() => _ImageFocusDialogState();
}

class _ImageFocusDialogState extends State<ImageFocusDialog> {
  late Alignment _alignment = _clamp(widget.initialAlignment);
  Size? _imageSize;
  ImageStream? _imageStream;
  ImageStreamListener? _listener;

  static Alignment _clamp(Alignment alignment) =>
      Alignment(alignment.x.clamp(-1.0, 1.0), alignment.y.clamp(-1.0, 1.0));

  @override
  void initState() {
    super.initState();
    _resolveImageSize();
  }

  @override
  void dispose() {
    _stopListening();
    super.dispose();
  }

  /// Necesitamos el tamaño real de la foto para saber exactamente dónde está
  /// dibujada dentro del contenedor (`BoxFit.contain` deja franjas vacías).
  void _resolveImageSize() {
    final stream = NetworkImage(
      stripImageFocus(widget.imageUrl),
    ).resolve(const ImageConfiguration());

    final listener = ImageStreamListener(
      (info, _) {
        if (!mounted) return;
        setState(() {
          _imageSize = Size(
            info.image.width.toDouble(),
            info.image.height.toDouble(),
          );
        });
        _stopListening();
      },
      onError: (_, _) {
        _stopListening();
      },
    );

    _imageStream = stream;
    _listener = listener;
    stream.addListener(listener);
  }

  void _stopListening() {
    final stream = _imageStream;
    final listener = _listener;
    if (stream != null && listener != null) {
      stream.removeListener(listener);
    }
    _imageStream = null;
    _listener = null;
  }

  Rect _containRect(Size container, Size image) {
    final imageAspect = image.width / image.height;
    final containerAspect = container.width / container.height;

    double width;
    double height;
    if (imageAspect > containerAspect) {
      width = container.width;
      height = width / imageAspect;
    } else {
      height = container.height;
      width = height * imageAspect;
    }

    return Rect.fromLTWH(
      (container.width - width) / 2,
      (container.height - height) / 2,
      width,
      height,
    );
  }

  void _updateFromPosition(Offset localPosition, Rect imageRect) {
    if (imageRect.width <= 0 || imageRect.height <= 0) return;

    final x = ((localPosition.dx - imageRect.left) / imageRect.width) * 2 - 1;
    final y = ((localPosition.dy - imageRect.top) / imageRect.height) * 2 - 1;

    setState(() => _alignment = _clamp(Alignment(x, y)));
  }

  Widget _placeholder() {
    return Container(
      color: Colors.orange.shade100,
      alignment: Alignment.center,
      child: Icon(Icons.fastfood, size: 56, color: Colors.deepOrange.shade300),
    );
  }

  @override
  Widget build(BuildContext context) {
    final baseUrl = stripImageFocus(widget.imageUrl);

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.center_focus_strong,
                    color: Colors.deepOrange,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Punto de enfoque',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 8),
              Text(
                'Toca o arrastra la mira sobre la parte más importante del platillo. '
                'La foto original no se recorta ni se modifica.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),
              AspectRatio(
                aspectRatio: 4 / 3,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final containerSize = Size(
                      constraints.maxWidth,
                      constraints.maxHeight,
                    );
                    final imageRect = _containRect(
                      containerSize,
                      _imageSize ?? containerSize,
                    );
                    final focusPoint = Offset(
                      imageRect.center.dx + _alignment.x * imageRect.width / 2,
                      imageRect.center.dy + _alignment.y * imageRect.height / 2,
                    );

                    return ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (details) => _updateFromPosition(
                          details.localPosition,
                          imageRect,
                        ),
                        onPanUpdate: (details) => _updateFromPosition(
                          details.localPosition,
                          imageRect,
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.network(
                              baseUrl,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) => _placeholder(),
                            ),
                            Positioned(
                              left: focusPoint.dx - 26,
                              top: focusPoint.dy - 26,
                              child: const IgnorePointer(
                                child: _FocusReticle(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text(
                    'Vista previa en el menú',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  Text(
                    'x: ${_alignment.x.toStringAsFixed(2)}  y: ${_alignment.y.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    width: 130,
                    height: 130,
                    child: Image.network(
                      baseUrl,
                      fit: BoxFit.cover,
                      alignment: _alignment,
                      errorBuilder: (_, _, _) => _placeholder(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepOrange,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.check),
                    label: const Text('Guardar enfoque'),
                    onPressed: () => Navigator.pop(context, _alignment),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mira arrastrable que indica el punto de enfoque seleccionado.
class _FocusReticle extends StatelessWidget {
  const _FocusReticle();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white, width: 2.5),
              color: Colors.white.withValues(alpha: 0.10),
              boxShadow: const [
                BoxShadow(color: Colors.black38, blurRadius: 6),
              ],
            ),
          ),
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}
