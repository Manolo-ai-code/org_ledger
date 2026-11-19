import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../core/constants/app_categories.dart';
import '../core/constants/expense_status.dart';
import '../core/utils/app_format.dart';
import '../data/models/app_user.dart';
import '../data/models/expense.dart';
import '../data/models/org_event.dart';
import '../data/models/user_role.dart';
import '../data/repositories/audit_repository.dart';
import '../data/repositories/expense_repository.dart';
import '../data/services/connectivity_service.dart';
import '../data/services/liquidation_pdf_service.dart';
import '../data/services/sync_service.dart';

/// Reviewer actions available on an expense.
enum ReviewAction { approve, reject, flag }

/// Lightweight result object for provider operations.
class LedgerActionResult {
  const LedgerActionResult({
    required this.success,
    required this.message,
    this.expenseId,
  });

  final bool success;
  final String message;
  final int? expenseId;
}

/// A point on the budget burn-down line chart.
class BurnDownPoint {
  const BurnDownPoint({
    required this.index,
    required this.date,
    required this.remaining,
    required this.label,
  });

  final int index;
  final DateTime date;
  final double remaining;
  final String label;
}

/// The live ledger: events, expenses, derived metrics, reviews and sync.
///
/// Invariant: only expenses with status `Adviser_Approved` contribute to
/// `totalSpent`, `budgetUsage`, category charts and the PDF export. Pending,
/// flagged and rejected entries never touch the official burn-down.
class LedgerProvider extends ChangeNotifier {
  LedgerProvider({
    required ExpenseRepository expenseRepository,
    required AuditRepository auditRepository,
    required SyncService syncService,
    required ConnectivityService connectivityService,
    required LiquidationPdfService pdfService,
  })  : _expensesRepo = expenseRepository,
        _auditRepo = auditRepository,
        _sync = syncService,
        _connectivity = connectivityService,
        _pdf = pdfService;

  final ExpenseRepository _expensesRepo;
  final AuditRepository _auditRepo;
  final SyncService _sync;
  final ConnectivityService _connectivity;
  final LiquidationPdfService _pdf;

  List<OrgEvent> _events = <OrgEvent>[];
  OrgEvent? _selectedEvent;
  List<Expense> _expenses = <Expense>[];
  bool _loading = false;
  bool _initialized = false;
  bool _syncing = false;
  bool _online = true;
  bool _disposed = false;
  int _pendingSyncCount = 0;
  int _loadToken = 0;
  DateTime? _lastSyncAt;
  String? _error;
  StreamSubscription<bool>? _connectivitySub;

  List<OrgEvent> get events => List<OrgEvent>.unmodifiable(_events);
  OrgEvent? get selectedEvent => _selectedEvent;
  List<Expense> get expenses => List<Expense>.unmodifiable(_expenses);
  bool get isLoading => _loading;
  bool get isInitialized => _initialized;
  bool get isSyncing => _syncing;
  bool get isOnline => _online;
  int get pendingSyncCount => _pendingSyncCount;
  DateTime? get lastSyncAt => _lastSyncAt;
  String? get error => _error;

  /// Loads events, the selected event and its expenses once per session.
  Future<void> initialize() async {
    if (_initialized) {
      await refresh();
      return;
    }
    _initialized = true;
    await _listenToConnectivity();
    await loadEvents();
  }

  Future<void> _listenToConnectivity() async {
    try {
      _online = await _connectivity.isOnline();
    } catch (_) {
      _online = true;
    }
    final StreamSubscription<bool>? previousSub = _connectivitySub;
    _connectivitySub = null;
    if (previousSub != null) {
      try {
        await previousSub.cancel();
      } catch (_) {
        // A broken connectivity channel must not block ledger loading.
      }
    }
    try {
      _connectivitySub = _connectivity.onStatusChange.listen(
        (bool online) {
          final bool cameBackOnline = online && !_online;
          _online = online;
          _notify();
          if (cameBackOnline && _pendingSyncCount > 0 && !_syncing) {
            unawaited(syncPending(performedBy: 'System · auto-sync'));
          }
        },
        onError: (Object _) {
          // Connectivity reporting is advisory; keep using local records.
        },
      );
    } catch (_) {
      // Some platforms (or tests) have no connectivity channel. The ledger is
      // offline-first, so treating the device as online is a safe fallback.
      _connectivitySub = null;
      _online = true;
    }
    _notify();
  }

