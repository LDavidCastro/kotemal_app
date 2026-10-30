import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppUpdateInfo {
  final bool hasUpdate;
  final String currentVersion;
  final String latestVersion;
  final String? downloadUrl;
  final String? releaseNotes;

  AppUpdateInfo({
    required this.hasUpdate,
    required this.currentVersion,
    required this.latestVersion,
    this.downloadUrl,
    this.releaseNotes,
  });
}

class UpdateService {
  // Tu repositorio de GitHub
  static const String _repoOwner = 'LDavidCastro';
  static const String _repoName = 'kotemal_app';

  /// Revisa si existe una versión superior en GitHub Releases
  static Future<AppUpdateInfo> checkForUpdate() async {
    final packageInfo = await PackageInfo.fromPlatform();
    // Limpia el número de compilación (+1, +2) si viene adjunto
    final currentVersion = packageInfo.version.split('+').first.trim();

    try {
      final url = Uri.parse('https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest');
      final response = await http.get(url, headers: {
        'Accept': 'application/vnd.github.v3+json',
      });

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // Quita prefijos 'v', 'V' o build metadata
        final tagName = (data['tag_name'] as String)
            .replaceAll(RegExp(r'^[vV]'), '')
            .split('+')
            .first
            .trim();

        final body = data['body'] as String?;
        final assets = data['assets'] as List?;

        String? apkUrl;
        if (assets != null && assets.isNotEmpty) {
          final apkAsset = assets.firstWhere(
            (a) => (a['name'] as String).endsWith('.apk'),
            orElse: () => null,
          );
          if (apkAsset != null) {
            apkUrl = apkAsset['browser_download_url'] as String;
          }
        }

        final hasUpdate = _isVersionHigher(tagName, currentVersion);

        return AppUpdateInfo(
          hasUpdate: hasUpdate,
          currentVersion: currentVersion,
          latestVersion: tagName,
          downloadUrl: apkUrl,
          releaseNotes: body,
        );
      }
    } catch (_) {}

    return AppUpdateInfo(
      hasUpdate: false,
      currentVersion: currentVersion,
      latestVersion: currentVersion,
    );
  }

  /// Descarga el APK e inicia el instalador del sistema
  static Stream<OtaEvent> downloadAndInstall(String apkUrl) {
    return OtaUpdate().execute(apkUrl, destinationFilename: 'kotemal_update.apk');
  }

  /// Compara semanticamente dos versiones (ej: '1.0.1' vs '1.0.0')
  static bool _isVersionHigher(String latest, String current) {
    try {
      final cleanLatest = latest.split('+').first.trim();
      final cleanCurrent = current.split('+').first.trim();

      // Si las cadenas de versión son idénticas, no hay actualización
      if (cleanLatest == cleanCurrent) return false;

      final lParts = cleanLatest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final cParts = cleanCurrent.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      final maxLength = lParts.length > cParts.length ? lParts.length : cParts.length;

      for (int i = 0; i < maxLength; i++) {
        final l = i < lParts.length ? lParts[i] : 0;
        final c = i < cParts.length ? cParts[i] : 0;
        if (l > c) return true;
        if (l < c) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}