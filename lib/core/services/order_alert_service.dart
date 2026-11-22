import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OrderAlertService extends ChangeNotifier {
  OrderAlertService._();

  static final OrderAlertService instance = OrderAlertService._();

  static const MethodChannel _ringtoneChannel =
      MethodChannel('kotemal/ringtones');

  static const _soundEnabledKey = 'cocina_sound_enabled';
  static const _alertModeKey = 'cocina_alert_mode';
  static const _ringtoneUriKey = 'cocina_ringtone_uri';
  static const _ringtoneTitleKey = 'cocina_ringtone_title';
  static const _voiceNameKey = 'cocina_voice_name';

  static const _priorityVoices = [
    'es-us-x-esd-local',
    'es-es-x-eec-network',
    'es-us-x-esd-network',
    'es-us-x-sfb-network',
  ];

  final FlutterTts _flutterTts = FlutterTts();

  bool _initialized = false;
  Future<void>? _initFuture;

  bool _soundEnabled = true;
  String _alertMode = 'ambos';
  String? _selectedRingtoneUri;
  String _selectedRingtoneTitle = 'Predeterminado';
  String? _selectedVoiceName = 'es-us-x-esd-local';
  List<Map<String, String>> _availableRingtones = [];
  List<Map<String, String>> _availableVoices = [];

  bool get soundEnabled => _soundEnabled;
  String get alertMode => _alertMode;
  String? get selectedRingtoneUri => _selectedRingtoneUri;
  String get selectedRingtoneTitle => _selectedRingtoneTitle;
  String? get selectedVoiceName => _selectedVoiceName;
  List<Map<String, String>> get availableRingtones => _availableRingtones;
  List<Map<String, String>> get availableVoices => _availableVoices;

  Future<void> init() async {
    if (_initialized) return;
    final pending = _initFuture;
    if (pending != null) return pending;
    _initFuture = _init();
    await _initFuture;
    _initialized = true;
  }

  Future<void> _init() async {
    try {
      await _loadAlertPreferences();
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);

      await _loadRingtones();
      await _loadVoices();
      await _applySelectedVoice();
      notifyListeners();
    } catch (_) {
      // Se mantienen los valores por defecto.
    }
  }

  Future<void> _loadAlertPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _soundEnabled = prefs.getBool(_soundEnabledKey) ?? true;
      _alertMode = prefs.getString(_alertModeKey) ?? 'ambos';
      _selectedRingtoneUri = prefs.getString(_ringtoneUriKey);
      _selectedRingtoneTitle =
          prefs.getString(_ringtoneTitleKey) ?? 'Predeterminado';
      _selectedVoiceName =
          prefs.getString(_voiceNameKey) ?? 'es-us-x-esd-local';
    } catch (_) {
      // Se mantienen los valores por defecto.
    }
  }

  Future<void> _loadRingtones() async {
    try {
      final tones = await _ringtoneChannel
          .invokeListMethod<Map<dynamic, dynamic>>('getNotificationRingtones');
      if (tones != null && tones.isNotEmpty) {
        final mapped = tones.map((t) => {
              'title': (t['title'] ?? '').toString(),
              'uri': (t['uri'] ?? '').toString(),
            }).toList();
        _availableRingtones = [
          {'title': 'Predeterminado', 'uri': ''},
          ...mapped,
        ];
      } else {
        _availableRingtones = [
          {'title': 'Predeterminado', 'uri': ''},
        ];
      }
    } catch (_) {
      _availableRingtones = [
        {'title': 'Predeterminado', 'uri': ''},
      ];
    }
  }

  Future<void> _loadVoices() async {
    try {
      final dynamic rawVoices = await _flutterTts.getVoices;
      if (rawVoices is List) {
        final esVoices = <Map<String, String>>[];
        for (final item in rawVoices) {
          if (item is Map) {
            final name = item['name']?.toString() ?? '';
            final locale = item['locale']?.toString() ?? '';
            if (locale.toLowerCase().startsWith('es')) {
              esVoices.add({
                'name': name,
                'locale': locale,
                'label': getVoiceFriendlyLabel(name, locale),
              });
            }
          }
        }

        esVoices.sort((a, b) {
          final idxA = _priorityVoices.indexOf(a['name']!.toLowerCase());
          final idxB = _priorityVoices.indexOf(b['name']!.toLowerCase());
          final pA = idxA >= 0 ? idxA : 999;
          final pB = idxB >= 0 ? idxB : 999;
          if (pA != pB) return pA.compareTo(pB);
          return a['label']!.compareTo(b['label']!);
        });

        if (esVoices.isNotEmpty) {
          _availableVoices = esVoices;
        }
      }
    } catch (_) {}

    if (_availableVoices.isEmpty) {
      _availableVoices = [
        {
          'name': 'es-us-x-esd-local',
          'locale': 'es-US',
          'label': 'Voz EE.UU. Local (es-us-x-esd-local)',
        },
        {
          'name': 'es-es-x-eec-network',
          'locale': 'es-ES',
          'label': 'Voz España Red (es-es-x-eec-network)',
        },
        {
          'name': 'es-us-x-esd-network',
          'locale': 'es-US',
          'label': 'Voz EE.UU. Red (es-us-x-esd-network)',
        },
        {
          'name': 'es-us-x-sfb-network',
          'locale': 'es-US',
          'label': 'Voz EE.UU. Red 2 (es-us-x-sfb-network)',
        },
      ];
    }
  }

  Map<String, String>? _findSelectedVoice() {
    if (_selectedVoiceName == null) return null;
    for (final voice in _availableVoices) {
      if (voice['name']?.toLowerCase() == _selectedVoiceName?.toLowerCase()) {
        return voice;
      }
    }
    return null;
  }

  Future<void> _applySelectedVoice() async {
    final voice = _findSelectedVoice() ??
        (_availableVoices.isNotEmpty ? _availableVoices.first : null);
    if (voice == null) return;
    _selectedVoiceName = voice['name'];
    try {
      await _flutterTts.setVoice({
        'name': voice['name']!,
        'locale': voice['locale']!,
      });
    } catch (_) {
      try {
        await _flutterTts.setLanguage('es-MX');
      } catch (_) {}
    }
  }

  String getVoiceFriendlyLabel(String name, String locale) {
    final lower = name.toLowerCase();
    if (lower == 'es-us-x-esd-local') {
      return 'Voz EE.UU. Local (es-us-x-esd-local)';
    } else if (lower == 'es-es-x-eec-network') {
      return 'Voz España Red (es-es-x-eec-network)';
    } else if (lower == 'es-us-x-esd-network') {
      return 'Voz EE.UU. Red (es-us-x-esd-network)';
    } else if (lower == 'es-us-x-sfb-network') {
      return 'Voz EE.UU. Red 2 (es-us-x-sfb-network)';
    }

    final isNetwork = lower.contains('network');
    final isLocal = lower.contains('local');
    final typeSuffix = isNetwork
        ? ' (Red)'
        : isLocal
            ? ' (Local)'
            : '';

    final loc = locale.toLowerCase();
    String country = 'Español';
    if (loc.contains('mx')) {
      country = 'México';
    } else if (loc.contains('es')) {
      country = 'España';
    } else if (loc.contains('us')) {
      country = 'EE.UU.';
    } else if (loc.contains('gt')) {
      country = 'Guatemala';
    } else if (loc.contains('co')) {
      country = 'Colombia';
    } else if (loc.contains('ar')) {
      country = 'Argentina';
    }

    return 'Voz $country$typeSuffix ($name)';
  }

  Future<void> toggleSound() async {
    _soundEnabled = !_soundEnabled;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_soundEnabledKey, _soundEnabled);
    } catch (_) {}
  }

  Future<void> setAlertMode(String mode) async {
    _alertMode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_alertModeKey, mode);
    } catch (_) {}
  }

  Future<void> setRingtone(String? uri, String title) async {
    _selectedRingtoneUri = uri;
    _selectedRingtoneTitle = title;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (uri == null || uri.isEmpty) {
        await prefs.remove(_ringtoneUriKey);
      } else {
        await prefs.setString(_ringtoneUriKey, uri);
      }
      await prefs.setString(_ringtoneTitleKey, title);
    } catch (_) {}
  }

  Future<void> setVoice(String voiceName) async {
    _selectedVoiceName = voiceName;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_voiceNameKey, voiceName);
    } catch (_) {}
  }

  Future<void> previewRingtone(String? uri) async {
    final tone = _availableRingtones.firstWhere(
      (t) => (t['uri'] ?? '') == (uri ?? ''),
      orElse: () => {'title': 'Predeterminado', 'uri': uri ?? ''},
    );
    await setRingtone(uri, tone['title'] ?? 'Predeterminado');
    try {
      await _ringtoneChannel.invokeMethod('playRingtone', {'uri': uri});
    } catch (_) {
      await SystemSound.play(SystemSoundType.alert);
    }
  }

  Future<void> previewVoice(Map<String, String> voice) async {
    final name = voice['name'];
    if (name == null) return;
    await setVoice(name);
    try {
      await _flutterTts.stop();
      await _flutterTts.setVoice({
        'name': name,
        'locale': voice['locale'] ?? 'es-US',
      });
      await _flutterTts.speak('Nuevo pedido recibido en cocina');
    } catch (_) {}
  }

  Future<void> announceCustom({
    required String message,
    bool ignoreMute = false,
  }) async {
    if (!ignoreMute && !_soundEnabled) return;

    final playTone = _alertMode == 'tono' || _alertMode == 'ambos';
    final speak = _alertMode == 'voz' || _alertMode == 'ambos';

    if (playTone) {
      try {
        await _ringtoneChannel.invokeMethod('playRingtone', {
          'uri': _selectedRingtoneUri,
        });
      } catch (_) {
        await SystemSound.play(SystemSoundType.alert);
      }
    }

    if (speak) {
      if (playTone) {
        await Future.delayed(const Duration(milliseconds: 650));
      }
      try {
        await _flutterTts.stop();
        await _applySelectedVoice();
        await _flutterTts.speak(message);
      } catch (_) {}
    }
  }

  String _orderModality(Map<String, dynamic> order) {
    final deliveryType = (order['delivery_type'] ?? 'domicilio').toString();
    final tableNumber = order['table_number']?.toString() ?? '';
    return switch (deliveryType) {
      'local' => 'para mesa #$tableNumber',
      'para_llevar' => 'para llevar',
      _ => 'a domicilio',
    };
  }

  Future<void> announceKitchenOrder(Map<String, dynamic> order) async {
    final rawCustomerName = (order['customer_name'] ?? '').toString().trim();
    final customerName =
        rawCustomerName.isEmpty ? 'cliente sin nombre' : rawCustomerName;

    final message =
        'Nuevo pedido, orden ${order['id']}, '
        'a nombre de $customerName, ${_orderModality(order)}';

    await announceCustom(message: message);
  }
}