  Future<void> loadEvents() async {
    final int token = ++_loadToken;
    _loading = true;
    _error = null;
    _notify();

    try {
      final List<OrgEvent> events = await _expensesRepo.getEvents();
      final int? previousId = _selectedEvent?.id;
      OrgEvent? selected;
      for (final OrgEvent event in events) {
        if (event.id == previousId) {
          selected = event;
          break;
        }
      }
      selected ??= events.isNotEmpty ? events.first : null;
      final List<Expense> expenses = selected == null
          ? <Expense>[]
          : await _expensesRepo.getExpenses(eventId: selected.id);
      final int pending = await _expensesRepo.pendingSyncCount();

      if (token != _loadToken) {
        return;
      }
      _events = events;
      _selectedEvent = selected;
      _expenses = expenses;
      _pendingSyncCount = pending;
    } catch (_) {
      if (token == _loadToken) {
        _error =
            'We could not open the local ledger. Pull down to try again.';
      }
    } finally {
      if (token == _loadToken) {
        _loading = false;
        _notify();
      }
    }
  }

  /// Pull-to-refresh entry point.
  Future<void> refresh() => loadEvents();

  Future<void> selectEvent(OrgEvent event) async {
    if (_selectedEvent?.id == event.id) {
      return;
    }
    final int token = ++_loadToken;
    _selectedEvent = event;
    _loading = true;
    _error = null;
    _notify();

    try {
      final List<Expense> expenses = await _expensesRepo.getExpenses(
        eventId: event.id,
      );
      final int pending = await _expensesRepo.pendingSyncCount();
      if (token != _loadToken) {
        return;
      }
      _expenses = expenses;
      _pendingSyncCount = pending;
    } catch (_) {
      if (token == _loadToken) {
        _error = 'Could not load expenses for ${event.title}.';
      }
    } finally {
      if (token == _loadToken) {
        _loading = false;
        _notify();
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Derived financial metrics (approved-only)
  // ---------------------------------------------------------------------------

  List<Expense> get approvedExpenses {
    final List<Expense> approved = _expenses
        .where((Expense expense) => expense.isApproved)
        .toList();
    approved.sort(
      (Expense a, Expense b) => a.createdAt.compareTo(b.createdAt),
    );
    return approved;
  }

  List<Expense> get latestExpenses => _expenses.take(5).toList(growable: false);

  double get totalBudget => _selectedEvent?.startingBudget ?? 0;

  /// Official spend. Only fully approved items are counted.
  double get totalSpent {
    double total = 0;
    for (final Expense expense in _expenses) {
      if (expense.isApproved) {
        total += AppFormat.safeNumber(expense.amount);
      }
    }
    return total;
  }

  double get remainingBudget => totalBudget - totalSpent;

  /// Clamped 0..1 ratio used by progress indicators.
  double get budgetUsage => AppFormat.clampRatio(totalSpent, totalBudget);

  /// Raw ratio for labels; can exceed 1 when overspent.
  double get budgetUsageRaw => AppFormat.ratio(totalSpent, totalBudget);

  bool get isOverBudget => totalSpent > totalBudget && totalBudget > 0;

  bool get isNearBudgetLimit => budgetUsageRaw >= 0.8;

  /// Every item still moving through the pipeline.
  int get pendingApprovalsCount =>
      _expenses.where((Expense expense) => expense.isInFlight).length;

  /// Literal `Pending` count, shown as a secondary detail.
  int get pendingOnlyCount =>
      _expenses.where((Expense expense) => expense.isPending).length;

  int get flaggedCount =>
      _expenses.where((Expense expense) => expense.isFlagged).length;

  int get rejectedCount =>
      _expenses.where((Expense expense) => expense.isRejected).length;

  /// Expenses awaiting the signed-in officer's exact tier.
  int awaitingMyReviewCount(UserRole role) {
    final String? status = role.reviewableStatus;
    if (status == null) {
      return 0;
    }
    return _expenses.where((Expense expense) => expense.status == status).length;
  }

  List<Expense> expensesForRole(UserRole role) {
    final String? status = role.reviewableStatus;
    if (status == null) {
      return const <Expense>[];
    }
    return _expenses
        .where((Expense expense) => expense.status == status)
        .toList(growable: false);
  }

  /// Approved spending grouped by displayed category, largest first.
  Map<String, double> get categoryTotals {
    final Map<String, double> totals = <String, double>{};
    for (final Expense expense in _expenses) {
      if (!expense.isApproved) {
        continue;
      }
      final String key = expense.displayCategory;
      totals.update(
        key,
        (double value) => value + AppFormat.safeNumber(expense.amount),
        ifAbsent: () => AppFormat.safeNumber(expense.amount),
      );
    }
    final List<MapEntry<String, double>> entries = totals.entries.toList()
      ..sort(
        (MapEntry<String, double> a, MapEntry<String, double> b) =>
            b.value.compareTo(a.value),
      );
    return <String, double>{
      for (final MapEntry<String, double> entry in entries)
        entry.key: entry.value,
    };
  }

  /// Remaining balance after each approved expense, for the burn-down line.
  List<BurnDownPoint> get burnDownPoints {
    final double budget = AppFormat.safeNumber(totalBudget);
    final List<Expense> approved = approvedExpenses;
    final DateTime now = DateTime.now();

    if (approved.isEmpty) {
      return <BurnDownPoint>[
        BurnDownPoint(
          index: 0,
          date: now.subtract(const Duration(days: 7)),
          remaining: budget,
          label: 'Start',
        ),
        BurnDownPoint(
          index: 1,
          date: now,
          remaining: budget,
          label: 'Now',
        ),
      ];
    }

    final List<BurnDownPoint> points = <BurnDownPoint>[
      BurnDownPoint(
        index: 0,
        date: approved.first.createdAt,
        remaining: budget,
        label: 'Start',
      ),
    ];
    double remaining = budget;
    for (int i = 0; i < approved.length; i++) {
      remaining -= AppFormat.safeNumber(approved[i].amount);
      points.add(
        BurnDownPoint(
          index: i + 1,
          date: approved[i].createdAt,
          remaining: remaining,
          label: AppFormat.shortDate(approved[i].createdAt),
        ),
      );
    }
    return points;
  }

  // ---------------------------------------------------------------------------
  // Mutations
  // ---------------------------------------------------------------------------

  Future<LedgerActionResult> submitExpense({
    required AppUser user,
    required String title,
    required double amount,
    required String category,
    String customCategory = '',
    String receiptImagePath = '',
  }) async {
    if (!user.role.canSubmitExpenses) {
      return LedgerActionResult(
        success: false,
        message:
            '${user.role.label} accounts cannot submit expenses. Ask the Business Manager or Secretary.',
      );
    }

    final OrgEvent? event = _selectedEvent;
    if (event == null || event.id <= 0) {
      return const LedgerActionResult(
        success: false,
        message: 'Select an event before adding an expense.',
      );
    }

    final String cleanTitle = title.trim();
    final double cleanAmount = AppFormat.safeNumber(amount);
    final String cleanCategory =
        AppCategories.normalise(category.trim());
    final String cleanCustom = customCategory.trim();

    if (cleanTitle.length < 3) {
      return const LedgerActionResult(
        success: false,
        message: 'Please describe the expense in at least 3 characters.',
      );
    }
    if (cleanAmount <= 0) {
      return const LedgerActionResult(
        success: false,
        message: 'Enter an amount greater than zero.',
      );
    }
    if (!AppCategories.isValid(cleanCategory)) {
      return const LedgerActionResult(
        success: false,
        message: 'Choose a valid category.',
      );
    }
    if (cleanCategory == AppCategories.others && cleanCustom.isEmpty) {
      return const LedgerActionResult(
        success: false,
        message: 'Please name the custom category.',
      );
    }

    final DateTime now = DateTime.now();
    final Expense expense = Expense(
      id: 0,
      eventId: event.id,
      title: cleanTitle,
      amount: cleanAmount,
      category: cleanCategory,
      customCategory:
          cleanCategory == AppCategories.others ? cleanCustom : '',
      receiptImagePath: receiptImagePath.trim(),
      status: ExpenseStatus.pending,
      submittedBy: user.id,
      remarks: '',
      isSynced: false,
      createdAt: now,
      updatedAt: now,
      submittedByName: user.name,
      eventTitle: event.title,
    );

    try {
      final int id = await _expensesRepo.insertExpense(expense);
      await _tryAudit(
        'Submitted "$cleanTitle" for review',
        '${user.name} · ${user.role.label}',
      );
      await _refreshAfterMutation();
      return LedgerActionResult(
        success: true,
        message: _online
            ? 'Expense submitted for Treasurer verification.'
            : 'Saved offline. It will sync when you are back online.',
        expenseId: id,
      );
    } catch (_) {
      return const LedgerActionResult(
        success: false,
        message: 'The expense could not be saved. Please try again.',
      );
    }
  }

  Future<LedgerActionResult> reviewExpense({
    required Expense expense,
    required UserRole role,
    required String actorName,
    required ReviewAction action,
    String remarks = '',
  }) async {
    final String? expected = role.reviewableStatus;
    if (expected == null) {
      return const LedgerActionResult(
        success: false,
        message: 'Your role does not participate in the approval chain.',
      );
    }
    if (expense.status != expected) {
      return const LedgerActionResult(
        success: false,
        message: 'This expense is no longer awaiting your review.',
      );
    }

    final String cleanRemarks = remarks.trim();
    String targetStatus;
    String auditAction;

    switch (action) {
      case ReviewAction.approve:
        final String? next = ExpenseStatus.next(expense.status);
        if (next == null) {
          return const LedgerActionResult(
            success: false,
            message: 'This expense cannot advance any further.',
          );
        }
        targetStatus = next;
        auditAction = 'Approved "${expense.title}" · '
            '${ExpenseStatus.label(next)}';
        break;
      case ReviewAction.reject:
        if (cleanRemarks.length < 5) {
          return const LedgerActionResult(
            success: false,
            message: 'A rejection reason is required (at least 5 characters).',
          );
        }
        targetStatus = ExpenseStatus.rejected;
        auditAction = 'Rejected "${expense.title}": $cleanRemarks';
        break;
      case ReviewAction.flag:
        if (cleanRemarks.length < 5) {
          return const LedgerActionResult(
            success: false,
            message: 'A flag reason is required (at least 5 characters).',
          );
        }
        targetStatus = ExpenseStatus.flagged;
        auditAction = 'Flagged "${expense.title}": $cleanRemarks';
        break;
    }

    try {
      final int updated = await _expensesRepo.updateStatus(
        expenseId: expense.id,
        status: targetStatus,
        remarks: cleanRemarks,
        isSynced: false,
        expectedStatus: expense.status,
      );
      if (updated == 0) {
        return const LedgerActionResult(
          success: false,
          message:
              'This expense is no longer awaiting your review. Refresh and try again.',
        );
      }

      await _tryAudit(auditAction, '$actorName · ${role.label}');
      await _refreshAfterMutation();

      final String message;
      switch (action) {
        case ReviewAction.approve:
          message = targetStatus == ExpenseStatus.adviserApproved
              ? 'Final approval granted. The expense is now locked.'
              : 'Approved and forwarded to ${ExpenseStatus.label(targetStatus)}.';
          break;
        case ReviewAction.reject:
          message = 'Expense rejected. Your remark is visible to the submitter.';
          break;
        case ReviewAction.flag:
          message = 'Expense flagged. Your remark is visible to the submitter.';
          break;
      }
      return LedgerActionResult(success: true, message: message);
    } catch (_) {
      return const LedgerActionResult(
        success: false,
        message: 'The review could not be saved. Please try again.',
      );
    }
  }

  Future<LedgerActionResult> syncPending({
    String performedBy = 'System',
  }) async {
    if (_syncing) {
      return const LedgerActionResult(
        success: false,
        message: 'A sync is already in progress.',
      );
    }
    _syncing = true;
    _error = null;
    _notify();

    try {
      final SyncResult result = await _sync.syncPending(
        performedBy: performedBy,
      );
      if (result.offline) {
        _online = false;
      } else if (result.success) {
        _online = true;
        _lastSyncAt = DateTime.now();
      }
      await _refreshPendingCount();
      return LedgerActionResult(
        success: result.success,
        message: result.message,
      );
    } catch (_) {
      return const LedgerActionResult(
        success: false,
        message: 'Sync failed. Your records remain stored offline.',
      );
    } finally {
      _syncing = false;
      _notify();
    }
  }

  Future<LedgerActionResult> exportLiquidation({
    required String preparedBy,
  }) async {
    final OrgEvent? event = _selectedEvent;
    if (event == null) {
      return const LedgerActionResult(
        success: false,
        message: 'Select an event before exporting a report.',
      );
    }
    final List<Expense> approved = approvedExpenses;
    if (approved.isEmpty) {
      return const LedgerActionResult(
        success: false,
        message: 'No approved expenses to export yet.',
      );
    }

    try {
      final bool shared = await _pdf.shareReport(
        event: event,
        expenses: approved,
        preparedBy: preparedBy,
      );
      if (shared) {
        await _tryAudit(
          'Exported liquidation PDF for "${event.title}" '
          '(${approved.length} approved items)',
          preparedBy,
        );
      }
      return LedgerActionResult(
        success: true,
        message: shared
            ? 'Liquidation report generated.'
            : 'Export closed without sharing.',
      );
    } catch (error) {
      return LedgerActionResult(
        success: false,
        message: error is PdfExportException
            ? error.message
            : 'Could not export the report. Please try again.',
      );
    }
  }

  /// Clears transient state when the user signs out.
  Future<void> reset() async {
    await _connectivitySub?.cancel();
    _connectivitySub = null;
    _loadToken++;
    _initialized = false;
    _events = <OrgEvent>[];
    _selectedEvent = null;
    _expenses = <Expense>[];
    _loading = false;
    _syncing = false;
    _online = true;
    _pendingSyncCount = 0;
    _lastSyncAt = null;
    _error = null;
    _notify();
  }

  void clearError() {
    if (_error == null) {
      return;
    }
    _error = null;
    _notify();
  }

  Future<void> _refreshAfterMutation() async {
    final OrgEvent? event = _selectedEvent;
    try {
      if (event != null) {
        _expenses = await _expensesRepo.getExpenses(eventId: event.id);
      }
      _pendingSyncCount = await _expensesRepo.pendingSyncCount();
    } catch (_) {
      _error = 'Saved, but the ledger list could not refresh. Pull to refresh.';
    }
  }

  Future<void> _refreshPendingCount() async {
    try {
      _pendingSyncCount = await _expensesRepo.pendingSyncCount();
    } catch (_) {
      // Keep the previous count; the sync result still reports success.
    }
  }

  Future<void> _tryAudit(String action, String actor) async {
    try {
      await _auditRepo.log(action: action, performedBy: actor);
    } catch (_) {
      // The primary action already succeeded; auditing is best effort.
    }
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    final StreamSubscription<bool>? sub = _connectivitySub;
    _connectivitySub = null;
    if (sub != null) {
      try {
        unawaited(sub.cancel());
      } catch (_) {
        // Connectivity reporting is advisory; disposal must never throw.
      }
    }
    super.dispose();
  }
}
