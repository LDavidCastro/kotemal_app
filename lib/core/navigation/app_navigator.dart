import 'package:flutter/widgets.dart';

/// Clave global del [Navigator] principal.
///
/// Permite abrir pantallas (por ejemplo el seguimiento de un pedido) desde
/// callbacks que no tienen un [BuildContext], como las notificaciones.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
