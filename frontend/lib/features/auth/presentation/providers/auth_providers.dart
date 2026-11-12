import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/core_providers.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../domain/repositories/auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepositoryImpl(supabase: ref.watch(supabaseClientProvider));
});

final currentUserProvider = StreamProvider<AppUser?>((ref) {
  return ref.watch(authRepositoryProvider).watchUser();
});

/// Whether the current visitor may modify data. Anonymous visitors and signed-in
/// accounts that are not in `app_editors` get a read-only UI (RLS enforces it too).
final canEditProvider = FutureProvider<bool>((ref) async {
  final user = await ref.watch(currentUserProvider.future);
  if (user == null) return false;
  return ref.watch(authRepositoryProvider).isEditor();
});

/// Synchronous convenience for widgets: false while loading or on error.
final isEditorProvider = Provider<bool>((ref) => ref.watch(canEditProvider).value ?? false);
