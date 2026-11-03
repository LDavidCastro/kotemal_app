import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class DeviceIdService {
  static const String _key = 'kotemal_unique_device_id';

  static Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_key);
    if (existing != null && existing.isNotEmpty) return existing;

    final randomPart = Random.secure().nextInt(0x7fffffff).toRadixString(16);
    final deviceId = 'dev_${DateTime.now().millisecondsSinceEpoch}_$randomPart';

    await prefs.setString(_key, deviceId);
    return deviceId;
  }
}
