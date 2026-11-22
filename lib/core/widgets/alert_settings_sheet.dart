import 'package:flutter/material.dart';
import '../services/order_alert_service.dart';

Future<void> showAlertSettingsSheet(BuildContext context) async {
  final service = OrderAlertService.instance;
  await service.init();
  if (!context.mounted) return;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const AlertSettingsSheet(),
  );
}

class AlertSettingsSheet extends StatelessWidget {
  const AlertSettingsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final service = OrderAlertService.instance;

    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.90,
          decoration: const BoxDecoration(
            color: Colors.white,
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
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Activar / Silenciar alertas',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        service.soundEnabled
                            ? 'Las alertas de nuevos pedidos están activas.'
                            : 'Las alertas de nuevos pedidos están silenciadas.',
                        style: const TextStyle(fontSize: 12),
                      ),
                      value: service.soundEnabled,
                      activeThumbColor: Colors.deepOrange,
                      onChanged: (_) => service.toggleSound(),
                    ),
                    const Divider(height: 20),

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
                    _ModeOption(
                      icon: Icons.notifications_active,
                      title: 'Tono + Voz',
                      subtitle:
                          'Suena el tono elegido y anuncia los detalles por voz.',
                      selected: service.alertMode == 'ambos',
                      onTap: () => service.setAlertMode('ambos'),
                    ),
                    _ModeOption(
                      icon: Icons.record_voice_over,
                      title: 'Solo Voz',
                      subtitle:
                          'Anuncia el pedido por voz sin reproducir tono.',
                      selected: service.alertMode == 'voz',
                      onTap: () => service.setAlertMode('voz'),
                    ),
                    _ModeOption(
                      icon: Icons.volume_up,
                      title: 'Solo Tono',
                      subtitle: 'Reproduce únicamente el tono del sistema.',
                      selected: service.alertMode == 'tono',
                      onTap: () => service.setAlertMode('tono'),
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
                          '${service.availableRingtones.length} disponibles',
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
                        'Actual: ${service.selectedRingtoneTitle} (toca para escuchar y elegir)',
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
                      child: service.availableRingtones.isEmpty
                          ? const Center(
                              child: Text(
                                'No se detectaron tonos en el dispositivo.',
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              itemCount: service.availableRingtones.length,
                              separatorBuilder: (_, _) => Divider(
                                height: 1,
                                color: Colors.grey.shade200,
                              ),
                              itemBuilder: (context, i) {
                                final tone = service.availableRingtones[i];
                                final uri = tone['uri'];
                                final title = tone['title'] ?? 'Tono';
                                final isSelected =
                                    (service.selectedRingtoneUri == uri &&
                                            (uri != null && uri.isNotEmpty)) ||
                                        (service.selectedRingtoneTitle ==
                                            title);

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
                                  onTap: () => service.previewRingtone(uri),
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
                          '${service.availableVoices.length} disponibles',
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
                        'Voz activa: ${service.selectedVoiceName ?? 'Predeterminada'} (toca para probar)',
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
                      child: service.availableVoices.isEmpty
                          ? const Center(
                              child: Text(
                                'No se detectaron voces en español.',
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              itemCount: service.availableVoices.length,
                              separatorBuilder: (_, _) => Divider(
                                height: 1,
                                color: Colors.grey.shade200,
                              ),
                              itemBuilder: (context, i) {
                                final voice = service.availableVoices[i];
                                final name = voice['name'] ?? '';
                                final label = voice['label'] ?? name;
                                final isSelected = name.toLowerCase() ==
                                    service.selectedVoiceName?.toLowerCase();

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
                                  onTap: () => service.previewVoice(voice),
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
                  border: Border(top: BorderSide(color: Colors.grey.shade200)),
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
                      onPressed: () => service.announceCustom(
                        message:
                            'Nuevo pedido, orden 101, a nombre de Juan Pérez, para mesa 4',
                        ignoreMute: true,
                      ),
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
    );
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
              color: selected ? Colors.deepOrange : Colors.grey.shade700,
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
}
