import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Public client configuration loaded from `frontend/.env` (bundled asset).
///
/// Only public values belong here (Supabase URL + anon key, backend URL).
class AppConfig {
  const AppConfig({
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    required this.backendUrl,
  });

  final String supabaseUrl;
  final String supabaseAnonKey;
  final String backendUrl;

  static const String rawCadBucket = 'raw-cad-files';
  static const String processedModelsBucket = 'processed-models';
  static const String componentDocsBucket = 'component-docs';

  static Future<AppConfig> load() async {
    await dotenv.load(fileName: '.env');
    String require(String key) {
      final value = dotenv.maybeGet(key)?.trim() ?? '';
      if (value.isEmpty) {
        throw StateError('Missing "$key" in frontend/.env');
      }
      return value;
    }

    final backend = dotenv.maybeGet('BACKEND_URL', fallback: 'http://localhost:8000')!.trim();
    return AppConfig(
      supabaseUrl: require('SUPABASE_URL'),
      supabaseAnonKey: require('SUPABASE_ANON_KEY'),
      backendUrl: backend.endsWith('/') ? backend.substring(0, backend.length - 1) : backend,
    );
  }
}
