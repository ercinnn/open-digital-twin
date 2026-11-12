import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/app_theme.dart';
import '../providers/auth_providers.dart';

/// App-bar control: "Sign in" for visitors, account menu for signed-in users.
class AccountButton extends ConsumerWidget {
  const AccountButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    final canEdit = ref.watch(isEditorProvider);

    if (user == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: OutlinedButton.icon(
          onPressed: () => showDialog<void>(context: context, builder: (_) => const SignInDialog()),
          icon: const Icon(Icons.login, size: 18),
          label: const Text('Sign in'),
        ),
      );
    }

    return PopupMenuButton<String>(
      tooltip: user.email ?? 'Account',
      onSelected: (value) async {
        if (value == 'signout') await ref.read(authRepositoryProvider).signOut();
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          enabled: false,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(user.email ?? 'Signed in'),
            subtitle: Text(canEdit ? 'Editor' : 'Read-only account'),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'signout',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout),
            title: Text('Sign out'),
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              canEdit ? Icons.edit_note : Icons.visibility_outlined,
              size: 18,
              color: canEdit ? AppTheme.accent : AppTheme.textMuted,
            ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(user.email ?? 'Account', overflow: TextOverflow.ellipsis),
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}

/// Small badge shown to visitors so it is obvious why editing controls are disabled.
class ReadOnlyBadge extends ConsumerWidget {
  const ReadOnlyBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(isEditorProvider)) return const SizedBox.shrink();
    return const Tooltip(
      message: 'Sign in with an editor account to change statuses, upload files or run simulations.',
      child: Chip(
        visualDensity: VisualDensity.compact,
        avatar: Icon(Icons.visibility_outlined, size: 16),
        label: Text('Read-only'),
      ),
    );
  }
}

class SignInDialog extends ConsumerStatefulWidget {
  const SignInDialog({super.key});

  @override
  ConsumerState<SignInDialog> createState() => _SignInDialogState();
}

class _SignInDialogState extends ConsumerState<SignInDialog> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).signIn(email: _email.text, password: _password.text);
      final canEdit = await ref.read(authRepositoryProvider).isEditor();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            canEdit ? 'Signed in – editing enabled.' : 'Signed in, but this account has no editor rights (read-only).',
          ),
        ),
      );
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editor sign in'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: AutofillGroup(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Visitors can view every twin. Editing requires an editor account.',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _email,
                  autofocus: true,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  obscureText: _obscure,
                  autofillHints: const [AutofillHints.password],
                  decoration: InputDecoration(
                    labelText: 'Password',
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
                  onFieldSubmitted: (_) => _submit(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Color(0xFFF87171))),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Sign in'),
        ),
      ],
    );
  }
}
