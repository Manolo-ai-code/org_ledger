/// The complete expense lifecycle.
///
/// Normal flow:
/// Pending → Treasurer_Verified → Auditor_Checked → President_Endorsed →
/// Adviser_Approved.
///
/// Rejected and Flagged are terminal states that always carry a mandatory
/// remark so the submitter knows exactly what needs fixing.
abstract final class ExpenseStatus {
  static const String pending = 'Pending';
  static const String treasurerVerified = 'Treasurer_Verified';
  static const String auditorChecked = 'Auditor_Checked';
  static const String presidentEndorsed = 'President_Endorsed';
  static const String adviserApproved = 'Adviser_Approved';
  static const String rejected = 'Rejected';
  static const String flagged = 'Flagged';

  /// The ordered happy-path chain.
  static const List<String> approvalChain = <String>[
    pending,
    treasurerVerified,
    auditorChecked,
    presidentEndorsed,
    adviserApproved,
  ];

  /// Statuses that are awaiting somebody's action.
  static const List<String> inFlight = <String>[
    pending,
    treasurerVerified,
    auditorChecked,
    presidentEndorsed,
  ];

  static const List<String> terminal = <String>[
    adviserApproved,
    rejected,
    flagged,
  ];

  /// Every value that may legally be written to the database.
  static const List<String> all = <String>[
    pending,
    treasurerVerified,
    auditorChecked,
    presidentEndorsed,
    adviserApproved,
    rejected,
    flagged,
  ];

  /// Normalises a value read from SQLite.
  ///
  /// Unknown, null or empty values fall back to [pending] rather than throwing.
  static String normalise(String? value) {
    final String candidate = value?.trim() ?? '';
    for (final String status in all) {
      if (status.toLowerCase() == candidate.toLowerCase()) {
        return status;
      }
    }
    return pending;
  }

  static bool isApproved(String? status) =>
      normalise(status) == adviserApproved;

  static bool isRejected(String? status) => normalise(status) == rejected;

  static bool isFlagged(String? status) => normalise(status) == flagged;

  static bool isInFlight(String? status) => inFlight.contains(normalise(status));

  static bool isTerminal(String? status) => terminal.contains(normalise(status));

  /// Human friendly label, e.g. `Treasurer_Verified` → `Treasurer verified`.
  static String label(String? status) {
    switch (normalise(status)) {
      case treasurerVerified:
        return 'Treasurer verified';
      case auditorChecked:
        return 'Auditor checked';
      case presidentEndorsed:
        return 'President endorsed';
      case adviserApproved:
        return 'Adviser approved';
      case rejected:
        return 'Rejected';
      case flagged:
        return 'Flagged';
      case pending:
      default:
        return 'Pending';
    }
  }

  /// The next status in the chain, or `null` for terminal/unknown statuses.
  static String? next(String? status) {
    final int index = approvalChain.indexOf(normalise(status));
    if (index < 0 || index >= approvalChain.length - 1) {
      return null;
    }
    return approvalChain[index + 1];
  }

  /// 1-based position in the five-step approval chain (0 for rejected/flagged).
  static int step(String? status) {
    final int index = approvalChain.indexOf(normalise(status));
    return index < 0 ? 0 : index + 1;
  }
}
