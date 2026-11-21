import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../core/constants/app_categories.dart';
import '../core/constants/app_constants.dart';
import '../core/constants/expense_status.dart';
import '../core/utils/app_format.dart';
import '../data/database/database_helper.dart';
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
    DatabaseHelper? databaseHelper,
  })  : _expensesRepo = expenseRepository,
        _auditRepo = auditRepository,
        _sync = syncService,
        _connectivity = connectivityService,
        _pdf = pdfService,
        _db = databaseHelper;

  final ExpenseRepository _expensesRepo;
  final AuditRepository _auditRepo;
  final SyncService _sync;
  final ConnectivityService _connectivity;
  final LiquidationPdfService _pdf;
  final DatabaseHelper? _db;

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

  AppUser? _viewer;

  /// Sets the current viewer for role/member-scoped visibility.
  /// Members have read-only access to all approved expenses; officers/reviewers
  /// see all expenses for the selected event.
  void setViewer(AppUser? user) {
    final int? oldId = _viewer?.id;
    final UserRole? oldRole = _viewer?.role;
    _viewer = user;
    final bool changed = oldId != user?.id || oldRole != user?.role;
    if (changed && _expenses.isNotEmpty) {
      _expenses = _scopeForViewer(_expenses);
      _notify();
    }
  }

  List<Expense> _scopeForViewer(List<Expense> expenses) {
    final AppUser? viewer = _viewer;
    if (viewer == null) {
      return expenses;
    }
    if (viewer.role == UserRole.member) {
      return expenses
          .where((Expense expense) => expense.isApproved)
          .toList(growable: false);
    }
    return expenses;
  }

  /// Loads events, the selected event and its expenses once per session.
  Future<void> initialize({AppUser? viewer}) async {
    if (viewer != null || _viewer == null) {
      _viewer = viewer;
    }
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
  }

  Future<void> loadEvents() async {
    await _loadEventsInternal();
  }

  Future<void> _loadEventsInternal({int? preferredEventId}) async {
    final int token = ++_loadToken;
    _loading = true;
    _error = null;
    _notify();

    try {
      final List<OrgEvent> events = await _expensesRepo.getEvents();
      final int? persistedId = preferredEventId ?? await _readSelectedEventId();
      final int? desiredId = preferredEventId ?? _selectedEvent?.id ?? persistedId;
      OrgEvent? selected;
      if (desiredId != null) {
        for (final OrgEvent event in events) {
          if (event.id == desiredId) {
            selected = event;
            break;
          }
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
      _expenses = _scopeForViewer(expenses);
      _pendingSyncCount = pending;
      if (selected != null) {
        await _persistSelectedEventId(selected.id);
      }
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
  Future<void> refresh() => _loadEventsInternal();

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
      await _persistSelectedEventId(event.id);
      final List<Expense> expenses = await _expensesRepo.getExpenses(
        eventId: event.id,
      );
      final int pending = await _expensesRepo.pendingSyncCount();
      if (token != _loadToken) {
        return;
      }
      _expenses = _scopeForViewer(expenses);
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

  Future<int?> _readSelectedEventId() async {
    final DatabaseHelper? db = _db;
    if (db == null) {
      return null;
    }
    try {
      final String? stored =
          await db.getSetting(AppConstants.settingSelectedEventId);
      final int id = int.tryParse(stored?.trim() ?? '') ?? 0;
      return id > 0 ? id : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _persistSelectedEventId(int eventId) async {
    final DatabaseHelper? db = _db;
    if (db == null || eventId <= 0) {
      return;
    }
    try {
      await db.setSetting(
        AppConstants.settingSelectedEventId,
        eventId.toString(),
      );
    } catch (_) {
      // Best effort: selection still works in-memory for this session.
    }
  }

  /// Returns active and archived events for management views.
  Future<List<OrgEvent>> fetchAllEventsForManagement() async {
    try {
      return await _expensesRepo.getEvents(includeArchived: true);
    } catch (_) {
      return List<OrgEvent>.from(_events);
    }
  }

  // ---------------------------------------------------------------------------
  // Budget event management (Adviser/manager only; audited)
  // ---------------------------------------------------------------------------

  Future<LedgerActionResult> createBudgetEvent({
    required AppUser actor,
    required String title,
    required double startingBudget,
    String eventType = 'General',
    String schoolYear = '',
  }) async {
    if (!actor.isActive || !actor.role.canManageMembers) {
      return const LedgerActionResult(
        success: false,
        message: 'Only the Adviser can manage budget events.',
      );
    }
    final String cleanTitle = title.trim();
    final double budget = AppFormat.safeNumber(startingBudget);
    if (cleanTitle.length < 3) {
      return const LedgerActionResult(
        success: false,
        message: 'Enter an event name with at least 3 characters.',
      );
    }
    if (budget < 0 || !budget.isFinite) {
      return const LedgerActionResult(
        success: false,
        message: 'Enter a valid starting budget (zero or greater).',
      );
    }
    try {
      final int id = await _expensesRepo.createEvent(
        title: cleanTitle,
        startingBudget: budget,
        eventType: eventType.trim().isEmpty ? 'General' : eventType.trim(),
        schoolYear: schoolYear.trim(),
      );
      await _loadEventsInternal(preferredEventId: id);
      return LedgerActionResult(
        success: true,
        message: 'Budget event "$cleanTitle" created.',
        expenseId: id,
      );
    } catch (_) {
      return const LedgerActionResult(
        success: false,
        message: 'The budget event could not be created. Please try again.',
      );
    }
  }

  Future<LedgerActionResult> updateBudgetEvent({
    required AppUser actor,
    required OrgEvent event,
    required String title,
    required double startingBudget,
    String? eventType,
    String? schoolYear,
  }) async {
    if (!actor.isActive || !actor.role.canManageMembers) {
      return const LedgerActionResult(
        success: false,
        message: 'Only the Adviser can manage budget events.',
      );
    }
    final String cleanTitle = title.trim();
    final double budget = AppFormat.safeNumber(startingBudget);
    if (cleanTitle.length < 3) {
      return const LedgerActionResult(
        success: false,
        message: 'Enter an event name with at least 3 characters.',
      );
    }
    if (budget < 0 || !budget.isFinite) {
      return const LedgerActionResult(
        success: false,
        message: 'Enter a valid starting budget (zero or greater).',
      );
    }
    try {
      final int updated = await _expensesRepo.updateEvent(
        eventId: event.id,
        title: cleanTitle,
        startingBudget: budget,
        eventType: eventType,
        schoolYear: schoolYear,
      );
      if (updated == 0) {
        return const LedgerActionResult(
          success: false,
          message: 'The selected budget event could not be found.',
        );
      }
      
      await _loadEventsInternal(preferredEventId: event.id);
      return LedgerActionResult(
        success: true,
        message: 'Budget event updated.',
      );
    } catch (_) {
      return const LedgerActionResult(
        success: false,
        message: 'The budget event could not be updated. Please try again.',
      );
    }
  }

  Future<LedgerActionResult> setBudgetEventArchived({
    required AppUser actor,
    required OrgEvent event,
    required bool archived,
  }) async {
    if (!actor.isActive || !actor.role.canManageMembers) {
      return const LedgerActionResult(
        success: false,
        message: 'Only the Adviser can manage budget events.',
      );
    }
    try {
      final int updated = await _expensesRepo.setEventArchived(
        eventId: event.id,
        archived: archived,
      );
      if (updated == 0) {
        return const LedgerActionResult(
          success: false,
          message: 'This budget event could not be updated.',
        );
      }
      
      await _loadEventsInternal(
        preferredEventId:
            _selectedEvent?.id == event.id ? null : _selectedEvent?.id,
      );
      return LedgerActionResult(
        success: true,
        message: archived
            ? '"${event.title}" archived. Past records remain available.'
            : '"${event.title}" restored.',
      );
    } catch (_) {
      return const LedgerActionResult(
        success: false,
        message: 'The budget event could not be updated. Please try again.',
      );
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

  /// Amount spent beyond the starting budget (approved only). Zero when within budget.
  double get overspentAmount {
    if (totalBudget <= 0) return 0;
    final double over = totalSpent - totalBudget;
    return over > 0 ? over : 0;
  }

  /// Remaining budget after adding [amount] to current approved spend.
  /// Uses approved-only spend as baseline (in-flight items do not affect budget).
  double projectedRemaining(double amount) =>
      totalBudget - (totalSpent + AppFormat.safeNumber(amount));

  bool wouldExceedBudget(double amount) {
    if (totalBudget <= 0) return false;
    return AppFormat.safeNumber(amount) > (remainingBudget);
  }

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
    if (!user.isActive || !user.role.canSubmitExpenses) {
      return const LedgerActionResult(
        success: false,
        message:
            'Members have read-only access. Only authenticated officers can add expenses.',
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
      await _tryExpenseAudit(
        expense.copyWith(id: id),
        action: 'Submitted expense for review',
        performedBy: '${user.name} · ${user.role.label}',
        status: ExpenseStatus.pending,
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
        auditAction = targetStatus == ExpenseStatus.adviserApproved
            ? 'Approved and locked expense'
            : 'Approved expense and advanced to ${ExpenseStatus.label(targetStatus)}';
        break;
      case ReviewAction.reject:
        if (cleanRemarks.length < 5) {
          return const LedgerActionResult(
            success: false,
            message: 'A rejection reason is required (at least 5 characters).',
          );
        }
        targetStatus = ExpenseStatus.rejected;
        auditAction = 'Rejected expense';
        break;
      case ReviewAction.flag:
        if (cleanRemarks.length < 5) {
          return const LedgerActionResult(
            success: false,
            message: 'A flag reason is required (at least 5 characters).',
          );
        }
        targetStatus = ExpenseStatus.flagged;
        auditAction = 'Flagged expense';
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

      final Expense reviewedExpense = expense.copyWith(
        status: targetStatus,
        remarks: cleanRemarks,
        isSynced: false,
        updatedAt: DateTime.now(),
      );
      await _tryExpenseAudit(
        reviewedExpense,
        action: auditAction,
        performedBy: '$actorName · ${role.label}',
        status: targetStatus,
        remarks: cleanRemarks,
      );
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
        for (final Expense expense in approved) {
          await _tryExpenseAudit(
            expense,
            action: 'Included in liquidation report export',
            performedBy: preparedBy,
            status: expense.status,
            remarks: 'Liquidation report for "${event.title}"',
          );
        }
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
    _viewer = null;
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
        final List<Expense> expenses = await _expensesRepo.getExpenses(
          eventId: event.id,
        );
        _expenses = _scopeForViewer(expenses);
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

  /// Best-effort, expense-only audit entry. Non-expense events are never logged.
  Future<void> _tryExpenseAudit(
    Expense expense, {
    required String action,
    required String performedBy,
    String? status,
    String? remarks,
  }) async {
    try {
      await _auditRepo.logExpenseAction(
        expense: expense,
        action: action,
        performedBy: performedBy,
        status: status,
        remarks: remarks,
      );
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