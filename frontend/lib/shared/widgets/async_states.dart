import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5)),
          if (label != null) ...[
            const SizedBox(height: 12),
            Text(label!, style: const TextStyle(color: AppTheme.textMuted)),
          ],
        ],
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFF87171), size: 36),
            const SizedBox(height: 12),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textMuted),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: AppTheme.textMuted),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card with a title row used by the inspector sections.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.child, this.icon, this.trailing});

  final String title;
  final IconData? icon;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (icon != null) ...[Icon(icon, size: 16, color: AppTheme.accent), const SizedBox(width: 8)],
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11.5,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}
