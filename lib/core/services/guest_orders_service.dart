import 'package:shared_preferences/shared_preferences.dart';

class GuestOrdersService {
  static const String _key = 'guest_order_ids';

  /// Guarda el ID de una nueva orden generada como invitado
  static Future<void> saveOrderId(int orderId) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> savedList = prefs.getStringList(_key) ?? [];
    
    final idStr = orderId.toString();
    if (!savedList.contains(idStr)) {
      savedList.insert(0, idStr); // Agregar al inicio para mostrar el más reciente primero
      await prefs.setStringList(_key, savedList);
    }
  }

  /// Recupera los IDs de pedidos del invitado como enteros
  static Future<List<int>> getSavedOrderIds() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> savedList = prefs.getStringList(_key) ?? [];
    return savedList.map((e) => int.tryParse(e) ?? 0).where((id) => id > 0).toList();
  }

  /// Limpia una orden si fue cancelada o finalizada (opcional)
  static Future<void> removeOrderId(int orderId) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> savedList = prefs.getStringList(_key) ?? [];
    savedList.remove(orderId.toString());
    await prefs.setStringList(_key, savedList);
  }
}