import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'guest_orders_service.dart';
import 'order_alert_service.dart';

class OrderBackgroundMonitor with WidgetsBindingObserver {
  OrderBackgroundMonitor._();

  static final OrderBackgroundMonitor instance = OrderBackgroundMonitor._();

  static const MethodChannel _channel =
      MethodChannel('kotemal/background_alerts');

  bool _started = false;
  String? _role;
  String? _currentUserId;
  Set<int> _guestOrderIds = <int>{};
  Set<int> _knownOrderIds = <int>{};
  final Map<int, String> _lastOrderStatuses = <int, String>{};
  bool _initialOrdersLoaded = false;
  StreamSubscription<List<Map<String, dynamic>>>? _subscription;
  Timer? _backgroundPollTimer;
  bool _observerRegistered = false;
  int _alertCounter = 0;

  bool get _isKitchenRole =>
      _role == 'admin' || _role == 'cocina' || _role == 'cocinero';

  bool get _isWorkerRole => _isKitchenRole || _role == 'repartidor';

  Future<void> start() async {
    if (_started) return;
    _started = true;

    if (!_observerRegistered) {
      WidgetsBinding.instance.addObserver(this);
      _observerRegistered = true;
    }

    await OrderAlertService.instance.init();
    await _configureSession();
    _subscribe();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _startBackgroundPolling();
    } else if (state == AppLifecycleState.resumed) {
      _stopBackgroundPolling();
    }
  }

  void _startBackgroundPolling() {
    if (!_isWorkerRole) return;
    if (_backgroundPollTimer != null) return;
    _backgroundPollTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _pollOrdersInBackground(),
    );
  }

  void _stopBackgroundPolling() {
    _backgroundPollTimer?.cancel();
    _backgroundPollTimer = null;
  }

  Future<void> _pollOrdersInBackground() async {
    if (!_isWorkerRole) return;

    try {
      final orders = await Supabase.instance.client
          .from('orders')
          .select()
          .order('id', ascending: false)
          .limit(20);

      final alertsBefore = _alertCounter;
      await _onOrders(orders);

      if (_alertCounter != alertsBefore) {
        await _nativePing();
      }
    } catch (e) {
      debugPrint('Error en polling de pedidos en segundo plano: $e');
    }
  }

  Future<void> _nativePing() async {
    try {
      await _channel.invokeMethod('pingAlert');
    } catch (_) {}
  }

  /// Re-evalúa el rol y los pedidos guardados cuando cambia la sesión.
  Future<void> refreshSession() async {
    if (!_started) {
      await start();
      return;
    }

    final previousUserId = _currentUserId;
    final previousRole = _role;
    await _configureSession();

    if (previousUserId != _currentUserId || previousRole != _role) {
      await _subscription?.cancel();
      _subscription = null;
      _knownOrderIds.clear();
      _lastOrderStatuses.clear();
      _initialOrdersLoaded = false;
      _subscribe();
    }
  }

  Future<void> _configureSession() async {
    final user = Supabase.instance.client.auth.currentUser;
    var role = 'cliente';

    if (user != null) {
      try {
        final res = await Supabase.instance.client
            .from('profiles')
            .select('role')
            .eq('id', user.id)
            .maybeSingle();
        role = (res?['role']?.toString() ?? 'cliente').trim().toLowerCase();
      } catch (_) {
        role = 'cliente';
      }
    }

    _role = role;
    _currentUserId = user?.id;

    try {
      _guestOrderIds = (await GuestOrdersService.getSavedOrderIds()).toSet();
    } catch (_) {
      _guestOrderIds = <int>{};
    }

    if (_isWorkerRole) {
      await _requestWorkerPermissions();
    } else {
      _stopBackgroundPolling();
      await _stopWorkerService();
    }
  }

  Future<void> _requestWorkerPermissions() async {
    try {
      await Permission.notification.request();
    } catch (_) {}

    try {
      if (!await Permission.ignoreBatteryOptimizations.isGranted) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (_) {}

    try {
      await _channel.invokeMethod('startBackgroundService');
    } catch (_) {}
  }

  Future<void> _stopWorkerService() async {
    try {
      await _channel.invokeMethod('stopBackgroundService');
    } catch (_) {}
  }

  void _subscribe() {
    if (_subscription != null) return;
    _subscription = Supabase.instance.client
        .from('orders')
        .stream(primaryKey: ['id'])
        .order('id', ascending: false)
        .listen(
          _onOrders,
          onError: (Object e) =>
              debugPrint('Error en monitor global de pedidos: $e'),
        );
  }

  Future<void> _onOrders(List<Map<String, dynamic>> orders) async {
    if (_role == 'cliente' && _currentUserId == null) {
      try {
        _guestOrderIds = (await GuestOrdersService.getSavedOrderIds()).toSet();
      } catch (_) {}
    }

    if (!_initialOrdersLoaded) {
      _knownOrderIds = {
        for (final order in orders)
          if (order['id'] is int) order['id'] as int,
      };
      for (final order in orders) {
        final id = order['id'];
        if (id is int) {
          _lastOrderStatuses[id] = (order['status'] ?? '').toString();
        }
      }
      _initialOrdersLoaded = true;
      return;
    }

    for (final order in orders) {
      final id = order['id'];
      if (id is! int) continue;

      final status = (order['status'] ?? '').toString().trim().toLowerCase();
      final previousStatus = _lastOrderStatuses[id];
      final isNew = !_knownOrderIds.contains(id);
      final isDelivery =
          (order['delivery_type'] ?? 'domicilio') == 'domicilio';
      final driverId = order['delivery_driver_id'];
      final rawCustomerName = (order['customer_name'] ?? '').toString().trim();
      final customerName =
          rawCustomerName.isEmpty ? 'cliente sin nombre' : rawCustomerName;

      if (_isKitchenRole) {
        if (isNew && status == 'pendiente') {
          OrderAlertService.instance.announceKitchenOrder(order);
          _alertCounter++;
        }
      } else if (_role == 'repartidor') {
        if (isDelivery &&
            isNew &&
            (status == 'pendiente' ||
                status == 'en cocina' ||
                status == 'listo') &&
            driverId == null) {
          OrderAlertService.instance.announceCustom(
            message:
                'Nuevo pedido a domicilio, orden $id, a nombre de $customerName',
          );
          _alertCounter++;
        }

        final previousStatusLower =
            (previousStatus ?? '').toString().trim().toLowerCase();

        if (isDelivery &&
            previousStatusLower != 'listo' &&
            status == 'listo' &&
            (driverId == null || driverId == _currentUserId)) {
          OrderAlertService.instance.announceCustom(
            message:
                '¡Orden número $id de $customerName está lista para recoger!',
          );
          _alertCounter++;
        }
      } else {
        final isMine = (_currentUserId != null &&
                order['customer_id'] == _currentUserId) ||
            _guestOrderIds.contains(id);

        if (isMine && previousStatus != status) {
          if (!isDelivery && status == 'listo') {
            OrderAlertService.instance.announceCustom(
              message: '¡Tu orden número $id ya está lista!',
            );
            _alertCounter++;
          } else if (isDelivery && status == 'en camino') {
            OrderAlertService.instance.announceCustom(
              message:
                  '¡Tu repartidor ya va en camino con tu orden número $id!',
            );
            _alertCounter++;
          } else if (status == 'entregado') {
            OrderAlertService.instance.previewRingtone(
              OrderAlertService.instance.selectedRingtoneUri,
            );
            _alertCounter++;
          }
        }
      }
    }

    _knownOrderIds = {
      ..._knownOrderIds,
      for (final order in orders)
        if (order['id'] is int) order['id'] as int,
    };
    for (final order in orders) {
      final id = order['id'];
      if (id is int) {
        _lastOrderStatuses[id] = (order['status'] ?? '').toString();
      }
    }
  }
}
