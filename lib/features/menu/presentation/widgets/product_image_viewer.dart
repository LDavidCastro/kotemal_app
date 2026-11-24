import 'package:flutter/material.dart';

import '../../../../core/utils/image_focus_helper.dart';

/// Abre la fotografía de un producto a pantalla completa con zoom.
///
/// El usuario puede pellizcar para acercar/alejar y arrastrar para moverse
/// sobre la imagen. Se muestra completa (sin recortes) sobre fondo negro.
void showProductImageViewer(
  BuildContext context, {
  required String imageUrl,
  required String title,
}) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (_) => ProductImageViewerDialog(imageUrl: imageUrl, title: title),
  );
}

class ProductImageViewerDialog extends StatelessWidget {
  final String imageUrl;
  final String title;

  const ProductImageViewerDialog({
    super.key,
    required this.imageUrl,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Icon(Icons.zoom_in, color: Colors.white54, size: 20),
                  const SizedBox(width: 8),
                ],
              ),
            ),
            Expanded(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 4.0,
                child: Center(
                  child: Image.network(
                    stripImageFocus(imageUrl),
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.broken_image,
                      color: Colors.white54,
                      size: 64,
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
}
