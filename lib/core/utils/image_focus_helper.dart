import 'package:flutter/material.dart';

/// Fragmento `#focus=x,y` con valores normalizados de -1.0 a 1.0.
final RegExp _focusFragment = RegExp(
  r'#focus=(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)$',
);

/// Devuelve [imageUrl] sin su fragmento (`#...`), incluido `#focus=`.
///
/// Es la URL que debe usarse para descargar/mostrar la imagen, ya que el
/// fragmento es metadata local y nunca se envía al servidor.
String stripImageFocus(String imageUrl) {
  final hashIndex = imageUrl.indexOf('#');
  return hashIndex == -1 ? imageUrl : imageUrl.substring(0, hashIndex);
}

/// Lee el punto de enfoque guardado en la URL como `#focus=x,y`.
///
/// Si no hay fragmento, está mal formado o queda fuera del rango
/// [-1.0, 1.0], devuelve [Alignment.center].
Alignment parseImageFocus(String? imageUrl) {
  if (imageUrl == null || imageUrl.trim().isEmpty) return Alignment.center;

  final match = _focusFragment.firstMatch(imageUrl.trim());
  if (match == null) return Alignment.center;

  final x = double.tryParse(match.group(1)!);
  final y = double.tryParse(match.group(2)!);
  if (x == null || y == null) return Alignment.center;
  if (x < -1.0 || x > 1.0 || y < -1.0 || y > 1.0) return Alignment.center;

  return Alignment(x, y);
}

/// Agrega (o reemplaza) el fragmento `#focus=x,y` al final de [imageUrl].
///
/// No modifica el archivo de imagen: el enfoque viaja en la misma URL.
String applyImageFocus(String imageUrl, Alignment alignment) {
  final base = stripImageFocus(imageUrl.trim());
  final x = alignment.x.clamp(-1.0, 1.0);
  final y = alignment.y.clamp(-1.0, 1.0);
  return '$base#focus=${x.toStringAsFixed(2)},${y.toStringAsFixed(2)}';
}
