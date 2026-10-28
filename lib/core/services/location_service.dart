import 'package:geolocator/geolocator.dart';

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

  static String getGoogleMapsUrl(double lat, double lng) =>
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng';

  static String getWazeUrl(double lat, double lng) =>
      'https://waze.com/ul?ll=$lat,$lng&navigate=yes';
}