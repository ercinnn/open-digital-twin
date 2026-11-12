import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/repositories/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({required this.supabase});

  final SupabaseClient supabase;

  AppUser? _map(User? user) => user == null ? null : AppUser(id: user.id, email: user.email);

  @override
  Stream<AppUser?> watchUser() async* {
    yield _map(supabase.auth.currentUser);
    yield* supabase.auth.onAuthStateChange.map((state) => _map(state.session?.user));
  }

  @override
  Future<AppUser> signIn({required String email, required String password}) async {
    final response = await supabase.auth.signInWithPassword(email: email.trim(), password: password);
    final user = _map(response.user);
    if (user == null) throw const AuthException('Sign-in failed.');
    return user;
  }

  @override
  Future<void> signOut() => supabase.auth.signOut();

  @override
  Future<bool> isEditor() async {
    if (supabase.auth.currentUser == null) return false;
    final result = await supabase.rpc<dynamic>('is_editor');
    return result == true;
  }
}
