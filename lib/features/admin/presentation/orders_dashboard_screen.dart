import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/services/location_service.dart';
import '../../../core/utils/formatters.dart';

class OrdersDashboardScreen extends StatefulWidget {
  const OrdersDashboardScreen({super.key});

  @override
  State<OrdersDashboardScreen> createState() => _OrdersDashboardScreenState();
}

class _OrdersDashboardScreenState extends State<OrdersDashboardScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  late final TabController _tabController;
  bool _isAdmin = false;

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

  late final FlutterTts _flutterTts;
  bool _soundEnabled = true;
  String _alertMode = 'ambos';
  String? _selectedRingtoneUri;
  String _selectedRingtoneTitle = 'Predeterminado';
  String? _selectedVoiceName = 'es-us-x-esd-local';
  List<Map<String, String>> _availableRingtones = [];
  List<Map<String, String>> _availableVoices = [];

  Set<int> _knownOrderIds = {};
  bool _initialOrdersLoaded = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _flutterTts = FlutterTts();
    _initAudio();
    _checkRole();
  }

  @override
  void dispose() {
    _flutterTts.stop();
    _tabController.dispose();
    super.dispose();
  }

  String _getVoiceFriendlyLabel(String name, String locale) {
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

  Future<void> _initAudio() async {
    try {
      await _loadAlertPreferences();
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);

      // 1. Cargar tonos nativos desde el canal de Android
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

      // 2. Cargar voces instaladas desde FlutterTts
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
                  'label': _getVoiceFriendlyLabel(name, locale),
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

      // Aplicar voz configurada o preferida
      Map<String, String>? voiceToApply;
      if (_selectedVoiceName != null) {
        voiceToApply = _availableVoices.cast<Map<String, String>?>().firstWhere(
              (v) =>
                  v?['name']?.toLowerCase() ==
                  _selectedVoiceName?.toLowerCase(),
              orElse: () => null,
            );
      }
      voiceToApply ??= _availableVoices.first;
      _selectedVoiceName = voiceToApply['name'];

      try {
        await _flutterTts.setVoice({
          'name': voiceToApply['name']!,
          'locale': voiceToApply['locale']!,
        });
      } catch (_) {
        await _flutterTts.setLanguage('es-MX');
      }
    } catch (_) {}
  }

  Future<void> _loadAlertPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _soundEnabled = prefs.getBool(_soundEnabledKey) ?? true;
        _alertMode = prefs.getString(_alertModeKey) ?? 'ambos';
        _selectedRingtoneUri = prefs.getString(_ringtoneUriKey);
        _selectedRingtoneTitle =
            prefs.getString(_ringtoneTitleKey) ?? 'Predeterminado';
        _selectedVoiceName =
            prefs.getString(_voiceNameKey) ?? 'es-us-x-esd-local';
      });
    } catch (_) {
      // Se mantienen los valores por defecto.
    }
  }

  Future<void> _toggleSound() async {
    final enabled = !_soundEnabled;
    setState(() => _soundEnabled = enabled);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_soundEnabledKey, enabled);
    } catch (_) {}
  }

  Future<void> _setAlertMode(String mode) async {
    setState(() => _alertMode = mode);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_alertModeKey, mode);
    } catch (_) {}
  }

  Future<void> _setRingtone(String? uri, String title) async {
    setState(() {
      _selectedRingtoneUri = uri;
      _selectedRingtoneTitle = title;
    });
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

  Future<void> _setVoice(String voiceName) async {
    setState(() => _selectedVoiceName = voiceName);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_voiceNameKey, voiceName);
    } catch (_) {}
  }

  String _orderModality(Map<String, dynamic> order) {
    final deliveryType = (order['delivery_type'] ?? 'domicilio').toString();
    final tableNumber = order['table_number']?.toString() ?? '';
    return switch (deliveryType) {
      'local' => 'para mesa $tableNumber',
      'para_llevar' => 'para llevar',
      _ => 'a domicilio',
    };
  }

  Future<void> _announceOrder(Map<String, dynamic> order) async {
    if (!_soundEnabled) return;

    final rawCustomerName = (order['customer_name'] ?? '').toString().trim();
    final customerName =
        rawCustomerName.isEmpty ? 'cliente sin nombre' : rawCustomerName;

    final message =
        'Nuevo pedido, orden ${order['id']}, '
        'a nombre de $customerName, ${_orderModality(order)}';

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
        await Future.delayed(const Duration(milliseconds: 600));
      }
      try {
        await _flutterTts.stop();
        if (_selectedVoiceName != null) {
          final voice =
              _availableVoices.cast<Map<String, String>?>().firstWhere(
                    (v) =>
                        v?['name']?.toLowerCase() ==
                        _selectedVoiceName?.toLowerCase(),
                    orElse: () => null,
                  );
          if (voice != null) {
            await _flutterTts.setVoice({
              'name': voice['name']!,
              'locale': voice['locale']!,
            });
          }
        }
        await _flutterTts.speak(message);
      } catch (_) {}
    }
  }

  void _handleIncomingOrders(List<Map<String, dynamic>> orders) {
    if (!_initialOrdersLoaded) {
      _knownOrderIds = {
        for (final order in orders)
          if (order['id'] is int) order['id'] as int,
      };
      _initialOrdersLoaded = true;
      return;
    }

    final newOrders = <Map<String, dynamic>>[];
    for (final order in orders) {
      final id = order['id'];
      if (id is! int || _knownOrderIds.contains(id)) continue;
      _knownOrderIds.add(id);
      if (order['status'] == 'pendiente') {
        newOrders.add(order);
      }
    }

    if (newOrders.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final order in newOrders) {
        _announceOrder(order);
      }
    });
  }

  Future<void> _showAlertSettings() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          Future<void> selectMode(String mode) async {
            await _setAlertMode(mode);
            setSheetState(() {});
          }

          Future<void> previewTone(String? uri, String title) async {
            await _setRingtone(uri, title);
            setSheetState(() {});
            try {
              await _ringtoneChannel
                  .invokeMethod('playRingtone', {'uri': uri});
            } catch (_) {
              await SystemSound.play(SystemSoundType.alert);
            }
          }

          Future<void> previewVoice(Map<String, String> voice) async {
            await _setVoice(voice['name']!);
            setSheetState(() {});
            try {
              await _flutterTts.stop();
              await _flutterTts.setVoice({
                'name': voice['name']!,
                'locale': voice['locale']!,
              });
              await _flutterTts.speak('Nuevo pedido recibido en cocina');
            } catch (_) {}
          }

          Future<void> testFullAlert() async {
            try {
              await _ringtoneChannel.invokeMethod('playRingtone', {
                'uri': _selectedRingtoneUri,
              });
            } catch (_) {
              await SystemSound.play(SystemSoundType.alert);
            }
            await Future.delayed(const Duration(milliseconds: 650));
            try {
              await _flutterTts.stop();
              if (_selectedVoiceName != null) {
                final voice =
                    _availableVoices.cast<Map<String, String>?>().firstWhere(
                          (v) =>
                              v?['name']?.toLowerCase() ==
                              _selectedVoiceName?.toLowerCase(),
                          orElse: () => null,
                        );
                if (voice != null) {
                  await _flutterTts.setVoice({
                    'name': voice['name']!,
                    'locale': voice['locale']!,
                  });
                }
              }
              await _flutterTts.speak(
                'Nuevo pedido, orden 101, a nombre de Juan Pérez, para mesa 4',
              );
            } catch (_) {}
          }

          Widget modeOption({
            required String mode,
            required IconData icon,
            required String title,
            required String subtitle,
          }) {
            final selected = _alertMode == mode;
            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => selectMode(mode),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: selected ? Colors.deepOrange.shade50 : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? Colors.deepOrange : Colors.grey.shade300,
                    width: selected ? 1.5 : 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      icon,
                      color:
                          selected ? Colors.deepOrange : Colors.grey.shade700,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: selected
                                  ? Colors.deepOrange.shade900
                                  : Colors.black87,
                            ),
                          ),
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (selected)
                      const Icon(
                        Icons.check_circle,
                        color: Colors.deepOrange,
                        size: 20,
                      ),
                  ],
                ),
              ),
            );
          }

          return Container(
            height: MediaQuery.of(ctx).size.height * 0.90,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                // Barra superior de arrastre
                Container(
                  width: 44,
                  height: 5,
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 12, 10),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Configuración de Alertas',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Personaliza el tono y la voz para nuevos pedidos',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
                    children: [
                      // SECCIÓN 1: MODO DE ALERTA
                      const Row(
                        children: [
                          Icon(Icons.tune, size: 18, color: Colors.deepOrange),
                          SizedBox(width: 6),
                          Text(
                            '1. Modo de alerta',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      modeOption(
                        mode: 'ambos',
                        icon: Icons.notifications_active,
                        title: 'Tono + Voz',
                        subtitle:
                            'Suena el tono elegido y anuncia los detalles por voz.',
                      ),
                      modeOption(
                        mode: 'voz',
                        icon: Icons.record_voice_over,
                        title: 'Solo Voz',
                        subtitle:
                            'Anuncia el pedido por voz sin reproducir tono.',
                      ),
                      modeOption(
                        mode: 'tono',
                        icon: Icons.volume_up,
                        title: 'Solo Tono',
                        subtitle: 'Reproduce únicamente el tono del sistema.',
                      ),

                      const SizedBox(height: 18),

                      // SECCIÓN 2: SELECTOR DE TONO
                      Row(
                        children: [
                          const Icon(
                            Icons.music_note,
                            size: 18,
                            color: Colors.deepOrange,
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            '2. Tono de Notificación',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${_availableRingtones.length} disponibles',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 2, bottom: 8),
                        child: Text(
                          'Actual: $_selectedRingtoneTitle (toca para escuchar y elegir)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.deepOrange.shade800,
                          ),
                        ),
                      ),
                      Container(
                        height: 200,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: _availableRingtones.isEmpty
                            ? const Center(
                                child: Text(
                                  'No se detectaron tonos en el dispositivo.',
                                ),
                              )
                            : ListView.separated(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                itemCount: _availableRingtones.length,
                                separatorBuilder: (_, _) => Divider(
                                  height: 1,
                                  color: Colors.grey.shade200,
                                ),
                                itemBuilder: (context, i) {
                                  final tone = _availableRingtones[i];
                                  final uri = tone['uri'];
                                  final title = tone['title'] ?? 'Tono';
                                  final isSelected =
                                      (_selectedRingtoneUri == uri &&
                                              (uri != null &&
                                                  uri.isNotEmpty)) ||
                                          (_selectedRingtoneTitle == title);

                                  return ListTile(
                                    dense: true,
                                    visualDensity: VisualDensity.compact,
                                    leading: Icon(
                                      isSelected
                                          ? Icons.volume_up
                                          : Icons.music_note,
                                      color: isSelected
                                          ? Colors.deepOrange
                                          : Colors.grey.shade600,
                                      size: 20,
                                    ),
                                    title: Text(
                                      title,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: isSelected
                                            ? Colors.deepOrange.shade900
                                            : Colors.black87,
                                      ),
                                    ),
                                    trailing: isSelected
                                        ? const Icon(
                                            Icons.check_circle,
                                            color: Colors.deepOrange,
                                            size: 20,
                                          )
                                        : Icon(
                                            Icons.play_circle_outline,
                                            color: Colors.grey.shade500,
                                            size: 20,
                                          ),
                                    onTap: () => previewTone(uri, title),
                                  );
                                },
                              ),
                      ),

                      const SizedBox(height: 18),

                      // SECCIÓN 3: SELECTOR DE VOZ
                      Row(
                        children: [
                          const Icon(
                            Icons.record_voice_over,
                            size: 18,
                            color: Colors.deepOrange,
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            '3. Voz en Español (Google TTS)',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${_availableVoices.length} disponibles',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 2, bottom: 8),
                        child: Text(
                          'Voz activa: ${_selectedVoiceName ?? 'Predeterminada'} (toca para probar)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.deepOrange.shade800,
                          ),
                        ),
                      ),
                      Container(
                        height: 200,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: _availableVoices.isEmpty
                            ? const Center(
                                child: Text(
                                  'No se detectaron voces en español.',
                                ),
                              )
                            : ListView.separated(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                itemCount: _availableVoices.length,
                                separatorBuilder: (_, _) => Divider(
                                  height: 1,
                                  color: Colors.grey.shade200,
                                ),
                                itemBuilder: (context, i) {
                                  final voice = _availableVoices[i];
                                  final name = voice['name'] ?? '';
                                  final label = voice['label'] ?? name;
                                  final isSelected = name.toLowerCase() ==
                                      _selectedVoiceName?.toLowerCase();

                                  return ListTile(
                                    dense: true,
                                    visualDensity: VisualDensity.compact,
                                    leading: Icon(
                                      isSelected
                                          ? Icons.record_voice_over
                                          : Icons.mic_none,
                                      color: isSelected
                                          ? Colors.deepOrange
                                          : Colors.grey.shade600,
                                      size: 20,
                                    ),
                                    title: Text(
                                      label,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: isSelected
                                            ? Colors.deepOrange.shade900
                                            : Colors.black87,
                                      ),
                                    ),
                                    subtitle: Text(
                                      name,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    trailing: isSelected
                                        ? const Icon(
                                            Icons.check_circle,
                                            color: Colors.deepOrange,
                                            size: 20,
                                          )
                                        : Icon(
                                            Icons.play_circle_outline,
                                            color: Colors.grey.shade500,
                                            size: 20,
                                          ),
                                    onTap: () => previewVoice(voice),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),

                // SECCIÓN 4: BOTÓN PROBAR ALERTA COMPLETA
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border:
                        Border(top: BorderSide(color: Colors.grey.shade200)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 8,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    top: false,
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepOrange,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: testFullAlert,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text(
                          'Probar alerta completa',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _navigateToStatusTab(String status) {
    final index = switch (status) {
      'pendiente' => 0,
      'en cocina' => 1,
      'listo' => 2,
      'en camino' => 3,
      'entregado' || 'cancelado' => 4,
      _ => null,
    };

    if (index != null && _tabController.index != index) {
      _tabController.animateTo(index);
    }
  }

  Future<void> _checkRole() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      final res = await _supabase
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();

      if (mounted && res != null && res['role'] == 'admin') {
        setState(() => _isAdmin = true);
      }
    } catch (_) {
      // Si falla la consulta se mantiene el modo no-admin.
    }
  }

  Future<void> _updateStatus(int orderId, String newStatus) async {
    try {
      await _supabase
          .from('orders')
          .update({'status': newStatus})
          .eq('id', orderId);

      if (!mounted) return;
      _navigateToStatusTab(newStatus);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al actualizar estado: $e')),
        );
      }
    }
  }

  Future<void> _markAsPaid(int orderId, String method) async {
    try {
      await _supabase.from('orders').update({
        'status': 'entregado',
        'payment_status': 'pagado',
        'payment_method': method,
        'paid_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', orderId);

      if (!mounted) return;
      _navigateToStatusTab('entregado');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Orden #$orderId cobrada y entregada '
            '(${method == 'efectivo' ? 'Efectivo' : 'Transferencia'}).',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al registrar el pago: $e')),
        );
      }
    }
  }

  Future<void> _showPaymentMethodSheet(int orderId) async {
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Método de pago - Orden #$orderId',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  child: Icon(Icons.payments),
                ),
                title: const Text('Efectivo'),
                onTap: () {
                  Navigator.pop(ctx);
                  _markAsPaid(orderId, 'efectivo');
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  child: Icon(Icons.account_balance),
                ),
                title: const Text('Transferencia'),
                onTap: () {
                  Navigator.pop(ctx);
                  _markAsPaid(orderId, 'transferencia');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openNavigation(double? lat, double? lng) async {
    if (lat == null || lng == null) return;
    final url = Uri.parse(LocationService.getGoogleMapsUrl(lat, lng));
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  // Menú de opciones de contacto: Llamada telefónica o WhatsApp
  Future<void> _showContactOptions(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'\D'), ''); // Elimina espacios o guiones
    if (cleanPhone.isEmpty) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Contactar al Cliente ($phone)',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  child: Icon(Icons.call),
                ),
                title: const Text('Llamar por Teléfono'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final uri = Uri.parse('tel:$cleanPhone');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri);
                  }
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  child: Icon(Icons.chat),
                ),
                title: const Text('Escribir por WhatsApp'),
                onTap: () async {
                  Navigator.pop(ctx);
                  // Prefijo de Guatemala (+502) si tiene 8 dígitos
                  final waNumber = cleanPhone.length == 8 ? '502$cleanPhone' : cleanPhone;
                  final uri = Uri.parse('https://wa.me/$waNumber?text=Hola,%20nos%20comunicamos%20de%20K\'OTEMAL%20sobre%20su%20pedido.');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Modal para ver los productos detallados que ordenó el cliente
  Future<void> _showOrderDetailsModal(
    int orderId,
    Map<String, dynamic> order,
  ) async {
    final deliveryType = (order['delivery_type'] ?? 'domicilio') as String;
    final tableNumber = order['table_number']?.toString() ?? '';
    final status = (order['status'] ?? 'pendiente') as String;
    final paymentStatus = (order['payment_status'] ?? 'pendiente') as String;
    final deliveryNotes = (order['delivery_notes'] ?? '').toString().trim();
    final rawCustomerName = (order['customer_name'] ?? '').toString().trim();
    final customerName =
        rawCustomerName.isEmpty ? 'Cliente sin nombre' : rawCustomerName;
    final hasDeliveryNotes =
        deliveryNotes.isNotEmpty && deliveryNotes != 'Sin referencias';
    final createdAt = order['created_at'] != null
        ? DateTime.tryParse(order['created_at'].toString())
        : null;

    final modeLabel = deliveryType == 'local'
        ? 'MESA #$tableNumber'
        : deliveryType == 'para_llevar'
            ? 'PARA LLEVAR'
            : 'DOMICILIO';
    final modeIcon = deliveryType == 'local'
        ? Icons.table_restaurant
        : deliveryType == 'para_llevar'
            ? Icons.takeout_dining
            : Icons.delivery_dining;

    String? nextStatus;
    String nextLabel = '';
    IconData nextIcon = Icons.arrow_forward;
    if (status == 'pendiente') {
      nextStatus = 'en cocina';
      nextLabel = 'Enviar a Cocina';
      nextIcon = Icons.soup_kitchen;
    } else if (status == 'en cocina') {
      nextStatus = 'listo';
      nextLabel = 'Marcar Listo';
      nextIcon = Icons.check_circle_outline;
    } else if (status == 'listo') {
      if (deliveryType == 'domicilio') {
        nextStatus = 'en camino';
        nextLabel = 'Marcar En Camino';
        nextIcon = Icons.two_wheeler;
      } else {
        nextStatus = 'entregado';
        nextLabel = 'Marcar Entregado';
        nextIcon = Icons.check_circle;
      }
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Color(0xFFFFFBF5),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 5,
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Orden #$orderId',
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.person,
                                    size: 18,
                                    color: Colors.deepOrange,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      customerName,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  _buildComandaBadge(
                                    icon: modeIcon,
                                    label: modeLabel,
                                    background: Colors.deepOrange.shade50,
                                    border: Colors.deepOrange.shade200,
                                    foreground: Colors.deepOrange.shade900,
                                  ),
                                  if (createdAt != null)
                                    _buildComandaBadge(
                                      icon: Icons.schedule,
                                      label: Formatters.dateTime(createdAt),
                                      background: Colors.grey.shade100,
                                      border: Colors.grey.shade300,
                                      foreground: Colors.grey.shade800,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    if (hasDeliveryNotes) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.amber.shade400),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.sticky_note_2,
                              size: 20,
                              color: Colors.amber.shade900,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                deliveryNotes,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.amber.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    Expanded(
                      child: FutureBuilder<List<Map<String, dynamic>>>(
                        future: _supabase
                            .from('order_items')
                            .select(
                              'quantity, unit_price, notes, '
                              'products(name, category)',
                            )
                            .eq('order_id', orderId),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }

                          if (snapshot.hasError) {
                            return Center(
                              child: Text('Error: ${snapshot.error}'),
                            );
                          }

                          final items = snapshot.data ?? [];

                          if (items.isEmpty) {
                            return const Center(
                              child: Text(
                                'No hay detalles registrados para esta orden.',
                              ),
                            );
                          }

                          return ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            itemCount: items.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, i) =>
                                _buildComandaItem(items[i]),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 10,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total a cobrar',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          Formatters.currency(
                            num.tryParse(order['total']?.toString() ?? '') ?? 0,
                          ),
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                    if (nextStatus != null) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepOrange,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () async {
                            Navigator.pop(ctx);
                            if (nextStatus == 'entregado' &&
                                paymentStatus != 'pagado') {
                              await _showPaymentMethodSheet(orderId);
                            } else {
                              await _updateStatus(orderId, nextStatus!);
                            }
                          },
                          icon: Icon(nextIcon),
                          label: Text(
                            nextLabel,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComandaBadge({
    required IconData icon,
    required String label,
    required Color background,
    required Color border,
    required Color foreground,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComandaItem(Map<String, dynamic> item) {
    final qty = (item['quantity'] as num?) ?? 1;
    final unitPrice = (item['unit_price'] ?? 0.0).toDouble();
    final subtotal = qty.toDouble() * unitPrice;
    final rawNotes = (item['notes'] ?? '').toString().trim();
    final prod = item['products'] as Map<String, dynamic>?;
    final name = prod?['name']?.toString() ?? 'Producto';
    final category = prod?['category']?.toString() ?? '';

    final removed = <String>[];
    final extras = <String>[];
    final observations = <String>[];

    if (rawNotes.isNotEmpty) {
      for (final section in rawNotes.split(' | ')) {
        final trimmed = section.trim();
        if (trimmed.isEmpty) continue;

        if (trimmed.startsWith('SIN: ')) {
          removed.addAll(
            trimmed
                .replaceFirst('SIN: ', '')
                .split(',')
                .map((value) => value.trim())
                .where((value) => value.isNotEmpty),
          );
        } else if (trimmed.startsWith('CON EXTRA: ')) {
          extras.addAll(
            trimmed
                .replaceFirst('CON EXTRA: ', '')
                .split(',')
                .map((value) => value.trim())
                .where((value) => value.isNotEmpty),
          );
        } else {
          observations.add(trimmed);
        }
      }
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.deepOrange,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${qty}x',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (category.isNotEmpty)
                      Text(
                        category,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                Formatters.currency(subtotal),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade800,
                ),
              ),
            ],
          ),
          if (removed.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildComandaNotesSection(
              title: 'SIN',
              icon: Icons.remove_circle_outline,
              items: removed,
              background: Colors.red.shade50,
              border: Colors.red.shade200,
              foreground: Colors.red.shade800,
            ),
          ],
          if (extras.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildComandaNotesSection(
              title: 'CON / EXTRAS',
              icon: Icons.add_circle_outline,
              items: extras,
              background: Colors.green.shade50,
              border: Colors.green.shade200,
              foreground: Colors.green.shade800,
            ),
          ],
          if (observations.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.edit_note,
                    size: 18,
                    color: Colors.orange.shade900,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      observations.join(' | '),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildComandaNotesSection({
    required String title,
    required IconData icon,
    required List<String> items,
    required Color background,
    required Color border,
    required Color foreground,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: foreground),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: foreground,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: items
                .map(
                  (label) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 13, color: foreground),
                        const SizedBox(width: 4),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: foreground,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pendiente':
        return Colors.orange;
      case 'en cocina':
        return Colors.blue;
      case 'listo':
        return Colors.teal;
      case 'en camino':
        return Colors.purple;
      case 'entregado':
        return Colors.green;
      case 'cancelado':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _supabase
          .from('orders')
          .stream(primaryKey: ['id'])
          .order('id', ascending: false),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          _handleIncomingOrders(snapshot.data!);
        }

        final allOrders = snapshot.data ?? [];

        final now = DateTime.now();
        final start = DateTime(now.year, now.month, now.day);
        final end = start.add(const Duration(days: 1));
        bool createdToday(Map<String, dynamic> order) {
          final raw = order['created_at'];
          if (raw == null) return false;
          final createdAt = DateTime.tryParse(raw.toString())?.toLocal();
          return createdAt != null &&
              !createdAt.isBefore(start) &&
              createdAt.isBefore(end);
        }

        final pendientes =
            allOrders.where((o) => o['status'] == 'pendiente').toList();
        final enCocina =
            allOrders.where((o) => o['status'] == 'en cocina').toList();
        final listos =
            allOrders.where((o) => o['status'] == 'listo').toList();
        final enCamino = allOrders
            .where((o) => o['status'] == 'en camino' && createdToday(o))
            .toList();
        final historialHoy = allOrders
            .where((o) =>
                (o['status'] == 'entregado' || o['status'] == 'cancelado') &&
                createdToday(o))
            .toList();

        return Scaffold(
          appBar: AppBar(
            title: const Text("K'OTEMAL - Panel de Cocina"),
            backgroundColor: Colors.deepOrange,
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                tooltip: _soundEnabled
                    ? 'Silenciar alertas'
                    : 'Activar alertas',
                icon: Icon(
                  _soundEnabled ? Icons.volume_up : Icons.volume_off,
                ),
                onPressed: _toggleSound,
              ),
              IconButton(
                tooltip: 'Configurar alertas',
                icon: const Icon(Icons.record_voice_over),
                onPressed: _showAlertSettings,
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(
                  icon: const Icon(Icons.receipt_long),
                  text: 'Pendientes (${pendientes.length})',
                ),
                Tab(
                  icon: const Icon(Icons.soup_kitchen),
                  text: 'En Cocina (${enCocina.length})',
                ),
                Tab(
                  icon: const Icon(Icons.check_circle_outline),
                  text: 'Listos (${listos.length})',
                ),
                Tab(
                  icon: const Icon(Icons.two_wheeler),
                  text: 'En Camino (${enCamino.length})',
                ),
                Tab(
                  icon: const Icon(Icons.history),
                  text: 'Historial (${historialHoy.length})',
                ),
              ],
            ),
          ),
          body: snapshot.connectionState == ConnectionState.waiting
              ? const Center(child: CircularProgressIndicator())
              : snapshot.hasError
                  ? Center(child: Text('Error: ${snapshot.error}'))
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildOrdersList(
                          pendientes,
                          'No hay pedidos pendientes.',
                        ),
                        _buildOrdersList(
                          enCocina,
                          'No hay pedidos en cocina.',
                        ),
                        _buildOrdersList(
                          listos,
                          'No hay pedidos listos para entregar.',
                        ),
                        _buildOrdersList(
                          enCamino,
                          'No hay pedidos en camino hoy.',
                        ),
                        _buildOrdersList(
                          historialHoy,
                          'No hay pedidos en el historial de hoy.',
                        ),
                      ],
                    ),
        );
      },
    );
  }

  Widget _buildOrdersList(
    List<Map<String, dynamic>> orders,
    String emptyMessage,
  ) {
    if (orders.isEmpty) {
      return Center(
        child: Text(
          emptyMessage,
          style: const TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: orders.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _buildOrderCard(orders[index]),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final orderId = order['id'] as int;
    final status = (order['status'] ?? 'pendiente') as String;
    final total = (order['total'] ?? 0.0).toString();
    final phone = order['customer_phone'] ?? 'Sin número';
    final notes = order['delivery_notes'] ?? 'Sin referencias';
    final rawCustomerName = (order['customer_name'] ?? '').toString().trim();
    final customerName =
        rawCustomerName.isEmpty ? 'Cliente sin nombre' : rawCustomerName;
    final isGuest = order['customer_id'] == null;
    final lat = order['delivery_latitude'] as double?;
    final lng = order['delivery_longitude'] as double?;
    final deliveryType = (order['delivery_type'] ?? 'domicilio') as String;
    final tableNumber = order['table_number']?.toString() ?? '';
    final paymentStatus = (order['payment_status'] ?? 'pendiente') as String;
    final paymentMethod = order['payment_method'] as String?;
    final isPaid = paymentStatus == 'pagado';
    final paymentLabel = paymentMethod == 'efectivo'
        ? 'Efectivo'
        : paymentMethod == 'transferencia'
            ? 'Transferencia'
            : 'Sin método';

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showOrderDetailsModal(orderId, order), // Tocar la tarjeta abre el detalle de productos
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        'Orden #$orderId',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.touch_app, size: 16, color: Colors.grey),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getStatusColor(status).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _getStatusColor(status)),
                    ),
                    child: Text(
                      status.toUpperCase(),
                      style: TextStyle(
                        color: _getStatusColor(status),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(),
              Row(
                children: [
                  Icon(
                    deliveryType == 'local'
                        ? Icons.table_restaurant
                        : deliveryType == 'para_llevar'
                            ? Icons.takeout_dining
                            : Icons.delivery_dining,
                    size: 18,
                    color: Colors.deepOrange,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    deliveryType == 'local'
                        ? 'MESA: $tableNumber (Consumo en Local)'
                        : deliveryType == 'para_llevar'
                            ? 'PARA LLEVAR (Mostrador)'
                            : 'A DOMICILIO (Delivery)',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Teléfono clickeable para llamada o WhatsApp
              InkWell(
                onTap: () => _showContactOptions(phone),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.phone_in_talk, size: 16, color: Colors.blue),
                    const SizedBox(width: 6),
                    Text(
                      phone,
                      style: const TextStyle(
                        fontSize: 15,
                        color: Colors.blue,
                        decoration: TextDecoration.underline,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.chat, size: 16, color: Colors.green),
                  ],
                ),
              ),

              if (notes.isNotEmpty && notes != 'Sin referencias') ...[
                const SizedBox(height: 6),
                Text('Detalles / Referencia: $notes', style: const TextStyle(color: Colors.black87)),
              ],
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    isGuest ? Icons.person_outline : Icons.person,
                    size: 18,
                    color: isGuest ? Colors.grey : Colors.amber.shade800,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      customerName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    isGuest ? 'Cliente Invitado' : 'Cliente Registrado (Suma Puntos)',
                    style: TextStyle(
                      color: isGuest ? Colors.grey.shade700 : Colors.amber.shade900,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Total: Q$total',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    isPaid ? Icons.verified : Icons.payments_outlined,
                    size: 18,
                    color: isPaid ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      isPaid ? 'Pagado ($paymentLabel)' : 'Pago pendiente',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isPaid ? Colors.green : Colors.orange,
                      ),
                    ),
                  ),
                  if (_isAdmin && !isPaid)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.green,
                        side: const BorderSide(color: Colors.green),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () => _showPaymentMethodSheet(orderId),
                      icon: const Icon(Icons.price_check, size: 18),
                      label: const Text('Marcar Pagado'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (deliveryType == 'domicilio' && lat != null && lng != null)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => _openNavigation(lat, lng),
                      icon: const Icon(Icons.directions, size: 18),
                      label: const Text('Ruta Maps'),
                    ),
                  const Spacer(),
                  DropdownButton<String>(
                    value: status,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 'pendiente', child: Text('Pendiente')),
                      DropdownMenuItem(value: 'en cocina', child: Text('En cocina')),
                      DropdownMenuItem(value: 'listo', child: Text('Listo')),
                      DropdownMenuItem(value: 'en camino', child: Text('En camino')),
                      DropdownMenuItem(value: 'entregado', child: Text('Entregado')),
                      DropdownMenuItem(value: 'cancelado', child: Text('Cancelado')),
                    ],
                    onChanged: (val) {
                      if (val == null || val == status) return;

                      if (val == 'entregado' && paymentStatus != 'pagado') {
                        // No se permite entregar sin cobrar: primero se elige el método.
                        _showPaymentMethodSheet(orderId);
                      } else {
                        _updateStatus(orderId, val);
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
