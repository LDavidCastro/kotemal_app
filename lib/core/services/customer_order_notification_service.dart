import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notificaciones nativas del sistema para el cliente cuando cambia el estado
/// de sus pedidos del día.
class CustomerOrderNotificationService {
  CustomerOrderNotificationService._();

  static final CustomerOrderNotificationService instance =
      CustomerOrderNotificationService._();

  static const String channelId = 'kotemal_order_updates';
  static const String channelName = 'Actualizaciones de pedidos';
  static const String channelDescription =
      "Estado de tus pedidos de K'OTEMAL en tiempo real";

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Se invoca cuando el usuario toca una notificación de pedido.
  void Function(int orderId)? onOrderTap;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const settings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
      );

      await _plugin.initialize(
        settings,
        onDidReceiveNotificationResponse: _handleResponse,
      );

      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        // Canal de alta importancia con sonido y vibración.
        await android.createNotificationChannel(
          const AndroidNotificationChannel(
            channelId,
            channelName,
            description: channelDescription,
            importance: Importance.max,
            playSound: true,
            enableVibration: true,
          ),
        );

        // Android 13+ requiere permiso explícito para notificaciones.
        final enabled = await android.areNotificationsEnabled();
        if (enabled != true) {
          await android.requestNotificationsPermission();
        }
      }

      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      await ios?.requestPermissions(alert: true, badge: true, sound: true);

      final macOS = _plugin.resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin>();
      await macOS?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (e) {
      debugPrint('No se pudo inicializar las notificaciones de pedidos: $e');
    }
  }

  void _handleResponse(NotificationResponse response) {
    final orderId = int.tryParse(response.payload ?? '');
    if (orderId == null) return;
    onOrderTap?.call(orderId);
  }

  /// Muestra (o actualiza) la notificación del pedido si [status] es uno de
  /// los estados que el cliente debe conocer.
  Future<void> notifyStatusChange(
    Map<String, dynamic> order,
    String status,
  ) async {
    final normalized = status.trim().toLowerCase();
    final rawId = order['id'];
    if (rawId is! int) return;

    final message = _messageFor(normalized, rawId, order);
    if (message == null) return;

    try {
      await _plugin.show(
        rawId,
        message.$1,
        message.$2,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: channelDescription,
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            category: AndroidNotificationCategory.status,
            ticker: message.$1,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: rawId.toString(),
      );
    } catch (e) {
      debugPrint('No se pudo mostrar la notificación del pedido $rawId: $e');
    }
  }

  (String, String)? _messageFor(
    String status,
    int orderId,
    Map<String, dynamic> order,
  ) {
    final deliveryType =
        (order['delivery_type'] ?? 'domicilio').toString().trim().toLowerCase();

    switch (status) {
      case 'en cocina':
        return (
          '🍳 Orden #$orderId en preparación',
          "La cocina de K'OTEMAL ya está preparando tu pedido.",
        );
      case 'listo':
        return (
          '✅ ¡Orden #$orderId lista!',
          deliveryType == 'para_llevar'
              ? 'Tu pedido está listo para recoger en mostrador.'
              : 'Tu pedido ya está listo.',
        );
      case 'en camino':
        return (
          '🛵 ¡Orden #$orderId va en camino!',
          'El repartidor va rumbo a tu dirección. Toca para verlo en el mapa.',
        );
      case 'entregado':
        return (
          '🎉 Orden #$orderId entregada',
          "¡Buen provecho! Gracias por pedir en K'OTEMAL.",
        );
      default:
        return null;
    }
  }
}
