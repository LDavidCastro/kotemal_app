import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';
import '../services/update_service.dart';

class AppUpdateCard extends StatefulWidget {
  const AppUpdateCard({super.key});

  @override
  State<AppUpdateCard> createState() => _AppUpdateCardState();
}

class _AppUpdateCardState extends State<AppUpdateCard> {
  bool _isChecking = false;
  AppUpdateInfo? _updateInfo;
  String? _downloadProgress;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() => _isChecking = true);
    final info = await UpdateService.checkForUpdate();
    if (mounted) {
      setState(() {
        _updateInfo = info;
        _isChecking = false;
      });
    }
  }

  void _startUpdate(String apkUrl) {
    try {
      UpdateService.downloadAndInstall(apkUrl).listen((OtaEvent event) {
        setState(() {
          if (event.status == OtaStatus.DOWNLOADING) {
            _downloadProgress = 'Descargando actualización: ${event.value}%';
          } else if (event.status == OtaStatus.INSTALLING) {
            _downloadProgress = 'Abriendo instalador del sistema...';
          } else {
            _downloadProgress = null;
          }
        });
      }, onError: (e) {
        setState(() => _downloadProgress = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al descargar actualización: $e')),
        );
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo iniciar la descarga: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.system_update, color: Colors.deepOrange),
                const SizedBox(width: 8),
                const Text(
                  'Versión del Sistema',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_isChecking)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    tooltip: 'Buscar actualizaciones',
                    onPressed: _check,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Versión actual: v${_updateInfo?.currentVersion ?? '1.0.0'}',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
            ),
            const SizedBox(height: 10),

            if (_downloadProgress != null) ...[
              LinearProgressIndicator(color: Colors.deepOrange, backgroundColor: Colors.orange.shade100),
              const SizedBox(height: 6),
              Text(_downloadProgress!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ] else if (_updateInfo != null && _updateInfo!.hasUpdate && _updateInfo!.downloadUrl != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '¡Nueva versión v${_updateInfo!.latestVersion} disponible!',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade900),
                    ),
                    if (_updateInfo!.releaseNotes != null && _updateInfo!.releaseNotes!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(_updateInfo!.releaseNotes!, style: const TextStyle(fontSize: 12)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.download),
                  label: const Text('Descargar e Instalar Actualización'),
                  onPressed: () => _startUpdate(_updateInfo!.downloadUrl!),
                ),
              ),
            ] else if (!_isChecking) ...[
              const Text(
                '✓ Cuentas con la versión más reciente.',
                style: TextStyle(color: Colors.green, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
      ),
    );
  }
}