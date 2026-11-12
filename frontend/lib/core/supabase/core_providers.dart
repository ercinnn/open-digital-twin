import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import '../network/backend_api_client.dart';

/// Overridden in `main.dart` with the loaded configuration.
final appConfigProvider = Provider<AppConfig>(
  (ref) => throw UnimplementedError('appConfigProvider must be overridden in main()'),
);

final supabaseClientProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

final backendApiClientProvider = Provider<BackendApiClient>((ref) {
  final client = BackendApiClient(baseUrl: ref.watch(appConfigProvider).backendUrl);
  ref.onDispose(client.close);
  return client;
});
