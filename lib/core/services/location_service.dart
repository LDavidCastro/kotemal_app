import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RouteResult {
  final List<LatLng> points;
  final int durationMinutes;
  final double distanceKm;

  const RouteResult({
    required this.points,
    required this.durationMinutes,
    required this.distanceKm,
  });
}

class LocationService {
  /// Obtiene la posición GPS actual validando permisos y precisión
  Future<Position> getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Los servicios de ubicación están desactivados.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Permisos de ubicación denegados.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Permisos de ubicación denegados permanentemente. Actívalos en Ajustes.',
      );
    }

    // Parámetros directos compatibles con tu versión de geolocator
    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 15),
    );
  }

  /// Obtiene la ruta de conducción real entre dos puntos usando OSRM.
  Future<RouteResult> getDrivingRoute(
    LatLng origin,
    LatLng destination,
  ) async {
    final fallback = RouteResult(
      points: [origin, destination],
      durationMinutes: 0,
      distanceKm: 0,
    );

    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${origin.longitude},${origin.latitude};'
        '${destination.longitude},${destination.latitude}'
        '?overview=full&geometries=geojson',
      );

      final response = await http.get(url).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final routes = data['routes'] as List?;
        if (routes == null || routes.isEmpty) return fallback;

        final route = routes.first as Map<String, dynamic>;
        final geometry = route['geometry'] as Map<String, dynamic>?;
        final coordinates = geometry?['coordinates'] as List?;
        if (coordinates == null || coordinates.isEmpty) return fallback;

        final points = coordinates.map((coord) {
          final pair = coord as List;
          return LatLng(
            (pair[1] as num).toDouble(),
            (pair[0] as num).toDouble(),
          );
        }).toList();

        final durationSeconds = (route['duration'] as num?)?.toDouble() ?? 0;
        final distanceMeters = (route['distance'] as num?)?.toDouble() ?? 0;
        final durationMinutes = (durationSeconds / 60).round();

        return RouteResult(
          points: points,
          durationMinutes: durationMinutes < 1 ? 1 : durationMinutes,
          distanceKm: distanceMeters / 1000,
        );
      }
    } catch (_) {
      // Timeout, red o respuesta inválida: se usa la ruta de respaldo.
    }

    return fallback;
  }

  static String getGoogleMapsUrl(double lat, double lng) =>
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng';

  static String getWazeUrl(double lat, double lng) =>
      'https://waze.com/ul?ll=$lat,$lng&navigate=yes';
}