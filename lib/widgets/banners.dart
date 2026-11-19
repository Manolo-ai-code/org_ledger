import 'package:material_ui/material_ui.dart';

import '../core/theme/app_colors.dart';

/// Inline error panel with an optional retry callback.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({
    super.key,
    required this.message,
    this.onRetry,
    this.retryLabel = 'Retry',
  });

  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.error_outline_rounded,
            color: theme.colorScheme.error,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
          if (onRetry != null) ...<Widget>[
            const SizedBox(width: 8),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
                minimumSize: const Size(40, 32),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(retryLabel),
            ),
          ],
        ],
      ),
    );
  }
}

/// Compact offline / pending-sync banner used at the top of ledger screens.
class SyncBanner extends StatelessWidget {
  const SyncBanner({
    super.key,
    required this.isOnline,
    required this.pendingCount,
    required this.isSyncing,
    this.onSync,
  });

  final bool isOnline;
  final int pendingCount;
  final bool isSyncing;
  final Future<void> Function()? onSync;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (isOnline && pendingCount == 0 && !isSyncing) {
      return const SizedBox.shrink();
    }

    final bool offline = !isOnline;
    final Color accent = offline ? AppColors.warning : AppColors.emerald;
    final String message;
    if (isSyncing) {
      message = 'Synchronizing offline records…';
    } else if (offline) {
      message = pendingCount > 0
          ? 'Offline · $pendingCount ${pendingCount == 1 ? 'record' : 'records'} saved on this device'
          : 'Offline · changes are saved on this device';
    } else {
      message = '$pendingCount ${pendingCount == 1 ? 'record is' : 'records are'} waiting to sync';
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: theme.brightness == Brightness.dark ? 0.16 : 0.09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: <Widget>[
          if (isSyncing)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: accent,
              ),
            )
          else
            Icon(
              offline ? Icons.cloud_off_rounded : Icons.sync_rounded,
              size: 18,
              color: accent,
            ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (!isSyncing && isOnline && pendingCount > 0 && onSync != null)
            TextButton(
              onPressed: () {
                onSync?.call();
              },
              style: TextButton.styleFrom(
                foregroundColor: accent,
                minimumSize: const Size(40, 32),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('Sync'),
            ),
        ],
      ),
    );
  }
}
