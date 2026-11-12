/// Signed-in account as seen by the UI.
class AppUser {
  const AppUser({required this.id, required this.email});

  final String id;
  final String? email;
}

abstract interface class AuthRepository {
  /// Emits the current user immediately, then on every sign-in / sign-out.
  Stream<AppUser?> watchUser();

  Future<AppUser> signIn({required String email, required String password});

  Future<void> signOut();

  /// True when the signed-in user is listed in `app_editors` (RPC `is_editor`).
  Future<bool> isEditor();
}
