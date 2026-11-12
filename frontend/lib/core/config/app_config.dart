import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Public client configuration.
///
/// Resolution order:
/// 1. `--dart-define` values (used by the GitHub Pages CI build), then
/// 2. `frontend/.env` (bundled asset, local development).
///
/// Only public values belong here (Supabase URL + anon key, backend URL).
class AppConfig {
  const AppConfig({required this.supabaseUrl, required this.supabaseAnonKey, required this.backendUrl});

  final String supabaseUrl;
  final String supabaseAnonKey;
  final String backendUrl;

  static const String rawCadBucket = 'raw-cad-files';
  static const String processedModelsBucket = 'processed-models';
  static const String componentDocsBucket = 'component-docs';

  static const _defineUrl = String.fromEnvironment('SUPABASE_URL');
  static const _defineAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const _defineBackendUrl = String.fromEnvironment('BACKEND_URL');

  static Future<AppConfig> load() async {
    await dotenv.load(fileName: '.env', isOptional: true);

    String resolve(String key, String defined, {String? fallback}) {
      final value = defined.isNotEmpty ? defined : (dotenv.maybeGet(key)?.trim() ?? fallback ?? '');
      if (value.isEmpty) {
        throw StateError('Missing "$key": set it in frontend/.env or pass --dart-define=$key=...');
      }
      return value;
    }

    final backend = resolve('BACKEND_URL', _defineBackendUrl, fallback: 'http://localhost:8000');
    return AppConfig(
      supabaseUrl: resolve('SUPABASE_URL', _defineUrl),
      supabaseAnonKey: resolve('SUPABASE_ANON_KEY', _defineAnonKey),
      backendUrl: backend.endsWith('/') ? backend.substring(0, backend.length - 1) : backend,
    );
  }
}
