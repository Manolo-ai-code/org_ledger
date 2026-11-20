import '../models/expense.dart';
import '../repositories/audit_repository.dart';
import '../repositories/expense_repository.dart';
import 'connectivity_service.dart';

/// Outcome of a sync attempt, suitable for display in a SnackBar.
class SyncResult {
  const SyncResult({
    required this.success,
    required this.offline,
    required this.syncedCount,
    required this.message,
  });

  final bool success;
  final bool offline;
  final int syncedCount;
  final String message;
}

/// Offline queue synchroniser.
///
/// OrgLedger keeps expenses in SQLite with `is_synced = 0`. When connectivity
/// returns, the queue is flushed. There is no remote server in this build, so
/// the flush marks records as synced locally; [pushRecord] is the single place
/// to plug in a real API call without touching UI or provider code.
class SyncService {
  SyncService({
    required ExpenseRepository expenseRepository,
    required AuditRepository auditRepository,
    required ConnectivityService connectivityService,
  })  : _expenses = expenseRepository,
        _audit = auditRepository,
        _connectivity = connectivityService;

  final ExpenseRepository _expenses;
  final AuditRepository _audit;
  final ConnectivityService _connectivity;

  /// Flushes queued expenses and records an expense-linked audit entry for each
  /// synchronized expense record.
  Future<SyncResult> syncPending({required String performedBy}) async {
    final bool online = await _connectivity.isOnline();
    if (!online) {
      return const SyncResult(
        success: false,
        offline: true,
        syncedCount: 0,
        message: 'You are offline. Your records are safely stored on this device.',
      );
    }

    final List<Expense> pending = await _expenses.getUnsyncedExpenses();
    if (pending.isEmpty) {
      return const SyncResult(
        success: true,
        offline: false,
        syncedCount: 0,
        message: 'Everything is already up to date.',
      );
    }

    try {
      // Placeholder for a real backend upload. A production implementation
      // should upload each row and only flip its flag on a 2xx response.
      final int synced = await _expenses.markAllSynced();
      final List<Expense> syncedExpenses =
          pending.take(synced > 0 ? synced : pending.length).toList();
      for (final Expense expense in syncedExpenses) {
        try {
          await _audit.logExpenseAction(
            expense: expense,
            action: 'Synchronized offline expense record',
            performedBy: performedBy,
          );
        } catch (_) {
          // Auditing must not roll back a successful sync.
        }
      }
      final int count = synced > 0 ? synced : syncedExpenses.length;
      return SyncResult(
        success: true,
        offline: false,
        syncedCount: count,
        message: 'Synced $count ${count == 1 ? 'record' : 'records'}.',
      );
    } catch (_) {
      return const SyncResult(
        success: false,
        offline: false,
        syncedCount: 0,
        message: 'Sync failed. Your records are still stored offline.',
      );
    }
  }
}
