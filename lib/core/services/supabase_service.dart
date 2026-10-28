import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/api_constants.dart';

abstract final class SupabaseService {
  static bool get isConfigured =>
      ApiConstants.supabaseUrl.isNotEmpty &&
      ApiConstants.supabasePublishableKey.isNotEmpty;

  static Future<void> initialize() async {
    if (!isConfigured) {
      throw StateError(
        'Supabase no está configurado. Ejecuta la app con '
        '--dart-define=SUPABASE_URL=<url> '
        '--dart-define=SUPABASE_PUBLISHABLE_KEY=<publishable-key>.',
      );
    }

    await Supabase.initialize(
      url: ApiConstants.supabaseUrl,
      publishableKey: ApiConstants.supabasePublishableKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;

  static User? get currentUser => client.auth.currentUser;

  static Session? get currentSession => client.auth.currentSession;
}
