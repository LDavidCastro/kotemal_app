import 'package:flutter/material.dart';

abstract final class AppColors {
  /// Café tostado del logo (textos e iconos principales).
  static const Color primary = Color(0xFF4B2618);

  /// Naranja terracota de la llama (botones, acentos, estados activos).
  static const Color secondary = Color(0xFFC25229);

  /// Fondo crema claro de las pantallas.
  static const Color background = Color(0xFFF3ECE4);

  /// Fondo arena del logo / AppBar integrado.
  static const Color logoBackground = Color(0xFFE9E1D9);

  /// Superficies marfil cálido (tarjetas, inputs, chips).
  static const Color surface = Color(0xFFFAF6F1);

  /// Borde sutil para tarjetas y superficies.
  static const Color border = Color(0xFFE2D8CE);

  /// Borde suave para inputs y chips en reposo.
  static const Color inputBorder = Color(0xFFD5C8BC);

  static const Color error = Color(0xFFC62828);
  static const Color textPrimary = Color(0xFF4B2618);
  static const Color textSecondary = Color(0xFF616161);
}
